/// Tests for RelaySwitch — TEST426-TEST435

import XCTest
import Foundation
@testable import Bifaci
import CapDAG

@available(macOS 10.15.4, iOS 13.4, *)
final class CborRelaySwitchTests: XCTestCase {

    // Helper to send RelayNotify payload with capability URNs and installed cartridge identities.
    //
    // The wire schema embeds caps inside `installed_cartridges[*].cap_groups`, so the
    // helper wraps the test's flat cap-URN list in a single synthetic
    // installed-cartridge whose lone group declares all of them.
    /// Roster pools map for test stats: one at-rest singleton per cap
    /// (canonical URN) plus the mandatory `all` pool.
    static func testPoolStatesJSON(capUrns: [String]) -> [String: Any] {
        func atRest() -> [String: Any] {
            ["declared": 0, "configured": 0, "active": 0, "queued": 0]
        }
        var pools: [String: Any] = [:]
        for urn in capUrns {
            guard let canonical = try? CSCapUrn.fromString(urn).toString() else {
                fatalError("test cap URN must parse: \(urn)")
            }
            pools[canonical] = atRest()
        }
        pools["all"] = atRest()
        return pools
    }

    private func sendNotify(writer: FrameWriter, capabilities: [String], limits: Limits) throws {
        let groupCaps: [[String: Any]] = capabilities.map { urn in
            return [
                "urn": urn,
                "title": "test",
                "aliases": ["test"],
                "args": [] as [Any],
            ]
        }
        let manifestBytes = try JSONSerialization.data(withJSONObject: [
            "installed_cartridges": [[
                "registry_url": NSNull(),
                "channel": "release",
                "id": "test-cartridge",
                "version": "0.0.0",
                "sha256": String(repeating: "0", count: 64),
                "runtime_stats": [
                    "running": true,
                    // One at-rest singleton per advertised cap (canonical
                    // URN) plus the mandatory `all` pool — the pool-map
                    // equivalent of the retired scalar handler_capacity.
                    "pools": Self.testPoolStatesJSON(capUrns: capabilities),
                    "active_request_count": 0,
                    "peer_request_count": 0,
                    "memory_footprint_mb": 0,
                    "memory_rss_mb": 0,
                    "restart_count": 0,
                ] as [String: Any],
                "cap_groups": [[
                    "name": "test",
                    "caps": groupCaps,
                    "adapter_urns": [] as [String],
                ]],
            ]]
        ])
        let notify = Frame.relayNotify(
            manifest: manifestBytes,
            limits: limits
        )
        try writer.write(notify)
    }

    // Helper to handle the identity verification protocol that RelaySwitch init performs.
    // RelaySwitch sends: REQ + STREAM_START + CHUNK(nonce) + STREAM_END + END
    // This helper reads those frames and echoes back: STREAM_START + CHUNK(nonce) + STREAM_END + END
    private func handleIdentityVerification(reader: FrameReader, writer: FrameWriter) throws {
        var nonce = Data()
        var reqId: MessageId? = nil
        let streamId = "identity-verify"
        while true {
            guard let frame = try reader.read() else { return }
            switch frame.frameType {
            case .req:
                reqId = frame.id
            case .streamStart:
                break
            case .chunk:
                if let p = frame.payload { nonce.append(p) }
            case .streamEnd:
                break
            case .end:
                guard let id = reqId else { return }
                // Echo nonce back: STREAM_START + CHUNK(nonce) + STREAM_END + END
                try writer.write(Frame.streamStart(reqId: id, streamId: streamId, mediaUrn: "media:"))
                let checksum = Frame.computeChecksum(nonce)
                try writer.write(Frame.chunk(reqId: id, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum))
                try writer.write(Frame.streamEnd(reqId: id, streamId: streamId, chunkCount: 1))
                try writer.write(Frame.end(id: id))
                return
            case .policy where reqId == nil:
                // The switch's policy comes first (12.2 §Policy).
                break
            default:
                return
            }
        }
    }

    // TEST426: Single master REQ/response routing
    func test426_single_master_req_response() throws {
        // Create socket pairs for master-slave communication
        // engine_read <-> slave_write (one pair)
        // slave_read <-> engine_write (another pair)
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let done = DispatchSemaphore(value: 0)

        // Spawn mock slave that sends RelayNotify, handles identity verification, then echoes frames
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read, limits: Limits())  // slave reads from pair2
            let writer = FrameWriter(handle: pair1.write, limits: Limits())  // slave writes to pair1

            let caps: [String] = [CSCapIdentity]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            // Handle identity verification from RelaySwitch init
            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Read one REQ and send response (must copy XID from REQ so RelaySwitch routes as response)
            if let frame = try? reader.read(), frame.frameType == .req {
                var response = Frame.end(id: frame.id, finalPayload: Data([42]))
                response.routingId = frame.routingId
                try! writer.write(response)
            }
        }

        // Wait for RelayNotify
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        // Create RelaySwitch with properly connected sockets
        // engine reads from pair1 (where slave writes)
        // engine writes to pair2 (where slave reads)
        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-0", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // Send REQ
        let req = Frame.req(
            id: MessageId.uint(1),
            capUrn: CSCapIdentity,
            payload: Data([1, 2, 3]),
            contentType: "text/plain"
        )
        try switch_.sendToMaster(req)

        // Read response
        let response = try switch_.readFromMasters()
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.frameType, .end)
        XCTAssertEqual(response?.id.toString(), MessageId.uint(1).toString())
        XCTAssertEqual(response?.payload, Data([42]))

        // Cleanup - shutdown signals reader threads to exit
        // File handles closed by ARC when they go out of scope
        switch_.shutdown()
    }

    // TEST427: Multi-master cap routing
    func test427_multi_master_cap_routing() throws {
        // Create cross-connected socket pairs for two masters
        // Master 1: engine_read1 <-> slave_write1, slave_read1 <-> engine_write1
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        // Master 2: engine_read2 <-> slave_write2, slave_read2 <-> engine_write2
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)
        let resp1Done = DispatchSemaphore(value: 0)
        let resp2Done = DispatchSemaphore(value: 0)

        // Spawn slave 1 (echo cap) - handles exactly 1 request
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read, limits: Limits())
            let writer = FrameWriter(handle: pair1_1.write, limits: Limits())

            let caps: [String] = [CSCapIdentity]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done1.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Handle exactly 1 request then exit
            if let frame = try? reader.read(), frame.frameType == .req {
                var response = Frame.end(id: frame.id, finalPayload: Data([1]))
                response.routingId = frame.routingId
                try! writer.write(response)
            }
            resp1Done.signal()
        }

        // Spawn slave 2 (double cap) - handles exactly 1 request
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read, limits: Limits())
            let writer = FrameWriter(handle: pair2_1.write, limits: Limits())

            let caps: [String] = [CSCapIdentity, "cap:in=\"media:void\";double;out=\"media:void\""]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done2.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Handle exactly 1 request then exit
            if let frame = try? reader.read(), frame.frameType == .req {
                var response = Frame.end(id: frame.id, finalPayload: Data([2]))
                response.routingId = frame.routingId
                try! writer.write(response)
            }
            resp2Done.signal()
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(id: "test-master-1", read: pair1_1.read, write: pair1_2.write),
            SocketPair(id: "test-master-2", read: pair2_1.read, write: pair2_2.write),
        ], policy: HostPolicy(network: .full))

        // Send REQ for echo cap → routes to master 1
        let req1 = Frame.req(
            id: MessageId.uint(1),
            capUrn: CSCapIdentity,
            payload: Data(),
            contentType: "text/plain"
        )
        try switch_.sendToMaster(req1)

        let resp1 = try switch_.readFromMasters()
        XCTAssertEqual(resp1?.payload, Data([1]))

        // Send REQ for double cap → routes to master 2
        let req2 = Frame.req(
            id: MessageId.uint(2),
            capUrn: "cap:in=\"media:void\";double;out=\"media:void\"",
            payload: Data(),
            contentType: "text/plain"
        )
        try switch_.sendToMaster(req2)

        let resp2 = try switch_.readFromMasters()
        XCTAssertEqual(resp2?.payload, Data([2]))

        // Wait for background threads to finish
        XCTAssertEqual(resp1Done.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(resp2Done.wait(timeout: .now() + 2), .success)

        // Shutdown switch - file handles closed by ARC
        switch_.shutdown()
    }

    // TEST428: Unknown cap returns error
    func test428_unknown_cap_returns_error() throws {
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)  // slave reads from pair2
            let writer = FrameWriter(handle: pair1.write)  // slave writes to pair1

            let caps: [String] = [CSCapIdentity]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-3", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // Send REQ for unknown cap
        let req = Frame.req(
            id: MessageId.uint(1),
            capUrn: "cap:in=\"media:void\";unknown;out=\"media:void\"",
            payload: Data(),
            contentType: "text/plain"
        )

        XCTAssertThrowsError(try switch_.sendToMaster(req)) { error in
            guard case RelaySwitchError.noHandler = error else {
                XCTFail("Expected noHandler error")
                return
            }
        }

        // Cleanup
        switch_.shutdown()
    }

    // TEST429: Cap routing logic (find_master_for_cap)
    func test429_find_master_for_cap() throws {
        // Create cross-connected socket pairs for two masters
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read)  // slave1 reads from pair1_2
            let writer = FrameWriter(handle: pair1_1.write)  // slave1 writes to pair1_1
            let caps: [String] = [CSCapIdentity]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done1.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read)  // slave2 reads from pair2_2
            let writer = FrameWriter(handle: pair2_1.write)  // slave2 writes to pair2_1
            let caps: [String] = [CSCapIdentity, "cap:in=\"media:void\";double;out=\"media:void\""]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done2.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(id: "test-master-4", read: pair1_1.read, write: pair1_2.write),  // engine1 reads from pair1_1, writes to pair1_2
            SocketPair(id: "test-master-5", read: pair2_1.read, write: pair2_2.write),  // engine2 reads from pair2_1, writes to pair2_2
        ], policy: HostPolicy(network: .full))

        // Verify aggregate capabilities (returned as JSON array)
        let capList = try JSONSerialization.jsonObject(with: switch_.capabilities()) as! [String]
        XCTAssertEqual(capList.count, 2)

        // Cleanup
        switch_.shutdown()
    }

    // TEST430: Tie-breaking (same cap on multiple masters - first match wins, routing is consistent)
    func test430_tie_breaking_same_cap_multiple_masters() throws {
        // Create cross-connected socket pairs for two masters with the SAME cap
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)
        let slave1Done = DispatchSemaphore(value: 0)
        let slave2Done = DispatchSemaphore(value: 0)

        let sameCap = CSCapIdentity

        // Spawn slave 1 - handles 2 requests (both go to master 0)
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read)
            let writer = FrameWriter(handle: pair1_1.write)
            let caps: [String] = [sameCap]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done1.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Handle 2 requests then exit
            for _ in 0..<2 {
                if let frame = try? reader.read(), frame.frameType == .req {
                    var response = Frame.end(id: frame.id, finalPayload: Data([1]))
                    response.routingId = frame.routingId
                    try! writer.write(response)
                }
            }
            slave1Done.signal()
        }

        // Spawn slave 2 - handles 0 requests (routing goes to master 0)
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read)
            let writer = FrameWriter(handle: pair2_1.write)
            let caps: [String] = [sameCap]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done2.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)
            // No requests expected for slave 2
            slave2Done.signal()
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(id: "test-master-6", read: pair1_1.read, write: pair1_2.write),
            SocketPair(id: "test-master-7", read: pair2_1.read, write: pair2_2.write),
        ], policy: HostPolicy(network: .full))

        // Send first request - should go to master 0 (first match)
        let req1 = Frame.req(id: MessageId.uint(1), capUrn: sameCap, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req1)

        let resp1 = try switch_.readFromMasters()
        XCTAssertEqual(resp1?.payload, Data([1]))  // From master 0

        // Send second request - should ALSO go to master 0 (consistent routing)
        let req2 = Frame.req(id: MessageId.uint(2), capUrn: sameCap, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req2)

        let resp2 = try switch_.readFromMasters()
        XCTAssertEqual(resp2?.payload, Data([1]))  // Also from master 0

        // Wait for background threads
        XCTAssertEqual(slave1Done.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(slave2Done.wait(timeout: .now() + 2), .success)

        // Shutdown switch before closing file handles
        switch_.shutdown()

        // Cleanup
    }

    // TEST431: Continuation frame routing (CHUNK, END follow REQ)
    func test431_continuation_frame_routing() throws {
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)

            let caps: [String] = [CSCapIdentity, "cap:in=\"media:void\";test;out=\"media:void\""]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Read REQ
            let req = try! reader.read()!
            XCTAssertEqual(req.frameType, .req)

            // Read CHUNK continuation
            let chunk = try! reader.read()!
            XCTAssertEqual(chunk.frameType, .chunk)
            XCTAssertEqual(chunk.id.toString(), req.id.toString())

            // Read END continuation
            let end = try! reader.read()!
            XCTAssertEqual(end.frameType, .end)
            XCTAssertEqual(end.id.toString(), req.id.toString())

            // Send response (copy XID from REQ so RelaySwitch routes as response)
            var response = Frame.end(id: req.id, finalPayload: Data([42]))
            response.routingId = req.routingId
            try! writer.write(response)
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-8", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        let reqId = MessageId.uint(1)

        // Send REQ
        let req = Frame.req(id: reqId, capUrn: "cap:in=\"media:void\";test;out=\"media:void\"", payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req)

        // Send CHUNK continuation
        let chunkPayload = Data([1, 2, 3])
        let chunk = Frame.chunk(reqId: reqId, streamId: "stream1", seq: 0, payload: chunkPayload, chunkIndex: 0, checksum: Frame.computeChecksum(chunkPayload))
        try switch_.sendToMaster(chunk)

        // Send END continuation
        let end = Frame.end(id: reqId)
        try switch_.sendToMaster(end)

        // Read response
        let response = try switch_.readFromMasters()
        XCTAssertEqual(response?.frameType, .end)
        XCTAssertEqual(response?.payload, Data([42]))

        // Cleanup
        switch_.shutdown()
    }

    // TEST432: Empty masters list creates empty switch, add_master works
    func test432_empty_masters_allowed() throws {
        let sw = try RelaySwitch(sockets: [], policy: HostPolicy(network: .full))

        // Empty switch has no caps
        let capsJson = sw.capabilities()
        XCTAssertEqual(String(data: capsJson, encoding: .utf8), "[]", "empty switch should have empty caps JSON")

        // No handler for any cap — sendToMaster throws noHandler
        XCTAssertThrowsError(try sw.sendToMaster(Frame.req(id: .newUUID(), capUrn: CSCapIdentity, payload: Data(), contentType: ""))) { error in
            guard case RelaySwitchError.noHandler = error else {
                XCTFail("Expected noHandler error, got \(error)")
                return
            }
        }
    }

    // TEST433: Capability aggregation deduplicates caps
    func test433_capability_aggregation_deduplicates() throws {
        // Create two masters with overlapping caps
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read)  // slave1 reads from pair1_2
            let writer = FrameWriter(handle: pair1_1.write)
            let caps: [String] = [
                CSCapIdentity,
                "cap:in=\"media:void\";double;out=\"media:void\""
            ]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done1.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read)  // slave2 reads from pair2_2
            let writer = FrameWriter(handle: pair2_1.write)
            let caps: [String] = [
                CSCapIdentity,  // Duplicate
                "cap:in=\"media:void\";triple;out=\"media:void\""
            ]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done2.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(id: "test-master-9", read: pair1_1.read, write: pair1_2.write),
            SocketPair(id: "test-master-10", read: pair2_1.read, write: pair2_2.write),
        ], policy: HostPolicy(network: .full))

        let capList = (try JSONSerialization.jsonObject(with: switch_.capabilities()) as! [String]).sorted()

        // Should have 3 unique caps (echo appears twice but deduplicated)
        XCTAssertEqual(capList.count, 3)
        XCTAssertTrue(capList.contains("cap:in=\"media:void\";double;out=\"media:void\""))
        XCTAssertTrue(capList.contains(CSCapIdentity))
        XCTAssertTrue(capList.contains("cap:in=\"media:void\";triple;out=\"media:void\""))

        // Cleanup
        switch_.shutdown()
    }

    // TEST434: Limits negotiation takes minimum
    func test434_limits_negotiation_minimum() throws {
        let pair1_1 = FileHandle.socketPair()  // engine_read1, slave_write1
        let pair1_2 = FileHandle.socketPair()  // slave_read1, engine_write1
        let pair2_1 = FileHandle.socketPair()  // engine_read2, slave_write2
        let pair2_2 = FileHandle.socketPair()  // slave_read2, engine_write2

        let done1 = DispatchSemaphore(value: 0)
        let done2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair1_2.read)  // slave1 reads from pair1_2
            let writer = FrameWriter(handle: pair1_1.write)
            let caps: [String] = [CSCapIdentity]
            let limits1 = Limits(maxFrame: 1_000_000, maxChunk: 100_000)
            try! self.sendNotify(writer: writer, capabilities: caps, limits: limits1)
            done1.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2_2.read)  // slave2 reads from pair2_2
            let writer = FrameWriter(handle: pair2_1.write)
            let caps: [String] = [CSCapIdentity]
            let limits2 = Limits(maxFrame: 2_000_000, maxChunk: 50_000)  // Larger frame, smaller chunk
            try! self.sendNotify(writer: writer, capabilities: caps, limits: limits2)
            done2.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(id: "test-master-11", read: pair1_1.read, write: pair1_2.write),
            SocketPair(id: "test-master-12", read: pair2_1.read, write: pair2_2.write),
        ], policy: HostPolicy(network: .full))

        // Should take minimum of each limit
        XCTAssertEqual(switch_.limits().maxFrame, 1_000_000)  // min(1M, 2M)
        XCTAssertEqual(switch_.limits().maxChunk, 50_000)     // min(100K, 50K)

        // Cleanup
        switch_.shutdown()
    }

    // TEST435: URN matching (exact vs accepts())
    // Dispatch is contravariant on input (request input must conform to candidate input — i.e. request
    // can be more specific) and covariant on output (candidate output must conform to request output —
    // i.e. candidate can be more specific). A request whose input is in a different type family than
    // any registered candidate has no handler.
    func test435_urn_matching_exact_and_accepts() throws {
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let done = DispatchSemaphore(value: 0)
        let slaveDone = DispatchSemaphore(value: 0)

        // Master advertises a specific cap
        let registeredCap = "cap:in=\"media:text;utf8\";process;out=\"media:text;utf8\""

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            let caps: [String] = [CSCapIdentity, registeredCap]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Respond to every Req frame the engine forwards until the read side closes.
            while let frame = try? reader.read() {
                if frame.frameType == .req {
                    var response = Frame.end(id: frame.id, finalPayload: Data([42]))
                    response.routingId = frame.routingId
                    try! writer.write(response)
                }
            }
            slaveDone.signal()
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-13", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // Exact match should work
        let req1 = Frame.req(id: MessageId.uint(1), capUrn: registeredCap, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req1)
        let resp1 = try switch_.readFromMasters()
        XCTAssertEqual(resp1?.payload, Data([42]))

        // Request with more specific input and less specific output SHOULD match.
        // Input (contravariant): request's "media:text;utf8;normalized" conforms to candidate's "media:text;utf8".
        // Output (covariant): candidate's "media:text;utf8" conforms to request's "media:text".
        let req2 = Frame.req(
            id: MessageId.uint(2),
            capUrn: "cap:in=\"media:text;utf8;normalized\";process;out=\"media:text\"",
            payload: Data(),
            contentType: "text/plain"
        )
        try switch_.sendToMaster(req2)
        let resp2 = try switch_.readFromMasters()
        XCTAssertEqual(resp2?.payload, Data([42]))

        // Request with INCOMPATIBLE input (different type family) must NOT match.
        let req3 = Frame.req(
            id: MessageId.uint(3),
            capUrn: "cap:in=\"media:ext=png;image\";process;out=\"media:text\"",
            payload: Data(),
            contentType: "text/plain"
        )
        XCTAssertThrowsError(try switch_.sendToMaster(req3)) { error in
            guard case RelaySwitchError.noHandler = error else {
                XCTFail("Expected noHandler error, got: \(error)")
                return
            }
        }

        switch_.shutdown()
        _ = slaveDone.wait(timeout: .now() + 2)
    }

    // MARK: - Preferred Cap Routing Tests (TEST437-439)

    // TEST437: find_master_for_cap with preferred_cap routes to generic handler With is_dispatchable semantics: - Generic candidate (in=media:) CAN dispatch specific request (in="media:document;ext=pdf") because media: (wildcard) accepts any input type - Preference routes to preferred among dispatchable candidates
    func test437_preferredCapRoutesToExactMatch() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)
        let slaveDone = DispatchSemaphore(value: 0)

        // Master advertises the exact cap being requested
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            let caps: [String] = [CSCapIdentity]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Handle 1 request then exit
            if let frame = try? reader.read(), frame.frameType == .req {
                var response = Frame.end(id: frame.id, finalPayload: Data("matched".utf8))
                response.routingId = frame.routingId
                try! writer.write(response)
            }
            slaveDone.signal()
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-14", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // Request with the exact registered cap should route successfully
        let req = Frame.req(id: MessageId.uint(1), capUrn: CSCapIdentity, payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req)
        let resp = try switch_.readFromMasters()
        XCTAssertEqual(resp?.payload, Data("matched".utf8))

        XCTAssertEqual(slaveDone.wait(timeout: .now() + 2), .success)
        switch_.shutdown()
    }

    // TEST438: find_master_for_cap with preference falls back to closest-specificity when preferred cap is not in the comparable set
    func test438_preferredCapExactMatch() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)
        let slaveDone = DispatchSemaphore(value: 0)

        // Master advertises specific cap (with identity required)
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            let caps: [String] = [CSCapIdentity, "cap:in=media:text;out=media:text"]  // Identity + specific
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Handle 1 request then exit
            if let frame = try? reader.read(), frame.frameType == .req {
                var response = Frame.end(id: frame.id, finalPayload: Data("specific".utf8))
                response.routingId = frame.routingId
                try! writer.write(response)
            }
            slaveDone.signal()
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-15", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // Request for the exact registered cap should succeed
        let req = Frame.req(id: MessageId.uint(1), capUrn: "cap:in=media:text;out=media:text", payload: Data(), contentType: "text/plain")
        try switch_.sendToMaster(req)
        let resp = try switch_.readFromMasters()
        XCTAssertEqual(resp?.payload, Data("specific".utf8))

        XCTAssertEqual(slaveDone.wait(timeout: .now() + 2), .success)
        switch_.shutdown()
    }

    // TEST439: Generic candidate CAN dispatch specific request (but only matches if no more specific candidate exists) With is_dispatchable: generic candidate (in=media:) CAN handle specific request (in="media:document;ext=pdf") because media: accepts any input type. With preference, can route to generic even when more specific exists.
    func test439_specificRequestNoMatchingHandler() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)

        // Master advertises a different specific cap (with identity required)
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            // Advertise identity + a specific cap that doesn't match the request
            let caps: [String] = [CSCapIdentity, "cap:in=media:image;out=media:image"]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-16", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // Request for a cap that doesn't match should throw noHandler
        let req = Frame.req(id: MessageId.uint(1), capUrn: "cap:in=media:text;out=media:text", payload: Data(), contentType: "text/plain")

        XCTAssertThrowsError(try switch_.sendToMaster(req)) { error in
            guard case RelaySwitchError.noHandler = error else {
                XCTFail("Expected noHandler error, got \(error)")
                return
            }
        }

        // Cleanup
        switch_.shutdown()
    }

    // MARK: - Identity Verification in RelaySwitch Tests (TEST487-489)

    // TEST487: RelaySwitch construction verifies identity through relay chain
    func test487_relaySwitchIdentityVerificationSucceeds() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)

        // Master that passes identity verification
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            let caps: [String] = [CSCapIdentity]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            // Handle identity verification correctly (echo back)
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        // Should succeed - identity verification passes
        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-17", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))
        XCTAssertNotNil(switch_)

        // Cleanup
        switch_.shutdown()
    }

    // TEST488: RelaySwitch construction fails when master's identity verification fails
    func test488_relaySwitchIdentityVerificationFails() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)

        // Master that fails identity verification
        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            let caps: [String] = [CSCapIdentity]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()

            // Read identity request and return ERR
            // The switch's policy comes first (12.2 §Policy).
            guard let policy = try? reader.read(), policy.frameType == .policy else { return }
            if let req = try? reader.read() {
                if req.frameType == .req {
                    try! writer.write(Frame.err(id: req.id, code: "IDENTITY_FAILED", attributionClass: .internal, message: "Rejected"))
                }
            }
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        // Should fail - identity verification returns error
        XCTAssertThrowsError(try RelaySwitch(sockets: [SocketPair(id: "test-master-18", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))) { error in
            // Should get an error about identity verification
            XCTAssertTrue(error is RelaySwitchError)
        }

        // Cleanup (no switch_ because construction failed)
    }

    // TEST132: add_master dynamically connects new host to running switch
    func test132_addMasterDynamic() throws {
        // Start with empty switch
        let switch_ = try RelaySwitch(sockets: [], policy: HostPolicy(network: .full))
        XCTAssertEqual(String(data: switch_.capabilities(), encoding: .utf8), "[]")

        // Add master dynamically
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)
        let responseSent = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            let caps: [String] = [CSCapIdentity]
            try! self.sendNotify(writer: writer, capabilities: caps, limits: Limits())
            done.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Handle exactly one request then exit (no infinite loop!)
            if let frame = try? reader.read(), frame.frameType == .req {
                var response = Frame.end(id: frame.id, finalPayload: Data("dynamic".utf8))
                response.routingId = frame.routingId
                try! writer.write(response)
            }
            responseSent.signal()
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        _ = try switch_.addMaster(SocketPair(id: "test-master-19", read: pair1.read, write: pair2.write))

        // Should now have the cap
        let capList = try JSONSerialization.jsonObject(with: switch_.capabilities()) as! [String]
        XCTAssertTrue(capList.contains(CSCapIdentity))

        // Should be able to route requests
        let req = Frame.req(id: MessageId.uint(1), capUrn: CSCapIdentity, payload: Data(), contentType: "")
        try switch_.sendToMaster(req)
        let resp = try switch_.readFromMasters()
        XCTAssertEqual(resp?.payload, Data("dynamic".utf8))

        // Wait for background thread to finish before test ends
        XCTAssertEqual(responseSent.wait(timeout: .now() + 2), .success)

        // Shutdown switch - file handles closed by ARC
        switch_.shutdown()
    }

    // ============================================================
    // Reattach-by-id tests for the cardinality-stable slot model.
    //
    // When a master dies and the host reconnects, the new socket
    // MUST attach to the same slot index — preserving routing
    // entries keyed by index. Accumulating zombie slots on each
    // reconnect was the bug class these tests guard against.

    func test133_ReattachByIdPreservesSlotIndex() throws {
        // Phase 1: build a switch with one slot at id "xpc-service".
        let pair1a = FileHandle.socketPair()
        let pair2a = FileHandle.socketPair()
        let done1 = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2a.read)
            let writer = FrameWriter(handle: pair1a.write)
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            done1.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
            // Hold the read handle until the test closes its end —
            // simulates a healthy slave waiting for traffic.
            _ = try? reader.read()
        }
        XCTAssertEqual(done1.wait(timeout: .now() + 2), .success)
        let switch_ = try RelaySwitch(sockets: [
            SocketPair(id: "xpc-service", read: pair1a.read, write: pair2a.write)
        ], policy: HostPolicy(network: .full))

        // Phase 2: simulate master death synchronously, exactly
        // like the Rust reference test. The slot remains in the
        // cardinality list but becomes unhealthy, so a reconnect
        // under the same id must reattach in place.
        try switch_.handleMasterDeath(0)

        // Phase 3: reconnect with the SAME id. The new socket
        // should reattach to slot 0, not append a new slot.
        let pair1b = FileHandle.socketPair()
        let pair2b = FileHandle.socketPair()
        let done2 = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2b.read)
            let writer = FrameWriter(handle: pair1b.write)
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            done2.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
            _ = try? reader.read()
        }
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)
        let newIdx = try switch_.addMaster(SocketPair(
            id: "xpc-service",
            read: pair1b.read,
            write: pair2b.write
        ))
        XCTAssertEqual(newIdx, 0,
            "reattach MUST return the same slot index (0), not append a new slot")

        switch_.shutdown()
    }

    // TEST134: Add master with duplicate healthy id errors
    func test134_AddMasterWithDuplicateHealthyIdErrors() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            done.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
            _ = try? reader.read()
        }
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        let switch_ = try RelaySwitch(sockets: [
            SocketPair(id: "xpc-service", read: pair1.read, write: pair2.write)
        ], policy: HostPolicy(network: .full))

        // Try to add a second master with the same id while healthy.
        // The duplicate-id check fires BEFORE any I/O on the dummy
        // pipes, so the dummies never have to go through a handshake.
        let dummy1 = FileHandle.socketPair()
        let dummy2 = FileHandle.socketPair()
        XCTAssertThrowsError(try switch_.addMaster(SocketPair(
            id: "xpc-service",
            read: dummy1.read,
            write: dummy2.write
        ))) { error in
            guard case let RelaySwitchError.protocolError(msg) = error else {
                XCTFail("expected protocolError; got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("already attached to a healthy slot"),
                "error message should name the cardinality violation: \(msg)")
        }

        switch_.shutdown()
    }

    // TEST1965: attachment is decided by the SOCKET, not the health flag.
    // A slot whose identity probe is pending is unhealthy yet attached —
    // its socket is open — and reattaching over it would strand the
    // host; slotAcceptsAttach says no and addMaster refuses, so a host
    // that asks first never dials a slot it holds. Once the slave drops
    // its socket (reader EOF → the slot detaches) the same id reattaches
    // in place.
    func test1965_AttachDecidedBySocketLivenessNotHealth() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()
        let done = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            done.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
            _ = release.wait(timeout: .now() + 10)
            try? pair1.write.close()
            try? pair2.read.close()
        }
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        let switch_ = try RelaySwitch(sockets: [
            SocketPair(id: "xpc-service", read: pair1.read, write: pair2.write)
        ], policy: HostPolicy(network: .full))
        XCTAssertFalse(switch_.slotAcceptsAttach("xpc-service"),
            "a healthy attached slot must not accept a second attach")
        XCTAssertTrue(switch_.slotAcceptsAttach("never-seen"),
            "an id with no slot is always attachable")

        // Unhealthy but attached (the identity-probe-pending state):
        // the health flag alone must not open the slot.
        switch_.setMasterHealthyForTest(0, false)
        XCTAssertFalse(switch_.slotAcceptsAttach("xpc-service"),
            "an unhealthy slot whose socket is still open is still attached")
        let dummy1 = FileHandle.socketPair()
        let dummy2 = FileHandle.socketPair()
        XCTAssertThrowsError(try switch_.addMaster(SocketPair(
            id: "xpc-service", read: dummy1.read, write: dummy2.write
        ))) { error in
            guard case let RelaySwitchError.protocolError(msg) = error else {
                XCTFail("expected protocolError; got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("attached but unhealthy"),
                "the refusal names the real state: \(msg)")
        }
        switch_.setMasterHealthyForTest(0, true)

        // The slave drops its socket: the reader exits, the slot
        // detaches — without the pump having to run.
        release.signal()
        let deadline = Date().addingTimeInterval(5)
        while !switch_.slotAcceptsAttach("xpc-service") {
            XCTAssertLessThan(Date(), deadline, "the slot must detach once its socket is gone")
            if Date() >= deadline { break }
            Thread.sleep(forTimeInterval: 0.02)
        }

        // Reattach in place.
        let pair1b = FileHandle.socketPair()
        let pair2b = FileHandle.socketPair()
        let done2 = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2b.read)
            let writer = FrameWriter(handle: pair1b.write)
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            done2.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
            _ = try? reader.read()
        }
        XCTAssertEqual(done2.wait(timeout: .now() + 2), .success)
        let idx = try switch_.addMaster(SocketPair(
            id: "xpc-service", read: pair1b.read, write: pair2b.write
        ))
        XCTAssertEqual(idx, 0, "reattach must reuse slot 0")
        XCTAssertFalse(switch_.slotAcceptsAttach("xpc-service"), "a reattached slot is attached again")

        switch_.shutdown()
    }

    // TEST6745: RelaySwitch::new rejects duplicate ids in its cardinality list.
    func test6745_RelaySwitchInitRejectsDuplicateIds() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()
        let pair3 = FileHandle.socketPair()
        let pair4 = FileHandle.socketPair()
        XCTAssertThrowsError(try RelaySwitch(sockets: [
            SocketPair(id: "dup-id", read: pair1.read, write: pair2.write),
            SocketPair(id: "dup-id", read: pair3.read, write: pair4.write),
        ], policy: HostPolicy(network: .full))) { error in
            guard case let RelaySwitchError.protocolError(msg) = error else {
                XCTFail("expected protocolError; got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("duplicate master id 'dup-id'"),
                "error should name the duplicate id: \(msg)")
        }
    }

    // ============================================================
    // Deferred runtime identity probe / health-filtered routing /
    // capability-watch cluster. Ports the Rust reference tests
    // test0131 / test0135 / test0138 / test0141 plus Swift-specific
    // coverage of the peer-REQ NO_HANDLER-ERR-to-caller behaviour and
    // addMaster's identity-failure → register-unhealthy behaviour.
    //
    // Swift note: these run end-to-end through the per-master reader
    // threads and the lazily-spawned probe-driver thread. No engine
    // pump (readFromMasters) is needed for the deferred-probe tests —
    // the probe completes autonomously; the test only polls the public
    // health / routability surface. Routability is ALWAYS checked via
    // the dispatch path (routableMaster → findMasterForCap →
    // isDispatchable), NEVER by string-comparing cap URNs.

    /// Send an EMPTY initial RelayNotify (no installed cartridges, no
    /// caps), so `RelaySwitch.init` skips the synchronous identity probe
    /// and the master joins capless+healthy.
    private func sendNotifyEmpty(writer: FrameWriter, limits: Limits) throws {
        let manifestBytes = try JSONSerialization.data(withJSONObject: [
            "installed_cartridges": [] as [Any]
        ])
        try writer.write(Frame.relayNotify(manifest: manifestBytes, limits: limits))
    }

    /// Test slave for the DEFERRED runtime-identity-probe path. Mirrors
    /// the Rust helper `slave_deferred_identity`: an EMPTY initial
    /// RelayNotify (init skips the synchronous probe), then a POPULATED
    /// RelayNotify carrying `caps` (the empty→non-empty transition the
    /// relay must re-verify before routing). It then answers the runtime
    /// identity probe: if `succeed`, it echoes the probe's nonce back on
    /// the same flow (probe passes → master flips healthy → caps
    /// routable); if `!succeed`, it replies ERR (probe fails → master
    /// stays unhealthy, caps held back).
    ///
    /// The echo frames are assigned contiguous per-flow seq numbers via a
    /// `SeqAssigner`, because the switch's master-read path validates
    /// ordering through a `ReorderBuffer` keyed by (rid, xid) — exactly
    /// what a real CartridgeHost / RelaySlave does on its outbound stage.
    private func slaveDeferredIdentity(
        readHandle: FileHandle,
        writeHandle: FileHandle,
        caps: [String],
        limits: Limits,
        succeed: Bool
    ) {
        var reader = FrameReader(handle: readHandle)
        let writer = FrameWriter(handle: writeHandle)
        let seq = SeqAssigner()

        // 1. Empty initial RelayNotify — init skips the synchronous probe.
        try? sendNotifyEmpty(writer: writer, limits: limits)
        // 2. Populated RelayNotify — the empty→non-empty transition.
        try? sendNotify(writer: writer, capabilities: caps, limits: limits)

        // 3. Answer the runtime identity probe.
        var probeRid: MessageId? = nil
        var probeXid: MessageId? = nil
        var nonce = Data()
        while true {
            guard let frame = try? reader.read() else { return }
            switch frame.frameType {
            case .req:
                probeRid = frame.id
                probeXid = frame.routingId
                if !succeed {
                    // Broken identity handler: reply ERR on the same flow.
                    var err = Frame.err(id: frame.id, code: "BROKEN", attributionClass: .internal, message: "test cartridge")
                    err.routingId = frame.routingId
                    seq.assign(&err)
                    try? writer.write(err)
                    return
                }
            case .chunk:
                if let p = frame.payload { nonce.append(p) }
            case .end:
                guard let rid = probeRid, let xid = probeXid else { return }
                let streamId = "identity-echo"
                var ss = Frame.streamStart(reqId: rid, streamId: streamId, mediaUrn: "media:")
                ss.routingId = xid
                seq.assign(&ss)
                try? writer.write(ss)
                let checksum = Frame.computeChecksum(nonce)
                var chunk = Frame.chunk(reqId: rid, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum)
                chunk.routingId = xid
                seq.assign(&chunk)
                try? writer.write(chunk)
                var se = Frame.streamEnd(reqId: rid, streamId: streamId, chunkCount: 1)
                se.routingId = xid
                seq.assign(&se)
                try? writer.write(se)
                var end = Frame.end(id: rid)
                end.routingId = xid
                seq.assign(&end)
                try? writer.write(end)
                return
            default:
                break
            }
        }
    }

    // TEST0131: empty→non-empty cap transition requires a runtime identity
    // probe; a master that fails the probe (ERR) ends up UNHEALTHY with
    // lastError populated, and its caps are NOT routable.
    func test0131_runtimeIdentityProbeRequiredOnEmptyToNonemptyTransition() throws {
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        DispatchQueue.global().async {
            self.slaveDeferredIdentity(
                readHandle: pair2.read,
                writeHandle: pair1.write,
                caps: [CSCapIdentity, "cap:in=\"media:void\";test;out=\"media:void\""],
                limits: Limits(),
                succeed: false  // broken identity handler → master stays unhealthy
            )
        }

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-0131", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // Poll until the probe driver fails the probe and marks the master
        // unhealthy with a recorded error.
        let deadline = Date().addingTimeInterval(15)
        var unhealthy = false
        while Date() < deadline {
            let health = switch_.getMasterHealth()
            if let m = health.first, !m.healthy, m.lastError != nil {
                unhealthy = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(unhealthy, "master must be marked unhealthy with lastError after the runtime identity probe fails")

        // The unhealthy master's caps must NOT be routable — checked via
        // the dispatch path, never a string compare.
        XCTAssertNil(
            switch_.routableMaster(forCap: "cap:in=\"media:void\";test;out=\"media:void\""),
            "an unverified master's caps must be excluded from routing"
        )

        switch_.shutdown()
    }

    // TEST0135: the runtime identity probe SUCCESS path — a master that
    // advertises caps AFTER connecting (empty→non-empty) and then passes
    // the probe must flip healthy and its caps must become routable.
    func test0135_runtimeIdentityProbeSuccessMakesCapsRoutable() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        DispatchQueue.global().async {
            self.slaveDeferredIdentity(
                readHandle: pair2.read,
                writeHandle: pair1.write,
                caps: [CSCapIdentity, "cap:in=\"media:void\";test;out=\"media:void\""],
                limits: Limits(),
                succeed: true  // probe succeeds
            )
        }

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-0135", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // The post-init advertised cap becomes routable only AFTER the
        // probe passes (held back while the master is unhealthy).
        let deadline = Date().addingTimeInterval(15)
        var routable = false
        while Date() < deadline {
            if switch_.routableMaster(forCap: "cap:in=\"media:void\";test;out=\"media:void\"") == 0 {
                routable = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(routable, "after a successful runtime identity probe the master's post-init advertised cap must become routable")

        let health = switch_.getMasterHealth()
        XCTAssertEqual(health.first?.healthy, true, "master must be healthy after a successful runtime identity probe")
        XCTAssertNil(health.first?.lastError, "lastError must be cleared after a successful probe")

        switch_.shutdown()
    }

    // TEST1897: the installed-cartridge INVENTORY is NOT health-filtered.
    // A master held unhealthy by a failed runtime identity probe still has
    // its cartridges visible in the aggregate inventory, even though its
    // caps are excluded from ROUTING. Pins the deliberate asymmetry.
    func test1897_unhealthyMasterInventoryRetainedButNotRoutable() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        DispatchQueue.global().async {
            self.slaveDeferredIdentity(
                readHandle: pair2.read,
                writeHandle: pair1.write,
                caps: [CSCapIdentity, "cap:in=\"media:void\";test;out=\"media:void\""],
                limits: Limits(),
                succeed: false  // probe fails → master stays unhealthy
            )
        }

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-0138", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        let deadline = Date().addingTimeInterval(15)
        var unhealthy = false
        while Date() < deadline {
            let health = switch_.getMasterHealth()
            if let m = health.first, !m.healthy, m.lastError != nil {
                unhealthy = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(unhealthy, "master must be unhealthy after the probe fails")

        // ROUTING: the unhealthy master's caps are excluded.
        XCTAssertNil(
            switch_.routableMaster(forCap: "cap:in=\"media:void\";test;out=\"media:void\""),
            "an unhealthy master's caps must NOT be routable"
        )

        // INVENTORY: the cartridge is STILL visible — the inventory
        // aggregate is deliberately not health-filtered.
        let inventory = switch_.installedCartridges()
        XCTAssertTrue(
            inventory.contains { $0.id == "test-cartridge" },
            "an unhealthy master's installed cartridges must remain visible in the inventory aggregate, got: \(inventory.map { $0.id })"
        )

        switch_.shutdown()
    }

    // TEST1898: the routable-capability watch (subscribeCapabilities). A
    // subscriber must receive the CURRENT routable cap set on subscribe
    // even though it was rebuilt during construction — BEFORE any receiver
    // existed (the watch must persist the value, i.e. send_replace
    // semantics). The delivered set must be the health-filtered routable
    // cap URNs.
    func test1898_subscribeCapabilitiesDeliversRoutableSet() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            try! self.sendNotify(
                writer: writer,
                capabilities: [CSCapIdentity, "cap:in=\"media:void\";test;out=\"media:void\""],
                limits: Limits()
            )
            done.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
        }
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)

        // Capabilities are rebuilt inside init — before we subscribe.
        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-0141", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        let rx = switch_.subscribeCapabilities()
        let watched = rx.value()

        // The watch must mirror the synchronous getter: identical
        // serialized routable-set snapshot. This is a snapshot-identity
        // check (same bytes from the same source) and catches the bug this
        // guards: the snapshot is rebuilt inside init BEFORE any subscriber
        // exists, so the watch must persist it (send_replace). A plain
        // fire-and-forget send would leave the watch holding the empty
        // initial value while the getter returns the populated set.
        XCTAssertEqual(
            watched,
            switch_.capabilities(),
            "the capability watch must deliver the same routable-set snapshot as capabilities()"
        )

        // Prove that snapshot is the live ROUTABLE set the only correct way
        // — via dispatch conformance, not string comparison of URNs.
        XCTAssertEqual(
            switch_.routableMaster(forCap: "cap:in=\"media:void\";test;out=\"media:void\""),
            0,
            "the routable set the watch delivers must make the master's advertised cap dispatchable"
        )

        switch_.shutdown()
    }

    // TEST0142 (Swift-specific, gap 3): a peer cartridge→cartridge REQ for
    // a cap with NO handler must NOT abort the pump. The switch sends an
    // ERR("NO_HANDLER") frame straight back to the calling master (stamped
    // with the synthetic XID) so the caller fails fast, and
    // handleMasterFrame returns nil — it must NOT throw.
    func test1905_peerReqNoHandlerSendsErrToCaller() throws {
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let ready = DispatchSemaphore(value: 0)
        let errReceived = DispatchSemaphore(value: 0)
        var receivedCode: String? = nil
        var receivedHadXid = false

        DispatchQueue.global().async {
            var reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            ready.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Send a peer REQ (no XID) for a cap no master handles.
            let req = Frame.req(
                id: MessageId.uint(7),
                capUrn: "cap:in=\"media:void\";nonexistent;out=\"media:void\"",
                payload: Data(),
                contentType: "application/octet-stream"
            )
            try! writer.write(req)

            // Expect an ERR("NO_HANDLER") stamped with an XID to come back.
            while let frame = try? reader.read() {
                if frame.frameType == .err {
                    receivedCode = frame.errorCode
                    receivedHadXid = frame.routingId != nil
                    errReceived.signal()
                    return
                }
            }
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-0142", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // Pump the master frames in the background so the peer REQ is
        // processed (the call returns nil after sending the ERR; it must
        // NOT throw — try? would swallow a throw, so we assert the ERR
        // actually arrives at the caller, which only happens on the
        // non-throwing path).
        DispatchQueue.global().async {
            _ = try? switch_.readFromMasters(timeout: 3.0)
        }

        XCTAssertEqual(errReceived.wait(timeout: .now() + 4), .success, "caller must receive an ERR frame, not hang")
        XCTAssertEqual(receivedCode, "NO_HANDLER", "ERR code must be NO_HANDLER")
        XCTAssertTrue(receivedHadXid, "the NO_HANDLER ERR must carry the synthetic XID (path-C invariant)")

        switch_.shutdown()
    }

    // TEST0143 (Swift-specific, gap 5): addMaster whose identity probe
    // FAILS must register the master UNHEALTHY (keeping its inventory
    // visible) rather than throwing. Caps stay held back from routing.
    func test0143_addMasterIdentityFailureRegistersUnhealthy() throws {
        let switch_ = try RelaySwitch(sockets: [], policy: HostPolicy(network: .full))

        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()
        let ready = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2.read)
            let writer = FrameWriter(handle: pair1.write)
            try! self.sendNotify(
                writer: writer,
                capabilities: [CSCapIdentity, "cap:in=\"media:void\";test;out=\"media:void\""],
                limits: Limits()
            )
            ready.signal()
            // The switch's policy comes first (12.2 §Policy).
            guard let policy = try? reader.read(), policy.frameType == .policy else { return }
            // Reply ERR to the identity REQ — a broken identity handler.
            if let frame = try? reader.read(), frame.frameType == .req {
                try! writer.write(Frame.err(id: frame.id, code: "IDENTITY_FAILED", attributionClass: .internal, message: "Rejected"))
            }
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 2), .success)

        // addMaster MUST NOT throw on identity failure — it registers the
        // master unhealthy and returns its slot index.
        let idx = try switch_.addMaster(SocketPair(id: "broken-master", read: pair1.read, write: pair2.write))
        XCTAssertEqual(idx, 0)

        let health = switch_.getMasterHealth()
        XCTAssertEqual(health.count, 1)
        XCTAssertEqual(health.first?.healthy, false, "a master whose identity probe failed must be registered unhealthy")
        XCTAssertNotNil(health.first?.lastError, "the failure reason must be recorded in lastError")

        // Caps are NOT routable (cap_table skips unhealthy masters).
        XCTAssertNil(
            switch_.routableMaster(forCap: "cap:in=\"media:void\";test;out=\"media:void\""),
            "an unhealthy master's caps must NOT be routable"
        )

        // Inventory remains visible — not health-filtered.
        XCTAssertTrue(
            switch_.installedCartridges().contains { $0.id == "test-cartridge" },
            "the failed master's installed cartridges must remain visible in the inventory aggregate"
        )

        switch_.shutdown()
    }

    // TEST7091: Host protocol stats carried by a master's RelayNotify are
    // RETAINED by the switch (not parsed-and-discarded) and surface in
    // `protocolStats().hosts` keyed by master id; a master that has not yet
    // advertised stats is absent from the map — never a zeroed placeholder.
    func test7091_switchRetainsHostProtocolStatsFromRelayNotify() throws {
        let pair1 = FileHandle.socketPair()  // engine_read, slave_write
        let pair2 = FileHandle.socketPair()  // slave_read, engine_write

        let notifySent = DispatchSemaphore(value: 0)
        let emptyChecked = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2.read, limits: Limits())
            let writer = FrameWriter(handle: pair1.write, limits: Limits())

            // Initial advertisement — NO host stats (identity gates first).
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            notifySent.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)

            // Hold the republish until the test has asserted the empty
            // pre-state, so the "absent before advertised" check is
            // deterministic rather than a race against the reader loop.
            XCTAssertEqual(emptyChecked.wait(timeout: .now() + 5), .success)

            // Republish the SAME inventory (no cap change → no re-verify),
            // now carrying host protocol stats — the periodic refresh path.
            let manifestBytes = try! JSONSerialization.data(withJSONObject: [
                "installed_cartridges": [[
                    "registry_url": NSNull(),
                    "channel": "release",
                    "id": "test-cartridge",
                    "version": "0.0.0",
                    "sha256": String(repeating: "0", count: 64),
                    "runtime_stats": [
                        "running": true,
                        "pools": Self.testPoolStatesJSON(capUrns: [CSCapIdentity]),
                        "active_request_count": 0,
                        "peer_request_count": 0,
                        "memory_footprint_mb": 0,
                        "memory_rss_mb": 0,
                        "restart_count": 0,
                    ] as [String: Any],
                    "cap_groups": [[
                        "name": "test",
                        "caps": [[
                            "urn": CSCapIdentity,
                            "title": "test",
                            "aliases": ["test"],
                            "args": [] as [Any],
                        ]],
                        "adapter_urns": [] as [String],
                    ]],
                ]],
                "host_protocol_stats": [
                    "drops": ["total": 3, "by_reason": ["post_terminal": 2, "no_route": 1]],
                    "outgoing_rids": 4,
                    "incoming_rxids": 6,
                    "incoming_to_peer_rids": 0,
                    "outgoing_max_seq": 2,
                    "routing_gc_runs_total": 1,
                    "routing_gc_evicted_total": 9,
                ],
            ])
            try! writer.write(Frame.relayNotify(manifest: manifestBytes, limits: Limits()))
        }

        XCTAssertEqual(notifySent.wait(timeout: .now() + 2), .success)
        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "test-master-7091", read: pair1.read, write: pair2.write)], policy: HostPolicy(network: .full))

        // The initial advertisement carried no host stats: absent, not zeroed.
        XCTAssertTrue(
            switch_.protocolStats().hosts.isEmpty,
            "no host stats before a RelayNotify carries them"
        )
        emptyChecked.signal()

        // The republish is applied by the reader loop — poll until it lands.
        let deadline = Date().addingTimeInterval(2)
        var retained: HostProtocolStats?
        while Date() < deadline {
            if let host = switch_.protocolStats().hosts["test-master-7091"] {
                retained = host
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let stats = try XCTUnwrap(
            retained,
            "host stats must surface in protocolStats().hosts after RelayNotify"
        )
        XCTAssertEqual(stats.drops.total, 3)
        XCTAssertEqual(stats.drops.byReason["post_terminal"], 2)
        XCTAssertEqual(stats.incomingRxids, 6)
        XCTAssertEqual(stats.routingGcEvictedTotal, 9)

        switch_.shutdown()
    }
}

// Helper extension for creating socket pairs
extension FileHandle {
    static func socketPair() -> (read: FileHandle, write: FileHandle) {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        return (
            read: FileHandle(fileDescriptor: fds[0], closeOnDealloc: true),
            write: FileHandle(fileDescriptor: fds[1], closeOnDealloc: true)
        )
    }
}

// =============================================================================
// A peer request no master serves, held while the switch's provider brings
// the master that serves it (PeerHold.swift, 14.2 §Peer requests no master
// serves) — TEST463–TEST471.
//
// Every test runs a real switch over real sockets: a caller master that makes
// a peer call, and — when the provider brings it — a second master serving
// the peer cap, attached to the running switch. The masters speak the wire
// protocol themselves, as this suite's other tests do; a pump thread drives
// the switch's inbound stream as a host's loop does.
// =============================================================================

private let peerProvidedCap = "cap:in=\"media:enc=utf8\";peer-provided;out=\"media:enc=utf8\""
private let peerCallerCap = "cap:in=\"media:enc=utf8\";peer-caller;out=\"media:enc=utf8\""
private let peerUnrelatedCap = "cap:in=\"media:enc=utf8\";peer-unrelated;out=\"media:enc=utf8\""
private let peerRoomy = PeerHoldBound(frames: 64, bytes: 1 << 20, deadline: 10)

private func peerTestExpiry() -> PeerRefusal {
    PeerRefusal(
        code: "TEST_PROVIDER_TIMEOUT",
        attributionClass: .environment,
        message: "testcartridge, which provides peer-provided, was not started in time"
    )
}

/// A count several threads add to.
private final class PeerCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// A master whose cartridge makes peer calls: each call's answer is
/// "ok:<the bytes the peer answered>", or "err:<CODE>:<message>" with the ERR
/// the call ended with.
private final class PeerCaller: @unchecked Sendable {
    let writer: FrameWriter
    private let seq = SeqAssigner()
    private let lock = NSLock()
    private var answers: [String] = []
    private let answered = DispatchSemaphore(value: 0)

    init(writer: FrameWriter) {
        self.writer = writer
    }

    /// Read the switch's answers to this master's peer calls until its
    /// connection closes.
    func serve(_ reader: FrameReader) {
        var bodies: [MessageId: Data] = [:]
        while let frame = try? reader.read() {
            switch frame.frameType {
            case .chunk:
                bodies[frame.id, default: Data()].append(frame.payload ?? Data())
            case .end:
                let body = bodies.removeValue(forKey: frame.id) ?? Data()
                record("ok:" + String(decoding: body, as: UTF8.self))
            case .err:
                bodies[frame.id] = nil
                record("err:\(frame.errorCode ?? ""):\(frame.errorMessage ?? "")")
            default:
                break
            }
        }
    }

    private func record(_ answer: String) {
        lock.lock()
        answers.append(answer)
        lock.unlock()
        answered.signal()
    }

    /// Send one peer call to peerProvidedCap, as a cartridge's peer invoker
    /// does: the REQ with no routing id, its argument stream, its END — and,
    /// when asked, a CANCEL for it after.
    func call(_ argument: Data, cancel: Bool = false) throws {
        let rid = MessageId.newUUID()
        let streamId = "arg-0"
        var frames = [
            Frame.req(id: rid, capUrn: peerProvidedCap, payload: Data(), contentType: "application/cbor"),
            Frame.streamStart(reqId: rid, streamId: streamId, mediaUrn: "media:enc=utf8"),
            Frame.chunk(reqId: rid, streamId: streamId, seq: 0, payload: argument, chunkIndex: 0, checksum: Frame.computeChecksum(argument)),
            Frame.streamEnd(reqId: rid, streamId: streamId, chunkCount: 1),
            Frame.end(id: rid),
        ]
        if cancel {
            frames.append(Frame.cancel(targetRid: rid, reason: .user()))
        }
        for var frame in frames {
            seq.assign(&frame)
            try writer.write(frame)
        }
    }

    /// The next peer call's answer, or nil after 30 s.
    func answer() -> String? {
        guard answered.wait(timeout: .now() + 30) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return answers.removeFirst()
    }
}

/// Brings a master the way a host's provider brings a cartridge: it attaches
/// one to the switch it was set on.
private final class TestPeerProvider: PeerProvider, @unchecked Sendable {
    weak var switch_: RelaySwitch?
    let asked = PeerCounter()
    let served = PeerCounter()
    /// The cap the master it brings serves, and how long bringing it takes;
    /// `refusal`, when set, is what it answers instead.
    let urn: String
    let delay: TimeInterval
    let refusal: PeerRefusal?
    /// Starts the master it brings: its id, its cap, its counter.
    var startUpper: ((String, String, PeerCounter) -> SocketPair)!

    init(urn: String = peerProvidedCap, delay: TimeInterval = 0, refusal: PeerRefusal? = nil) {
        self.urn = urn
        self.delay = delay
        self.refusal = refusal
    }

    func provision(capUrn: String) -> Result<PeerProvision, PeerRefusal> {
        precondition(capUrn == peerProvidedCap, "the provider is asked for the cap the peer call named")
        asked.add()
        if let refusal = refusal {
            return .failure(refusal)
        }
        return .success(PeerProvision(
            ready: { [self] in
                Thread.sleep(forTimeInterval: delay)
                guard let switch_ = switch_ else {
                    return PeerRefusal(code: "TEST_ATTACH_FAILED", attributionClass: .internal, message: "the switch is gone")
                }
                do {
                    _ = try switch_.addMaster(startUpper("provided-host", urn, served))
                    return nil
                } catch {
                    return PeerRefusal(code: "TEST_ATTACH_FAILED", attributionClass: .internal, message: "\(error)")
                }
            },
            onExpiry: peerTestExpiry()
        ))
    }
}

@available(macOS 10.15.4, iOS 13.4, *)
extension CborRelaySwitchTests {

    /// Connect a master serving `urn`: it answers each request with its
    /// argument upper-cased, and counts the requests it served.
    private func startUpper(_ id: String, _ urn: String, _ served: PeerCounter) -> SocketPair {
        let toSwitch = FileHandle.socketPair()
        let fromSwitch = FileHandle.socketPair()
        let sent = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let reader = FrameReader(handle: fromSwitch.read)
            let writer = FrameWriter(handle: toSwitch.write)
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity, urn], limits: Limits())
            sent.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
            let seq = SeqAssigner()
            var arguments: [MessageId: Data] = [:]
            while let frame = try? reader.read() {
                switch frame.frameType {
                case .req:
                    arguments[frame.id] = Data()
                case .chunk:
                    arguments[frame.id, default: Data()].append(frame.payload ?? Data())
                case .end:
                    served.add()
                    let argument = arguments.removeValue(forKey: frame.id) ?? Data()
                    let answer = Data(String(decoding: argument, as: UTF8.self).uppercased().utf8)
                    let streamId = "answer"
                    for var out in [
                        Frame.streamStart(reqId: frame.id, streamId: streamId, mediaUrn: "media:enc=utf8"),
                        Frame.chunk(reqId: frame.id, streamId: streamId, seq: 0, payload: answer, chunkIndex: 0, checksum: Frame.computeChecksum(answer)),
                        Frame.streamEnd(reqId: frame.id, streamId: streamId, chunkCount: 1),
                        Frame.end(id: frame.id),
                    ] {
                        out.routingId = frame.routingId
                        seq.assign(&out)
                        try? writer.write(out)
                    }
                default:
                    break
                }
            }
        }
        _ = sent.wait(timeout: .now() + 5)
        return SocketPair(id: id, read: toSwitch.read, write: fromSwitch.write)
    }

    /// A switch with one master — the caller — pumped as a host's loop pumps
    /// it, and, when given, `provider` as its peer provider within `bound`.
    /// The returned stop ends the pump and the switch.
    private func peerSwitch(_ provider: TestPeerProvider?, _ bound: PeerHoldBound) throws -> (RelaySwitch, PeerCaller, () -> Void) {
        let toSwitch = FileHandle.socketPair()
        let fromSwitch = FileHandle.socketPair()
        let caller = PeerCaller(writer: FrameWriter(handle: toSwitch.write))
        let sent = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let reader = FrameReader(handle: fromSwitch.read)
            try! self.sendNotify(writer: caller.writer, capabilities: [CSCapIdentity, peerCallerCap], limits: Limits())
            sent.signal()
            try! self.handleIdentityVerification(reader: reader, writer: caller.writer)
            caller.serve(reader)
        }
        XCTAssertEqual(sent.wait(timeout: .now() + 5), .success)
        let switch_ = try RelaySwitch(
            sockets: [SocketPair(id: "caller-host", read: toSwitch.read, write: fromSwitch.write)],
            policy: HostPolicy(network: .full)
        )
        if let provider = provider {
            provider.switch_ = switch_
            provider.startUpper = { [unowned self] id, urn, served in self.startUpper(id, urn, served) }
            try switch_.setPeerProvider(provider, bound: bound)
        }
        let stopped = PeerCounter()
        DispatchQueue.global().async {
            while stopped.value == 0 {
                _ = try? switch_.readFromMasters(timeout: 0.1)
            }
        }
        return (switch_, caller, { stopped.add(); switch_.shutdown() })
    }

    // TEST463: A peer call to a cap no master serves is held while the
    // switch's provider brings a master that serves it, and is then answered
    // by that master, with every argument byte the caller sent while it was
    // held.
    func test463_heldPeerCallIsAnsweredOnceItsProviderIsBrought() throws {
        let provider = TestPeerProvider(delay: 0.3)
        let (_, caller, stop) = try peerSwitch(provider, peerRoomy)
        defer { stop() }

        try caller.call(Data("hello peer".utf8))
        XCTAssertEqual(caller.answer(), "ok:HELLO PEER")
        XCTAssertEqual(provider.asked.value, 1)
        XCTAssertEqual(provider.served.value, 1)

        // Brought once: the next call is routed to it at once.
        try caller.call(Data("again".utf8))
        XCTAssertEqual(caller.answer(), "ok:AGAIN")
        XCTAssertEqual(provider.asked.value, 1, "a served cap is not provided again")
    }

    // TEST464: A provider that cannot bring what serves the cap ends the held
    // call with its own ERR — its code and its message, which name what is
    // missing and what to do.
    func test464_refusedProvisionEndsTheCallWithTheProvidersErr() throws {
        let refusal = PeerRefusal(
            code: "CARTRIDGE_INSTALL_FAILED",
            attributionClass: .environment,
            message: "testcartridge provides peer-provided and is not installed; " +
                "install it with: capdag cartridge install testcartridge"
        )
        let (_, caller, stop) = try peerSwitch(TestPeerProvider(refusal: refusal), peerRoomy)
        defer { stop() }

        try caller.call(Data("hello".utf8))
        XCTAssertEqual(caller.answer(), "err:\(refusal.code):\(refusal.message)")
    }

    // TEST465: A held call waits no longer than its deadline: it ends with the
    // provider's own expiry ERR. The provider's work goes on, so what it
    // brought late serves the next call.
    func test465_heldCallEndsAtItsDeadlineAndTheLateProviderServesTheNext() throws {
        var bound = peerRoomy
        bound.deadline = 0.3
        let provider = TestPeerProvider(delay: 1.5)
        let (_, caller, stop) = try peerSwitch(provider, bound)
        defer { stop() }

        let started = Date()
        try caller.call(Data("hello".utf8))
        let expired = peerTestExpiry()
        XCTAssertEqual(caller.answer(), "err:\(expired.code):\(expired.message)")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "the call ended at its deadline, not when the provider finished")
        XCTAssertEqual(provider.served.value, 0, "the expired call was not replayed")

        Thread.sleep(forTimeInterval: 1.5)
        try caller.call(Data("later".utf8))
        XCTAssertEqual(caller.answer(), "ok:LATER")
        XCTAssertEqual(provider.asked.value, 1)
    }

    // TEST466: A hold keeps no more frames than its bound: a call that sends
    // more while it is held ends with PEER_HOLD_OVERFLOW, and is never
    // replayed.
    func test466_heldCallPastItsFrameBoundEnds() throws {
        // REQ, STREAM_START, CHUNK, STREAM_END and END are five frames.
        var bound = peerRoomy
        bound.frames = 4
        let provider = TestPeerProvider(delay: 0.3)
        let (_, caller, stop) = try peerSwitch(provider, bound)
        defer { stop() }

        try caller.call(Data("hello".utf8))
        let answer = caller.answer() ?? "no answer"
        XCTAssertTrue(answer.hasPrefix("err:\(PEER_HOLD_OVERFLOW):"), answer)
        XCTAssertTrue(answer.contains("more than 4 frames"), answer)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(provider.served.value, 0)
    }

    // TEST467: A hold keeps no more payload bytes than its bound.
    func test467_heldCallPastItsByteBoundEnds() throws {
        var bound = peerRoomy
        bound.bytes = 1024
        let provider = TestPeerProvider(delay: 0.3)
        let (_, caller, stop) = try peerSwitch(provider, bound)
        defer { stop() }

        // 400 copies of "hello" is 2000 bytes, over the 1024 a hold keeps.
        try caller.call(Data(String(repeating: "hello", count: 400).utf8))
        let answer = caller.answer() ?? "no answer"
        XCTAssertTrue(answer.hasPrefix("err:\(PEER_HOLD_OVERFLOW):"), answer)
        XCTAssertTrue(answer.contains("1024 bytes"), answer)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(provider.served.value, 0)
    }

    // TEST468: A caller that cancels its held call is answered with its
    // cancel at once, and the call is not replayed to the provider brought
    // after.
    func test468_cancelledHeldCallEndsAtOnceAndIsNotReplayed() throws {
        let provider = TestPeerProvider(delay: 0.8)
        let (_, caller, stop) = try peerSwitch(provider, peerRoomy)
        defer { stop() }

        let started = Date()
        try caller.call(Data("hello".utf8), cancel: true)
        let answer = caller.answer() ?? "no answer"
        XCTAssertTrue(answer.hasPrefix("err:CANCELLED:"), answer)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8, "the cancel was answered before the provider was there")
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(provider.served.value, 0)
    }

    // TEST469: A provider whose master does not serve the cap leaves the call
    // held until its deadline, which ends it with the provider's expiry ERR;
    // the provider is asked once.
    func test469_providerThatServesSomethingElseEndsTheCallAtItsDeadline() throws {
        var bound = peerRoomy
        bound.deadline = 0.8
        let provider = TestPeerProvider(urn: peerUnrelatedCap, delay: 0.05)
        let (_, caller, stop) = try peerSwitch(provider, bound)
        defer { stop() }

        try caller.call(Data("hello".utf8))
        let expired = peerTestExpiry()
        XCTAssertEqual(caller.answer(), "err:\(expired.code):\(expired.message)")
        XCTAssertEqual(provider.asked.value, 1)
    }

    // TEST470: A switch without a provider refuses a peer call to a cap no
    // master serves at once, with NO_HANDLER naming the cap.
    func test470_withoutAProviderTheCallIsRefusedWithNoHandler() throws {
        let (_, caller, stop) = try peerSwitch(nil, peerRoomy)
        defer { stop() }

        try caller.call(Data("hello".utf8))
        let answer = caller.answer() ?? "no answer"
        XCTAssertTrue(answer.hasPrefix("err:NO_HANDLER:No handler found for cap:"), answer)
        XCTAssertTrue(answer.contains("peer-provided"), answer)
    }

    // TEST471: A switch takes one peer provider.
    func test471_aSecondPeerProviderIsRefused() throws {
        let provider = TestPeerProvider(refusal: peerTestExpiry())
        let (switch_, _, stop) = try peerSwitch(provider, peerRoomy)
        defer { stop() }

        XCTAssertThrowsError(try switch_.setPeerProvider(provider, bound: peerRoomy)) { error in
            XCTAssertTrue("\(error)".contains("already has a peer provider"), "\(error)")
        }
    }
}
