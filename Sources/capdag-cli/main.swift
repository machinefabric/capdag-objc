// capdag — the Swift/ObjC capdag CLI.
//
// A capdag mirror is not just a library: `capdag new` is how a cartridge
// project comes into existence, and every mirror must be able to create the
// same project. This executable is the Swift mirror's CLI.
//
// # What this binary does and does not do
//
// The commands here are exactly those the Swift library can back today:
//
//     new                  scaffold a cartridge project in any vendored language
//     hash-cartridge-dir   the deterministic content hash of a version directory
//
// `dev-install`, `find`, `resolve` and `cache` need a fabric registry client,
// which this mirror does not have; `run`, single-cap dispatch, `plan` and
// `dag-viz` need the plan executor and the path-planner engine, which it also
// does not have. They are absent rather than stubbed: a command that accepted
// the arguments and then reported "unsupported" would be a worse lie than not
// existing, and `capdag help` says plainly what is missing and why.
//
// In particular `dev-install` is NOT offered without a registry: staging a dev
// cartridge without checking its aliases against the fabric would let a dev cap
// silently shadow a published one, which is the exact failure the check exists
// to prevent.

import Bifaci
import CapDAG
import Foundation

let arguments = CommandLine.arguments

func usage(_ program: String) -> String {
    let p = (program as NSString).lastPathComponent
    return """
    Usage:
      \(p) new <name> <\(stubLanguageFlagList())> [-o <dir>]   Scaffold a new cartridge project
      \(p) hash-cartridge-dir <dir>        Deterministic content hash of a version directory

    Options:
      --help           Show this help

    Not in this mirror: dev-install, find, resolve, cache (they need a fabric
    registry client), and run, single-cap dispatch, plan, dag-viz (they need the
    plan executor and the path-planner engine). The Swift library implements
    none of those yet. Use the reference capdag CLI for them.

    """
}

func die(_ message: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func emit(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - new

func cmdNew(_ args: [String]) -> Never {
    var name: String?
    var language: StubLanguage?
    var parent = "."

    var index = 2
    while index < args.count {
        let arg = args[index]
        if arg == "-o" || arg == "--output" {
            index += 1
            guard index < args.count else { die("--output requires a directory path", 2) }
            parent = args[index]
        } else if let matched = stubLanguage(arg) {
            // Two language flags is not a preference to resolve, it is a
            // command that cannot mean one thing.
            if let already = language {
                die("`new` takes one language: '\(already.flag)' was already given, then '\(arg)'.", 2)
            }
            language = matched
        } else if arg.hasPrefix("--") {
            die("Unknown option '\(arg)' for `new`. Languages: \(stubLanguageFlagList()).", 2)
        } else if name == nil {
            name = arg
        } else {
            die("Unexpected argument '\(arg)' for `new`.", 2)
        }
        index += 1
    }

    guard let name else {
        die("Usage: \((args[0] as NSString).lastPathComponent) new <name> "
            + "<\(stubLanguageFlagList())> [-o <dir>]", 2)
    }
    // No default language. Defaulting would make `capdag new mycart` produce a
    // different project as the stub set grows, and silently pick for someone who
    // simply forgot to say.
    guard let language else {
        die("`new` requires a language: \(stubLanguageFlagList()). "
            + "Each scaffolds the same cartridge, in that language.", 2)
    }

    do {
        let projectDir = try scaffoldCartridge(name: name, language: language, parentDir: parent)
        emit("Scaffolded \(language.display) cartridge '\(name)' at \(projectDir)")
        emit("Next:")
        emit("  cd \(projectDir)")
        for step in language.build {
            emit("  " + step.replacingOccurrences(of: stubPlaceholder, with: name))
        }
        emit("  capdag dev-install .          # install under the local `dev` slug")
        emit("  echo \"I love this\" | capdag \(name)")
        print(projectDir)
        exit(0)
    } catch {
        die("\(error)")
    }
}

// MARK: - hash-cartridge-dir

/// Print the deterministic content hash of a cartridge version directory.
///
/// This is the same walk every host computes at discovery time, so a hash
/// printed here is byte-identical to the one a running engine derives. Never
/// reimplement the walk elsewhere — it would silently drift.
func cmdHashCartridgeDir(_ args: [String]) -> Never {
    guard args.count > 2 else {
        die("Usage: \((args[0] as NSString).lastPathComponent) hash-cartridge-dir <version-dir>", 2)
    }
    do {
        print(try hashCartridgeDirectory(args[2]))
        exit(0)
    } catch {
        die("hash-cartridge-dir: failed to hash '\(args[2])': \(error)")
    }
}

// MARK: - Dispatch

guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data(usage(arguments[0]).utf8))
    exit(1)
}

switch arguments[1] {
case "new":
    cmdNew(arguments)
case "hash-cartridge-dir":
    cmdHashCartridgeDir(arguments)
case "help", "--help", "-h":
    FileHandle.standardError.write(Data(usage(arguments[0]).utf8))
    exit(0)
default:
    // A `.machine` file or a bare cap alias means the caller wants to EXECUTE
    // something, which this mirror cannot do. Saying so — and naming what does —
    // beats "unknown command".
    let token = arguments[1]
    if token.hasSuffix(".machine") || !token.hasPrefix("-") {
        die("""
        \(token): this mirror does not execute machines or caps — it has no plan executor.
        Run it with the reference capdag CLI (the Rust build) instead.
        This binary covers: new, hash-cartridge-dir
        """, 2)
    }
    FileHandle.standardError.write(Data("Unknown option '\(token)'.\n".utf8))
    FileHandle.standardError.write(Data(usage(arguments[0]).utf8))
    exit(2)
}
