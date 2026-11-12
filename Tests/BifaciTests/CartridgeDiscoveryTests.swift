import XCTest
import CapDAG
@testable import Bifaci

// =============================================================================
// CartridgeDiscovery Tests
//
// Mirrors `capdag/src/cartridge_discovery.rs` scan-all tests: TEST1875-1878,
// its attach-rule tests: TEST1907, TEST1908, and its bundled-cartridge tests:
// TEST1928, TEST1931, TEST1932.
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

    // MARK: - TEST1878 / TEST1928 / TEST1931 / TEST1932

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

    /// The cap groups a build recorded for the fixture cartridge: one cap,
    /// which discovery must hand back as recorded.
    private func recordedCapGroups() -> [CapGroup] {
        [CapGroup(
            name: "cart",
            caps: [CapDefinition(urn: CSCapIdentity, title: "Identity", aliases: ["identity"])],
            adapterUrns: []
        )]
    }

    /// A manifest recording the fixture cartridge at `sha256`, built for
    /// fabric manifest version `fabricManifestVersion`.
    private func recorded(_ sha256: String, _ fabricManifestVersion: UInt32) -> BundleManifest {
        BundleManifest(environment: "dev", cartridges: [
            BundledCartridge(
                name: "cart", version: "1.0.0", channel: "nightly", sha256: sha256,
                fabricManifestVersion: fabricManifestVersion, capGroups: recordedCapGroups()
            )
        ])
    }

    /// Lay down the bundled fixture cartridge with an entry point that cannot
    /// be started on any platform: marked executable, as an installed entry
    /// point must be, and not a program. A discovery that started it would
    /// end at handshakeFailed. Returns the version directory.
    private func installUnstartableBundled(root: String) throws -> String {
        var dir = root
        for component in ["dev", "v\(CSBakedCartridgeRegistryVersion)", "nightly", "cart", "1.0.0"] {
            dir = (dir as NSString).appendingPathComponent(component)
        }
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try bundledCartridgeJSON().write(
            toFile: (dir as NSString).appendingPathComponent("cartridge.json"), atomically: true, encoding: .utf8
        )
        let entryPath = (dir as NSString).appendingPathComponent("cart")
        try Data("not a program".utf8).write(to: URL(fileURLWithPath: entryPath))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entryPath)
        return dir
    }

    // TEST1928: a bundled cartridge is admitted exactly when the manifest
    // records it, and refused, before anything runs, when it does not.
    //
    // The other half of TEST1878, and the one that proves the gate is a real
    // check rather than a refusal of everything: the same tree, the same
    // cartridge, and the only difference is what the build recorded about it.
    func test1928_aBundledCartridgePassesExactlyWhenTheManifestRecordsIt() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        _ = try installUnstartableBundled(root: root)

        let admitted = try discoverCartridges(root, identity: bundledIdentity(recorded(String(repeating: "a", count: 64), 1)))
        XCTAssertEqual(admitted.count, 1)
        guard case .directory = admitted.first else {
            return XCTFail("a recorded bundled cartridge must be admitted: \(String(describing: admitted.first))")
        }

        // Recorded under another name: this build ships a cartridge it did not
        // record.
        let other = BundleManifest(environment: "dev", cartridges: [
            BundledCartridge(
                name: "other", version: "1.0.0", channel: "nightly", sha256: String(repeating: "a", count: 64),
                fabricManifestVersion: 1, capGroups: recordedCapGroups()
            )
        ])
        let refused = try discoverCartridges(root, identity: bundledIdentity(other))
        expectIncompatible(refused, .misplaced)
        guard case let .incompatible(_, _, _, _, _, error) = refused.first else {
            return XCTFail("expected Incompatible, got \(String(describing: refused.first))")
        }
        XCTAssertTrue(error.message.contains("bundled cartridge integrity"),
                      "a cartridge the manifest does not record must be refused: \(error.message)")
    }

    // TEST1931: discovering a bundle neither starts nor hashes a cartridge:
    // its caps and its content hash are the ones the signed manifest records.
    //
    // The entry point cannot be started, so a discovery that probed it would
    // report handshakeFailed; and the recorded hash is not the directory's, so
    // a discovery that hashed it would refuse it. The hash is held to the
    // directory when a host starts the cartridge (TEST1962's half).
    func test1931_bundledDiscoveryReadsTheManifestAndStartsNothing() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let dir = try installUnstartableBundled(root: root)

        let out = try discoverCartridges(root, identity: bundledIdentity(recorded(String(repeating: "f", count: 64), 1)))
        XCTAssertEqual(out.count, 1)
        guard case let .directory(entryPoint, versionDir, _, _, _, _, capGroups, bundleSHA256) = out.first else {
            return XCTFail("expected the bundled cartridge admitted from its manifest, got \(String(describing: out.first))")
        }
        XCTAssertEqual(capGroups, recordedCapGroups(), "the caps must be the recorded ones")
        XCTAssertEqual(bundleSHA256, String(repeating: "f", count: 64))
        XCTAssertEqual(versionDir, dir)
        XCTAssertEqual(entryPoint, (dir as NSString).appendingPathComponent("cart"))
    }

    // TEST1932: a bundled cartridge whose build recorded another fabric
    // manifest version is refused as built for another fabric, without being
    // started.
    //
    // Its cartridge.json says the host's version; the signed record says
    // otherwise, and the signed record is what discovery believes, since
    // cartridge.json is outside the hash.
    func test1932_aBundledCartridgeBuiltForAnotherFabricIsRefusedUnstarted() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        _ = try installUnstartableBundled(root: root)

        let out = try discoverCartridges(root, identity: bundledIdentity(recorded(String(repeating: "a", count: 64), 2)))
        expectIncompatible(out, .fabricManifestVersionMismatch)
        guard case let .incompatible(_, _, _, _, _, error) = out.first else {
            return XCTFail("expected Incompatible, got \(String(describing: out.first))")
        }
        XCTAssertTrue(
            error.message.contains("was built for fabric manifest 2, as its build's signed bundle manifest records"),
            error.message
        )
    }

    // MARK: - TEST1907

    // TEST1907: a cartridge's installed version is its newest, dotted numbers
    // compared as numbers: 1.174.414 is newer than 1.99.0, though it sorts
    // before it as text. Discovery shows that version, and a run uses it.
    func test1907_theNewestVersionIsChosenByNumberNotText() throws {
        let dirs = ["1.99.0", "1.174.414", "1.9.12", "1.174.9"].map { ("cart" as NSString).appendingPathComponent($0) }
        XCTAssertEqual(newestVersionDir(dirs), ("cart" as NSString).appendingPathComponent("1.174.414"))
        XCTAssertNil(newestVersionDir([]))

        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        for (version, manifest) in [("1.99.0", 1), ("1.174.414", 999)] {
            let json = """
            {"name":"cart","version":"\(version)","channel":"nightly","registry_url":null,"entry":"cart","installed_at":"2024-01-01T00:00:00Z","fabric_manifest_version":\(manifest)}
            """
            try installFixture(root: root, slug: "dev", channelFolder: "nightly", name: "cart",
                               version: version, cartridgeJSON: json, entry: "cart")
        }
        let out = try discoverCartridges(root, identity: nightlyDevIdentity())
        // 1.174.414 is the one shown, and it is stamped for another manifest,
        // so the cartridge is refused rather than 1.99.0 being probed.
        guard out.count == 1, case let .incompatible(_, _, _, _, version, error) = out[0] else {
            return XCTFail("expected the newest version, refused; got \(out)")
        }
        XCTAssertEqual(version, "1.174.414")
        XCTAssertEqual(error.kind, .fabricManifestVersionMismatch)
    }

    // MARK: - TEST1908

    // TEST1908: a cartridge stamped for another fabric manifest is refused
    // naming it, its version, its manifest and the host's, with the remedy
    // that fits where it came from: a registry install is installed again, a
    // dev cartridge rebuilt, and a bundled one means the build is wrong.
    func test1908_aManifestRefusalNamesBothManifestsAndTheRemedy() throws {
        let terms = AttachTerms(channel: .release, fabricManifestVersion: 13, bundle: .none("no bundle here"))
        func stamped(_ from: CartridgeInstallSource?, _ registry: String?, _ manifest: UInt32) -> CartridgeJson {
            CartridgeJson(name: "imagecartridge", version: "1.174.414", channel: .release, registryURL: registry,
                          entry: "imagecartridge", installedAt: "2024-01-01T00:00:00Z", installedFrom: from,
                          fabricManifestVersion: manifest)
        }

        guard case .success(.probe) = admission(stamped(.registry, cartridgesAnchor, 13), terms: terms) else {
            return XCTFail("a cartridge stamped for this host is attached by starting it")
        }

        func refused(_ from: CartridgeInstallSource?, _ registry: String?) throws -> Refusal {
            guard case let .failure(refusal) = admission(stamped(from, registry, 12), terms: terms) else {
                XCTFail("stamped for 12, refused by a host at 13")
                throw Refusal(kind: .misplaced, message: "not refused")
            }
            return refusal
        }
        let installed = try refused(.registry, cartridgesAnchor)
        XCTAssertEqual(installed.kind, .fabricManifestVersionMismatch)
        XCTAssertEqual(
            installed.message,
            "imagecartridge 1.174.414 was installed for fabric manifest 12, and this host reads "
                + "fabric manifest 13. Remove it and install it again from its registry."
        )
        // Provenance other than `bundle` carries no meaning: a registryURL is
        // what makes it a registry install.
        XCTAssertEqual(try refused(nil, cartridgesAnchor), installed)
        let rebuild = "Rebuild it with MFR_FABRIC_MANIFEST_VERSION=13 and install it again."
        XCTAssertTrue(try refused(.dev, nil).message.hasSuffix(rebuild))
        XCTAssertTrue(try refused(nil, nil).message.hasSuffix(rebuild))
        XCTAssertTrue(try refused(.bundle, cartridgesAnchor).message
            .hasSuffix("its bundle holds a cartridge for another fabric manifest."))
    }
}
