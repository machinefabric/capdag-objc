//
//  CartridgeDiscovery.swift
//  Bifaci
//
//  Shared cartridge discovery: the on-disk scan + identity validation +
//  HELLO probe that classifies each installed cartridge version directory as
//  attachable (`directory`) or `incompatible`. Mirrors
//  `capdag/src/cartridge_discovery.rs`.
//
//  Managed layout (relative to the root passed to `discoverCartridges`):
//  `{root}/{slug}/{channel}/{name}/{version}/cartridge.json`.
//

import Foundation

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

    public init(channel: CartridgeChannel, registryURL: String?, fabricManifestVersion: UInt32, cartridgeRegistryVersion: UInt32) {
        self.channel = channel
        self.registryURL = registryURL
        self.fabricManifestVersion = fabricManifestVersion
        self.cartridgeRegistryVersion = cartridgeRegistryVersion
    }

    /// On-disk top-level slug for THIS host's own baked registry (`dev` when
    /// `registryURL` is nil). Discovery enumerates every slug folder on disk
    /// and validates each cartridge against the folder it sits under; this
    /// helper is retained for callers that need the host's own slug.
    public func slug() -> String {
        slugFor(registryURL)
    }
}

// MARK: - Discovered classification

/// A discovered cartridge version directory, classified.
///
/// - `directory` — passed every identity check and its HELLO probe succeeded.
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
        capGroups: [CapGroup]
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

// MARK: - Probe

/// Probe a cartridge binary for its capability surface.
///
/// Spawns the binary, performs the bifaci HELLO handshake, parses the
/// manifest, returns its full `cap_groups`, then kills the process. A binary
/// that fails to spawn, fails HELLO, or returns an unparseable manifest is an
/// error — the caller surfaces it as `handshakeFailed`.
@available(macOS 10.15.4, iOS 13.4, *)
public func probeCartridgeCapGroups(path: String) throws -> [CapGroup] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)

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

    guard let manifestData = result.manifest else {
        throw CartridgeDiscoveryError.readDirFailed(path: path, underlying: "cartridge \(path) HELLO missing manifest")
    }

    do {
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        return manifest.capGroups
    } catch {
        let preview = String(data: manifestData.prefix(500), encoding: .utf8) ?? "<non-utf8>"
        throw CartridgeDiscoveryError.readDirFailed(path: path, underlying: "cartridge \(path) invalid manifest (\(error)): \(preview)")
    }
}

// MARK: - Bundled-cartridge integrity (non-macOS)

#if !os(macOS)
/// Baked content hashes for bundled cartridges. Empty in the plain test build
/// (no cartridges bundled); a real bundle build codegens entries. Mirrors the
/// Rust `BUNDLED_CARTRIDGE_HASHES` const.
let bundledCartridgeHashes: [(name: String, version: String, hash: String)] = []

/// Look up the baked expected directory hash for a bundled cartridge, or nil
/// if `(name, version)` was not recorded at build time.
func bundledCartridgeExpectedHash(name: String, version: String) -> String? {
    bundledCartridgeHashes.first(where: { $0.name == name && $0.version == version })?.hash
}

/// Verify a bundled cartridge's on-disk content against the baked hash.
/// `nil` return ⇔ ok; a non-nil string is the failure reason.
func verifyBundledCartridgeHash(name: String, version: String, versionDir: String) -> String? {
    guard let expected = bundledCartridgeExpectedHash(name: name, version: version) else {
        return "no baked hash for bundled cartridge \(name) \(version) — this build did not record it (MFR_BUNDLED_CARTRIDGE_HASHES)"
    }
    let actual: String
    do {
        actual = try hashCartridgeDirectory(versionDir)
    } catch {
        return "failed to hash bundled cartridge directory: \(error)"
    }
    if actual == expected {
        return nil
    }
    return "content hash mismatch — baked \(expected), on-disk \(actual); the shipped cartridge differs from what this build was compiled to ship"
}
#endif

// MARK: - Discovery

/// Discover every cartridge under `{cartridgesRoot}/{slug}/{channel}/`. Each
/// cartridge name directory's newest version is validated against `identity`
/// and probed; the result is the full classified roster. An empty/absent scan
/// root is not an error — it yields an empty roster. A real I/O failure
/// reading an existing scan root IS an error.
@available(macOS 10.15.4, iOS 13.4, *)
public func discoverCartridges(_ cartridgesRoot: String, identity: DiscoveryIdentity) throws -> [DiscoveredCartridge] {
    var discovered: [DiscoveredCartridge] = []
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: cartridgesRoot, isDirectory: &isDir), isDir.boolValue else {
        return discovered
    }

    // Scan EVERY slug folder present on disk — full macOS parity. The host's
    // baked registry does NOT restrict which slugs are scanned; each cartridge
    // is validated in place against the slug folder it sits under. The channel
    // folder IS still pinned to the host's channel.
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
        // {slug}/v{cartridgeRegistryVersion}/{channel}/… — the registry regime
        // version is a path level pinned to the host's version (like channel).
        let versionDir = (slugDir as NSString).appendingPathComponent("v\(identity.cartridgeRegistryVersion)")
        let scanRoot = (versionDir as NSString).appendingPathComponent(identity.channel.asString)
        var scanIsDir: ObjCBool = false
        guard fm.fileExists(atPath: scanRoot, isDirectory: &scanIsDir), scanIsDir.boolValue else {
            // This slug has no subtree for the host's (version, channel) — skip.
            continue
        }
        try scanChannelRoot(scanRoot: scanRoot, expectedSlug: slugName, identity: identity, discovered: &discovered)
    }

    return discovered
}

/// Scan one `{slug}/{channel}/` root: classify each cartridge name directory's
/// newest version against the host identity and the slug folder it sits under.
@available(macOS 10.15.4, iOS 13.4, *)
private func scanChannelRoot(
    scanRoot: String,
    expectedSlug: String,
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

        if versionDirs.isEmpty {
            continue
        }

        // Prefer the newest version (lexical-descending on the folder name).
        versionDirs.sort { a, b in
            let va = (a as NSString).lastPathComponent
            let vb = (b as NSString).lastPathComponent
            return vb < va
        }
        let versionDir = versionDirs[0]

        let pathDerivedName = (nameDir as NSString).lastPathComponent
        let pathDerivedVersion = (versionDir as NSString).lastPathComponent
        let detectedAt = unixSecondsNow()

        // read_from_dir enforces the three-place rule against the ACTUAL slug
        // folder: the cartridge's declared registry_url must hash to it.
        let cj: CartridgeJson
        do {
            cj = try CartridgeJson.readFromDir(versionDir, expectedSlug: expectedSlug)
        } catch let e as CartridgeJsonError {
            let kind: CartridgeAttachmentErrorKind = e.isRegistrySlugMismatch ? .badInstallation : .manifestInvalid
            discovered.append(.incompatible(
                versionDir: versionDir,
                id: pathDerivedName,
                channel: identity.channel,
                registryURL: identity.registryURL,
                version: pathDerivedVersion,
                error: CartridgeAttachmentError(
                    kind: kind,
                    message: "cartridge.json failed to load under slug '\(expectedSlug)': \(e)",
                    detectedAtUnixSeconds: detectedAt
                )
            ))
            continue
        }

        if cj.channel != identity.channel {
            discovered.append(.incompatible(
                versionDir: versionDir,
                id: cj.name,
                channel: cj.channel,
                registryURL: cj.registryURL,
                version: cj.version,
                error: CartridgeAttachmentError(
                    kind: .badInstallation,
                    message: "Channel mismatch: cartridge declares '\(cj.channel.asString)' but host is pinned to '\(identity.channel.asString)'. Release and nightly artefacts must not mix.",
                    detectedAtUnixSeconds: detectedAt
                )
            ))
            continue
        }

        // Scheme check is per-cartridge: a registry cartridge must use https.
        if let url = cj.registryURL {
            switch validateRegistryURLScheme(url, devMode: false) {
            case .ok:
                break
            case .nonHTTPS(let scheme):
                discovered.append(.incompatible(
                    versionDir: versionDir,
                    id: cj.name,
                    channel: cj.channel,
                    registryURL: cj.registryURL,
                    version: cj.version,
                    error: CartridgeAttachmentError(
                        kind: .incompatible,
                        message: "registry_url uses '\(scheme)' scheme, must be https in non-dev builds. Rebuild the cartridge with an https registry URL.",
                        detectedAtUnixSeconds: detectedAt
                    )
                ))
                continue
            case .notAURL(let bad):
                discovered.append(.incompatible(
                    versionDir: versionDir,
                    id: cj.name,
                    channel: cj.channel,
                    registryURL: cj.registryURL,
                    version: cj.version,
                    error: CartridgeAttachmentError(
                        kind: .incompatible,
                        message: "registry_url '\(bad)' is not a well-formed URL.",
                        detectedAtUnixSeconds: detectedAt
                    )
                ))
                continue
            }
        }

        if cj.fabricManifestVersion != identity.fabricManifestVersion {
            discovered.append(.incompatible(
                versionDir: versionDir,
                id: cj.name,
                channel: cj.channel,
                registryURL: cj.registryURL,
                version: cj.version,
                error: CartridgeAttachmentError(
                    kind: .fabricManifestVersionMismatch,
                    message: "Cartridge built against fabric manifest version \(cj.fabricManifestVersion), but host is pinned to \(identity.fabricManifestVersion). Rebuild the cartridge with MFR_FABRIC_MANIFEST_VERSION=\(identity.fabricManifestVersion).",
                    detectedAtUnixSeconds: detectedAt
                )
            ))
            continue
        }

        // Bundled-cartridge integrity. A cartridge marked `installed_from:
        // bundle` is shipped INSIDE this build and has no upstream registry to
        // verify against — so it needs its own integrity proof.
        // - macOS: the OS code-signature IS the guard (notarized .app); no
        //   baked-hash verification (Apple's re-signing would re-break a content
        //   hash). We trust the signature — an explicit, visible rule.
        // - Linux/Windows: integrity is a content hash baked at build time.
        if cj.installedFrom == .bundle {
            #if !os(macOS)
            if let reason = verifyBundledCartridgeHash(name: cj.name, version: cj.version, versionDir: versionDir) {
                discovered.append(.incompatible(
                    versionDir: versionDir,
                    id: cj.name,
                    channel: cj.channel,
                    registryURL: cj.registryURL,
                    version: cj.version,
                    error: CartridgeAttachmentError(
                        kind: .badInstallation,
                        message: "bundled cartridge integrity check failed: \(reason)",
                        detectedAtUnixSeconds: detectedAt
                    )
                ))
                continue
            }
            #endif
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
                capGroups: capGroups
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
