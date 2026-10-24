import XCTest
import CapDAG
@testable import Bifaci

// =============================================================================
// CartridgeDiscovery Tests
//
// Mirrors `capdag/src/cartridge_discovery.rs` scan-all tests: TEST1875-1878.
//
// The scanner enumerates every registry folder on disk (full macOS parity)
// and validates each cartridge in place against the registry folder it sits
// under — as the charter stored there names it (the charter rule) — and the
// host's channel.
// =============================================================================

@available(macOS 10.15.4, iOS 13.4, *)
final class CartridgeDiscoveryTests: XCTestCase {

    // MARK: - Helpers

    private func nightlyDevIdentity() -> DiscoveryIdentity {
        // A root that ships no bundle. Every test that is not ABOUT the bundle
        // scans a tree nothing built, so a cartridge claiming to be bundled
        // there is in the wrong place — which is what this says.
        DiscoveryIdentity(channel: .nightly, registryURL: nil, fabricManifestVersion: 1,
                          cartridgeRegistryVersion: CSBakedCartridgeRegistryVersion,
                          bundle: .none("this directory is not a build's bundle"))
    }

    /// An identity whose bundled cartridges are proven by `manifest`.
    ///
    /// Built here rather than verified, because what is under test is what
    /// discovery DOES with a proof. This mirror carries no chain verification
    /// at all — the Rust library is the only implementation of it — which is
    /// exactly why the proof is a parameter.
    private func bundledIdentity(_ manifest: BundleManifest) -> DiscoveryIdentity {
        DiscoveryIdentity(channel: .nightly, registryURL: nil, fabricManifestVersion: 1,
                          cartridgeRegistryVersion: CSBakedCartridgeRegistryVersion,
                          bundle: .proven(manifest))
    }

    /// Lay down `{root}/{slug}/v{CSBakedCartridgeRegistryVersion}/{channelFolder}/{name}/{version}/`
    /// — the version level pins to the build's baked registry version, exactly
    /// where discovery scans. When `cartridgeJSON` is non-nil, also write it plus
    /// an executable `entry` binary so `readFromDir` accepts the directory and
    /// discovery reaches its own identity checks.
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
        for component in [slug, "v\(CSBakedCartridgeRegistryVersion)", channelFolder, name, version] {
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

    private let cartridgesAnchor = "https://registry.example/cartridges"
    private let cartridgesSlug = "example-cartridges"

    /// Store the example registry's charter in `{root}/{folder}`, as an
    /// installer does — written directly, so a test can store it under another
    /// name than its slug. The signature is opaque here: this mirror carries it
    /// and never reads it.
    private func storeCharter(root: String, folder: String) throws {
        let charter: [String: Any] = [
            "format": CSCharterFormat,
            "anchor": cartridgesAnchor,
            "kind": "cartridges",
            "slug": cartridgesSlug,
            "environment": "prod",
            "locations": ["manifest": "\(cartridgesAnchor)/v{registry_version}/manifest"],
            "fabric": "https://registry.example/fabric",
            "issued_at": 1_792_800_000,
            "not_after": NSNull(),
        ]
        let dir = (root as NSString).appendingPathComponent(folder)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: charter)
            .write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent(CSCharterFile)))
        try Data("sig".utf8).write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent(CSCharterSigFile)))
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

    // TEST1875: scan-all — a chartered registry folder AND the dev slot present on disk are BOTH scanned, regardless of the host's own baked registry. The dev cartridge (null registry under dev/) and the registry cartridge (its url the anchor of its folder's charter) each reach their probe. Both fixtures lack a real bifaci binary, so both end at HandshakeFailed — proving discovery REACHED them (was not filtered out by a registry pin), which is the behavior under test. A registry-pin rejection would instead surface BadInstallation and never probe.
    func test1875_scanAllReachesBothDevAndRegistrySlugs() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try storeCharter(root: root, folder: cartridgesSlug)
        let url = cartridgesAnchor
        let rslug = cartridgesSlug
        // Host baked for a DIFFERENT registry than the on-disk registry cartridge.
        let host = DiscoveryIdentity(
            channel: .nightly,
            registryURL: "https://other.example.com/cartridges",
            fabricManifestVersion: 1,
            cartridgeRegistryVersion: CSBakedCartridgeRegistryVersion,
            bundle: .none("this directory is not a build's bundle")
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

    // TEST1876: only the host's channel subtree is scanned. A cartridge under a slug's `release/` folder is invisible to a nightly host even though the slug folder is present (its `nightly/` subtree is absent).
    func test1876_otherChannelSubtreeIsSkipped() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try storeCharter(root: root, folder: cartridgesSlug)
        let url = cartridgesAnchor
        let rslug = cartridgesSlug
        try installFixture(root: root, slug: rslug, channelFolder: "release", name: "regcart", version: "1.0.0", cartridgeJSON: registryCartridgeJSON(url, "release", 1), entry: "cart")

        let out = try discoverCartridges(root, identity: nightlyDevIdentity())
        XCTAssertTrue(out.isEmpty, "a release-only slug must be invisible to a nightly host, got: \(out)")
    }

    // MARK: - TEST1877

    // TEST1877: a registry cartridge hand-copied into the folder of ANOTHER registry fails the charter rule (Misplaced) — scan-all does not mean "accept anywhere", placement must still be self-consistent.
    func test1877_registryCartridgeUnderWrongSlugIsBadInstall() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try storeCharter(root: root, folder: cartridgesSlug)
        let json = registryCartridgeJSON("https://somewhere-else.example/cartridges", "nightly", 1)
        try installFixture(root: root, slug: cartridgesSlug, channelFolder: "nightly", name: "cart", version: "1.0.0", cartridgeJSON: json, entry: "cart")

        let out = try discoverCartridges(root, identity: nightlyDevIdentity())
        expectIncompatible(out, .misplaced)
    }

    // MARK: - TEST12923

    // TEST12923: a registry folder is what its stored charter proves, never what its name says. The same cartridge, recording the same anchor, is misplaced in a folder with no charter and in a folder whose charter is stored under another name; it reaches its probe only in the folder its charter names.
    func test12923_aRegistryFolderIsProvenByItsCharterNotItsName() throws {
        let json = registryCartridgeJSON(cartridgesAnchor, "nightly", 1)

        // A folder named for the registry, holding no charter.
        let unchartered = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: unchartered) }
        try installFixture(root: unchartered, slug: cartridgesSlug, channelFolder: "nightly", name: "cart", version: "1.0.0", cartridgeJSON: json, entry: "cart")
        let bare = try discoverCartridges(unchartered, identity: nightlyDevIdentity())
        expectIncompatible(bare, .misplaced)
        if case let .incompatible(_, _, _, _, _, error) = bare.first {
            XCTAssertTrue(error.message.contains("no charter that reads"), error.message)
        }

        // The registry's charter, stored in a folder of another name.
        let renamed = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: renamed) }
        try storeCharter(root: renamed, folder: "cartridges.example.com")
        try installFixture(root: renamed, slug: "cartridges.example.com", channelFolder: "nightly", name: "cart", version: "1.0.0", cartridgeJSON: json, entry: "cart")
        expectIncompatible(try discoverCartridges(renamed, identity: nightlyDevIdentity()), .misplaced)

        // Its charter, in the folder the charter names: placement holds, and
        // discovery goes on to probe the (fake) binary.
        let placed = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: placed) }
        try storeCharter(root: placed, folder: cartridgesSlug)
        try installFixture(root: placed, slug: cartridgesSlug, channelFolder: "nightly", name: "cart", version: "1.0.0", cartridgeJSON: json, entry: "cart")
        expectIncompatible(try discoverCartridges(placed, identity: nightlyDevIdentity()), .handshakeFailed)
    }

    // MARK: - TEST1878 / TEST1928

    /// The cartridge.json of a bundled cartridge in the dev slot: placement is
    /// self-consistent (null registry → dev slug), so it passes every earlier
    /// check and reaches the bundled-integrity gate.
    private func bundledCartridgeJSON() -> String {
        """
        {"name":"cart","version":"1.0.0","channel":"nightly","registry_url":null,"entry":"cart","installed_at":"2024-01-01T00:00:00Z","installed_from":"bundle","fabric_manifest_version":1}
        """
    }

    // TEST1878: a bundled cartridge in a root that proves nothing is refused —
    // on every platform.
    //
    // This is the check macOS did not have. The old rule was platform-split:
    // Linux and Windows verified a baked content hash and macOS verified
    // nothing of ours, trusting Gatekeeper instead — so this test was
    // `#if !os(macOS)`. It runs everywhere now because the guard does.
    func test1878_aBundledCartridgeIsRefusedWhereNothingProvesIt() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try installFixture(root: root, slug: "dev", channelFolder: "nightly", name: "cart",
                           version: "1.0.0", cartridgeJSON: bundledCartridgeJSON(), entry: "cart")

        let out = try discoverCartridges(root, identity: nightlyDevIdentity())
        expectIncompatible(out, .misplaced)
        guard case let .incompatible(_, _, _, _, _, error) = out.first else {
            return XCTFail("expected Incompatible, got \(String(describing: out.first))")
        }
        XCTAssertTrue(error.message.contains("bundled cartridge integrity"),
                      "message should name the bundled-integrity failure: \(error.message)")
    }

    // TEST1928: a bundled cartridge the manifest records passes, and one it
    // records differently does not.
    //
    // The other half of TEST1878, and the one that proves the gate is a real
    // check rather than a refusal of everything: the same tree, the same
    // cartridge, and the only difference is what the build recorded about it.
    // A gate that always said no would pass TEST1878 alone.
    func test1928_aBundledCartridgePassesExactlyWhenTheManifestRecordsIt() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try installFixture(root: root, slug: "dev", channelFolder: "nightly", name: "cart",
                           version: "1.0.0", cartridgeJSON: bundledCartridgeJSON(), entry: "cart")

        let versionDir = ((((root as NSString)
            .appendingPathComponent("dev") as NSString)
            .appendingPathComponent("v\(CSBakedCartridgeRegistryVersion)") as NSString)
            .appendingPathComponent("nightly") as NSString)
            .appendingPathComponent("cart") as NSString
        let cartridgeDir = versionDir.appendingPathComponent("1.0.0")
        let recorded = try hashCartridgeDirectory(cartridgeDir)

        func listed(_ sha256: String) -> DiscoveryIdentity {
            bundledIdentity(BundleManifest(environment: "dev", cartridges: [
                BundledCartridge(name: "cart", version: "1.0.0", channel: "nightly", sha256: sha256)
            ]))
        }

        // Recorded as it is on disk: past the gate. It still ends at the HELLO
        // probe, because the fixture's entry point is not a cartridge — what
        // matters is that the failure is no longer the integrity one.
        let passed = try discoverCartridges(root, identity: listed(recorded))
        XCTAssertEqual(passed.count, 1)
        guard case let .incompatible(_, _, _, _, _, error) = passed.first else {
            return XCTFail("expected the probe to be reached, got \(String(describing: passed.first))")
        }
        XCTAssertFalse(error.message.contains("bundled cartridge integrity"),
                       "a cartridge the manifest records must get past the integrity gate: \(error.message)")

        // Recorded as something else — the cartridge was changed after the
        // build recorded it.
        let refused = try discoverCartridges(root, identity: listed(String(repeating: "f", count: 64)))
        expectIncompatible(refused, .misplaced)
        guard case let .incompatible(_, _, _, _, _, other) = refused.first else {
            return XCTFail("expected Incompatible, got \(String(describing: refused.first))")
        }
        XCTAssertTrue(other.message.contains("bundled cartridge integrity"),
                      "a cartridge that differs from the manifest must be refused: \(other.message)")
    }
}
