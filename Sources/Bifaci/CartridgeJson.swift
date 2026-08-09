//
//  CartridgeJson.swift
//  Bifaci
//
//  Cartridge install-context metadata (`cartridge.json`) + the registry
//  slug mapping and registry-URL scheme validator. Mirrors
//  `capdag/src/bifaci/cartridge_slug.rs` and `capdag/src/bifaci/cartridge_json.rs`.
//

import Foundation

// MARK: - Registry slug

/// Reserved folder name for cartridges with no registry (developer-built
/// cartridges installed without `--registry`). A real registry authority is
/// never the literal "dev".
public let cartridgeDevSlug = "dev"

/// The authority (host[:port]) of a registry URL: after `://` up to the next
/// `/`, `?`, or `#` (path/query/fragment discarded).
private func cartridgeAuthorityOf(_ url: String) -> Substring {
    let afterScheme: Substring
    if let r = url.range(of: "://") {
        afterScheme = url[r.upperBound...]
    } else {
        afterScheme = url[...]
    }
    if let idx = afterScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
        return afterScheme[..<idx]
    }
    return afterScheme
}

private func cartridgeIsAuthorityScalar(_ v: UInt32) -> Bool {
    (v >= 97 && v <= 122) || (v >= 48 && v <= 57) || v == 46 || v == 45
}

/// Compute the on-disk slug for a registry URL. Mirrors
/// capdag::cartridge_slug::slug_for byte-for-byte:
///
/// `nil` (a dev cartridge) → the literal `dev` slug.
/// non-nil URL → a path-safe transform of the URL's authority (host[:port]):
/// ASCII-lowercased, every character outside `[a-z0-9.-]` replaced by `-`.
/// Depends ONLY on the authority — path (incl. the version segment), query,
/// trailing slash, and host case do not change it.
public func slugFor(_ registryURL: String?) -> String {
    guard let url = registryURL else {
        return cartridgeDevSlug
    }
    var out = String.UnicodeScalarView()
    for scalar in cartridgeAuthorityOf(url).unicodeScalars {
        var v = scalar.value
        if v >= 65 && v <= 90 { v += 32 }  // ASCII A-Z -> a-z only
        if cartridgeIsAuthorityScalar(v) {
            out.append(Unicode.Scalar(v)!)
        } else {
            out.append("-")
        }
    }
    return String(out)
}

/// True if `s` could be a valid slug for a non-dev registry: a non-empty
/// path-safe authority string (`[a-z0-9.-]+`) that is not the dev sentinel.
public func isRegistrySlug(_ s: String) -> Bool {
    !s.isEmpty && s != cartridgeDevSlug
        && s.unicodeScalars.allSatisfy { cartridgeIsAuthorityScalar($0.value) }
}

// MARK: - Registry-URL scheme validation

/// Result of validating a non-null `registry_url` scheme. Mirrors the Rust
/// `RegistryUrlSchemeResult`.
public enum RegistryURLSchemeResult: Equatable {
    /// URL is acceptable (dev-mode allows it, or scheme is `https`).
    case ok
    /// URL string didn't parse as a valid URL. Carries the offending string.
    case notAURL(String)
    /// URL parsed but scheme is not `https` and dev-mode is off. Carries the
    /// offending scheme.
    case nonHTTPS(scheme: String)
}

/// Validate that a non-null `registry_url` uses the `https` scheme — UNLESS
/// `devMode` is set, in which case any well-formed URL is accepted (so
/// developers can point at `http://localhost:port` during integration
/// testing). The rule lives at the deepest layer so a caller can never
/// bypass it by parsing the URL out of band. Dev cartridges
/// (`registry_url == nil`) never go through this validator.
public func validateRegistryURLScheme(_ url: String, devMode: Bool) -> RegistryURLSchemeResult {
    // Cheap parse: split once on `://`. The rule is "scheme must be the
    // literal bytes `https`"; full URL validation is the caller's job.
    guard let range = url.range(of: "://") else {
        return .notAURL(url)
    }
    let scheme = String(url[url.startIndex..<range.lowerBound])
    let rest = String(url[range.upperBound...])
    if rest.isEmpty {
        return .notAURL(url)
    }
    if devMode {
        // Dev mode: accept any well-formed scheme. We still require SOME
        // scheme to be present (an empty scheme is malformed regardless).
        return .ok
    }
    if scheme.lowercased() == "https" {
        return .ok
    }
    return .nonHTTPS(scheme: scheme)
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

/// Install-provenance hint stored in `cartridge.json`. **Not consulted for
/// any routing or attachment decision** — the dev-vs-not-dev signal the host
/// actually uses is `registryURL` (nil ⇔ dev). Snake-cased on the wire.
public enum CartridgeInstallSource: String, Codable, Equatable, Sendable {
    case registry
    case dev
    case bundle
    case appInstaller = "app_installer"
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
    /// The folder the cartridge.json was loaded from doesn't match the slug
    /// derived from its declared `registry_url`. The three-place consistency
    /// check: top-level folder, the provenance's `registry_url`, and the
    /// cartridge's HELLO manifest must all agree.
    case registrySlugMismatch(path: String, registryURL: String?, expectedSlug: String, actualSlug: String)

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
        case .registrySlugMismatch(let path, let registryURL, let expectedSlug, let actualSlug):
            return "cartridge.json at \(path): registry slug mismatch — registry_url=\(String(describing: registryURL)) hashes to slug='\(expectedSlug)' but the directory tree placed it under '\(actualSlug)'"
        }
    }

    /// True for the slug-mismatch case (used by discovery to choose the
    /// `badInstallation` attachment-error kind vs `manifestInvalid`).
    public var isRegistrySlugMismatch: Bool {
        if case .registrySlugMismatch = self { return true }
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
            guard let parsed = CartridgeInstallSource(rawValue: isf) else {
                throw CartridgeJsonError.invalidJSON(path: path, underlying: "unknown installed_from '\(isf)'")
            }
            installedFrom = parsed
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
    /// `expectedSlug` is the registry slug the host reached the version
    /// directory through — the second-to-top-level folder name in
    /// `{root}/{slug}/{channel}/{name}/{version}/`. Passing it in lets us
    /// enforce the three-place rule (folder slug ⇔ provenance `registry_url`)
    /// inside the parser.
    ///
    /// Validates: file exists + valid JSON; `slug_for(registryURL) ==
    /// expectedSlug`; entry point does not escape the version directory;
    /// entry point binary exists and is executable.
    public static func readFromDir(_ versionDir: String, expectedSlug: String) throws -> CartridgeJson {
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

        // Three-place consistency rule (places 1 + 2): the folder slug must
        // match the slug derived from the provenance's registry_url. None+`dev`
        // and Some(url)+slug(url) are the only valid pairings.
        let derivedSlug = slugFor(cj.registryURL)
        if derivedSlug != expectedSlug {
            throw CartridgeJsonError.registrySlugMismatch(
                path: jsonPath,
                registryURL: cj.registryURL,
                expectedSlug: derivedSlug,
                actualSlug: expectedSlug
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

    /// The on-disk slug this provenance must live under.
    public var registrySlug: String { slugFor(registryURL) }

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
        if let installedFrom { d["installed_from"] = installedFrom.rawValue }
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
