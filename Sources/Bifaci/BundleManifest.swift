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
//  # What a host learns from it, and when it checks the bytes
//
//  Each entry records, under the signature, everything discovery decides from:
//  the cartridge's directory hash, the fabric manifest version it was built
//  against, and the cap groups it advertises in its HELLO (recorded by the
//  build, which starts each cartridge once to ask). So discovering a bundle
//  reads one signed file: it neither hashes a cartridge nor starts one, and a
//  command that lists or plans pays for no cartridge it does not run.
//
//  The bytes are checked when they matter, which is when a host starts a
//  cartridge: its directory is hashed and held to the recorded value each time
//  it is spawned, and a cartridge that was changed is refused there, by name
//  (`verifyBundledContent`). Checking at the spawn rather than at discovery
//  also closes the gap between the two, during which a checked cartridge could
//  be replaced before it ran.
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
import CapDAG

/// The `format` every bundle manifest carries. A manifest without exactly this
/// is refused rather than interpreted: the shape is the contract between the
/// build that writes it and the runtime that reads it.
public let bundleManifestFormat = "capdag.bundle/v2"

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
    /// The fabric manifest version the cartridge was built against.
    ///
    /// Its `cartridge.json` states it too, but that file is outside the hash;
    /// recorded here it is signed, and a host pinned to another version
    /// refuses the cartridge without starting it.
    public let fabricManifestVersion: UInt32
    /// The cap groups the cartridge advertises in its HELLO, as the build read
    /// them by starting it. Discovery takes them from here instead of starting
    /// every bundled cartridge to ask again; they are a function of the bytes
    /// `sha256` covers, which are checked before the cartridge runs.
    public let capGroups: [CapGroup]

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case channel
        case sha256
        case fabricManifestVersion = "fabric_manifest_version"
        case capGroups = "cap_groups"
    }

    public init(
        name: String,
        version: String,
        channel: String,
        sha256: String,
        fabricManifestVersion: UInt32,
        capGroups: [CapGroup]
    ) {
        self.name = name
        self.version = version
        self.channel = channel
        self.sha256 = sha256
        self.fabricManifestVersion = fabricManifestVersion
        self.capGroups = capGroups
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

    /// The entry for one bundled cartridge, held to the channel it is on.
    ///
    /// Unlisted, or listed at another version, is a cartridge the build did
    /// not record — a stale copy left from an earlier build among them. Listed
    /// for the other channel is a manifest vouching for an artefact it did not
    /// describe.
    public func admit(name: String, version: String, channel: String) throws -> BundledCartridge {
        guard let entry = entry(name: name, version: version) else {
            throw BundleManifestError.notListed(name: name, version: version)
        }
        guard entry.channel == channel else {
            throw BundleManifestError.wrongChannel(
                name: name, version: version, recorded: entry.channel, found: channel
            )
        }
        return entry
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

    /// What this proof records about one bundled cartridge, which discovery
    /// takes its caps and its fabric manifest version from.
    ///
    /// Reads nothing on disk. The cartridge's bytes are held to the recorded
    /// hash when a host starts it (`verifyBundledContent`), not here. Throws a
    /// `BundleManifestError` saying why the cartridge is not admitted.
    public func admit(name: String, version: String, channel: String) throws -> BundledCartridge {
        switch self {
        case .none(let reason):
            throw BundleManifestError.unproven(reason)
        case .proven(let manifest):
            return try manifest.admit(name: name, version: version, channel: channel)
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

/// What went wrong reading a bundle manifest, or holding a bundled cartridge
/// to one.
public enum BundleManifestError: Error, CustomStringConvertible, LocalizedError {
    case missing(String)
    case unsigned(String)
    case unreadable(path: String, reason: String)
    case malformed(path: String, reason: String)
    case unsupportedFormat(String)
    /// Nothing proves the bundled cartridges under this root (`BundleProof.none`),
    /// for the reason given.
    case unproven(String)
    case notListed(name: String, version: String)
    case wrongChannel(name: String, version: String, recorded: String, found: String)
    case contentMismatch(dir: String, name: String, version: String, expected: String, actual: String)

    public var description: String {
        switch self {
        case .missing(let path):
            return "no bundle manifest at \(path) — this build shipped cartridges it cannot vouch for"
        case .unsigned(let path):
            return "no signature at \(path) — an unsigned bundle manifest proves nothing"
        case .unreadable(let path, let reason):
            return "cannot read \(path): \(reason)"
        case .malformed(let path, let reason):
            return "\(path) is not a bundle manifest: \(reason)"
        case .unsupportedFormat(let found):
            return "bundle manifest has format '\(found)' (expected '\(bundleManifestFormat)')"
        case .unproven(let reason):
            return reason.isEmpty
                ? "nothing proves the bundled cartridges under this root"
                : reason
        case .notListed(let name, let version):
            return "the bundle manifest does not list \(name) \(version); "
                + "this build ships a cartridge it did not record"
        case .wrongChannel(let name, let version, let recorded, let found):
            return "the bundle manifest records \(name) \(version) for the '\(recorded)' channel, "
                + "and this cartridge is on the '\(found)' channel"
        case .contentMismatch(let dir, let name, let version, let expected, let actual):
            return "the bundled cartridge \(name) \(version) was changed after its build recorded it, "
                + "so it is not started: its directory \(dir) hashes to \(actual), and the build's "
                + "signed bundle manifest records \(expected). Reinstall the application it is bundled with"
        }
    }

    public var errorDescription: String? { description }
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
    let manifest = try parseBundleManifest(bytes, path: manifestPath)
    return (manifest, bytes, envelope)
}

/// The format field alone, read before the document is.
private struct BundleManifestFormatField: Decodable {
    let format: String
}

/// The document a manifest's bytes hold, held to this format and to the cap
/// definition rules.
///
/// The format is read first and on its own, so a manifest in another format
/// is refused for being one, rather than as a document that fails to parse.
/// No earlier format is read: a v1 manifest records no caps and no fabric
/// manifest version, so a host reading one would have to start every cartridge
/// to learn them, which is what v2 exists to stop.
func parseBundleManifest(_ bytes: Data, path: String) throws -> BundleManifest {
    let format: String
    do {
        format = try JSONDecoder().decode(BundleManifestFormatField.self, from: bytes).format
    } catch {
        throw BundleManifestError.malformed(path: path, reason: "\(error)")
    }
    guard format == bundleManifestFormat else {
        throw BundleManifestError.unsupportedFormat(format)
    }
    let manifest: BundleManifest
    do {
        manifest = try JSONDecoder().decode(BundleManifest.self, from: bytes)
    } catch {
        throw BundleManifestError.malformed(path: path, reason: "\(error)")
    }
    // The recorded caps cross from the cartridge that advertised them to every
    // host that reads them here, so they are held to the definition rules as
    // an advertised manifest is (`advertisedManifest`). The rules are the cap
    // library's (`CSCapValidator`); what is held to them is the groups exactly
    // as this host will route by them.
    for cartridge in manifest.cartridges {
        if let ruleError = capGroupsRuleError(cartridge.capGroups) {
            throw BundleManifestError.malformed(
                path: path,
                reason: "\(cartridge.name) \(cartridge.version): \(ruleError)"
            )
        }
    }
    return manifest
}

/// The definition rule a group's caps break, or why the groups are no cap
/// groups the cap library reads; nil when every cap keeps the rules.
private func capGroupsRuleError(_ groups: [CapGroup]) -> String? {
    for group in groups {
        let dictionary: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(group))
            guard let decoded = object as? [String: Any] else {
                return "cap group '\(group.name)' does not encode as a JSON object"
            }
            dictionary = decoded
        } catch {
            return "cap group '\(group.name)' does not encode: \(error)"
        }
        let parsed: CSCapGroup
        do {
            parsed = try CSCapGroup(dictionary: dictionary)
        } catch {
            return "cap group '\(group.name)' is not a cap group: \(error.localizedDescription)"
        }
        for cap in parsed.caps {
            do {
                try CSCapValidator.validateCapDefinition(cap)
            } catch {
                return "invalid cap definition: \(error.localizedDescription)"
            }
        }
    }
    return nil
}

/// Hold a bundled cartridge's directory to the hash its build recorded.
///
/// A host calls this each time it starts a bundled cartridge, which is the
/// moment the bytes are about to run. Throws `.contentMismatch` naming the
/// cartridge and its directory when the bytes changed, and `.unreadable` when
/// the directory cannot be hashed.
public func verifyBundledContent(name: String, version: String, versionDir: String, recorded: String) throws {
    let actual: String
    do {
        actual = try hashCartridgeDirectory(versionDir)
    } catch {
        throw BundleManifestError.unreadable(path: versionDir, reason: "\(error)")
    }
    guard actual == recorded else {
        throw BundleManifestError.contentMismatch(
            dir: versionDir, name: name, version: version, expected: recorded, actual: actual
        )
    }
}
