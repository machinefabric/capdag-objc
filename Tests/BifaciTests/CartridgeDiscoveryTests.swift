import XCTest
@testable import Bifaci

// =============================================================================
// CartridgeDiscovery Tests
//
// Mirrors `capdag/src/cartridge_discovery.rs` scan-all tests: TEST1875-1878.
//
// The scanner enumerates every slug folder on disk (full macOS parity) and
// validates each cartridge in place against the slug folder it sits under
// (the three-place rule) and the host's channel.
// =============================================================================

@available(macOS 10.15.4, iOS 13.4, *)
final class CartridgeDiscoveryTests: XCTestCase {

    // MARK: - Helpers

    private func nightlyDevIdentity() -> DiscoveryIdentity {
        DiscoveryIdentity(channel: .nightly, registryURL: nil, fabricManifestVersion: 1)
    }

    /// Lay down `{root}/{slug}/{channelFolder}/{name}/{version}/`. When
    /// `cartridgeJSON` is non-nil, also write it plus an executable `entry`
    /// binary so `readFromDir` accepts the directory and discovery reaches its
    /// own identity checks.
    private func installFixture(
        root: String,
        slug: String,
        channelFolder: String,
        name: String,
        version: String,
        cartridgeJSON: String?,
        entry: String
    ) throws {
        let fm = FileManager.default
        var dir = root
        for component in [slug, channelFolder, name, version] {
            dir = (dir as NSString).appendingPathComponent(component)
        }
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let json = cartridgeJSON {
            let jsonPath = (dir as NSString).appendingPathComponent("cartridge.json")
            try json.write(toFile: jsonPath, atomically: true, encoding: .utf8)
            let entryPath = (dir as NSString).appendingPathComponent(entry)
            try "#!/bin/sh\nexit 0\n".write(toFile: entryPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entryPath)
        }
    }

    private func devCartridgeJSON(_ channel: String, _ fabricManifestVersion: UInt32) -> String {
        """
        {"name":"cart","version":"1.0.0","channel":"\(channel)","registry_url":null,"entry":"cart","installed_at":"2024-01-01T00:00:00Z","fabric_manifest_version":\(fabricManifestVersion)}
        """
    }

    /// The registry slug for a fixed URL, so tests can place a registry
    /// cartridge under the folder that matches its declared registry_url.
    private func registrySlugFor(_ url: String) -> String {
        slugFor(url)
    }

    private func registryCartridgeJSON(_ url: String, _ channel: String, _ fmv: UInt32) -> String {
        """
        {"name":"cart","version":"1.0.0","channel":"\(channel)","registry_url":"\(url)","entry":"cart","installed_at":"2024-01-01T00:00:00Z","fabric_manifest_version":\(fmv)}
        """
    }

    private func makeTempRoot() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("disco-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func expectIncompatible(_ out: [DiscoveredCartridge], _ kind: CartridgeAttachmentErrorKind, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(out.count, 1, "expected exactly one discovered entry", file: file, line: line)
        guard case let .incompatible(_, _, _, _, _, error) = out.first else {
            return XCTFail("expected Incompatible(\(kind)), got \(String(describing: out.first))", file: file, line: line)
        }
        XCTAssertEqual(error.kind, kind, "wrong attachment-error kind: \(error.message)", file: file, line: line)
    }

    // MARK: - TEST1875

    // TEST1875: scan-all — a registry slug folder AND the dev slot present on
    // disk are BOTH scanned, regardless of the host's own baked registry. The
    // dev cartridge (null registry under dev/) and the registry cartridge (its
    // url hashing to its slug folder) each reach their probe. Both fixtures lack
    // a real bifaci binary, so both end at HandshakeFailed — proving discovery
    // REACHED them (was not filtered out by a registry pin). A registry-pin
    // rejection would instead surface BadInstallation and never probe.
    func test1875_scanAllReachesBothDevAndRegistrySlugs() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let url = "https://cartridges.example.com/manifest"
        let rslug = registrySlugFor(url)
        // Host baked for a DIFFERENT registry than the on-disk registry cartridge.
        let host = DiscoveryIdentity(
            channel: .nightly,
            registryURL: "https://other.example.com/manifest",
            fabricManifestVersion: 1
        )
        try installFixture(root: root, slug: "dev", channelFolder: "nightly", name: "devcart", version: "1.0.0", cartridgeJSON: devCartridgeJSON("nightly", 1), entry: "cart")
        try installFixture(root: root, slug: rslug, channelFolder: "nightly", name: "regcart", version: "1.0.0", cartridgeJSON: registryCartridgeJSON(url, "nightly", 1), entry: "cart")

        let out = try discoverCartridges(root, identity: host)
        XCTAssertEqual(out.count, 2, "both slugs must be scanned, got: \(out)")
        for c in out {
            guard case let .incompatible(_, _, _, _, _, error) = c else {
                return XCTFail("expected probe-stage Incompatible, got \(c)")
            }
            XCTAssertEqual(error.kind, .handshakeFailed, "both reached the probe (not registry-pin-rejected): \(error.message)")
        }
    }

    // MARK: - TEST1876

    // TEST1876: only the host's channel subtree is scanned. A cartridge under a
    // slug's `release/` folder is invisible to a nightly host even though the
    // slug folder is present (its `nightly/` subtree is absent).
    func test1876_otherChannelSubtreeIsSkipped() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let url = "https://cartridges.example.com/manifest"
        let rslug = registrySlugFor(url)
        try installFixture(root: root, slug: rslug, channelFolder: "release", name: "regcart", version: "1.0.0", cartridgeJSON: registryCartridgeJSON(url, "release", 1), entry: "cart")

        let out = try discoverCartridges(root, identity: nightlyDevIdentity())
        XCTAssertTrue(out.isEmpty, "a release-only slug must be invisible to a nightly host, got: \(out)")
    }

    // MARK: - TEST1877

    // TEST1877: a registry cartridge hand-copied under the WRONG registry slug
    // folder fails the three-place rule (BadInstallation) — scan-all does not
    // mean "accept anywhere", placement must still be self-consistent.
    func test1877_registryCartridgeUnderWrongSlugIsBadInstall() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let url = "https://cartridges.example.com/manifest"
        let wrongSlug = registrySlugFor("https://somewhere-else.example.com/manifest")
        let json = registryCartridgeJSON(url, "nightly", 1)
        try installFixture(root: root, slug: wrongSlug, channelFolder: "nightly", name: "cart", version: "1.0.0", cartridgeJSON: json, entry: "cart")

        let out = try discoverCartridges(root, identity: nightlyDevIdentity())
        expectIncompatible(out, .badInstallation)
    }

    // MARK: - TEST1878

    // TEST1878: a cartridge marked `installed_from: bundle` with no baked hash
    // is rejected as BadInstallation — the bundled-integrity gate fires before
    // the probe. Non-macOS only: on macOS the baked-hash path is intentionally
    // absent (OS code-signature is the guard), so a bundled provider is accepted
    // there and would instead end at the probe.
    #if !os(macOS)
    func test1878_bundledProviderWithoutBakedHashIsRejected() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        // Dev slug (null registry) but installed_from=bundle — placement is
        // self-consistent (null→dev), so it passes readFromDir and reaches the
        // bundled-hash gate, which has no baked entry → BadInstallation.
        let json = """
        {"name":"cart","version":"1.0.0","channel":"nightly","registry_url":null,"entry":"cart","installed_at":"2024-01-01T00:00:00Z","installed_from":"bundle","fabric_manifest_version":1}
        """
        try installFixture(root: root, slug: "dev", channelFolder: "nightly", name: "cart", version: "1.0.0", cartridgeJSON: json, entry: "cart")

        let out = try discoverCartridges(root, identity: nightlyDevIdentity())
        expectIncompatible(out, .badInstallation)
        guard case let .incompatible(_, _, _, _, _, error) = out.first else {
            return XCTFail("expected Incompatible, got \(String(describing: out.first))")
        }
        XCTAssertTrue(error.message.contains("bundled provider integrity"),
                      "message should name the bundled-integrity failure: \(error.message)")
    }
    #endif
}
