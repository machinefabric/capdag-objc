import Foundation

/// How a cartridge entry is started.
///
/// A scaffolded Python cartridge is `cartridge.py`, and on Unix its shebang
/// makes it directly executable. Windows has no shebang: `CreateProcess` — and
/// so every language's `exec` — refuses the file outright with
///
/// ```text
/// %1 is not a valid Win32 application
/// ```
///
/// so `capdag dev-install` could not read a Python project's manifest, and no
/// scaffolded Python cartridge could be launched on that platform at all.
///
/// This mirror runs on macOS, where the shebang works and nothing here is
/// needed to make a cartridge start. It is here because it is the CONTRACT —
/// how any capdag decides what program a given entry is — and a mirror that
/// answered the question differently would be a mirror that scaffolds projects
/// the others cannot launch. The reference is `capdag-rs/src/bifaci/launch.rs`.
public enum Launch {
    /// How an entry that is a SCRIPT is run, by extension.
    ///
    /// Keyed on the extension rather than on the language, because the callers
    /// that need it have a PATH and not a language: `projectEntry` finds an
    /// entry by looking, and what it finds is a filename.
    public static let interpreters: [String: String] = ["py": "python3", "js": "node"]

    /// What a COMPILED entry is called on this platform.
    ///
    /// A scaffolded Rust cartridge declares `target/release/<name>` and Cargo
    /// writes `target/release/<name>.exe`. Looking for the declared spelling
    /// finds nothing on Windows, so a project that had built perfectly reports
    /// that it has no entry.
    public static var executableSuffix: String {
        #if os(Windows)
        return ".exe"
        #else
        return ""
        #endif
    }

    /// The program that runs `entry`, and the arguments that precede the
    /// entry's own.
    ///
    /// A compiled entry runs itself. A script entry runs under the interpreter
    /// its extension names.
    public static func launcher(_ entry: String) -> (program: String, leading: [String]) {
        let suffix = URL(fileURLWithPath: entry).pathExtension.lowercased()
        guard let interpreter = interpreters[suffix] else {
            return (entry, [])
        }
        return (interpreter, [entry])
    }

    /// A `Process` set up to run a cartridge entry with `arguments`.
    ///
    /// One place, so every caller that starts a cartridge — reading a
    /// manifest, probing its caps, hosting it — starts it the same way. They
    /// did not: each set `executableURL` to the entry itself.
    public static func process(_ entry: String, arguments: [String] = []) -> Process {
        let process = Process()
        let (program, leading) = launcher(entry)
        if leading.isEmpty {
            process.executableURL = URL(fileURLWithPath: program)
        } else {
            // A bare interpreter name is resolved against PATH, which
            // `executableURL` does not do.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [program] + leading + arguments
            return process
        }
        process.arguments = arguments
        return process
    }
}
