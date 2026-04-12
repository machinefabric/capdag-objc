//
//  InProcessCartridgeHost.swift
//  In-Process Cartridge Host — Direct dispatch to FrameHandler protocols
//
//  Sits where CartridgeHost sits (connected to RelaySlave via local socket pair),
//  but routes requests to `FrameHandler` protocol conformers instead of cartridge binaries.
//
//  ## Architecture
//
//  RelaySlave ←→ InProcessCartridgeHost ←→ Handler A (streaming frames)
//                                    ←→ Handler B (streaming frames)
//                                    ←→ Handler C (streaming frames)
//
//  ## Design
//
//  The host does NOT accumulate data. On REQ, it spawns a handler with
//  channels for frame I/O. All continuation frames (STREAM_START, CHUNK, STREAM_END,
//  END) are forwarded to the handler. The handler processes frames natively —
//  streaming or accumulating as it sees fit.
//
//  This matches how real cartridges work: CartridgeRuntime forwards frames to handlers,
//  and each handler decides how to consume/produce data.

import Foundation
import CapDAG
import SwiftCBOR

// MARK: - FrameHandler Protocol

/// Handler for streaming frame-based requests.
///
/// Handlers receive input frames (STREAM_START, CHUNK, STREAM_END, END) via a
/// channel and send response frames via a ResponseWriter. The host never
/// accumulates — handlers decide how to process input (stream or accumulate).
///
/// For handlers that don't need streaming, use `accumulateInput()` to collect
/// all input streams into `[CapArgumentValue]`.
public protocol FrameHandler: Sendable {
    /// Handle a streaming request.
    ///
    /// Called in a dedicated thread for each incoming request. The handler reads
    /// input frames from `inputStream` and sends response frames via `output`.
    ///
    /// The REQ frame has already been consumed by the host. `inputStream` receives:
    /// STREAM_START, CHUNK, STREAM_END (per argument stream), then END.
    ///
    /// The handler MUST send a complete response: either response frames
    /// (STREAM_START + CHUNK(s) + STREAM_END + END) or an error (via `output.emitError()`).
    func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) async
}

// MARK: - ResponseWriter

/// Wraps an output channel with automatic request_id and routing_id stamping.
///
/// All frames sent via ResponseWriter get the correct request_id and routing_id
/// for relay routing. Seq is left at 0 — the wire writer's SeqAssigner handles it.
public final class ResponseWriter: @unchecked Sendable {
    private let requestId: MessageId
    private let routingId: MessageId?
    private let sendFrame: @Sendable (Frame) -> Void
    private let maxChunkSize: Int

    init(requestId: MessageId, routingId: MessageId?, sendFrame: @escaping @Sendable (Frame) -> Void, maxChunk: Int) {
        self.requestId = requestId
        self.routingId = routingId
        self.sendFrame = sendFrame
        self.maxChunkSize = maxChunk
    }

    /// Send a frame, stamping it with the request_id and routing_id.
    public func send(_ frame: Frame) {
        var stamped = frame
        stamped.id = requestId
        stamped.routingId = routingId
        stamped.seq = 0 // SeqAssigner handles this
        sendFrame(stamped)
    }

    /// Max chunk size for this connection.
    public func maxChunk() -> Int {
        return maxChunkSize
    }

    /// Send a complete data response: STREAM_START + CBOR-encoded CHUNK(s) + STREAM_END + END.
    public func emitResponse(mediaUrn: String, data: Data) {
        let streamId = "result"

        send(Frame.streamStart(reqId: MessageId.uint(0), streamId: streamId, mediaUrn: mediaUrn, isSequence: false))

        if data.isEmpty {
            // Empty data: single chunk with CBOR-encoded empty bytes
            let cborPayload = Data(CBOR.byteString([UInt8](Data())).encode())
            let checksum = Frame.computeChecksum(cborPayload)
            send(Frame.chunk(reqId: MessageId.uint(0), streamId: streamId, seq: 0, payload: cborPayload, chunkIndex: 0, checksum: checksum))
            send(Frame.streamEnd(reqId: MessageId.uint(0), streamId: streamId, chunkCount: 1))
        } else {
            let chunks = stride(from: 0, to: data.count, by: maxChunkSize).map {
                data[$0..<min($0 + maxChunkSize, data.count)]
            }
            let chunkCount = UInt64(chunks.count)

            for (index, chunkData) in chunks.enumerated() {
                let cborPayload = Data(CBOR.byteString([UInt8](chunkData)).encode())
                let checksum = Frame.computeChecksum(cborPayload)
                send(Frame.chunk(reqId: MessageId.uint(0), streamId: streamId, seq: 0, payload: cborPayload, chunkIndex: UInt64(index), checksum: checksum))
            }
            send(Frame.streamEnd(reqId: MessageId.uint(0), streamId: streamId, chunkCount: chunkCount))
        }

        send(Frame.endOk(id: MessageId.uint(0)))
    }

    /// Send a list response: STREAM_START + one CHUNK per item + STREAM_END + END.
    ///
    /// Each item is CBOR-encoded and sent as a raw chunk payload (matching
    /// `OutputStream.emitListItem` semantics). The receiver concatenates
    /// payloads to produce an RFC 8742 CBOR sequence — one self-delimiting
    /// CBOR value per item.
    ///
    /// This differs from `emitResponse`, which wraps each chunk in `Bytes()`.
    /// `emitListResponse` is for list-typed cap outputs where the executor's
    /// list path expects a CBOR sequence without transport wrapping.
    public func emitListResponse(mediaUrn: String, items: [CBOR]) {
        emitListResponseWithMetas(mediaUrn: mediaUrn, items: items, itemMetas: [])
    }

    /// Emit a sequence response with optional per-item metadata.
    /// Each entry in `itemMetas` corresponds to the item at the same index.
    /// If `itemMetas` is shorter than `items`, remaining items get no meta.
    public func emitListResponseWithMetas(mediaUrn: String, items: [CBOR], itemMetas: [[String: CBOR]?]) {
        let streamId = "result"

        send(Frame.streamStart(reqId: MessageId.uint(0), streamId: streamId, mediaUrn: mediaUrn, isSequence: true))

        for (index, item) in items.enumerated() {
            let cborPayload = Data(item.encode())
            let checksum = Frame.computeChecksum(cborPayload)
            var chunk = Frame.chunk(reqId: MessageId.uint(0), streamId: streamId, seq: 0, payload: cborPayload, chunkIndex: UInt64(index), checksum: checksum)
            if index < itemMetas.count, let meta = itemMetas[index] {
                chunk.meta = meta
            }
            send(chunk)
        }

        send(Frame.streamEnd(reqId: MessageId.uint(0), streamId: streamId, chunkCount: UInt64(items.count)))
        send(Frame.endOk(id: MessageId.uint(0)))
    }

    /// Send an error response.
    public func emitError(code: String, message: String) {
        send(Frame.err(id: MessageId.uint(0), code: code, message: message))
    }
}

// MARK: - Input Accumulation Utility

/// Accumulate all input streams from a frame channel into CapArgumentValues.
///
/// Reads frames until END. CBOR-decodes chunk payloads to extract raw bytes.
/// For handlers that don't need streaming — they accumulate all input, process,
/// then emit a response.
///
/// Returns error on CBOR decode failure (protocol violation).
public func accumulateInput(inputStream: AsyncStream<Frame>) async throws -> [CapArgumentValue] {
    var streams: [(streamId: String, mediaUrn: String, data: Data)] = []
    var active: [String: Int] = [:]

    for await frame in inputStream {
        switch frame.frameType {
        case .streamStart:
            let sid = frame.streamId ?? ""
            let mediaUrn = frame.mediaUrn ?? ""
            let idx = streams.count
            streams.append((sid, mediaUrn, Data()))
            active[sid] = idx

        case .chunk:
            let sid = frame.streamId ?? ""
            if let idx = active[sid], let payload = frame.payload {
                // CBOR-decode chunk payload to extract raw bytes
                guard let cbor = try? CBOR.decode([UInt8](payload)) else {
                    throw NSError(domain: "accumulateInput", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "chunk payload is not valid CBOR (stream=\(sid), \(payload.count) bytes)"
                    ])
                }

                switch cbor {
                case .byteString(let bytes):
                    streams[idx].data.append(contentsOf: bytes)
                case .utf8String(let str):
                    streams[idx].data.append(contentsOf: str.data(using: String.Encoding.utf8) ?? Data())
                default:
                    throw NSError(domain: "accumulateInput", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "unexpected CBOR type in chunk payload: \(cbor)"
                    ])
                }
            }

        case .streamEnd:
            break // nothing to do

        case .end:
            return streams.map { CapArgumentValue(mediaUrn: $0.mediaUrn, value: $0.data) }

        default:
            break // ignore unexpected frame types
        }
    }

    // If we exit the loop without seeing END, return what we have
    return streams.map { CapArgumentValue(mediaUrn: $0.mediaUrn, value: $0.data) }
}

// MARK: - Built-in Identity Handler

/// Identity handler: raw byte passthrough (no CBOR decode/encode).
///
/// Echoes all accumulated chunk payloads back as-is. This is the protocol-level
/// identity verification — it proves the transport works end-to-end.
final class IdentityHandler: FrameHandler {
    func handleRequest(capUrn: String, inputStream: AsyncStream<Frame>, output: ResponseWriter) async {
        // Accumulate raw payload bytes (no CBOR decode — identity is raw passthrough)
        var data = Data()
        for await frame in inputStream {
            switch frame.frameType {
            case .chunk:
                if let payload = frame.payload {
                    data.append(payload)
                }
            case .end:
                // Echo back as a single stream (raw bytes, no CBOR encode)
                let streamId = "identity"
                output.send(Frame.streamStart(reqId: MessageId.uint(0), streamId: streamId, mediaUrn: "media:", isSequence: false))

                let checksum = Frame.computeChecksum(data)
                output.send(Frame.chunk(reqId: MessageId.uint(0), streamId: streamId, seq: 0, payload: data, chunkIndex: 0, checksum: checksum))

                output.send(Frame.streamEnd(reqId: MessageId.uint(0), streamId: streamId, chunkCount: 1))
                output.send(Frame.endOk(id: MessageId.uint(0)))
                return

            default:
                break // STREAM_START, STREAM_END — skip
            }
        }
    }
}

// MARK: - In-Process Cartridge Host

/// Entry for a registered in-process handler.
struct HandlerEntry {
    let name: String
    let caps: [CSCap]
    let handler: FrameHandler
}

private struct RelayNotifyCapabilitiesPayload: Codable {
    let caps: [String]
    let installedCartridges: [InstalledCartridgeIdentity]

    enum CodingKeys: String, CodingKey {
        case caps
        case installedCartridges = "installed_cartridges"
    }
}

/// Cap table entry: (cap_urn_string, handler_index).
typealias CapTable = [(String, Int)]

/// A cartridge host that dispatches to in-process FrameHandler implementations.
///
/// Speaks the Frame protocol to a RelaySlave, but routes requests to
/// `FrameHandler` protocol conformers via frame channels — no accumulation
/// at the host level, handlers own the streaming.
public final class InProcessCartridgeHost {
    private let handlers: [HandlerEntry]

    /// Create a new in-process cartridge host with the given handlers.
    ///
    /// Each handler is a tuple of (name, caps, handler).
    public init(handlers: [(name: String, caps: [CSCap], handler: FrameHandler)]) {
        self.handlers = handlers.map { HandlerEntry(name: $0.name, caps: $0.caps, handler: $0.handler) }
    }

    /// Build the aggregate RelayNotify payload.
    /// Always includes CAP_IDENTITY as the first cap entry.
    internal func buildManifest() -> Data {
        var capUrns: [String] = [CSCapIdentity]
        for entry in handlers {
            for cap in entry.caps {
                let urn = cap.capUrn.toString()
                if urn != CSCapIdentity {
                    capUrns.append(urn)
                }
            }
        }
        let payload = RelayNotifyCapabilitiesPayload(
            caps: capUrns,
            installedCartridges: []
        )
        return try! JSONEncoder().encode(payload)
    }

    /// Build the cap table for routing: flat list of (cap_urn, handler_idx).
    private static func buildCapTable(handlers: [HandlerEntry]) -> CapTable {
        var table: CapTable = []
        for (idx, entry) in handlers.enumerated() {
            for cap in entry.caps {
                table.append((cap.capUrn.toString(), idx))
            }
        }
        return table
    }

    /// Find the best handler for a cap URN.
    ///
    /// Uses `isDispatchable(provider, request)` to find handlers that can
    /// legally handle the request, then ranks by specificity.
    ///
    /// Ranking prefers:
    /// 1. Equivalent matches (distance 0)
    /// 2. More specific providers (positive distance) - refinements
    /// 3. More generic providers (negative distance) - fallbacks
    private static func findHandlerForCap(capTable: CapTable, capUrn: String) -> Int? {
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else {
            return nil
        }

        let requestSpecificity = Int(requestUrn.specificity())
        var matches: [(handlerIdx: Int, signedDistance: Int)] = []

        for (registeredCap, handlerIdx) in capTable {
            if let registeredUrn = try? CSCapUrn.fromString(registeredCap) {
                if registeredUrn.isDispatchable(requestUrn) {
                    let specificity = Int(registeredUrn.specificity())
                    let signedDistance = specificity - requestSpecificity
                    matches.append((handlerIdx, signedDistance))
                }
            }
        }

        guard !matches.isEmpty else {
            return nil
        }

        // Ranking: prefer equivalent (0), then more specific (+), then more generic (-)
        matches.sort { a, b in
            let (_, distA) = a
            let (_, distB) = b
            // Non-negative distances before negative
            if distA >= 0 && distB < 0 { return true }
            if distA < 0 && distB >= 0 { return false }
            // Same sign: prefer smaller absolute distance
            return abs(distA) < abs(distB)
        }

        return matches.first?.handlerIdx
    }

    /// Run the host. Blocks until the local connection closes.
    ///
    /// `localRead` / `localWrite` connect to the RelaySlave's local side.
    public func run(localRead: FileHandle, localWrite: FileHandle) throws {
        let reader = FrameReader(handle: localRead)

        // Writer runs with SeqAssigner
        let writeContinuation: AsyncStream<Frame>.Continuation
        let writeStream: AsyncStream<Frame>
        (writeStream, writeContinuation) = AsyncStream<Frame>.makeStream()

        let writerTask = Task {
            let writer = FrameWriter(handle: localWrite)
            let seqAssigner = SeqAssigner()

            for await var frame in writeStream {
                seqAssigner.assign(&frame)
                try? writer.write(frame)
                if frame.frameType == .end || frame.frameType == .err {
                    seqAssigner.remove(FlowKey.fromFrame(frame))
                }
            }
        }

        // Send initial RelayNotify with aggregate caps
        let manifest = buildManifest()
        let notify = Frame.relayNotify(manifest: manifest, limits: Limits())
        writeContinuation.yield(notify)

        // Build cap table
        let capTable = Self.buildCapTable(handlers: handlers)

        // Active request channels: request_id → AsyncStream.Continuation for forwarding frames to handler
        var active: [MessageId: AsyncStream<Frame>.Continuation] = [:]

        // Built-in identity handler
        let identityHandler = IdentityHandler()

        // Main read loop — forward frames to handlers, no accumulation
        while let frame = try? reader.read() {
            switch frame.frameType {
            case .req:
                let rid = frame.id
                let xid = frame.routingId
                guard let capUrn = frame.cap else {
                    var err = Frame.err(id: rid, code: "PROTOCOL_ERROR", message: "REQ missing cap URN")
                    err.routingId = xid
                    writeContinuation.yield(err)
                    continue
                }

                // Identity cap is "cap:" — exact string match, NOT conforms_to.
                let isIdentity = capUrn == CSCapIdentity

                let handler: FrameHandler = isIdentity ? identityHandler : {
                    if let idx = Self.findHandlerForCap(capTable: capTable, capUrn: capUrn) {
                        return handlers[idx].handler
                    } else {
                        var err = Frame.err(id: rid, code: "NO_HANDLER", message: "no handler for cap: \(capUrn)")
                        err.routingId = xid
                        writeContinuation.yield(err)
                        return identityHandler // dummy, never used
                    }
                }()

                // If NO_HANDLER was sent, skip spawning handler
                if !isIdentity && Self.findHandlerForCap(capTable: capTable, capUrn: capUrn) == nil {
                    continue
                }

                // Create channel for forwarding frames to handler
                let inputContinuation: AsyncStream<Frame>.Continuation
                let inputStream: AsyncStream<Frame>
                (inputStream, inputContinuation) = AsyncStream<Frame>.makeStream()
                active[rid] = inputContinuation

                // Spawn handler task
                let output = ResponseWriter(
                    requestId: rid,
                    routingId: xid,
                    sendFrame: { writeContinuation.yield($0) },
                    maxChunk: Limits().maxChunk
                )

                Task.detached {
                    await handler.handleRequest(capUrn: capUrn, inputStream: inputStream, output: output)
                }

            // Continuation frames: forward to handler
            case .streamStart, .chunk, .streamEnd:
                if let continuation = active[frame.id] {
                    continuation.yield(frame)
                }

            case .end:
                // Forward END to handler, then remove from active
                if let continuation = active.removeValue(forKey: frame.id) {
                    continuation.yield(frame)
                    continuation.finish()
                }

            case .heartbeat:
                let response = Frame.heartbeat(id: frame.id)
                writeContinuation.yield(response)

            case .err:
                // Error from relay for a pending request — close handler's input
                if let continuation = active.removeValue(forKey: frame.id) {
                    continuation.finish()
                }

            case .cancel:
                // Cancel: close handler's input stream (cooperative cancel) and send ERR
                let targetRid = frame.id
                let xid = frame.routingId
                if let continuation = active.removeValue(forKey: targetRid) {
                    continuation.finish()
                }
                var err = Frame.err(id: targetRid, code: "CANCELLED", message: "Request cancelled")
                err.routingId = xid
                writeContinuation.yield(err)

            default:
                // RelayNotify, RelayState, etc. — not expected from relay side
                break
            }
        }

        // Drop all active channels to signal handlers to exit
        for (_, continuation) in active {
            continuation.finish()
        }
        active.removeAll()

        writeContinuation.finish()
        writerTask.cancel()
    }
}
