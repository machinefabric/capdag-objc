import XCTest
@testable import Bifaci
@testable import CapDAG

// =============================================================================
// Manifest Tests
//
// Covers TEST148-155 from manifest.rs in the reference Rust implementation.
// Tests both the Swift `Manifest` struct (Bifaci runtime) and the
// Objective-C `CSCapManifest` class.
//
// Schema regime: caps live exclusively inside `cap_groups`. There is
// no flat top-level `caps` field. Every manifest carries `channel`
// (release / nightly) — `(name, version, channel)` is the cartridge's
// identity, channels are independent namespaces.
// =============================================================================

final class ManifestTests: XCTestCase {

    private func defaultGroup(_ caps: [CapDefinition]) -> CapGroup {
        CapGroup(name: "default", caps: caps, adapterUrns: [])
    }

    // MARK: - Swift Manifest Tests

    // TEST148: Cap manifest construction stores name, version, channel,
    // description, and the cap_groups verbatim.
    func test148_capManifestCreation() throws {
        let cap = CapDefinition(urn: "cap:in=media:;out=media:", title: "Test Cap", command: "test")
        let manifest = Manifest(
            name: "test-cartridge",
            version: "1.0.0",
            channel: "release",
            registryURL: nil,
            description: "A test cartridge",
            capGroups: [defaultGroup([cap])]
        )

        XCTAssertEqual(manifest.name, "test-cartridge")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.channel, "release")
        XCTAssertEqual(manifest.description, "A test cartridge")
        XCTAssertEqual(manifest.capGroups.count, 1)
        XCTAssertEqual(manifest.capGroups[0].caps.count, 1)
        XCTAssertEqual(manifest.capGroups[0].caps[0].urn, "cap:in=media:;out=media:")
    }

    // TEST149: Author field round-trips through CSCapManifest.withAuthor.
    func test149_capManifestWithAuthor() throws {
        let csManifest = CSCapManifest(
            name: "test-cartridge",
            version: "1.0.0",
            channel: .release,
            registryURL: nil,
            manifestDescription: "A test cartridge",
            capGroups: []
        ).withAuthor("Test Author")

        XCTAssertEqual(csManifest.author, "Test Author")
    }

    // TEST150: JSON roundtrip preserves channel and cap_groups.
    func test150_capManifestJsonRoundtrip() throws {
        let capUrn = "cap:in=media:;out=media:"
        let cap = CapDefinition(
            urn: capUrn,
            title: "Process",
            command: "process",
            capDescription: "Roundtrip process cap",
            args: [
                CapArg(
                    mediaUrn: "media:pdf",
                    required: true,
                    sources: [.stdin("media:pdf")]
                ),
                CapArg(
                    mediaUrn: "media:chunk-size;textable;numeric",
                    required: false,
                    sources: [.cliFlag("--chunk-size")],
                    argDescription: "Chunk size",
                    defaultValue: .integer(400)
                ),
                CapArg(
                    mediaUrn: "media:timestamps;textable;bool",
                    required: false,
                    sources: [.cliFlag("--timestamps")],
                    argDescription: "Include timestamps",
                    defaultValue: .bool(false)
                ),
                CapArg(
                    mediaUrn: "media:model-config;json;record",
                    required: false,
                    sources: [.cliFlag("--model-config")],
                    argDescription: "Model config",
                    defaultValue: .object([
                        "repo": .string("hf:sentence-transformers/all-MiniLM-L6-v2"),
                        "batch": .integer(8)
                    ])
                )
            ]
        )
        let original = Manifest(
            name: "roundtrip-cartridge",
            version: "2.0.0",
            channel: "nightly",
            registryURL: nil,
            description: "Roundtrip test",
            capGroups: [defaultGroup([cap])]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Manifest.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.channel, original.channel)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.capGroups.count, original.capGroups.count)
        XCTAssertEqual(decoded.capGroups[0].caps[0].urn, capUrn)
        XCTAssertEqual(decoded.capGroups[0].caps[0].args.count, 4)
        XCTAssertEqual(decoded.capGroups[0].caps[0].args[1].defaultValue, .integer(400))
        XCTAssertEqual(decoded.capGroups[0].caps[0].args[2].defaultValue, .bool(false))
        XCTAssertEqual(
            decoded.capGroups[0].caps[0].args[3].defaultValue,
            .object([
                "repo": .string("hf:sentence-transformers/all-MiniLM-L6-v2"),
                "batch": .integer(8)
            ])
        )
    }

    // TEST151: Manifest deserialization fails when any required field is
    // missing — including channel, which is part of the cartridge's
    // identity. There is no fallback default; missing means broken.
    func test151_capManifestRequiredFields() throws {
        let decoder = JSONDecoder()

        // Missing "name" field
        let missingName = """
        {"version": "1.0.0", "channel": "release", "description": "test", "cap_groups": []}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(Manifest.self, from: missingName)) { error in
            XCTAssertTrue(error is DecodingError)
        }

        // Missing "version" field
        let missingVersion = """
        {"name": "test", "channel": "release", "description": "test", "cap_groups": []}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(Manifest.self, from: missingVersion)) { error in
            XCTAssertTrue(error is DecodingError)
        }

        // Missing "channel" field
        let missingChannel = """
        {"name": "test", "version": "1.0.0", "description": "test", "cap_groups": []}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(Manifest.self, from: missingChannel)) { error in
            XCTAssertTrue(error is DecodingError)
        }

        // Missing "cap_groups" field
        let missingCapGroups = """
        {"name": "test", "version": "1.0.0", "channel": "release", "description": "test"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(Manifest.self, from: missingCapGroups)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    // TEST152: Multiple caps across multiple cap_groups serialize and
    // deserialize correctly, preserving group structure.
    func test152_capManifestWithMultipleCaps() throws {
        let processCap = CapDefinition(urn: "cap:in=media:;out=media:", title: "Process", command: "process")
        let transformCap = CapDefinition(urn: "cap:in=text:;out=text:", title: "Transform", command: "transform")
        let convertCap = CapDefinition(urn: "cap:in=image:;out=image:", title: "Convert", command: "convert")

        let manifest = Manifest(
            name: "multi-cap-cartridge",
            version: "1.0.0",
            channel: "release",
            registryURL: nil,
            description: "Cartridge with multiple cap groups",
            capGroups: [
                CapGroup(name: "media", caps: [processCap], adapterUrns: ["media:"]),
                CapGroup(name: "content", caps: [transformCap, convertCap], adapterUrns: []),
            ]
        )

        XCTAssertEqual(manifest.capGroups.count, 2)
        XCTAssertEqual(manifest.capGroups[0].name, "media")
        XCTAssertEqual(manifest.capGroups[0].caps.count, 1)
        XCTAssertEqual(manifest.capGroups[1].name, "content")
        XCTAssertEqual(manifest.capGroups[1].caps.count, 2)

        // JSON roundtrip preserves group + cap structure.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(Manifest.self, from: data)

        XCTAssertEqual(decoded.capGroups.count, 2)
        XCTAssertEqual(decoded.capGroups[0].caps.count, 1)
        XCTAssertEqual(decoded.capGroups[1].caps.count, 2)
    }

    // TEST153: An empty cap_groups list round-trips without losing the
    // channel / version envelope.
    func test153_capManifestEmptyCapGroups() throws {
        let manifest = Manifest(
            name: "empty-groups-cartridge",
            version: "1.0.0",
            channel: "nightly",
            registryURL: nil,
            description: "Cartridge with no cap groups",
            capGroups: []
        )

        XCTAssertEqual(manifest.capGroups.count, 0)
        XCTAssertEqual(manifest.channel, "nightly")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(Manifest.self, from: data)

        XCTAssertEqual(decoded.capGroups.count, 0)
        XCTAssertEqual(decoded.channel, "nightly")
    }

    // TEST154: Optional author field on CSCapManifest is nil by default
    // and round-trips through `withAuthor`.
    func test154_capManifestOptionalAuthorField() throws {
        let manifestNoAuthor = CSCapManifest(
            name: "test",
            version: "1.0.0",
            channel: .release,
            registryURL: nil,
            manifestDescription: "test",
            capGroups: []
        )
        XCTAssertNil(manifestNoAuthor.author)

        let manifestWithAuthor = manifestNoAuthor.withAuthor("Author Name")
        XCTAssertEqual(manifestWithAuthor.author, "Author Name")
    }

    // TEST155: CSCapManifest exposes name / version / channel /
    // description / cap_groups via its accessors. The Obj-C bridge is
    // schema-equivalent to the Swift `Manifest` struct.
    func test155_componentMetadataAccessors() throws {
        let capUrn = try CSCapUrn.fromString("cap:in=media:;out=media:")
        let cap = CSCap(urn: capUrn, title: "Test", command: "test")
        let group = CSCapGroup(name: "default", caps: [cap], adapterUrns: [])
        let manifest = CSCapManifest(
            name: "test-component",
            version: "1.0.0",
            channel: .release,
            registryURL: nil,
            manifestDescription: "Test component",
            capGroups: [group]
        )

        XCTAssertEqual(manifest.name, "test-component")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.channel, .release)
        XCTAssertEqual(manifest.manifestDescription, "Test component")
        XCTAssertEqual(manifest.capGroups.count, 1)
        XCTAssertEqual(manifest.capGroups[0].caps.count, 1)
    }

    // MARK: - CSCapManifest With PageUrl Test

    func test_csCapManifestWithPageUrl() throws {
        let manifest = CSCapManifest(
            name: "cartridge-with-url",
            version: "1.0.0",
            channel: .release,
            registryURL: nil,
            manifestDescription: "Cartridge with page URL",
            capGroups: []
        ).withPageUrl("https://example.com/cartridge")

        XCTAssertEqual(manifest.pageUrl, "https://example.com/cartridge")
    }

    // Channel is part of the cartridge's identity; the deserializer
    // accepts the closed enum {release, nightly} only. Anything else
    // is a publish-pipeline bug we want to surface.
    func test_csCapManifestRejectsUnknownChannel() {
        let dict: [String: Any] = [
            "name": "weird-cartridge",
            "version": "1.0.0",
            "channel": "staging",
            "description": "channel value outside the closed enum",
            "cap_groups": [],
        ]
        XCTAssertThrowsError(try CSCapManifest(dictionary: dict),
                             "Manifest with channel='staging' must be rejected")
    }
}
