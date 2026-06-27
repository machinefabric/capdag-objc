import XCTest
@testable import Bifaci

// =============================================================================
// CartridgeRepo Tests
//
// Mirrors the host-compatibility resolution + legacy-package-fallback tests
// from `capdag/src/bifaci/cartridge_repo.rs`: TEST1847, TEST1849-1853.
// =============================================================================

final class CartridgeRepoTests: XCTestCase {

    // MARK: - Helpers

    /// One platform build carrying a single native-format package, so a
    /// resolution test can assert exactly which package URL the host gets.
    private func buildForPlatform(_ platform: String, _ format: String, _ pkgName: String) -> CartridgeBuild {
        CartridgeBuild(
            platform: platform,
            packages: [
                CartridgeDistributionInfo(
                    name: pkgName,
                    sha256: "deadbeef",
                    size: 4242,
                    url: "https://cartridges.machinefabric.com/\(pkgName)",
                    format: format
                )
            ],
            package: nil
        )
    }

    /// Construct a cartridge whose versions/platform-builds are fully
    /// specified. `versions` is given newest-first; `version` (the "latest"
    /// field) is set to the first entry.
    private func cartridgeWithVersions(
        _ id: String,
        _ versions: [(String, [(String, String, String)])]
    ) -> CartridgeInfo {
        var versionMap: [String: CartridgeVersionData] = [:]
        var available: [String] = []
        for (ver, builds) in versions {
            available.append(ver)
            versionMap[ver] = CartridgeVersionData(
                releaseDate: "2026-02-07",
                changelog: [],
                minAppVersion: "",
                builds: builds.map { buildForPlatform($0.0, $0.1, $0.2) },
                notesURL: nil
            )
        }
        let latest = versions.first?.0 ?? ""
        return CartridgeInfo(
            id: id,
            name: id,
            version: latest,
            teamID: "TEAM123",
            signedAt: "2026-02-07T00:00:00Z",
            versions: versionMap,
            availableVersions: available,
            channel: .release,
            registryURL: "https://example.com/cartridges"
        )
    }

    // MARK: - TEST1847

    // TEST1847: A build from a registry manifest published BEFORE `packages[]` existed carries only the legacy singular `package` (no `format`). It must still deserialize (a missing `packages` must not fail the whole parse) and `primary_package()` must fall back to that legacy package, so a registry not yet republished with the dual-write keeps installing. When `packages[]` is present it is preferred over the legacy field.
    func test1847_cartridgeBuildLegacyPackageFallback() throws {
        // Legacy-only: `package`, no `packages`.
        let legacyJSON = """
        {
            "platform": "linux-x86_64",
            "package": {
                "name": "imagecartridge-1.0.0.pkg",
                "url": "https://cartridges.machinefabric.com/imagecartridge-1.0.0.pkg",
                "sha256": "abc123",
                "size": 1000
            }
        }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(CartridgeBuild.self, from: legacyJSON)
        XCTAssertTrue(legacy.packages.isEmpty)
        let primary = try XCTUnwrap(legacy.primaryPackage(), "legacy package must be read as a fallback")
        XCTAssertEqual(primary.name, "imagecartridge-1.0.0.pkg")
        XCTAssertEqual(primary.format, "") // legacy object has no format
        XCTAssertTrue(primary.url.hasSuffix("imagecartridge-1.0.0.pkg"))

        // packages[] present: preferred over the legacy field, native format wins.
        let modernJSON = """
        {
            "platform": "linux-x86_64",
            "package": {
                "name": "legacy.pkg", "url": "https://x/legacy.pkg",
                "sha256": "dead", "size": 1
            },
            "packages": [
                {"name": "c.rpm", "url": "https://x/c.rpm", "sha256": "a", "size": 2, "format": "rpm"},
                {"name": "c.deb", "url": "https://x/c.deb", "sha256": "b", "size": 3, "format": "deb"}
            ]
        }
        """.data(using: .utf8)!
        let modern = try JSONDecoder().decode(CartridgeBuild.self, from: modernJSON)
        // linux prefers deb over rpm; the legacy `package` is ignored.
        XCTAssertEqual(modern.primaryPackage()?.name, "c.deb")
    }

    // MARK: - resolveForHost (TEST1849-1852)

    // TEST1849: latest version has a host build → Compatible, resolving to the latest version and that platform's native-format package.
    func test1849_resolveForHostCompatibleLatest() {
        let cartridge = cartridgeWithVersions("c", [
            ("1.2.0", [
                ("darwin-arm64", "pkg", "c-1.2.0.pkg"),
                ("linux-x86_64", "deb", "c-1.2.0.deb"),
            ]),
            ("1.1.0", [("darwin-arm64", "pkg", "c-1.1.0.pkg")]),
        ])

        let r = cartridge.resolveForHost("linux-x86_64")
        XCTAssertEqual(r.status, .compatible)
        XCTAssertEqual(r.resolvedVersion, "1.2.0")
        XCTAssertEqual(r.resolvedPackage?.name, "c-1.2.0.deb")
        XCTAssertEqual(r.resolvedPackage?.format, "deb")
        XCTAssertNil(r.reason, "Compatible carries no reason")
        XCTAssertEqual(r.hostPlatform, "linux-x86_64")
    }

    // TEST1850: the latest version lacks a host build but an older version has one → CompatibleOutdated, resolving to the older version with a reason naming both the latest and the resolved version.
    func test1850_resolveForHostCompatibleOutdated() {
        let cartridge = cartridgeWithVersions("c", [
            // Latest 1.3.0 ships only macOS.
            ("1.3.0", [("darwin-arm64", "pkg", "c-1.3.0.pkg")]),
            // 1.2.0 still shipped Linux.
            ("1.2.0", [
                ("darwin-arm64", "pkg", "c-1.2.0.pkg"),
                ("linux-x86_64", "deb", "c-1.2.0.deb"),
            ]),
            ("1.1.0", [("linux-x86_64", "deb", "c-1.1.0.deb")]),
        ])

        let r = cartridge.resolveForHost("linux-x86_64")
        XCTAssertEqual(r.status, .compatibleOutdated)
        // Newest-with-host-build is 1.2.0, NOT the oldest 1.1.0 that also has it.
        XCTAssertEqual(r.resolvedVersion, "1.2.0")
        XCTAssertEqual(r.resolvedPackage?.name, "c-1.2.0.deb")
        let reason = try? XCTUnwrap(r.reason, "outdated carries a reason")
        XCTAssertTrue(reason?.contains("1.3.0") ?? false, "reason names the latest: \(String(describing: r.reason))")
        XCTAssertTrue(reason?.contains("1.2.0") ?? false, "reason names the resolved: \(String(describing: r.reason))")
    }

    // TEST1851: no version ships a host build → Incompatible, no resolved version/package, reason states the host platform.
    func test1851_resolveForHostIncompatible() {
        let cartridge = cartridgeWithVersions("c", [
            ("1.2.0", [("darwin-arm64", "pkg", "c-1.2.0.pkg")]),
            ("1.1.0", [("darwin-arm64", "pkg", "c-1.1.0.pkg")]),
        ])

        let r = cartridge.resolveForHost("windows-x86_64")
        XCTAssertEqual(r.status, .incompatible)
        XCTAssertNil(r.resolvedVersion)
        XCTAssertNil(r.resolvedPackage)
        XCTAssertTrue(r.reason?.contains("windows-x86_64") ?? false)
    }

    // TEST1852: a host build whose packages[] is empty AND has no legacy `package` ships no installer; resolution must SKIP it (not resolve to an un-downloadable version) and fall through to an older usable version.
    func test1852_resolveForHostSkipsBuildWithNoInstaller() {
        var cartridge = cartridgeWithVersions("c", [
            // Latest has a linux build entry but we strip its installer below.
            ("2.0.0", [("linux-x86_64", "deb", "c-2.0.0.deb")]),
            ("1.0.0", [("linux-x86_64", "deb", "c-1.0.0.deb")]),
        ])
        // Make 2.0.0's linux build ship nothing installable.
        var v2 = cartridge.versions["2.0.0"]!
        v2.builds[0].packages = []
        v2.builds[0].package = nil
        cartridge.versions["2.0.0"] = v2

        let r = cartridge.resolveForHost("linux-x86_64")
        // 2.0.0 is skipped (no installer); newest USABLE host build is 1.0.0.
        XCTAssertEqual(r.status, .compatibleOutdated)
        XCTAssertEqual(r.resolvedVersion, "1.0.0")
        XCTAssertEqual(r.resolvedPackage?.name, "c-1.0.0.deb")
    }

    // MARK: - TEST1853

    // TEST1853: host_platform() returns a normalized {os}-{arch} string with arch aarch64 mapped to arm64 — the exact form the registry uses.
    func test1853_hostPlatformNormalizedForm() {
        let p = hostPlatform()
        let parts = p.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 2, "host_platform must be os-arch, got \(p)")
        let os = String(parts[0])
        let arch = String(parts[1])
        XCTAssertTrue(["darwin", "linux", "windows"].contains(os) || !os.isEmpty, "os segment present: \(os)")
        // The registry never uses the raw "aarch64"; it must be normalized.
        XCTAssertNotEqual(arch, "aarch64", "arch must be normalized to arm64")
    }
}
