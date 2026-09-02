import Foundation
import XCTest

@testable import Bifaci

/// How a cartridge entry is started, in every language.
///
/// The reference is `capdag-rs/src/bifaci/launch.rs`; these numbers mean the
/// same behaviour in every mirror.
final class LaunchTests: XCTestCase {
    /// TEST7162: a script cartridge is started through its interpreter.
    ///
    /// A scaffolded Python cartridge is `cartridge.py`, and on Unix its
    /// shebang makes it directly executable. Windows has no shebang, so
    /// `CreateProcess` refuses the file outright with `%1 is not a valid Win32
    /// application` — and every caller set `executableURL` to the entry
    /// itself, so all three were wrong there in the same way at once.
    ///
    /// This mirror runs on macOS, where the shebang works. The test is here
    /// because the CONTRACT is shared: a mirror that answered this differently
    /// would scaffold projects the others cannot launch.
    func test7162_a_script_entry_is_launched_through_an_interpreter() {
        let entry = ("proj" as NSString).appendingPathComponent("cartridge.py")
        let (program, leading) = Launch.launcher(entry)
        XCTAssertNotEqual(program, entry, "a .py must not be launched as a program")
        XCTAssertEqual(leading, [entry], "the entry is the interpreter's argument")

        // Case does not decide it.
        XCTAssertNotEqual(Launch.launcher("CARTRIDGE.PY").program, "CARTRIDGE.PY")
    }

    /// TEST7163: a compiled cartridge is started as itself.
    ///
    /// The rule keys on the extension, so it has to leave alone the entries
    /// that already are programs. Running a Rust cartridge's binary through an
    /// interpreter would be a new failure invented by the fix.
    func test7163_a_compiled_entry_runs_itself() {
        let entry = ("target/release" as NSString)
            .appendingPathComponent("mood-tagger" + Launch.executableSuffix)
        let (program, leading) = Launch.launcher(entry)
        XCTAssertEqual(program, entry)
        XCTAssertTrue(leading.isEmpty, "a compiled entry takes no leading arguments")
    }

    /// TEST7164: a compiled entry carries the platform's suffix.
    ///
    /// The stub declares `target/release/<name>` — one string, vendored into
    /// four mirrors, so it cannot carry one platform's spelling.
    func test7164_a_compiled_entry_carries_the_platforms_suffix() {
        #if os(Windows)
        XCTAssertEqual(Launch.executableSuffix, ".exe")
        #else
        XCTAssertEqual(Launch.executableSuffix, "")
        #endif
    }

    /// TEST7165: the entry's own arguments come after the interpreter's.
    ///
    /// The command has to be `python3 cartridge.py manifest` and never
    /// `python3 manifest cartridge.py`, which would ask the interpreter to run
    /// a file called `manifest`.
    func test7165_the_entrys_arguments_follow_it() {
        let entry = ("proj" as NSString).appendingPathComponent("cartridge.py")
        let process = Launch.process(entry, arguments: ["manifest"])
        let argv = process.arguments ?? []
        XCTAssertEqual(argv.last, "manifest")
        XCTAssertTrue(
            argv[argv.count - 2].hasSuffix("cartridge.py"),
            "the entry must precede its own arguments: \(argv)")
    }
}
