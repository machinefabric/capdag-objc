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
