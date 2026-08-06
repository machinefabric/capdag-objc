import XCTest
@testable import Bifaci

// =============================================================================
// Host-side drop classification (mirrors Rust TEST8116/TEST8117)
//
// The host discriminates the two ways a frame can arrive with no routing
// entry: a RID released by an OBSERVED terminal is a BENIGN post-terminal
// straggler (the ordinary teardown race of credit-based flow control —
// counted per frame type, never a drop); a RID this host never routed is a
// genuine `no_route` DROP. Both are counted (L8) — never errors, never
// silent, never conflated.
// =============================================================================

final class CartridgeHostDropClassificationTests: XCTestCase {

    // TEST8116: the terminal-release ring discriminates and stays bounded —
    // released rids classify as benign-straggler material, unknown rids do not,
    // duplicates collapse, and eviction past the cap ages a rid back out.
    func test8116_releasedRidRingDiscriminatesDedupesAndAgesOut() {
        let host = CartridgeHost()
        let rid = MessageId.uint(7)

        XCTAssertFalse(host.recentlyReleasedRidLocked(rid), "nothing released yet")
        host.noteReleasedRidLocked(rid)
        host.noteReleasedRidLocked(rid) // duplicate must collapse
        XCTAssertTrue(host.recentlyReleasedRidLocked(rid))
        XCTAssertEqual(
            host.recentReleasedRids.count, 1,
            "duplicate releases collapse to one ring entry"
        )
        XCTAssertFalse(
            host.recentlyReleasedRidLocked(.uint(9999)),
            "a rid never released here is a genuine anomaly"
        )

        for n in 100..<(100 + CartridgeHost.recentReleasedRidsCap) {
            host.noteReleasedRidLocked(.uint(UInt64(n)))
        }
        XCTAssertFalse(
            host.recentlyReleasedRidLocked(rid),
            "eviction past recentReleasedRidsCap ends benign-straggler classification"
        )
        XCTAssertEqual(
            host.recentReleasedRids.count, CartridgeHost.recentReleasedRidsCap,
            "the ring is bounded"
        )
    }

    // TEST8117: an unroutable continuation from the relay is classified by
    // the release ring — a rid a terminal just released is a BENIGN
    // straggler (counted per frame type, never a drop); a rid this host
    // never routed is a genuine no_route DROP. The same law covers
    // unroutable LOG frames: counted, never silent, never conflated.
    func test8117_unroutableContinuationClassifiedByReleaseRing() {
        let host = CartridgeHost()

        // Unknown rid: no routing entry, nothing released → no_route.
        var unknown = Frame(frameType: .chunk, id: .uint(41))
        unknown.routingId = .uint(4)
        unknown.streamId = "s"
        unknown.chunkIndex = 0
        unknown.checksum = 0
        host.handleRelayFrameForTest(unknown)
        XCTAssertEqual(host.drops.get(.noRoute), 1, "a rid never routed here is a routing anomaly")
        XCTAssertEqual(host.stragglers.total, 0, "a genuine anomaly is never counted as a benign straggler")

        // Released rid: the same frame after a terminal released the route →
        // a benign straggler; NO drop counter moves.
        host.noteReleasedRidLocked(.uint(42))
        var straggler = Frame(frameType: .chunk, id: .uint(42))
        straggler.routingId = .uint(4)
        straggler.streamId = "s"
        straggler.chunkIndex = 0
        straggler.checksum = 0
        host.handleRelayFrameForTest(straggler)
        XCTAssertEqual(
            host.stragglers.get(.chunk), 1,
            "a released rid's straggler is the benign teardown race, named by frame type"
        )
        XCTAssertEqual(
            host.drops.total, 1,
            "the drop counters must not absorb benign teardown races"
        )

        // Unroutable LOG frames follow the same law — counted, never silent.
        var logReleased = Frame.progress(id: .uint(42), progress: 0.5, message: "late log")
        logReleased.routingId = .uint(4)
        host.handleRelayFrameForTest(logReleased)
        XCTAssertEqual(host.stragglers.get(.log), 1)
        var logUnknown = Frame.progress(id: .uint(43), progress: 0.5, message: "alien log")
        logUnknown.routingId = .uint(4)
        host.handleRelayFrameForTest(logUnknown)
        XCTAssertEqual(host.drops.get(.noRoute), 2)
    }
}
