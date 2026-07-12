//
//  ProtocolV3Tests.swift
//  Bifaci
//
//  Protocol v3 parity tests (TEST7000–TEST7029) ported from the Rust
//  reference (capdag/src/bifaci/{io,frame,credit,stats}.rs).
//
//  Covers: handshake version enforcement + initial_credit negotiation,
//  CREDIT frames, unbounded streams, END terminal metadata, CreditGate/
//  CreditRouter flow control, drop counters, and terminated-flow tracking.
//
//  Tests use // TEST###: comments matching the Rust implementation for cross-tracking.
//

import XCTest
@testable import Bifaci
@preconcurrency import SwiftCBOR
import Foundation

// Test manifest JSON - cartridges MUST include manifest in HELLO response (including mandatory CAP_IDENTITY).
private let v3TestManifest = """
{"name":"TestCartridge","version":"1.0.0","channel":"release","description":"Test cartridge","cap_groups":[{"name":"default","caps":[{"urn":"cap:effect=none","title":"Identity","aliases":["identity"]}]}]}
""".data(using: .utf8)!

/// Thread-safe boolean flag for observing completion of concurrent waiters.
private final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// Thread-safe single-value box for capturing a concurrent waiter's result.
private final class TestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?

    func set(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class ProtocolV3Tests: XCTestCase {

    // MARK: - Helpers

    /// Helper: create Unix socket pairs for bidirectional communication
    private func createSocketPairs() -> (hostWrite: FileHandle, cartridgeRead: FileHandle,
                                         cartridgeWrite: FileHandle, hostRead: FileHandle) {
        var hostWritePair: [Int32] = [0, 0]
        var cartridgeWritePair: [Int32] = [0, 0]

        socketpair(AF_UNIX, SOCK_STREAM, 0, &hostWritePair)
        socketpair(AF_UNIX, SOCK_STREAM, 0, &cartridgeWritePair)

        let hostWrite = FileHandle(fileDescriptor: hostWritePair[0], closeOnDealloc: true)
        let cartridgeRead = FileHandle(fileDescriptor: hostWritePair[1], closeOnDealloc: true)
        let cartridgeWrite = FileHandle(fileDescriptor: cartridgeWritePair[0], closeOnDealloc: true)
        let hostRead = FileHandle(fileDescriptor: cartridgeWritePair[1], closeOnDealloc: true)

        return (hostWrite, cartridgeRead, cartridgeWrite, hostRead)
    }

    /// Run a full v3 handshake: host with default limits against a cartridge
    /// proposing `cartridgeLimits`. Returns both sides' negotiated results.
    private func runV3Handshake(cartridgeLimits: Limits) throws -> (host: HandshakeResult, cart: Limits) {
        let (hostWrite, cartridgeRead, cartridgeWrite, hostRead) = createSocketPairs()

        let cartResult = TestBox<Result<Limits, Error>>()
        let semaphore = DispatchSemaphore(value: 0)

        // Cartridge thread
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: cartridgeRead)
                let writer = FrameWriter(handle: cartridgeWrite, limits: cartridgeLimits)
                let limits = try acceptHandshakeWithManifest(reader: reader, writer: writer, manifest: v3TestManifest)
                cartResult.set(.success(limits))
            } catch {
                cartResult.set(.failure(error))
            }
            semaphore.signal()
        }

        // Host side
        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)
        let host = try performHandshakeWithManifest(reader: reader, writer: writer)

        guard semaphore.wait(timeout: .now() + 10) == .success else {
            throw FrameError.ioError("timed out waiting for cartridge thread")
        }
        let cart = try cartResult.get()!.get()
        return (host, cart)
    }

    /// Wait until `condition` holds or the timeout elapses; the caller asserts
    /// the condition afterwards so a timeout fails the test instead of hanging.
    private func waitUntil(timeout: TimeInterval = 1.0, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Handshake (TEST7000-7002)

    // TEST7000: v3 handshake succeeds and negotiates the element-wise minimum of all four limits including initial_credit
    func test7000_v3HandshakeNegotiatesAllFourLimits() throws {
        let cartridgeLimits = Limits(
            maxFrame: 2_000_000,
            maxChunk: 128_000,
            maxReorderBuffer: 32,
            initialCredit: 16
        )
        let (host, cart) = try runV3Handshake(cartridgeLimits: cartridgeLimits)

        XCTAssertEqual(host.limits.maxFrame, 2_000_000, "min(3.5MB, 2MB)")
        XCTAssertEqual(host.limits.maxChunk, 128_000, "min(256KB, 128KB)")
        XCTAssertEqual(host.limits.maxReorderBuffer, 32, "min(64, 32)")
        XCTAssertEqual(host.limits.initialCredit, 16, "min(32, 16)")
        XCTAssertFalse(host.manifest?.isEmpty ?? true, "manifest must be extracted")

        XCTAssertEqual(cart.initialCredit, 16)
        XCTAssertEqual(cart.maxReorderBuffer, 32)
    }

    // TEST7001: HELLO carrying protocol version 2 is rejected at handshake with a version-mismatch error
    func test7001_handshakeRejectsVersion2() throws {
        let (hostWrite, cartridgeRead, cartridgeWrite, hostRead) = createSocketPairs()

        let semaphore = DispatchSemaphore(value: 0)

        // Fake v2 cartridge: replies to the host HELLO with a version=2 HELLO.
        DispatchQueue.global().async {
            do {
                let reader = FrameReader(handle: cartridgeRead)
                let writer = FrameWriter(handle: cartridgeWrite)
                _ = try reader.read() // host HELLO
                var hello = Frame.helloWithManifest(limits: Limits(), manifest: v3TestManifest)
                hello.version = 2
                hello.meta?["version"] = .unsignedInt(2)
                try writer.write(hello)
            } catch {
                XCTFail("fake v2 cartridge failed: \(error)")
            }
            semaphore.signal()
        }

        let reader = FrameReader(handle: hostRead)
        let writer = FrameWriter(handle: hostWrite)

        XCTAssertThrowsError(try performHandshakeWithManifest(reader: reader, writer: writer), "v2 HELLO must be rejected") { error in
            let msg = (error as? FrameError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("version"), "error must name the version mismatch: \(msg)")
            XCTAssertTrue(msg.contains("2") && msg.contains("3"), "error must state both versions: \(msg)")
        }
        XCTAssertEqual(semaphore.wait(timeout: .now() + 10), .success, "timed out waiting for cartridge thread")
    }

    // TEST7002: initial_credit negotiation picks the element-wise minimum of the two proposals
    func test7002_initialCreditNegotiatedMinimum() throws {
        // Cartridge proposes a smaller window than the host default (32) → 8 wins.
        let smaller = Limits(initialCredit: 8)
        let (smallHost, smallCart) = try runV3Handshake(cartridgeLimits: smaller)
        XCTAssertEqual(smallHost.limits.initialCredit, 8)
        XCTAssertEqual(smallCart.initialCredit, 8)

        // Cartridge proposes a larger window (128) → the host default 32 wins.
        let larger = Limits(initialCredit: 128)
        let (largeHost, largeCart) = try runV3Handshake(cartridgeLimits: larger)
        XCTAssertEqual(largeHost.limits.initialCredit, 32)
        XCTAssertEqual(largeCart.initialCredit, 32)
    }

    // MARK: - CREDIT and unbounded-stream frames (TEST7010-7014, TEST7026)

    // TEST7010: CREDIT frame round-trips encode/decode with rid, stream_id, and credit count
    func test7010_creditFrameRoundtrip() throws {
        let rid = MessageId.newUUID()
        let frame = Frame.credit(targetRid: rid, streamId: "s1", credits: 17, direction: .response)
        XCTAssertEqual(frame.creditCount, 17)

        var decoded = try decodeFrame(try encodeFrame(frame))
        XCTAssertEqual(decoded.frameType, .credit)
        XCTAssertEqual(decoded.id, rid)
        XCTAssertEqual(decoded.streamId, "s1")
        XCTAssertEqual(decoded.creditCount, 17)
        XCTAssertEqual(
            decoded.creditDirection, .response,
            "the routing direction must survive the wire (L11)"
        )

        // Stream-less grant (request's sole stream) round-trips too
        decoded = try decodeFrame(try encodeFrame(Frame.credit(targetRid: rid, streamId: nil, credits: 3, direction: .request)))
        XCTAssertNil(decoded.streamId)
        XCTAssertEqual(decoded.creditCount, 3)
        XCTAssertEqual(decoded.creditDirection, .request)

        // A Credit frame with no direction reports nil — hosts drop it as
        // unroutable (counted), since (xid, rid) alone cannot place it.
        var dirless = Frame(frameType: .credit, id: .newUUID())
        dirless.credit = 1
        XCTAssertNil(dirless.creditDirection)

        // creditCount is nil on non-Credit frames even if the field is set
        var chunkish = Frame(frameType: .log, id: rid)
        chunkish.credit = 9
        XCTAssertNil(chunkish.creditCount)
    }

    // TEST7011: CREDIT is a non-flow frame — no seq assigned, passes the reorder buffer untouched regardless of flow state
    func test7011_creditIsNonFlow() throws {
        let rid = MessageId.newUUID()

        // SeqAssigner leaves Credit at seq 0 while flow frames advance
        let assigner = SeqAssigner()
        var chunk = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([1]), chunkIndex: 0, checksum: 1)
        assigner.assign(&chunk)
        XCTAssertEqual(chunk.seq, 0)
        var credit = Frame.credit(targetRid: rid, streamId: "s1", credits: 4, direction: .response)
        assigner.assign(&credit)
        XCTAssertEqual(credit.seq, 0, "Credit must not consume a flow seq")
        var chunk2 = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: Data([2]), chunkIndex: 1, checksum: 1)
        assigner.assign(&chunk2)
        XCTAssertEqual(chunk2.seq, 1, "flow seq must be contiguous across a Credit")

        // ReorderBuffer returns Credit immediately even while the flow is gapped
        let buffer = ReorderBuffer(maxBufferPerFlow: 8)
        var gapped = Frame.chunk(reqId: rid, streamId: "s1", seq: 5, payload: Data([3]), chunkIndex: 5, checksum: 1)
        gapped.seq = 5
        XCTAssertTrue(try buffer.accept(gapped).isEmpty, "out-of-order flow frame must be buffered")
        let creditFrame = Frame.credit(targetRid: rid, streamId: "s1", credits: 4, direction: .response)
        let delivered = try buffer.accept(creditFrame)
        XCTAssertEqual(delivered.count, 1, "Credit must bypass the reorder buffer and deliver immediately")
        XCTAssertEqual(delivered[0].frameType, .credit)
    }

    // TEST7012: STREAM_START unbounded flag round-trips through CBOR; absent flag means bounded
    func test7012_streamStartUnboundedRoundtrip() throws {
        let rid = MessageId.newUUID()
        let bounded = Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:enc=utf-8", isSequence: false)
        XCTAssertFalse(bounded.isUnbounded)
        var decoded = try decodeFrame(try encodeFrame(bounded))
        XCTAssertFalse(decoded.isUnbounded, "absent flag must read as bounded")
        XCTAssertNil(decoded.unbounded, "bounded frames omit the key")

        let unbounded = Frame.streamStartUnbounded(reqId: rid, streamId: "s2", mediaUrn: "media:enc=utf-8", isSequence: true)
        XCTAssertTrue(unbounded.isUnbounded)
        decoded = try decodeFrame(try encodeFrame(unbounded))
        XCTAssertTrue(decoded.isUnbounded)
        XCTAssertEqual(decoded.streamId, "s2")
        XCTAssertEqual(decoded.isSequence, true)
    }

    // TEST7013: CBOR decode REJECTS a CREDIT frame missing its credit count
    func test7013_cborRejectsCreditWithoutCount() throws {
        var frame = Frame(frameType: .credit, id: .newUUID())
        frame.streamId = "s1"
        // credit deliberately missing

        let encoded = try encodeFrame(frame)
        XCTAssertThrowsError(try decodeFrame(encoded), "decode must reject CREDIT without a credit count") { error in
            guard case FrameError.protocolError(let msg) = error else {
                XCTFail("Expected protocolError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("credit") || msg.contains("CREDIT"), "error must name the missing field: \(msg)")
        }
    }

    // TEST7014: END terminal meta (progress, message) round-trips; successful END without progress reads as 1.0; failed END without progress reads as None
    func test7014_endTerminalMetaRoundtrip() throws {
        let rid = MessageId.newUUID()

        // Explicit terminal progress + message round-trip
        let end = Frame.endOkWith(id: rid, finalPayload: nil, progress: 0.87, message: "partial corpus")
        var decoded = try decodeFrame(try encodeFrame(end))
        XCTAssertEqual(decoded.finalProgress(), 0.87)
        XCTAssertEqual(decoded.finalMessage(), "partial corpus")
        XCTAssertEqual(decoded.exitCode, 0, "end_ok_with implies success")

        // Successful END with no explicit progress reads as 1.0
        decoded = try decodeFrame(try encodeFrame(Frame.endOk(id: rid, finalPayload: nil)))
        XCTAssertEqual(decoded.finalProgress(), 1.0)
        XCTAssertNil(decoded.finalMessage())

        // Non-successful END (no exit_code) with no explicit progress: nil —
        // failure must not synthesize a completion value.
        decoded = try decodeFrame(try encodeFrame(Frame.end(id: rid, finalPayload: nil)))
        XCTAssertNil(decoded.finalProgress())

        // Non-END frames never report a final progress
        let log = Frame.progress(id: rid, progress: 0.5, message: "halfway")
        XCTAssertNil(log.finalProgress())
    }

    // TEST7026: An out-of-order terminal is buffered until the gap fills; buffered pre-terminal frames flush ahead of it in seq order, and only then may the flow be cleaned up
    func test7026_reorderFlushesPreTerminalBeforeCleanup() throws {
        let rid = MessageId.newUUID()
        let buffer = ReorderBuffer(maxBufferPerFlow: 8)

        func mk(_ seq: UInt64, _ frameType: FrameType) -> Frame {
            var frame = Frame(frameType: frameType, id: rid)
            frame.seq = seq
            return frame
        }

        // seq 0 delivers immediately.
        var delivered = try buffer.accept(mk(0, .chunk))
        XCTAssertEqual(delivered.count, 1)

        // seq 2 (chunk) and seq 3 (END) arrive out of order — both buffered,
        // nothing delivered, no premature cleanup possible.
        XCTAssertTrue(try buffer.accept(mk(2, .chunk)).isEmpty)
        XCTAssertTrue(try buffer.accept(mk(3, .end)).isEmpty)

        // The gap fills: seq 1 arrives → 1, 2, 3(END) all deliver in order.
        // The terminal is DELIVERED strictly after every pre-terminal frame.
        delivered = try buffer.accept(mk(1, .chunk))
        XCTAssertEqual(delivered.map { $0.seq }, [1, 2, 3])
        XCTAssertEqual(delivered.last?.frameType, .end)

        // Cleanup after delivered terminal (as the relay does, post-drain):
        // the flow state resets and a fresh flow under the same key starts
        // cleanly at seq 0.
        buffer.cleanupFlow(FlowKey.fromFrame(delivered[2]))
        let fresh = try buffer.accept(mk(0, .chunk))
        XCTAssertEqual(fresh.count, 1, "cleaned flow accepts a fresh seq 0")
    }

    // MARK: - CreditGate / CreditRouter (TEST7015-7018)

    // TEST7015: CreditGate acquire succeeds immediately within the initial window and waits when exhausted until a grant arrives.
    func test7015_creditGateAcquireAndGrant() async throws {
        let gate = CreditGate(initialCredit: 2)
        try await gate.acquire(1)
        try await gate.acquire(1)
        XCTAssertEqual(gate.available, 0)

        let finished = TestFlag()
        let waiter = Task {
            try await gate.acquire(1)
            finished.set()
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(finished.isSet, "acquire must wait at zero credit")

        gate.grant(1)
        try await waitUntil { finished.isSet }
        XCTAssertTrue(finished.isSet, "waiter must wake on grant")
        try await waiter.value
    }

    // TEST7016: CreditGate close releases blocked waiters with CreditClosed and fails all future acquires.
    func test7016_creditGateCloseReleasesWaiters() async throws {
        let gate = CreditGate(initialCredit: 0)
        let result = TestBox<Result<Void, Error>>()
        let waiter = Task {
            do {
                try await gate.acquire(1)
                result.set(.success(()))
            } catch {
                result.set(.failure(error))
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        gate.close(reason: "CANCELLED")
        try await waitUntil { result.get() != nil }
        guard case .failure(let error)? = result.get(), let closed = error as? CreditClosed else {
            XCTFail("waiter must wake on close with CreditClosed, got \(String(describing: result.get()))")
            return
        }
        XCTAssertEqual(closed.reason, "CANCELLED")
        await waiter.value

        do {
            try await gate.acquire(1)
            XCTFail("closed gate rejects acquire")
        } catch {}
        gate.grant(5) // no-op after close
        do {
            try await gate.acquire(1)
            XCTFail("closed gate rejects acquire even after a post-close grant")
        } catch {}
    }

    // TEST7017: CreditRouter routes grants by (rid, stream_id), falls back to a request's sole gate for stream-less grants, and reports unmatched grants.
    func test7017_creditRouterRouting() throws {
        let router = CreditRouter()
        let rid = MessageId.newUUID()
        let gate = CreditGate(initialCredit: 0)
        router.register(rid: rid, streamId: "s1", gate: gate)

        // Exact (rid, stream) match
        XCTAssertTrue(router.grant(Frame.credit(targetRid: rid, streamId: "s1", credits: 3, direction: .response)))
        XCTAssertEqual(gate.available, 3)

        // Stream-less grant matches the sole gate
        XCTAssertTrue(router.grant(Frame.credit(targetRid: rid, streamId: nil, credits: 2, direction: .response)))
        XCTAssertEqual(gate.available, 5)

        // Second gate makes a stream-less grant ambiguous → unmatched
        let gate2 = CreditGate(initialCredit: 0)
        router.register(rid: rid, streamId: "s2", gate: gate2)
        XCTAssertFalse(router.grant(Frame.credit(targetRid: rid, streamId: nil, credits: 1, direction: .response)))

        // Unknown request → unmatched no-op
        XCTAssertFalse(router.grant(Frame.credit(targetRid: .newUUID(), streamId: nil, credits: 1, direction: .response)))
    }

    // TEST7018: CreditRouter close_request closes and removes every gate of the request, releasing their waiters.
    func test7018_creditRouterCloseRequest() async throws {
        let router = CreditRouter()
        let rid = MessageId.newUUID()
        let gate1 = CreditGate(initialCredit: 0)
        let gate2 = CreditGate(initialCredit: 0)
        router.register(rid: rid, streamId: "a", gate: gate1)
        router.register(rid: rid, streamId: "b", gate: gate2)

        let result = TestBox<Result<Void, Error>>()
        let waiter = Task {
            do {
                try await gate1.acquire(1)
                result.set(.success(()))
            } catch {
                result.set(.failure(error))
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        router.closeRequest(rid: rid, reason: "END")
        XCTAssertTrue(router.isEmpty)
        XCTAssertTrue(gate2.isClosed)
        try await waitUntil { result.get() != nil }
        guard case .failure(let error)? = result.get(), let closed = error as? CreditClosed else {
            XCTFail("waiter must be released with CreditClosed, got \(String(describing: result.get()))")
            return
        }
        XCTAssertEqual(closed.reason, "END")
        await waiter.value
    }

    // MARK: - Stats (TEST7019, TEST7029)

    // TEST7019: Drop counters record per-reason exactly once per drop, and the snapshot omits zero-count reasons while totalling all of them.
    func test7019_dropCountersRecordAndSnapshot() {
        let counters = DropCounters()
        XCTAssertEqual(counters.total, 0)
        XCTAssertEqual(counters.snapshot(), DropSnapshot())

        XCTAssertEqual(counters.record(.postTerminal), 1)
        XCTAssertEqual(counters.record(.postTerminal), 2)
        XCTAssertEqual(counters.record(.channelClosed), 1)

        XCTAssertEqual(counters.get(.postTerminal), 2)
        XCTAssertEqual(counters.get(.channelClosed), 1)
        XCTAssertEqual(counters.get(.noRoute), 0)
        XCTAssertEqual(counters.total, 3)

        let snap = counters.snapshot()
        XCTAssertEqual(snap.total, 3)
        XCTAssertEqual(snap.byReason["post_terminal"], 2)
        XCTAssertEqual(snap.byReason["channel_closed"], 1)
        XCTAssertNil(snap.byReason["no_route"], "zero-count reasons are omitted from the snapshot")
    }

    // TEST7029: TerminatedFlows membership is exact up to capacity and evicts strictly oldest-first beyond it.
    func test7029_terminatedFlowsCapacityAndEviction() {
        let flows = TerminatedFlows(cap: 2)
        func k(_ n: UInt64) -> FlowKey {
            return FlowKey(rid: .uint(n), xid: nil)
        }

        flows.insert(k(1))
        flows.insert(k(1)) // duplicate insert is a no-op
        flows.insert(k(2))
        XCTAssertEqual(flows.count, 2)
        XCTAssertTrue(flows.contains(k(1)) && flows.contains(k(2)))

        flows.insert(k(3)) // evicts k(1), the oldest
        XCTAssertEqual(flows.count, 2)
        XCTAssertFalse(flows.contains(k(1)))
        XCTAssertTrue(flows.contains(k(2)) && flows.contains(k(3)))

        // XID-bearing key is a distinct flow from the bare-RID key
        let withXid = FlowKey(rid: .uint(2), xid: .uint(9))
        XCTAssertFalse(flows.contains(withXid))
    }
}
