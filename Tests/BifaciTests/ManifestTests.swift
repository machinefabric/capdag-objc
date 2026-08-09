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
        let cap = CapDefinition(urn: "cap:test", title: "Test Cap", aliases: ["test"])
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
        XCTAssertEqual(manifest.capGroups[0].caps[0].urn, "cap:test")
    }

    // TEST6411: Author field round-trips through CSCapManifest.withAuthor.
    func test6411_capManifestWithAuthor() throws {
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

    // TEST6412: JSON roundtrip preserves channel and cap_groups.
    func test6412_capManifestJsonRoundtrip() throws {
        let capUrn = "cap:test"
        let cap = CapDefinition(
            urn: capUrn,
            title: "Process",
            aliases: ["process"],
            capDescription: "Roundtrip process cap",
            args: [
                CapArg(
                    mediaUrn: "media:ext=pdf",
                    required: true,
                    sources: [.stdin("media:ext=pdf")]
                ),
                CapArg(
                    mediaUrn: "media:chunk-size;numeric",
                    required: false,
                    sources: [.cliFlag("--chunk-size")],
                    argDescription: "Chunk size",
                    defaultValue: .integer(400)
                ),
                CapArg(
                    mediaUrn: "media:enc=utf-8;timestamps;bool",
                    required: false,
                    sources: [.cliFlag("--timestamps")],
                    argDescription: "Include timestamps",
                    defaultValue: .bool(false)
                ),
                CapArg(
                    mediaUrn: "media:model-config;fmt=json;record",
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
        let processCap = CapDefinition(urn: "cap:process", title: "Process", aliases: ["process"])
        let transformCap = CapDefinition(urn: "cap:in=text:;out=text:", title: "Transform", aliases: ["transform"])
        let convertCap = CapDefinition(urn: "cap:in=image:;out=image:", title: "Convert", aliases: ["convert"])

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

    // TEST6422: CSCapManifest exposes name / version / channel /
    // description / cap_groups via its accessors. The Obj-C bridge is
    // schema-equivalent to the Swift `Manifest` struct.
    func test6422_componentMetadataAccessors() throws {
        let capUrn = try CSCapUrn.fromString("cap:process")
        let cap = CSCap(urn: capUrn, title: "Test", aliases: ["test"])
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

    func test6200_csCapManifestWithPageUrl() throws {
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
    func test6205_csCapManifestRejectsUnknownChannel() {
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

    // MARK: - registryURLFromBuildEnv (TEST1872-1874)

    // TEST1872: `registry_url_from_build_env` passes a non-empty registry URL through unchanged. This is the function that decides the engine's baked PRIMARY registry (surfaced over SystemService.HealthStatus); a published build must report exactly the URL it was compiled with.
    func test1872_registryUrlFromBuildEnvPassesThroughNonempty() throws {
        let url = "https://cartridges.machinefabric.com/manifest"
        XCTAssertEqual(try registryURLFromBuildEnv(url), url)
    }

    // TEST1873: an unset env (None) yields None — a dev build has no baked registry, so the engine reports an empty primary-registry URL and loads only `dev/` cartridges. This is the dev-engine contract the registry sheets rely on to omit the read-only "Primary · built-in" row.
    func test1873_registryUrlFromBuildEnvNoneForDev() throws {
        XCTAssertNil(try registryURLFromBuildEnv(nil))
    }

    // TEST1874: an exported-but-empty env (the empty string) is neither a dev
    // build nor a valid identity and MUST fail hard, so the build can never
    // silently hash the empty string into a fake registry slug. We assert the
    // failure AND its exact message — the catchable Swift analog of Rust's
    // compile-time panic — so a regression that dropped the check (or replaced
    // it with a silent fallback) is caught rather than passing on a bogus empty
    // primary registry.
    func test1874_registryUrlFromBuildEnvRejectsEmptyString() {
        XCTAssertThrowsError(try registryURLFromBuildEnv("")) { error in
            guard let buildEnvError = error as? ManifestBuildEnvError else {
                return XCTFail("expected ManifestBuildEnvError, got \(error)")
            }
            XCTAssertEqual(buildEnvError, .emptyRegistryURL)
            XCTAssertEqual(
                buildEnvError.message,
                "MFR_CARTRIDGE_REGISTRY_URL must be unset for dev builds or set to a non-empty registry URL for published builds; empty string is invalid"
            )
        }
    }

    // TEST7150: a cap's OUTPUT survives a manifest round-trip, under the wire
    // key names the other implementations read.
    func test7150_capOutputSurvivesSerializationRoundtrip() throws {
        let cap = CapDefinition(
            urn: "cap:in=\"media:enc=utf-8;in\";out=\"media:enc=utf-8;tag\";tag",
            title: "tag",
            aliases: ["tag"],
            output: CapOutput(
                mediaUrn: "media:enc=utf-8;tag",
                outputDescription: "One of 'positive', 'neutral', or 'negative'."
            )
        )

        let encoded = try JSONEncoder().encode(cap)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let outputJson = try XCTUnwrap(json["output"] as? [String: Any],
                                       "a cap that declares an output must serialize one")
        XCTAssertEqual(outputJson["media_urn"] as? String, "media:enc=utf-8;tag")
        XCTAssertEqual(outputJson["output_description"] as? String,
                       "One of 'positive', 'neutral', or 'negative'.")

        let back = try JSONDecoder().decode(CapDefinition.self, from: encoded)
        let backOutput = try XCTUnwrap(back.output, "output survives the round-trip")
        XCTAssertEqual(backOutput.mediaUrn, "media:enc=utf-8;tag")
        XCTAssertFalse(backOutput.isSequence)

        // A cap with no output must not carry the key at all.
        let bare = CapDefinition(urn: "cap:effect=none", title: "Identity", aliases: ["identity"])
        let bareJson = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(bare)) as? [String: Any])
        XCTAssertNil(bareJson["output"], "a cap without an output must omit the key")
    }

    // TEST7151: `is_sequence` is serialized even when false, on both CapArg and
    // CapOutput.
    //
    // It is not a `skip_serializing_if` field. Mirrors that omitted it produced
    // a manifest for the identical cap that differed from this one's bytes,
    // which is how a cross-language manifest comparison finds drift that every
    // per-mirror test passes through.
    func test7151_isSequenceIsSerializedEvenWhenFalse() throws {
        let arg = CapArg(
            mediaUrn: "media:enc=utf-8;in",
            required: true,
            sources: [.stdin("media:enc=utf-8;in")]
        )
        let argJson = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(arg)) as? [String: Any])
        XCTAssertEqual(argJson["is_sequence"] as? Bool, false,
                       "CapArg must write is_sequence even when false")

        let output = CapOutput(mediaUrn: "media:enc=utf-8;tag", outputDescription: "a tag")
        let outputJson = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(output)) as? [String: Any])
        XCTAssertEqual(outputJson["is_sequence"] as? Bool, false,
                       "CapOutput must write is_sequence even when false")
    }

    // TEST7152: an empty `adapter_urns` is omitted from a serialized cap group.
    //
    // Most cartridges claim no adapters, so a mirror that wrote `[]` put an
    // extra key in nearly every manifest it produced — invisible to that
    // mirror's own tests, and a difference the moment two languages' manifests
    // for the same cartridge are compared.
    func test7152_emptyAdapterUrnsIsOmitted() throws {
        let group = CapGroup(name: "default", caps: [])
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(group)) as? [String: Any])
        XCTAssertNil(json["adapter_urns"],
                     "an empty adapter_urns must be omitted, not written as []")

        // A group that DOES claim adapters still writes them.
        let claiming = CapGroup(name: "default", caps: [], adapterUrns: ["media:ext=pdf"])
        let claimingJson = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(claiming)) as? [String: Any])
        XCTAssertEqual((claimingJson["adapter_urns"] as? [String])?.count, 1,
                       "a non-empty adapter_urns must be written")
    }
}
