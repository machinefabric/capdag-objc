/// Tests for the unified request table (protocol v3, L7/L8) — TEST7030-7033,
/// TEST7087, TEST7088. Mirrors capdag/src/bifaci/request_state.rs tests.

import XCTest
import Foundation
@testable import Bifaci

@available(macOS 10.15.4, iOS 13.4, *)
final class RequestStateTests: XCTestCase {

    private func key(_ x: UInt64, _ r: UInt64) -> RequestKey {
        return RequestKey(xid: .uint(x), rid: .uint(r))
    }

    private func state(dest: Int, origin: Int?, isPeer: Bool) -> RequestState {
        return RequestState(
            routing: RoutingEntry(sourceMasterIdx: origin, destinationMasterIdx: dest),
            origin: origin,
            externalChannel: nil,
            isPeer: isPeer
        )
    }

    private func snapshotJSON(_ table: RequestTable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(table.snapshot())
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any])
    }

    // TEST7092: A request registered with its originating REQ's cap URN carries that identity through the ACTIVE snapshot and into the terminated ring — observability surfaces can always NAME a request (background chatter vs run traffic), never just show a bare rid. A request registered without one snapshots with cap_urn absent — never invented.
    func test7092_capUrnAttributionSurvivesLifecycle() throws {
        let table = RequestTable()
        let named = key(1, 9)
        let namedState = state(dest: 0, origin: 1, isPeer: false)
        namedState.capUrn = "cap:effect=none"
        try table.register(named, namedState)
        let anonymous = key(2, 10)
        try table.register(anonymous, state(dest: 0, origin: 1, isPeer: true))

        var snapshot = table.snapshot()
        let byRid: (String) -> RequestSnapshot? = { rid in
            snapshot.active.first { $0.rid == rid }
        }
        XCTAssertEqual(
            try XCTUnwrap(byRid("9")).capUrn,
            "cap:effect=none",
            "active snapshot names the request's cap"
        )
        XCTAssertNil(try XCTUnwrap(byRid("10")).capUrn, "unknown identity stays absent")

        _ = table.terminate(named, kind: .end)
        snapshot = table.snapshot()
        XCTAssertEqual(
            snapshot.recentTerminated[0].capUrn,
            "cap:effect=none",
            "the terminated ring keeps the cap identity"
        )
    }

    // TEST7087: Protocol stats snapshots serialize with stable field names — the snapshot shape is the mirror contract.
    func test7087_snapshotFieldNamesAreStable() throws {
        let table = RequestTable()
        let k = key(1, 9)
        try table.register(k, state(dest: 0, origin: 1, isPeer: true))
        let rid = MessageId.uint(9)
        let ss = Frame.streamStart(
            reqId: rid,
            streamId: "s",
            mediaUrn: "media:enc=utf-8",
            isSequence: false
        )
        table.recordFrame(k, direction: .inbound, frame: ss)

        var json = try snapshotJSON(table)
        for field in ["active", "recent_terminated", "total_registered", "terminated_by_kind"] {
            XCTAssertNotNil(json[field], "missing top-level field \(field)")
        }
        let active = try XCTUnwrap(json["active"] as? [[String: Any]])
        let req = try XCTUnwrap(active.first)
        for field in [
            "xid", "rid", "phase", "is_peer", "origin_master", "destination_master",
            "age_ms", "idle_ms", "children", "streams",
        ] {
            XCTAssertTrue(req.keys.contains(field), "missing request field \(field)")
        }
        XCTAssertEqual(req["phase"] as? String, "streaming", "phase serializes snake_case")
        let streams = try XCTUnwrap(req["streams"] as? [[String: Any]])
        let stream = try XCTUnwrap(streams.first)
        for field in [
            "stream_id", "frames_in", "frames_out", "bytes_in", "bytes_out",
            "chunks_in", "chunks_out", "credit_outstanding", "unbounded", "ended",
        ] {
            XCTAssertTrue(stream.keys.contains(field), "missing stream field \(field)")
        }

        XCTAssertNotNil(table.terminate(k, kind: .masterDied))
        json = try snapshotJSON(table)
        let terminated = try XCTUnwrap(json["recent_terminated"] as? [[String: Any]])
        let summary = try XCTUnwrap(terminated.first)
        for field in [
            "xid", "rid", "kind", "is_peer", "lifetime_ms",
            "frames_in", "frames_out", "bytes_in", "bytes_out",
        ] {
            XCTAssertTrue(summary.keys.contains(field), "missing summary field \(field)")
        }
        XCTAssertEqual(summary["kind"] as? String, "master_died", "kind serializes snake_case")
    }

    // TEST7088: last_activity is monotonic non-decreasing across a long-lived streaming request — idle time resets on every recorded frame and never runs backwards.
    func test7088_lastActivityMonotonic() throws {
        let table = RequestTable()
        let k = key(1, 5)
        try table.register(k, state(dest: 0, origin: nil, isPeer: false))
        let rid = MessageId.uint(5)

        var lastActivityPoints: [UInt64] = []
        for i in 0..<3 {
            Thread.sleep(forTimeInterval: 0.015)
            let payload = Data(repeating: 0, count: 4)
            let checksum = Frame.computeChecksum(payload)
            let chunk = Frame.chunk(
                reqId: rid, streamId: "s", seq: UInt64(i),
                payload: payload, chunkIndex: UInt64(i), checksum: checksum
            )
            table.recordFrame(k, direction: .inbound, frame: chunk)
            let entry = try XCTUnwrap(table.get(k))
            XCTAssertGreaterThanOrEqual(
                entry.lastActivityNanos, entry.createdAtNanos,
                "activity never precedes creation"
            )
            lastActivityPoints.append(entry.lastActivityNanos)
        }
        for i in 1..<lastActivityPoints.count {
            XCTAssertGreaterThanOrEqual(
                lastActivityPoints[i], lastActivityPoints[i - 1],
                "last_activity must be monotonic non-decreasing"
            )
        }
        // idle_ms in the snapshot reflects the LAST activity, not the first:
        // it must be (much) smaller than the request's age.
        Thread.sleep(forTimeInterval: 0.015)
        let snap = table.snapshot()
        let req = try XCTUnwrap(snap.active.first)
        XCTAssertLessThanOrEqual(
            req.idleMs, req.ageMs,
            "idle \(req.idleMs)ms cannot exceed age \(req.ageMs)ms"
        )
        XCTAssertGreaterThanOrEqual(req.ageMs, 45, "age accumulates across the request lifetime")
    }

    // TEST7030: A request registers exactly once and terminates exactly once — duplicate registration and double termination are rejected, and after terminate zero state remains for the key.
    func test7030_registerOnceTerminateOnce() throws {
        let table = RequestTable()
        let k = key(1, 100)

        try table.register(k, state(dest: 0, origin: nil, isPeer: false))
        XCTAssertTrue(table.contains(k))
        XCTAssertEqual(table.xidForRid(.uint(100)), .uint(1))

        // Duplicate registration of a live key is a protocol violation.
        XCTAssertThrowsError(try table.register(k, state(dest: 0, origin: nil, isPeer: false))) { error in
            XCTAssertTrue("\(error)".contains("already registered"), "\(error)")
        }

        // Same RID under a different XID is rejected while live.
        XCTAssertThrowsError(try table.register(key(2, 100), state(dest: 0, origin: nil, isPeer: false))) { error in
            XCTAssertTrue("\(error)".contains("already indexed"), "\(error)")
        }

        let removed = try XCTUnwrap(table.terminate(k, kind: .end), "live entry")
        XCTAssertFalse(removed.isPeer)
        XCTAssertFalse(table.contains(k), "no entry remains after terminate")
        XCTAssertNil(table.xidForRid(.uint(100)), "rid index removed with the entry (L7)")
        XCTAssertNil(table.terminate(k, kind: .end), "termination happens exactly once")
    }

    // TEST7031: The rid index and the entry table never disagree across register/terminate cycles, and a terminated rid is immediately reusable.
    func test7031_ridIndexConsistency() throws {
        let table = RequestTable()
        for round in 0..<3 {
            for n in 0..<10 {
                let k = key(UInt64(round * 100 + n), UInt64(n))
                try table.register(k, state(dest: 0, origin: nil, isPeer: false))
            }
            for n in 0..<10 {
                let k = key(UInt64(round * 100 + n), UInt64(n))
                let xid = try XCTUnwrap(table.xidForRid(.uint(UInt64(n))), "indexed")
                XCTAssertEqual(xid, k.xid, "index resolves to the live entry's xid")
                XCTAssertTrue(table.contains(RequestKey(xid: xid, rid: .uint(UInt64(n)))))
                XCTAssertNotNil(table.terminate(k, kind: .end))
                XCTAssertNil(table.xidForRid(.uint(UInt64(n))))
            }
        }
        XCTAssertTrue(table.isEmpty)
        XCTAssertEqual(table.snapshot().totalRegistered, 30)
    }

    // TEST7032: record_frame accumulates per-stream frame/byte/chunk counters by direction, flips phase Created→Streaming on the first flow frame, and tracks unbounded/ended/credit stream markers.
    func test7032_recordFrameStatsAndPhase() throws {
        let table = RequestTable()
        let k = key(1, 7)
        try table.register(k, state(dest: 0, origin: nil, isPeer: false))
        XCTAssertEqual(try XCTUnwrap(table.get(k)).phase, .created)

        let rid = MessageId.uint(7)
        let ss = Frame.streamStartUnbounded(reqId: rid, streamId: "s1", mediaUrn: "media:enc=utf-8")
        table.recordFrame(k, direction: .inbound, frame: ss)
        XCTAssertEqual(try XCTUnwrap(table.get(k)).phase, .streaming)

        let payload = Data(repeating: 0, count: 100)
        let checksum = Frame.computeChecksum(payload)
        let chunk = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: payload, chunkIndex: 0, checksum: checksum)
        table.recordFrame(k, direction: .inbound, frame: chunk)
        table.recordFrame(k, direction: .outbound, frame: chunk)

        let credit = Frame.credit(targetRid: rid, streamId: "s1", credits: 4, direction: .response)
        table.recordFrame(k, direction: .outbound, frame: credit)

        let se = Frame.streamEndUnbounded(reqId: rid, streamId: "s1")
        table.recordFrame(k, direction: .inbound, frame: se)

        let entry = try XCTUnwrap(table.get(k))
        let s1 = try XCTUnwrap(entry.streams["s1"])
        XCTAssertEqual(s1.framesIn, 3, "stream_start + chunk + stream_end")
        XCTAssertEqual(s1.framesOut, 2, "chunk + credit")
        XCTAssertEqual(s1.chunksIn, 1)
        XCTAssertEqual(s1.chunksOut, 1)
        XCTAssertEqual(s1.bytesIn, 100)
        XCTAssertEqual(s1.bytesOut, 100)
        XCTAssertTrue(s1.unbounded)
        XCTAssertTrue(s1.ended)
        // +4 granted, -1 consumed inbound chunk
        XCTAssertEqual(s1.creditOutstanding, 3)
    }

    // TEST7033: Terminated requests leave a bounded ring of summaries carrying kind, lifetime, and flow totals, and the ring evicts oldest-first at capacity.
    func test7033_terminatedSummariesRing() throws {
        let table = RequestTable()
        let cap = RequestTable.recentTerminatedCap
        for n in 0..<(cap + 3) {
            let k = key(UInt64(n), UInt64(n))
            try table.register(k, state(dest: 0, origin: 2, isPeer: true))
            let payload = Data(repeating: 0, count: 10)
            let checksum = Frame.computeChecksum(payload)
            let chunk = Frame.chunk(
                reqId: .uint(UInt64(n)), streamId: "s", seq: 0,
                payload: payload, chunkIndex: 0, checksum: checksum
            )
            table.recordFrame(k, direction: .inbound, frame: chunk)
            XCTAssertNotNil(table.terminate(k, kind: .cancelled))
        }
        let snap = table.snapshot()
        XCTAssertEqual(snap.recentTerminated.count, cap)
        // Oldest evicted: first retained summary is rid "3"
        XCTAssertEqual(snap.recentTerminated.first?.rid, MessageId.uint(3).description)
        let last = try XCTUnwrap(snap.recentTerminated.last)
        XCTAssertEqual(last.kind, .cancelled)
        XCTAssertTrue(last.isPeer)
        XCTAssertEqual(last.framesIn, 1)
        XCTAssertEqual(last.bytesIn, 10)
        XCTAssertEqual(snap.terminatedByKind["cancelled"], UInt64(cap + 3))
    }
}
