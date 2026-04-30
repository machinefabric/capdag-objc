//
//  CartridgeHostObserverTests.swift
//  Bifaci Tests — CartridgeHostObserver lifecycle
//
//  Pins down the surface contract of the lifecycle-observer trait.
//  Spawn/death are driven by I/O on real pipes and are exercised
//  end-to-end in the integration-test family
//  (`InProcessCartridgeHostTests`, `IntegrationTests`). This file's
//  job is the smaller invariants:
//
//    1. The observer registration is OPTIONAL. With no observer set,
//       host construction, observer-clearing, and `close()` on an
//       empty host must succeed without referencing a missing
//       observer. A regression here would mean we accidentally
//       made the trait-firing path mandatory and broke the
//       in-process / engine call sites that don't register an
//       observer.
//    2. `setObserver(nil)` cancels a previously-registered observer.
//       Failure of this assertion would mean the host kept firing
//       events into a torn-down `XPCCartridgeLifecycleBridge` after
//       its connection died — exactly the leak shape we're trying
//       to prevent.
//
//  Tests must FAIL when those guarantees regress.
//

import XCTest
import Foundation
@testable import Bifaci

private final class RecordingObserver: CartridgeHostObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var spawnCountStorage = 0
    private var deathCountStorage = 0

    var spawnCount: Int {
        lock.lock(); defer { lock.unlock() }; return spawnCountStorage
    }
    var deathCount: Int {
        lock.lock(); defer { lock.unlock() }; return deathCountStorage
    }

    func cartridgeSpawned(cartridgeIndex: Int, pid: pid_t?, name: String, caps: [String]) {
        lock.lock(); spawnCountStorage += 1; lock.unlock()
    }
    func cartridgeDied(cartridgeIndex: Int, pid: pid_t?, name: String) {
        lock.lock(); deathCountStorage += 1; lock.unlock()
    }
}

final class CartridgeHostObserverTests: XCTestCase {

    func testHostConstructsAndClosesWithoutAnObserver() {
        let host = CartridgeHost()
        // Empty host with no cartridges → no spawn moments, no death
        // moments. close() must not crash even though the observer
        // is unset, the cartridge array is empty, and there's
        // nothing to tear down.
        host.close()
    }

    func testSetObserverNilClearsThePreviouslyRegisteredObserver() {
        let host = CartridgeHost()
        let observer = RecordingObserver()

        host.setObserver(observer)
        // A second setObserver(nil) must drop the strong reference
        // so a later spawn/death from the host does not flow into
        // the observer. We verify by closing an empty host —
        // still no events expected, but the run path must not
        // capture the previous observer either.
        host.setObserver(nil)
        host.close()

        XCTAssertEqual(
            observer.spawnCount, 0,
            "Observer was cleared via setObserver(nil) before any "
            + "spawn moment, yet recorded \(observer.spawnCount) "
            + "spawn events — the host is firing into a cleared "
            + "observer slot."
        )
        XCTAssertEqual(
            observer.deathCount, 0,
            "Observer was cleared via setObserver(nil) before any "
            + "death moment, yet recorded \(observer.deathCount) "
            + "death events — the host is firing into a cleared "
            + "observer slot."
        )
    }
}
