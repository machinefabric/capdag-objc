//
//  CartridgeDeathReportTests.swift
//  Bifaci Tests — what the host says when a cartridge dies on its own.
//
//  A crashing process closes its output before it can be collected, so the
//  host's reader sees the stream end first. The host must wait for the
//  process's real exit rather than ask once, find it still there, and kill
//  it: the death names the cartridge, the read error and how the process
//  ended, and never calls an exited process still running. Mirrors the
//  reference host's TEST13210 and TEST13211.
//
//  The cartridge here is a stub whose process is a real `/bin/sh` that ends
//  a moment after its output "broke", the order a crash has.
//

import XCTest
import Foundation
@testable import Bifaci

final class CartridgeDeathReportTests: XCTestCase {

    /// Start `/bin/sh -c script` as a child the host will collect.
    private func spawnShell(_ script: String) throws -> pid_t {
        var pid: pid_t = 0
        let arguments = ["/bin/sh", "-c", script]
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let result = posix_spawn(&pid, "/bin/sh", nil, nil, argv, environ)
        guard result == 0 else {
            throw NSError(
                domain: "CartridgeDeathReportTests", code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: "posix_spawn /bin/sh: \(String(cString: strerror(result)))"])
        }
        return pid
    }

    /// The death a stub cartridge whose process runs `script` is reported
    /// with, its reader having seen the stream end part way through a frame.
    private func deathAfterBrokenOutput(_ script: String) throws -> String {
        let host = CartridgeHost.withFullPolicy()
        let idx = host.attachStubCartridgeForTest()
        host.setCartridgePidForTest(cartridgeIdx: idx, pid: try spawnShell(script))
        let generation = host.cartridgeProcessStateForTest(cartridgeIdx: idx).generation
        host.handleCartridgeDeathForTest(
            cartridgeIdx: idx,
            generation: generation,
            stream: CartridgeStreamEnd.fromReadError(FrameError.unexpectedEof)
        )
        let message = try XCTUnwrap(host.lastDeathMessageForTest(cartridgeIdx: idx))
        XCTAssertTrue(
            message.contains("reading its output failed: Unexpected end of stream"),
            "the death names the read error the host saw: \(message)")
        XCTAssertFalse(message.contains("still running"), "the process had exited: \(message)")
        return message
    }

    /// TEST13210: a cartridge whose output broke part way through a frame and
    /// that then exits is reported with the read error and its exit code.
    func test13210_aCartridgeThatExitsMidFrameIsReportedWithItsReadErrorAndExitCode() throws {
        let message = try deathAfterBrokenOutput("sleep 0.3; exit 3")
        XCTAssertTrue(message.contains("exited unexpectedly (exit code 3)"), message)
        // Bytes that are not a frame are malformed output, not a broken stream.
        XCTAssertEqual(
            CartridgeStreamEnd.fromReadError(FrameError.decodeError("bad map")),
            .malformed("CBOR decode error: bad map"))
    }

    /// TEST13211: one killed by a signal is reported with the signal.
    func test13211_aCartridgeKilledMidFrameIsReportedWithItsSignal() throws {
        let message = try deathAfterBrokenOutput("sleep 0.3; kill -ABRT $$")
        XCTAssertTrue(message.contains("exited unexpectedly (killed by signal 6 (SIGABRT)"), message)
    }
}
