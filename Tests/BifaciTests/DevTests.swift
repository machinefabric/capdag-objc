import XCTest
@testable import Bifaci

// =============================================================================
// Dev Tests
//
// Covers TEST7154-7160 from `dev.rs` in the reference Rust implementation:
// the `capdag new` / `capdag dev-install` scaffolding and staging path, and the
// local-manifest alias resolution that lets an unpublished cap run.
//
// TEST7153 covers the `installed_at` timestamp format the staging path writes.
// =============================================================================

final class DevTests: XCTestCase {

    private func makeTempDir(_ label: String) throws -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("capdag-dev-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    // TEST7153: `installed_at` is a real RFC3339 UTC timestamp, at known epoch
    // instants and at the instants that break naive date arithmetic — a leap
    // day, the day after one, and a century year that is NOT a leap year.
    // Emitting a bare epoch count with a `Z` appended would satisfy "some string
    // ending in Z" and satisfy nothing else; every reader and every fixture in
    // the tree treats this field as a parseable timestamp.
    func test7153_installTimestampIsRfc3339Utc() throws {
        let cases: [(Int64, String)] = [
            (0, "1970-01-01T00:00:00Z"),
            (1_000_000_000, "2001-09-09T01:46:40Z"),
            // 2024-02-29 — a leap day in a leap year divisible by 4.
            (1_709_164_800, "2024-02-29T00:00:00Z"),
            // The instant after it: the rollover a naive +1 gets wrong.
            (1_709_251_199, "2024-02-29T23:59:59Z"),
            // 2100-03-01 — 2100 is divisible by 100 but not 400, so it has NO
            // Feb 29. A leap rule of "divisible by 4" lands a day early.
            (4_107_542_400, "2100-03-01T00:00:00Z"),
        ]
        for (secs, want) in cases {
            XCTAssertEqual(formatRFC3339UTC(secs), want, "epoch \(secs)")
        }

        // The live producer emits the same shape, and a plausible present
        // instant — a broken epoch-to-civil conversion typically lands in 1970
        // or the far future rather than producing a malformed string.
        let now = installTimestampNow()
        XCTAssertEqual(now.count, 20, "not RFC3339-shaped: \(now)")
        XCTAssertTrue(now.hasSuffix("Z"), "not UTC-marked: \(now)")
        let year = Int(now.prefix(4))
        XCTAssertNotNil(year, "year is not numeric: \(now)")
        XCTAssertTrue(
            (2020..<2200).contains(year ?? 0),
            "the current year came out as \(year ?? 0): \(now)")
    }

    // TEST7154: EVERY vendored language scaffolds a runnable-shaped project —
    // every declared file exists, no placeholder survives anywhere (contents or
    // paths), the manifest/alias/media URNs are seeded from the project name,
    // and the files declared executable are.
    //
    // Iterating the contract rather than testing one language is the point: a
    // newly vendored language is covered the moment it appears, instead of
    // whenever someone remembers to add a test for it.
    func test7154_scaffoldWritesARunnableProjectInEveryLanguage() throws {
        XCTAssertFalse(
            stubLanguageList().isEmpty,
            "the vendored contract must declare at least one language")
        let parent = try makeTempDir("scaffold")
        let fm = FileManager.default

        for language in stubLanguages {
            let name = "mood-tagger-\(language.id)"
            let project = try scaffoldCartridge(
                name: name, language: language, parentDir: parent)
            XCTAssertEqual(project, (parent as NSString).appendingPathComponent(name))

            var sources = ""
            for file in language.files {
                let dest = (project as NSString)
                    .appendingPathComponent(
                        file.dest.replacingOccurrences(of: stubPlaceholder, with: name))
                var isDirectory: ObjCBool = false
                XCTAssertTrue(
                    fm.fileExists(atPath: dest, isDirectory: &isDirectory)
                        && !isDirectory.boolValue,
                    "\(language.id): declared file \(dest) was not written")
                let body = try String(contentsOfFile: dest, encoding: .utf8)
                XCTAssertFalse(
                    body.contains(stubPlaceholder),
                    "\(language.id): \(dest) still contains the placeholder")
                sources += body

                if file.executable {
                    XCTAssertTrue(
                        fm.isExecutableFile(atPath: dest),
                        "\(language.id): \(dest) is declared executable but is not")
                }
            }

            // The rendered entry path must itself be free of the placeholder —
            // a compiled cartridge's binary is named after the project.
            XCTAssertFalse(
                stubEntry(language, name).contains(stubPlaceholder),
                "\(language.id): the entry path was not rendered")

            // The project name reaches the cap it declares, in every language.
            XCTAssertTrue(
                sources.contains("media:enc=utf-8;\(name)-input"),
                "\(language.id): input media URN is not seeded from the project name")
            XCTAssertFalse(
                sources.contains("command="),
                "\(language.id): carries the removed `command=` field")
        }
    }

    // TEST7155: scaffolding rejects a bad name and refuses to overwrite.
    func test7155_scaffoldGuards() throws {
        let parent = try makeTempDir("guards")
        let language = stubLanguages[0]

        XCTAssertThrowsError(
            try scaffoldCartridge(name: "Bad Name", language: language, parentDir: parent)
        ) { error in
            guard case DevError.invalidName = error else {
                return XCTFail("expected invalidName, got \(error)")
            }
        }

        _ = try scaffoldCartridge(name: "greeter", language: language, parentDir: parent)
        XCTAssertThrowsError(
            try scaffoldCartridge(name: "greeter", language: language, parentDir: parent)
        ) { error in
            guard case DevError.alreadyExists = error else {
                return XCTFail("expected alreadyExists, got \(error)")
            }
        }
    }

    /// Write a cartridge entry (a shell script) that prints a canned Manifest on
    /// `manifest`, exercising the capdag-side staging/parsing/resolution without
    /// any language runtime.
    ///
    /// It is written at the PYTHON entry because that is the one language whose
    /// entry is a source file with no build step, so a shell script standing in
    /// for it is discovered by exactly the same path a real project would be.
    @discardableResult
    private func writeStubEntry(
        _ directory: String, name: String, alias: String, capURN: String
    ) throws -> String {
        guard let python = stubLanguage("python") else {
            XCTFail("the contract must cover python")
            throw DevError.io("python missing from the contract")
        }
        let urnJSON = capURN.replacingOccurrences(of: "\"", with: "\\\"")
        let manifest = """
            {"name":"\(name)","version":"0.1.0","channel":"nightly","registry_url":null,\
            "description":"stub","cap_groups":[{"name":"default","caps":[\
            {"urn":"cap:effect=none","title":"Identity","aliases":["identity"]},\
            {"urn":"\(urnJSON)","title":"\(name)","aliases":["\(alias)"]}]}]}
            """
        let script = """
            #!/usr/bin/env bash
            if [ "$1" = manifest ]; then
              cat <<'EOF'
            \(manifest)
            EOF
            fi

            """
        let projectName = (directory as NSString).lastPathComponent
        let path = (directory as NSString)
            .appendingPathComponent(stubEntry(python, projectName))
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: path)
        return path
    }

    // TEST7156: readEntryManifest + stageDevCartridge + findDevCapByAlias
    // round-trip: a stub project installs under dev/v{N}/nightly/<name>/<ver>/,
    // writes a cartridge.json, and its custom cap is resolvable by alias.
    func test7156_devInstallAndFindByAlias() throws {
        let root = try makeTempDir("install")
        let project = (root as NSString).appendingPathComponent("proj")
        try FileManager.default.createDirectory(
            atPath: project, withIntermediateDirectories: true)
        let capURN = #"cap:greet;in="media:enc=utf-8";out="media:enc=utf-8;greeting""#
        try writeStubEntry(project, name: "greeter", alias: "greet", capURN: capURN)

        let userDir = (root as NSString).appendingPathComponent("cartridges")
        let entry = try projectEntry(project)
        let manifest = try readEntryManifest(entry)
        XCTAssertEqual(manifest.name, "greeter")
        XCTAssertNil(manifest.registryURL)

        let versionDir = try stageDevCartridge(
            projectDir: project,
            manifest: manifest,
            userCartridgeDir: userDir,
            registryVersion: 1,
            fabricManifestVersion: 7)
        XCTAssertTrue(
            versionDir.hasSuffix("dev/v1/nightly/greeter/0.1.0"),
            "staged at an unexpected path: \(versionDir)")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: (versionDir as NSString).appendingPathComponent("cartridge.json")))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: (versionDir as NSString)
                    .appendingPathComponent(stubEntry(stubLanguage("python")!, "proj"))))

        let found = try findDevCapByAlias(
            userCartridgeDir: userDir, registryVersion: 1, alias: "greet")
        XCTAssertNotNil(found, "the dev cap must be resolvable by its alias")
        XCTAssertEqual(found?.versionDir, versionDir)
        XCTAssertTrue(found?.cap.hasAlias("greet") ?? false)
    }

    // TEST7157: dev-install refuses a PUBLISHED manifest. `registry_url`
    // non-null means the cartridge belongs to a registry, and staging it under
    // the dev slug would put a published identity in a slot reserved for local
    // work.
    func test7157_devInstallRejectsPublishedManifest() throws {
        let root = try makeTempDir("published")
        let project = (root as NSString).appendingPathComponent("proj")
        try FileManager.default.createDirectory(
            atPath: project, withIntermediateDirectories: true)

        let manifest = Manifest(
            name: "greeter",
            version: "0.1.0",
            channel: "nightly",
            registryURL: "https://cartridges.machinefabric.com/v1/manifest",
            description: "published",
            capGroups: [])

        XCTAssertThrowsError(
            try stageDevCartridge(
                projectDir: project,
                manifest: manifest,
                userCartridgeDir: (root as NSString).appendingPathComponent("cartridges"),
                registryVersion: 1,
                fabricManifestVersion: 7)
        ) { error in
            guard case DevError.notDev = error else {
                return XCTFail("expected notDev, got \(error)")
            }
        }
    }

    // TEST7158: the fabric-conflict guard — a dev cap whose alias the fabric
    // maps to a DIFFERENT cap is rejected; a brand-new alias, and a dev cap that
    // matches an existing fabric cap exactly, are both accepted.
    //
    // The resolver stands in for the fabric's alias table. The reference passes
    // a live FabricRegistry; this mirror takes the lookup as a closure, which is
    // a documented object-level divergence — the guard's behavior is identical,
    // and that is what the shared number asserts.
    func test7158_fabricConflictGuard() throws {
        let alphaURN = #"cap:alpha;in="media:enc=utf-8";out="media:enc=utf-8;alpha""#
        let alpha = CapDefinition(urn: alphaURN, title: "Alpha", aliases: ["alpha"])

        // The fabric knows exactly one alias: `alpha`.
        let resolve: (String) -> String? = { $0 == "alpha" ? alphaURN : nil }

        // A dev cap claiming `alpha` but with a DIFFERENT URN => conflict.
        let clashing = CapDefinition(
            urn: #"cap:beta;in="media:enc=utf-8";out="media:enc=utf-8;beta""#,
            title: "Clash",
            aliases: ["alpha"])
        XCTAssertThrowsError(
            try checkNoFabricConflict(resolveAlias: resolve, cap: clashing)
        ) { error in
            guard case DevError.fabricConflict(let alias, _, _) = error else {
                return XCTFail("expected fabricConflict, got \(error)")
            }
            XCTAssertEqual(alias, "alpha", "the error must name the conflicting alias")
        }

        // A brand-new alias the fabric never heard of => fine.
        let fresh = CapDefinition(
            urn: #"cap:gamma;in="media:enc=utf-8";out="media:enc=utf-8;gamma""#,
            title: "Fresh",
            aliases: ["gamma"])
        XCTAssertNoThrow(try checkNoFabricConflict(resolveAlias: resolve, cap: fresh))

        // The very same fabric cap (same alias => same URN) => not a conflict.
        XCTAssertNoThrow(try checkNoFabricConflict(resolveAlias: resolve, cap: alpha))
    }

    // TEST7159: a project with two languages' entries is REFUSED, not silently
    // resolved. A project is one cartridge; installing whichever entry sorted
    // first would be a coin flip the developer never sees.
    func test7159_twoEntriesIsAmbiguousNotACoinFlip() throws {
        let root = try makeTempDir("ambiguous")
        let project = (root as NSString).appendingPathComponent("twoheaded")
        try FileManager.default.createDirectory(
            atPath: project, withIntermediateDirectories: true)

        var written = 0
        for language in stubLanguages {
            let entry = (project as NSString)
                .appendingPathComponent(stubEntry(language, "twoheaded"))
            try FileManager.default.createDirectory(
                atPath: (entry as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try "#!/usr/bin/env bash\n".write(toFile: entry, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: entry)
            written += 1
            if written == 2 { break }
        }
        XCTAssertEqual(written, 2, "the contract must cover at least two languages")

        XCTAssertThrowsError(try projectEntry(project)) { error in
            guard case DevError.ambiguousEntry = error else {
                return XCTFail("expected ambiguousEntry, got \(error)")
            }
        }
    }

    // TEST7160: the vendored stub contract is IDENTICAL to the reference's.
    //
    // This is the whole promise of `capdag new`: the same command from any
    // capdag binary writes the same project. The vendored copies are generated
    // from one source, so a difference here means a mirror was vendored from a
    // different commit — which would ship two capdags that disagree about what a
    // cartridge looks like, silently.
    func test7160_vendoredStubContractMatchesTheCanonicalSource() throws {
        // Locate the canonical stubs relative to this mirror inside the
        // workspace. Absent (a standalone checkout of capdag-objc), there is
        // nothing to compare against and the vendored copy IS the contract —
        // that is not a skip to hide behind, it is the only meaningful statement
        // available.
        let here = URL(fileURLWithPath: #filePath)  // .../capdag-objc/Tests/BifaciTests/DevTests.swift
        let stubRoot = here
            .deletingLastPathComponent()  // BifaciTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // capdag-objc
            .deletingLastPathComponent()  // machinefabric
            .appendingPathComponent("capdag-stub-cartridges")
        let canonical = stubRoot.appendingPathComponent("stubs.json")
        guard FileManager.default.fileExists(atPath: canonical.path) else {
            throw XCTSkip("canonical stubs not present at \(canonical.path) (standalone checkout)")
        }

        let raw = try Data(contentsOf: canonical)
        guard let contract = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
            let languages = contract["languages"] as? [String: Any]
        else {
            return XCTFail("canonical stubs.json is not the expected object shape")
        }

        XCTAssertEqual(
            contract["contract_version"] as? Int, stubContractVersion,
            "vendored contract version differs from canonical — re-run dx stubs vendor")
        XCTAssertEqual(contract["placeholder"] as? String, stubPlaceholder)
        XCTAssertEqual(
            languages.count, stubLanguages.count,
            "vendored language count differs from canonical — re-run dx stubs vendor")

        for vendored in stubLanguages {
            guard let spec = languages[vendored.id] as? [String: Any] else {
                XCTFail("vendored language \(vendored.id) is not in the canonical contract")
                continue
            }
            XCTAssertEqual(spec["flag"] as? String, vendored.flag)
            XCTAssertEqual(spec["entry"] as? String, vendored.entry)
            guard let declaredFiles = spec["files"] as? [[String: Any]] else {
                XCTFail("\(vendored.id): canonical `files` is not a list of objects")
                continue
            }
            XCTAssertEqual(declaredFiles.count, vendored.files.count, vendored.id)
            for (declared, got) in zip(declaredFiles, vendored.files) {
                guard let source = declared["source"] as? String else {
                    XCTFail("\(vendored.id): a canonical file declares no `source`")
                    continue
                }
                let want = try String(
                    contentsOf: stubRoot.appendingPathComponent(source), encoding: .utf8)
                XCTAssertEqual(got.dest, declared["dest"] as? String)
                XCTAssertEqual(got.executable, declared["executable"] as? Bool)
                XCTAssertEqual(
                    got.contents, want,
                    "\(vendored.id): vendored \(got.dest) differs from the canonical bytes "
                        + "— re-run dx stubs vendor")
            }
        }
    }
}
