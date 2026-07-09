/// Protocol v3 RUNTIME-layer parity tests — writer terminal gate (L4),
/// counted drops (L8), credit flow control (L9/L10/L12/L14), unbounded
/// streams (L16), unified switch request state (L6/L7), and host stats
/// surfacing. Mirrors the same-numbered tests in
/// capdag/src/bifaci/cartridge_runtime.rs and relay_switch.rs.

import XCTest
import Foundation
@preconcurrency import SwiftCBOR
import CapDAG
@testable import Bifaci

// MARK: - Helpers

/// FrameSender that records every frame it is asked to send.
final class RecordingFrameSender: FrameSender, @unchecked Sendable {
    private var frames: [Frame] = []
    private let lock = NSLock()

    func send(_ frame: Frame) throws {
        lock.lock()
        frames.append(frame)
        lock.unlock()
    }

    func snapshot() -> [Frame] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }
}

/// Thread-safe boolean flag.
final class LockedFlag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()
    func set() { lock.lock(); value = true; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}

@available(macOS 10.15.4, iOS 13.4, *)
final class ProtocolV3RuntimeTests: XCTestCase {

    /// Build a ChannelFrameSender (the runtime's single output serialization
    /// point — the Swift counterpart of the Rust writer thread) writing to a
    /// temp file whose bytes the test decodes back into frames.
    private func makeWireCapture() throws -> (sender: ChannelFrameSender, writer: FrameWriter, drops: DropCounters, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wire-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        let writer = FrameWriter(handle: handle)
        let drops = DropCounters()
        let sender = ChannelFrameSender(
            writer: writer,
            writerLock: NSLock(),
            seqAssigner: SeqAssigner(),
            drops: drops
        )
        return (sender, writer, drops, url)
    }

    /// Decode every length-prefixed frame from a captured wire buffer.
    private func decodeWire(_ url: URL) throws -> [Frame] {
        let buf = try Data(contentsOf: url)
        var frames: [Frame] = []
        var pos = 0
        while pos + 4 <= buf.count {
            let len = Int(UInt32(buf[pos]) << 24 | UInt32(buf[pos + 1]) << 16 | UInt32(buf[pos + 2]) << 8 | UInt32(buf[pos + 3]))
            pos += 4
            frames.append(try decodeFrame(buf.subdata(in: pos..<(pos + len))))
            pos += len
        }
        XCTAssertEqual(pos, buf.count, "trailing bytes on the wire")
        return frames
    }

    private func makeChunk(rid: MessageId, streamId: String, index: UInt64, byte: UInt8) -> Frame {
        let payload = Data(CBOR.byteString([byte]).encode())
        let checksum = Frame.computeChecksum(payload)
        return Frame.chunk(reqId: rid, streamId: streamId, seq: index, payload: payload, chunkIndex: index, checksum: checksum)
    }

    // MARK: - Writer terminal gate (L4)

    // TEST7020: A flow frame reaching the writer after the flow's END has been written is dropped with a counted post_terminal drop — END is the last flow frame on the wire.
    func test7020_writerGateDropsPostTerminalFlowFrames() throws {
        let rid = MessageId.newUUID()
        let (sender, _, drops, url) = try makeWireCapture()

        // In-order: chunk, END — both written.
        let payload = Data([1, 2, 3])
        let checksum = Frame.computeChecksum(payload)
        let chunk = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: payload, chunkIndex: 0, checksum: checksum)
        try sender.send(chunk)
        let end = Frame.endOkWith(id: rid, finalPayload: nil, progress: 1.0, message: nil)
        try sender.send(end)

        // The detached-sender race: a straggler progress LOG enqueued after
        // the handler returned reaches the writer after END. Dropped+counted.
        let straggler = Frame.progress(id: rid, progress: 1.0, message: "late keepalive")
        try sender.send(straggler) // gated drop — not an error
        XCTAssertEqual(drops.get(.postTerminal), 1)

        let frames = try decodeWire(url)
        XCTAssertEqual(frames.count, 2, "straggler must not reach the wire")
        XCTAssertEqual(frames[0].frameType, .chunk)
        XCTAssertEqual(frames[1].frameType, .end)
        XCTAssertEqual(frames.last?.frameType, .end, "END is the last flow frame on the wire (L4)")
        // Seq is contiguous and terminal-final
        XCTAssertEqual(frames[0].seq, 0)
        XCTAssertEqual(frames[1].seq, 1)
    }

    // TEST7021: The writer gate is precise — flow frames before END are written, non-flow frames (heartbeat, credit) still pass after a flow's terminal, and only that flow is gated.
    func test7021_writerGatePrecision() throws {
        let ridA = MessageId.uint(1)
        let ridB = MessageId.uint(2)
        let (sender, _, drops, url) = try makeWireCapture()

        // Progress before END is written (the gate never over-drops).
        try sender.send(Frame.progress(id: ridA, progress: 0.5, message: "halfway"))
        try sender.send(Frame.endOk(id: ridA, finalPayload: nil))

        // Non-flow frames for the terminated flow still pass (heartbeats and
        // credit must never be blocked by data-flow termination).
        try sender.send(Frame.heartbeat(id: ridA))
        try sender.send(Frame.credit(targetRid: ridA, streamId: nil, credits: 4, direction: .response))

        // A different flow is untouched by A's terminal.
        try sender.send(Frame.progress(id: ridB, progress: 0.1, message: "other request"))

        // But a flow frame for A is gated.
        try sender.send(Frame.log(id: ridA, level: "info", message: "late"))

        let frames = try decodeWire(url)
        XCTAssertEqual(
            frames.map { $0.frameType },
            [.log, .end, .heartbeat, .credit, .log]
        )
        XCTAssertEqual(drops.get(.postTerminal), 1)
    }

    // TEST7027: A frame sent through a ChannelFrameSender whose receiver is gone is a counted channel_closed drop, never a silent loss.
    func test7027_channelClosedSendsAreCounted() throws {
        let (sender, writer, drops, _) = try makeWireCapture()

        // Receiver alive: send succeeds, nothing counted.
        let frame = Frame.progress(id: .newUUID(), progress: 0.4, message: "working")
        try sender.send(frame)
        XCTAssertEqual(drops.get(.channelClosed), 0)

        // Receiver gone (writer closed): send fails AND the drop is counted.
        writer.close()
        XCTAssertThrowsError(try sender.send(frame)) { error in
            XCTAssertTrue("\(error)".contains("Output channel closed"), "\(error)")
        }
        XCTAssertEqual(drops.get(.channelClosed), 1)
        _ = try? sender.send(frame)
        XCTAssertEqual(drops.get(.channelClosed), 2, "every dropped frame increments exactly once (L8)")
    }

    // TEST7086: One runtime's drop counters aggregate every drop source — post-terminal writer drops and closed-channel sends — each counted exactly once, and the snapshot totals match the induced drops.
    func test7086_dropSnapshotMatchesInducedDrops() throws {
        let rid = MessageId.newUUID()
        let (sender, writer, drops, _) = try makeWireCapture()

        // Source 1: post-terminal drops at the writer gate (two stragglers).
        try sender.send(Frame.endOk(id: rid, finalPayload: nil))
        for _ in 0..<2 {
            try sender.send(Frame.progress(id: rid, progress: 1.0, message: "straggler"))
        }

        // Source 2: closed-channel send (one drop). Must use a FRESH rid:
        // `rid`'s END is already on the wire, so a frame for it would be
        // claimed by the terminal gate (post_terminal) before ever reaching
        // the closed writer — the Rust reference induces this drop through a
        // gate-free sender for the same reason.
        writer.close()
        _ = try? sender.send(Frame.log(id: MessageId.newUUID(), level: "info", message: "dead channel"))

        let snap = drops.snapshot()
        XCTAssertEqual(snap.total, 3, "each induced drop counted exactly once (L8)")
        XCTAssertEqual(snap.byReason["post_terminal"], 2)
        XCTAssertEqual(snap.byReason["channel_closed"], 1)
    }

    // MARK: - Sequence item reassembly (RFC 8742 fragments)

    private func makeFragmentChunk(rid: MessageId, streamId: String, index: UInt64, payload: Data, meta: StreamMeta? = nil) -> Frame {
        let checksum = Frame.computeChecksum(payload)
        var frame = Frame.chunk(reqId: rid, streamId: streamId, seq: index, payload: payload, chunkIndex: index, checksum: checksum)
        frame.meta = meta
        return frame
    }

    // TEST1300: A sequence item CBOR-encoded once and split across multiple CHUNK frames (the emitListItem framing) reassembles into exactly one delivered item.
    func test1300_sequenceItemFragmentsReassembleIntoOneItem() throws {
        let rid = MessageId.newUUID()
        let frames = BlockingQueue<Frame>()

        // One large item, encoded once, then fragmented — exactly what
        // emitListItem does for an item bigger than maxChunk. Per-frame
        // decoding of any fragment fails, which is how cap→cap forwarding
        // of rendered page images broke in the reference.
        let itemBytes = (0..<60_000).map { UInt8($0 % 251) }
        let encoded = Data(CBOR.byteString(itemBytes).encode())
        let fragmentSize = 16 * 1024
        XCTAssertGreaterThan(encoded.count, fragmentSize, "item must span multiple fragments")

        // Per-item metadata rides the item's FIRST fragment only (the
        // emitListItem contract) and must survive reassembly.
        let itemMeta: StreamMeta = ["title": .utf8String("page 1")]

        frames.push(Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:ext=png;image", isSequence: true))
        var index: UInt64 = 0
        var offset = 0
        while offset < encoded.count {
            let end = min(offset + fragmentSize, encoded.count)
            frames.push(makeFragmentChunk(
                rid: rid,
                streamId: "s1",
                index: index,
                payload: encoded.subdata(in: offset..<end),
                meta: index == 0 ? itemMeta : nil
            ))
            index += 1
            offset = end
        }
        // A second, single-fragment item follows — reassembly must realign
        // on the item boundary, not swallow it into the first.
        let second = Data(CBOR.byteString([7, 7, 7]).encode())
        frames.push(makeFragmentChunk(rid: rid, streamId: "s1", index: index, payload: second))
        frames.push(Frame.streamEnd(reqId: rid, streamId: "s1", chunkCount: index + 1))
        frames.push(Frame.end(id: rid))
        frames.finish()

        let package = demuxMultiStream(frameIterator: AnyIterator { frames.dequeue() })
        let inputStream = try XCTUnwrap(package.nextStream()).get()
        var items: [(CBOR, StreamMeta?)] = []
        var iterator = inputStream.makeIterator()
        while let item = iterator.next() {
            items.append(try item.get())
        }
        XCTAssertEqual(items.count, 2, "exactly two items")
        XCTAssertEqual(items[0].0, CBOR.byteString(itemBytes), "fragments must reassemble into the original item")
        XCTAssertEqual(items[0].1, itemMeta, "first fragment's meta rides the reassembled item")
        XCTAssertEqual(items[1].0, CBOR.byteString([7, 7, 7]))
        XCTAssertNil(items[1].1)
    }

    // TEST1301: A sequence stream that ENDs mid-item (trailing fragment bytes that never complete a CBOR item) surfaces a hard decode error instead of silently dropping the partial item.
    func test1301_sequenceStreamTruncatedMidItemFailsHard() throws {
        let rid = MessageId.newUUID()
        let frames = BlockingQueue<Frame>()

        let encoded = Data(CBOR.byteString([UInt8](repeating: 42, count: 4096)).encode())
        // Send only a strict prefix of the item, then STREAM_END.
        let prefix = encoded.subdata(in: 0..<(encoded.count / 2))

        frames.push(Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:ext=png;image", isSequence: true))
        frames.push(makeFragmentChunk(rid: rid, streamId: "s1", index: 0, payload: prefix))
        frames.push(Frame.streamEnd(reqId: rid, streamId: "s1", chunkCount: 1))
        frames.push(Frame.end(id: rid))
        frames.finish()

        let package = demuxMultiStream(frameIterator: AnyIterator { frames.dequeue() })
        let inputStream = try XCTUnwrap(package.nextStream()).get()
        var iterator = inputStream.makeIterator()
        let item = try XCTUnwrap(iterator.next(), "truncation must surface, not close silently")
        XCTAssertThrowsError(try item.get()) { error in
            XCTAssertTrue("\(error)".contains("mid-item"), "\(error)")
        }
    }

    // TEST1302: Continuation fragments of a multi-frame sequence item are credited back by the demux on arrival — the handler grants one frame per consumed item, so without fragment grants an item spanning more frames than the credit window could never finish arriving.
    func test1302_sequenceFragmentFramesAreCreditedOnArrival() throws {
        let grantSink = RecordingFrameSender()
        let rid = MessageId.newUUID()
        let frames = BlockingQueue<Frame>()

        // One item spanning 4 fragments against a credit window of 2: only
        // demux-side fragment grants keep the producer's window open.
        let itemBytes = [UInt8](repeating: 9, count: 4096)
        let encoded = Data(CBOR.byteString(itemBytes).encode())
        let fragmentSize = (encoded.count + 3) / 4

        frames.push(Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:ext=png;image", isSequence: true))
        var index: UInt64 = 0
        var offset = 0
        while offset < encoded.count {
            let end = min(offset + fragmentSize, encoded.count)
            frames.push(makeFragmentChunk(rid: rid, streamId: "s1", index: index, payload: encoded.subdata(in: offset..<end)))
            index += 1
            offset = end
        }
        XCTAssertEqual(index, 4)
        frames.push(Frame.streamEnd(reqId: rid, streamId: "s1", chunkCount: index))
        frames.push(Frame.end(id: rid))
        frames.finish()

        let package = demuxMultiStream(
            frameIterator: AnyIterator { frames.dequeue() },
            credit: InputCreditContext(sender: grantSink, rid: rid, xid: nil, initialCredit: 2)
        )
        let inputStream = try XCTUnwrap(package.nextStream()).get()
        var iterator = inputStream.makeIterator()
        let first = try XCTUnwrap(iterator.next())
        XCTAssertEqual(try first.get().0, CBOR.byteString(itemBytes))
        XCTAssertNil(iterator.next())

        // Continuation fragments (all but the item's first frame) must have
        // been credited by the demux as they arrived: 3 immediate one-frame
        // grants. The item's own frame is granted by handler consumption.
        var demuxGranted: UInt64 = 0
        for frame in grantSink.snapshot() where frame.frameType == .credit {
            demuxGranted += frame.creditCount ?? 0
        }
        XCTAssertGreaterThanOrEqual(demuxGranted, index - 1, "expected at least \(index - 1) fragment credits, saw \(demuxGranted)")
    }

    // MARK: - Credit flow control (L9/L10/L12/L14)

    // TEST7050: A credited sender emits exactly its window of chunks then stalls until a CREDIT grant arrives — observed on the frame channel.
    func test7050_senderStallsAtWindowAndResumesOnGrant() async throws {
        let sender = RecordingFrameSender()
        let router = CreditRouter()
        let rid = MessageId.newUUID()
        // Window of 4 chunks; payload needs 6 chunks at maxChunk=4 bytes.
        let output = Bifaci.OutputStream(
            sender: sender,
            streamId: "s1",
            mediaUrn: "media:enc=utf-8",
            requestId: rid,
            routingId: nil,
            maxChunk: 4,
            initialCredit: 4,
            creditRouter: router
        )
        try output.start(isSequence: false)

        let data = Data((0..<24).map { UInt8($0) }) // 6 chunks of 4 bytes
        let finished = LockedFlag()
        let writerTask = Task {
            try await output.write(data)
            try output.close()
            finished.set()
        }

        // Exactly STREAM_START + 4 chunks appear, then the sender stalls.
        try await Task.sleep(nanoseconds: 100_000_000)
        let before = sender.snapshot()
        XCTAssertEqual(before.first?.frameType, .streamStart)
        let chunksBefore = before.filter { $0.frameType == .chunk }.count
        XCTAssertEqual(chunksBefore, 4, "sender must stall at exactly the window")
        XCTAssertFalse(finished.get(), "writer must be blocked on credit")

        // Grant 2 → the remaining 2 chunks + STREAM_END flow; data is intact
        // and chunk indexes are contiguous (nothing lost or reordered).
        router.grant(Frame.credit(targetRid: rid, streamId: "s1", credits: 2, direction: .response))
        try await writerTask.value

        let all = sender.snapshot()
        let chunksAfter = all.filter { $0.frameType == .chunk }.count - chunksBefore
        XCTAssertEqual(chunksAfter, 2, "grant releases exactly the granted chunks")
        XCTAssertEqual(all.last?.frameType, .streamEnd)
        let indexes = all.filter { $0.frameType == .chunk }.compactMap { $0.chunkIndex }
        XCTAssertEqual(indexes, [0, 1, 2, 3, 4, 5], "in order, none lost")
    }

    // TEST7062: LOG/progress frames flow while the data window is exhausted — control frames are never credited.
    func test7062_logFlowsWhileWindowExhausted() async throws {
        let sender = RecordingFrameSender()
        let router = CreditRouter()
        let rid = MessageId.newUUID()
        let output = Bifaci.OutputStream(
            sender: sender,
            streamId: "s1",
            mediaUrn: "media:enc=utf-8",
            requestId: rid,
            routingId: nil,
            maxChunk: 4,
            initialCredit: 1,
            creditRouter: router
        )
        try output.start(isSequence: false)

        // Exhaust the window (1 chunk), then block trying to send another.
        let finished = LockedFlag()
        let writerTask = Task {
            _ = try? await output.write(Data(repeating: 0, count: 8)) // 2 chunks; blocks after 1
            finished.set()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(finished.get(), "data sender must be stalled")

        // Progress still flows — uncredited (L14).
        output.progress(0.5, message: "still alive")
        let sawProgress = sender.snapshot().contains {
            $0.frameType == .log && $0.logProgress == 0.5
        }
        XCTAssertTrue(sawProgress, "progress must bypass the exhausted data window")

        // Release the blocked writer (L13) so the task exits cleanly.
        router.closeRequest(rid: rid, reason: "END")
        _ = await writerTask.value
    }

    // TEST7052: Input consumption emits batched CREDIT grants — roughly one grant per half-window consumed, not one per chunk.
    func test7052_inputGrantsAreBatched() throws {
        let grantSink = RecordingFrameSender()
        let rid = MessageId.newUUID()
        let frames = BlockingQueue<Frame>()

        // Stream 16 chunks through a credited demux with window 8.
        frames.push(Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:enc=utf-8", isSequence: false))
        // A CONFORMING producer: first burst = the initial window (8)...
        for i in 0..<8 {
            frames.push(makeChunk(rid: rid, streamId: "s1", index: UInt64(i), byte: UInt8(i)))
        }

        let package = demuxMultiStream(
            frameIterator: AnyIterator { frames.dequeue() },
            credit: InputCreditContext(sender: grantSink, rid: rid, xid: nil, initialCredit: 8)
        )
        let stream = try XCTUnwrap(package.nextStream()).get
        let inputStream = try stream()
        // Let the demux forward all 8 pre-queued chunks before consuming so
        // phase-1 consumption never hits an empty channel (no flushes fire
        // and batching is deterministic).
        Thread.sleep(forTimeInterval: 0.1)
        var iterator = inputStream.makeIterator()
        var consumed = 0
        for _ in 0..<8 {
            let item = try XCTUnwrap(iterator.next())
            _ = try item.get()
            consumed += 1
        }
        // ...then the rest only after consumption granted more window.
        for i in 8..<16 {
            frames.push(makeChunk(rid: rid, streamId: "s1", index: UInt64(i), byte: UInt8(i)))
        }
        frames.push(Frame.streamEnd(reqId: rid, streamId: "s1", chunkCount: 16))
        frames.push(Frame.end(id: rid))
        frames.finish()
        while let item = iterator.next() {
            _ = try item.get()
            consumed += 1
        }
        XCTAssertEqual(consumed, 16)

        var grants: [UInt64] = []
        for frame in grantSink.snapshot() {
            XCTAssertEqual(frame.frameType, .credit)
            grants.append(try XCTUnwrap(frame.creditCount))
        }
        // The first 8 items were pre-queued, so their consumption never hits
        // an empty channel: no flushes fire and batching is deterministic —
        // exactly two grants of batch size 4.
        XCTAssertTrue(
            grants.count >= 2 && grants[0] == 4 && grants[1] == 4,
            "pre-queued consumption must batch deterministically at window/2: \(grants)"
        )
        // The second phase races the demux forwarding, so flush-before-block
        // (L10 corollary) may legally split grants below the batch size. The
        // invariants that hold under any scheduling: strictly fewer grant
        // frames than chunks (batching is real), and everything consumed
        // before the final block is granted (allowing at most batch-1 pending
        // at stream close, when granting is moot — the sender is done).
        let total = grants.reduce(0, +)
        XCTAssertLessThan(
            grants.count, 16,
            "fewer grant frames than chunks — batching must be real: \(grants)"
        )
        XCTAssertTrue(
            (13...16).contains(total),
            "all consumption granted (≤ batch-1 pending at close): total=\(total) \(grants)"
        )
        // Note: 16 chunks arrive against an 8-window with grants extending it
        // as the handler consumes — the shared window accounting is what lets
        // the producer legally exceed the initial window (L10).
    }

    // TEST7063: A receiver flushes pending sub-batch grants before blocking on an empty input — progress is guaranteed even when the sender's window is smaller than the receiver's grant batch threshold.
    func test7063_pendingGrantsFlushBeforeBlocking() throws {
        let grantSink = RecordingFrameSender()
        let rid = MessageId.newUUID()
        let frames = BlockingQueue<Frame>()

        // Receiver negotiated a 32 window → batch threshold 16. The sender
        // (a different link) has a window of only 8: it emits 8 chunks and
        // stalls, BELOW the receiver's batch threshold.
        frames.push(Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:enc=utf-8", isSequence: false))
        for i in 0..<8 {
            frames.push(makeChunk(rid: rid, streamId: "s1", index: UInt64(i), byte: UInt8(i)))
        }
        // Channel stays open — the sender is stalled, not finished.

        let package = demuxMultiStream(
            frameIterator: AnyIterator { frames.dequeue() },
            credit: InputCreditContext(sender: grantSink, rid: rid, xid: nil, initialCredit: 32)
        )
        let inputStream = try XCTUnwrap(package.nextStream()).get()
        // Let the demux forward all 8 pre-queued chunks before consuming so
        // the consumer never hits an empty channel mid-batch (a partial
        // flush would split the single deterministic 8-chunk grant).
        Thread.sleep(forTimeInterval: 0.1)

        // Consume all 8 available items, then attempt the 9th — which blocks
        // on the empty channel and MUST flush the pending 8-chunk grant first.
        let consumerReleased = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var iterator = inputStream.makeIterator()
            for _ in 0..<8 {
                _ = try? iterator.next()?.get()
            }
            // Blocks (sender stalled) — but only AFTER flushing grants.
            _ = iterator.next()
            consumerReleased.signal()
        }

        // The flushed grant must arrive even though 8 < batch(16).
        let deadline = Date().addingTimeInterval(2)
        var grantFrames: [Frame] = []
        while Date() < deadline {
            grantFrames = grantSink.snapshot()
            if !grantFrames.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let grant = try XCTUnwrap(
            grantFrames.first,
            "pending grants must flush before blocking (L10 corollary)"
        )
        XCTAssertEqual(grant.frameType, .credit)
        XCTAssertEqual(
            grant.creditCount, 8,
            "the full pending consumption is granted on flush"
        )

        // Release the parked consumer so the thread exits cleanly.
        frames.finish()
        XCTAssertEqual(consumerReleased.wait(timeout: .now() + 2), .success)
    }

    // TEST7053: A chunk received beyond the granted window is a fatal CREDIT_VIOLATION surfaced to the consumer (L12).
    func test7053_overWindowChunkIsCreditViolation() throws {
        let grantSink = RecordingFrameSender()
        let rid = MessageId.newUUID()
        let frames = BlockingQueue<Frame>()

        frames.push(Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:enc=utf-8", isSequence: false))
        // Window is 2; a misbehaving sender pushes 3 chunks with no grants
        // possible (nothing consumed yet).
        for i in 0..<3 {
            frames.push(makeChunk(rid: rid, streamId: "s1", index: UInt64(i), byte: UInt8(i)))
        }
        frames.push(Frame.end(id: rid))
        frames.finish()

        let package = demuxMultiStream(
            frameIterator: AnyIterator { frames.dequeue() },
            credit: InputCreditContext(sender: grantSink, rid: rid, xid: nil, initialCredit: 2)
        )
        let inputStream = try XCTUnwrap(package.nextStream()).get()
        // Let the demux drain all three pre-queued chunks before anything is
        // consumed — no grant can extend the window, so the third chunk is
        // deterministically a violation.
        Thread.sleep(forTimeInterval: 0.1)
        var iterator = inputStream.makeIterator()
        // First two chunks are within the window.
        XCTAssertNoThrow(try XCTUnwrap(iterator.next()).get())
        XCTAssertNoThrow(try XCTUnwrap(iterator.next()).get())
        // The third is the violation.
        let third = try XCTUnwrap(iterator.next(), "violation must be surfaced, not silently dropped")
        XCTAssertThrowsError(try third.get()) { error in
            XCTAssertTrue(
                "\(error)".contains("CREDIT_VIOLATION"),
                "error must carry the CREDIT_VIOLATION code: \(error)"
            )
        }
    }

    // MARK: - Unbounded streams (L16)

    // TEST7070: An unbounded input stream is consumed live — the handler observes early items while the producer is still emitting, and the stream reports itself unbounded.
    func test7070_unboundedInputConsumedLive() throws {
        let rid = MessageId.newUUID()
        let frames = BlockingQueue<Frame>()

        // Announce an UNBOUNDED stream and send only the first item.
        frames.push(Frame.streamStartUnbounded(reqId: rid, streamId: "live", mediaUrn: "media:enc=utf-8", isSequence: true))
        frames.push(makeChunk(rid: rid, streamId: "live", index: 0, byte: 0))

        let package = demuxMultiStream(frameIterator: AnyIterator { frames.dequeue() })
        let stream = try XCTUnwrap(package.nextStream()).get()
        XCTAssertTrue(stream.isUnbounded, "STREAM_START flag must surface")

        // The handler receives item 0 while the producer has not produced
        // item 1 — no buffering-to-completion (L16).
        var iterator = stream.makeIterator()
        let (v0, _) = try XCTUnwrap(iterator.next()).get()
        XCTAssertEqual(v0, CBOR.byteString([0]))

        // Producer continues; consumer keeps up item by item.
        frames.push(makeChunk(rid: rid, streamId: "live", index: 1, byte: 1))
        let (v1, _) = try XCTUnwrap(iterator.next()).get()
        XCTAssertEqual(v1, CBOR.byteString([1]))

        // The unbounded stream still ENDS cleanly — no chunk_count promise.
        frames.push(Frame.streamEndUnbounded(reqId: rid, streamId: "live"))
        frames.push(Frame.end(id: rid))
        frames.finish()
        XCTAssertNil(iterator.next(), "stream closes after STREAM_END")
    }

    // TEST7073: Buffering collectors refuse unbounded streams with a hard error instead of buffering without bound.
    func test7073_collectRefusesUnboundedStreams() throws {
        func makeUnbounded() -> Bifaci.InputStream {
            let queue = BlockingQueue<Result<(CBOR, StreamMeta?), StreamError>>()
            queue.push(.success((.byteString([1]), nil)))
            // Producer stays open — an unbounded collect would hang forever;
            // the guard must reject BEFORE consuming.
            return Bifaci.InputStream(
                mediaUrn: "media:enc=utf-8",
                rx: AnyIterator { queue.dequeue() },
                unbounded: true
            )
        }

        func assertRefused(_ body: @autoclosure () throws -> Any) {
            XCTAssertThrowsError(try body()) { error in
                XCTAssertTrue("\(error)".contains("unbounded"), "\(error)")
            }
        }

        assertRefused(try makeUnbounded().collectBytes())
        assertRefused(try makeUnbounded().collectItems())
        assertRefused(try makeUnbounded().collectValue())
        assertRefused(try makeUnbounded().collectCborSequence())
    }
}

// MARK: - Switch-layer unified request state (L6/L7) + stats surfacing

@available(macOS 10.15.4, iOS 13.4, *)
final class ProtocolV3SwitchTests: XCTestCase {

    // Helper: RelayNotify payload with capability URNs wrapped in a synthetic
    // installed cartridge (the wire schema embeds caps in cap_groups).
    private func sendNotify(writer: FrameWriter, capabilities: [String], limits: Limits) throws {
        let groupCaps: [[String: Any]] = capabilities.map { urn in
            return ["urn": urn, "title": "test", "command": "test", "args": [] as [Any]]
        }
        let manifestBytes = try JSONSerialization.data(withJSONObject: [
            "installed_cartridges": [[
                "registry_url": NSNull(),
                "channel": "release",
                "id": "test-cartridge",
                "version": "0.0.0",
                "sha256": String(repeating: "0", count: 64),
                "cap_groups": [[
                    "name": "test",
                    "caps": groupCaps,
                    "adapter_urns": [] as [String],
                ]],
            ]]
        ])
        try writer.write(Frame.relayNotify(manifest: manifestBytes, limits: limits))
    }

    // Helper: answer the identity verification RelaySwitch init performs
    // (the Swift analogue of Rust's slave_notify_with_identity).
    private func handleIdentityVerification(reader: FrameReader, writer: FrameWriter) throws {
        var nonce = Data()
        var reqId: MessageId? = nil
        let streamId = "identity-verify"
        while true {
            guard let frame = try reader.read() else { return }
            switch frame.frameType {
            case .req:
                reqId = frame.id
            case .streamStart, .streamEnd:
                break
            case .chunk:
                if let p = frame.payload { nonce.append(p) }
            case .end:
                guard let id = reqId else { return }
                try writer.write(Frame.streamStart(reqId: id, streamId: streamId, mediaUrn: "media:"))
                let checksum = Frame.computeChecksum(nonce)
                try writer.write(Frame.chunk(reqId: id, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum))
                try writer.write(Frame.streamEnd(reqId: id, streamId: streamId, chunkCount: 1))
                try writer.write(Frame.end(id: id))
                return
            default:
                return
            }
        }
    }

    /// Register an externally-waiting request directly in the switch's
    /// unified table (the Swift analogue of the Rust tests' direct
    /// `switch.requests.write().await.register(...)`).
    private func registerExternal(
        _ switch_: RelaySwitch,
        key: RequestKey,
        destination: Int,
        channel: BlockingQueue<Frame>?
    ) throws {
        try switch_.requests.register(key, RequestState(
            routing: RoutingEntry(sourceMasterIdx: nil, destinationMasterIdx: destination),
            origin: nil,
            externalChannel: channel.map { q in { frame in q.push(frame); return true } },
            isPeer: false
        ))
    }

    // TEST7059: Terminal frames release ALL request state and every
    // registration is accounted exactly once (L7/L13) — across a mixed
    // workload of END-, ERR-, and cancel-terminated requests the active
    // table drains to empty and the terminated-by-kind counts sum to the
    // total registrations. A leaked entry keeps `active` non-empty; a
    // double- or un-counted termination breaks the conservation equation.
    // (The reference runs this over a real cartridge execution; the law
    // under test lives in the switch's request table, which is the layer
    // this mirror implements.)
    func test7059_terminalEndReleasesCreditAndLeaksNoState() throws {
        let switch_ = try RelaySwitch(sockets: [])

        // Three requests, three terminal paths.
        let endKey = RequestKey(xid: .uint(1), rid: .newUUID())
        let errKey = RequestKey(xid: .uint(2), rid: .newUUID())
        let cancelKey = RequestKey(xid: .uint(3), rid: .newUUID())
        let endChannel = BlockingQueue<Frame>()
        let errChannel = BlockingQueue<Frame>()
        let cancelChannel = BlockingQueue<Frame>()
        try registerExternal(switch_, key: endKey, destination: 0, channel: endChannel)
        try registerExternal(switch_, key: errKey, destination: 0, channel: errChannel)
        try registerExternal(switch_, key: cancelKey, destination: 0, channel: cancelChannel)
        XCTAssertEqual(switch_.protocolStats().requests.active.count, 3)

        var end = Frame.endOkWith(id: endKey.rid, finalPayload: nil, progress: 1.0, message: nil)
        end.routingId = endKey.xid
        _ = try switch_.handleMasterFrame(sourceIdx: 0, frame: end)

        var err = Frame.err(id: errKey.rid, code: "HANDLER_ERROR", message: "boom")
        err.routingId = errKey.xid
        _ = try switch_.handleMasterFrame(sourceIdx: 0, frame: err)

        switch_.cancelRequest(rid: cancelKey.rid, forceKill: false)

        // Terminals must have been DELIVERED before release (L6) — a leak
        // test over a broken run proves nothing.
        XCTAssertEqual(try XCTUnwrap(endChannel.tryPop(timeout: 2)).frameType, .end)
        XCTAssertEqual(try XCTUnwrap(errChannel.tryPop(timeout: 2)).frameType, .err)

        let stats = switch_.protocolStats()
        XCTAssertTrue(
            stats.requests.active.isEmpty,
            "terminal frames must release ALL state for every (xid,rid) (L7); still active: \(stats.requests.active.map { $0.rid })"
        )
        XCTAssertEqual(stats.requests.totalRegistered, 3)
        let endCount = stats.requests.terminatedByKind["end"] ?? 0
        XCTAssertGreaterThanOrEqual(endCount, 1, "the END-terminated request must be counted; got \(stats.requests.terminatedByKind)")
        let terminatedTotal = stats.requests.terminatedByKind.values.reduce(0, +)
        XCTAssertEqual(
            terminatedTotal, stats.requests.totalRegistered,
            "every registered request must be terminated exactly once (L7): \(stats.requests.terminatedByKind) vs total \(stats.requests.totalRegistered)"
        )
        switch_.shutdown()
    }

    // TEST7061: The negotiated initial_credit is the element-wise min of all
    // masters' proposals, wire-visible at the switch. A master's RelayNotify
    // carries its limits; renegotiation must include initialCredit — the
    // regression this pins is `rebuildLimits()` dropping the credit field and
    // silently resetting it to the default (which would let switch-side
    // senders overrun a smaller window with CREDIT_VIOLATIONs at the master).
    func test7061_negotiatedInitialCreditIsMinOfProposals() throws {
        let pairA1 = FileHandle.socketPair() // switch reads A, A writes
        let pairA2 = FileHandle.socketPair() // A reads, switch writes
        let pairB1 = FileHandle.socketPair()
        let pairB2 = FileHandle.socketPair()

        let aNotified = DispatchSemaphore(value: 0)
        let bMayNotify = DispatchSemaphore(value: 0)

        // Master A proposes the DEFAULT limits. Empty caps → no identity
        // probe → the master stays healthy and its limits count.
        DispatchQueue.global().async {
            let writer = FrameWriter(handle: pairA1.write, limits: Limits())
            try! self.sendNotify(writer: writer, capabilities: [], limits: Limits())
            aNotified.signal()
        }
        // Master B proposes initialCredit=8 — everything else default.
        DispatchQueue.global().async {
            let writer = FrameWriter(handle: pairB1.write, limits: Limits())
            bMayNotify.wait()
            var low = Limits()
            low.initialCredit = 8
            try! self.sendNotify(writer: writer, capabilities: [], limits: low)
        }

        let switch_ = try RelaySwitch(sockets: [
            SocketPair(id: "mA", read: pairA1.read, write: pairA2.write),
            SocketPair(id: "mB", read: pairB1.read, write: pairB2.write),
        ])

        // Part 1: default-vs-default converges on the default first burst.
        XCTAssertEqual(aNotified.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(
            switch_.limits().initialCredit, DEFAULT_INITIAL_CREDIT,
            "with every master proposing the default, the negotiated min must be exactly the default"
        )

        // Part 2: B's low proposal drops the negotiated value to min(32, 8) = 8.
        bMayNotify.signal()
        let deadline = Date().addingTimeInterval(5)
        while switch_.limits().initialCredit != 8 {
            if Date() > deadline {
                XCTFail(
                    "negotiated initial_credit must drop to the element-wise min of all masters' proposals (min(\(DEFAULT_INITIAL_CREDIT), 8) = 8); still \(switch_.limits().initialCredit) after 5s"
                )
                switch_.shutdown()
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // The OTHER fields stay at their (default) minima — renegotiation is
        // element-wise, not a wholesale swap to the lowest proposer's struct.
        XCTAssertEqual(switch_.limits().maxFrame, DEFAULT_MAX_FRAME)
        XCTAssertEqual(switch_.limits().maxChunk, DEFAULT_MAX_CHUNK)
        switch_.shutdown()
    }

    // TEST7093: A response frame for a LIVE request whose external consumer is
    // gone (dropped/timed-out caller) is a counted channel_closed drop AND
    // cancels the request upstream — the destination master receives Cancel,
    // the entry terminates as cancelled, and zero state remains: the cartridge
    // stops producing for a dead channel instead of running to completion
    // against it.
    func test7093_deadConsumerCancelsUpstream() throws {
        let pair1 = FileHandle.socketPair() // switch reads, slave writes
        let pair2 = FileHandle.socketPair() // slave reads, switch writes

        final class RidBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value: MessageId?
            let seen = DispatchSemaphore(value: 0)
            func set(_ v: MessageId) {
                lock.lock()
                value = v
                lock.unlock()
                seen.signal()
            }
            func get() -> MessageId? {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }
        let cancelled = RidBox()
        let notified = DispatchSemaphore(value: 0)

        // Mock cartridge master: RelayNotify + identity echo, then wait for
        // the Cancel the dead-consumer path must send us.
        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2.read, limits: Limits())
            let writer = FrameWriter(handle: pair1.write, limits: Limits())
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            notified.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
            while true {
                guard let f = try? reader.read() else { return }
                if f.frameType == .cancel {
                    cancelled.set(f.id)
                    return
                }
            }
        }

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "m0", read: pair1.read, write: pair2.write)])
        XCTAssertEqual(notified.wait(timeout: .now() + 2), .success)

        // A LIVE engine-origin request whose consumer is GONE: the external
        // channel refuses delivery.
        let key = RequestKey(xid: .uint(7), rid: .newUUID())
        try switch_.requests.register(key, RequestState(
            routing: RoutingEntry(sourceMasterIdx: nil, destinationMasterIdx: 0),
            origin: nil,
            externalChannel: { _ in false }, // dead consumer
            isPeer: false
        ))

        // The cartridge streams a response frame into the dead channel.
        var log = Frame.log(id: key.rid, level: "info", message: "first result row")
        log.routingId = key.xid
        _ = try switch_.handleMasterFrame(sourceIdx: 0, frame: log)

        // The switch must cancel upstream — the master observes Cancel for
        // exactly the abandoned request.
        XCTAssertEqual(
            cancelled.seen.wait(timeout: .now() + 5), .success,
            "the destination must receive Cancel for the abandoned request"
        )
        XCTAssertEqual(cancelled.get(), key.rid, "cancel targets the abandoned request")

        // The drop is counted, the request terminates as cancelled, and no
        // state remains (L7). The cancel dispatches off-lock, so poll briefly
        // for the terminated accounting before asserting hard.
        let deadline = Date().addingTimeInterval(5)
        while (switch_.protocolStats().requests.terminatedByKind["cancelled"] ?? 0) < 1 {
            if Date() > deadline { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let stats = switch_.protocolStats()
        XCTAssertEqual(
            stats.drops.byReason["channel_closed"], 1,
            "the abandoned frame is a counted channel_closed drop"
        )
        XCTAssertEqual(
            stats.requests.terminatedByKind["cancelled"], 1,
            "the abandoned request terminates as cancelled — it never lingers"
        )
        XCTAssertTrue(
            stats.requests.active.isEmpty,
            "no state remains for the abandoned request (L7)"
        )
        switch_.shutdown()
    }


    // TEST7085: The RelayNotify capabilities payload carries the host's protocol stats snapshot, surviving the wire round-trip.
    func test7085_relayNotifyCarriesHostProtocolStats() throws {
        let counters = DropCounters()
        counters.record(.noRoute)
        counters.record(.noRoute)
        let stats = HostProtocolStats(
            drops: counters.snapshot(),
            outgoingRids: 3,
            incomingRxids: 5,
            incomingToPeerRids: 1,
            outgoingMaxSeq: 4,
            routingGcRunsTotal: 2,
            routingGcEvictedTotal: 7
        )
        let payload = RelayNotifyCapabilitiesPayload(installedCartridges: [])
            .withHostProtocolStats(stats)
        let bytes = try JSONEncoder().encode(payload)

        let parsed = try RelaySwitch.parseRelayNotifyPayload(bytes)
        let got = try XCTUnwrap(parsed.hostProtocolStats, "host stats must survive the round trip")
        XCTAssertEqual(got.drops.total, 2)
        XCTAssertEqual(got.drops.byReason["no_route"], 2)
        XCTAssertEqual(got.incomingRxids, 5)
        XCTAssertEqual(got.routingGcEvictedTotal, 7)

        // A payload WITHOUT stats (initial capability advertisement) still
        // parses — the field is a per-republish refresh, not a requirement.
        let bare = RelayNotifyCapabilitiesPayload(installedCartridges: [])
        let bareBytes = try JSONEncoder().encode(bare)
        let bareParsed = try RelaySwitch.parseRelayNotifyPayload(bareBytes)
        XCTAssertNil(bareParsed.hostProtocolStats)
    }

    // TEST7025: A flow frame for a request with no routing state is a counted no_route drop — not a protocol error and not a silent loss — observable in the protocol stats snapshot.
    func test7025_unroutableFlowFrameIsCountedDrop() throws {
        let switch_ = try RelaySwitch(sockets: [])

        // Response continuation (has XID) for a key that was never registered
        // (or already terminated): must be dropped + counted, never an error.
        var orphan = Frame.progress(id: .newUUID(), progress: 0.5, message: "orphan")
        orphan.routingId = .uint(999)
        let result = try switch_.handleMasterFrame(sourceIdx: 0, frame: orphan)
        XCTAssertNil(result, "nothing to deliver")

        // Request continuation (no XID) for an unknown RID: same law.
        var chunk = Frame(frameType: .chunk, id: .newUUID())
        chunk.streamId = "s"
        chunk.chunkIndex = 0
        chunk.checksum = 0
        let result2 = try switch_.handleMasterFrame(sourceIdx: 0, frame: chunk)
        XCTAssertNil(result2)

        let stats = switch_.protocolStats()
        XCTAssertEqual(
            stats.drops.byReason["no_route"], 2,
            "both drops counted, exactly once each (L8): \(stats.drops)"
        )
        XCTAssertTrue(stats.requests.active.isEmpty)
        switch_.shutdown()
    }

    // TEST7035: After END, the switch holds zero state for the request — entry, rid index, and response channel all released atomically, with the terminal delivered and a terminated summary recorded.
    func test7035_endTerminatesAndReleasesAllState() throws {
        let switch_ = try RelaySwitch(sockets: [])

        let xid = MessageId.uint(11)
        let rid = MessageId.newUUID()
        let key = RequestKey(xid: xid, rid: rid)
        let channel = BlockingQueue<Frame>()
        try registerExternal(switch_, key: key, destination: 0, channel: channel)
        XCTAssertEqual(switch_.protocolStats().requests.active.count, 1)

        // Terminal END arrives from the master side.
        var end = Frame.endOkWith(id: rid, finalPayload: nil, progress: 1.0, message: nil)
        end.routingId = xid
        _ = try switch_.handleMasterFrame(sourceIdx: 0, frame: end)

        // The terminal was DELIVERED to the waiting channel...
        let delivered = try XCTUnwrap(channel.tryPop(timeout: 2), "END must reach the response channel")
        XCTAssertEqual(delivered.frameType, .end)
        XCTAssertEqual(delivered.finalProgress(), 1.0)

        // ...and zero state remains (L7), with the lifecycle recorded.
        let stats = switch_.protocolStats()
        XCTAssertTrue(stats.requests.active.isEmpty, "no live entry after END")
        XCTAssertEqual(stats.requests.terminatedByKind["end"], 1)
        let summary = try XCTUnwrap(stats.requests.recentTerminated.last, "terminated summary must be recorded")
        XCTAssertEqual(summary.rid, rid.description)
        XCTAssertEqual(summary.framesIn, 1, "ingress recording captured the terminal frame")

        // A follow-up frame for the released key is a counted no_route drop.
        var late = Frame.progress(id: rid, progress: 1.0, message: "late")
        late.routingId = xid
        _ = try switch_.handleMasterFrame(sourceIdx: 0, frame: late)
        XCTAssertEqual(switch_.protocolStats().drops.byReason["no_route"], 1)
        switch_.shutdown()
    }

    // TEST7036: After ERR, the same total-cleanup invariant holds as after END, with kind err.
    func test7036_errTerminatesAndReleasesAllState() throws {
        let switch_ = try RelaySwitch(sockets: [])

        let xid = MessageId.uint(21)
        let rid = MessageId.newUUID()
        let channel = BlockingQueue<Frame>()
        try registerExternal(switch_, key: RequestKey(xid: xid, rid: rid), destination: 0, channel: channel)

        var err = Frame.err(id: rid, code: "HANDLER_ERROR", message: "boom")
        err.routingId = xid
        _ = try switch_.handleMasterFrame(sourceIdx: 0, frame: err)

        let delivered = try XCTUnwrap(channel.tryPop(timeout: 2), "ERR must reach the channel")
        XCTAssertEqual(delivered.frameType, .err)
        XCTAssertEqual(delivered.errorCode, "HANDLER_ERROR")

        let stats = switch_.protocolStats()
        XCTAssertTrue(stats.requests.active.isEmpty)
        XCTAssertEqual(stats.requests.terminatedByKind["err"], 1)
        switch_.shutdown()
    }

    // TEST7037: Cancelling a request terminates it AND its recursively-linked peer children — Cancel frames reach the destination, waiting channels get ERR CANCELLED, and zero state remains for parent or child.
    func test7037_cancelCascadesToChildrenAndCleansAllState() throws {
        let pair1 = FileHandle.socketPair() // engine reads, slave writes
        let pair2 = FileHandle.socketPair() // slave reads, engine writes

        let notified = DispatchSemaphore(value: 0)
        final class CancelCollector: @unchecked Sendable {
            private var rids: [MessageId] = []
            private let lock = NSLock()
            let done = DispatchSemaphore(value: 0)
            func add(_ rid: MessageId) {
                lock.lock()
                rids.append(rid)
                let count = rids.count
                lock.unlock()
                if count == 2 { done.signal() }
            }
            func get() -> [MessageId] {
                lock.lock(); defer { lock.unlock() }
                return rids
            }
        }
        let cancels = CancelCollector()

        // Mock slave: RelayNotify + identity echo, then collect the Cancel
        // frames the cascade sends us.
        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2.read, limits: Limits())
            let writer = FrameWriter(handle: pair1.write, limits: Limits())
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            notified.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
            while cancels.get().count < 2 {
                guard let f = try? reader.read() else { return }
                if f.frameType == .cancel {
                    cancels.add(f.id)
                }
            }
        }
        XCTAssertEqual(notified.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "m0", read: pair1.read, write: pair2.write)])

        // Parent (engine-origin, has a waiting channel) + child peer call.
        let parentKey = RequestKey(xid: .uint(1), rid: .newUUID())
        let childKey = RequestKey(xid: .uint(2), rid: .newUUID())
        let parentChannel = BlockingQueue<Frame>()
        try switch_.requests.register(parentKey, RequestState(
            routing: RoutingEntry(sourceMasterIdx: nil, destinationMasterIdx: 0),
            origin: nil,
            externalChannel: { frame in parentChannel.push(frame); return true },
            isPeer: false
        ))
        try switch_.requests.register(childKey, RequestState(
            routing: RoutingEntry(sourceMasterIdx: 0, destinationMasterIdx: 0),
            origin: 0,
            externalChannel: nil,
            isPeer: true
        ))
        switch_.requests.linkChild(parent: parentKey, child: childKey)

        switch_.cancelRequest(rid: parentKey.rid, forceKill: false)

        // Parent's waiter observes ERR CANCELLED.
        let delivered = try XCTUnwrap(parentChannel.tryPop(timeout: 2), "parent channel gets ERR")
        XCTAssertEqual(delivered.errorCode, "CANCELLED")

        // Both parent and child are fully released (L7), recorded cancelled.
        let stats = switch_.protocolStats()
        XCTAssertTrue(
            stats.requests.active.isEmpty,
            "no state for parent or child remains: \(stats.requests.active)"
        )
        XCTAssertEqual(stats.requests.terminatedByKind["cancelled"], 2)

        // The destination master received Cancel for BOTH rids.
        XCTAssertEqual(cancels.done.wait(timeout: .now() + 2), .success, "slave must see both Cancels")
        let got = cancels.get()
        XCTAssertEqual(got.count, 2, "parent + cascaded child Cancel frames")
        XCTAssertTrue(got.contains(parentKey.rid))
        XCTAssertTrue(got.contains(childKey.rid))
        switch_.shutdown()
    }

    // TEST7038: Master death terminates every request routed to it with kind master_died, delivering synthetic MASTER_DIED ERRs to waiting channels and leaving zero state.
    func test7038_masterDeathTerminatesPendingRequests() throws {
        let pair1 = FileHandle.socketPair()
        let pair2 = FileHandle.socketPair()

        let notified = DispatchSemaphore(value: 0)
        // Mock slave: RelayNotify + identity echo, then keep the connection
        // alive until the test finishes.
        DispatchQueue.global().async {
            let reader = FrameReader(handle: pair2.read, limits: Limits())
            let writer = FrameWriter(handle: pair1.write, limits: Limits())
            try! self.sendNotify(writer: writer, capabilities: [CSCapIdentity], limits: Limits())
            notified.signal()
            try! self.handleIdentityVerification(reader: reader, writer: writer)
            _ = try? reader.read() // park until close
        }
        XCTAssertEqual(notified.wait(timeout: .now() + 2), .success)

        let switch_ = try RelaySwitch(sockets: [SocketPair(id: "m0", read: pair1.read, write: pair2.write)])

        let key = RequestKey(xid: .uint(5), rid: .newUUID())
        let channel = BlockingQueue<Frame>()
        try switch_.requests.register(key, RequestState(
            routing: RoutingEntry(sourceMasterIdx: nil, destinationMasterIdx: 0),
            origin: nil,
            externalChannel: { frame in channel.push(frame); return true },
            isPeer: false
        ))

        try switch_.handleMasterDeath(0)

        let delivered = try XCTUnwrap(channel.tryPop(timeout: 2), "synthetic ERR must be delivered")
        XCTAssertEqual(delivered.errorCode, "MASTER_DIED")

        let stats = switch_.protocolStats()
        XCTAssertTrue(stats.requests.active.isEmpty, "zero state remains (L7)")
        XCTAssertEqual(stats.requests.terminatedByKind["master_died"], 1)
        let summary = try XCTUnwrap(stats.requests.recentTerminated.last)
        XCTAssertEqual(summary.rid, key.rid.description)
        switch_.shutdown()
    }
}
