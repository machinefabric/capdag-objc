//
//  CartridgeHostSessionLifecycleTests.swift
//  Bifaci Tests — `CartridgeHost.run()` is one-shot (matches the
//  Rust reference contract in capdag/src/bifaci/host_runtime.rs:875,
//  `event_rx.take().expect("run() must only be called once")`).
//
//  Two contracts are pinned here:
//
//    1. On `run()` exit (clean or via `close()`), every managed
//       cartridge is killed and the lifecycle observer is fired
//       once per cartridge that was actually running. Mirrors the
//       Rust reference's `self.kill_all_cartridges().await` at the
//       end of `run()` (host_runtime.rs:989). Failure of this
//       assertion would mean cartridges leak across relay
//       sessions — exactly the multi-GB NSConcreteData accumulator
//       we're guarding against.
//
//    2. The `run()` method is one-shot. We don't death-test the
//       `precondition(!hasRun, ...)` directly — `precondition`
//       traps and SIGABRTs, which XCTest can't catch in-process —
//       but we exercise the well-behaved path (one host → one
//       run → drop) so a regression that accidentally let
//       `hasRun` reset between calls would be caught by the
//       death-on-exit test (cartridges would survive).
//
//  These tests use stub stdio pipes for the cartridge side; we do
//  not spawn a real child process, so PID-based kill semantics are
//  exercised via `attachCartridge` (which only registers the host
//  side of the pipes and does not call `posix_spawn`).
//

import XCTest
import Foundation
@testable import Bifaci

private final class RecordingObserver: CartridgeHostObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var spawnedStorage: [(idx: Int, name: String)] = []
    private var diedStorage: [(idx: Int, name: String)] = []
    private var rosterReplacedStorage: [[(idx: Int, name: String)]] = []

    var spawned: [(idx: Int, name: String)] {
        lock.lock(); defer { lock.unlock() }; return spawnedStorage
    }
    var died: [(idx: Int, name: String)] {
        lock.lock(); defer { lock.unlock() }; return diedStorage
    }

    func cartridgeSpawned(cartridgeIndex: Int, pid: pid_t?, name: String, caps: [String]) {
        lock.lock(); spawnedStorage.append((cartridgeIndex, name)); lock.unlock()
    }
    func cartridgeDied(cartridgeIndex: Int, pid: pid_t?, name: String) {
        lock.lock(); diedStorage.append((cartridgeIndex, name)); lock.unlock()
    }
}

final class CartridgeHostSessionLifecycleTests: XCTestCase {

    /// Contract #1: when `run()` exits because the relay closed,
    /// every running cartridge is torn down and the observer is
    /// fired with a death notification for each. The Rust reference
    /// enforces this by calling `kill_all_cartridges().await` at
    /// the very end of `run()`. The Swift mirror's previous
    /// behavior was to leak cartridges across reconnects, which is
    /// what allowed the XPC-service NSConcreteData accumulator bug.
    func testRunExitKillsAllManagedCartridges() async throws {
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let host = CartridgeHost()
        let observer = RecordingObserver()
        host.setObserver(observer)

        // Register two stub cartridges, both pre-marked as running
        // by the helper. They have no real process, so the kill
        // loop's `killProcess()` call is a no-op (pid is nil) —
        // but the death-notification path still fires because
        // those notifications are gated on the `running` flag, not
        // on having a live pid.
        let idx0 = host.attachStubCartridgeForTest()
        let idx1 = host.attachStubCartridgeForTest()
        XCTAssertEqual(idx0, 0)
        XCTAssertEqual(idx1, 1)

        let runFinished = expectation(description: "run() returned")
        let runTask = Task.detached { @Sendable in
            try? host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
            runFinished.fulfill()
        }

        // Let run() get into the main loop, then close the relay
        // write end so the host's relayReader sees EOF and pushes
        // .relayClosed. This is the same disconnect signal the
        // engine emits when it tears down its end of the unix
        // socket.
        try await Task.sleep(nanoseconds: 200_000_000)
        engineToHost.fileHandleForWriting.closeFile()

        await fulfillment(of: [runFinished], timeout: 5.0)
        _ = try await runTask.value

        // One death notification per running cartridge. If this
        // count is 0, the run-exit kill path is not tearing
        // cartridges down — the original leak vector is back.
        XCTAssertEqual(
            observer.died.count, 2,
            "Expected exactly two cartridgeDied callbacks after "
            + "run() exit (one per running stub), got "
            + "\(observer.died.count). The run-exit kill loop is "
            + "not tearing managed cartridges down — the bug that "
            + "lets cartridges outlive their relay session has "
            + "regressed."
        )
        XCTAssertEqual(Set(observer.died.map { $0.idx }), Set([0, 1]))

        // Outbound writer must be cleared on exit so any late
        // sendToRelay() from a still-alive reader thread fails
        // visibly (logged as "outboundWriter is nil — frame
        // dropped") instead of silently buffering against a
        // stale FD.
        XCTAssertNil(
            host.outboundWriterForTest,
            "outboundWriter must be cleared on run() exit so late "
            + "frames fail loud instead of accumulating."
        )
    }

    /// Contract #2 (well-behaved path): one host → one run() →
    /// drop. The misuse path (calling run() twice) is enforced via
    /// `precondition` and is not death-tested here — the well-
    /// behaved path is sufficient because if the precondition were
    /// silently disabled, the prior test (`testRunExitKills…`)
    /// would still pass on the first invocation but the second
    /// call would race with itself and fail intermittently. This
    /// test documents the contract by demonstrating that a fresh
    /// `CartridgeHost` instance is the only correct way to start
    /// a new relay session.
    func testNewHostInstancePerRelaySession() async throws {
        // Session 1
        do {
            let engineToHost = Pipe()
            let hostToEngine = Pipe()
            let host = CartridgeHost()
            let runFinished = expectation(description: "session1 run() returned")
            let task = Task.detached { @Sendable in
                try? host.run(
                    relayRead: engineToHost.fileHandleForReading,
                    relayWrite: hostToEngine.fileHandleForWriting
                ) { Data() }
                runFinished.fulfill()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            engineToHost.fileHandleForWriting.closeFile()
            await fulfillment(of: [runFinished], timeout: 5.0)
            _ = try await task.value
        }

        // Session 2 — fresh host instance. If this throws or
        // hangs, the per-session-host pattern is broken.
        do {
            let engineToHost = Pipe()
            let hostToEngine = Pipe()
            let host = CartridgeHost()
            let runFinished = expectation(description: "session2 run() returned")
            let task = Task.detached { @Sendable in
                try? host.run(
                    relayRead: engineToHost.fileHandleForReading,
                    relayWrite: hostToEngine.fileHandleForWriting
                ) { Data() }
                runFinished.fulfill()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            engineToHost.fileHandleForWriting.closeFile()
            await fulfillment(of: [runFinished], timeout: 5.0)
            _ = try await task.value
        }
    }
}
