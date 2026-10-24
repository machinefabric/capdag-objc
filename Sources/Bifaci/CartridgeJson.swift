//
//  CartridgeJson.swift
//  Bifaci
//
//  Cartridge install-context metadata (`cartridge.json`) and the registry
//  folder it is installed in. Mirrors `capdag/src/bifaci/cartridge_json.rs`
//  and the folder half of `capdag/src/bifaci/charter.rs`.
//

import Foundation
import CapDAG

// MARK: - Registry folders

/// What one top-level folder of a cartridge tree holds: the cartridges built
/// with no registry, or a chartered registry's — named by the charter stored
/// in it, never by its own name. The charter is read, not verified: this
/// mirror carries no chain verification (see `CSCharter.h`).
public enum RegistryFolder {
    /// The reserved `dev` folder.
    case dev
    /// A registry's folder, named by its stored charter.
    case chartered(CSCharter)

    /// Open a top-level folder: `dev` by its reserved name, any other by the
    /// cartridges charter stored in it.
    public static func open(_ folder: String) throws -> RegistryFolder {
        if (folder as NSString).lastPathComponent == CSCharterDevSlug {
            return .dev
        }
        return .chartered(try CSCharter.stored(inFolder: folder, kind: .cartridges))
    }

    /// The folder's name.
    public var slug: String {
        switch self {
        case .dev: return CSCharterDevSlug
        case .chartered(let charter): return charter.slug
        }
    }

    /// The anchor every cartridge in the folder must record: nil for dev.
    public var anchor: String? {
        switch self {
        case .dev: return nil
        case .chartered(let charter): return charter.anchor
        }
    }
}

// MARK: - Install timestamps

/// Render `installedAt` for a cartridge being installed right now.
///
/// The field is declared RFC3339 and every reader (and every fixture) treats it
/// as one, so every producer goes through this one function — a bare epoch count
/// with a `Z` stuck on the end parses as neither a number nor a timestamp, and
/// would leave the field readable only by a human who already knew what it was.
///
/// Mirrors `capdag::bifaci::cartridge_json::install_timestamp_now`.
public func installTimestampNow() -> String {
    formatRFC3339UTC(Int64(Date().timeIntervalSince1970))
}

/// Format Unix seconds as `YYYY-MM-DDTHH:MM:SSZ`.
///
/// Built on `DateComponents` in the Gregorian calendar rather than a
/// `DateFormatter` template, so the result does not depend on the process
/// locale or the user's 12/24-hour preference — both of which silently rewrite
/// a format string.
public func formatRFC3339UTC(_ secs: Int64) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: TimeInterval(secs))
    let c = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
        format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
        c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
}

// MARK: - Install source

/// Install-provenance hint stored in `cartridge.json`. Exactly ONE value is
/// semantic: `bundle` selects the bundled-cartridge integrity path at
/// discovery. Every other value is provenance telemetry, and the vocabulary
/// GROWS as installers do — so an unrecognized spelling is preserved
/// verbatim (`other`) and round-trips, never failing the cartridge.json
/// parse. A telemetry hint that could invalidate an otherwise-sound install
/// would make every vocabulary addition brick older hosts against newer
/// installers' records. The dev-vs-not-dev signal the host actually uses is
/// `registryURL` (nil ⇔ dev). Snake-cased on the wire.
public enum CartridgeInstallSource: Codable, Equatable, Sendable {
    case registry
    case dev
    /// The ONE semantic value: selects the bundled-integrity check at discovery.
    case bundle
    case appInstaller
    /// A provenance spelling this build does not know. Preserved verbatim so
    /// the record round-trips; carries no semantics.
    case other(String)

    /// The wire spelling (snake_case for named cases; `other` verbatim).
    public var wireValue: String {
        switch self {
        case .registry: return "registry"
        case .dev: return "dev"
        case .bundle: return "bundle"
        case .appInstaller: return "app_installer"
        case .other(let raw): return raw
        }
    }

    public init(wireValue: String) {
        switch wireValue {
        case "registry": self = .registry
        case "dev": self = .dev
        case "bundle": self = .bundle
        case "app_installer": self = .appInstaller
        default: self = .other(wireValue)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(wireValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }
}

// MARK: - Errors

/// Errors when reading or validating a `cartridge.json`. Mirrors the Rust
/// `CartridgeJsonError`.
public enum CartridgeJsonError: Error, CustomStringConvertible {
    case notFound(path: String)
    case readFailed(path: String, underlying: String)
    case writeFailed(path: String, underlying: String)
    case invalidJSON(path: String, underlying: String)
    case entryPointMissing(path: String, entry: String)
    case entryPointNotExecutable(path: String, entry: String)
    case entryPathEscape(path: String, entry: String)
    /// The charter rule, broken: the cartridge records another registry than
    /// the one its folder's charter names (or a registry in dev, or none in a
    /// registry's folder).
    case registryFolderMismatch(path: String, registryURL: String?, folderSlug: String, holds: String)

    public var description: String {
        switch self {
        case .notFound(let path):
            return "cartridge.json not found at \(path)"
        case .readFailed(let path, let underlying):
            return "failed to read cartridge.json at \(path): \(underlying)"
        case .writeFailed(let path, let underlying):
            return "failed to write cartridge.json at \(path): \(underlying)"
        case .invalidJSON(let path, let underlying):
            return "invalid cartridge.json at \(path): \(underlying)"
        case .entryPointMissing(let path, let entry):
            return "cartridge.json at \(path): entry point '\(entry)' does not exist"
        case .entryPointNotExecutable(let path, let entry):
            return "cartridge.json at \(path): entry point '\(entry)' is not executable"
        case .entryPathEscape(let path, let entry):
            return "cartridge.json at \(path): entry path '\(entry)' escapes version directory"
        case .registryFolderMismatch(let path, let registryURL, let folderSlug, let holds):
            return "cartridge.json at \(path): registry_url=\(registryURL ?? "null"), but it sits in the folder '\(folderSlug)', which holds \(holds)"
        }
    }

    /// True for the folder-mismatch case (used by discovery to choose the
    /// `misplaced` attachment-error kind vs `manifestInvalid`).
    public var isRegistryFolderMismatch: Bool {
        if case .registryFolderMismatch = self { return true }
        return false
    }
}

// MARK: - CartridgeJson

/// Install-context metadata stored in `cartridge.json` inside each cartridge
/// version directory. Identity tuple: `(registryURL, channel, name, version)`.
///
/// All identity fields are required; `registryURL` is required-but-nullable:
/// a missing `registry_url` KEY in the JSON is a parse error (forces the new
/// schema across every install path); only `null` means dev.
public struct CartridgeJson: Equatable, Sendable {
    public let name: String
    public let version: String
    public let channel: CartridgeChannel
    /// Registry the cartridge was published from, recorded as the exact URL
    /// byte-string. `nil` ⇔ dev install.
    public let registryURL: String?
    /// Relative path from the version directory to the executable entry point.
    public let entry: String
    public let installedAt: String
    /// Optional install-provenance hint. Absence is not a parse error.
    public let installedFrom: CartridgeInstallSource?
    public let sourceURL: String
    public let packageSHA256: String
    public let packageSize: UInt64
    /// Fabric registry manifest version this cartridge was built against.
    public let fabricManifestVersion: UInt32

    public init(
        name: String,
        version: String,
        channel: CartridgeChannel,
        registryURL: String?,
        entry: String,
        installedAt: String,
        installedFrom: CartridgeInstallSource? = nil,
        sourceURL: String = "",
        packageSHA256: String = "",
        packageSize: UInt64 = 0,
        fabricManifestVersion: UInt32 = 0
    ) {
        self.name = name
        self.version = version
        self.channel = channel
        self.registryURL = registryURL
        self.entry = entry
        self.installedAt = installedAt
        self.installedFrom = installedFrom
        self.sourceURL = sourceURL
        self.packageSHA256 = packageSHA256
        self.packageSize = packageSize
        self.fabricManifestVersion = fabricManifestVersion
    }

    /// Parse a `cartridge.json` blob, enforcing "required-but-nullable" for
    /// `registry_url`: the JSON key MUST be present (otherwise parse fails);
    /// the value MAY be null (dev install) or a string (registry install).
    /// Returns `nil`-equivalent via throw on any structural failure.
    static func parse(data: Data, path: String) throws -> CartridgeJson {
        let any: Any
        do {
            any = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "\(error)")
        }
        guard let obj = any as? [String: Any] else {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "cartridge.json must be a JSON object")
        }
        // Required-but-nullable: the KEY must be present.
        guard obj.keys.contains("registry_url") else {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "missing field `registry_url`")
        }
        guard let name = obj["name"] as? String else {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "missing or non-string field `name`")
        }
        guard let version = obj["version"] as? String else {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "missing or non-string field `version`")
        }
        guard let channelStr = obj["channel"] as? String else {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "missing or non-string field `channel`")
        }
        guard let channel = CartridgeChannel.from(channelStr) else {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "unknown channel '\(channelStr)'")
        }
        guard let entry = obj["entry"] as? String else {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "missing or non-string field `entry`")
        }
        guard let installedAt = obj["installed_at"] as? String else {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "missing or non-string field `installed_at`")
        }

        let registryURL: String?
        if obj["registry_url"] is NSNull {
            registryURL = nil
        } else if let s = obj["registry_url"] as? String {
            registryURL = s
        } else {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "`registry_url` must be null or a string")
        }

        var installedFrom: CartridgeInstallSource? = nil
        if let isf = obj["installed_from"] as? String {
            // Unknown spellings are preserved verbatim (`other`): the
            // provenance vocabulary grows as installers do, and a telemetry
            // hint must never fail the parse and take the cartridge down
            // with it. Only `bundle` carries semantics.
            installedFrom = CartridgeInstallSource(wireValue: isf)
        } else if obj["installed_from"] != nil && !(obj["installed_from"] is NSNull) {
            throw CartridgeJsonError.invalidJSON(path: path, underlying: "`installed_from` must be a string")
        }

        let sourceURL = (obj["source_url"] as? String) ?? ""
        let packageSHA256 = (obj["package_sha256"] as? String) ?? ""
        let packageSize = (obj["package_size"] as? NSNumber)?.uint64Value ?? 0
        let fabricManifestVersion = (obj["fabric_manifest_version"] as? NSNumber)?.uint32Value ?? 0

        return CartridgeJson(
            name: name,
            version: version,
            channel: channel,
            registryURL: registryURL,
            entry: entry,
            installedAt: installedAt,
            installedFrom: installedFrom,
            sourceURL: sourceURL,
            packageSHA256: packageSHA256,
            packageSize: packageSize,
            fabricManifestVersion: fabricManifestVersion
        )
    }

    /// Read and validate a `cartridge.json` from a version directory.
    ///
    /// `folder` is the top-level folder the host reached the version directory
    /// through, already opened — dev, or a registry named by the charter
    /// stored in it. Passing it in lets us enforce the charter rule (folder ⇔
    /// provenance `registry_url`) inside the parser.
    ///
    /// Validates: file exists + valid JSON; `registryURL` is the folder's
    /// anchor, or nil in dev; entry point does not escape the version
    /// directory; entry point binary exists and is executable.
    public static func readFromDir(_ versionDir: String, folder: RegistryFolder) throws -> CartridgeJson {
        let jsonPath = (versionDir as NSString).appendingPathComponent("cartridge.json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: jsonPath) else {
            throw CartridgeJsonError.notFound(path: jsonPath)
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        } catch {
            throw CartridgeJsonError.readFailed(path: jsonPath, underlying: "\(error)")
        }

        let cj = try parse(data: data, path: jsonPath)

        // The charter rule (places 1 + 2): the cartridge records exactly the
        // anchor its folder's charter states, or no registry in dev. Any other
        // pairing — nil in a registry's folder, a URL in dev, or another
        // registry's anchor — is an installer bug or a tampered tree.
        if cj.registryURL != folder.anchor {
            throw CartridgeJsonError.registryFolderMismatch(
                path: jsonPath,
                registryURL: cj.registryURL,
                folderSlug: folder.slug,
                holds: folder.anchor.map { "the registry chartered for \($0)" }
                    ?? "the cartridges built with no registry"
            )
        }

        // Validate entry point exists.
        let entryPath = (versionDir as NSString).appendingPathComponent(cj.entry)
        guard fm.fileExists(atPath: entryPath) else {
            throw CartridgeJsonError.entryPointMissing(path: jsonPath, entry: cj.entry)
        }

        // Validate entry path does not escape version directory.
        let canonicalDir = (URL(fileURLWithPath: versionDir).resolvingSymlinksInPath().standardizedFileURL).path
        let canonicalEntry = (URL(fileURLWithPath: entryPath).resolvingSymlinksInPath().standardizedFileURL).path
        if !(canonicalEntry == canonicalDir || canonicalEntry.hasPrefix(canonicalDir + "/")) {
            throw CartridgeJsonError.entryPathEscape(path: jsonPath, entry: cj.entry)
        }

        // Validate entry point is executable.
        if !fm.isExecutableFile(atPath: entryPath) {
            throw CartridgeJsonError.entryPointNotExecutable(path: jsonPath, entry: cj.entry)
        }

        return cj
    }

    /// True when this cartridge was installed as a dev build (no registry URL).
    public var isDevInstall: Bool { registryURL == nil }

    /// Resolve the absolute path to the entry point binary.
    public func resolveEntryPoint(_ versionDir: String) -> String {
        (versionDir as NSString).appendingPathComponent(entry)
    }

    /// Serialize to a JSON-compatible dictionary.
    ///
    /// `registry_url` is always emitted (as JSON null for dev installs), never
    /// elided — the consumer's required-but-nullable check would reject an
    /// absent key. The remaining optional fields are omitted when empty rather
    /// than written as null or zero, mirroring the reference's
    /// `skip_serializing_if`: a reader that treats absent and empty alike is
    /// exactly the regime we want, and the smaller file is what every existing
    /// dev install on disk already looks like.
    public func toDictionary() -> [String: Any] {
        var d: [String: Any] = [
            "name": name,
            "version": version,
            "channel": channel.rawValue,
            "registry_url": registryURL as Any? ?? NSNull(),
            "entry": entry,
            "installed_at": installedAt,
        ]
        if let installedFrom { d["installed_from"] = installedFrom.wireValue }
        if !sourceURL.isEmpty { d["source_url"] = sourceURL }
        if !packageSHA256.isEmpty { d["package_sha256"] = packageSHA256 }
        if packageSize != 0 { d["package_size"] = packageSize }
        if fabricManifestVersion != 0 { d["fabric_manifest_version"] = fabricManifestVersion }
        return d
    }

    /// Write this `cartridge.json` into a version directory.
    ///
    /// Mirrors the reference's `write_to_dir`.
    public func writeToDir(_ versionDir: String) throws {
        let jsonPath = (versionDir as NSString).appendingPathComponent("cartridge.json")
        do {
            let data = try JSONSerialization.data(
                withJSONObject: toDictionary(), options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: jsonPath))
        } catch {
            throw CartridgeJsonError.writeFailed(path: jsonPath, underlying: "\(error)")
        }
    }
}

/// Compute a deterministic SHA256 hash of a cartridge directory tree,
/// excluding `cartridge.json`. Mirrors `hash_cartridge_directory`; delegates
/// to the streaming implementation in `CartridgeHost.swift`.
public func hashCartridgeDirectory(_ dir: String) throws -> String {
    try computeCartridgeDirectoryHash(atPath: dir)
}
