// Cartridge-development support for the capdag CLI.
//
// This file backs three developer commands and the local-manifest run path:
//
//   - `scaffoldCartridge` — `capdag new <name> --<language>`: write a fresh,
//     runnable cartridge project (one custom cap, one Op that peer-calls a
//     model, one manifest) into a new directory, in any language the vendored
//     canonical stubs cover. The stubs are the SAME bytes in every capdag
//     implementation (see StubsGenerated.swift), so the project you get does not
//     depend on which capdag binary you ran.
//   - `stageDevCartridge` — `capdag dev-install <project-dir>`: read the
//     project's manifest, then copy it under the per-user cartridge root's
//     reserved `dev` slug so the capdag host discovers it. Re-running overwrites
//     the same version directory — the update step of the edit/reinstall loop.
//   - `findDevCapByAlias` + `checkNoFabricConflict` — the local-manifest run
//     path: when `capdag <alias>` names a cap the fabric does NOT define, a
//     locally dev-installed cartridge's OWN manifest answers it, as long as the
//     cap does not conflict with the fabric. A dev cap never needs to be
//     published to be developed and run locally.
//
// The on-disk layout mirrors every other host exactly:
// {userCartridgeDir}/dev/v{registryVersion}/{channel}/{name}/{version}/
//
// Mirrors the reference implementation in capdag/src/dev.rs.

import CapDAG
import Foundation

// MARK: - Errors
//
// Each names the file, entry or conflicting alias so a developer can act on it
// without reproducing the failure.

public enum DevError: Error, CustomStringConvertible {
    case invalidName(String)
    case alreadyExists(String)
    case noEntry(project: String, candidates: String)
    case ambiguousEntry(project: String, found: [String])
    case notDev(registryURL: String)
    case fabricConflict(alias: String, devURN: String, fabricURN: String)
    case io(String)
    case manifestSpawn(entry: String, reason: String)
    case manifestFailed(entry: String, code: Int32, stderr: String)
    case manifestParse(entry: String, reason: String)

    public var description: String {
        switch self {
        case .invalidName(let name):
            return "invalid cartridge name '\(name)': use a lowercase, path-safe name matching "
                + "[a-z0-9] with '-' or '_' separators (e.g. sentiment-tagger)"
        case .alreadyExists(let path):
            return "'\(path)' already exists — pick a new name or remove it first"
        case .noEntry(let project, let candidates):
            return "no cartridge entry found in '\(project)'. Looked for \(candidates). "
                + "A compiled cartridge must be BUILT before it is installed — the host "
                + "launches the binary, not the sources. Create the project with `capdag new`."
        case .ambiguousEntry(let project, let found):
            return "'\(project)' contains more than one cartridge entry "
                + "(\(found.joined(separator: ", "))) — capdag cannot tell which one to "
                + "install. A project is ONE cartridge; remove the build outputs of the "
                + "language you are not developing."
        case .notDev(let registryURL):
            return "this project's manifest declares registry_url '\(registryURL)', so it is a "
                + "PUBLISHED cartridge, not a dev one. `dev-install` stages only dev "
                + "cartridges (registry_url null)."
        case .fabricConflict(let alias, let devURN, let fabricURN):
            return "the dev cap '\(devURN)' claims alias '\(alias)', which the fabric already "
                + "resolves to '\(fabricURN)'. Rename the dev cap's alias — a dev cartridge "
                + "may not shadow a published cap."
        case .io(let message):
            return message
        case .manifestSpawn(let entry, let reason):
            return "could not run the cartridge entry '\(entry)' to read its manifest: \(reason). "
                + "Make sure it is executable and its dependencies are importable."
        case .manifestFailed(let entry, let code, let stderr):
            return "the cartridge entry '\(entry)' exited \(code) when asked for its manifest: \(stderr)"
        case .manifestParse(let entry, let reason):
            return "the cartridge entry '\(entry)' printed a manifest capdag cannot parse: \(reason)"
        }
    }
}

// MARK: - The vendored stub contract

/// Every language `capdag new` can scaffold, in contract order.
///
/// A mirror that offered a subset would silently make `capdag new --rust` mean
/// different things depending on which capdag binary you happened to run.
public func stubLanguageList() -> [StubLanguage] { stubLanguages }

/// Look a language up by its id (`python`) or its flag (`--python`).
///
/// Returns nil for anything else; the caller turns that into an error that
/// lists what IS available, which is the only useful thing to say.
public func stubLanguage(_ selector: String) -> StubLanguage? {
    stubLanguages.first { $0.id == selector || $0.flag == selector }
}

/// The scaffoldable flags, for usage and error messages. Built from the contract
/// so a newly vendored language appears everywhere at once rather than in
/// whichever message someone remembered to update.
public func stubLanguageFlagList() -> String {
    stubLanguages.map { $0.flag }.joined(separator: " | ")
}

/// Substitute the project name into a stub's text.
///
/// The placeholder appears in file CONTENTS, in destination PATHS, and in the
/// entry — a compiled cartridge's binary is named after the project — so one
/// function serves all three rather than three call sites each remembering.
func renderStub(_ template: String, _ name: String) -> String {
    template.replacingOccurrences(of: stubPlaceholder, with: name)
}

/// The executable the host launches, relative to the project directory.
public func stubEntry(_ language: StubLanguage, _ name: String) -> String {
    renderStub(language.entry, name)
}

/// Whether a name is safe as a directory, a cap alias and a media-URN fragment
/// all at once.
public func validCartridgeName(_ name: String) -> Bool {
    guard let first = name.first else { return false }
    let isLower = { (c: Character) in c.isASCII && c.isLowercase && c.isLetter }
    let isDigit = { (c: Character) in c.isASCII && c.isNumber }
    guard isLower(first) || isDigit(first) else { return false }
    return name.allSatisfy { isLower($0) || isDigit($0) || $0 == "-" || $0 == "_" }
}

// MARK: - new — scaffold a project

/// Write a new cartridge project named `name` under `parentDir`, in `language`,
/// returning the created project directory.
///
/// Fails hard if the name is not path-safe or the target already exists — never
/// overwrites existing work, and never half-writes: a failure part-way names the
/// exact file it could not write.
public func scaffoldCartridge(
    name: String,
    language: StubLanguage,
    parentDir: String
) throws -> String {
    guard validCartridgeName(name) else { throw DevError.invalidName(name) }
    let fm = FileManager.default
    let projectDir = (parentDir as NSString).appendingPathComponent(name)
    if fm.fileExists(atPath: projectDir) { throw DevError.alreadyExists(projectDir) }

    do {
        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
    } catch {
        throw DevError.io("creating project dir '\(projectDir)': \(error)")
    }

    for file in language.files {
        let dest = (projectDir as NSString).appendingPathComponent(renderStub(file.dest, name))
        let parent = (dest as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try renderStub(file.contents, name).write(toFile: dest, atomically: true, encoding: .utf8)
        } catch {
            throw DevError.io("writing '\(dest)': \(error)")
        }
        if file.executable {
            try makeExecutable(dest)
        }
    }
    return projectDir
}

func makeExecutable(_ path: String) throws {
    let fm = FileManager.default
    let attributes = (try? fm.attributesOfItem(atPath: path)) ?? [:]
    let current = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
    do {
        try fm.setAttributes([.posixPermissions: NSNumber(value: current | 0o111)], ofItemAtPath: path)
    } catch {
        throw DevError.io("chmod +x '\(path)': \(error)")
    }
}

// MARK: - Entry discovery

/// The name a scaffolded directory carries: its own directory name.
///
/// `capdag new <name>` creates <parent>/<name> and every rendered path is seeded
/// from that name, so the directory IS the name. Reading it back is how
/// dev-install knows what a compiled entry is called without being told.
func projectName(_ projectDir: String) -> String {
    ((projectDir as NSString).standardizingPath as NSString).lastPathComponent
}

/// Name every entry path that WOULD have been accepted, turning "no entry found"
/// into an instruction.
func stubEntryCandidatesDescription(_ projectDir: String) -> String {
    let name = projectName(projectDir)
    return stubLanguages.map { "\(stubEntry($0, name)) (\($0.display))" }.joined(separator: ", ")
}

/// The project's entry, discovered across every scaffoldable language and
/// verified to exist.
///
/// A project is ONE cartridge, so finding two entries is an error rather than a
/// silent pick: installing whichever language happened to sort first would be a
/// coin flip the developer never sees.
public func projectEntry(_ projectDir: String) throws -> String {
    let fm = FileManager.default
    let name = projectName(projectDir)
    var found: [String] = []
    for language in stubLanguages {
        let candidate = (projectDir as NSString).appendingPathComponent(stubEntry(language, name))
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue {
            found.append(candidate)
        }
    }
    switch found.count {
    case 1: return found[0]
    case 0:
        throw DevError.noEntry(
            project: projectDir, candidates: stubEntryCandidatesDescription(projectDir))
    default:
        throw DevError.ambiguousEntry(project: projectDir, found: found)
    }
}

// MARK: - Reading a project's manifest

/// Run a cartridge entry's `manifest` subcommand and parse the printed Manifest.
///
/// Every cartridge in every language prints the same wire shape, which is what
/// lets capdag read a Go project's manifest from Swift without knowing or caring
/// which language wrote it.
public func readEntryManifest(_ entry: String) throws -> Manifest {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: entry)
    process.arguments = ["manifest"]
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        throw DevError.manifestSpawn(entry: entry, reason: "\(error)")
    }
    let out = stdout.fileHandleForReading.readDataToEndOfFile()
    let err = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw DevError.manifestFailed(
            entry: entry,
            code: process.terminationStatus,
            stderr: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    do {
        return try JSONDecoder().decode(Manifest.self, from: out)
    } catch {
        throw DevError.manifestParse(entry: entry, reason: "\(error)")
    }
}

// MARK: - dev-install — stage a project under the `dev` slug

/// `dev/v{registryVersion}/{channel}/{name}/{version}/` under the root.
public func devVersionDir(
    userCartridgeDir: String,
    registryVersion: UInt32,
    channel: String,
    name: String,
    version: String
) -> String {
    var path = userCartridgeDir as NSString
    for component in [cartridgeDevSlug, "v\(registryVersion)", channel, name, version] {
        path = path.appendingPathComponent(component) as NSString
    }
    return path as String
}

/// Project entries the install copy skips.
///
/// Developer scratch, plus build trees: a compiled cartridge's intermediates are
/// gigabytes of object files and dependency sources the host never reads — only
/// the linked entry matters, and `stageDevCartridge` copies that explicitly
/// after the walk.
private let ignoredProjectEntries: Set<String> = [
    ".venv", "__pycache__", ".git", ".pytest_cache", "cartridge.json",
    "target", ".build", ".swiftpm", "node_modules",
]

func isIgnoredProjectEntry(_ name: String) -> Bool {
    ignoredProjectEntries.contains(name) || name.hasSuffix(".pyc")
}

func copyProjectTree(from src: String, to dst: String) throws {
    let fm = FileManager.default
    let names: [String]
    do {
        names = try fm.contentsOfDirectory(atPath: src).sorted()
    } catch {
        throw DevError.io("reading project dir '\(src)': \(error)")
    }
    for name in names where !isIgnoredProjectEntry(name) {
        let srcPath = (src as NSString).appendingPathComponent(name)
        let dstPath = (dst as NSString).appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: srcPath, isDirectory: &isDirectory) else { continue }
        if isDirectory.boolValue {
            do {
                try fm.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
            } catch {
                throw DevError.io("creating '\(dstPath)': \(error)")
            }
            try copyProjectTree(from: srcPath, to: dstPath)
        } else {
            do {
                if fm.fileExists(atPath: dstPath) { try fm.removeItem(atPath: dstPath) }
                try fm.copyItem(atPath: srcPath, toPath: dstPath)
            } catch {
                throw DevError.io("copying '\(srcPath)': \(error)")
            }
        }
    }
}

/// Copy a project under the per-user cartridge root's `dev` slug and write its
/// cartridge.json, returning the version directory.
///
/// `manifest` must already have been read from the project (via
/// `readEntryManifest`) and is verified here to be a dev cartridge (registry_url
/// null); this staging step does not itself re-run the entry.
public func stageDevCartridge(
    projectDir: String,
    manifest: Manifest,
    userCartridgeDir: String,
    registryVersion: UInt32,
    fabricManifestVersion: UInt32
) throws -> String {
    if let url = manifest.registryURL {
        throw DevError.notDev(registryURL: url)
    }
    let fm = FileManager.default
    let versionDir = devVersionDir(
        userCartridgeDir: userCartridgeDir,
        registryVersion: registryVersion,
        channel: manifest.channel,
        name: manifest.name,
        version: manifest.version)

    // The entry is discovered in the PROJECT, then recorded relative to the
    // install — a compiled cartridge's entry lives under its build directory
    // (.build/release/<name>), and the two are the same relative path.
    let entryPath = try projectEntry(projectDir)
    let projectPrefix = (projectDir as NSString).standardizingPath
    guard entryPath.hasPrefix(projectPrefix) || entryPath.hasPrefix(projectDir) else {
        throw DevError.io("the discovered entry '\(entryPath)' is not inside '\(projectDir)'")
    }
    let base = entryPath.hasPrefix(projectDir) ? projectDir : projectPrefix
    var relativeEntry = String(entryPath.dropFirst(base.count))
    while relativeEntry.hasPrefix("/") { relativeEntry.removeFirst() }

    // Update semantics: replace the version directory wholesale so a removed
    // file in the project does not linger in a stale install.
    if fm.fileExists(atPath: versionDir) {
        do {
            try fm.removeItem(atPath: versionDir)
        } catch {
            throw DevError.io("clearing old install '\(versionDir)': \(error)")
        }
    }
    do {
        try fm.createDirectory(atPath: versionDir, withIntermediateDirectories: true)
    } catch {
        throw DevError.io("creating '\(versionDir)': \(error)")
    }

    try copyProjectTree(from: projectDir, to: versionDir)

    // The entry is copied explicitly because a compiled one lives INSIDE a build
    // tree the walk above deliberately skips. Doing it here rather than
    // exempting the whole tree keeps the install to the sources plus the one
    // binary the host actually launches.
    let installedEntry = (versionDir as NSString).appendingPathComponent(relativeEntry)
    if !fm.fileExists(atPath: installedEntry) {
        let parent = (installedEntry as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try fm.copyItem(atPath: entryPath, toPath: installedEntry)
        } catch {
            throw DevError.io("copying the cartridge entry into the install: \(error)")
        }
    }
    try makeExecutable(installedEntry)

    guard let channel = CartridgeChannel.from(manifest.channel) else {
        throw DevError.io(
            "the manifest declares channel '\(manifest.channel)', which is neither "
            + "'release' nor 'nightly'")
    }
    let cj = CartridgeJson(
        name: manifest.name,
        version: manifest.version,
        channel: channel,
        registryURL: nil,
        entry: relativeEntry,
        installedAt: installTimestampNow(),
        installedFrom: .dev,
        fabricManifestVersion: fabricManifestVersion)
    do {
        try cj.writeToDir(versionDir)
    } catch {
        throw DevError.io("writing cartridge.json: \(error)")
    }

    return versionDir
}

// MARK: - The local-manifest run path

/// Search every dev-installed cartridge's own manifest for a cap carrying
/// `alias`, returning the cap and its version directory.
///
/// Returns nil when no dev cartridge claims the alias — an ordinary outcome, not
/// an error: the caller then reports the alias as unknown to both the fabric and
/// the dev slug.
public func findDevCapByAlias(
    userCartridgeDir: String,
    registryVersion: UInt32,
    alias: String
) throws -> (cap: CapDefinition, versionDir: String)? {
    let devRoot = ((userCartridgeDir as NSString).appendingPathComponent(cartridgeDevSlug)
        as NSString).appendingPathComponent("v\(registryVersion)")
    let fm = FileManager.default

    for versionDir in walkVersionDirs(devRoot) {
        // A version directory with no cartridge.json is not an install — it is a
        // leftover directory. Skipping it is not a fallback: the reader
        // distinguishes "absent" from "unreadable", and only the latter is worth
        // stopping the whole lookup for.
        let cartridgeJson = (versionDir as NSString).appendingPathComponent("cartridge.json")
        guard fm.fileExists(atPath: cartridgeJson) else { continue }

        let cj: CartridgeJson
        do {
            cj = try CartridgeJson.readFromDir(versionDir, expectedSlug: cartridgeDevSlug)
        } catch {
            throw DevError.io(
                "the dev install at '\(versionDir)' has an unreadable cartridge.json: \(error)")
        }
        let manifest = try readEntryManifest(cj.resolveEntryPoint(versionDir))
        for group in manifest.capGroups {
            for cap in group.caps where cap.hasAlias(alias) {
                return (cap, versionDir)
            }
        }
    }
    return nil
}

/// Every `{channel}/{name}/{version}/` directory under a dev root.
///
/// A missing root is not an error — nothing has been dev-installed yet.
func walkVersionDirs(_ devRoot: String) -> [String] {
    var out: [String] = []
    for channel in readSubdirs(devRoot) {
        for name in readSubdirs(channel) {
            out.append(contentsOf: readSubdirs(name))
        }
    }
    return out.sorted()
}

func readSubdirs(_ directory: String) -> [String] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
    return names.sorted().compactMap { name in
        let path = (directory as NSString).appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return path
    }
}

/// Refuse a dev cap whose alias already means a DIFFERENT cap in the fabric.
///
/// A dev cap providing the same fabric cap (e.g. identity) is not a conflict —
/// the comparison is on canonical URNs, not on the alias alone.
public func checkNoFabricConflict(
    resolveAlias: (String) -> String?,
    cap: CapDefinition
) throws {
    // Compare CANONICAL URNs: the fabric records an alias target as whatever
    // string the publisher wrote, and two spellings of the same cap must not
    // read as a conflict. An unparseable target is compared verbatim — that is
    // the only honest reading of a string capdag cannot interpret, and it still
    // catches the case the guard exists for.
    let devURN = (try? CSCapUrn.fromString(cap.urn))?.toString() ?? cap.urn
    for alias in cap.aliases {
        guard let target = resolveAlias(alias) else {
            // The fabric does not define this alias — nothing to conflict with.
            continue
        }
        let fabricURN = (try? CSCapUrn.fromString(target))?.toString() ?? target
        if fabricURN != devURN {
            throw DevError.fabricConflict(alias: alias, devURN: devURN, fabricURN: fabricURN)
        }
    }
}
