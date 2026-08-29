//
//  BundleManifest.swift
//
//  The signed manifest a build ships beside its bundled cartridges.
//
//  # What this replaces, and why
//
//  Bundled cartridges — the ones shipped inside a build's own
//  `bundled-cartridges/` tree — have no upstream registry to verify against, so
//  they need their own integrity proof. That proof used to be a content hash
//  baked into the build, and it was DISABLED on macOS: the distribution step
//  re-signs every cartridge when it seals the `.app`, which rewrites their
//  bytes long after the build recorded them, so a baked hash could not survive.
//  macOS was left trusting Gatekeeper instead.
//
//  That made Apple's signature the load-bearing check on one platform and ours
//  the load-bearing check on the others. It is the wrong way round: Apple's
//  signature is what stops the operating system warning a user; OUR chain is
//  what decides whether code runs, and it has to say the same thing everywhere.
//
//  So the proof is a signed manifest — `bundle.json` with a `bundle.json.sig`
//  envelope beside it — produced at the END of a build, after every platform
//  signing step. There is no ordering problem left to have.
//
//  # What this file does and does not do
//
//  It reads and applies a manifest. It does NOT verify the signature: this
//  mirror carries no chain verification (`release_cert.rs` in the Rust library
//  is the only implementation of it), and a mirror that stubbed one would be
//  worse than a mirror that has none. The caller supplies a `BundleProof`, and
//  the only way to get a proven one is to have proven it.
//

import Foundation

/// The `format` every bundle manifest carries. A manifest without exactly this
/// is refused rather than interpreted.
public let bundleManifestFormat = "capdag.bundle/v1"

/// The manifest's name inside the bundled-cartridges root.
public let bundleManifestFile = "bundle.json"

/// The signature envelope's name, beside the manifest.
public let bundleManifestSigFile = "bundle.json.sig"

/// One cartridge a build ships.
public struct BundledCartridge: Codable, Equatable {
    public let name: String
    public let version: String
    /// `release` or `nightly`. Stated so a manifest cannot vouch for a
    /// cartridge from the other channel.
    public let channel: String
    /// The directory hash, as `hashCartridgeDirectory` computes it — sorted
    /// relative paths and file contents, `cartridge.json` excluded. That
    /// exclusion is what lets a build write the manifest without changing what
    /// the manifest attests.
    public let sha256: String

    public init(name: String, version: String, channel: String, sha256: String) {
        self.name = name
        self.version = version
        self.channel = channel
        self.sha256 = sha256
    }
}

/// What a build ships beside its executable.
public struct BundleManifest: Codable, Equatable {
    public let format: String
    /// The signing environment this bundle was built for.
    public let environment: String
    public let cartridges: [BundledCartridge]

    /// A manifest in a stable order, so the same tree produces the same bytes
    /// and therefore the same signature.
    public init(environment: String, cartridges: [BundledCartridge]) {
        self.format = bundleManifestFormat
        self.environment = environment
        self.cartridges = cartridges.sorted {
            $0.name == $1.name ? $0.version < $1.version : $0.name < $1.name
        }
    }

    /// What this manifest says about one cartridge, if it says anything.
    public func entry(name: String, version: String) -> BundledCartridge? {
        cartridges.first { $0.name == name && $0.version == version }
    }
}

/// What a discovery run knows about the bundle it is scanning.
///
/// Carried rather than looked up. Verification is one act per discovery — a
/// chain check per cartridge would do the same work repeatedly and give as many
/// chances to disagree — and making it a value means the thing that LOADS a
/// manifest and the thing that USES one are separable.
public enum BundleProof {
    /// The manifest this root's bundled cartridges are held to.
    ///
    /// Only a caller that has verified the manifest's signature may construct
    /// this. This module cannot: it carries no chain verification, and
    /// stubbing one would turn a refusal into a pass.
    case proven(BundleManifest)
    /// Nothing here can vouch for a bundled cartridge, and why.
    ///
    /// Not an absence: every `installed_from: bundle` cartridge under this root
    /// is refused with this reason. A root that legitimately ships none — the
    /// operator's installed-cartridges directory — carries a reason saying so,
    /// and if a bundled cartridge ever turns up there it is refused for exactly
    /// the right reason rather than quietly hosted.
    case none(String)

    /// Hold one bundled cartridge to what this proof allows. `nil` when it
    /// passes, the reason when it does not.
    public func check(name: String, version: String, versionDir: String) -> String? {
        switch self {
        case .none(let reason):
            return reason.isEmpty
                ? "nothing proves the bundled cartridges under this root"
                : reason
        case .proven(let manifest):
            guard let entry = manifest.entry(name: name, version: version) else {
                return "the bundle manifest does not list \(name) \(version); "
                    + "this build ships a cartridge it did not record"
            }
            let actual: String
            do {
                actual = try hashCartridgeDirectory(versionDir)
            } catch {
                return "failed to hash bundled cartridge directory: \(error)"
            }
            if actual != entry.sha256 {
                return "\(name) \(version) does not match the bundle manifest: "
                    + "recorded \(entry.sha256), on disk \(actual)"
            }
            return nil
        }
    }
}

/// Where the manifest and its signature live under a bundled-cartridges root.
public func bundleManifestPaths(_ bundledRoot: String) -> (manifest: String, signature: String) {
    let root = bundledRoot as NSString
    return (
        root.appendingPathComponent(bundleManifestFile),
        root.appendingPathComponent(bundleManifestSigFile)
    )
}

/// Whether a name in a bundled-cartridges root belongs to this mechanism.
///
/// Discovery reports unmanaged files in that directory; these two are managed,
/// and a warning about them on every startup would train an operator to ignore
/// the one that matters.
public func isBundleManifestFile(_ fileName: String) -> Bool {
    fileName == bundleManifestFile || fileName == bundleManifestSigFile
}

/// What went wrong reading a bundle manifest.
public enum BundleManifestError: Error, CustomStringConvertible {
    case missing(String)
    case unsigned(String)
    case malformed(path: String, reason: String)
    case unsupportedFormat(String)

    public var description: String {
        switch self {
        case .missing(let path):
            return "no bundle manifest at \(path) — this build shipped cartridges it cannot vouch for"
        case .unsigned(let path):
            return "no signature at \(path) — an unsigned bundle manifest proves nothing"
        case .malformed(let path, let reason):
            return "\(path) is not a bundle manifest: \(reason)"
        case .unsupportedFormat(let found):
            return "bundle manifest has format '\(found)' (expected '\(bundleManifestFormat)')"
        }
    }
}

/// Read and shape-check the manifest under a bundled-cartridges root, with the
/// exact bytes it was read from and the envelope beside it.
///
/// Does NOT verify the signature — the caller does that with a chain verifier
/// this mirror does not have, and only then builds `.proven`. The signature
/// file's presence IS checked: an unsigned manifest proves nothing, and
/// reporting that here means a caller cannot forget to look.
public func readBundleManifest(
    _ bundledRoot: String
) throws -> (manifest: BundleManifest, bytes: Data, envelope: String) {
    let (manifestPath, sigPath) = bundleManifestPaths(bundledRoot)
    guard let bytes = FileManager.default.contents(atPath: manifestPath) else {
        throw BundleManifestError.missing(manifestPath)
    }
    guard let envelopeData = FileManager.default.contents(atPath: sigPath),
          let envelope = String(data: envelopeData, encoding: .utf8)
    else {
        throw BundleManifestError.unsigned(sigPath)
    }
    let manifest: BundleManifest
    do {
        manifest = try JSONDecoder().decode(BundleManifest.self, from: bytes)
    } catch {
        throw BundleManifestError.malformed(path: manifestPath, reason: "\(error)")
    }
    guard manifest.format == bundleManifestFormat else {
        throw BundleManifestError.unsupportedFormat(manifest.format)
    }
    return (manifest, bytes, envelope)
}
