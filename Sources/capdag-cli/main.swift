// capdag — the Swift/ObjC capdag CLI.
//
// A capdag mirror is not just a library: `capdag dev new` is how a cartridge
// project comes into existence, and every mirror must be able to create the
// same project. This executable is the Swift mirror's CLI.
//
// # What this binary does and does not do
//
// The commands here are exactly those the Swift library can back today, named
// and shaped as the reference capdag CLI names them:
//
//     dev new <path> --lang <language>   start a cartridge project in any vendored language
//     dev hash-dir <dir>                 the deterministic content hash of a version directory
//
// `info`, `cache` and `dev install` need a fabric registry client, which this
// mirror does not have; `run`, `plan`, `caps`, `check` and `graph` need the plan
// executor and the path-planner engine, which it also does not have. They are
// absent rather than stubbed: a command that accepted the arguments and then
// reported "unsupported" would be a worse lie than not existing.
//
// In particular `dev install` is NOT offered without a registry: staging a dev
// cartridge without checking its aliases against the fabric would let a dev cap
// silently shadow a published one, which is the exact failure the check exists
// to prevent.

import Bifaci
import CapDAG
import Foundation

/// What went wrong, said as the reference CLI says it: the problem, what was
/// expected and found, and what to type next.
struct CliError: Error {
    let problem: String
    var context: [String] = []
    var hint: String?
    var exit: Int32 = 1

    func render() -> String {
        var out = "error: \(problem)\n"
        for line in context { out += "  \(line)\n" }
        if let hint { out += "hint: \(hint)\n" }
        return out
    }
}

func usage(_ problem: String, hint: String, context: [String] = []) -> CliError {
    CliError(problem: problem, context: context, hint: hint, exit: 2)
}

let help = """
The Swift capdag CLI: cartridge development.

Usage: capdag [--json] dev <command>

Commands:
  dev new <path> --lang <language>   start a cartridge project

Examples:
  capdag dev new sentiment --lang swift

This mirror has no fabric registry client and no plan executor: info, cache,
dev install, run, plan, caps, check and graph are the reference capdag's.

"""

func say(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func emit(_ record: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func languageIds() -> String {
    stubLanguageList().map { $0.id }.joined(separator: ", ")
}

// MARK: - dev new

func devNew(_ args: [String], json: Bool) throws {
    var path: String?
    var lang: String?
    var index = 0
    while index < args.count {
        let arg = args[index]
        if arg == "--lang" {
            index += 1
            guard index < args.count else { throw usage("--lang needs a language", hint: "languages: \(languageIds())") }
            lang = args[index]
        } else if arg.hasPrefix("-") {
            throw usage("dev new has no option '\(arg)'", hint: "capdag dev new <path> --lang <language>")
        } else if path == nil {
            path = arg
        } else {
            throw usage("dev new takes one path, and was also given '\(arg)'", hint: "capdag dev new <path> --lang <language>")
        }
        index += 1
    }
    guard let path else {
        throw usage("dev new needs the path of the project to make", hint: "capdag dev new <path> --lang <language>")
    }
    // No default language: a default would make one command mean different
    // projects as the stub set grows.
    guard let lang, let language = stubLanguageList().first(where: { $0.id == lang }) else {
        throw usage("'\(lang ?? "")' is not a language capdag scaffolds", hint: "languages: \(languageIds())")
    }
    let name = (path as NSString).lastPathComponent
    let parent = (path as NSString).deletingLastPathComponent
    let projectDir: String
    do {
        projectDir = try scaffoldCartridge(name: name, language: language, parentDir: parent.isEmpty ? "." : parent)
    } catch {
        throw CliError(problem: "the project \(path) could not be made", context: ["\(error)"])
    }
    if json {
        try emit(["type": "project", "dir": projectDir, "language": language.id])
        return
    }
    say("Made the \(language.display) cartridge '\(name)' at \(projectDir)")
    say("Next:")
    say("  cd \(projectDir)")
    for step in language.build {
        say("  " + step.replacingOccurrences(of: stubPlaceholder, with: name))
    }
    say("  capdag dev install")
    say("  echo \"I love this\" | capdag run \(name)")
    print(projectDir)
}

// MARK: - dev hash-dir

/// Print the deterministic content hash of a cartridge version directory: the
/// walk every host computes at discovery time, byte-identical to it.
func devHashDir(_ args: [String]) throws {
    guard args.count == 1 else {
        throw usage("dev hash-dir takes one directory", hint: "capdag dev hash-dir <version-dir>")
    }
    do {
        print(try hashCartridgeDirectory(args[0]))
    } catch {
        throw CliError(problem: "\(args[0]) could not be hashed", context: ["\(error)"])
    }
}

// MARK: - Dispatch

var arguments = Array(CommandLine.arguments.dropFirst())
let json = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }

do {
    switch (arguments.first, arguments.dropFirst().first) {
    case ("help", _), ("--help", _), ("-h", _):
        print(help, terminator: "")
    case ("dev", "new"):
        try devNew(Array(arguments.dropFirst(2)), json: json)
    case ("dev", "hash-dir"):
        try devHashDir(Array(arguments.dropFirst(2)))
    case (nil, _):
        FileHandle.standardError.write(Data(help.utf8))
        throw usage("no command was given", hint: "capdag --help lists them")
    case ("dev", let other):
        throw usage("there is no command `capdag dev \(other ?? "")` in this mirror", hint: "this binary covers: dev new, dev hash-dir")
    case (let other?, _):
        throw usage(
            "there is no command `\(other)` in this mirror",
            hint: "info, cache, dev install, run, plan, caps, check and graph are the reference capdag's (the Rust build)",
            context: ["this binary covers: dev new, dev hash-dir"]
        )
    }
} catch let error as CliError {
    if json {
        try? emit(["type": "error", "problem": error.problem, "context": error.context, "hint": error.hint ?? NSNull(), "exit": error.exit])
    }
    FileHandle.standardError.write(Data(error.render().utf8))
    exit(error.exit)
} catch {
    FileHandle.standardError.write(Data(CliError(problem: "\(error)").render().utf8))
    exit(1)
}
