import XCTest
import Foundation
import CapDAG
@testable import Bifaci

// =============================================================================
// BundleManifest Tests
//
// Mirrors `capdag/src/bifaci/bundle_manifest_tests.rs`: TEST1924, TEST1929,
// TEST1930. This mirror carries no chain verification, so the reference's
// signature tests have no counterpart here; what is tested is what the mirror
// does with a manifest: admit from it, hold a directory to it, and read it.
// =============================================================================

final class BundleManifestTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempRoot() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Lay down a cartridge directory with `contents`, and answer its path.
    private func cartridgeDir(root: String, contents: [(String, String)]) throws -> String {
        let dir = ((root as NSString).appendingPathComponent("cart") as NSString).appendingPathComponent("1.0.0")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Excluded from the hash by `hashCartridgeDirectory`, and present
        // because a real cartridge has one.
        try #"{"name":"cart"}"#.write(
            toFile: (dir as NSString).appendingPathComponent("cartridge.json"), atomically: true, encoding: .utf8
        )
        for (name, body) in contents {
            try body.write(toFile: (dir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }

    /// One entry as a build records it.
    private func entry(_ name: String, _ version: String, _ channel: String, _ sha256: String) -> BundledCartridge {
        BundledCartridge(
            name: name, version: version, channel: channel, sha256: sha256,
            fabricManifestVersion: 1, capGroups: []
        )
    }

    // MARK: - TEST1924

    // TEST1924: a bundled cartridge is held to the bytes the manifest recorded,
    // and the refusal says which cartridge was changed and where.
    //
    // The manifest is built here rather than loaded, because what is under test
    // is the CHECK. The message is what a user reads when a host refuses to
    // start the cartridge, so it must name the cartridge and say that its
    // bundle changed.
    func test1924_aBundledCartridgeMustMatchWhatTheManifestRecorded() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let dir = try cartridgeDir(root: root, contents: [("cart", "the entry point")])
        let recorded = try hashCartridgeDirectory(dir)

        XCTAssertNoThrow(
            try verifyBundledContent(name: "cart", version: "1.0.0", versionDir: dir, recorded: recorded),
            "an unchanged cartridge passes"
        )

        // Changed after the build recorded it.
        try "something else".write(
            toFile: (dir as NSString).appendingPathComponent("cart"), atomically: true, encoding: .utf8
        )
        XCTAssertThrowsError(
            try verifyBundledContent(name: "cart", version: "1.0.0", versionDir: dir, recorded: recorded),
            "a changed cartridge must be refused"
        ) { why in
            guard case let BundleManifestError.contentMismatch(_, _, _, expected, _) = why else {
                return XCTFail("the refusal must be a content mismatch, said: \(why)")
            }
            XCTAssertEqual(expected, recorded, "the refusal must name what was recorded")
            let said = "\(why)"
            XCTAssertTrue(said.contains("the bundled cartridge cart 1.0.0 was changed"), said)
            XCTAssertTrue(said.contains(dir), "the refusal must say where: \(said)")
            XCTAssertTrue(said.contains("is not started"), said)
        }

        // A file added beside the entry point is a change too.
        try "the entry point".write(
            toFile: (dir as NSString).appendingPathComponent("cart"), atomically: true, encoding: .utf8
        )
        XCTAssertNoThrow(
            try verifyBundledContent(name: "cart", version: "1.0.0", versionDir: dir, recorded: recorded),
            "restored, it passes again"
        )
        try "planted".write(
            toFile: (dir as NSString).appendingPathComponent("extra.dylib"), atomically: true, encoding: .utf8
        )
        XCTAssertThrowsError(
            try verifyBundledContent(name: "cart", version: "1.0.0", versionDir: dir, recorded: recorded)
        ) { why in
            guard case BundleManifestError.contentMismatch = why else {
                return XCTFail("a planted file must be a content mismatch, said: \(why)")
            }
        }
    }

    // MARK: - TEST1929

    // TEST1929: the manifest admits exactly the cartridges it records, on the
    // channel it records them for, without reading a byte of them.
    //
    // Admission is what discovery does instead of hashing and starting each
    // cartridge, so it must refuse everything the old check refused that does
    // not need the bytes: a cartridge never recorded, a stale copy of another
    // version, and one recorded for the other channel.
    func test1929_theManifestAdmitsOnlyWhatItRecords() throws {
        let manifest = BundleManifest(
            environment: "prod",
            cartridges: [entry("cart", "1.0.0", "release", String(repeating: "a", count: 64))]
        )

        let admitted = try manifest.admit(name: "cart", version: "1.0.0", channel: "release")
        XCTAssertEqual(admitted.sha256, String(repeating: "a", count: 64))

        XCTAssertThrowsError(try manifest.admit(name: "other", version: "1.0.0", channel: "release")) { why in
            guard case BundleManifestError.notListed = why else { return XCTFail("\(why)") }
        }
        // The right cartridge at the wrong version — a stale copy from an
        // earlier build, which a bare per-binary signature would have accepted
        // because it was validly signed once.
        XCTAssertThrowsError(try manifest.admit(name: "cart", version: "0.9.0", channel: "release")) { why in
            guard case BundleManifestError.notListed = why else { return XCTFail("\(why)") }
        }
        // A manifest vouches for one channel's artefact, never the other's.
        XCTAssertThrowsError(try manifest.admit(name: "cart", version: "1.0.0", channel: "nightly")) { why in
            guard case BundleManifestError.wrongChannel = why else { return XCTFail("\(why)") }
        }

        // A root that proves nothing admits nothing, and says why.
        let none = BundleProof.none("not a build's bundle")
        XCTAssertThrowsError(try none.admit(name: "cart", version: "1.0.0", channel: "release")) { why in
            XCTAssertEqual("\(why)", "not a build's bundle")
        }
    }

    // MARK: - TEST1930

    // TEST1930: a manifest document is believed only in this format, with caps
    // that pass the definition rules.
    //
    // No earlier format is read: a v1 manifest records no caps and no fabric
    // manifest version, so a host reading one would have to start every
    // cartridge to learn them, which is what v2 exists to stop. (The
    // reference also holds the document to the build's signing environment;
    // that check belongs to the chain verification this mirror does not carry.)
    func test1930_aManifestDocumentIsHeldToTheFormatAndTheRules() throws {
        let path = "bundle.json"
        let good = BundleManifest(
            environment: "prod",
            cartridges: [entry("cart", "1.0.0", "release", String(repeating: "a", count: 64))]
        )
        let bytes = try JSONEncoder().encode(good)
        XCTAssertEqual(try parseBundleManifest(bytes, path: path), good, "a v2 manifest parses")

        let v1 = Data(#"{"format":"capdag.bundle/v1","environment":"prod","cartridges":[{"name":"cart","version":"1.0.0","channel":"release","sha256":"aa"}]}"#.utf8)
        XCTAssertThrowsError(try parseBundleManifest(v1, path: path), "a v1 manifest must be refused for its format") { why in
            guard case let BundleManifestError.unsupportedFormat(found) = why else {
                return XCTFail("a v1 manifest must be refused for its format, said: \(why)")
            }
            XCTAssertEqual(found, "capdag.bundle/v1")
        }

        // A recorded cap that breaks the definition rules (RULE21: an out=
        // that is not void needs its main output) is refused as an advertised
        // one would be.
        let brokenCap = CapDefinition(
            urn: #"cap:in="media:enc=utf8";test;out="media:enc=utf8;fmt=json;record""#,
            title: "Test",
            aliases: ["cmd"]
        )
        let broken = BundleManifest(environment: "prod", cartridges: [
            BundledCartridge(
                name: "cart", version: "1.0.0", channel: "release", sha256: String(repeating: "a", count: 64),
                fabricManifestVersion: 1,
                capGroups: [CapGroup(name: "g", caps: [brokenCap], adapterUrns: [])]
            )
        ])
        let brokenBytes = try JSONEncoder().encode(broken)
        XCTAssertThrowsError(
            try parseBundleManifest(brokenBytes, path: path),
            "a recorded cap that fails the definition rules must be refused"
        ) { why in
            guard case BundleManifestError.malformed = why else {
                return XCTFail("a recorded cap that fails the definition rules must be refused as malformed, said: \(why)")
            }
        }
    }
}
