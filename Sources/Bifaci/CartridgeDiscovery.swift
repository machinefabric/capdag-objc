//
//  CartridgeDiscovery.swift
//  Bifaci
//
//  Shared cartridge discovery: the on-disk scan + identity validation +
//  HELLO probe that classifies each installed cartridge version directory as
//  attachable (`directory`) or `incompatible`. A bundled cartridge is not
//  probed: its build's signed bundle manifest records what the probe would
//  learn, and its bytes are held to that manifest when a host starts it.
//  Mirrors `capdag/src/cartridge_discovery.rs`.
//
//  Managed layout (relative to the root passed to `discoverCartridges`):
//  `{root}/{slug}/{channel}/{name}/{version}/cartridge.json`.
//

import Foundation
import CapDAG

// MARK: - Identity

/// The identity a host accepts cartridges for. A cartridge whose
/// `cartridge.json` diverges from this on channel, registry URL, registry
/// scheme, or fabric manifest version is surfaced as `incompatible` — never
/// hosted.
public struct DiscoveryIdentity {
    public let channel: CartridgeChannel
    /// `Some(url)` for release/nightly hosts, `nil` for dev hosts (cartridges
    /// then live under the reserved dev slug).
    public let registryURL: String?
    public let fabricManifestVersion: UInt32
    /// Cartridge registry regime version this host speaks — an on-disk PATH
    /// level: cartridges live under `{slug}/v{cartridgeRegistryVersion}/
    /// {channel}/…`, pinned like the channel so a v1 host never scans a v2 tree.
    public let cartridgeRegistryVersion: UInt32
    /// What proves the bundled cartridges under the root being scanned.
    ///
    /// Carried rather than looked up, because verification is one act per
    /// discovery and because the caller is the only thing that knows what this
    /// root IS: a build's own bundled-cartridges tree carries a verified
    /// manifest, and the operator's installed-cartridges directory carries
    /// `.none` — so a cartridge claiming to be bundled while sitting there is
    /// refused for exactly that reason instead of being hosted because nobody
    /// asked.
    public let bundle: BundleProof

    public init(
        channel: CartridgeChannel,
        registryURL: String?,
        fabricManifestVersion: UInt32,
        cartridgeRegistryVersion: UInt32,
        bundle: BundleProof
    ) {
        self.channel = channel
        self.registryURL = registryURL
        self.fabricManifestVersion = fabricManifestVersion
        self.cartridgeRegistryVersion = cartridgeRegistryVersion
        self.bundle = bundle
    }
}

// MARK: - Discovered classification

/// A discovered cartridge version directory, classified.
///
/// - `directory` — passed every identity check, and its caps are known: from
///   its HELLO probe, or, for a bundled cartridge, from its build's signed
///   bundle manifest. `bundleSHA256` is, for a bundled cartridge, the
///   directory hash that manifest records, and `nil` for an installed or dev
///   one. Discovery does not hash a bundled cartridge: a host holds its
///   directory to this value each time it starts the cartridge
///   (`verifyBundledContent`), and refuses to start one that was changed.
/// - `incompatible` — found on disk but failed a check. NOT spawned; surfaced
///   with a structured attachment error so the UI can render the reason.
public enum DiscoveredCartridge {
    case directory(
        entryPoint: String,
        versionDir: String,
        id: String,
        channel: CartridgeChannel,
        registryURL: String?,
        version: String,
        capGroups: [CapGroup],
        bundleSHA256: String?
    )
    case incompatible(
        versionDir: String,
        id: String,
        channel: CartridgeChannel,
        registryURL: String?,
        version: String,
        error: CartridgeAttachmentError
    )
}

// MARK: - Errors

/// A real I/O failure reading an existing scan root. Distinct from an
/// absent/empty root (which is an empty roster, not an error).
public enum CartridgeDiscoveryError: Error, CustomStringConvertible {
    case readDirFailed(path: String, underlying: String)

    public var description: String {
        switch self {
        case .readDirFailed(let path, let underlying):
            return "read_dir(\(path)): \(underlying)"
        }
    }
}

/// Current wall-clock time as Unix seconds, for stamping attachment errors.
private func unixSecondsNow() -> Int64 {
    Int64(Date().timeIntervalSince1970)
}

// MARK: - The attach rule

/// What a host holds a cartridge to before it attaches it, from what the
/// cartridge's `cartridge.json` says: the part of a host's identity that
/// `admission(_:terms:)` reads.
public struct AttachTerms {
    public let channel: CartridgeChannel
    public let fabricManifestVersion: UInt32
    /// What proves a cartridge that says it was bundled; see
    /// `DiscoveryIdentity.bundle`.
    public let bundle: BundleProof

    public init(channel: CartridgeChannel, fabricManifestVersion: UInt32, bundle: BundleProof) {
        self.channel = channel
        self.fabricManifestVersion = fabricManifestVersion
        self.bundle = bundle
    }
}

extension DiscoveryIdentity {
    /// The terms this host attaches cartridges on.
    public var attachTerms: AttachTerms {
        AttachTerms(channel: channel, fabricManifestVersion: fabricManifestVersion, bundle: bundle)
    }
}

/// Why a host does not attach a cartridge.
public struct Refusal: Error, Equatable {
    public let kind: CartridgeAttachmentErrorKind
    public let message: String

    public init(kind: CartridgeAttachmentErrorKind, message: String) {
        self.kind = kind
        self.message = message
    }

    /// The refusal as the attachment error a roster carries.
    public func at(_ detectedAtUnixSeconds: Int64) -> CartridgeAttachmentError {
        CartridgeAttachmentError(kind: kind, message: message, detectedAtUnixSeconds: detectedAtUnixSeconds)
    }
}

/// How a host attaches a cartridge it does not refuse.
public enum Admission {
    /// Nothing vouches for its caps: the host learns them by starting it.
    case probe
    /// A bundled cartridge, attached as its build's signed bundle manifest
    /// records it: its caps are the recorded ones, and a host holds its
    /// directory to the recorded hash each time it starts it
    /// (`verifyBundledContent`).
    case bundled(BundledCartridge)
}

/// Whether, and how, a cartridge whose `cartridge.json` reads as `cj` is
/// attached under `terms`; the refusal when it is not.
///
/// The one rule every host decides by: discovery's roster and a run that
/// attaches the installed cartridge a cap needs both call it, so a cartridge
/// one of them refuses is never run by the other. It reads nothing on disk.
public func admission(_ cj: CartridgeJson, terms: AttachTerms) -> Result<Admission, Refusal> {
    if cj.channel != terms.channel {
        return .failure(Refusal(
            kind: .misplaced,
            message: "Channel mismatch: cartridge declares '\(cj.channel.asString)' but host is pinned to '\(terms.channel.asString)'. Release and nightly artefacts must not mix."
        ))
    }

    // NO registry pin: the host's baked registry does NOT restrict which
    // registries' cartridges are attached. Whether a version is actually
    // LISTED upstream is the verdict layer's call.

    let bundled = cj.installedFrom == .bundle
    if cj.fabricManifestVersion != terms.fabricManifestVersion {
        let ours = terms.fabricManifestVersion
        // What to do differs by where the cartridge came from, told as every
        // host tells it: `installed_from: bundle` is the one provenance with
        // meaning, and otherwise a registryURL is a registry install and none
        // a dev cartridge.
        let remedy: String
        if bundled {
            remedy = "The build that bundled it is inconsistent: its bundle holds a cartridge for another fabric manifest."
        } else if cj.registryURL != nil {
            remedy = "Remove it and install it again from its registry."
        } else {
            remedy = "Rebuild it with MFR_FABRIC_MANIFEST_VERSION=\(ours) and install it again."
        }
        return .failure(Refusal(
            kind: .fabricManifestVersionMismatch,
            message: "\(cj.name) \(cj.version) was installed for fabric manifest \(cj.fabricManifestVersion), and this host reads fabric manifest \(ours). \(remedy)"
        ))
    }

    // A bundled cartridge. A cartridge marked `installed_from: bundle` is
    // shipped INSIDE this build, not user-installed, and has no upstream
    // registry to verify against — so it needs its own proof.
    //
    // ONE mechanism, on every platform: the build's signed bundle manifest.
    // The proof was established when this host started (see `BundleProof`);
    // here it is applied to the cartridge in hand. Apple's signature still
    // matters, and it is what stops the operating system warning a user; it
    // is not what decides whether code runs here.
    //
    // The manifest records what a probe would learn — the caps the cartridge
    // advertises, and the fabric manifest version it was built for — so the
    // cartridge is attached from that record without being started or hashed.
    if bundled {
        let recorded: BundledCartridge
        do {
            recorded = try terms.bundle.admit(name: cj.name, version: cj.version, channel: cj.channel.asString)
        } catch {
            return .failure(Refusal(kind: .misplaced, message: "bundled cartridge integrity check failed: \(error)"))
        }
        // cartridge.json is outside the hash, so what it says of the fabric
        // was checked above only as far as it goes: the signed record is what
        // is believed.
        if recorded.fabricManifestVersion != terms.fabricManifestVersion {
            return .failure(Refusal(
                kind: .fabricManifestVersionMismatch,
                message: "\(cj.name) \(cj.version) was built for fabric manifest \(recorded.fabricManifestVersion), as its build's signed bundle manifest records, and this host reads fabric manifest \(terms.fabricManifestVersion). The build that bundled it is inconsistent: its bundle holds a cartridge for another fabric manifest."
            ))
        }
        return .success(.bundled(recorded))
    }

    return .success(.probe)
}

/// Order two cartridge version strings by their dotted numeric parts; a
/// missing part counts as 0 and a part that is not a number is skipped. The
/// one order cartridge versions have, as every capdag library gives it.
func compareCartridgeVersions(_ a: String, _ b: String) -> ComparisonResult {
    let partsA = a.split(separator: ".").compactMap { UInt32($0) }
    let partsB = b.split(separator: ".").compactMap { UInt32($0) }
    for i in 0..<max(partsA.count, partsB.count) {
        let numA = i < partsA.count ? partsA[i] : 0
        let numB = i < partsB.count ? partsB[i] : 0
        if numA != numB {
            return numA < numB ? .orderedAscending : .orderedDescending
        }
    }
    return .orderedSame
}

/// The newest of a cartridge's installed version directories, by their
/// names, in the order the registry gives versions: dotted numbers compared
/// as numbers, so `1.174.0` is newer than `1.99.0`. Every host attaches this
/// one and only this one, so what a roster shows for a cartridge is what a
/// run uses. `nil` for no directories.
public func newestVersionDir(_ versionDirs: [String]) -> String? {
    versionDirs.max {
        compareCartridgeVersions(($0 as NSString).lastPathComponent, ($1 as NSString).lastPathComponent) == .orderedAscending
    }
}

// MARK: - Probe

/// Probe a cartridge binary for its capability surface.
///
/// Spawns the binary, performs the bifaci HELLO handshake, parses the
/// manifest, returns its full `cap_groups`, then kills the process. A binary
/// that fails to spawn, fails HELLO, or returns an unparseable manifest is an
/// error — the caller surfaces it as `handshakeFailed`.
@available(macOS 10.15.4, iOS 13.4, *)
public func probeCartridgeCapGroups(path: String) throws -> [CapGroup] {
    // Through the launcher, because a dev cartridge's entry may be a script.
    // See `Launch`.
    let process = Launch.process(path)

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    // Inherit stderr (matches the reference's Stdio::inherit).

    do {
        try process.run()
    } catch {
        throw CartridgeDiscoveryError.readDirFailed(path: path, underlying: "Failed to spawn cartridge \(path): \(error)")
    }

    let reader = FrameReader(handle: stdoutPipe.fileHandleForReading)
    let writer = FrameWriter(handle: stdinPipe.fileHandleForWriting)

    defer {
        if process.isRunning {
            process.terminate()
        }
    }

    let result: HandshakeResult
    do {
        result = try performHandshakeWithManifest(reader: reader, writer: writer)
    } catch {
        throw CartridgeDiscoveryError.readDirFailed(path: path, underlying: "cartridge \(path) HELLO failed: \(error)")
    }

    let manifestData = result.manifest

    do {
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        return manifest.capGroups
    } catch {
        let preview = String(data: manifestData.prefix(500), encoding: .utf8) ?? "<non-utf8>"
        throw CartridgeDiscoveryError.readDirFailed(path: path, underlying: "cartridge \(path) invalid manifest (\(error)): \(preview)")
    }
}

// MARK: - Discovery

/// Discover every cartridge under `{cartridgesRoot}/{slug}/{channel}/`. Each
/// cartridge name directory's newest version is validated against `identity`
/// and probed — or, when bundled, admitted from the build's signed bundle
/// manifest without being started; the result is the full classified roster.
/// An empty/absent scan root is not an error — it yields an empty roster. A
/// real I/O failure reading an existing scan root IS an error.
@available(macOS 10.15.4, iOS 13.4, *)
public func discoverCartridges(_ cartridgesRoot: String, identity: DiscoveryIdentity) throws -> [DiscoveredCartridge] {
    var discovered: [DiscoveredCartridge] = []
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: cartridgesRoot, isDirectory: &isDir), isDir.boolValue else {
        return discovered
    }

    // Scan EVERY registry folder present on disk — full macOS parity. The
    // host's baked registry does NOT restrict which folders are scanned; each
    // cartridge is validated in place against the registry folder it sits
    // under, as the charter stored there names it. The channel folder IS
    // still pinned to the host's channel.
    let slugNames: [String]
    do {
        slugNames = try fm.contentsOfDirectory(atPath: cartridgesRoot)
    } catch {
        throw CartridgeDiscoveryError.readDirFailed(path: cartridgesRoot, underlying: "\(error)")
    }

    for slugName in slugNames.sorted() {
        let slugDir = (cartridgesRoot as NSString).appendingPathComponent(slugName)
        var slugIsDir: ObjCBool = false
        guard fm.fileExists(atPath: slugDir, isDirectory: &slugIsDir), slugIsDir.boolValue else {
            continue
        }
        // The folder is what its stored charter names, never what its own name
        // says. A folder whose charter is missing or refused still has its
        // cartridges surfaced — each as misplaced, with the reason — so the
        // operator sees what is there and why none of it runs.
        let folder: Result<RegistryFolder, Error>
        do {
            folder = .success(try RegistryFolder.open(slugDir))
        } catch {
            folder = .failure(error)
        }
        // {slug}/v{cartridgeRegistryVersion}/{channel}/… — the registry regime
        // version is a path level pinned to the host's version (like channel).
        let versionDir = (slugDir as NSString).appendingPathComponent("v\(identity.cartridgeRegistryVersion)")
        let scanRoot = (versionDir as NSString).appendingPathComponent(identity.channel.asString)
        var scanIsDir: ObjCBool = false
        guard fm.fileExists(atPath: scanRoot, isDirectory: &scanIsDir), scanIsDir.boolValue else {
            // This slug has no subtree for the host's (version, channel) — skip.
            continue
        }
        try scanChannelRoot(scanRoot: scanRoot, slugDir: slugDir, folder: folder, identity: identity, discovered: &discovered)
    }

    return discovered
}

/// Scan one `{slug}/{channel}/` root: classify each cartridge name directory's
/// newest version against the host identity and the registry folder it sits
/// under — opened through the charter stored in it, or why it could not be.
@available(macOS 10.15.4, iOS 13.4, *)
private func scanChannelRoot(
    scanRoot: String,
    slugDir: String,
    folder: Result<RegistryFolder, Error>,
    identity: DiscoveryIdentity,
    discovered: inout [DiscoveredCartridge]
) throws {
    let fm = FileManager.default
    let nameEntries: [String]
    do {
        nameEntries = try fm.contentsOfDirectory(atPath: scanRoot)
    } catch {
        throw CartridgeDiscoveryError.readDirFailed(path: scanRoot, underlying: "\(error)")
    }

    for name in nameEntries.sorted() {
        let nameDir = (scanRoot as NSString).appendingPathComponent(name)
        var nameIsDir: ObjCBool = false
        guard fm.fileExists(atPath: nameDir, isDirectory: &nameIsDir), nameIsDir.boolValue else {
            continue
        }

        let subEntries: [String]
        do {
            subEntries = try fm.contentsOfDirectory(atPath: nameDir)
        } catch {
            continue
        }

        var versionDirs: [String] = []
        for sub in subEntries {
            let subPath = (nameDir as NSString).appendingPathComponent(sub)
            var subIsDir: ObjCBool = false
            if fm.fileExists(atPath: subPath, isDirectory: &subIsDir), subIsDir.boolValue {
                versionDirs.append(subPath)
            }
        }

        guard let versionDir = newestVersionDir(versionDirs) else {
            continue
        }

        let pathDerivedName = (nameDir as NSString).lastPathComponent
        let pathDerivedVersion = (versionDir as NSString).lastPathComponent
        let detectedAt = unixSecondsNow()

        // A folder with no charter that reads makes every cartridge in it
        // misplaced, for the charter's reason.
        let registryFolder: RegistryFolder
        switch folder {
        case .success(let opened):
            registryFolder = opened
        case .failure(let error):
            discovered.append(.incompatible(
                versionDir: versionDir,
                id: pathDerivedName,
                channel: identity.channel,
                registryURL: identity.registryURL,
                version: pathDerivedVersion,
                error: CartridgeAttachmentError(
                    kind: .misplaced,
                    message: "the registry folder \(slugDir) has no charter that reads: \(error.localizedDescription)",
                    detectedAtUnixSeconds: detectedAt
                )
            ))
            continue
        }

        // read_from_dir enforces the charter rule against the folder the
        // cartridge ACTUALLY sits in: its declared registry_url must be the
        // folder's anchor.
        let cj: CartridgeJson
        do {
            cj = try CartridgeJson.readFromDir(versionDir, folder: registryFolder)
        } catch let e as CartridgeJsonError {
            let kind: CartridgeAttachmentErrorKind = e.isRegistryFolderMismatch ? .misplaced : .manifestInvalid
            discovered.append(.incompatible(
                versionDir: versionDir,
                id: pathDerivedName,
                channel: identity.channel,
                registryURL: identity.registryURL,
                version: pathDerivedVersion,
                error: CartridgeAttachmentError(
                    kind: kind,
                    message: "cartridge.json failed to load in the registry folder '\(registryFolder.slug)': \(e)",
                    detectedAtUnixSeconds: detectedAt
                )
            ))
            continue
        }

        switch admission(cj, terms: identity.attachTerms) {
        case .failure(let refused):
            discovered.append(.incompatible(
                versionDir: versionDir,
                id: cj.name,
                channel: cj.channel,
                registryURL: cj.registryURL,
                version: cj.version,
                error: refused.at(detectedAt)
            ))
            continue
        // A bundled cartridge is neither started nor hashed here: its build's
        // signed bundle manifest records the caps a probe would learn, and a
        // host holds its bytes to the recorded hash when it starts it, which
        // is when they are about to run.
        case .success(.bundled(let recorded)):
            discovered.append(.directory(
                entryPoint: cj.resolveEntryPoint(versionDir),
                versionDir: versionDir,
                id: cj.name,
                channel: cj.channel,
                registryURL: cj.registryURL,
                version: cj.version,
                capGroups: recorded.capGroups,
                bundleSHA256: recorded.sha256
            ))
            continue
        case .success(.probe):
            break
        }

        let entryPoint = cj.resolveEntryPoint(versionDir)
        do {
            let capGroups = try probeCartridgeCapGroups(path: entryPoint)
            discovered.append(.directory(
                entryPoint: entryPoint,
                versionDir: versionDir,
                id: cj.name,
                channel: cj.channel,
                registryURL: cj.registryURL,
                version: cj.version,
                capGroups: capGroups,
                bundleSHA256: nil
            ))
        } catch {
            discovered.append(.incompatible(
                versionDir: versionDir,
                id: cj.name,
                channel: cj.channel,
                registryURL: cj.registryURL,
                version: cj.version,
                error: CartridgeAttachmentError(
                    kind: .handshakeFailed,
                    message: "HELLO handshake / cap discovery probe failed: \(error)",
                    detectedAtUnixSeconds: detectedAt
                )
            ))
        }
    }
}
