//
//  CartridgeRepo.swift
//  Bifaci
//
//  Cartridge-registry data model + host-compatibility resolution.
//  Mirrors `capdag/src/bifaci/cartridge_repo.rs`.
//
//  This is the data the registry API serves (`/api/cartridges`) plus the
//  pure logic the engine runs over it to decide, for a given host platform,
//  which version/package (if any) the host should install. The resolution
//  is computed once so both clients render identically without re-deriving
//  platform/version logic.
//

import Foundation

// MARK: - CartridgeChannel

/// Distribution channel a cartridge entry belongs to. Mirrors the Rust
/// `CartridgeChannel` enum — lowercase on the wire (`release`/`nightly`).
public enum CartridgeChannel: String, Codable, Hashable, Sendable {
    /// User-facing release channel.
    case release
    /// In-flight nightly channel.
    case nightly

    /// Wire/disk string form (`"release"` / `"nightly"`).
    public var asString: String { rawValue }

    /// Parse a channel from its wire string, or `nil` if unrecognized.
    public static func from(_ s: String) -> CartridgeChannel? {
        CartridgeChannel(rawValue: s)
    }
}

// MARK: - Distribution / build types

/// Distribution file info (package). `url` is the absolute URL of the
/// package — every consumer downloads from that URL directly.
public struct CartridgeDistributionInfo: Codable, Hashable, Sendable {
    public let name: String
    public let sha256: String
    public let size: UInt64
    public let url: String
    /// Installer format: "pkg" (macOS), "deb"/"rpm" (Linux),
    /// "msi"/"exe" (Windows). Defaulted + skipped-when-empty so the legacy
    /// singular `package` (which has no `format`) round-trips through this
    /// same struct.
    public let format: String

    public init(name: String, sha256: String, size: UInt64, url: String, format: String = "") {
        self.name = name
        self.sha256 = sha256
        self.size = size
        self.url = url
        self.format = format
    }

    enum CodingKeys: String, CodingKey {
        case name, sha256, size, url, format
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        sha256 = try c.decode(String.self, forKey: .sha256)
        size = try c.decode(UInt64.self, forKey: .size)
        url = try c.decode(String.self, forKey: .url)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(sha256, forKey: .sha256)
        try c.encode(size, forKey: .size)
        try c.encode(url, forKey: .url)
        if !format.isEmpty {
            try c.encode(format, forKey: .format)
        }
    }
}

/// A platform-specific build within a version. A platform may ship more than
/// one installer format (e.g. linux-x86_64 → `.deb` + `.rpm`), so `packages`
/// is a list; consumers pick the format the host can run via
/// `primaryPackage()`.
public struct CartridgeBuild: Codable, Hashable, Sendable {
    public let platform: String
    /// Per-format installer list (`.pkg`/`.deb`/`.rpm`/`.msi`/`.exe`).
    /// Defaulted so a registry manifest published before `packages[]`
    /// existed (carrying only the legacy singular `package`) still
    /// deserializes instead of failing the whole parse.
    public var packages: [CartridgeDistributionInfo]
    /// Legacy singular installer (`{name,url,sha256,size}`, no `format`).
    /// Read here only as a fallback when `packages[]` is absent, so a
    /// registry not yet republished with the dual-write keeps installing.
    public var package: CartridgeDistributionInfo?

    public init(platform: String, packages: [CartridgeDistributionInfo] = [], package: CartridgeDistributionInfo? = nil) {
        self.platform = platform
        self.packages = packages
        self.package = package
    }

    enum CodingKeys: String, CodingKey {
        case platform, packages, package
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        platform = try c.decode(String.self, forKey: .platform)
        packages = try c.decodeIfPresent([CartridgeDistributionInfo].self, forKey: .packages) ?? []
        package = try c.decodeIfPresent(CartridgeDistributionInfo.self, forKey: .package)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(platform, forKey: .platform)
        try c.encode(packages, forKey: .packages)
        if let package = package {
            try c.encode(package, forKey: .package)
        }
    }

    /// The installer package the host should use, preferring the platform's
    /// native format. Falls back to the legacy singular `package` when
    /// `packages[]` is empty (pre-dual-write manifests). Returns `nil` only
    /// when the build ships no installer at all.
    public func primaryPackage() -> CartridgeDistributionInfo? {
        let os = platform.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let preference: [String]
        switch os {
        case "darwin": preference = ["pkg"]
        case "linux": preference = ["deb", "rpm"]
        case "windows": preference = ["msi", "exe"]
        default: preference = []
        }
        for fmt in preference {
            if let pkg = packages.first(where: { $0.format == fmt }) {
                return pkg
            }
        }
        return packages.first ?? package
    }
}

/// A cartridge version's data (v5.0 schema). Each version has one or more
/// platform-specific builds.
public struct CartridgeVersionData: Codable, Hashable, Sendable {
    public let releaseDate: String
    public let changelog: [String]
    public let minAppVersion: String
    public var builds: [CartridgeBuild]
    public let notesURL: String?

    public init(releaseDate: String, changelog: [String] = [], minAppVersion: String = "", builds: [CartridgeBuild], notesURL: String? = nil) {
        self.releaseDate = releaseDate
        self.changelog = changelog
        self.minAppVersion = minAppVersion
        self.builds = builds
        self.notesURL = notesURL
    }

    enum CodingKeys: String, CodingKey {
        case releaseDate
        case changelog
        case minAppVersion
        case builds
        case notesURL = "notesUrl"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        releaseDate = try c.decode(String.self, forKey: .releaseDate)
        changelog = try c.decodeIfPresent([String].self, forKey: .changelog) ?? []
        minAppVersion = try c.decodeIfPresent(String.self, forKey: .minAppVersion) ?? ""
        builds = try c.decode([CartridgeBuild].self, forKey: .builds)
        notesURL = try c.decodeIfPresent(String.self, forKey: .notesURL)
    }
}

// MARK: - Host platform

/// The platform string (`{os}-{arch}`) of the binary that calls this, in the
/// exact form the registry uses (`darwin-arm64`, `darwin-x86_64`,
/// `linux-x86_64`, `windows-x86_64`). Single source of truth: every consumer
/// that needs "what am I running on?" calls this rather than re-deriving the
/// os/arch mapping. The raw `aarch64` is never used — it is normalized to
/// `arm64`.
public func hostPlatform() -> String {
    let os: String
    #if os(macOS)
    os = "darwin"
    #elseif os(Linux)
    os = "linux"
    #elseif os(Windows)
    os = "windows"
    #else
    os = "unknown"
    #endif

    let arch: String
    #if arch(arm64)
    arch = "arm64"
    #elseif arch(x86_64)
    arch = "x86_64"
    #else
    arch = "unknown"
    #endif

    return "\(os)-\(arch)"
}

// MARK: - Compatibility resolution

/// Host-compatibility status of a registry cartridge, resolved against a
/// specific host platform string. Mirrors the proto
/// `CartridgeCompatibilityStatus`.
public enum CompatStatus: String, Codable, Hashable, Sendable {
    /// The latest version has a build for this host platform — install as-is.
    case compatible
    /// The latest version has no host build, but an older version does;
    /// `resolvedVersion` names that older version. Install it, mark outdated.
    case compatibleOutdated
    /// No version has a build for this host platform. Nothing to install.
    case incompatible
}

/// The resolved verdict the engine attaches to an available cartridge: which
/// version/package the host should install (if any) and a human reason when
/// it is not the latest-and-greatest.
public struct CartridgeCompatibilityResolution: Hashable, Sendable {
    public let status: CompatStatus
    public let hostPlatform: String
    /// Newest version that has a build for this host (`nil` when incompatible).
    public let resolvedVersion: String?
    /// Host-preferred installer package within `resolvedVersion` (`nil` when
    /// incompatible).
    public let resolvedPackage: CartridgeDistributionInfo?
    /// Explanation, set whenever status is not `.compatible`.
    public let reason: String?
}

// MARK: - CartridgeInfo

/// A cartridge entry as returned by `/api/cartridges`.
public struct CartridgeInfo: Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String
    public var author: String
    public var teamID: String
    public var signedAt: String
    public var minAppVersion: String
    public var pageURL: String
    public var categories: [String]
    public var tags: [String]
    public var capGroups: [CapGroup]
    /// All versions with their builds (platform-specific packages).
    public var versions: [String: CartridgeVersionData]
    /// All available versions (newest first).
    public var availableVersions: [String]
    /// Channel this entry belongs to.
    public var channel: CartridgeChannel
    /// Registry URL this entry was fetched from. Verbatim string — never
    /// trimmed, normalized, or re-derived. Identity comparison is byte
    /// equality.
    public var registryURL: String

    public init(
        id: String,
        name: String,
        version: String,
        description: String = "",
        author: String = "",
        teamID: String = "",
        signedAt: String = "",
        minAppVersion: String = "",
        pageURL: String = "",
        categories: [String] = [],
        tags: [String] = [],
        capGroups: [CapGroup] = [],
        versions: [String: CartridgeVersionData],
        availableVersions: [String],
        channel: CartridgeChannel,
        registryURL: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.teamID = teamID
        self.signedAt = signedAt
        self.minAppVersion = minAppVersion
        self.pageURL = pageURL
        self.categories = categories
        self.tags = tags
        self.capGroups = capGroups
        self.versions = versions
        self.availableVersions = availableVersions
        self.channel = channel
        self.registryURL = registryURL
    }

    /// Find this cartridge's build for `hostPlatform` within a given version,
    /// if any. The host package within it is then chosen by
    /// `CartridgeBuild.primaryPackage()`.
    func buildForHost(version: String, hostPlatform: String) -> CartridgeBuild? {
        versions[version]?.builds.first(where: { $0.platform == hostPlatform })
    }

    /// Resolve which version/package this host should install, scanning
    /// versions newest-first (`availableVersions` is the authoritative
    /// newest-first ordering). The newest version with a usable host build
    /// wins:
    ///   * it IS the latest version → `.compatible`
    ///   * it is older than the latest → `.compatibleOutdated`
    ///   * no version has a host build → `.incompatible`
    ///
    /// "Latest" is `self.version` — not `availableVersions.first`. They must
    /// agree; if they do not, the host build found at `self.version` still
    /// classifies as `.compatible` while any other found version classifies
    /// as `.compatibleOutdated`. We do not paper over a `self.version` with no
    /// host build by silently calling another version latest.
    public func resolveForHost(_ hostPlatform: String) -> CartridgeCompatibilityResolution {
        let latest = version

        for ver in availableVersions {
            guard let build = buildForHost(version: ver, hostPlatform: hostPlatform) else {
                continue
            }
            // primaryPackage() returns nil only when the build ships no
            // installer at all — a build entry with an empty packages[] and no
            // legacy package. That is a malformed registry build; skip it
            // rather than resolve to a version the host cannot actually
            // download, and keep scanning older versions for a usable one.
            guard let pkg = build.primaryPackage() else {
                continue
            }
            if ver == latest {
                return CartridgeCompatibilityResolution(
                    status: .compatible,
                    hostPlatform: hostPlatform,
                    resolvedVersion: ver,
                    resolvedPackage: pkg,
                    reason: nil
                )
            }
            return CartridgeCompatibilityResolution(
                status: .compatibleOutdated,
                hostPlatform: hostPlatform,
                resolvedVersion: ver,
                resolvedPackage: pkg,
                reason: "Latest \(latest) has no \(hostPlatform) build; newest compatible is \(ver)"
            )
        }

        return CartridgeCompatibilityResolution(
            status: .incompatible,
            hostPlatform: hostPlatform,
            resolvedVersion: nil,
            resolvedPackage: nil,
            reason: "No installable \(hostPlatform) build available in any version"
        )
    }
}
