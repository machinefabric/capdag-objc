//
//  CartridgeHostRoutingTableGCTests.swift
//  Bifaci Tests — bounded-routing-table GC contract.
//
//  Pins down two invariants that protect the host's routing
//  tables from unbounded growth:
//
//    1. CAP IS ENFORCED. When the soft watermark is crossed, the
//       GC fires and reduces the table size. After enough GC
//       passes — at most one per insertion — no routing table can
//       exceed the hard cap. Failure of this assertion would mean
//       a cartridge or relay path could create RIDs faster than
//       the cleanup paths drain them and grow the host's memory
//       without bound, the exact regression class we just fixed.
//
//    2. EVICTION IS ORDERED BY `touchedAt`, OLDEST FIRST. A still-
//       active flow (one that has been routed through recently)
//       must NOT be evicted before a stale one. Failure of this
//       assertion would mean a long-running streaming request can
//       have its routing entry dropped while continuations are
//       still arriving, dropping frames silently. The test seeds
//       a deterministic age distribution and verifies that the
//       set of evicted keys equals the set of oldest keys —
//       computed by the test, not by inspecting the production
//       code's choice of victim.
//

import XCTest
import Foundation
@testable import Bifaci

final class CartridgeHostRoutingTableGCTests: XCTestCase {

    /// Contract #1 — the GC keeps the table strictly below the
    /// hard cap. We seed the table well above the soft watermark
    /// (matching what a runaway producer would do mid-frame-burst)
    /// and call the production GC entry point. The post-state
    /// must be at most `softWatermark` entries because the GC
    /// drops at least `evictionFraction × pre-state` entries in
    /// one pass and the pre-state is below `hardCap` (i.e. one
    /// pass is enough; the secondary "hard cap" pass would only
    /// kick in if pre-state crossed the hard cap before insertion
    /// completed, which production prevents by gc-ing on every
    /// insert).
    func testGcReducesTableBelowSoftWatermarkInOnePass() {
        let host = CartridgeHost()
        let preCount = CartridgeHost.routingTableSoftWatermarkForTest + 256
        XCTAssertLessThan(preCount, CartridgeHost.routingTableHardCapForTest,
                          "Test precondition: preCount must stay under the hard cap "
                          + "so we can verify the SOFT watermark path, not the secondary "
                          + "hard-cap pass.")

        // Seed deterministically — touchedAt encodes the insertion
        // order (older keys get smaller values), so we can later
        // compute the expected victim set from first principles.
        for i in 0..<preCount {
            host.seedIncomingRxidForTest(
                key: RxidKey(xid: .uint(UInt64(i)), rid: .uint(UInt64(i))),
                cartridgeIdx: 0,
                touchedAt: UInt64(i)
            )
        }
        let pre = host.routingTableSnapshotForTest()
        XCTAssertEqual(pre.incomingRxids, preCount,
                       "Seeder must populate exactly preCount entries before the GC runs; "
                       + "if it doesn't, every other assertion below is meaningless.")

        host.runRoutingTableGcForTest()

        let post = host.routingTableSnapshotForTest()
        XCTAssertLessThan(
            post.incomingRxids, CartridgeHost.routingTableHardCapForTest,
            "Post-GC table size \(post.incomingRxids) must stay strictly under the hard cap "
            + "(\(CartridgeHost.routingTableHardCapForTest)). If this fires, the GC is not "
            + "evicting enough to recover headroom — the routing table can grow unbounded "
            + "between GC firings and reintroduce the multi-MB-per-session leak."
        )
        XCTAssertEqual(
            post.gcRunsTotal, 1,
            "Exactly one GC pass should have fired. \(post.gcRunsTotal) runs means the "
            + "single-pass invariant has changed and the test's expected-victim "
            + "calculation below is no longer accurate."
        )
        let evictedHere = post.gcEvictedTotal
        let expectedEvicted = max(1, Int(Double(preCount) * CartridgeHost.routingTableGcEvictionFractionForTest))
        XCTAssertEqual(
            Int(evictedHere), expectedEvicted,
            "GC pass evicted \(evictedHere) entries; expected \(expectedEvicted) "
            + "(eviction fraction \(CartridgeHost.routingTableGcEvictionFractionForTest) of "
            + "preCount \(preCount)). If this drifts, the GC's chosen eviction count is no "
            + "longer aligned with the documented contract."
        )
    }

    /// Contract #2 — the GC drops the OLDEST entries by
    /// `touchedAt`, not arbitrary keys. We seed a known age
    /// distribution and recompute the expected victim set
    /// independently of the production code, then assert that
    /// the post-GC table contains exactly the entries the test
    /// computed should survive.
    ///
    /// A regression where the GC e.g. iterates the dictionary and
    /// drops the first N entries (dictionary iteration order is
    /// arbitrary in Swift) would still pass contract #1 but fail
    /// this one — so this is the assertion that catches a "wrong
    /// victims" bug, which is the more dangerous one (silently
    /// drops in-flight continuation frames).
    func testGcEvictsOldestEntriesByTouchedAt() {
        let host = CartridgeHost()
        let preCount = CartridgeHost.routingTableSoftWatermarkForTest + 256
        let evictionCount = max(1, Int(Double(preCount) * CartridgeHost.routingTableGcEvictionFractionForTest))

        // Seed: key i has touchedAt == i. Smallest i means oldest.
        // Expected victim set: keys 0 ..< evictionCount.
        // Expected survivor set: keys evictionCount ..< preCount.
        var allKeys: [RxidKey] = []
        for i in 0..<preCount {
            let key = RxidKey(xid: .uint(UInt64(i)), rid: .uint(UInt64(i)))
            allKeys.append(key)
            host.seedIncomingRxidForTest(
                key: key,
                cartridgeIdx: 0,
                touchedAt: UInt64(i)
            )
        }

        host.runRoutingTableGcForTest()

        // Direct access to the post-GC keyset isn't exposed
        // (we don't want production code to grow accessors that
        // tests rely on but real callers shouldn't have). Instead
        // we re-seed the same table after the GC and check that
        // re-inserting any of the expected-victim keys lands as
        // an INSERT (count goes up by 1), and re-inserting any
        // of the expected-survivor keys lands as an UPDATE (count
        // does NOT go up).
        for i in 0..<evictionCount {
            let key = allKeys[i]
            let before = host.routingTableSnapshotForTest().incomingRxids
            host.seedIncomingRxidForTest(key: key, cartridgeIdx: 0, touchedAt: UInt64(preCount + i))
            let after = host.routingTableSnapshotForTest().incomingRxids
            XCTAssertEqual(
                after, before + 1,
                "Key \(i) should have been evicted (touchedAt=\(i), one of the "
                + "\(evictionCount) oldest), but re-inserting it did not grow the "
                + "table — it must have survived the GC. The eviction-by-age contract "
                + "has regressed; the GC is choosing victims by something other than "
                + "`touchedAt`."
            )
        }
        for i in evictionCount..<preCount {
            let key = allKeys[i]
            let before = host.routingTableSnapshotForTest().incomingRxids
            host.seedIncomingRxidForTest(key: key, cartridgeIdx: 0, touchedAt: UInt64(preCount + i))
            let after = host.routingTableSnapshotForTest().incomingRxids
            XCTAssertEqual(
                after, before,
                "Key \(i) should have survived the GC (touchedAt=\(i), one of the "
                + "\(preCount - evictionCount) most-recently-touched), but re-inserting "
                + "it grew the table — it must have been evicted. The eviction-by-age "
                + "contract has regressed; the GC is dropping fresh entries before stale ones."
            )
        }
    }

    /// Contract #3 — the secondary "hard cap" pass kicks in if
    /// the table somehow exceeds `hardCap` (e.g. a seed that goes
    /// over, simulating an extreme runaway). Without the
    /// secondary pass, a single GC at the soft watermark would
    /// not be enough to recover headroom and the table could
    /// grow without bound between bursts.
    func testGcSecondaryPassEnforcesHardCap() {
        let host = CartridgeHost()
        // Size the seed so a SINGLE eviction-fraction pass is NOT
        // enough to bring the table under the hard cap. We need
        // `pre * (1 - evictionFraction) >= hardCap`, i.e.
        // `pre >= hardCap / (1 - evictionFraction)`. With
        // hardCap=8192, evictionFraction=0.25, that's pre >= 10923.
        // Add an extra 256 of headroom so a small change to the
        // eviction fraction doesn't accidentally make the test
        // pass via the primary pass alone.
        let oneMinusFraction = 1.0 - CartridgeHost.routingTableGcEvictionFractionForTest
        let preCount = Int(ceil(Double(CartridgeHost.routingTableHardCapForTest) / oneMinusFraction)) + 256
        for i in 0..<preCount {
            host.seedIncomingRxidForTest(
                key: RxidKey(xid: .uint(UInt64(i)), rid: .uint(UInt64(i))),
                cartridgeIdx: 0,
                touchedAt: UInt64(i)
            )
        }
        let pre = host.routingTableSnapshotForTest()
        XCTAssertGreaterThanOrEqual(
            pre.incomingRxids, CartridgeHost.routingTableHardCapForTest,
            "Seeder must populate at or above the hard cap so the secondary "
            + "pass actually fires. If this fires the test setup is wrong."
        )

        host.runRoutingTableGcForTest()

        let post = host.routingTableSnapshotForTest()
        XCTAssertLessThan(
            post.incomingRxids, CartridgeHost.routingTableHardCapForTest,
            "Post-GC table size \(post.incomingRxids) must be strictly under the "
            + "hard cap (\(CartridgeHost.routingTableHardCapForTest)). The secondary "
            + "pass exists precisely to catch the case where one eviction-fraction "
            + "pass isn't enough; if this assertion fails, that pass is broken."
        )
        // The secondary pass logs a separate `os_log(.error)` line
        // and uses the same `gcEvictedTotal` counter, but does NOT
        // increment `gcRunsTotal` (only the primary pass does).
        // Verify the eviction count instead — it must exceed what
        // a single primary pass over `preCount` would evict.
        let singlePassMax = UInt64(Double(preCount) * CartridgeHost.routingTableGcEvictionFractionForTest)
        XCTAssertGreaterThan(
            post.gcEvictedTotal, singlePassMax,
            "Total evicted \(post.gcEvictedTotal) should exceed single-pass max "
            + "\(singlePassMax) (the secondary pass must have evicted additional "
            + "entries). If equal, the secondary pass didn't fire."
        )
    }
}
