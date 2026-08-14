import XCTest
@testable import Bifaci

// =============================================================================
// CartridgeJson Tests
//
// Mirrors `capdag/src/bifaci/cartridge_json.rs` TEST1514.
// =============================================================================

final class CartridgeJsonTests: XCTestCase {

    private func json(installedFrom: String) -> Data {
        Data("""
        {
            "name": "candlecartridge",
            "version": "1.227.800",
            "channel": "nightly",
            "registry_url": "https://cartridges-staging.machinefabric.com/v1/manifest",
            "entry": "candlecartridge",
            "installed_at": "2026-08-14T22:26:59Z",
            "installed_from": "\(installedFrom)",
            "fabric_manifest_version": 4
        }
        """.utf8)
    }

    // TEST1514: the provenance vocabulary grows with installers. A workspace
    // build install parses to its named case; a spelling this build does not
    // know parses to `other`, round-trips VERBATIM, and is not `bundle` (the
    // one semantic value) — an unknown telemetry hint can never fail the
    // cartridge.json parse and take the cartridge (or, through discovery,
    // the whole host roster) down with it.
    func test1514_installSourceVocabularyTolerance() throws {
        // A drifted installer's spelling is tolerated but NOT blessed: the
        // protocol's vocabulary is registry/dev/bundle/app_installer, and a
        // writer's mistake never becomes a named case.
        let built = try CartridgeJson.parse(data: json(installedFrom: "build"), path: "/t/cartridge.json")
        XCTAssertEqual(built.installedFrom, .other("build"))

        let unknown = try CartridgeJson.parse(data: json(installedFrom: "quantum_courier"), path: "/t/cartridge.json")
        XCTAssertEqual(unknown.installedFrom, .other("quantum_courier"))
        XCTAssertNotEqual(unknown.installedFrom, .bundle)
        // Round-trip: the unknown spelling is preserved verbatim on rewrite.
        let rewritten = unknown.toDictionary()
        XCTAssertEqual(rewritten["installed_from"] as? String, "quantum_courier")
    }
}
