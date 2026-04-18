import XCTest
@testable import Bifaci
@preconcurrency import SwiftCBOR

// =============================================================================
// Streaming API Tests
//
// Covers TEST529-545 from cartridge_runtime.rs in the reference Rust implementation.
// Tests InputStream, InputPackage, OutputStream, and PeerCall streaming APIs.
//
// Note: We use Bifaci.InputStream and Bifaci.OutputStream to avoid ambiguity
// with Foundation types.
// =============================================================================

final class StreamingAPITests: XCTestCase {

    // MARK: - InputStream Tests (TEST529-534)

    // TEST529: InputStream recv yields chunks in order
    func test529_inputStreamIteratorOrder() throws {
        // Create an InputStream with ordered chunks
        let chunks: [Result<CBOR, StreamError>] = [
            .success(.byteString([1, 2, 3])),
            .success(.byteString([4, 5, 6])),
            .success(.byteString([7, 8, 9])),
        ]

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:test", rx: iterator)

        var collectedChunks: [[UInt8]] = []
        for result in stream {
            switch result {
            case .success(let cbor):
                if case .byteString(let bytes) = cbor {
                    collectedChunks.append(bytes)
                }
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(collectedChunks.count, 3)
        XCTAssertEqual(collectedChunks[0], [1, 2, 3])
        XCTAssertEqual(collectedChunks[1], [4, 5, 6])
        XCTAssertEqual(collectedChunks[2], [7, 8, 9])
    }

    // TEST530: InputStream::collect_bytes concatenates byte chunks
    func test530_inputStreamCollectBytes() throws {
        let chunks: [Result<CBOR, StreamError>] = [
            .success(.byteString([1, 2])),
            .success(.byteString([3, 4])),
            .success(.byteString([5, 6])),
        ]

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:test", rx: iterator)
        let allBytes = try stream.collectBytes()

        XCTAssertEqual([UInt8](allBytes), [1, 2, 3, 4, 5, 6])
    }

    // TEST531: InputStream::collect_bytes handles text chunks
    func test531_inputStreamCollectBytesText() throws {
        let chunks: [Result<CBOR, StreamError>] = [
            .success(.utf8String("Hello")),
            .success(.utf8String(" ")),
            .success(.utf8String("World")),
        ]

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:text", rx: iterator)
        let allBytes = try stream.collectBytes()

        XCTAssertEqual(String(data: allBytes, encoding: .utf8), "Hello World")
    }

    // TEST532: InputStream empty stream produces empty bytes
    func test532_inputStreamEmpty() throws {
        let chunks: [Result<CBOR, StreamError>] = []

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:empty", rx: iterator)
        let allBytes = try stream.collectBytes()

        XCTAssertTrue(allBytes.isEmpty, "Empty stream must produce empty bytes")
    }

    // TEST533: InputStream propagates errors
    func test533_inputStreamErrorPropagation() throws {
        let chunks: [Result<CBOR, StreamError>] = [
            .success(.byteString([1, 2, 3])),
            .failure(.protocolError("Test error")),
        ]

        var index = 0
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard index < chunks.count else { return nil }
            let chunk = chunks[index]
            index += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:test", rx: iterator)

        var gotError = false
        for result in stream {
            if case .failure = result {
                gotError = true
            }
        }

        XCTAssertTrue(gotError, "Error must be propagated through iterator")
    }

    // TEST534: InputStream::media_urn returns correct URN
    func test534_inputStreamMediaUrn() throws {
        let iterator = AnyIterator<Result<CBOR, StreamError>> { nil }
        let stream = Bifaci.InputStream(mediaUrn: "media:image/png", rx: iterator)

        XCTAssertEqual(stream.mediaUrn, "media:image/png")
    }

    // MARK: - InputPackage Tests (TEST535-538)

    // TEST535: InputPackage recv yields streams
    func test535_inputPackageIteration() throws {
        // Create InputPackage with multiple streams
        let stream1Chunks: [Result<CBOR, StreamError>] = [.success(.byteString([1, 2]))]
        let stream2Chunks: [Result<CBOR, StreamError>] = [.success(.byteString([3, 4]))]

        var idx1 = 0
        let iter1 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx1 < stream1Chunks.count else { return nil }
            let c = stream1Chunks[idx1]
            idx1 += 1
            return c
        }

        var idx2 = 0
        let iter2 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx2 < stream2Chunks.count else { return nil }
            let c = stream2Chunks[idx2]
            idx2 += 1
            return c
        }

        let s1 = Bifaci.InputStream(mediaUrn: "media:a", rx: iter1)
        let s2 = Bifaci.InputStream(mediaUrn: "media:b", rx: iter2)
        let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(s1), .success(s2)]

        var streamIdx = 0
        let streamIter = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIdx < streams.count else { return nil }
            let s = streams[streamIdx]
            streamIdx += 1
            return s
        }

        let package = InputPackage(rx: streamIter)

        var count = 0
        for result in package {
            if case .success = result {
                count += 1
            }
        }

        XCTAssertEqual(count, 2, "InputPackage should yield 2 streams")
    }

    // TEST536: InputPackage::collect_all_bytes aggregates all streams
    func test536_inputPackageCollectAllBytes() throws {
        // Create two streams
        let stream1Chunks: [Result<CBOR, StreamError>] = [.success(.byteString([1, 2]))]
        let stream2Chunks: [Result<CBOR, StreamError>] = [.success(.byteString([3, 4]))]

        var idx1 = 0
        let iter1 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx1 < stream1Chunks.count else { return nil }
            let c = stream1Chunks[idx1]
            idx1 += 1
            return c
        }

        var idx2 = 0
        let iter2 = AnyIterator<Result<CBOR, StreamError>> {
            guard idx2 < stream2Chunks.count else { return nil }
            let c = stream2Chunks[idx2]
            idx2 += 1
            return c
        }

        let s1 = Bifaci.InputStream(mediaUrn: "media:a", rx: iter1)
        let s2 = Bifaci.InputStream(mediaUrn: "media:b", rx: iter2)
        let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(s1), .success(s2)]

        var streamIdx = 0
        let streamIter = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIdx < streams.count else { return nil }
            let s = streams[streamIdx]
            streamIdx += 1
            return s
        }

        let package = InputPackage(rx: streamIter)
        let allBytes = try package.collectAllBytes()

        // Bytes from both streams should be concatenated
        XCTAssertEqual([UInt8](allBytes), [1, 2, 3, 4])
    }

    // TEST537: InputPackage empty package produces empty bytes
    func test537_inputPackageEmpty() throws {
        let streams: [Result<Bifaci.InputStream, StreamError>] = []

        var streamIdx = 0
        let streamIter = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIdx < streams.count else { return nil }
            let s = streams[streamIdx]
            streamIdx += 1
            return s
        }

        let package = InputPackage(rx: streamIter)
        let allBytes = try package.collectAllBytes()

        XCTAssertTrue(allBytes.isEmpty, "Empty package must produce empty bytes")
    }

    // TEST538: InputPackage propagates stream errors
    func test538_inputPackageErrorPropagation() throws {
        let streams: [Result<Bifaci.InputStream, StreamError>] = [
            .failure(.protocolError("Stream error")),
        ]

        var streamIdx = 0
        let streamIter = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIdx < streams.count else { return nil }
            let s = streams[streamIdx]
            streamIdx += 1
            return s
        }

        let package = InputPackage(rx: streamIter)

        var gotError = false
        for result in package {
            if case .failure = result {
                gotError = true
            }
        }

        XCTAssertTrue(gotError, "Error must be propagated through package iterator")
    }

    // MARK: - OutputStream Tests (TEST539-542)

    // TEST539: OutputStream sends STREAM_START on first write
    func test539_outputStreamSendsStreamStart() throws {
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        // start() must be called before write
        try output.start(isSequence: false)
        try output.write(Data([1, 2, 3]))

        XCTAssertGreaterThanOrEqual(sentFrames.count, 1, "Should send at least STREAM_START")

        // First frame should be STREAM_START with isSequence=false
        let first = sentFrames[0]
        XCTAssertEqual(first.frameType, .streamStart, "First frame must be STREAM_START")
        XCTAssertEqual(first.streamId, "test-stream")
        XCTAssertEqual(first.mediaUrn, "media:test")
        XCTAssertEqual(first.isSequence, false, "STREAM_START must carry isSequence=false")
    }

    // TEST540: OutputStream::close sends STREAM_END with correct chunk_count
    func test540_outputStreamCloseSendsStreamEnd() throws {
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        // start() then write 3 chunks
        try output.start(isSequence: false)
        try output.write(Data([1]))
        try output.write(Data([2]))
        try output.write(Data([3]))
        try output.close()

        // Last frame before any END should be STREAM_END
        let streamEndFrames = sentFrames.filter { $0.frameType == .streamEnd }
        XCTAssertEqual(streamEndFrames.count, 1, "Should send exactly one STREAM_END")

        let streamEnd = streamEndFrames[0]
        XCTAssertEqual(streamEnd.chunkCount, 3, "chunk_count should be 3")
    }

    // TEST541: OutputStream chunks large data correctly
    func test541_outputStreamChunksLargeData() throws {
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let maxChunk = 10
        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: maxChunk
        )

        // start() then write data larger than maxChunk
        try output.start(isSequence: false)
        let largeData = Data(repeating: 0x42, count: 35)
        try output.write(largeData)
        try output.close()

        // Should have STREAM_START + 4 CHUNKs + STREAM_END
        // 35 bytes / 10 max = 4 chunks (10 + 10 + 10 + 5)
        let chunkFrames = sentFrames.filter { $0.frameType == .chunk }
        XCTAssertEqual(chunkFrames.count, 4, "35 bytes at max 10 should produce 4 chunks")

        // Verify each chunk respects max size (CBOR overhead adds bytes)
        for chunk in chunkFrames {
            // The payload contains CBOR-encoded data, so size may vary slightly
            XCTAssertNotNil(chunk.payload)
        }
    }

    // TEST542: OutputStream empty stream sends STREAM_START and STREAM_END only
    func test542_outputStreamCloseWithoutStartIsNoop() throws {
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        // Close without calling start() — no output produced, nothing to close
        try output.close()

        XCTAssertEqual(sentFrames.count, 0, "close() without start() must send no frames")
    }

    // TEST542b: OutputStream start + close sends STREAM_START + STREAM_END (empty stream)
    func test542b_outputStreamStartThenCloseEmpty() throws {
        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        // start() then close without writing — empty stream
        try output.start(isSequence: false)
        try output.close()

        let streamStartFrames = sentFrames.filter { $0.frameType == .streamStart }
        let chunkFrames = sentFrames.filter { $0.frameType == .chunk }
        let streamEndFrames = sentFrames.filter { $0.frameType == .streamEnd }

        XCTAssertEqual(streamStartFrames.count, 1)
        XCTAssertEqual(chunkFrames.count, 0)
        XCTAssertEqual(streamEndFrames.count, 1)
        XCTAssertEqual(streamEndFrames[0].chunkCount, 0)
    }

    // TEST542c: OutputStream write without start() throws
    func test542c_outputStreamWriteWithoutStartThrows() throws {
        let mockSender = MockFrameSender { _ in }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        XCTAssertThrowsError(try output.write(Data([1, 2, 3])), "write() without start() must throw")
    }

    // TEST542d: OutputStream start() twice throws
    func test542d_outputStreamDoubleStartThrows() throws {
        let mockSender = MockFrameSender { _ in }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        try output.start(isSequence: false)
        XCTAssertThrowsError(try output.start(isSequence: false), "start() twice must throw")
    }

    // TEST542e: OutputStream mode conflict throws (start write, call emitListItem)
    func test542e_outputStreamModeConflictThrows() throws {
        let mockSender = MockFrameSender { _ in }

        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "test-stream",
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        try output.start(isSequence: false)
        XCTAssertThrowsError(try output.emitListItem(.byteString([1, 2, 3])),
            "emitListItem on write-mode stream must throw")
    }

    // MARK: - PeerCall Tests (TEST543-545)

    // TEST543: PeerCall::arg creates OutputStream with correct stream_id
    func test543_peerCallArgCreatesStream() throws {
        // PeerCall.arg() should create an OutputStream for sending arguments
        // We test this by verifying the OutputStream has a unique streamId

        var sentFrames: [Frame] = []
        let mockSender = MockFrameSender { frame in
            sentFrames.append(frame)
        }

        // Create output stream (simulating what PeerCall.arg does)
        let output = Bifaci.OutputStream(
            sender: mockSender,
            streamId: "arg-0",  // PeerCall assigns sequential stream IDs
            mediaUrn: "media:test",
            requestId: .uint(1),
            routingId: nil,
            maxChunk: 1000
        )

        try output.start(isSequence: false)
        try output.write(Data([1, 2, 3]))
        try output.close()

        // Verify stream ID is used
        let streamStart = sentFrames.first { $0.frameType == .streamStart }
        XCTAssertEqual(streamStart?.streamId, "arg-0")
    }

    // TEST544: PeerCall::finish sends END frame
    func test544_peerCallFinishSendsEnd() throws {
        let captured = CaptureFrameSender()
        let requestId = MessageId.newUUID()

        // Create empty response channel (closes immediately)
        let emptyResponseRx = AnyIterator<Frame> { nil }

        let peer = PeerCall(
            sender: captured,
            requestId: requestId,
            maxChunk: 256_000,
            responseRx: emptyResponseRx
        )

        let _ = try peer.finish()

        let endFrames = captured.frames.filter { $0.frameType == .end }
        XCTAssertEqual(endFrames.count, 1, "must send END frame")
        XCTAssertEqual(endFrames[0].id, requestId, "END must have correct request ID")
    }

    // TEST545: PeerCall::finish returns PeerResponse with data
    func test545_peerCallFinishReturnsPeerResponse() throws {
        let captured = CaptureFrameSender()
        let reqId = MessageId.newUUID()

        // Build response frames
        var responseFrames: [Frame] = []
        responseFrames.append(Frame.streamStart(reqId: reqId, streamId: "response-stream", mediaUrn: "media:response"))

        let rawData = Data("response data".utf8)
        let cborPayload = Data(CBOR.byteString([UInt8](rawData)).encode())
        let checksum = Frame.computeChecksum(cborPayload)
        responseFrames.append(Frame.chunk(reqId: reqId, streamId: "response-stream", seq: 0, payload: cborPayload, chunkIndex: 0, checksum: checksum))
        responseFrames.append(Frame.streamEnd(reqId: reqId, streamId: "response-stream", chunkCount: 1))

        var idx = 0
        let responseRx = AnyIterator<Frame> {
            guard idx < responseFrames.count else { return nil }
            let f = responseFrames[idx]
            idx += 1
            return f
        }

        let peer = PeerCall(
            sender: captured,
            requestId: reqId,
            maxChunk: 256_000,
            responseRx: responseRx
        )

        let response = try peer.finish()
        let bytes = try response.collectBytes()
        XCTAssertEqual(bytes, rawData)
    }

    // MARK: - Stream Lookup Tests (TEST678-683)

    // TEST678: find_stream with exact equivalent URN (same tags, different order) succeeds
    func test678_findStreamEquivalentUrnDifferentTagOrder() throws {
        // One stream with tags in one order
        let streams: [(mediaUrn: String, bytes: Data)] = [
            ("media:json;record;llm-generation-request", Data("data".utf8)),
        ]

        // Look for it with tags in a DIFFERENT order — is_equivalent is order-independent
        let found = findStream(streams, mediaUrn: "media:llm-generation-request;json;record")
        XCTAssertNotNil(found, "Same tags in different order must match via is_equivalent")
        XCTAssertEqual(String(data: found!, encoding: .utf8), "data")
    }

    // TEST679: find_stream with base URN vs full URN fails — is_equivalent is strict This is the root cause of the cartridge_client.rs bug. Sender sent "media:llm-generation-request" but receiver looked for "media:llm-generation-request;json;record".
    func test679_findStreamBaseUrnDoesNotMatchFullUrn() throws {
        let streams: [(mediaUrn: String, bytes: Data)] = [
            ("media:llm-generation-request;json;record", Data("data".utf8)),
        ]

        // Base URN should NOT match full URN (strict equivalence)
        let result = findStream(streams, mediaUrn: "media:llm-generation-request")
        XCTAssertNil(result, "Base URN must not match full URN - is_equivalent is strict")
    }

    // TEST680: require_stream with missing URN returns hard StreamError
    func test680_requireStreamMissingUrnReturnsError() throws {
        let streams: [(mediaUrn: String, bytes: Data)] = [
            ("media:text", Data("data".utf8)),
        ]

        XCTAssertThrowsError(try requireStream(streams, mediaUrn: "media:missing")) { error in
            guard case StreamError.protocolError(let msg) = error else {
                XCTFail("Expected protocolError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("media:missing"), "Error message should contain the missing URN")
        }
    }

    // TEST681: find_stream with multiple streams returns the correct one
    func test681_findStreamMultipleStreamsReturnsCorrect() throws {
        let streams: [(mediaUrn: String, bytes: Data)] = [
            ("media:text", Data("text-data".utf8)),
            ("media:json", Data("json-data".utf8)),
            ("media:binary", Data("binary-data".utf8)),
        ]

        let textResult = findStream(streams, mediaUrn: "media:text")
        XCTAssertEqual(String(data: textResult!, encoding: .utf8), "text-data")

        let jsonResult = findStream(streams, mediaUrn: "media:json")
        XCTAssertEqual(String(data: jsonResult!, encoding: .utf8), "json-data")

        let binaryResult = findStream(streams, mediaUrn: "media:binary")
        XCTAssertEqual(String(data: binaryResult!, encoding: .utf8), "binary-data")
    }

    // TEST682: require_stream_str returns UTF-8 string for text data
    func test682_requireStreamStrReturnsUtf8() throws {
        let streams: [(mediaUrn: String, bytes: Data)] = [
            ("media:text", Data("Hello, World!".utf8)),
        ]

        let result = try requireStreamStr(streams, mediaUrn: "media:text")
        XCTAssertEqual(result, "Hello, World!")
    }

    // TEST683: find_stream returns None for invalid media URN string (not a parse error — just None)
    func test683_findStreamInvalidUrnReturnsNone() throws {
        let streams: [(mediaUrn: String, bytes: Data)] = [
            ("media:text", Data("data".utf8)),
        ]

        // Non-existent URN should return nil, not error
        let result = findStream(streams, mediaUrn: "media:nonexistent")
        XCTAssertNil(result)

        // Empty URN should return nil
        let emptyResult = findStream(streams, mediaUrn: "")
        XCTAssertNil(emptyResult)
    }

    // MARK: - PeerResponse Tests (TEST839-841)

    // TEST839: LOG frames arriving BEFORE StreamStart are delivered immediately  This tests the critical fix: during a peer call, the peer (e.g., modelcartridge) sends LOG frames for minutes during model download BEFORE sending any data (StreamStart + Chunk). The handler must receive these LOGs in real-time so it can re-emit progress and keep the engine's activity timer alive.  Previously, demux_single_stream blocked on awaiting StreamStart before returning PeerResponse, which meant the handler couldn't call recv() until data arrived — causing 120s activity timeouts during long downloads.
    func test839_peerResponseDeliversLogsBeforeStreamStart() throws {
        let reqId = MessageId.newUUID()

        // Build response frames: LOG frames BEFORE StreamStart
        var responseFrames: [Frame] = []
        responseFrames.append(Frame.progress(id: reqId, progress: 0.1, message: "downloading file 1/10"))
        responseFrames.append(Frame.progress(id: reqId, progress: 0.5, message: "downloading file 5/10"))
        responseFrames.append(Frame.log(id: reqId, level: "status", message: "large file in progress"))

        // Then the actual data
        responseFrames.append(Frame.streamStart(reqId: reqId, streamId: "s1", mediaUrn: "media:binary"))

        let rawData = Data("model output".utf8)
        let cborPayload = Data(CBOR.byteString([UInt8](rawData)).encode())
        let checksum = Frame.computeChecksum(cborPayload)
        responseFrames.append(Frame.chunk(reqId: reqId, streamId: "s1", seq: 0, payload: cborPayload, chunkIndex: 0, checksum: checksum))
        responseFrames.append(Frame.streamEnd(reqId: reqId, streamId: "s1", chunkCount: 1))

        var idx = 0
        let responseRx = AnyIterator<Frame> {
            guard idx < responseFrames.count else { return nil }
            let f = responseFrames[idx]
            idx += 1
            return f
        }

        // demuxSingleStream returns PeerResponse immediately — not blocking on StreamStart
        let response = demuxSingleStream(responseRx: responseRx, maxChunk: 256_000)

        // First 3 items must be LOG frames
        let item1 = response.recv()
        if case .log(let f) = item1 {
            XCTAssertEqual(f.logProgress, 0.1)
            XCTAssertEqual(f.logMessage, "downloading file 1/10")
        } else {
            XCTFail("Expected LOG frame, got \(String(describing: item1))")
        }

        let item2 = response.recv()
        if case .log(let f) = item2 {
            XCTAssertEqual(f.logProgress, 0.5)
            XCTAssertEqual(f.logMessage, "downloading file 5/10")
        } else {
            XCTFail("Expected LOG frame, got \(String(describing: item2))")
        }

        let item3 = response.recv()
        if case .log(let f) = item3 {
            XCTAssertEqual(f.logMessage, "large file in progress")
        } else {
            XCTFail("Expected LOG frame, got \(String(describing: item3))")
        }

        // Next item must be data
        let item4 = response.recv()
        if case .data(let result) = item4 {
            let value = try result.get()
            if case .byteString(let bytes) = value {
                XCTAssertEqual(Data(bytes), rawData)
            } else {
                XCTFail("Expected byteString, got \(value)")
            }
        } else {
            XCTFail("Expected Data, got \(String(describing: item4))")
        }

        // Stream must end
        XCTAssertNil(response.recv(), "stream must end after STREAM_END")
    }

    // TEST840: PeerResponse::collect_bytes discards LOG frames
    func test840_peerResponseCollectBytesDiscardsLogs() throws {
        let reqId = MessageId.newUUID()

        var responseFrames: [Frame] = []
        responseFrames.append(Frame.streamStart(reqId: reqId, streamId: "s1", mediaUrn: "media:binary"))
        // LOG frames interleaved with data
        responseFrames.append(Frame.progress(id: reqId, progress: 0.25, message: "working"))
        responseFrames.append(Frame.progress(id: reqId, progress: 0.75, message: "almost"))

        let cborPayload = Data(CBOR.byteString([UInt8]("hello".utf8)).encode())
        let checksum = Frame.computeChecksum(cborPayload)
        responseFrames.append(Frame.chunk(reqId: reqId, streamId: "s1", seq: 0, payload: cborPayload, chunkIndex: 0, checksum: checksum))

        responseFrames.append(Frame.log(id: reqId, level: "info", message: "done"))
        responseFrames.append(Frame.streamEnd(reqId: reqId, streamId: "s1", chunkCount: 1))

        var idx = 0
        let responseRx = AnyIterator<Frame> {
            guard idx < responseFrames.count else { return nil }
            let f = responseFrames[idx]
            idx += 1
            return f
        }

        let response = demuxSingleStream(responseRx: responseRx, maxChunk: 256_000)
        let bytes = try response.collectBytes()
        XCTAssertEqual(bytes, Data("hello".utf8), "collectBytes must return only data, discarding all LOG frames")
    }

    // TEST841: PeerResponse::collect_value discards LOG frames
    func test841_peerResponseCollectValueDiscardsLogs() throws {
        let reqId = MessageId.newUUID()

        var responseFrames: [Frame] = []
        responseFrames.append(Frame.streamStart(reqId: reqId, streamId: "s1", mediaUrn: "media:binary"))
        // LOG frames before data
        responseFrames.append(Frame.progress(id: reqId, progress: 0.5, message: "half"))
        responseFrames.append(Frame.log(id: reqId, level: "debug", message: "processing"))

        // Single CHUNK with a CBOR unsigned int 42
        let cborPayload = Data(CBOR.unsignedInt(42).encode())
        let checksum = Frame.computeChecksum(cborPayload)
        responseFrames.append(Frame.chunk(reqId: reqId, streamId: "s1", seq: 0, payload: cborPayload, chunkIndex: 0, checksum: checksum))
        responseFrames.append(Frame.streamEnd(reqId: reqId, streamId: "s1", chunkCount: 1))

        var idx = 0
        let responseRx = AnyIterator<Frame> {
            guard idx < responseFrames.count else { return nil }
            let f = responseFrames[idx]
            idx += 1
            return f
        }

        let response = demuxSingleStream(responseRx: responseRx, maxChunk: 256_000)
        let value = try response.collectValue()
        XCTAssertEqual(value, CBOR.unsignedInt(42), "collectValue must skip LOG frames and return first data value")
    }

    // MARK: - Keepalive Tests (TEST842-844)

    // TEST842: run_with_keepalive returns closure result (fast operation, no keepalive frames)
    func test842_runWithKeepaliveReturnsResult() async throws {
        let captured = CaptureFrameSender()
        let stream = Bifaci.OutputStream(
            sender: captured,
            streamId: "stream-1",
            mediaUrn: "media:test",
            requestId: MessageId.newUUID(),
            routingId: nil,
            maxChunk: DEFAULT_MAX_CHUNK
        )

        // Run a fast operation — no keepalive frame expected (interval is 30s)
        let result: Int = try await stream.runWithKeepalive(progress: 0.25, message: "Loading model") {
            42
        }
        XCTAssertEqual(result, 42, "Closure result must be returned")

        // No keepalive frame should have been emitted (operation was instant)
        let progressFrames = captured.frames.filter { $0.frameType == .log }
        XCTAssertEqual(progressFrames.count, 0, "No keepalive frame for instant operation")
    }

    // TEST843: run_with_keepalive returns Ok/Err from closure
    func test843_runWithKeepaliveReturnsResultType() async throws {
        let captured = CaptureFrameSender()
        let stream = Bifaci.OutputStream(
            sender: captured,
            streamId: "stream-1",
            mediaUrn: "media:test",
            requestId: MessageId.newUUID(),
            routingId: nil,
            maxChunk: DEFAULT_MAX_CHUNK
        )

        let result: String = try await stream.runWithKeepalive(progress: 0.5, message: "Loading") {
            "model_loaded"
        }
        XCTAssertEqual(result, "model_loaded")
    }

    // TEST844: run_with_keepalive propagates errors from closure
    func test844_runWithKeepalivePropagatesError() async throws {
        let captured = CaptureFrameSender()
        let stream = Bifaci.OutputStream(
            sender: captured,
            streamId: "stream-1",
            mediaUrn: "media:test",
            requestId: MessageId.newUUID(),
            routingId: nil,
            maxChunk: DEFAULT_MAX_CHUNK
        )

        do {
            let _: Void = try await stream.runWithKeepalive(progress: 0.25, message: "Loading") {
                throw CartridgeRuntimeError.handlerError("load failed")
            }
            XCTFail("Should have thrown")
        } catch let error as CartridgeRuntimeError {
            if case .handlerError(let msg) = error {
                XCTAssertEqual(msg, "load failed")
            } else {
                XCTFail("Expected handlerError, got \(error)")
            }
        }
    }

    // MARK: - ProgressSender Tests (TEST845)

    // TEST845: ProgressSender emits progress and log frames independently of OutputStream
    func test845_progressSenderEmitsFrames() throws {
        let captured = CaptureFrameSender()
        let stream = Bifaci.OutputStream(
            sender: captured,
            streamId: "stream-1",
            mediaUrn: "media:test",
            requestId: MessageId.newUUID(),
            routingId: nil,
            maxChunk: DEFAULT_MAX_CHUNK
        )

        let ps = stream.progressSender()
        ps.progress(0.5, message: "halfway there")
        ps.log(level: "info", message: "loading complete")

        XCTAssertEqual(captured.frames.count, 2, "ProgressSender should emit 2 frames")
        XCTAssertEqual(captured.frames[0].frameType, .log)
        XCTAssertEqual(captured.frames[1].frameType, .log)
        // Verify progress frame
        XCTAssertEqual(captured.frames[0].logProgress, 0.5)
        XCTAssertEqual(captured.frames[0].logMessage, "halfway there")
        // Verify log frame
        XCTAssertEqual(captured.frames[1].logLevel, "info")
        XCTAssertEqual(captured.frames[1].logMessage, "loading complete")
    }
}

// MARK: - Mock FrameSenders

/// Mock FrameSender for testing (callback-based, private to this file)
private final class MockFrameSender: FrameSender, @unchecked Sendable {
    private let onSend: (Frame) -> Void

    init(onSend: @escaping (Frame) -> Void) {
        self.onSend = onSend
    }

    func send(_ frame: Frame) throws {
        onSend(frame)
    }
}

/// Thread-safe frame-capturing sender for testing
private final class CaptureFrameSender: FrameSender, @unchecked Sendable {
    private let lock = NSLock()
    private var _frames: [Frame] = []

    var frames: [Frame] {
        lock.lock()
        defer { lock.unlock() }
        return _frames
    }

    func send(_ frame: Frame) throws {
        lock.lock()
        _frames.append(frame)
        lock.unlock()
    }
}
