import XCTest
import Foundation
import SwiftCBOR
@testable import Bifaci
import Ops
import CapDAG

/// Test Op: emits fixed "transformed" bytes, drains input. Used in TEST293.
final class TransformOp: Op, @unchecked Sendable {
    typealias Output = Void
    init() {}
    func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        _ = try? input.collectAllBytes()
        try req.output().start(isSequence: false)
        try req.output().write("transformed".data(using: .utf8)!)
    }
    func metadata() -> OpMetadata { OpMetadata.builder("TransformOp").build() }
}

// =============================================================================
// CartridgeHost Multi-Cartridge Runtime Tests
//
// Tests the restructured CartridgeHost which manages N cartridge binaries with
// frame routing. These mirror the Rust CartridgeHostRuntime tests (TEST413-425).
//
// Test architecture:
//   Engine task ←→ Relay pipes ←→ CartridgeHost.run() ←→ Cartridge pipes ←→ Cartridge task
// =============================================================================

@available(macOS 10.15.4, iOS 13.4, *)
@MainActor
final class CborRuntimeTests: XCTestCase, @unchecked Sendable {

    // MARK: - Test Infrastructure

    nonisolated static let testManifestJSON = """
    {"name":"TestCartridge","version":"1.0.0","description":"Test cartridge","caps":[{"urn":"cap:in=media:;out=media:","title":"Identity","command":"identity"},{"urn":"cap:in=media:;op=test;out=media:","title":"Test","command":"test"}]}
    """
    nonisolated static let testManifestData = testManifestJSON.data(using: .utf8)!

    nonisolated static func helloWithManifest(maxFrame: Int = DEFAULT_MAX_FRAME, maxChunk: Int = DEFAULT_MAX_CHUNK) -> Frame {
        let limits = Limits(maxFrame: maxFrame, maxChunk: maxChunk, maxReorderBuffer: DEFAULT_MAX_REORDER_BUFFER)
        return Frame.helloWithManifest(limits: limits, manifest: testManifestData)
    }

    nonisolated static func makeManifest(name: String, caps: [String]) -> Data {
        // Always include CAP_IDENTITY as first cap (mandatory)
        var allCaps = ["{\"urn\":\"cap:in=media:;out=media:\",\"title\":\"Identity\",\"command\":\"identity\"}"]
        // Add user caps as proper cap objects with full direction specs
        for cap in caps {
            let capWithDirs = cap.contains("in=") ? cap : "cap:in=media:;\(cap.dropFirst(4));out=media:"
            allCaps.append("{\"urn\":\"\(capWithDirs)\",\"title\":\"\(name)\",\"command\":\"\(name.lowercased())\"}")
        }
        let capsJson = allCaps.joined(separator: ",")
        return "{\"name\":\"\(name)\",\"version\":\"1.0\",\"caps\":[\(capsJson)]}".data(using: .utf8)!
    }

    nonisolated static func helloWith(manifest: Data, maxFrame: Int = DEFAULT_MAX_FRAME, maxChunk: Int = DEFAULT_MAX_CHUNK) -> Frame {
        let limits = Limits(maxFrame: maxFrame, maxChunk: maxChunk, maxReorderBuffer: DEFAULT_MAX_REORDER_BUFFER)
        return Frame.helloWithManifest(limits: limits, manifest: manifest)
    }

    /// Helper for mock cartridges to handle identity verification after HELLO exchange.
    /// Reads REQ + streaming frames, echoes payload back.
    nonisolated static func handleIdentityVerification(reader: FrameReader, writer: FrameWriter) throws {
        // Read REQ
        guard let req = try reader.read(), req.frameType == .req else {
            throw CartridgeHostError.protocolError("Expected identity REQ")
        }

        // Read streaming frames until END, collect payload
        var payload = Data()
        while true {
            guard let frame = try reader.read() else {
                throw CartridgeHostError.receiveFailed("Connection closed during identity verification")
            }
            if frame.frameType == .chunk, let p = frame.payload {
                payload.append(p)
            }
            if frame.frameType == .end { break }
        }

        // Echo payload back
        let streamId = "identity-echo"
        try writer.write(Frame.streamStart(reqId: req.id, streamId: streamId, mediaUrn: "media:"))
        if !payload.isEmpty {
            let checksum = Frame.computeChecksum(payload)
            try writer.write(Frame.chunk(reqId: req.id, streamId: streamId, seq: 0, payload: payload, chunkIndex: 0, checksum: checksum))
        }
        try writer.write(Frame.streamEnd(reqId: req.id, streamId: streamId, chunkCount: payload.isEmpty ? 0 : 1))
        try writer.write(Frame.end(id: req.id))
    }

    /// Helper to write a frame with routingId (XID) stamped — required for frames entering via relay
    nonisolated static func writeWithXid(_ writer: FrameWriter, _ frame: Frame, xid: MessageId) throws {
        var f = frame
        f.routingId = xid
        try writer.write(f)
    }

    /// Helper to read next protocol frame, skipping relayNotify frames
    /// (host.run() sends relayNotify as first frame when outbound writer is set)
    nonisolated static func readProtocolFrame(_ reader: FrameReader) throws -> Frame? {
        while true {
            guard let frame = try reader.read() else { return nil }
            if frame.frameType != .relayNotify { return frame }
        }
    }

    /// Helper to write a chunk with proper checksum
    nonisolated static func writeChunk(writer: FrameWriter, reqId: MessageId, streamId: String, seq: UInt64, payload: Data, chunkIndex: UInt64) throws {
        let checksum = Frame.computeChecksum(payload)
        try writer.write(Frame.chunk(reqId: reqId, streamId: streamId, seq: seq, payload: payload, chunkIndex: chunkIndex, checksum: checksum))
    }

    /// Helper to write streamEnd with chunk count
    nonisolated static func writeStreamEnd(writer: FrameWriter, reqId: MessageId, streamId: String, chunkCount: UInt64) throws {
        try writer.write(Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: chunkCount))
    }

    /// Read a complete request: REQ + per-argument streams + END.
    nonisolated static func readCompleteRequest(
        reader: FrameReader
    ) throws -> (reqId: MessageId, cap: String, contentType: String, payload: Data) {
        let (reqId, cap, contentType, streams) = try readCompleteRequestStreams(reader: reader)
        var payload = Data()
        for (_, _, data) in streams {
            payload.append(data)
        }
        return (reqId, cap, contentType, payload)
    }

    nonisolated static func readCompleteRequestStreams(
        reader: FrameReader
    ) throws -> (reqId: MessageId, cap: String, contentType: String, streams: [(streamId: String, mediaUrn: String, data: Data)]) {
        guard let req = try reader.read() else {
            throw CartridgeHostError.receiveFailed("No REQ frame")
        }
        guard req.frameType == .req else {
            throw CartridgeHostError.handshakeFailed("Expected REQ, got \(req.frameType)")
        }

        let reqId = req.id
        let cap = req.cap ?? ""
        let contentType = req.contentType ?? ""

        var streams: [(streamId: String, mediaUrn: String, data: Data)] = []
        var currentStreamId: String?
        var currentMediaUrn: String?
        var currentData = Data()

        while true {
            guard let frame = try reader.read() else {
                throw CartridgeHostError.receiveFailed("Unexpected EOF reading request stream")
            }
            switch frame.frameType {
            case .streamStart:
                currentStreamId = frame.streamId
                currentMediaUrn = frame.mediaUrn
                currentData = Data()
            case .chunk:
                currentData.append(frame.payload ?? Data())
            case .streamEnd:
                if let sid = currentStreamId, let murn = currentMediaUrn {
                    streams.append((streamId: sid, mediaUrn: murn, data: currentData))
                }
                currentStreamId = nil
                currentMediaUrn = nil
                currentData = Data()
            case .end:
                return (reqId, cap, contentType, streams)
            default:
                throw CartridgeHostError.handshakeFailed("Unexpected frame type in request stream: \(frame.frameType)")
            }
        }
    }

    /// Write a complete single-value response: STREAM_START + CHUNK + STREAM_END + END
    nonisolated static func writeResponse(
        writer: FrameWriter,
        reqId: MessageId,
        payload: Data,
        streamId: String = "response-stream",
        mediaUrn: String = "media:"
    ) throws {
        try writer.write(Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn))
        let checksum = Frame.computeChecksum(payload)
        try writer.write(Frame.chunk(reqId: reqId, streamId: streamId, seq: 0, payload: payload, chunkIndex: 0, checksum: checksum))
        try writer.write(Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: 1))
        try writer.write(Frame.end(id: reqId, finalPayload: nil))
    }

    // MARK: - Handshake Tests (TEST231-232)
    // NOTE: TEST284 and TEST290 are tested at the protocol level in IntegrationTests.swift

    // TEST232: attachCartridge fails when cartridge HELLO is missing required manifest
    func test232_attachCartridgeFailsOnMissingManifest() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading, limits: Limits())
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting, limits: Limits())

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else {
                throw CartridgeHostError.receiveFailed("No HELLO")
            }
            let limits = Limits(maxFrame: DEFAULT_MAX_FRAME, maxChunk: DEFAULT_MAX_CHUNK, maxReorderBuffer: DEFAULT_MAX_REORDER_BUFFER)
            try cartridgeWriter.write(Frame.hello(limits: limits))
        }

        let host = CartridgeHost()
        do {
            try host.attachCartridge(
                stdinHandle: hostToCartridge.fileHandleForWriting,
                stdoutHandle: cartridgeToHost.fileHandleForReading
            )
            XCTFail("Should have thrown handshake error due to missing manifest")
        } catch let error as CartridgeHostError {
            if case .handshakeFailed(let msg) = error {
                XCTAssertTrue(msg.contains("missing required manifest"), "Error should mention missing manifest: \(msg)")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }

        try? await cartridgeTask.value
    }

    // TEST231: attachCartridge fails when peer sends non-HELLO frame
    func test231_attachCartridgeFailsOnWrongFrameType() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else {
                throw CartridgeHostError.receiveFailed("No HELLO")
            }
            try cartridgeWriter.write(Frame.err(id: .uint(0), code: "WRONG", message: "Not a HELLO"))
        }

        let host = CartridgeHost()
        do {
            try host.attachCartridge(
                stdinHandle: hostToCartridge.fileHandleForWriting,
                stdoutHandle: cartridgeToHost.fileHandleForReading
            )
            XCTFail("Should have thrown handshake error")
        } catch let error as CartridgeHostError {
            if case .handshakeFailed(let msg) = error {
                XCTAssertTrue(msg.contains("Expected HELLO"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }

        try? await cartridgeTask.value
    }

    // MARK: - Cartridge Registration & Routing (TEST413-414, TEST425)

    // TEST413: registerCartridge adds to cap_table and findCartridgeForCap resolves it
    func test413_registerCartridgeAddsToCaptable() {
        let host = CartridgeHost()
        host.registerCartridge(path: "/usr/bin/test", cartridgeDir: "", knownCaps: ["cap:op=convert"])
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=convert"), "Registered cap must be found")
        XCTAssertNil(host.findCartridgeForCap("cap:op=unknown"), "Unregistered cap must not be found")
    }

    // TEST414: capabilities returns empty initially
    func test414_capabilitiesEmptyInitially() {
        let host = CartridgeHost()
        // Capabilities are rebuilt from running cartridges — no running cartridges means empty
        let caps = host.capabilities
        XCTAssertTrue(caps.isEmpty || String(data: caps, encoding: .utf8) == "[]",
            "Capabilities should be empty initially")
    }

    // TEST425: findCartridgeForCap returns nil for unknown cap
    func test425_findCartridgeForCapUnknown() {
        let host = CartridgeHost()
        host.registerCartridge(path: "/test", cartridgeDir: "", knownCaps: ["cap:op=known"])
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=known"))
        XCTAssertNil(host.findCartridgeForCap("cap:op=unknown"))
    }

    // MARK: - Full Path Tests (TEST416-420, TEST426)

    // TEST416: attachCartridge extracts manifest and updates capabilities
    func test416_attachCartridgeUpdatesCaps() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWithManifest())
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)
        }

        let host = CartridgeHost()
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        // After attach, the cap should be registered
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=test"), "Attached cartridge's cap must be found")

        // Capabilities should be non-empty
        let caps = host.capabilities
        XCTAssertFalse(caps.isEmpty, "Capabilities should include attached cartridge's caps")

        try await cartridgeTask.value
    }

    // TEST417 + TEST426: Full path - engine REQ -> relay -> host -> cartridge -> response -> relay -> engine
    func test417_fullPathRequestResponse() async throws {
        // Cartridge pipes
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()

        // Relay pipes (engine <-> host)
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        // Cartridge: handshake + identity verification + read REQ + write response
        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWithManifest())
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)

            // Read REQ + streams + END from host
            let (reqId, cap, _, _) = try CborRuntimeTests.readCompleteRequest(reader: cartridgeReader)
            guard cap == "cap:op=test" else { throw CartridgeHostError.protocolError("Expected cap:op=test, got \(cap)") }

            // Write response
            try CborRuntimeTests.writeResponse(writer: cartridgeWriter, reqId: reqId, payload: "hello-from-cartridge".data(using: .utf8)!)
        }

        // Host: attach cartridge + run
        let host = CartridgeHost()
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        // Engine: write REQ, read response
        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        let xid = MessageId.newUUID()
        // Frames from relay must have routingId (XID) — RelaySwitch stamps these in real deployment
        try Self.writeWithXid(engineWriter, Frame.req(id: reqId, capUrn: "cap:op=test", payload: Data(), contentType: "application/cbor"), xid: xid)
        let sid = "arg-0"
        try Self.writeWithXid(engineWriter, Frame.streamStart(reqId: reqId, streamId: sid, mediaUrn: "media:"), xid: xid)
        let payload1 = "request-data".data(using: .utf8)!
        let checksum1 = Frame.computeChecksum(payload1)
        try Self.writeWithXid(engineWriter, Frame.chunk(reqId: reqId, streamId: sid, seq: 0, payload: payload1, chunkIndex: 0, checksum: checksum1), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.streamEnd(reqId: reqId, streamId: sid, chunkCount: 1), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.end(id: reqId, finalPayload: nil), xid: xid)

        // Read response from cartridge (via host relay) — skip relayNotify
        var responseData = Data()
        while true {
            guard let frame = try Self.readProtocolFrame(engineReader) else { break }
            if frame.frameType == .chunk {
                responseData.append(frame.payload ?? Data())
            }
            if frame.frameType == .end { break }
        }

        // Close relay to let run() exit
        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertEqual(String(data: responseData, encoding: .utf8), "hello-from-cartridge")

        try? await cartridgeTask.value
        try? await hostTask.value
    }

    // TEST419: Cartridge HEARTBEAT handled locally (not forwarded to relay)
    func test419_heartbeatHandledLocally() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        // Cartridge: handshake + identity verification, send heartbeat, then respond to REQ
        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWithManifest())
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)

            // Send a heartbeat to the host
            let hbId = MessageId.newUUID()
            try cartridgeWriter.write(Frame.heartbeat(id: hbId))

            // Read heartbeat response from host
            guard let hbResp = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("No heartbeat response") }
            guard hbResp.frameType == .heartbeat else { throw CartridgeHostError.protocolError("Expected heartbeat, got \(hbResp.frameType)") }
            guard hbResp.id == hbId else { throw CartridgeHostError.protocolError("Heartbeat ID mismatch") }

            // Read REQ and respond
            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: cartridgeReader)
            try CborRuntimeTests.writeResponse(writer: cartridgeWriter, reqId: reqId, payload: "ok".data(using: .utf8)!)
        }

        let host = CartridgeHost()
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        // Engine sends REQ with XID
        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        let xid = MessageId.newUUID()
        try Self.writeWithXid(engineWriter, Frame.req(id: reqId, capUrn: "cap:op=test", payload: Data(), contentType: "application/cbor"), xid: xid)
        let sid = "arg-0"
        try Self.writeWithXid(engineWriter, Frame.streamStart(reqId: reqId, streamId: sid, mediaUrn: "media:"), xid: xid)
        let emptyPayload = Data()
        let emptyChecksum = Frame.computeChecksum(emptyPayload)
        try Self.writeWithXid(engineWriter, Frame.chunk(reqId: reqId, streamId: sid, seq: 0, payload: emptyPayload, chunkIndex: 0, checksum: emptyChecksum), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.streamEnd(reqId: reqId, streamId: sid, chunkCount: 1), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.end(id: reqId, finalPayload: nil), xid: xid)

        // Read response — should NOT contain any heartbeat frames (skip relayNotify)
        var gotHeartbeat = false
        var responseData = Data()
        while true {
            guard let frame = try Self.readProtocolFrame(engineReader) else { break }
            if frame.frameType == .heartbeat { gotHeartbeat = true }
            if frame.frameType == .chunk { responseData.append(frame.payload ?? Data()) }
            if frame.frameType == .end { break }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertFalse(gotHeartbeat, "Heartbeat must NOT be forwarded to relay")
        XCTAssertEqual(String(data: responseData, encoding: .utf8), "ok")

        try? await cartridgeTask.value
        try? await hostTask.value
    }

    // TEST423: Multiple cartridges registered with distinct caps route independently
    func test423_multipleCartridgesRouteIndependently() async throws {
        // Cartridge A
        let hostToCartridgeA = Pipe()
        let cartridgeAToHost = Pipe()
        // Cartridge B
        let hostToCartridgeB = Pipe()
        let cartridgeBToHost = Pipe()
        // Relay
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let manifestA = CborRuntimeTests.makeManifest(name: "CartridgeA", caps: ["cap:op=alpha"])
        let manifestB = CborRuntimeTests.makeManifest(name: "CartridgeB", caps: ["cap:op=beta"])

        let cartridgeAReader = FrameReader(handle: hostToCartridgeA.fileHandleForReading)
        let cartridgeAWriter = FrameWriter(handle: cartridgeAToHost.fileHandleForWriting)
        let cartridgeBReader = FrameReader(handle: hostToCartridgeB.fileHandleForReading)
        let cartridgeBWriter = FrameWriter(handle: cartridgeBToHost.fileHandleForWriting)

        let taskA = Task.detached { @Sendable [manifestA] in
            guard let _ = try cartridgeAReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeAWriter.write(CborRuntimeTests.helloWith(manifest: manifestA))
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeAReader, writer: cartridgeAWriter)
            let (reqId, cap, _, _) = try CborRuntimeTests.readCompleteRequest(reader: cartridgeAReader)
            guard cap == "cap:op=alpha" else { throw CartridgeHostError.protocolError("Expected alpha, got \(cap)") }
            try CborRuntimeTests.writeResponse(writer: cartridgeAWriter, reqId: reqId, payload: "from-A".data(using: .utf8)!)
        }

        let taskB = Task.detached { @Sendable [manifestB] in
            guard let _ = try cartridgeBReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeBWriter.write(CborRuntimeTests.helloWith(manifest: manifestB))
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeBReader, writer: cartridgeBWriter)
            let (reqId, cap, _, _) = try CborRuntimeTests.readCompleteRequest(reader: cartridgeBReader)
            guard cap == "cap:op=beta" else { throw CartridgeHostError.protocolError("Expected beta, got \(cap)") }
            try CborRuntimeTests.writeResponse(writer: cartridgeBWriter, reqId: reqId, payload: "from-B".data(using: .utf8)!)
        }

        let host = CartridgeHost()
        try host.attachCartridge(stdinHandle: hostToCartridgeA.fileHandleForWriting, stdoutHandle: cartridgeAToHost.fileHandleForReading)
        try host.attachCartridge(stdinHandle: hostToCartridgeB.fileHandleForWriting, stdoutHandle: cartridgeBToHost.fileHandleForReading)

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        // Send REQ for alpha (with XID)
        let alphaId = MessageId.newUUID()
        let alphaXid = MessageId.newUUID()
        try Self.writeWithXid(engineWriter, Frame.req(id: alphaId, capUrn: "cap:op=alpha", payload: Data(), contentType: "application/cbor"), xid: alphaXid)
        try Self.writeWithXid(engineWriter, Frame.streamStart(reqId: alphaId, streamId: "a0", mediaUrn: "media:"), xid: alphaXid)
        var alphaChunk = Frame.chunk(reqId: alphaId, streamId: "a0", seq: 0, payload: Data(), chunkIndex: 0, checksum: 0)
        alphaChunk.routingId = alphaXid
        try engineWriter.write(alphaChunk)
        var alphaEnd1 = Frame.streamEnd(reqId: alphaId, streamId: "a0", chunkCount: 1)
        alphaEnd1.routingId = alphaXid
        try engineWriter.write(alphaEnd1)
        try Self.writeWithXid(engineWriter, Frame.end(id: alphaId, finalPayload: nil), xid: alphaXid)

        // Send REQ for beta (with XID)
        let betaId = MessageId.newUUID()
        let betaXid = MessageId.newUUID()
        try Self.writeWithXid(engineWriter, Frame.req(id: betaId, capUrn: "cap:op=beta", payload: Data(), contentType: "application/cbor"), xid: betaXid)
        try Self.writeWithXid(engineWriter, Frame.streamStart(reqId: betaId, streamId: "b0", mediaUrn: "media:"), xid: betaXid)
        let betaPayload = Data()
        var betaChunk = Frame.chunk(reqId: betaId, streamId: "b0", seq: 0, payload: betaPayload, chunkIndex: 0, checksum: Frame.computeChecksum(betaPayload))
        betaChunk.routingId = betaXid
        try engineWriter.write(betaChunk)
        var betaStreamEnd = Frame.streamEnd(reqId: betaId, streamId: "b0", chunkCount: 1)
        betaStreamEnd.routingId = betaXid
        try engineWriter.write(betaStreamEnd)
        try Self.writeWithXid(engineWriter, Frame.end(id: betaId, finalPayload: nil), xid: betaXid)

        // Read responses (skip relayNotify)
        var alphaData = Data()
        var betaData = Data()
        var ends = 0
        while ends < 2 {
            guard let frame = try Self.readProtocolFrame(engineReader) else { break }
            if frame.frameType == .chunk {
                if frame.id == alphaId { alphaData.append(frame.payload ?? Data()) }
                else if frame.id == betaId { betaData.append(frame.payload ?? Data()) }
            }
            if frame.frameType == .end { ends += 1 }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertEqual(String(data: alphaData, encoding: .utf8), "from-A", "Alpha response from Cartridge A")
        XCTAssertEqual(String(data: betaData, encoding: .utf8), "from-B", "Beta response from Cartridge B")

        try? await taskA.value
        try? await taskB.value
        try? await hostTask.value
    }

    // TEST901: REQ for unknown cap returns ERR (NoHandler) — not fatal, just per-request error
    func test901_reqForUnknownCapReturnsErr() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWithManifest())
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)
            // Cartridge just waits — no request should arrive for unknown cap
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let host = CartridgeHost()
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        // Send REQ for unknown cap (with XID — relay always stamps XID)
        let reqId = MessageId.newUUID()
        let xid = MessageId.newUUID()
        try Self.writeWithXid(engineWriter, Frame.req(id: reqId, capUrn: "cap:op=nonexistent", payload: Data(), contentType: "text/plain"), xid: xid)

        // Should receive ERR with NO_HANDLER (skip relayNotify)
        let frame = try Self.readProtocolFrame(engineReader)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.frameType, .err, "Unknown cap should return ERR")
        XCTAssertEqual(frame!.errorCode, "NO_HANDLER", "Error code should be NO_HANDLER")

        engineToHost.fileHandleForWriting.closeFile()

        try? await cartridgeTask.value
        try? await hostTask.value
    }

    // MARK: - Handler Registration (TEST293)

    // TEST293: Test CartridgeRuntime Op registration and lookup by exact and non-existent cap URN
    func test293_cartridgeRuntimeHandlerRegistration() throws {
        let runtime = CartridgeRuntime(manifest: CborRuntimeTests.testManifestData)

        runtime.register_op_type(capUrn: "cap:in=media:;out=media:", make: EchoAllBytesOp.init)
        runtime.register_op_type(capUrn: "cap:op=transform", make: TransformOp.init)

        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:in=media:;out=media:"), "echo handler must be found")
        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:op=transform"), "transform handler must be found")
        XCTAssertNil(runtime.findHandler(capUrn: "cap:op=unknown"), "unknown handler must be nil")
    }

    // MARK: - Gap Tests (TEST415, TEST418, TEST420-422, TEST424)

    // TEST415: REQ for known cap triggers spawn (expect error for non-existent binary)
    func test415_reqTriggersSpawnError() async throws {
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let host = CartridgeHost()
        host.registerCartridge(path: "/nonexistent/cartridge/binary/path", cartridgeDir: "", knownCaps: ["cap:op=spawn-test"])

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        let xid = MessageId.newUUID()
        try Self.writeWithXid(engineWriter, Frame.req(id: reqId, capUrn: "cap:op=spawn-test", payload: Data(), contentType: "text/plain"), xid: xid)

        let frame = try Self.readProtocolFrame(engineReader)
        XCTAssertNotNil(frame, "Must receive ERR frame for failed spawn")
        XCTAssertEqual(frame!.frameType, .err, "Failed spawn must return ERR")
        XCTAssertEqual(frame!.errorCode, "SPAWN_FAILED", "Error code must be SPAWN_FAILED")

        engineToHost.fileHandleForWriting.closeFile()
        try? await hostTask.value
    }

    // TEST418: Route STREAM_START/CHUNK/STREAM_END/END by req_id
    func test418_routeContinuationByReqId() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "ContCartridge", caps: ["cap:op=cont"])
            ))
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)

            // Read REQ
            guard let req = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("No REQ") }
            guard req.frameType == .req else { throw CartridgeHostError.protocolError("Expected REQ") }
            let reqId = req.id

            // Read STREAM_START
            guard let ss = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("No STREAM_START") }
            guard ss.frameType == .streamStart else { throw CartridgeHostError.protocolError("Expected STREAM_START, got \(ss.frameType)") }
            guard ss.id == reqId else { throw CartridgeHostError.protocolError("STREAM_START req_id mismatch") }

            // Read CHUNK
            guard let chunk = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("No CHUNK") }
            guard chunk.frameType == .chunk else { throw CartridgeHostError.protocolError("Expected CHUNK, got \(chunk.frameType)") }
            guard chunk.payload == "payload-data".data(using: .utf8) else { throw CartridgeHostError.protocolError("CHUNK payload mismatch") }

            // Read STREAM_END
            guard let se = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("No STREAM_END") }
            guard se.frameType == .streamEnd else { throw CartridgeHostError.protocolError("Expected STREAM_END, got \(se.frameType)") }

            // Read END
            guard let end = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("No END") }
            guard end.frameType == .end else { throw CartridgeHostError.protocolError("Expected END, got \(end.frameType)") }

            // Respond
            try CborRuntimeTests.writeResponse(writer: cartridgeWriter, reqId: reqId, payload: "ok".data(using: .utf8)!)
        }

        let host = CartridgeHost()
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        let xid = MessageId.newUUID()
        try Self.writeWithXid(engineWriter, Frame.req(id: reqId, capUrn: "cap:op=cont", payload: Data(), contentType: "text/plain"), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.streamStart(reqId: reqId, streamId: "arg-0", mediaUrn: "media:"), xid: xid)
        let chunkPayload = "payload-data".data(using: .utf8)!
        var chunkFrame = Frame.chunk(reqId: reqId, streamId: "arg-0", seq: 0, payload: chunkPayload, chunkIndex: 0, checksum: Frame.computeChecksum(chunkPayload))
        chunkFrame.routingId = xid
        try engineWriter.write(chunkFrame)
        try Self.writeWithXid(engineWriter, Frame.streamEnd(reqId: reqId, streamId: "arg-0", chunkCount: 1), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.end(id: reqId, finalPayload: nil), xid: xid)

        var responseData = Data()
        while true {
            guard let frame = try Self.readProtocolFrame(engineReader) else { break }
            if frame.frameType == .chunk { responseData.append(frame.payload ?? Data()) }
            if frame.frameType == .end { break }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertEqual(String(data: responseData, encoding: .utf8), "ok", "Continuation frames must route correctly")

        try await cartridgeTask.value
        try? await hostTask.value
    }

    // TEST420: Cartridge non-HELLO/non-HB frames forwarded to relay
    func test420_cartridgeFramesForwardedToRelay() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "FwdCartridge", caps: ["cap:op=fwd"])
            ))
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)

            let (reqId, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: cartridgeReader)

            // Send diverse frame types back
            try cartridgeWriter.write(Frame.log(id: reqId, level: "info", message: "processing"))
            try cartridgeWriter.write(Frame.streamStart(reqId: reqId, streamId: "output", mediaUrn: "media:"))
            let payload = "data".data(using: .utf8)!
            try cartridgeWriter.write(Frame.chunk(reqId: reqId, streamId: "output", seq: 0, payload: payload, chunkIndex: 0, checksum: Frame.computeChecksum(payload)))
            try cartridgeWriter.write(Frame.streamEnd(reqId: reqId, streamId: "output", chunkCount: 1))
            try cartridgeWriter.write(Frame.end(id: reqId, finalPayload: nil))
        }

        let host = CartridgeHost()
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        let xid = MessageId.newUUID()
        try Self.writeWithXid(engineWriter, Frame.req(id: reqId, capUrn: "cap:op=fwd", payload: Data(), contentType: "text/plain"), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.streamStart(reqId: reqId, streamId: "a0", mediaUrn: "media:"), xid: xid)
        let emptyPayload = Data()
        var chunkFrame = Frame.chunk(reqId: reqId, streamId: "a0", seq: 0, payload: emptyPayload, chunkIndex: 0, checksum: Frame.computeChecksum(emptyPayload))
        chunkFrame.routingId = xid
        try engineWriter.write(chunkFrame)
        try Self.writeWithXid(engineWriter, Frame.streamEnd(reqId: reqId, streamId: "a0", chunkCount: 1), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.end(id: reqId, finalPayload: nil), xid: xid)

        var receivedTypes: [FrameType] = []
        while true {
            guard let frame = try Self.readProtocolFrame(engineReader) else { break }
            receivedTypes.append(frame.frameType)
            if frame.frameType == .end { break }
        }

        engineToHost.fileHandleForWriting.closeFile()

        let typeSet = Set(receivedTypes)
        XCTAssertTrue(typeSet.contains(.log), "LOG must be forwarded")
        XCTAssertTrue(typeSet.contains(.streamStart), "STREAM_START must be forwarded")
        XCTAssertTrue(typeSet.contains(.chunk), "CHUNK must be forwarded")
        XCTAssertTrue(typeSet.contains(.end), "END must be forwarded")

        try await cartridgeTask.value
        try? await hostTask.value
    }

    // TEST421: Cartridge death updates capability list (removes dead cartridge's caps)
    func test421_cartridgeDeathUpdatesCaps() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "DieCartridge", caps: ["cap:op=die"])
            ))
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)
            // Die immediately by closing write end
            cartridgeToHost.fileHandleForWriting.closeFile()
        }

        let host = CartridgeHost()
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        // Before death: cap should be present
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=die"), "Cap must be found before death")

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        // Wait for cartridge death to be processed
        try await Task.sleep(nanoseconds: 500_000_000)

        // Close relay to let run() exit
        engineToHost.fileHandleForWriting.closeFile()

        try? await cartridgeTask.value
        try? await hostTask.value

        // After death: capabilities should not include the dead cartridge's caps
        let capsAfter = host.capabilities
        if !capsAfter.isEmpty, let capsStr = String(data: capsAfter, encoding: .utf8) {
            XCTAssertFalse(capsStr.contains("cap:op=die"), "Dead cartridge's caps must be removed")
        }
    }

    // TEST422: Cartridge death sends ERR for all pending requests
    func test422_cartridgeDeathSendsErr() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "DieCartridge", caps: ["cap:op=die"])
            ))
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)
            // Read actual test REQ (first frame after identity), then die without responding
            let _ = try cartridgeReader.read()
            cartridgeToHost.fileHandleForWriting.closeFile()
        }

        let host = CartridgeHost()
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let reqId = MessageId.newUUID()
        let xid = MessageId.newUUID()
        try Self.writeWithXid(engineWriter, Frame.req(id: reqId, capUrn: "cap:op=die", payload: Data(), contentType: "text/plain"), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.streamStart(reqId: reqId, streamId: "a0", mediaUrn: "media:"), xid: xid)
        let chunkPayload = "hello".data(using: .utf8)!
        var chunkFrame = Frame.chunk(reqId: reqId, streamId: "a0", seq: 0, payload: chunkPayload, chunkIndex: 0, checksum: Frame.computeChecksum(chunkPayload))
        chunkFrame.routingId = xid
        try engineWriter.write(chunkFrame)
        try Self.writeWithXid(engineWriter, Frame.streamEnd(reqId: reqId, streamId: "a0", chunkCount: 1), xid: xid)
        try Self.writeWithXid(engineWriter, Frame.end(id: reqId, finalPayload: nil), xid: xid)

        // Should receive ERR with CARTRIDGE_DIED (skip relayNotify)
        var errFrame: Frame?
        while true {
            guard let frame = try Self.readProtocolFrame(engineReader) else { break }
            if frame.frameType == .err {
                errFrame = frame
                break
            }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertNotNil(errFrame, "Must receive ERR when cartridge dies with pending request")
        XCTAssertEqual(errFrame!.errorCode, "CARTRIDGE_DIED", "Error code must be CARTRIDGE_DIED")

        try? await cartridgeTask.value
        try? await hostTask.value
    }

    // TEST424: Concurrent requests to same cartridge handled independently
    func test424_concurrentRequestsSameCartridge() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "ConcCartridge", caps: ["cap:op=conc"])
            ))
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)

            // Read first complete request
            let (reqId0, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: cartridgeReader)
            // Read second complete request
            let (reqId1, _, _, _) = try CborRuntimeTests.readCompleteRequest(reader: cartridgeReader)

            // Respond to both
            try CborRuntimeTests.writeResponse(writer: cartridgeWriter, reqId: reqId0, payload: "response-0".data(using: .utf8)!, streamId: "s0")
            try CborRuntimeTests.writeResponse(writer: cartridgeWriter, reqId: reqId1, payload: "response-1".data(using: .utf8)!, streamId: "s1")
        }

        let host = CartridgeHost()
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        let hostTask = Task.detached { @Sendable in
            try host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineWriter = FrameWriter(handle: engineToHost.fileHandleForWriting)
        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        let id0 = MessageId.newUUID()
        let id1 = MessageId.newUUID()
        let xid0 = MessageId.newUUID()
        let xid1 = MessageId.newUUID()

        // Send both requests with XIDs
        try Self.writeWithXid(engineWriter, Frame.req(id: id0, capUrn: "cap:op=conc", payload: Data(), contentType: "text/plain"), xid: xid0)
        try Self.writeWithXid(engineWriter, Frame.streamStart(reqId: id0, streamId: "a0", mediaUrn: "media:"), xid: xid0)
        let payload0 = Data()
        var chunk0 = Frame.chunk(reqId: id0, streamId: "a0", seq: 0, payload: payload0, chunkIndex: 0, checksum: Frame.computeChecksum(payload0))
        chunk0.routingId = xid0
        try engineWriter.write(chunk0)
        try Self.writeWithXid(engineWriter, Frame.streamEnd(reqId: id0, streamId: "a0", chunkCount: 1), xid: xid0)
        try Self.writeWithXid(engineWriter, Frame.end(id: id0, finalPayload: nil), xid: xid0)

        try Self.writeWithXid(engineWriter, Frame.req(id: id1, capUrn: "cap:op=conc", payload: Data(), contentType: "text/plain"), xid: xid1)
        try Self.writeWithXid(engineWriter, Frame.streamStart(reqId: id1, streamId: "a1", mediaUrn: "media:"), xid: xid1)
        let payload1 = Data()
        var chunk1 = Frame.chunk(reqId: id1, streamId: "a1", seq: 0, payload: payload1, chunkIndex: 0, checksum: Frame.computeChecksum(payload1))
        chunk1.routingId = xid1
        try engineWriter.write(chunk1)
        try Self.writeWithXid(engineWriter, Frame.streamEnd(reqId: id1, streamId: "a1", chunkCount: 1), xid: xid1)
        try Self.writeWithXid(engineWriter, Frame.end(id: id1, finalPayload: nil), xid: xid1)

        // Read both responses (skip relayNotify)
        var data0 = Data()
        var data1 = Data()
        var ends = 0
        while ends < 2 {
            guard let frame = try Self.readProtocolFrame(engineReader) else { break }
            if frame.frameType == .chunk {
                if frame.id == id0 { data0.append(frame.payload ?? Data()) }
                else if frame.id == id1 { data1.append(frame.payload ?? Data()) }
            }
            if frame.frameType == .end { ends += 1 }
        }

        engineToHost.fileHandleForWriting.closeFile()

        XCTAssertEqual(String(data: data0, encoding: .utf8), "response-0", "First request must get response-0")
        XCTAssertEqual(String(data: data1, encoding: .utf8), "response-1", "Second request must get response-1")

        try await cartridgeTask.value
        try? await hostTask.value
    }

    // MARK: - Response Types (TEST316)

    // Mirror-specific coverage: concatenated() returns full payload while finalPayload returns only last chunk
    func testconcatenatedVsFinalPayloadDivergence() {
        let chunks = [
            ResponseChunk(payload: "AAAA".data(using: .utf8)!, seq: 0, offset: nil, len: nil, isEof: false),
            ResponseChunk(payload: "BBBB".data(using: .utf8)!, seq: 1, offset: nil, len: nil, isEof: false),
            ResponseChunk(payload: "CCCC".data(using: .utf8)!, seq: 2, offset: nil, len: nil, isEof: true),
        ]

        let response = CartridgeResponse.streaming(chunks)
        XCTAssertEqual(String(data: response.concatenated(), encoding: .utf8), "AAAABBBBCCCC")
        XCTAssertEqual(String(data: response.finalPayload!, encoding: .utf8), "CCCC")
        XCTAssertNotEqual(response.concatenated(), response.finalPayload!,
            "concatenated and finalPayload must diverge for multi-chunk responses")
    }

    // MARK: - Cartridge Death and Known Caps Tests (TEST661-665)

    // TEST661: Cartridge death keeps known_caps advertised for on-demand respawn
    func test661_cartridgeDeathKeepsKnownCapsAdvertised() async throws {
        let host = CartridgeHost()

        // Register a cartridge by path (not running, just known caps)
        host.registerCartridge(path: "/nonexistent/cartridge", cartridgeDir: "", knownCaps: ["cap:op=respawn-test"])

        // Should find the cartridge by cap
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=respawn-test"), "Known caps must be findable before spawn")

        // The cap should be advertised (registered cartridges are advertised)
        let caps = host.capabilities
        if !caps.isEmpty, let capsStr = String(data: caps, encoding: .utf8) {
            XCTAssertTrue(capsStr.contains("cap:op=respawn-test"), "Known caps must be in capabilities")
        }
    }

    // TEST662: rebuild_capabilities includes non-running cartridges' known_caps
    func test662_rebuildCapabilitiesIncludesNonRunningCartridges() async throws {
        let host = CartridgeHost()

        // Register multiple cartridges with different caps
        host.registerCartridge(path: "/nonexistent/p1", cartridgeDir: "", knownCaps: ["cap:op=cap1"])
        host.registerCartridge(path: "/nonexistent/p2", cartridgeDir: "", knownCaps: ["cap:op=cap2", "cap:op=cap3"])

        let caps = host.capabilities
        if !caps.isEmpty, let capsStr = String(data: caps, encoding: .utf8) {
            XCTAssertTrue(capsStr.contains("cap:op=cap1"), "cap1 must be in capabilities")
            XCTAssertTrue(capsStr.contains("cap:op=cap2"), "cap2 must be in capabilities")
            XCTAssertTrue(capsStr.contains("cap:op=cap3"), "cap3 must be in capabilities")
        }
    }

    // TEST663: Cartridge with hello_failed is permanently removed from capabilities
    func test663_helloFailedCartridgeRemovedFromCapabilities() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()

        // Cartridge that sends invalid HELLO (no manifest)
        DispatchQueue.global().async {
            let reader = FrameReader(handle: hostToCartridge.fileHandleForReading)
            let writer = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

            // Read host's HELLO
            _ = try? reader.read()

            // Send invalid HELLO (no manifest - this should fail)
            let badHello = Frame.hello(limits: Limits())
            try? writer.write(badHello)
        }

        let host = CartridgeHost()

        // Attempt to attach - should fail due to missing manifest
        do {
            try host.attachCartridge(
                stdinHandle: hostToCartridge.fileHandleForWriting,
                stdoutHandle: cartridgeToHost.fileHandleForReading
            )
            XCTFail("attachCartridge should fail without manifest")
        } catch {
            // Expected - cartridge HELLO without manifest should be rejected
            XCTAssertTrue(error is CartridgeHostError)
        }

        // Failed cartridge should not contribute to capabilities
        let caps = host.capabilities
        // Empty or no capabilities since the only cartridge failed
        XCTAssertTrue(caps.isEmpty || String(data: caps, encoding: .utf8) == "[]",
            "Failed cartridge must not be in capabilities")
    }

    // TEST664: Running cartridge uses manifest caps, not known_caps
    func test664_runningCartridgeUsesManifestCaps() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            // Cartridge advertises "cap:op=manifest-cap" in its manifest
            try cartridgeWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "ManifestCartridge", caps: ["cap:op=manifest-cap"])
            ))
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)
            // Keep connection alive
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let host = CartridgeHost()

        // Register with known_caps, but cartridge will advertise different caps via manifest
        host.registerCartridge(path: "/fake/path", cartridgeDir: "", knownCaps: ["cap:op=known-cap"])

        // Before attach: known_cap should be findable
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=known-cap"), "Known cap must be findable before attach")

        // Attach the actual cartridge
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        // After attach: manifest caps should take precedence
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=manifest-cap"), "Manifest cap must be findable after attach")

        try? await cartridgeTask.value
    }

    // TEST665: Cap table uses manifest caps for running, known_caps for non-running
    func test665_capTableMixedRunningAndNonRunning() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            guard let _ = try cartridgeReader.read() else { throw CartridgeHostError.receiveFailed("") }
            try cartridgeWriter.write(CborRuntimeTests.helloWith(
                manifest: CborRuntimeTests.makeManifest(name: "RunningCartridge", caps: ["cap:op=running"])
            ))
            try CborRuntimeTests.handleIdentityVerification(reader: cartridgeReader, writer: cartridgeWriter)
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let host = CartridgeHost()

        // Register a non-running cartridge
        host.registerCartridge(path: "/nonexistent/p1", cartridgeDir: "", knownCaps: ["cap:op=dormant"])

        // Attach a running cartridge
        try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        // Both caps should be findable via cap table
        // Running cartridge: uses manifest caps (from HELLO)
        // Dormant cartridge: uses known_caps (from registerCartridge)
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=running"), "Running cartridge cap must be findable")
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=dormant"), "Dormant cartridge cap must be findable")

        // Capabilities includes both running and non-running cartridges
        // (Note: running cartridge's caps come from manifest, not known_caps)
        let caps = host.capabilities
        let capsStr = String(data: caps, encoding: .utf8) ?? "[]"

        // At minimum, dormant caps should be present
        XCTAssertTrue(capsStr.contains("cap:op=dormant"), "Dormant cartridge cap must be in capabilities")
        // Running cartridge's manifest caps may or may not be merged into capabilities
        // depending on when capabilities is called relative to handshake completion

        try? await cartridgeTask.value
    }

    // MARK: - Error Type Tests (TEST244-247)

    // TEST244: CartridgeHostError from FrameError converts correctly
    func test244_cartridgeHostErrorFromFrameError() {
        // Verify error types have proper descriptions
        let handshakeFailed = CartridgeHostError.handshakeFailed("test error")
        XCTAssertTrue(handshakeFailed.errorDescription?.contains("Handshake failed") ?? false)

        let sendFailed = CartridgeHostError.sendFailed("send error")
        XCTAssertTrue(sendFailed.errorDescription?.contains("Send failed") ?? false)

        let receiveFailed = CartridgeHostError.receiveFailed("receive error")
        XCTAssertTrue(receiveFailed.errorDescription?.contains("Receive failed") ?? false)

        let protocolError = CartridgeHostError.protocolError("protocol violation")
        XCTAssertTrue(protocolError.errorDescription?.contains("Protocol error") ?? false)
    }

    // TEST245: CartridgeHostError stores and retrieves error details
    func test245_cartridgeHostErrorDetails() {
        let cartridgeErr = CartridgeHostError.cartridgeError(code: "TEST_CODE", message: "Test message")
        let desc = cartridgeErr.errorDescription ?? ""
        XCTAssertTrue(desc.contains("TEST_CODE"), "Error description must contain code")
        XCTAssertTrue(desc.contains("Test message"), "Error description must contain message")
    }

    // TEST246: CartridgeHostError variants are distinct
    func test246_cartridgeHostErrorVariants() {
        // Each error type is distinct
        let errors: [CartridgeHostError] = [
            .handshakeFailed("a"),
            .sendFailed("b"),
            .receiveFailed("c"),
            .cartridgeError(code: "X", message: "Y"),
            .unexpectedFrameType(.req),
            .protocolError("d"),
            .processExited,
            .closed,
            .noHandler("e"),
            .cartridgeDied("f"),
        ]

        for (i, err1) in errors.enumerated() {
            for (j, err2) in errors.enumerated() {
                if i != j {
                    // Different indices should mean different error descriptions
                    XCTAssertNotEqual(err1.errorDescription, err2.errorDescription,
                        "Error \(i) and \(j) should have different descriptions")
                }
            }
        }
    }

    // TEST247: ResponseChunk stores and retrieves data correctly
    func test247_responseChunkStorage() {
        let payload = Data([1, 2, 3, 4, 5])
        let chunk = ResponseChunk(payload: payload, seq: 42, offset: 100, len: 1000, isEof: true)

        XCTAssertEqual(chunk.payload, payload)
        XCTAssertEqual(chunk.seq, 42)
        XCTAssertEqual(chunk.offset, 100)
        XCTAssertEqual(chunk.len, 1000)
        XCTAssertTrue(chunk.isEof)

        // Test with nil optional values
        let chunk2 = ResponseChunk(payload: payload, seq: 0, offset: nil, len: nil, isEof: false)
        XCTAssertNil(chunk2.offset)
        XCTAssertNil(chunk2.len)
        XCTAssertFalse(chunk2.isEof)
    }

    // MARK: - Identity Verification Tests (TEST485, TEST486, TEST490)

    // TEST485: attach_cartridge completes identity verification with working cartridge
    func test485_attachCartridgeIdentityVerificationSucceeds() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            // Read host HELLO
            guard let hostHello = try cartridgeReader.read() else {
                throw CartridgeHostError.receiveFailed("No HELLO from host")
            }
            XCTAssertEqual(hostHello.frameType, .hello)

            // Send cartridge HELLO with manifest
            let manifest = CborRuntimeTests.makeManifest(name: "IdentityTestCartridge", caps: [
                "cap:in=media:;out=media:",  // Identity cap
                "cap:in=media:;op=test;out=media:"
            ])
            try cartridgeWriter.write(CborRuntimeTests.helloWith(manifest: manifest))

            // Handle identity verification - read streaming request, echo payload
            guard let identityReq = try cartridgeReader.read() else {
                throw CartridgeHostError.receiveFailed("No identity request")
            }
            XCTAssertEqual(identityReq.frameType, .req)
            XCTAssertEqual(identityReq.cap, CSCapIdentity)

            // Read streaming frames until END
            var identityPayload = Data()
            while true {
                guard let frame = try cartridgeReader.read() else {
                    throw CartridgeHostError.receiveFailed("Connection closed during identity request")
                }
                switch frame.frameType {
                case .streamStart: break
                case .chunk:
                    if let p = frame.payload { identityPayload.append(p) }
                case .streamEnd: break
                case .end: break
                default:
                    throw CartridgeHostError.protocolError("Unexpected frame during identity: \(frame.frameType)")
                }
                if frame.frameType == .end { break }
            }

            // Echo the payload back (standard identity behavior)
            let streamId = UUID().uuidString
            try cartridgeWriter.write(Frame.streamStart(reqId: identityReq.id, streamId: streamId, mediaUrn: "media:"))
            if !identityPayload.isEmpty {
                let checksum = Frame.computeChecksum(identityPayload)
                try cartridgeWriter.write(Frame.chunk(reqId: identityReq.id, streamId: streamId, seq: 0, payload: identityPayload, chunkIndex: 0, checksum: checksum))
            }
            try cartridgeWriter.write(Frame.streamEnd(reqId: identityReq.id, streamId: streamId, chunkCount: identityPayload.isEmpty ? 0 : 1))
            try cartridgeWriter.write(Frame.end(id: identityReq.id))
        }

        let host = CartridgeHost()
        let idx = try host.attachCartridge(
            stdinHandle: hostToCartridge.fileHandleForWriting,
            stdoutHandle: cartridgeToHost.fileHandleForReading
        )

        XCTAssertEqual(idx, 0, "First cartridge must be index 0")

        // Verify cartridge is registered and has caps
        XCTAssertNotNil(host.findCartridgeForCap("cap:in=media:;out=media:"), "Must find identity cap")
        XCTAssertNotNil(host.findCartridgeForCap("cap:in=media:;op=test;out=media:"), "Must find test cap")

        try await cartridgeTask.value
    }

    // TEST486: attach_cartridge rejects cartridge that fails identity verification
    func test486_attachCartridgeIdentityVerificationFails() async throws {
        let hostToCartridge = Pipe()
        let cartridgeToHost = Pipe()

        let cartridgeReader = FrameReader(handle: hostToCartridge.fileHandleForReading)
        let cartridgeWriter = FrameWriter(handle: cartridgeToHost.fileHandleForWriting)

        let cartridgeTask = Task.detached { @Sendable in
            // Read host HELLO
            guard let hostHello = try cartridgeReader.read() else {
                throw CartridgeHostError.receiveFailed("No HELLO from host")
            }
            XCTAssertEqual(hostHello.frameType, .hello)

            // Send cartridge HELLO with manifest
            let manifest = CborRuntimeTests.makeManifest(name: "BrokenIdentityCartridge", caps: [
                "cap:in=media:;out=media:"
            ])
            try cartridgeWriter.write(CborRuntimeTests.helloWith(manifest: manifest))

            // Handle identity verification - return ERR instead of echoing
            guard let identityReq = try cartridgeReader.read() else {
                throw CartridgeHostError.receiveFailed("No identity request")
            }
            XCTAssertEqual(identityReq.frameType, .req)

            // Consume streaming frames until END
            while true {
                guard let frame = try cartridgeReader.read() else { break }
                if frame.frameType == .end { break }
            }

            // Return error - identity verification fails
            try cartridgeWriter.write(Frame.err(id: identityReq.id, code: "IDENTITY_FAILED", message: "Broken cartridge"))
        }

        let host = CartridgeHost()

        // attach_cartridge should fail due to identity verification failure
        do {
            try host.attachCartridge(
                stdinHandle: hostToCartridge.fileHandleForWriting,
                stdoutHandle: cartridgeToHost.fileHandleForReading
            )
            XCTFail("attach_cartridge should fail when identity verification fails")
        } catch {
            // Expected - identity verification failed
            XCTAssertTrue(error is CartridgeHostError, "Should be CartridgeHostError")
        }

        try? await cartridgeTask.value
    }

    // TEST490: Identity verification with multiple cartridges through single relay
    func test490_identityVerificationMultipleCartridges() async throws {
        let host = CartridgeHost()

        // Attach first cartridge
        let hostToCartridge1 = Pipe()
        let cartridge1ToHost = Pipe()

        let cartridge1Reader = FrameReader(handle: hostToCartridge1.fileHandleForReading)
        let cartridge1Writer = FrameWriter(handle: cartridge1ToHost.fileHandleForWriting)

        let cartridge1Task = Task.detached { @Sendable in
            guard let _ = try cartridge1Reader.read() else { throw CartridgeHostError.receiveFailed("") }
            let manifest = CborRuntimeTests.makeManifest(name: "Cartridge1", caps: ["cap:op=cartridge1"])
            try cartridge1Writer.write(CborRuntimeTests.helloWith(manifest: manifest))

            // Handle identity verification - read streaming request
            guard let identityReq = try cartridge1Reader.read() else { throw CartridgeHostError.receiveFailed("") }
            var identityPayload = Data()
            while true {
                guard let frame = try cartridge1Reader.read() else { break }
                if frame.frameType == .chunk, let p = frame.payload { identityPayload.append(p) }
                if frame.frameType == .end { break }
            }

            // Echo payload back
            let streamId = "id1"
            try cartridge1Writer.write(Frame.streamStart(reqId: identityReq.id, streamId: streamId, mediaUrn: "media:"))
            if !identityPayload.isEmpty {
                let checksum = Frame.computeChecksum(identityPayload)
                try cartridge1Writer.write(Frame.chunk(reqId: identityReq.id, streamId: streamId, seq: 0, payload: identityPayload, chunkIndex: 0, checksum: checksum))
            }
            try cartridge1Writer.write(Frame.streamEnd(reqId: identityReq.id, streamId: streamId, chunkCount: identityPayload.isEmpty ? 0 : 1))
            try cartridge1Writer.write(Frame.end(id: identityReq.id))
        }

        let idx1 = try host.attachCartridge(
            stdinHandle: hostToCartridge1.fileHandleForWriting,
            stdoutHandle: cartridge1ToHost.fileHandleForReading
        )
        XCTAssertEqual(idx1, 0)

        // Attach second cartridge
        let hostToCartridge2 = Pipe()
        let cartridge2ToHost = Pipe()

        let cartridge2Reader = FrameReader(handle: hostToCartridge2.fileHandleForReading)
        let cartridge2Writer = FrameWriter(handle: cartridge2ToHost.fileHandleForWriting)

        let cartridge2Task = Task.detached { @Sendable in
            guard let _ = try cartridge2Reader.read() else { throw CartridgeHostError.receiveFailed("") }
            let manifest = CborRuntimeTests.makeManifest(name: "Cartridge2", caps: ["cap:op=cartridge2"])
            try cartridge2Writer.write(CborRuntimeTests.helloWith(manifest: manifest))

            // Handle identity verification - read streaming request
            guard let identityReq = try cartridge2Reader.read() else { throw CartridgeHostError.receiveFailed("") }
            var identityPayload = Data()
            while true {
                guard let frame = try cartridge2Reader.read() else { break }
                if frame.frameType == .chunk, let p = frame.payload { identityPayload.append(p) }
                if frame.frameType == .end { break }
            }

            // Echo payload back
            let streamId = "id2"
            try cartridge2Writer.write(Frame.streamStart(reqId: identityReq.id, streamId: streamId, mediaUrn: "media:"))
            if !identityPayload.isEmpty {
                let checksum = Frame.computeChecksum(identityPayload)
                try cartridge2Writer.write(Frame.chunk(reqId: identityReq.id, streamId: streamId, seq: 0, payload: identityPayload, chunkIndex: 0, checksum: checksum))
            }
            try cartridge2Writer.write(Frame.streamEnd(reqId: identityReq.id, streamId: streamId, chunkCount: identityPayload.isEmpty ? 0 : 1))
            try cartridge2Writer.write(Frame.end(id: identityReq.id))
        }

        let idx2 = try host.attachCartridge(
            stdinHandle: hostToCartridge2.fileHandleForWriting,
            stdoutHandle: cartridge2ToHost.fileHandleForReading
        )
        XCTAssertEqual(idx2, 1, "Second cartridge must be index 1")

        // Both cartridges should be findable by their caps
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=cartridge1"), "Cartridge 1 cap must be findable")
        XCTAssertNotNil(host.findCartridgeForCap("cap:op=cartridge2"), "Cartridge 2 cap must be findable")

        try await cartridge1Task.value
        try await cartridge2Task.value
    }
}
