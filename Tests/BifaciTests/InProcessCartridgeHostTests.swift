//
//  InProcessCartridgeHostTests.swift
//  Tests for InProcessCartridgeHost
//
//  Mirrors Rust tests from capdag/src/bifaci/in_process_host.rs exactly
//  Tests numbered TEST654-TEST660

import XCTest
import Foundation
import SwiftCBOR
@testable import Bifaci
@testable import CapDAG

final class InProcessCartridgeHostTests: XCTestCase {

    // MARK: - Test Helpers

    /// Make a test cap from a URN string
    private func makeTestCap(_ urnStr: String) -> CSCap {
        let urn = try! CSCapUrn.fromString(urnStr)
        return CSCap(urn: urn, title: "test", aliases: ["test"])
    }

    /// Build a CBOR-encoded chunk payload from raw bytes (matching build_request_frames).
    private func cborBytesPayload(_ data: Data) -> Data {
        return Data(CBOR.byteString([UInt8](data)).encode())
    }

    /// CBOR-decode a response chunk payload to extract raw bytes.
    private func decodeChunkPayload(_ payload: Data) -> Data {
        guard let cbor = try? CBOR.decode([UInt8](payload)) else {
            fatalError("Failed to decode CBOR from payload")
        }
        switch cbor {
        case .byteString(let bytes):
            return Data(bytes)
        case .utf8String(let str):
            return str.data(using: .utf8) ?? Data()
        default:
            fatalError("unexpected CBOR type in response chunk: \(cbor)")
        }
    }

    /// Identity nonce for verification (must match Rust exactly)
    /// CBOR-encoded Text("bifaci") — 7-byte deterministic nonce
    private func identityNonce() -> Data {
        return Data(CBOR.utf8String("bifaci").encode())
    }

    // MARK: - Test Handlers

    /// Echo handler: accumulates input, echoes raw bytes back (for TEST654, TEST657, TEST660)
    final class EchoHandler: FrameHandler {
        func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) {
            Task {
                do {
                    let args = try await accumulateInput(inputStream: inputStream)
                    let data = args.flatMap { $0.value }
                    output.emitResponse(mediaUrn: "media:", data: Data(data))
                } catch {
                    output.emitError(code: "ACCUMULATE_ERROR", message: error.localizedDescription)
                }
            }
        }
    }

    /// Fail handler: always returns error (for TEST659)
    final class FailHandler: FrameHandler {
        func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) {
            Task {
                // Drain input
                for await frame in inputStream {
                    if frame.frameType == .end {
                        break
                    }
                }
                output.emitError(code: "CARTRIDGE_ERROR", message: "cartridge crashed")
            }
        }
    }

    /// Tagged handler: returns its tag name (for TEST660)
    final class TaggedHandler: FrameHandler {
        let tag: String

        init(tag: String) {
            self.tag = tag
        }

        func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) {
            Task {
                // Drain input
                for await frame in inputStream {
                    if frame.frameType == .end {
                        break
                    }
                }
                output.emitResponse(mediaUrn: "media:text", data: tag.data(using: .utf8)!)
            }
        }
    }

    // TEST6748: InProcessCartridgeHost routes REQ to matching handler and returns response
    func test6748_routesReqToHandler() throws {
        let capUrn = "cap:in=\"media:text\";echo;out=\"media:text\""
        let cap = makeTestCap(capUrn)
        let handlers: [(name: String, caps: [CSCap], handler: FrameHandler)] = [
            ("echo", [cap], EchoHandler())
        ]

        let host = InProcessCartridgeHost(
            identity: InProcessHostIdentity.forTest(id: "in-process-test"),
            handlers: handlers
        )

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        // Run host in background thread
        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // First frame should be RelayNotify with manifest
        let notify = try! reader.read()!
        XCTAssertEqual(notify.frameType, .relayNotify)
        let manifest = notify.relayNotifyManifest!
        let payload = try! JSONDecoder().decode(RelayNotifyCapabilitiesPayload.self, from: manifest)
        let caps = payload.capUrns()
        XCTAssertTrue(caps.count >= 2) // identity + echo cap
        XCTAssertEqual(caps[0], CSCapIdentity)
        // The InProcessCartridgeHost wraps its handlers in one
        // installed-cartridge entry whose identity is the
        // `InProcessHostIdentity` the test passed at construction
        // (here, `forTest(id: "in-process-test")`).
        XCTAssertEqual(payload.installedCartridges.count, 1)
        XCTAssertEqual(payload.installedCartridges[0].id, "in-process-test")

        // Send a REQ + STREAM_START + CHUNK (CBOR-encoded) + STREAM_END + END
        let rid = MessageId.newUUID()
        var req = Frame.req(id: rid, capUrn: capUrn, payload: Data(), contentType: "application/cbor")
        req.routingId = MessageId.uint(1)
        try! writer.write(req)

        let ss = Frame.streamStart(reqId: rid, streamId: "arg0", mediaUrn: "media:text")
        try! writer.write(ss)

        let chunkPayload = cborBytesPayload("hello world".data(using: .utf8)!)
        let checksum = Frame.computeChecksum(chunkPayload)
        let chunk = Frame.chunk(reqId: rid, streamId: "arg0", seq: 0, payload: chunkPayload, chunkIndex: 0, checksum: checksum)
        try! writer.write(chunk)

        let se = Frame.streamEnd(reqId: rid, streamId: "arg0", chunkCount: 1)
        try! writer.write(se)

        let end = Frame.end(id: rid)
        try! writer.write(end)

        // Read response: STREAM_START + CHUNK (CBOR-encoded) + STREAM_END + END
        let respSs = try! reader.read()!
        XCTAssertEqual(respSs.frameType, .streamStart)
        XCTAssertEqual(respSs.id, rid)
        XCTAssertEqual(respSs.streamId, "result")

        let respChunk = try! reader.read()!
        XCTAssertEqual(respChunk.frameType, .chunk)
        let respData = decodeChunkPayload(respChunk.payload!)
        XCTAssertEqual(respData, "hello world".data(using: .utf8)!)

        let respSe = try! reader.read()!
        XCTAssertEqual(respSe.frameType, .streamEnd)

        let respEnd = try! reader.read()!
        XCTAssertEqual(respEnd.frameType, .end)

        // Cleanup
        testWrite.closeFile()
        testRead.closeFile()
        // Host thread will exit when sockets close
        Thread.sleep(forTimeInterval: 0.1)
    }

    // TEST1961: the in-process host answers a Cancel in the cancel's OWN
    // attribution — ERR ABORTED/resource for a host abort (message carries
    // the reason), ERR ABORTED_COLLATERAL with the originating failure's
    // class for collateral, ERR CANCELLED/user for an operator's cancel, and
    // ERR CANCELLED/internal for an UNATTRIBUTED cancel, which still cancels.
    // A CloseStream is a no-op for a handler with no live feed: the request
    // continues and completes normally with END.
    func test1961_cancelTerminalCarriesItsAttribution() throws {
        let capUrn = "cap:in=\"media:text\";echo;out=\"media:text\""

        func run(_ control: Frame) throws -> Frame {
            let cap = makeTestCap(capUrn)
            let host = InProcessCartridgeHost(
                identity: InProcessHostIdentity.forTest(id: "in-process-test"),
                handlers: [("echo", [cap], EchoHandler())]
            )
            let (hostRead, testWrite) = Pipe.socketPair()
            let (testRead, hostWrite) = Pipe.socketPair()
            let hostThread = Thread {
                try? host.run(localRead: hostRead, localWrite: hostWrite)
            }
            hostThread.start()
            let reader = FrameReader(handle: testRead)
            let writer = FrameWriter(handle: testWrite)
            let notify = try XCTUnwrap(reader.read())
            XCTAssertEqual(notify.frameType, .relayNotify)

            // Open the request and its input stream, but do not END it — the
            // handler is active when the control frame arrives.
            let rid = MessageId.newUUID()
            var req = Frame.req(id: rid, capUrn: capUrn, payload: Data(), contentType: "application/cbor")
            req.routingId = MessageId.uint(1)
            try writer.write(req)
            try writer.write(Frame.streamStart(reqId: rid, streamId: "arg0", mediaUrn: "media:text"))

            var control = control
            control.id = rid
            control.routingId = MessageId.uint(1)
            try writer.write(control)

            var outcome: Frame
            if control.frameType == .closeStream {
                // Finish the request: it was never cancelled.
                let chunkPayload = cborBytesPayload("still here".data(using: .utf8)!)
                try writer.write(Frame.chunk(reqId: rid, streamId: "arg0", seq: 0, payload: chunkPayload, chunkIndex: 0, checksum: Frame.computeChecksum(chunkPayload)))
                try writer.write(Frame.streamEnd(reqId: rid, streamId: "arg0", chunkCount: 1))
                try writer.write(Frame.end(id: rid))
                while true {
                    let frame = try XCTUnwrap(reader.read())
                    XCTAssertEqual(frame.id, rid)
                    XCTAssertNotEqual(frame.frameType, .err, "a CloseStream never aborts")
                    outcome = frame
                    if frame.frameType == .end { break }
                }
            } else {
                outcome = try XCTUnwrap(reader.read())
                XCTAssertEqual(outcome.id, rid)
            }
            testWrite.closeFile()
            testRead.closeFile()
            Thread.sleep(forTimeInterval: 0.1)
            return outcome
        }
        func cancel(_ reason: CancelReason) -> Frame { Frame.cancel(targetRid: .uint(0), reason: reason) }

        let hostAbort = try run(cancel(.host(.resource, "memory pressure relief")))
        XCTAssertEqual(hostAbort.frameType, .err)
        XCTAssertEqual(hostAbort.errorCode, "ABORTED")
        XCTAssertEqual(try hostAbort.attributionClass(), .resource)
        XCTAssertTrue((hostAbort.errorMessage ?? "").contains("memory pressure relief"), hostAbort.errorMessage ?? "")

        let collateral = try run(cancel(.collateral(.input, "step s1 failed")))
        XCTAssertEqual(collateral.errorCode, "ABORTED_COLLATERAL")
        XCTAssertEqual(try collateral.attributionClass(), .input)

        let user = try run(cancel(.user()))
        XCTAssertEqual(user.errorCode, "CANCELLED")
        XCTAssertEqual(try user.attributionClass(), .user)

        let bare = try run(cancel(.unattributed()))
        XCTAssertEqual(bare.errorCode, "CANCELLED", "an unattributed Cancel still cancels")
        XCTAssertEqual(try bare.attributionClass(), .internal)

        XCTAssertEqual(try run(Frame.closeStream(targetRid: .uint(0))).frameType, .end)
    }

    // TEST6749: InProcessCartridgeHost handles identity verification (echo nonce)
    func test6749_identityVerification() throws {
        let host = InProcessCartridgeHost(
            identity: InProcessHostIdentity.forTest(id: "in-process-test"),
            handlers: []
        )

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        // Send identity verification
        let rid = MessageId.newUUID()
        var req = Frame.req(id: rid, capUrn: CSCapIdentity, payload: Data(), contentType: "application/cbor")
        req.routingId = MessageId.uint(0)
        try! writer.write(req)

        // Send nonce via stream (raw bytes, NOT CBOR-encoded for identity)
        let nonce = identityNonce()
        let ss = Frame.streamStart(reqId: rid, streamId: "identity-verify", mediaUrn: "media:")
        try! writer.write(ss)

        let checksum = Frame.computeChecksum(nonce)
        let chunk = Frame.chunk(reqId: rid, streamId: "identity-verify", seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum)
        try! writer.write(chunk)

        let se = Frame.streamEnd(reqId: rid, streamId: "identity-verify", chunkCount: 1)
        try! writer.write(se)

        let end = Frame.end(id: rid)
        try! writer.write(end)

        // Read echoed response — identity echoes raw bytes (no CBOR decode/encode)
        let respSs = try! reader.read()!
        XCTAssertEqual(respSs.frameType, .streamStart)

        let respChunk = try! reader.read()!
        XCTAssertEqual(respChunk.frameType, .chunk)
        XCTAssertEqual(respChunk.payload, nonce)

        let respSe = try! reader.read()!
        XCTAssertEqual(respSe.frameType, .streamEnd)

        let respEnd = try! reader.read()!
        XCTAssertEqual(respEnd.frameType, .end)

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }

    // TEST6750: InProcessCartridgeHost returns NO_HANDLER for unregistered cap
    func test6750_noHandlerReturnsErr() throws {
        let host = InProcessCartridgeHost(
            identity: InProcessHostIdentity.forTest(id: "in-process-test"),
            handlers: []
        )

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        let rid = MessageId.newUUID()
        var req = Frame.req(
            id: rid,
            capUrn: "cap:in=\"media:ext=pdf\";unknown;out=\"media:text\"",
            payload: Data(),
            contentType: "application/cbor"
        )
        req.routingId = MessageId.uint(1)
        try! writer.write(req)

        // Should get ERR back
        let errFrame = try! reader.read()!
        XCTAssertEqual(errFrame.frameType, .err)
        XCTAssertEqual(errFrame.id, rid)
        XCTAssertEqual(errFrame.errorCode, "NO_HANDLER")

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }

    // TEST6751: InProcessCartridgeHost manifest includes identity cap and handler caps
    func test6751_manifestIncludesAllCaps() throws {
        let capUrn = "cap:in=\"media:ext=pdf\";thumbnail;out=\"media:ext=png;image\""
        let cap = makeTestCap(capUrn)
        let host = InProcessCartridgeHost(
            identity: InProcessHostIdentity.forTest(id: "thumb-host"),
            handlers: [
                ("thumb", [cap], EchoHandler())
            ]
        )

        let manifest = host.buildManifest()
        let payload = try! JSONDecoder().decode(RelayNotifyCapabilitiesPayload.self, from: manifest)
        let caps = payload.capUrns()
        XCTAssertEqual(caps[0], CSCapIdentity)
        XCTAssertTrue(caps.contains { $0.contains("thumbnail") })
        XCTAssertEqual(payload.installedCartridges.count, 1)
        // Identity round-trips: the manifest carries whatever id the
        // embedder supplied, here `forTest(id: "thumb-host")`.
        XCTAssertEqual(payload.installedCartridges[0].id, "thumb-host")
        XCTAssertEqual(payload.installedCartridges[0].capGroups.count, 1)
        XCTAssertEqual(payload.installedCartridges[0].runtimeStats?.running, true)
        // The pool map is the capacity surface: one at-rest unlimited
        // singleton per advertised cap plus the mandatory `all` pool.
        let pools = payload.installedCartridges[0].runtimeStats?.pools ?? [:]
        XCTAssertEqual(pools[poolAll]?.configured, 0, "in-process hosts are unlimited")
        XCTAssertNotNil(pools[CSCapIdentity])
    }

    // TEST658: InProcessCartridgeHost handles heartbeat by echoing same ID
    func test658_heartbeatResponse() throws {
        let host = InProcessCartridgeHost(
            identity: InProcessHostIdentity.forTest(id: "in-process-test"),
            handlers: []
        )

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        let hbId = MessageId.newUUID()
        let hb = Frame.heartbeat(id: hbId)
        try! writer.write(hb)

        let resp = try! reader.read()!
        XCTAssertEqual(resp.frameType, .heartbeat)
        XCTAssertEqual(resp.id, hbId)
        // The heartbeat reply's mandatory pool map replaces the retired
        // scalar handler_capacity meta.
        let poolBytes = resp.poolStateBytes
        XCTAssertNotNil(poolBytes, "heartbeat reply must carry the pool map")
        let states = try decodePoolStates(poolBytes!)
        XCTAssertEqual(states[poolAll]?.configured, 0, "in-process hosts are unlimited")
        XCTAssertEqual(states[poolAll]?.active, 0)

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }

    // TEST659: InProcessCartridgeHost handler error returns ERR frame
    func test659_handlerErrorReturnsErrFrame() throws {
        let capUrn = "cap:in=\"media:void\";fail;out=\"media:void\""
        let cap = makeTestCap(capUrn)
        let host = InProcessCartridgeHost(
            identity: InProcessHostIdentity.forTest(id: "fail-host"),
            handlers: [
                ("fail", [cap], FailHandler())
            ]
        )

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        // Send REQ + END (no streams, void input)
        let rid = MessageId.newUUID()
        var req = Frame.req(id: rid, capUrn: capUrn, payload: Data(), contentType: "application/cbor")
        req.routingId = MessageId.uint(1)
        try! writer.write(req)

        let end = Frame.end(id: rid)
        try! writer.write(end)

        // Should get ERR frame
        let errFrame = try! reader.read()!
        XCTAssertEqual(errFrame.frameType, .err)
        XCTAssertEqual(errFrame.id, rid)
        XCTAssertEqual(errFrame.errorCode, "CARTRIDGE_ERROR")
        XCTAssertTrue(errFrame.errorMessage!.contains("cartridge crashed"))

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }

    // TEST660: InProcessCartridgeHost closest-specificity routing prefers specific over identity
    func test660_closestSpecificityRouting() throws {
        let specificUrn = "cap:in=\"media:ext=pdf\";thumbnail;out=\"media:ext=png;image\""
        let genericUrn = "cap:in=\"media:image\";thumbnail;out=\"media:ext=png;image\""

        let specificCap = makeTestCap(specificUrn)
        let genericCap = makeTestCap(genericUrn)

        let handlers: [(name: String, caps: [CSCap], handler: FrameHandler)] = [
            ("generic", [genericCap], TaggedHandler(tag: "generic")),
            ("specific", [specificCap], TaggedHandler(tag: "specific")),
        ]

        let host = InProcessCartridgeHost(
            identity: InProcessHostIdentity.forTest(id: "in-process-test"),
            handlers: handlers
        )

        let (hostRead, testWrite) = Pipe.socketPair()
        let (testRead, hostWrite) = Pipe.socketPair()

        let hostThread = Thread {
            try? host.run(localRead: hostRead, localWrite: hostWrite)
        }
        hostThread.start()

        let reader = FrameReader(handle: testRead)
        let writer = FrameWriter(handle: testWrite)

        // Skip RelayNotify
        _ = try! reader.read()!

        // Request with specific input (media:ext=pdf) — should route to "specific" handler
        let rid = MessageId.newUUID()
        var req = Frame.req(id: rid, capUrn: specificUrn, payload: Data(), contentType: "application/cbor")
        req.routingId = MessageId.uint(1)
        try! writer.write(req)

        let end = Frame.end(id: rid, finalPayload: nil)
        try! writer.write(end)

        // Read response
        let respSs = try! reader.read()!
        XCTAssertEqual(respSs.frameType, .streamStart)

        let respChunk = try! reader.read()!
        XCTAssertEqual(respChunk.frameType, .chunk)
        let respData = decodeChunkPayload(respChunk.payload!)
        XCTAssertEqual(String(data: respData, encoding: .utf8), "specific")

        let respSe = try! reader.read()!
        XCTAssertEqual(respSe.frameType, .streamEnd)

        let respEnd = try! reader.read()!
        XCTAssertEqual(respEnd.frameType, .end)

        testWrite.closeFile()
        testRead.closeFile()
        Thread.sleep(forTimeInterval: 0.1)
    }

    // MARK: - One terminal per request

    /// Answers however its input ended: at END, or when the host finished its
    /// input. It stands for every handler that does not check — the host, not
    /// the handler, is what keeps a request to one terminal. Signals
    /// `answered` once it has sent its answer.
    final class AnswersAnywayHandler: FrameHandler {
        let answered = DispatchSemaphore(value: 0)
        func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) {
            Task {
                for await frame in inputStream where frame.frameType == .end {
                    break
                }
                output.emitResponse(mediaUrn: "media:", data: "an answer".data(using: .utf8)!)
                self.answered.signal()
            }
        }
    }

    // TEST344: input that does not reach its END is refused, not returned as
    // the request's arguments.
    //
    // The host finishes a handler's input when the request is cancelled or its
    // connection ends, and forwards an ERR from upstream. Each was accumulated
    // as if the request were complete, so a handler answered a request that no
    // longer existed, with whatever part of its input had arrived.
    func test344_accumulateRefusesInputThatNeverEnded() async throws {
        let rid = MessageId.newUUID()
        let payload = cborBytesPayload("part".data(using: .utf8)!)
        let start = Frame.streamStart(reqId: rid, streamId: "arg0", mediaUrn: "media:text")
        let chunk = Frame.chunk(reqId: rid, streamId: "arg0", seq: 0, payload: payload, chunkIndex: 0, checksum: Frame.computeChecksum(payload))

        let (closed, closedIn) = AsyncStream<Frame>.makeStream()
        closedIn.yield(start)
        closedIn.yield(chunk)
        closedIn.finish()
        do {
            _ = try await accumulateInput(inputStream: closed)
            XCTFail("input finished before its END was accumulated")
        } catch let error as InProcessInputError {
            XCTAssertEqual(error, .endedWithoutEnd)
        }

        let (failed, failedIn) = AsyncStream<Frame>.makeStream()
        failedIn.yield(start)
        failedIn.yield(Frame.err(id: rid, code: "UPSTREAM_DIED", attributionClass: .internal, message: "the producer failed"))
        failedIn.finish()
        do {
            _ = try await accumulateInput(inputStream: failed)
            XCTFail("input with an upstream ERR was accumulated")
        } catch let error as InProcessInputError {
            XCTAssertEqual(error, .failedUpstream(code: "UPSTREAM_DIED", message: "the producer failed"))
        }

        let (complete, completeIn) = AsyncStream<Frame>.makeStream()
        for frame in [start, chunk, Frame.streamEnd(reqId: rid, streamId: "arg0", chunkCount: 1), Frame.end(id: rid)] {
            completeIn.yield(frame)
        }
        completeIn.finish()
        let args = try await accumulateInput(inputStream: complete)
        XCTAssertEqual(args.map { $0.value }, ["part".data(using: .utf8)!])
    }

    // TEST345: once a request has its terminal, the host sends nothing more
    // for it.
    //
    // Two ways a request ended and more followed: a CANCEL arriving after the
    // handler finished, answered with a second terminal; and a CANCEL while
    // input was open, after which a handler that answers anyway sent its
    // response around the cancel's ERR. The ERR must be that request's only
    // frame.
    func test345_aRequestEndsOnce() throws {
        let capUrn = "cap:in=\"media:text\";echo;out=\"media:text\""
        let xid = MessageId.uint(1)

        /// Runs `script` against a fresh host; every frame the host sent for
        /// the request, up to the connection's end.
        func framesFor(_ script: (MessageId, FrameWriter, FrameReader, DispatchSemaphore) throws -> [Frame]) throws -> [Frame] {
            let handler = AnswersAnywayHandler()
            let host = InProcessCartridgeHost(
                identity: InProcessHostIdentity.forTest(id: "in-process-test"),
                handlers: [("answers", [makeTestCap(capUrn)], handler)]
            )
            let (hostRead, testWrite) = Pipe.socketPair()
            let (testRead, hostWrite) = Pipe.socketPair()
            let hostDone = DispatchSemaphore(value: 0)
            let hostThread = Thread {
                try? host.run(localRead: hostRead, localWrite: hostWrite)
                hostDone.signal()
            }
            hostThread.start()
            let reader = FrameReader(handle: testRead)
            let writer = FrameWriter(handle: testWrite)
            XCTAssertEqual(try XCTUnwrap(reader.read()).frameType, .relayNotify)

            let rid = MessageId.newUUID()
            var req = Frame.req(id: rid, capUrn: capUrn, payload: Data(), contentType: "application/cbor")
            req.routingId = xid
            try writer.write(req)
            try writer.write(Frame.streamStart(reqId: rid, streamId: "arg0", mediaUrn: "media:text"))
            var seen = try script(rid, writer, reader, handler.answered)
            // The script is done writing: the host ends, and everything it
            // sent is read to the connection's end.
            testWrite.closeFile()
            XCTAssertEqual(hostDone.wait(timeout: .now() + 10), .success, "the host ends when its input does")
            hostWrite.closeFile()
            while let frame = try reader.read() {
                seen.append(frame)
            }
            testRead.closeFile()
            return seen.filter { $0.id == rid }
        }
        func cancelFor(_ rid: MessageId) -> Frame {
            var cancel = Frame.cancel(targetRid: .uint(0), reason: .user())
            cancel.id = rid
            cancel.routingId = xid
            return cancel
        }

        // A CANCEL after the handler finished: the request's END stands alone.
        let afterEnd = try framesFor { rid, writer, reader, answered in
            try writer.write(Frame.end(id: rid))
            XCTAssertEqual(answered.wait(timeout: .now() + 10), .success)
            var seen: [Frame] = []
            while true {
                let frame = try XCTUnwrap(reader.read())
                seen.append(frame)
                if frame.id == rid && frame.frameType == .end { break }
            }
            try writer.write(cancelFor(rid))
            return seen
        }
        XCTAssertEqual(afterEnd.last?.frameType, .end)
        XCTAssertFalse(afterEnd.contains { $0.frameType == .err }, "a cancel after END adds no terminal")

        // A CANCEL while input is open: its ERR is the request's only frame.
        let cancelled = try framesFor { rid, writer, _, answered in
            try writer.write(cancelFor(rid))
            XCTAssertEqual(answered.wait(timeout: .now() + 10), .success, "the handler answered")
            return []
        }
        XCTAssertEqual(cancelled.count, 1, "\(cancelled.map { $0.frameType })")
        XCTAssertEqual(cancelled.first?.frameType, .err)
        XCTAssertEqual(cancelled.first?.errorCode, "CANCELLED")
    }
}

// MARK: - Socket Pair Extension

extension Pipe {
    /// Create a bidirectional socket pair (like UnixStream::pair in Rust)
    static func socketPair() -> (FileHandle, FileHandle) {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        return (FileHandle(fileDescriptor: fds[0]), FileHandle(fileDescriptor: fds[1]))
    }
}
