//
//  CartridgeRuntime.swift
//  Bifaci
//
//  Cartridge-side runtime for CBOR-based cartridge communication.
//
//  This is the ONLY supported way for a cartridge to communicate with the host.
//  Swift cartridges use this runtime to:
//  1. Perform HELLO handshake with the host
//  2. Register handlers for caps they provide
//  3. Process incoming REQ frames
//  4. Send CHUNK/END/ERR responses
//  5. Respond to HEARTBEAT for health monitoring
//  6. Invoke caps on the host via PeerInvoker (bidirectional communication)
//
//  Usage:
//  ```swift
//  let runtime = CartridgeRuntime(manifest: manifestData)
//  runtime.register(capUrn: "cap:my-op") { payload, emitter, peer in
//      emitter.emitStatus(operation: "processing", details: "Working...")
//      // Optionally invoke host caps via peer.invoke()
//      emitter.emit(chunk: someData)
//      return finalResult
//  }
//  try runtime.run()  // Blocks until stdin closes
//  ```

import Foundation
import os
import CapDAG
import TaggedUrn
@preconcurrency import SwiftCBOR
import Glob
import Ops

/// OSLog handle for cartridge-runtime diagnostic events. Visible to
/// `log stream --subsystem com.machinefabric.bifaci --category
/// CartridgeRuntime`, and to mfmon's predicate (which already covers
/// the bifaci subsystem).
private let cartridgeRuntimeLog = OSLog(
    subsystem: "com.machinefabric.bifaci",
    category: "CartridgeRuntime"
)

// MARK: - Error Types

/// Errors specific to CartridgeRuntime operations
public enum CartridgeRuntimeError: Error, LocalizedError, @unchecked Sendable {
    case handshakeFailed(String)
    case noHandler(String)
    case handlerError(String)
    case deserializationError(String)
    case serializationError(String)
    case ioError(String)
    case protocolError(String)
    case peerRequestError(String)
    case peerResponseError(String)
    case cliError(String)
    case missingArgument(String)
    case unknownSubcommand(String)
    case manifestError(String)
    case capUrnError(String)

    public var errorDescription: String? {
        switch self {
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .noHandler(let cap): return "No handler registered for cap: \(cap)"
        case .handlerError(let msg): return "Handler error: \(msg)"
        case .deserializationError(let msg): return "Deserialization error: \(msg)"
        case .serializationError(let msg): return "Serialization error: \(msg)"
        case .ioError(let msg): return "I/O error: \(msg)"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .peerRequestError(let msg): return "Peer request error: \(msg)"
        case .peerResponseError(let msg): return "Peer response error: \(msg)"
        case .cliError(let msg): return "CLI error: \(msg)"
        case .missingArgument(let arg): return "Missing required argument: \(arg)"
        case .unknownSubcommand(let cmd): return "Unknown subcommand: \(cmd)"
        case .manifestError(let msg): return "Manifest error: \(msg)"
        case .capUrnError(let msg): return "Cap URN error: \(msg)"
        }
    }
}

// MARK: - Stream Abstractions
// Stream abstractions hide the frame protocol from handlers.
// Handlers work with streams of CBOR values, not raw frames.

/// Errors that can occur during stream operations.
public enum StreamError: Error {
    case remoteError(code: String, message: String)
    case closed
    case decode(String)
    case io(String)
    case protocolError(String)
}

/// Allows sending frames directly through the output channel.
/// Internal to the runtime — handlers never see this.
protocol FrameSender: Sendable {
    func send(_ frame: Frame) throws
}

/// A single input stream — yields decoded CBOR values from CHUNK frames.
/// Handler never sees Frame, STREAM_START, STREAM_END, checksum, seq, or index.
public final class InputStream: Sequence, @unchecked Sendable {
    private let _mediaUrn: String
    private let rx: UnsafeTransfer<AnyIterator<Result<CBOR, StreamError>>>

    init(mediaUrn: String, rx: AnyIterator<Result<CBOR, StreamError>>) {
        self._mediaUrn = mediaUrn
        self.rx = UnsafeTransfer(rx)
    }

    /// Media URN of this stream (from STREAM_START).
    public var mediaUrn: String {
        _mediaUrn
    }

    /// Collect each chunk as a separate item with its raw bytes.
    /// For sequence streams (is_sequence=true), each chunk is one item.
    /// Returns an array of raw byte items, CBOR-unwrapped.
    public func collectItems() throws -> [Data] {
        var items: [Data] = []
        for itemResult in self {
            let item = try itemResult.get()
            switch item {
            case .byteString(let bytes):
                items.append(Data(bytes))
            case .utf8String(let str):
                items.append(str.data(using: .utf8) ?? Data())
            default:
                let encoded = Data(item.encode())
                items.append(encoded)
            }
        }
        return items
    }

    /// Collect all chunks into a single byte vector (scalar path).
    /// Extracts inner bytes from .byteString/.utf8String and concatenates.
    /// Use this for scalar (non-list) streams.
    public func collectBytes() throws -> Data {
        var result = Data()
        for itemResult in self {
            let item = try itemResult.get()
            switch item {
            case .byteString(let bytes):
                result.append(contentsOf: bytes)
            case .utf8String(let str):
                result.append(str.data(using: .utf8) ?? Data())
            default:
                // For non-byte types, CBOR-encode them
                let encoded = Data(item.encode())
                result.append(encoded)
            }
        }
        return result
    }

    /// Collect all chunks as a raw CBOR sequence (list path).
    ///
    /// Each chunk's CBOR-encoded payload is appended as-is — the result is an
    /// RFC 8742 CBOR sequence where each self-delimiting CBOR value is one list
    /// item. Use `splitCborSequence()` to iterate the items.
    ///
    /// Use this for list-tagged streams (where `CSMediaUrnIsList(mediaUrn)` is true).
    public func collectCborSequence() throws -> Data {
        var result = Data()
        for itemResult in self {
            let item = try itemResult.get()
            // Re-encode the CBOR value — this preserves the self-delimiting structure
            let encoded = Data(item.encode())
            result.append(encoded)
        }
        return result
    }

    /// Collect a single CBOR value (expects exactly one chunk).
    public func collectValue() throws -> CBOR {
        guard let first = rx.value.next() else {
            throw StreamError.closed
        }
        return try first.get()
    }

    public func makeIterator() -> AnyIterator<Result<CBOR, StreamError>> {
        rx.value
    }
}

/// A single item from a peer response — either decoded data or a LOG frame.
///
/// `PeerResponse.recv()` yields these interleaved in arrival order. Handlers
/// match on each variant to decide how to react (e.g., forward progress, accumulate data).
public enum PeerResponseItem {
    /// A decoded CBOR data chunk from the peer response.
    case data(Result<CBOR, StreamError>)
    /// A LOG frame from the peer (progress, status messages, etc.).
    case log(Frame)
}

/// Response from a peer call — yields both data items and LOG frames from a single collection.
///
/// The handler drains this with `recv()` and reacts to each `PeerResponseItem` as it arrives.
/// For callers that don't care about LOG frames, `collectBytes()` and `collectValue()`
/// silently discard them and return only data.
public final class PeerResponse: @unchecked Sendable {
    private let items: UnsafeTransfer<AnyIterator<PeerResponseItem>>

    init(items: AnyIterator<PeerResponseItem>) {
        self.items = UnsafeTransfer(items)
    }

    /// Receive the next item (data or LOG) from the peer response.
    /// Returns nil when the stream ends.
    public func recv() -> PeerResponseItem? {
        items.value.next()
    }

    /// Collect all data chunks into a single byte vector, discarding LOG frames.
    public func collectBytes() throws -> Data {
        var result = Data()
        while let item = recv() {
            switch item {
            case .data(let dataResult):
                let value = try dataResult.get()
                switch value {
                case .byteString(let bytes):
                    result.append(contentsOf: bytes)
                case .utf8String(let str):
                    result.append(str.data(using: .utf8) ?? Data())
                default:
                    let encoded = Data(value.encode())
                    result.append(encoded)
                }
            case .log:
                break // Discard LOG frames
            }
        }
        return result
    }

    /// Collect a single CBOR data value (expects exactly one data chunk), discarding LOG frames.
    public func collectValue() throws -> CBOR {
        while let item = recv() {
            switch item {
            case .data(let dataResult):
                return try dataResult.get()
            case .log:
                break // Discard LOG frames
            }
        }
        throw StreamError.closed
    }
}

/// The bundle of all input arg streams for one request.
/// Yields InputStream objects as STREAM_START frames arrive from the wire.
/// Returns nil after END frame (all args delivered).
public final class InputPackage: Sequence, @unchecked Sendable {
    private let rx: UnsafeTransfer<AnyIterator<Result<InputStream, StreamError>>>

    init(rx: AnyIterator<Result<InputStream, StreamError>>) {
        self.rx = UnsafeTransfer(rx)
    }

    /// Get the next input stream. Returns nil when all streams delivered (after END).
    public func nextStream() -> Result<InputStream, StreamError>? {
        rx.value.next()
    }

    /// Collect all streams' bytes into a single Data.
    public func collectAllBytes() throws -> Data {
        var all = Data()
        for streamResult in self {
            let stream = try streamResult.get()
            all.append(try stream.collectBytes())
        }
        return all
    }

    /// Collect each stream individually into an array of (mediaUrn, bytes) pairs.
    /// Each stream's bytes are accumulated separately — NOT concatenated.
    public func collectStreams() throws -> [(mediaUrn: String, bytes: Data)] {
        var result: [(mediaUrn: String, bytes: Data)] = []
        for streamResult in self {
            let stream = try streamResult.get()
            let urn = stream.mediaUrn
            let bytes = try stream.collectBytes()
            result.append((mediaUrn: urn, bytes: bytes))
        }
        return result
    }

    public func makeIterator() -> AnyIterator<Result<InputStream, StreamError>> {
        rx.value
    }
}

/// Find a stream's bytes by exact URN equivalence (order-independent tag matching).
/// Uses CSMediaUrn.isEquivalentTo — matches only if both URNs have the exact same tag set.
///
/// Use this when the cap-arg URN you are matching is a single canonical
/// constant (`MEDIA_LLM_GENERATION_REQUEST`, `CSMediaModelSpecMlxLlm`,
/// etc.) and the planner emits exactly that URN on the stream.
///
/// For cap-args declared in TOML with rich dim profiles (e.g.
/// `media:max-tokens;inference;limit;user;task;textable;numeric` —
/// richer than the bare `media:max-tokens;textable;numeric` shape the
/// handler thinks about), use `findStreamConforming` instead. Equality
/// matching against the bare form silently misses the rich form, and
/// any conforming-but-unmatched stream then falls through to a
/// downstream `media:textable` catch-all and overwrites the prompt
/// body — that's the gibberish-output bug.
public func findStream(_ streams: [(mediaUrn: String, bytes: Data)], mediaUrn: String) -> Data? {
    guard let target = try? CSMediaUrn.fromString(mediaUrn) else { return nil }
    for (urnStr, bytes) in streams {
        guard let urn = try? CSMediaUrn.fromString(urnStr) else { continue }
        if target.isEquivalent(to: urn) {
            return bytes
        }
    }
    return nil
}

/// Like findStream but returns a UTF-8 string.
public func findStreamStr(_ streams: [(mediaUrn: String, bytes: Data)], mediaUrn: String) -> String? {
    guard let data = findStream(streams, mediaUrn: mediaUrn) else { return nil }
    return String(data: data, encoding: .utf8)
}

/// Find a stream whose URN *conforms to* the given pattern. The
/// pattern is the broad form the handler knows about (e.g.
/// `media:max-tokens;textable;numeric`); any stream URN with at
/// least those tags (more tags = more specific) matches. This is
/// the right matcher for cap-args whose TOML URN is a refinement
/// of the bare handler form — see `findStream` for the equality
/// case and the rationale.
public func findStreamConforming(_ streams: [(mediaUrn: String, bytes: Data)], pattern: String) -> Data? {
    guard let target = try? CSMediaUrn.fromString(pattern) else { return nil }
    for (urnStr, bytes) in streams {
        guard let urn = try? CSMediaUrn.fromString(urnStr) else { continue }
        if urn.conforms(to: target) {
            return bytes
        }
    }
    return nil
}

/// Like findStreamConforming but returns a UTF-8 string.
public func findStreamStrConforming(_ streams: [(mediaUrn: String, bytes: Data)], pattern: String) -> String? {
    guard let data = findStreamConforming(streams, pattern: pattern) else { return nil }
    return String(data: data, encoding: .utf8)
}

/// Like findStream but fails hard if not found.
public func requireStream(_ streams: [(mediaUrn: String, bytes: Data)], mediaUrn: String) throws -> Data {
    guard let data = findStream(streams, mediaUrn: mediaUrn) else {
        throw StreamError.protocolError("Missing required arg: \(mediaUrn)")
    }
    return data
}

/// Like requireStream but returns a UTF-8 string.
public func requireStreamStr(_ streams: [(mediaUrn: String, bytes: Data)], mediaUrn: String) throws -> String {
    let data = try requireStream(streams, mediaUrn: mediaUrn)
    guard let str = String(data: data, encoding: .utf8) else {
        throw StreamError.decode("Arg '\(mediaUrn)' is not valid UTF-8")
    }
    return str
}

/// Writable stream handle for handler output or peer call arguments.
/// Manages STREAM_START/CHUNK/STREAM_END framing automatically.
///
/// Mirrors Rust's OutputStream exactly:
/// - `start(isSequence:)` must be called exactly once before any output.
/// - `write()` requires `start(isSequence: false)`.
/// - `emitListItem()` requires `start(isSequence: true)`.
/// - `emitCbor()` requires `start(isSequence: false)`.
/// - `close()` is idempotent. No-op if `start()` was never called.
public final class OutputStream: @unchecked Sendable {
    private let sender: any FrameSender
    private let streamId: String
    private let _mediaUrn: String
    private let requestId: MessageId
    private let routingId: MessageId?
    private let maxChunk: Int

    /// None = not started, Some(false) = write mode, Some(true) = sequence mode
    private let streamModeLock = NSLock()
    private var _streamMode: Bool? = nil

    private let chunkStateLock = NSLock()
    private var _chunkIndex: UInt64 = 0
    private var _chunkCount: UInt64 = 0

    private let closedLock = NSLock()
    private var _closed = false

    init(
        sender: any FrameSender,
        streamId: String,
        mediaUrn: String,
        requestId: MessageId,
        routingId: MessageId?,
        maxChunk: Int
    ) {
        self.sender = sender
        self.streamId = streamId
        self._mediaUrn = mediaUrn
        self.requestId = requestId
        self.routingId = routingId
        self.maxChunk = maxChunk
    }

    /// Media URN of this stream.
    public var mediaUrn: String {
        _mediaUrn
    }

    /// Send STREAM_START with the given mode. Must be called exactly once
    /// before any write/emitListItem/emitCbor calls.
    ///
    /// - `isSequence = false` — write mode: each chunk is a complete CBOR value
    /// - `isSequence = true`  — sequence mode: chunks are CBOR fragments (RFC 8742)
    public func start(isSequence: Bool) throws {
        streamModeLock.lock()
        let alreadyStarted = _streamMode != nil
        if !alreadyStarted {
            _streamMode = isSequence
        }
        streamModeLock.unlock()

        if alreadyStarted {
            throw CartridgeRuntimeError.handlerError("stream already started")
        }

        var startFrame = Frame.streamStart(
            reqId: requestId,
            streamId: streamId,
            mediaUrn: _mediaUrn,
            isSequence: isSequence
        )
        startFrame.routingId = routingId
        try sender.send(startFrame)
    }

    private func checkMode(_ isSequence: Bool) throws {
        streamModeLock.lock()
        let mode = _streamMode
        streamModeLock.unlock()

        guard let existing = mode else {
            throw CartridgeRuntimeError.handlerError(
                "stream not started: call start() before write/emitListItem"
            )
        }
        if existing != isSequence {
            let existingName = existing ? "sequence" : "write"
            let calledName = isSequence ? "sequence" : "write"
            throw CartridgeRuntimeError.handlerError(
                "stream mode conflict: started as \(existingName) but called with \(calledName)"
            )
        }
    }

    private func sendChunk(_ value: CBOR) throws {
        let cborPayload = Data(value.encode())

        chunkStateLock.lock()
        let currentChunkIndex = _chunkIndex
        _chunkIndex += 1
        _chunkCount += 1
        chunkStateLock.unlock()

        let checksum = Frame.computeChecksum(cborPayload)
        var frame = Frame.chunk(
            reqId: requestId,
            streamId: streamId,
            seq: 0, // seq assigned by writer thread SeqAssigner
            payload: cborPayload,
            chunkIndex: currentChunkIndex,
            checksum: checksum
        )
        frame.routingId = routingId
        try sender.send(frame)
    }

    /// Write raw bytes. Splits into maxChunk pieces, each wrapped as CBOR byteString.
    /// Requires `start(isSequence: false)` to have been called first.
    public func write(_ data: Data) throws {
        try checkMode(false)
        if data.isEmpty {
            return
        }
        var offset = 0
        while offset < data.count {
            let chunkSize = min(data.count - offset, maxChunk)
            let chunkBytes = data.subdata(in: offset..<(offset + chunkSize))
            try sendChunk(.byteString([UInt8](chunkBytes)))
            offset += chunkSize
        }
    }

    /// Emit a single CBOR value as one item in an RFC 8742 CBOR sequence.
    ///
    /// For list outputs: the receiver concatenates raw frame payloads and stores
    /// the result as a CBOR sequence. This method CBOR-encodes the value, then
    /// splits the encoded bytes across chunk frames at `maxChunk` boundaries.
    /// The receiver's concatenation reconstructs the original CBOR encoding,
    /// producing exactly one self-delimiting CBOR value in the sequence per call.
    ///
    /// Unlike `emitCbor` (which re-wraps each piece as a separate CBOR value),
    /// this sends raw CBOR bytes as frame payloads directly.
    /// Requires `start(isSequence: true)` to have been called first.
    public func emitListItem(_ value: CBOR) throws {
        try checkMode(true)
        let cborBytes = Data(value.encode())

        var offset = 0
        while offset < cborBytes.count {
            let chunkSize = min(cborBytes.count - offset, maxChunk)
            let chunkPayload = cborBytes.subdata(in: offset..<(offset + chunkSize))

            chunkStateLock.lock()
            let currentChunkIndex = _chunkIndex
            _chunkIndex += 1
            _chunkCount += 1
            chunkStateLock.unlock()

            let checksum = Frame.computeChecksum(chunkPayload)
            var frame = Frame.chunk(
                reqId: requestId,
                streamId: streamId,
                seq: 0,
                payload: chunkPayload,
                chunkIndex: currentChunkIndex,
                checksum: checksum
            )
            frame.routingId = routingId
            try sender.send(frame)
            offset += chunkSize
        }
    }

    /// Emit a CBOR value. Handles byteString/utf8String/array/map chunking.
    /// Uses write mode (isSequence=false) — each chunk is a complete CBOR value.
    /// Requires `start(isSequence: false)` to have been called first.
    public func emitCbor(_ value: CBOR) throws {
        try checkMode(false)
        switch value {
        case .byteString(let bytes):
            var offset = 0
            while offset < bytes.count {
                let chunkSize = min(bytes.count - offset, maxChunk)
                let chunkBytes = Array(bytes[offset..<(offset + chunkSize)])
                try sendChunk(.byteString(chunkBytes))
                offset += chunkSize
            }

        case .utf8String(let text):
            let textBytes = Data(text.utf8)
            var offset = 0
            while offset < textBytes.count {
                var chunkSize = min(textBytes.count - offset, maxChunk)
                // Ensure we don't split UTF-8 mid-character
                while chunkSize > 0 {
                    let chunkData = textBytes.subdata(in: offset..<(offset + chunkSize))
                    if String(data: chunkData, encoding: .utf8) != nil {
                        break
                    }
                    chunkSize -= 1
                }
                if chunkSize == 0 {
                    throw CartridgeRuntimeError.handlerError("Cannot split text on character boundary")
                }
                let chunkData = textBytes.subdata(in: offset..<(offset + chunkSize))
                let chunkText = String(data: chunkData, encoding: .utf8)!
                try sendChunk(.utf8String(chunkText))
                offset += chunkSize
            }

        case .array(let elements):
            for element in elements {
                try sendChunk(element)
            }

        case .map(let entries):
            for (key, val) in entries {
                let entry = CBOR.array([key, val])
                try sendChunk(entry)
            }

        default:
            // Other types (int, float, bool, null): send as single chunk
            try sendChunk(value)
        }
    }

    /// Emit a log message.
    public func log(level: String, message: String) {
        var frame = Frame.log(id: requestId, level: level, message: message)
        frame.routingId = routingId
        try? sender.send(frame)
    }

    /// Emit a progress update (0.0–1.0) with a human-readable status message.
    public func progress(_ progress: Float, message: String) {
        var frame = Frame.progress(id: requestId, progress: progress, message: message)
        frame.routingId = routingId
        try? sender.send(frame)
    }

    /// Run an async operation while emitting keepalive progress frames every 30 seconds.
    ///
    /// Model loading (MLX LLM, VLM, embeddings) can take minutes for large models.
    /// The engine's 120s activity timeout kills the task if no frames arrive.
    /// This method spawns a background Task that re-emits the given progress value
    /// every 30s, keeping the timeout reset. The keepalive Task is cancelled when
    /// the operation completes.
    public func runWithKeepalive<T>(progress progressValue: Float, message: String, operation: () async throws -> T) async throws -> T {
        let keepalive = Task { [self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled {
                    self.progress(progressValue, message: message)
                }
            }
        }
        do {
            let result = try await operation()
            keepalive.cancel()
            return result
        } catch {
            keepalive.cancel()
            throw error
        }
    }

    /// Create a detached progress/log emitter that can be used from any thread.
    ///
    /// The returned `ProgressSender` is `Sendable` and can be moved into background
    /// threads or `Task` closures. It emits LOG frames independently of the
    /// `OutputStream` — no stream start/close semantics.
    ///
    /// Use this when you need to emit progress from inside a blocking operation
    /// (e.g., model loading on a background thread).
    public func progressSender() -> ProgressSender {
        ProgressSender(sender: sender, requestId: requestId, routingId: routingId)
    }

    /// Close the output stream (sends STREAM_END). Idempotent.
    /// If `start()` was never called, this is a no-op (no STREAM_START was sent,
    /// so no STREAM_END is needed — the handler produced no output).
    public func close() throws {
        closedLock.lock()
        let alreadyClosed = _closed
        if !alreadyClosed {
            _closed = true
        }
        closedLock.unlock()

        if alreadyClosed {
            return
        }

        streamModeLock.lock()
        let mode = _streamMode
        streamModeLock.unlock()

        if mode == nil {
            return // Never started — no output produced, nothing to close
        }

        chunkStateLock.lock()
        let finalChunkCount = _chunkCount
        chunkStateLock.unlock()

        var frame = Frame.streamEnd(
            reqId: requestId,
            streamId: streamId,
            chunkCount: finalChunkCount
        )
        frame.routingId = routingId
        try sender.send(frame)
    }
}

/// Detached progress/log emitter that can be used from any thread.
///
/// Holds a `FrameSender` and the request routing info needed to construct
/// LOG frames. `Sendable` by construction — safe to move into background
/// threads or `Task` closures.
///
/// Use `OutputStream.progressSender()` to create one.
public final class ProgressSender: @unchecked Sendable {
    private let sender: any FrameSender
    private let requestId: MessageId
    private let routingId: MessageId?

    init(sender: any FrameSender, requestId: MessageId, routingId: MessageId?) {
        self.sender = sender
        self.requestId = requestId
        self.routingId = routingId
    }

    /// Emit a progress update (0.0–1.0) with a human-readable status message.
    public func progress(_ progress: Float, message: String) {
        var frame = Frame.progress(id: requestId, progress: progress, message: message)
        frame.routingId = routingId
        try? sender.send(frame)
    }

    /// Emit a log message.
    public func log(level: String, message: String) {
        var frame = Frame.log(id: requestId, level: level, message: message)
        frame.routingId = routingId
        try? sender.send(frame)
    }
}

/// Handle for an in-progress peer invocation.
/// Handler creates arg streams with `arg()`, writes data, then calls `finish()`
/// to get the single response InputStream.
public final class PeerCall: @unchecked Sendable {
    private let sender: any FrameSender
    private let requestId: MessageId
    private let maxChunk: Int
    private var responseRx: AnyIterator<Frame>?
    private let lock = NSLock()

    init(sender: any FrameSender, requestId: MessageId, maxChunk: Int, responseRx: AnyIterator<Frame>) {
        self.sender = sender
        self.requestId = requestId
        self.maxChunk = maxChunk
        self.responseRx = responseRx
    }

    /// Create a new arg OutputStream for this peer call.
    /// Each arg is an independent stream (own stream_id, no routing_id).
    public func arg(mediaUrn: String) -> OutputStream {
        let streamId = UUID().uuidString
        return OutputStream(
            sender: sender,
            streamId: streamId,
            mediaUrn: mediaUrn,
            requestId: requestId,
            routingId: nil, // No routing_id for peer requests
            maxChunk: maxChunk
        )
    }

    /// Finish sending args and get the peer response.
    /// Sends END for the peer request, spawns Demux on response channel.
    ///
    /// Returns a `PeerResponse` that yields `PeerResponseItem.data` and
    /// `PeerResponseItem.log` interleaved in arrival order. The handler
    /// decides how to react to each (e.g., forward progress, accumulate data).
    public func finish() throws -> PeerResponse {
        // Send END frame for the peer request
        fputs("[PeerCall] finish: sending END for peer_rid=\(requestId)\n", stderr)
        let endFrame = Frame.end(id: requestId, finalPayload: nil)
        try sender.send(endFrame)

        // Take the response receiver
        lock.lock()
        guard let rx = responseRx else {
            lock.unlock()
            throw CartridgeRuntimeError.peerRequestError("PeerCall already finished")
        }
        responseRx = nil
        lock.unlock()

        // Start demux — returns immediately so LOG frames can be consumed
        // before data arrives (critical for keeping activity timer alive)
        let peerResponse = demuxSingleStream(responseRx: rx, maxChunk: maxChunk)
        fputs("[PeerCall] finish: demux started for peer_rid=\(requestId)\n", stderr)
        return peerResponse
    }
}

/// Wrapper to transfer non-Sendable types across concurrency boundaries.
/// Use with extreme caution — ensures external synchronization.
private final class UnsafeTransfer<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

/// Thread-safe blocking queue for bridging async streams to sync iterators.
/// Used to stream frames from AsyncStream to handler threads.
public final class BlockingQueue<T>: @unchecked Sendable {
    private var queue: [T] = []
    private let lock = NSLock()
    private let condition = NSCondition()
    private var finished = false

    public init() {}

    public func push(_ item: T) {
        condition.lock()
        queue.append(item)
        condition.signal()
        condition.unlock()
    }

    public func enqueue(_ item: T) {
        push(item)
    }

    public func dequeue() -> T? {
        condition.lock()
        defer { condition.unlock() }

        while queue.isEmpty && !finished {
            condition.wait()
        }

        if !queue.isEmpty {
            return queue.removeFirst()
        }
        return nil
    }

    public func tryPop(timeout: TimeInterval) -> T? {
        condition.lock()
        defer { condition.unlock() }

        let deadline = Date().addingTimeInterval(timeout)
        while queue.isEmpty && !finished {
            guard condition.wait(until: deadline) else {
                return nil  // Timeout
            }
        }

        if !queue.isEmpty {
            return queue.removeFirst()
        }
        return nil
    }

    public func isEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return queue.isEmpty
    }

    public func finish() {
        condition.lock()
        finished = true
        condition.broadcast()
        condition.unlock()
    }
}

/// Demux a single response stream from frame channel.
/// Used by PeerCall.finish() to convert response frames into PeerResponse.
///
/// LOG frames are delivered as PeerResponseItem.log alongside data items.
/// Wraps the raw frame iterator into a PeerResponse that yields PeerResponseItems
/// one at a time as they arrive. Returns immediately — LOG frames are delivered
/// in real-time, not buffered until data starts. This is critical for keeping
/// the engine's activity timer alive during long peer calls (e.g., model downloads).
internal func demuxSingleStream(responseRx: AnyIterator<Frame>, maxChunk: Int) -> PeerResponse {
    let iterator = AnyIterator<PeerResponseItem> {
        while let frame = responseRx.next() {
            switch frame.frameType {
            case .streamStart:
                // Structural frame — skip, yield next item
                continue

            case .chunk:
                guard let payload = frame.payload else {
                    return .data(.failure(.protocolError("CHUNK frame missing payload")))
                }

                // Verify checksum (MANDATORY in protocol v2)
                guard let expectedChecksum = frame.checksum else {
                    return .data(.failure(.protocolError("CHUNK frame missing required checksum field")))
                }
                let actualChecksum = Frame.computeChecksum(payload)
                if actualChecksum != expectedChecksum {
                    return .data(.failure(.protocolError("Checksum mismatch: expected=\(expectedChecksum), actual=\(actualChecksum) (payload \(payload.count) bytes)")))
                }

                do {
                    guard let value = try CBOR.decode([UInt8](payload)) else {
                        return .data(.failure(.decode("Failed to decode CBOR chunk - decode returned nil")))
                    }
                    return .data(.success(value))
                } catch {
                    return .data(.failure(.decode("Failed to decode CBOR chunk: \(error)")))
                }

            case .log:
                return .log(frame)

            case .streamEnd, .end:
                // Terminal — stream is done
                return nil

            case .err:
                let code = frame.errorCode ?? "UNKNOWN"
                let message = frame.errorMessage ?? "Unknown error"
                return .data(.failure(.remoteError(code: code, message: message)))

            default:
                return .data(.failure(.protocolError("Unexpected frame type in response: \(frame.frameType)")))
            }
        }
        return nil
    }

    return PeerResponse(items: iterator)
}

/// Demux multiple input streams from frame iterator into InputPackage.
/// Groups frames by stream_id, yields InputStream for each stream.
/// Used for incoming requests (cartridge receiving from host).
internal func demuxMultiStream(frameIterator: AnyIterator<Frame>) -> InputPackage {
    // Track per-stream state
    class StreamState {
        var mediaUrn: String = "media:"
        var chunks: [Result<CBOR, StreamError>] = []
        var ended = false
    }

    var streams: [String: StreamState] = [:]
    var streamOrder: [String] = [] // Track order of STREAM_START arrivals

    // Drain all frames and organize by stream_id
    for frame in frameIterator {
        switch frame.frameType {
        case .streamStart:
            guard let streamId = frame.streamId else {
                continue
            }
            let state = StreamState()
            if let urn = frame.mediaUrn {
                state.mediaUrn = urn
            }
            streams[streamId] = state
            streamOrder.append(streamId)

        case .chunk:
            guard let streamId = frame.streamId,
                  let state = streams[streamId],
                  let payload = frame.payload else {
                continue
            }

            // Verify checksum (MANDATORY in protocol v2)
            guard let expectedChecksum = frame.checksum else {
                state.chunks.append(.failure(.protocolError("CHUNK frame missing required checksum field")))
                continue
            }
            let actualChecksum = Frame.computeChecksum(payload)
            if actualChecksum != expectedChecksum {
                state.chunks.append(.failure(.protocolError("Checksum mismatch: expected=\(expectedChecksum), actual=\(actualChecksum)")))
                continue
            }

            do {
                guard let value = try CBOR.decode([UInt8](payload)) else {
                    state.chunks.append(.failure(.decode("Failed to decode CBOR chunk - decode returned nil")))
                    continue
                }
                state.chunks.append(.success(value))
            } catch {
                state.chunks.append(.failure(.decode("Failed to decode CBOR chunk: \(error)")))
            }

        case .streamEnd:
            guard let streamId = frame.streamId,
                  let state = streams[streamId] else {
                continue
            }
            state.ended = true

        case .end:
            break

        case .err:
            // Error frame - propagate to all streams
            let code = frame.errorCode ?? "UNKNOWN"
            let message = frame.errorMessage ?? "Unknown error"
            let error = StreamError.remoteError(code: code, message: message)
            for state in streams.values {
                state.chunks.append(.failure(error))
            }
            break

        default:
            break
        }
    }

    // Build InputStream for each stream in arrival order
    var inputStreams: [Result<InputStream, StreamError>] = []
    for streamId in streamOrder {
        guard let state = streams[streamId] else {
            continue
        }

        var chunkIndex = 0
        let chunksCopy = state.chunks
        let iterator = AnyIterator<Result<CBOR, StreamError>> {
            guard chunkIndex < chunksCopy.count else { return nil }
            let item = chunksCopy[chunkIndex]
            chunkIndex += 1
            return item
        }

        let inputStream = InputStream(mediaUrn: state.mediaUrn, rx: iterator)
        inputStreams.append(.success(inputStream))
    }

    // Create InputPackage iterator
    var streamIndex = 0
    let streamsIterator = AnyIterator<Result<InputStream, StreamError>> {
        guard streamIndex < inputStreams.count else { return nil }
        let item = inputStreams[streamIndex]
        streamIndex += 1
        return item
    }

    return InputPackage(rx: streamsIterator)
}

// MARK: - Stream Chunk Type - REMOVED
// StreamChunk wrapper removed - handlers now receive bare Frame objects directly

// MARK: - Argument Types

/// Unified argument for cap invocation - arguments are identified by media_urn.
public struct CapArgumentValue: Sendable {
    /// Semantic identifier, e.g., "media:model-spec;textable"
    public let mediaUrn: String
    /// Value bytes (UTF-8 for text, raw for binary)
    public let value: Data

    public init(mediaUrn: String, value: Data) {
        self.mediaUrn = mediaUrn
        self.value = value
    }

    /// Create from a string value
    public static func fromString(mediaUrn: String, value: String) -> CapArgumentValue {
        guard let data = value.data(using: .utf8) else {
            fatalError("Failed to encode string as UTF-8: \(value)")
        }
        return CapArgumentValue(mediaUrn: mediaUrn, value: data)
    }

    /// Get the value as a UTF-8 string (fails for binary data)
    public func valueAsString() throws -> String {
        guard let str = String(data: value, encoding: .utf8) else {
            throw CartridgeRuntimeError.deserializationError("Value is not valid UTF-8")
        }
        return str
    }
}


// MARK: - PeerInvoker Protocol

/// Allows handlers to invoke caps on the peer (host).
///
/// This protocol enables bidirectional communication where a cartridge handler can
/// invoke caps on the host while processing a request.
///
/// The `call` method starts a peer invocation and returns a `PeerCall`.
/// The handler creates arg streams with `call.arg()`, writes data, then
/// calls `call.finish()` to get a `PeerResponse` with data + LOG frames.
public protocol PeerInvoker: Sendable {
    /// Start a peer call. Sends REQ, registers response channel.
    func call(capUrn: String) throws -> PeerCall

    /// Convenience: open call, write each arg's bytes, finish, return response.
    ///
    /// Returns a `PeerResponse` — use `collectBytes()` / `collectValue()` to
    /// discard LOG frames, or `recv()` to process them alongside data.
    func callWithBytes(capUrn: String, args: [(mediaUrn: String, data: Data)]) throws -> PeerResponse
}

// Default implementation of callWithBytes
extension PeerInvoker {
    public func callWithBytes(capUrn: String, args: [(mediaUrn: String, data: Data)]) throws -> PeerResponse {
        let call = try self.call(capUrn: capUrn)
        for (mediaUrn, data) in args {
            let arg = call.arg(mediaUrn: mediaUrn)
            try arg.start(isSequence: false)
            try arg.write(data)
            try arg.close()
        }
        return try call.finish()
    }
}

/// A no-op PeerInvoker that always returns an error.
/// Used when peer invocation is not supported (e.g., CLI mode).
public struct NoPeerInvoker: PeerInvoker {
    public init() {}

    public func call(capUrn: String) throws -> PeerCall {
        throw CartridgeRuntimeError.peerRequestError("Peer invocation not supported in this context")
    }
}

// MARK: - CliFrameSender

/// CLI-mode frame sender that extracts and writes raw content to stdout.
/// Used by OutputStream in CLI mode.
///
/// Supports NDJSON mode (default: true) which adds newlines after each emit,
/// matching Rust's CliStreamEmitter behavior.
final class CliFrameSender: FrameSender, @unchecked Sendable {
    private let stdoutHandle: FileHandle

    /// Whether to add newlines after each emit (NDJSON style)
    let ndjson: Bool

    /// Create a new CLI sender with NDJSON formatting (newline after each emit)
    init() {
        self.stdoutHandle = FileHandle.standardOutput
        self.ndjson = true
    }

    /// Create a CLI sender with explicit ndjson setting
    init(ndjson: Bool) {
        self.stdoutHandle = FileHandle.standardOutput
        self.ndjson = ndjson
    }

    /// Create a CLI sender without NDJSON formatting
    static func withoutNdjson() -> CliFrameSender {
        return CliFrameSender(ndjson: false)
    }

    func send(_ frame: Frame) throws {
        // In CLI mode, only handle CHUNK frames with payload
        // STREAM_START, STREAM_END are ignored
        guard frame.frameType == .chunk, let payload = frame.payload else {
            return
        }

        // Decode CBOR value from payload
        guard let value = try CBOR.decode([UInt8](payload)) else {
            throw CartridgeRuntimeError.protocolError("Failed to decode CBOR chunk payload")
        }

        // Extract and write raw content
        try extractAndWrite(value, to: stdoutHandle)

        // Add newline in NDJSON mode
        if ndjson {
            stdoutHandle.write(Data("\n".utf8))
        }
    }

    /// Recursively extract and write raw content from CBOR values
    /// Throws on unsupported types - no fallbacks
    private func extractAndWrite(_ value: CBOR, to handle: FileHandle) throws {
        switch value {
        case .byteString(let bytes):
            handle.write(Data(bytes))

        case .utf8String(let text):
            handle.write(Data(text.utf8))

        case .array(let items):
            // Emit each element's raw content
            for item in items {
                try extractAndWrite(item, to: handle)
            }

        case .map(let m):
            // Extract "value" field if present
            if let val = m[.utf8String("value")] {
                try extractAndWrite(val, to: handle)
            } else {
                // No value field - fail hard (no fallback)
                throw CartridgeRuntimeError.handlerError("Map in CLI output has no 'value' field")
            }

        default:
            // Unsupported type - fail hard (no fallback)
            throw CartridgeRuntimeError.handlerError("CLI output does not support CBOR type")
        }
    }
}


// MARK: - Process Memory Self-Reporting

/// Get this process's own physical memory footprint and RSS in MB.
/// Uses `proc_pid_rusage(getpid(), RUSAGE_INFO_V4)` which is always permitted,
/// even inside a macOS sandbox (the sandbox only blocks querying OTHER processes).
/// Returns `(footprintMb, rssMb)` or `nil` on failure.
func getOwnMemoryMb() -> (footprintMb: UInt64, rssMb: UInt64)? {
    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
        }
    }
    guard result == 0 else { return nil }
    let footprintMb = UInt64(usage.ri_phys_footprint) / (1024 * 1024)
    let rssMb = UInt64(usage.ri_resident_size) / (1024 * 1024)
    return (footprintMb: footprintMb, rssMb: rssMb)
}

// MARK: - Payload Extraction

/// Extract the effective payload from a REQ frame.
///
/// If the content_type is "application/cbor", the payload is expected to be
/// CBOR arguments: `[{media_urn: string, value: bytes}, ...]`
/// The function extracts the value whose media_urn matches the cap's input type.
///
/// For other content types (or if content_type is nil), returns the raw payload.
///
/// - Parameters:
///   - payload: Raw payload bytes from the REQ frame
///   - contentType: Content-Type header from the REQ frame
///   - capUrn: The cap URN being invoked (used to determine expected input type)
/// - Returns: The effective payload bytes
/// - Throws: CartridgeRuntimeError if parsing fails or no matching argument found
/// Extract the effective payload from a REQ frame.
///
/// Mirrors capdag/src/bifaci/cartridge_runtime.rs::extract_effective_payload.
///
/// When `contentType` is "application/cbor", decode the CBOR arguments,
/// perform file-path auto-conversion (reading file bytes and relabeling
/// the arg's media_urn to the stdin source's target URN), validate that
/// at least one argument matches the cap's declared in= spec (unless the
/// cap takes media:void), and return the re-serialized CBOR array.
public func extractEffectivePayload(payload: Data, contentType: String?, cap: CapDefinition, isCliMode: Bool) throws -> Data {
    // Not CBOR arguments - return raw payload.
    guard contentType == "application/cbor" else {
        return payload
    }

    // Parse cap URN to get expected input media URN.
    let capUrnParsed: CSCapUrn
    do {
        capUrnParsed = try CSCapUrn.fromString(cap.urn)
    } catch {
        throw CartridgeRuntimeError.capUrnError("Invalid cap URN: \(error.localizedDescription)")
    }
    let expectedInput = capUrnParsed.getInSpec()
    let expectedMediaUrn = try? CSMediaUrn.fromString(expectedInput)

    // Build arg-definition lookup: parsed CSMediaUrn -> (stdin_target, is_sequence).
    struct ArgDefInfo {
        let urn: CSMediaUrn
        let stdinTarget: String?
        let isSequence: Bool
    }
    var argDefs: [ArgDefInfo] = []
    for a in cap.args {
        guard let parsed = try? CSMediaUrn.fromString(a.mediaUrn) else { continue }
        var stdinTarget: String? = nil
        for s in a.sources {
            if case .stdin(let target) = s {
                stdinTarget = target
                break
            }
        }
        argDefs.append(ArgDefInfo(urn: parsed, stdinTarget: stdinTarget, isSequence: a.isSequence))
    }

    // Parse the CBOR payload as an array of argument maps.
    guard let decoded = try CBOR.decode([UInt8](payload)) else {
        throw CartridgeRuntimeError.deserializationError("Failed to parse CBOR arguments")
    }
    guard case .array(var arguments) = decoded else {
        throw CartridgeRuntimeError.deserializationError("CBOR arguments must be an array")
    }

    // File-path auto-conversion.
    let filePathBase = try CSMediaUrn.fromString("media:file-path")

    for (idx, arg) in arguments.enumerated() {
        guard case .map(var argMap) = arg else { continue }
        var urnStr: String? = nil
        var value: CBOR? = nil
        for (k, v) in argMap {
            if case .utf8String(let key) = k {
                if key == "media_urn", case .utf8String(let s) = v { urnStr = s }
                else if key == "value" { value = v }
            }
        }
        guard let urnStr = urnStr, let value = value else { continue }
        let argUrn: CSMediaUrn
        do {
            argUrn = try CSMediaUrn.fromString(urnStr)
        } catch {
            throw CartridgeRuntimeError.handlerError("Invalid argument media URN '\(urnStr)': \(error.localizedDescription)")
        }
        // file_path_base.accepts(argUrn) == argUrn.conforms(to: file_path_base).
        if !argUrn.conforms(to: filePathBase) { continue }

        // Look up the cap's arg definition by URN equivalence (NOT string compare).
        var matched: ArgDefInfo? = nil
        for ad in argDefs {
            if ad.urn.isEquivalent(to: argUrn) {
                matched = ad
                break
            }
        }
        guard let matchedInfo = matched else { continue }
        guard let stdinTarget = matchedInfo.stdinTarget else { continue }

        let paths = try expandFilePathValue(value: value, urnStr: urnStr, isCliMode: isCliMode)

        if !matchedInfo.isSequence {
            if paths.count != 1 {
                throw CartridgeRuntimeError.handlerError(
                    "File-path arg '\(urnStr)' declared is_sequence=false resolved to \(paths.count) files; "
                    + "expected exactly 1. CLI-mode dispatch should have iterated the handler "
                    + "across the expanded files before calling the runtime."
                )
            }
            let url = URL(fileURLWithPath: paths[0])
            let fileBytes: Data
            do {
                fileBytes = try Data(contentsOf: url)
            } catch {
                throw CartridgeRuntimeError.handlerError("Failed to read file '\(paths[0])': \(error.localizedDescription)")
            }
            replaceArgValue(&argMap, newValue: .byteString([UInt8](fileBytes)), newUrn: stdinTarget)
        } else {
            var items: [CBOR] = []
            for p in paths {
                let url = URL(fileURLWithPath: p)
                do {
                    let data = try Data(contentsOf: url)
                    items.append(.byteString([UInt8](data)))
                } catch {
                    throw CartridgeRuntimeError.handlerError("Failed to read file '\(p)': \(error.localizedDescription)")
                }
            }
            replaceArgValue(&argMap, newValue: .array(items), newUrn: stdinTarget)
        }
        arguments[idx] = .map(argMap)
    }

    // Validate: at least ONE argument must match the cap's declared in=spec,
    // unless the cap takes no input (in=media:void).
    let voidUrn = try CSMediaUrn.fromString("media:void")
    let isVoidInput: Bool = {
        guard let exp = expectedMediaUrn else { return false }
        return exp.isEquivalent(to: voidUrn)
    }()

    if !isVoidInput {
        var validTargets: [CSMediaUrn] = []
        if let exp = expectedMediaUrn {
            validTargets.append(exp)
        }
        for ad in argDefs {
            if let t = ad.stdinTarget, let parsed = try? CSMediaUrn.fromString(t) {
                validTargets.append(parsed)
            }
        }

        var foundMatchingArg = false
        outer: for arg in arguments {
            guard case .map(let argMap) = arg else { continue }
            for (k, v) in argMap {
                if case .utf8String(let key) = k, key == "media_urn", case .utf8String(let s) = v {
                    guard let argUrn = try? CSMediaUrn.fromString(s) else { continue }
                    for target in validTargets {
                        if argUrn.isComparable(to: target) {
                            foundMatchingArg = true
                            break outer
                        }
                    }
                }
            }
        }

        if !foundMatchingArg {
            throw CartridgeRuntimeError.deserializationError(
                "No argument found matching expected input media type '\(expectedInput)' in CBOR arguments"
            )
        }
    }

    // After file-path conversion and validation, return the full CBOR array.
    let modified = CBOR.array(arguments)
    return Data(modified.encode())
}

/// Replace an argument map's "value" and "media_urn" entries in place.
///
/// Mirrors capdag/src/bifaci/cartridge_runtime.rs::replace_arg_value.
func replaceArgValue(_ argMap: inout [CBOR: CBOR], newValue: CBOR, newUrn: String) {
    argMap[.utf8String("value")] = newValue
    argMap[.utf8String("media_urn")] = .utf8String(newUrn)
}

/// Expand a file-path arg value into a concrete list of filesystem paths.
///
/// Mirrors capdag/src/bifaci/cartridge_runtime.rs::expand_file_path_value.
///
/// The incoming value may be:
///   - byteString/utf8String containing a single path or a single glob pattern
///   - array of byteString/utf8String items, each a path or a glob (CBOR mode only)
///
/// Globs (detected via `*`, `?`, or `[`) are expanded and the results filtered
/// to regular files. Literal paths must exist and point at a regular file.
/// Returns at least one path on success; empty matches fail hard so the caller
/// never has to guard against a silently-empty list.
func expandFilePathValue(value: CBOR, urnStr: String, isCliMode: Bool) throws -> [String] {
    var rawPaths: [String] = []
    switch value {
    case .byteString(let bytes):
        rawPaths = [String(decoding: bytes, as: UTF8.self)]
    case .utf8String(let s):
        rawPaths = [s]
    case .array(let arr):
        if isCliMode {
            throw CartridgeRuntimeError.handlerError(
                "File-path arg '\(urnStr)' received a CBOR Array value in CLI mode; "
                + "CLI dispatch must expand globs before calling into the runtime"
            )
        }
        for item in arr {
            switch item {
            case .utf8String(let s): rawPaths.append(s)
            case .byteString(let b): rawPaths.append(String(decoding: b, as: UTF8.self))
            default:
                throw CartridgeRuntimeError.handlerError(
                    "File-path arg '\(urnStr)' array contained an unsupported CBOR item"
                )
            }
        }
    default:
        throw CartridgeRuntimeError.handlerError(
            "File-path arg '\(urnStr)' value must be Bytes, Text, or (CBOR mode) Array"
        )
    }

    let fileManager = FileManager.default
    var resolved: [String] = []
    for raw in rawPaths {
        let isGlob = raw.contains("*") || raw.contains("?") || raw.contains("[")
        if isGlob {
            // Validate bracket balance.
            var bracketCount = 0
            for ch in raw {
                if ch == "[" { bracketCount += 1 }
                else if ch == "]" {
                    bracketCount -= 1
                    if bracketCount < 0 {
                        throw CartridgeRuntimeError.handlerError("Invalid glob pattern '\(raw)': unmatched ']'")
                    }
                }
            }
            if bracketCount != 0 {
                throw CartridgeRuntimeError.handlerError("Invalid glob pattern '\(raw)': unclosed '['")
            }
            let matches = Glob(pattern: raw)
            let before = resolved.count
            for m in matches {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: m, isDirectory: &isDir), !isDir.boolValue {
                    resolved.append(m)
                }
            }
            if resolved.count == before {
                throw CartridgeRuntimeError.handlerError("No files matched glob pattern '\(raw)'")
            }
        } else {
            var isDir: ObjCBool = false
            if !fileManager.fileExists(atPath: raw, isDirectory: &isDir) {
                throw CartridgeRuntimeError.handlerError("File not found: '\(raw)'")
            }
            if isDir.boolValue {
                throw CartridgeRuntimeError.handlerError("Path is not a regular file: '\(raw)'")
            }
            resolved.append(raw)
        }
    }
    return resolved
}

/// Compute per-iteration CBOR argument payloads for a CLI invocation.
///
/// Mirrors capdag/src/bifaci/cartridge_runtime.rs::build_cli_foreach_iterations.
public func buildCliForeachIterations(rawPayload: Data, cap: CapDefinition) throws -> [Data] {
    let filePathBase = try CSMediaUrn.fromString("media:file-path")

    guard let decoded = try CBOR.decode([UInt8](rawPayload)) else {
        throw CartridgeRuntimeError.deserializationError("Failed to parse CBOR arguments")
    }
    guard case .array(let arguments) = decoded else {
        throw CartridgeRuntimeError.deserializationError("CBOR arguments must be an array")
    }

    struct ArgDefShort {
        let urn: CSMediaUrn
        let isSequence: Bool
    }
    var argDefs: [ArgDefShort] = []
    for a in cap.args {
        if let parsed = try? CSMediaUrn.fromString(a.mediaUrn) {
            argDefs.append(ArgDefShort(urn: parsed, isSequence: a.isSequence))
        }
    }

    var iterable: (Int, [String])? = nil
    for (idx, arg) in arguments.enumerated() {
        guard case .map(let argMap) = arg else { continue }
        var urnStr: String? = nil
        var value: CBOR? = nil
        for (k, v) in argMap {
            if case .utf8String(let key) = k {
                if key == "media_urn", case .utf8String(let s) = v { urnStr = s }
                else if key == "value" { value = v }
            }
        }
        guard let urnStr = urnStr, let value = value else { continue }
        let argUrn: CSMediaUrn
        do {
            argUrn = try CSMediaUrn.fromString(urnStr)
        } catch {
            throw CartridgeRuntimeError.handlerError("Invalid argument media URN '\(urnStr)': \(error.localizedDescription)")
        }
        if !argUrn.conforms(to: filePathBase) { continue }

        var isSeq = false
        for ad in argDefs {
            if ad.urn.isEquivalent(to: argUrn) {
                isSeq = ad.isSequence
                break
            }
        }
        if isSeq { continue }

        let paths = try expandFilePathValue(value: value, urnStr: urnStr, isCliMode: true)
        if paths.count <= 1 { continue }

        if iterable != nil {
            throw CartridgeRuntimeError.handlerError(
                "Multiple file-path arguments with is_sequence=false each resolved to more than one file; "
                + "the ForEach axis is ambiguous. Declare at most one such arg as scalar, or mark "
                + "additional args as is_sequence=true."
            )
        }
        iterable = (idx, paths)
    }

    guard let (idx, paths) = iterable else {
        return [rawPayload]
    }

    var out: [Data] = []
    for path in paths {
        var argsForIter = arguments
        if case .map(var m) = argsForIter[idx] {
            m[.utf8String("value")] = .utf8String(path)
            argsForIter[idx] = .map(m)
        }
        let wrapped = CBOR.array(argsForIter)
        out.append(Data(wrapped.encode()))
    }
    return out
}


// MARK: - Handler Type

/// Handler function type for Frame-based streaming.
///
/// Handlers receive bare CBOR Frame objects for both input arguments and peer responses.
/// No wrapper types - frames are delivered directly as they arrive.
/// Handler has full streaming control - decides when to consume frames and when to produce output.
///
/// Input frames: STREAM_START, CHUNK, STREAM_END, END (request arguments)
/// Peer response frames: STREAM_START, CHUNK, STREAM_END, END, ERR (from PeerInvoker)
///
/// Handler processes frames and emits output via CborStreamEmitter.
/// Handler signature for cap invocations.
// =============================================================================
// OP-BASED HANDLER SYSTEM — handlers implement Ops.Op<Void>
// =============================================================================

/// Bundles capdag I/O for WetContext. Op handlers extract this from WetContext
/// to access streaming input, output, and peer invocation.
public final class CborRequest: @unchecked Sendable {
    private let _inputLock = NSLock()
    private var _inputPackage: InputPackage?
    private let _output: OutputStream
    private let _peer: any PeerInvoker

    public init(input: InputPackage, output: OutputStream, peer: any PeerInvoker) {
        _inputPackage = input
        _output = output
        _peer = peer
    }

    /// Take the input package. Can only be called once — second call throws.
    public func takeInput() throws -> InputPackage {
        _inputLock.lock()
        defer { _inputLock.unlock() }
        guard let pkg = _inputPackage else {
            throw CartridgeRuntimeError.protocolError("Input already consumed")
        }
        _inputPackage = nil
        return pkg
    }

    public func output() -> OutputStream { _output }
    public func peer() -> any PeerInvoker { _peer }
}

/// WetContext key for the CborRequest object.
public let WET_KEY_REQUEST: String = "request"

/// Factory that creates a fresh AnyOp<Void> per invocation.
/// Matches Rust's `Arc<dyn Fn() -> Box<dyn Op<()>> + Send + Sync>`.
public typealias OpFactory = @Sendable () -> AnyOp<Void>

/// Standard identity handler — pure passthrough. Forwards all input chunks to output.
public struct IdentityOp: Op, Sendable {
    public typealias Output = Void
    public init() {}
    public func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        try req.output().start(isSequence: false)
        for streamResult in input {
            let stream = try streamResult.get()
            for chunkResult in stream {
                let chunk = try chunkResult.get()
                try req.output().emitCbor(chunk)
            }
        }
    }
    public func metadata() -> OpMetadata {
        OpMetadata.builder("IdentityOp").description("Pure passthrough — forwards all input to output").build()
    }
}

/// Standard discard handler — terminal morphism. Drains all input, produces nothing.
public struct DiscardOp: Op, Sendable {
    public typealias Output = Void
    public init() {}
    public func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        for streamResult in input {
            let stream = try streamResult.get()
            for chunkResult in stream {
                _ = try chunkResult.get()
            }
        }
    }
    public func metadata() -> OpMetadata {
        OpMetadata.builder("DiscardOp").description("Terminal morphism — drains all input, produces nothing").build()
    }
}

/// Default adapter selection handler — returns empty END (no match).
///
/// This is the standard default for cartridges that do not inspect file content.
/// Cartridges that provide content inspection override this by registering their
/// own handler for CSCapAdapterSelection.
///
/// The empty END frame (exit code 0, no stream output) is the ONLY valid "no match"
/// response. The orchestrator treats any stream output that isn't valid
/// {"media_urns": [...]} as a runtime error.
public struct AdapterSelectionOp: Op, Sendable {
    public typealias Output = Void
    public init() {}
    public func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        // Drain all input — we don't inspect it in the default handler
        for streamResult in input {
            let stream = try streamResult.get()
            for chunkResult in stream {
                _ = try chunkResult.get()
            }
        }
        // Return without starting output — produces empty END frame
    }
    public func metadata() -> OpMetadata {
        OpMetadata.builder("AdapterSelectionOp").description("Default adapter selection — returns empty END (no match)").build()
    }
}

/// Dispatch an AnyOp<Void> with a CborRequest via WetContext.
/// Bridges sync handler threads to async Op.perform via DispatchSemaphore + Task.
/// Closes the output stream on success (sends STREAM_END if stream was started).
func dispatchOp(op: AnyOp<Void>, input: InputPackage, output: OutputStream, peer: any PeerInvoker) throws {
    let req = CborRequest(input: input, output: output, peer: peer)
    let dry = DryContext()
    let wet = WetContext()
    wet.insertRef(req, for: WET_KEY_REQUEST)

    // Use a class wrapper so Task can capture it as @Sendable (Swift 6 requirement)
    final class ErrorHolder: @unchecked Sendable { var error: Error? = nil }
    let holder = ErrorHolder()
    let sema = DispatchSemaphore(value: 0)
    Task { [holder, sema] in
        do {
            _ = try await op.perform(dry: dry, wet: wet)
        } catch {
            holder.error = error
        }
        sema.signal()
    }
    sema.wait()

    if let err = holder.error {
        throw err
    }
    // Auto-close output stream on success
    try? output.close()
}

// MARK: - Internal: Pending Peer Request

/// Internal struct to track pending peer requests (cartridge invoking host caps).
/// Now uses AsyncStream continuation to forward frames instead of condition variables.
private struct PendingPeerRequest {
    let continuation: AsyncStream<Frame>.Continuation
    var isComplete: Bool
    let originRequestId: MessageId
}

// MARK: - Internal: PeerInvokerImpl

/// Implementation of PeerInvoker that sends REQ frames to the host.
/// Spawns a background task that forwards response frames via FrameQueue.
@available(macOS 10.15.4, iOS 13.4, *)
/// ChannelFrameSender implementation for sending frames from PeerInvokerImpl and OutputStream.
/// Applies SeqAssigner to every outbound frame, matching Rust's writer-thread seq assignment.
/// Cleans up flow tracking on terminal frames (END/ERR).
@available(macOS 10.15.4, iOS 13.4, *)
private final class ChannelFrameSender: FrameSender, @unchecked Sendable {
    private let writer: FrameWriter
    private let writerLock: NSLock
    private let seqAssigner: SeqAssigner

    init(writer: FrameWriter, writerLock: NSLock, seqAssigner: SeqAssigner) {
        self.writer = writer
        self.writerLock = writerLock
        self.seqAssigner = seqAssigner
    }

    func send(_ frame: Frame) throws {
        writerLock.lock()
        defer { writerLock.unlock() }
        var mutableFrame = frame
        seqAssigner.assign(&mutableFrame)
        try writer.write(mutableFrame)
        if mutableFrame.frameType == .end || mutableFrame.frameType == .err {
            seqAssigner.remove(FlowKey.fromFrame(mutableFrame))
        }
    }
}

@available(macOS 10.15.4, iOS 13.4, *)
final class PeerInvokerImpl: PeerInvoker, @unchecked Sendable {
    private let writer: FrameWriter
    private let writerLock: NSLock
    private let seqAssigner: SeqAssigner
    private let pendingRequests: NSMutableDictionary // [MessageId: PendingPeerRequest]
    private let pendingRequestsLock: NSLock
    private let originRequestId: MessageId
    private let maxChunk: Int

    init(writer: FrameWriter, writerLock: NSLock, seqAssigner: SeqAssigner, pendingRequests: NSMutableDictionary, pendingRequestsLock: NSLock, originRequestId: MessageId, maxChunk: Int) {
        self.writer = writer
        self.writerLock = writerLock
        self.seqAssigner = seqAssigner
        self.pendingRequests = pendingRequests
        self.pendingRequestsLock = pendingRequestsLock
        self.originRequestId = originRequestId
        self.maxChunk = maxChunk
    }

    func call(capUrn: String) throws -> PeerCall {
        // Generate a new message ID for this request
        let requestId = MessageId.newUUID()
        fputs("[CartridgeRuntime] PEER_CALL: cap='\(capUrn)' peer_rid=\(requestId)\n", stderr)

        // Create AsyncStream and continuation for response frames
        let (stream, continuation) = AsyncStream<Frame>.makeStream()

        // Create pending request tracking
        let pending = PendingPeerRequest(
            continuation: continuation,
            isComplete: false,
            originRequestId: originRequestId
        )

        // Register the pending request before sending REQ
        pendingRequestsLock.lock()
        pendingRequests[requestId] = pending
        pendingRequestsLock.unlock()

        // Send REQ with empty payload, stamped with parent_rid for cancel cascade
        writerLock.lock()
        do {
            var reqFrame = Frame.req(id: requestId, capUrn: capUrn, payload: Data(), contentType: "application/cbor")
            var meta = reqFrame.meta ?? [:]
            switch originRequestId {
            case .uuid(let data):
                meta["parent_rid"] = .byteString([UInt8](data))
            case .uint(let n):
                meta["parent_rid"] = .unsignedInt(n)
            }
            reqFrame.meta = meta
            seqAssigner.assign(&reqFrame)
            try writer.write(reqFrame)
        } catch {
            writerLock.unlock()
            pendingRequestsLock.lock()
            pendingRequests.removeObject(forKey: requestId)
            pendingRequestsLock.unlock()
            continuation.finish()
            throw CartridgeRuntimeError.peerRequestError("Failed to send peer REQ: \(error)")
        }
        writerLock.unlock()

        // Convert AsyncStream to AnyIterator for PeerCall
        // Use thread-safe queue with @unchecked Sendable wrappers to bridge async→sync
        final class FrameQueue: @unchecked Sendable {
            private var frames: [Frame] = []
            private let lock = NSLock()
            private let semaphore = DispatchSemaphore(value: 0)
            private var completed = false

            func add(_ frame: Frame) {
                lock.lock()
                frames.append(frame)
                lock.unlock()
                semaphore.signal()
            }

            func complete() {
                lock.lock()
                completed = true
                lock.unlock()
                semaphore.signal()
            }

            func next() -> Frame? {
                semaphore.wait()
                lock.lock()
                defer { lock.unlock() }

                if !frames.isEmpty {
                    return frames.removeFirst()
                } else if completed {
                    return nil
                } else {
                    return nil // Should not happen
                }
            }
        }

        let queue = FrameQueue()

        // Spawn background task to drain AsyncStream
        Task.detached {
            for await frame in stream {
                queue.add(frame)
            }
            queue.complete()
        }

        let frameIterator = AnyIterator<Frame> {
            queue.next()
        }

        // Create ChannelFrameSender for arg streams (shares seqAssigner)
        let sender = ChannelFrameSender(writer: writer, writerLock: writerLock, seqAssigner: seqAssigner)

        // Return PeerCall with response iterator
        return PeerCall(
            sender: sender,
            requestId: requestId,
            maxChunk: maxChunk,
            responseRx: frameIterator
        )
    }
}

// MARK: - Manifest Types (for CLI mode)

/// Source for extracting argument values in CLI mode.
public enum ArgSource: Codable, Sendable {
    case cliFlag(String)
    case positional(Int)
    case stdin(String)  // Media URN for stdin input

    enum CodingKeys: String, CodingKey {
        case type
        case cliFlag = "cli_flag"
        case position
        case stdin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // The format is a single-key object: {"stdin": "..."}, {"position": 0}, or {"cli_flag": "..."}
        // NOT {"type": "stdin", "stdin": "..."}
        if let flag = try? container.decode(String.self, forKey: .cliFlag) {
            self = .cliFlag(flag)
        } else if let pos = try? container.decode(Int.self, forKey: .position) {
            self = .positional(pos)
        } else if let mediaUrn = try? container.decode(String.self, forKey: .stdin) {
            self = .stdin(mediaUrn)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid source format: must have exactly one of 'cli_flag', 'position', or 'stdin'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Encode as single-key object: {"stdin": "..."}, {"position": 0}, or {"cli_flag": "..."}
        switch self {
        case .cliFlag(let flag):
            try container.encode(flag, forKey: .cliFlag)
        case .positional(let pos):
            try container.encode(pos, forKey: .position)
        case .stdin(let mediaUrn):
            try container.encode(mediaUrn, forKey: .stdin)
        }
    }
}

/// Argument definition in a cap.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported JSON value"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    fileprivate func lexicalBytes() throws -> Data {
        switch self {
        case .string(let value):
            return Data(value.utf8)
        case .integer(let value):
            return Data(String(value).utf8)
        case .double(let value):
            return Data(String(value).utf8)
        case .bool(let value):
            return Data((value ? "true" : "false").utf8)
        case .null:
            return Data()
        case .array, .object:
            return try JSONEncoder().encode(self)
        }
    }
}

public struct CapArg: Codable, Sendable {
    public let mediaUrn: String
    public let required: Bool
    /// Whether this argument carries a sequence of items (isSequence=true)
    /// or a single item (isSequence=false, the default). Drives
    /// file-path expansion cardinality: scalar args see one file per
    /// invocation; sequence args see a CBOR array of file bytes.
    public let isSequence: Bool
    public let sources: [ArgSource]
    public let argDescription: String?
    public let defaultValue: JSONValue?

    enum CodingKeys: String, CodingKey {
        case mediaUrn = "media_urn"
        case required
        case isSequence = "is_sequence"
        case sources
        case argDescription = "arg_description"
        case defaultValue = "default_value"
    }

    public init(mediaUrn: String, required: Bool, isSequence: Bool = false, sources: [ArgSource], argDescription: String? = nil, defaultValue: JSONValue? = nil) {
        self.mediaUrn = mediaUrn
        self.required = required
        self.isSequence = isSequence
        self.sources = sources
        self.argDescription = argDescription
        self.defaultValue = defaultValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaUrn = try container.decode(String.self, forKey: .mediaUrn)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        isSequence = try container.decodeIfPresent(Bool.self, forKey: .isSequence) ?? false
        sources = try container.decodeIfPresent([ArgSource].self, forKey: .sources) ?? []
        argDescription = try container.decodeIfPresent(String.self, forKey: .argDescription)
        defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .defaultValue)
    }
}

/// Cap definition in the manifest.
public struct CapDefinition: Codable, Sendable {
    public let urn: String
    public let title: String
    public let command: String
    public let capDescription: String?
    public let args: [CapArg]

    enum CodingKeys: String, CodingKey {
        case urn
        case title
        case command
        case capDescription = "cap_description"
        case args
    }

    public init(urn: String, title: String, command: String, capDescription: String? = nil, args: [CapArg] = []) {
        self.urn = urn
        self.title = title
        self.command = command
        self.capDescription = capDescription
        self.args = args
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urn = try container.decode(String.self, forKey: .urn)
        title = try container.decode(String.self, forKey: .title)
        command = try container.decode(String.self, forKey: .command)
        capDescription = try container.decodeIfPresent(String.self, forKey: .capDescription)
        args = try container.decodeIfPresent([CapArg].self, forKey: .args) ?? []
    }

    /// Check if this cap accepts stdin input.
    public func acceptsStdin() -> Bool {
        for arg in args {
            for source in arg.sources {
                if case .stdin(_) = source {
                    return true
                }
            }
        }
        return false
    }
}

/// Cartridge manifest structure.
/// A cap group bundles caps and adapter URNs as an atomic registration unit.
public struct CapGroup: Codable, Sendable {
    public let name: String
    public let caps: [CapDefinition]
    public let adapterUrns: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case caps
        case adapterUrns = "adapter_urns"
    }

    public init(name: String, caps: [CapDefinition], adapterUrns: [String] = []) {
        self.name = name
        self.caps = caps
        self.adapterUrns = adapterUrns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        caps = try container.decodeIfPresent([CapDefinition].self, forKey: .caps) ?? []
        adapterUrns = try container.decodeIfPresent([String].self, forKey: .adapterUrns) ?? []
    }
}

public struct Manifest: Codable, Sendable {
    public let name: String
    public let version: String
    /// Distribution channel ("release" or "nightly"). Part of the
    /// cartridge's identity. The Swift cartridge SDK reads this
    /// from `MFR_CARTRIDGE_CHANNEL` at compile time.
    public let channel: String
    /// Verbatim registry URL the cartridge was built for. `nil` ⇔
    /// dev build (cartridge.sh was invoked without `--registry`).
    /// Part of the cartridge's identity — `(name, version, channel,
    /// registryURL)` is the full four-tuple. The Swift cartridge
    /// SDK reads this from a generated `BuildIdentity.generated.swift`
    /// file under `Sources/<cartridge>/Generated/` (mirror of Rust's
    /// `option_env!("MFR_REGISTRY_URL")`).
    public let registryURL: String?
    public let description: String
    /// All caps must be in cap groups. Groups without adapter URNs are valid.
    public let capGroups: [CapGroup]

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case channel
        case registryURL = "registry_url"
        case description
        case capGroups = "cap_groups"
    }

    public init(name: String, version: String, channel: String, registryURL: String?, description: String, capGroups: [CapGroup]) {
        self.name = name
        self.version = version
        self.channel = channel
        self.registryURL = registryURL
        self.description = description
        self.capGroups = capGroups
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `registry_url` is required-but-nullable on the wire.
        // Missing key (vs. null value) means the cartridge SDK
        // emitting this manifest predates the registry-aware
        // schema; refuse to accept it.
        guard c.contains(.registryURL) else {
            throw DecodingError.keyNotFound(
                CodingKeys.registryURL,
                DecodingError.Context(
                    codingPath: c.codingPath,
                    debugDescription:
                        "Manifest is missing required `registry_url` field. "
                        + "It must be present, with value null for dev builds or "
                        + "a URL string for registry builds."
                )
            )
        }
        self.name = try c.decode(String.self, forKey: .name)
        self.version = try c.decode(String.self, forKey: .version)
        self.channel = try c.decode(String.self, forKey: .channel)
        self.registryURL = try c.decode(String?.self, forKey: .registryURL)
        self.description = try c.decode(String.self, forKey: .description)
        self.capGroups = try c.decode([CapGroup].self, forKey: .capGroups)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(version, forKey: .version)
        try c.encode(channel, forKey: .channel)
        // Always emit `registry_url` — even null is explicit so the
        // decoder's "required-but-nullable" check passes round-trip.
        try c.encode(registryURL, forKey: .registryURL)
        try c.encode(description, forKey: .description)
        try c.encode(capGroups, forKey: .capGroups)
    }

    /// Returns all caps from all cap groups.
    public func allCaps() -> [CapDefinition] {
        var result: [CapDefinition] = []
        for group in capGroups {
            result.append(contentsOf: group.caps)
        }
        return result
    }
}

// MARK: - CartridgeRuntime

/// Cartridge-side runtime for CBOR protocol communication.
///
/// Cartridges create a runtime, register handlers for their caps, then call `run()`.
/// The runtime handles all I/O mechanics:
/// - HELLO handshake for limit negotiation (includes manifest in response)
/// - Frame encoding/decoding
/// - Request routing to handlers
/// - Streaming response support
/// - HEARTBEAT health monitoring
/// - Bidirectional peer invocation (cartridge can call host caps)
///
/// **Multiplexed execution**: Multiple requests can be processed concurrently.
/// Each request handler runs in its own thread, allowing the runtime to:
/// - Respond to heartbeats while handlers are running
/// - Accept new requests while previous ones are still processing
/// - Route response frames to handlers that invoked peer caps
///
/// **This is the ONLY supported way for cartridges to communicate with the host.**
/// The manifest MUST be provided - cartridges without a manifest will fail handshake.
@available(macOS 10.15.4, iOS 13.4, *)
/// Shared handle for dynamic concurrency capacity adjustment.
///
/// Cartridges receive this via `CartridgeRuntime.capacityHandle()` and can call
/// `set(_:)` at any time to adjust how many concurrent requests the runtime
/// will dispatch to handlers.
public final class CapacityHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int

    init(_ initial: Int) {
        _value = initial
    }

    /// Set the concurrency capacity. 0 means unlimited.
    public func set(_ n: Int) {
        lock.lock()
        _value = n
        lock.unlock()
    }

    /// Get the current capacity. 0 means unlimited.
    public func get() -> Int {
        lock.lock()
        let v = _value
        lock.unlock()
        return v
    }
}

public final class CartridgeRuntime: @unchecked Sendable {

    // MARK: - Properties

    private var handlers: [String: OpFactory] = [:]
    private let handlersLock = NSLock()

    private var limits = Limits()

    /// Cartridge manifest JSON data - sent in HELLO response.
    /// This is REQUIRED - cartridges must provide their manifest.
    let manifestData: Data

    /// Parsed manifest for CLI mode support.
    /// Contains cap definitions with command names and argument sources.
    let parsedManifest: Manifest?

    /// Concurrency capacity: 0 = unlimited, N = max N concurrent handlers.
    private let capacity = CapacityHandle(0)

    // MARK: - Initialization

    /// Create a cartridge runtime with the required manifest.
    ///
    /// The manifest is JSON-encoded cartridge metadata including:
    /// - name: Cartridge name
    /// - version: Cartridge version
    /// - caps: Array of capability definitions with args and sources
    ///
    /// This manifest is sent in the HELLO response to the host (CBOR mode)
    /// and used for CLI argument parsing (CLI mode).
    /// **Cartridges MUST provide a manifest - there is no fallback.**
    ///
    /// The runtime automatically registers:
    /// - CAP_IDENTITY handler (mandatory) - passes input through unchanged
    /// - CAP_DISCARD handler (standard, optional) - consumes input, produces void
    ///
    /// - Parameter manifest: JSON-encoded manifest data
    public init(manifest: Data) {
        self.manifestData = manifest
        // Parse manifest for CLI mode support
        self.parsedManifest = try? JSONDecoder().decode(Manifest.self, from: manifest)

        // FAIL HARD if manifest doesn't declare CAP_IDENTITY
        // Cartridges MUST explicitly declare all caps they provide - no fallbacks
        if let parsed = self.parsedManifest {
            // Check using URN conformance, not string equality
            // CAP_IDENTITY ("cap:") can be declared as "cap:" or "cap:in=media:;out=media:"
            var hasIdentity = false
            if let identityUrn = try? CSCapUrn.fromString(CSCapIdentity) {
                hasIdentity = parsed.allCaps().contains { cap in
                    if let capUrn = try? CSCapUrn.fromString(cap.urn) {
                        // Check if the cap URN conforms to CAP_IDENTITY (is identity or more specific)
                        return (try? capUrn.conforms(to: identityUrn)) == true ||
                               (try? identityUrn.conforms(to: capUrn)) == true
                    }
                    return false
                }
            }
            precondition(hasIdentity, "Manifest validation failed - cartridge MUST declare CAP_IDENTITY (\(CSCapIdentity))")
        }

        // Auto-register standard capability handlers
        autoRegisterStandardCaps()
    }

    /// Create a cartridge runtime with manifest JSON string.
    /// - Parameter manifestJSON: JSON string of the manifest
    public convenience init(manifestJSON: String) {
        guard let data = manifestJSON.data(using: .utf8) else {
            fatalError("Failed to encode manifest JSON as UTF-8")
        }
        self.init(manifest: data)
    }

    /// Auto-register standard capability handlers.
    /// Called during initialization to provide mandatory and optional standard caps.
    private func autoRegisterStandardCaps() {
        // CAP_IDENTITY: "cap:in=media:;out=media:" (mandatory)
        if findHandler(capUrn: CSCapIdentity) == nil {
            register_op_type(capUrn: CSCapIdentity, make: IdentityOp.init)
        }
        // CAP_DISCARD: "cap:in=media:;out=media:void" (standard, optional)
        if findHandler(capUrn: CSCapDiscard) == nil {
            register_op_type(capUrn: CSCapDiscard, make: DiscardOp.init)
        }
        // CAP_ADAPTER_SELECTION: content inspection adapter (standard, optional)
        if findHandler(capUrn: CSCapAdapterSelection) == nil {
            register_op_type(capUrn: CSCapAdapterSelection, make: AdapterSelectionOp.init)
        }
    }

    // MARK: - Capacity

    /// Set the maximum number of concurrent handler invocations.
    ///
    /// When set to N > 0, the runtime queues incoming requests beyond N active
    /// handlers. Queued requests receive a LOG frame with `level="queued"` so the
    /// pipeline's activity timeout pauses for that body.
    ///
    /// - `0` — unlimited (default)
    /// - `1` — serial execution (e.g., mlxcartridge with single model loaded)
    /// - `N` — up to N concurrent handlers
    public func setCapacity(_ n: Int) {
        capacity.set(n)
    }

    /// Get a handle to the concurrency capacity for dynamic adjustment.
    public func capacityHandle() -> CapacityHandle {
        return capacity
    }

    // MARK: - Handler Registration

    /// Register an Op factory for a cap URN.
    /// The factory creates a fresh AnyOp<Void> per invocation.
    public func register_op(capUrn: String, factory: @escaping OpFactory) {
        handlersLock.lock()
        handlers[capUrn] = factory
        handlersLock.unlock()
    }

    /// Convenience: register an Op type for a cap URN using a no-arg factory closure.
    /// Call as: register_op_type(capUrn: "cap:...", make: { MyOp() })
    /// Or shorthand: register_op_type(capUrn: "cap:...", make: MyOp.init)
    public func register_op_type<T: Op>(capUrn: String, make: @escaping @Sendable () -> T) where T.Output == Void {
        register_op(capUrn: capUrn, factory: { AnyOp(make()) })
    }

    /// Find an Op factory for a cap URN.
    ///
    /// Uses `isDispatchable(provider, request)` to find handlers that can
    /// legally handle the request, then ranks by specificity.
    ///
    /// Ranking prefers:
    /// 1. Equivalent matches (distance 0)
    /// 2. More specific providers (positive distance) - refinements
    /// 3. More generic providers (negative distance) - fallbacks
    func findHandler(capUrn: String) -> OpFactory? {
        handlersLock.lock()
        defer { handlersLock.unlock() }

        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else {
            return nil
        }

        let requestSpecificity = Int(requestUrn.specificity())
        var best: (factory: OpFactory, signedDistance: Int)? = nil

        for (registeredCapStr, factory) in handlers {
            guard let registeredUrn = try? CSCapUrn.fromString(registeredCapStr) else {
                continue
            }

            if registeredUrn.isDispatchable(requestUrn) {
                let specificity = Int(registeredUrn.specificity())
                let signedDistance = specificity - requestSpecificity

                let dominated: Bool
                if let currentBest = best {
                    // Current best dominates if:
                    // - best is non-negative and candidate is negative
                    // - OR both same sign and best has smaller abs distance
                    if currentBest.signedDistance >= 0 && signedDistance < 0 {
                        dominated = true
                    } else if currentBest.signedDistance < 0 && signedDistance >= 0 {
                        dominated = false
                    } else {
                        dominated = abs(currentBest.signedDistance) <= abs(signedDistance)
                    }
                } else {
                    dominated = false
                }

                if !dominated {
                    best = (factory, signedDistance)
                }
            }
        }

        return best?.factory
    }

    // MARK: - Main Run Loop

    /// Run the cartridge runtime.
    ///
    /// **Mode Detection**:
    /// - No CLI arguments: Cartridge CBOR mode (stdin/stdout binary frames)
    /// - Any CLI arguments: CLI mode (parse args from cap definitions)
    ///
    /// **CLI Mode**:
    /// - `manifest` subcommand: output manifest JSON
    /// - `<command>` subcommand: find cap by command, parse args, invoke handler
    /// - `--help`: show available subcommands
    ///
    /// **Cartridge CBOR Mode** (no CLI args):
    /// 1. Receive HELLO from host
    /// 2. Send HELLO back with manifest (handshake)
    /// 3. Main loop reads frames, dispatches handlers
    /// 4. Exit when stdin closes
    ///
    /// - Throws: CartridgeRuntimeError on fatal errors
    public func run() throws {
        let args = CommandLine.arguments

        // No CLI arguments at all → Cartridge CBOR mode
        if args.count == 1 {
            try runCborMode()
            return
        }

        // Any CLI arguments → CLI mode
        // For CLI mode, we need to bridge async runCliMode to sync run()
        // Use a simple blocking approach with explicit Sendable conformance

        // Create a container class marked as @unchecked Sendable (safe because we use locks)
        final class ResultContainer: @unchecked Sendable {
            private let lock = NSLock()
            private var _result: Result<Void, Error>?

            func set(_ result: Result<Void, Error>) {
                lock.lock()
                _result = result
                lock.unlock()
            }

            func get() -> Result<Void, Error>? {
                lock.lock()
                defer { lock.unlock() }
                return _result
            }
        }

        let container = ResultContainer()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached { [container, semaphore] in
            let result: Result<Void, Error>
            do {
                try self.runCliMode(args)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            container.set(result)
            semaphore.signal()
        }

        semaphore.wait()

        switch container.get() {
        case .success:
            return
        case .failure(let error):
            throw error
        case .none:
            throw CartridgeRuntimeError.cliError("CLI mode failed to complete")
        }
    }

    // MARK: - CLI Mode

    /// Run in CLI mode - parse arguments and invoke handler.
    private func runCliMode(_ args: [String]) throws {
        guard let manifest = parsedManifest else {
            throw CartridgeRuntimeError.manifestError("Failed to parse manifest for CLI mode")
        }

        // Handle --help at top level
        if args.count == 2 && (args[1] == "--help" || args[1] == "-h") {
            printHelp(manifest: manifest)
            return
        }

        let subcommand = args[1]

        // Special subcommand: manifest
        if subcommand == "manifest" {
            // Output the raw manifest JSON to stdout
            FileHandle.standardOutput.write(manifestData)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        // Find cap by command name
        guard let cap = findCapByCommand(manifest: manifest, commandName: subcommand) else {
            throw CartridgeRuntimeError.unknownSubcommand("Unknown command '\(subcommand)'. Run with --help to see available commands.")
        }

        // Handle --help for specific command
        if args.count == 3 && (args[2] == "--help" || args[2] == "-h") {
            printCapHelp(cap: cap)
            return
        }

        // Find Op factory
        guard let factory = findHandler(capUrn: cap.urn) else {
            throw CartridgeRuntimeError.noHandler("No handler registered for cap '\(cap.urn)'")
        }

        // Build raw CBOR arguments payload (file-path values still raw strings).
        let cliArgs = Array(args.dropFirst(2))
        let rawPayload = try buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // CLI-mode foreach iteration. If any file-path arg with is_sequence=false
        // resolved to multiple files, this returns one per-iteration payload per
        // resolved file. Otherwise it returns the single original payload.
        let iterations = try buildCliForeachIterations(rawPayload: rawPayload, cap: cap)
        for perIter in iterations {
            let payload = try extractEffectivePayload(payload: perIter, contentType: "application/cbor", cap: cap, isCliMode: true)
            try dispatchCliPayload(cap: cap, factory: factory, payload: payload)
        }
    }

    /// Dispatch one CLI-mode invocation: take the (already file-path-resolved)
    /// CBOR arguments payload, build input frames, and run the handler.
    ///
    /// Mirrors capdag/src/bifaci/cartridge_runtime.rs::dispatch_cli_payload.
    private func dispatchCliPayload(cap: CapDefinition, factory: OpFactory, payload: Data) throws {
        let (stream, continuation) = AsyncStream<Frame>.makeStream()
        let requestId = MessageId.newUUID()

        if !payload.isEmpty {
            if let cborValue = try? CBOR.decode([UInt8](payload)),
               case .array(let arguments) = cborValue {
                for (i, arg) in arguments.enumerated() {
                    guard case .map(let argMap) = arg else { continue }

                    var mediaUrn: String?
                    var value: CBOR?
                    for (key, val) in argMap {
                        if case .utf8String(let keyStr) = key {
                            if keyStr == "media_urn", case .utf8String(let urnStr) = val { mediaUrn = urnStr }
                            else if keyStr == "value" { value = val }
                        }
                    }
                    guard let mediaUrn = mediaUrn, let value = value else { continue }

                    let streamId = "arg-\(i)"
                    continuation.yield(Frame.streamStart(reqId: requestId, streamId: streamId, mediaUrn: mediaUrn))

                    let cborBytes = Data(value.encode())
                    let checksum = Frame.computeChecksum(cborBytes)
                    continuation.yield(Frame.chunk(
                        reqId: requestId, streamId: streamId, seq: 0,
                        payload: cborBytes, chunkIndex: 0, checksum: checksum
                    ))

                    continuation.yield(Frame.streamEnd(reqId: requestId, streamId: streamId, chunkCount: 1))
                }
            }
        }

        continuation.yield(Frame.end(id: requestId))
        continuation.finish()

        // Collect all frames synchronously using DispatchGroup.
        final class FrameCollector: @unchecked Sendable {
            var frames: [Frame] = []
            let lock = NSLock()
            func add(_ frame: Frame) { lock.lock(); frames.append(frame); lock.unlock() }
            func getAll() -> [Frame] { lock.lock(); defer { lock.unlock() }; return frames }
        }
        let collector = FrameCollector()
        let group = DispatchGroup()
        group.enter()
        Task.detached {
            for await frame in stream { collector.add(frame) }
            group.leave()
        }
        group.wait()
        let allFrames = collector.getAll()

        var frameIndex = 0
        let frameIterator = AnyIterator<Frame> {
            guard frameIndex < allFrames.count else { return nil }
            let frame = allFrames[frameIndex]
            frameIndex += 1
            return frame
        }

        // Demux frames into InputPackage
        let inputPackage = demuxMultiStream(frameIterator: frameIterator)

        // Create CLI-mode OutputStream (writes to stdout)
        let cliSender = CliFrameSender()
        let outputStream = OutputStream(
            sender: cliSender,
            streamId: "cli-output",
            mediaUrn: "media:", // CLI outputs raw bytes
            requestId: requestId,
            routingId: nil,
            maxChunk: DEFAULT_MAX_CHUNK
        )

        // Create no-op peer invoker (CLI mode doesn't support peer calls)
        let peer = NoPeerInvoker()

        // Invoke Op handler — dispatchOp closes output stream on success
        let op = factory()
        try dispatchOp(op: op, input: inputPackage, output: outputStream, peer: peer)
    }

    /// Find a cap by its command name (the CLI subcommand).
    private func findCapByCommand(manifest: Manifest, commandName: String) -> CapDefinition? {
        return manifest.allCaps().first { $0.command == commandName }
    }

    /// Build the raw CBOR arguments payload from CLI args.
    /// Internal for testing purposes.
    func buildPayloadFromCli(cap: CapDefinition, cliArgs: [String]) throws -> Data {
        var arguments: [CapArgumentValue] = []

        // Check for stdin data if cap accepts stdin
        let stdinData: Data?
        if cap.acceptsStdin() {
            stdinData = try readStdinIfAvailable()
        } else {
            stdinData = nil
        }

        // Process each argument definition. File-path values stay as raw
        // path/glob strings here — file reading and glob expansion happen
        // later in extractEffectivePayload (after CLI-mode foreach iteration
        // via buildCliForeachIterations).
        for argDef in cap.args {
            let (value, cameFromStdin) = try extractArgValue(argDef: argDef, cliArgs: cliArgs, stdinData: stdinData)

            if let v = value {
                // Determine media_urn: if value came from stdin source, use stdin's media_urn.
                // Otherwise use arg's media_urn as-is (file-path conversion happens later).
                var mediaUrn = argDef.mediaUrn
                if cameFromStdin {
                    for source in argDef.sources {
                        if case .stdin(let stdinMediaUrn) = source {
                            mediaUrn = stdinMediaUrn
                            break
                        }
                    }
                }
                arguments.append(CapArgumentValue(mediaUrn: mediaUrn, value: v))
            } else if argDef.required {
                let sources = argDef.sources.map { source -> String in
                    switch source {
                    case .cliFlag(let flag): return flag
                    case .positional(let pos): return "<pos \(pos)>"
                    case .stdin(_): return "<stdin>"
                    }
                }.joined(separator: " or ")
                throw CartridgeRuntimeError.missingArgument("Required argument '\(argDef.mediaUrn)' not provided. Use: \(sources)")
            }
        }

        // If no arguments are defined but stdin data exists, use it as raw payload.
        if cap.args.isEmpty {
            if let stdin = stdinData { return stdin }
            return Data()
        }

        // Build CBOR arguments array (same format as CBOR mode).
        if !arguments.isEmpty {
            var cborArgs: [CBOR] = []
            for arg in arguments {
                let argMap: CBOR = .map([
                    .utf8String("media_urn"): .utf8String(arg.mediaUrn),
                    .utf8String("value"): .byteString([UInt8](arg.value))
                ])
                cborArgs.append(argMap)
            }
            let cborArray = CBOR.array(cborArgs)
            return Data(cborArray.encode())
        }

        return Data()
    }

    /// Extract a single argument value from CLI args or stdin.
    ///
    /// Mirrors capdag/src/bifaci/cartridge_runtime.rs::extract_arg_value.
    ///
    /// Returns (value, cameFromStdin). RAW values only — file-path
    /// auto-conversion happens later in extractEffectivePayload, after
    /// CLI-mode foreach iteration.
    func extractArgValue(argDef: CapArg, cliArgs: [String], stdinData: Data?) throws -> (Data?, Bool) {
        for source in argDef.sources {
            switch source {
            case .cliFlag(let flag):
                if let value = getCliFlagValue(args: cliArgs, flag: flag) {
                    return (Data(value.utf8), false)
                }
            case .positional(let position):
                let positional = getPositionalArgs(args: cliArgs)
                if position < positional.count {
                    return (Data(positional[position].utf8), false)
                }
            case .stdin(_):
                if let data = stdinData {
                    return (data, true)
                }
            }
        }

        if let defaultValue = argDef.defaultValue {
            return (try defaultValue.lexicalBytes(), false)
        }

        return (nil, false)
    }

    /// Get value for a CLI flag (e.g., --model "value")
    private func getCliFlagValue(args: [String], flag: String) -> String? {
        var iter = args.makeIterator()
        while let arg = iter.next() {
            if arg == flag {
                return iter.next()
            }
            // Handle --flag=value format
            if arg.hasPrefix("\(flag)=") {
                return String(arg.dropFirst(flag.count + 1))
            }
        }
        return nil
    }

    /// Get positional arguments (non-flag arguments)
    private func getPositionalArgs(args: [String]) -> [String] {
        var positional: [String] = []
        var skipNext = false

        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if arg.hasPrefix("-") {
                // This is a flag - skip its value too if not using =
                if !arg.contains("=") {
                    skipNext = true
                }
            } else {
                positional.append(arg)
            }
        }
        return positional
    }

    /// Read stdin if data is available (non-blocking check).
    private func readStdinIfAvailable() throws -> Data? {
        let stdin = FileHandle.standardInput

        // Check if stdin is a terminal (interactive)
        if isatty(stdin.fileDescriptor) != 0 {
            return nil
        }

        // Non-blocking check: use poll() with 0 timeout to see if data is ready
        var pollfd = Darwin.pollfd(fd: stdin.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let pollResult = Darwin.poll(&pollfd, 1, 0)  // 0 timeout = non-blocking

        if pollResult < 0 {
            throw CartridgeRuntimeError.ioError("poll() failed")
        }

        // No data ready - return nil immediately without blocking
        if pollResult == 0 || (pollfd.revents & Int16(POLLIN)) == 0 {
            return nil
        }

        // Data is ready - read it
        let data = stdin.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    /// Build payload from streaming reader (testable version).
    ///
    /// This simulates the CBOR chunked request flow for CLI piped stdin:
    /// - Pure binary chunks from reader
    /// - Accumulated in chunks (respecting maxChunk size)
    /// - Built into CBOR arguments array (same format as CBOR mode)
    ///
    /// This makes all 4 modes use the SAME payload format:
    /// - CLI file path → read file → payload
    /// - CLI piped binary → chunk reader → payload
    /// - CBOR chunked → payload
    /// - CBOR file path → auto-convert → payload
    func buildPayloadFromStreamingReader(cap: CapDefinition, reader: Foundation.InputStream, maxChunk: Int) throws -> Data {
        // Accumulate chunks
        var chunks: [Data] = []
        var totalBytes = 0

        reader.open()
        defer { reader.close() }

        while reader.hasBytesAvailable {
            var buffer = [UInt8](repeating: 0, count: maxChunk)
            let bytesRead = reader.read(&buffer, maxLength: maxChunk)
            if bytesRead < 0 {
                throw CartridgeRuntimeError.ioError("Stream read error: \(reader.streamError?.localizedDescription ?? "unknown")")
            }
            if bytesRead == 0 {
                break
            }
            let chunk = Data(buffer.prefix(bytesRead))
            chunks.append(chunk)
            totalBytes += bytesRead
        }

        // Concatenate chunks
        var completePayload = Data()
        for chunk in chunks {
            completePayload.append(chunk)
        }

        // Build CBOR arguments array (same format as CBOR mode)
        let capUrn = try CSCapUrn.fromString(cap.urn)
        let expectedMediaUrn = capUrn.inSpec

        let arg = CapArgumentValue(mediaUrn: expectedMediaUrn, value: completePayload)

        // Encode as CBOR array
        let cborArgs: [CBOR] = [
            CBOR.map([
                CBOR.utf8String("media_urn"): CBOR.utf8String(arg.mediaUrn),
                CBOR.utf8String("value"): CBOR.byteString([UInt8](arg.value)),
            ])
        ]

        let cborArray = CBOR.array(cborArgs)
        return Data(cborArray.encode())
    }

    /// Print help message showing all available subcommands.
    private func printHelp(manifest: Manifest) {
        let stderr = FileHandle.standardError
        stderr.write(Data("\(manifest.name) v\(manifest.version)\n".utf8))
        stderr.write(Data("\(manifest.description)\n\n".utf8))
        stderr.write(Data("USAGE:\n".utf8))
        stderr.write(Data("    \(manifest.name.lowercased()) <COMMAND> [OPTIONS]\n\n".utf8))
        stderr.write(Data("COMMANDS:\n".utf8))
        stderr.write(Data("    manifest    Output the cartridge manifest as JSON\n".utf8))

        for cap in manifest.allCaps() {
            let desc = cap.capDescription ?? cap.title
            let paddedCommand = cap.command.padding(toLength: 12, withPad: " ", startingAt: 0)
            let line = "    \(paddedCommand)\(desc)\n"
            stderr.write(Data(line.utf8))
        }

        stderr.write(Data("\nRun '\(manifest.name.lowercased()) <COMMAND> --help' for more information on a command.\n".utf8))
    }

    /// Print help for a specific cap.
    private func printCapHelp(cap: CapDefinition) {
        let stderr = FileHandle.standardError
        stderr.write(Data("\(cap.title)\n".utf8))
        if let desc = cap.capDescription {
            stderr.write(Data("\(desc)\n".utf8))
        }
        stderr.write(Data("\nUSAGE:\n".utf8))
        stderr.write(Data("    cartridge \(cap.command) [OPTIONS]\n\n".utf8))

        if !cap.args.isEmpty {
            stderr.write(Data("OPTIONS:\n".utf8))
            for arg in cap.args {
                let requiredStr = arg.required ? " (required)" : ""
                let desc = arg.argDescription ?? ""

                for source in arg.sources {
                    switch source {
                    case .cliFlag(let flag):
                        let paddedFlag = flag.padding(toLength: 16, withPad: " ", startingAt: 0)
                        let line = "    \(paddedFlag)\(desc)\(requiredStr)\n"
                        stderr.write(Data(line.utf8))
                    case .positional(let pos):
                        let argName = "<arg\(pos)>"
                        let paddedArg = argName.padding(toLength: 16, withPad: " ", startingAt: 0)
                        let line = "    \(paddedArg)\(desc)\(requiredStr)\n"
                        stderr.write(Data(line.utf8))
                    case .stdin(_):
                        let line = "    <stdin>          \(desc)\(requiredStr)\n"
                        stderr.write(Data(line.utf8))
                    }
                }
            }
        }
    }

    // MARK: - CBOR Mode

    /// Run in CBOR mode - binary protocol over stdin/stdout.
    private func runCborMode() throws {
        let stdinHandle = FileHandle.standardInput

        // Duplicate stdout so CBOR frame I/O is immune to anything that
        // writes to or closes the original FD 1 (e.g. Metal shader
        // compilation in MLX, Swift print(), C printf()).  The duplicated FD
        // points to the same pipe but lives at a different descriptor number.
        let safeFd = dup(STDOUT_FILENO)
        guard safeFd >= 0 else {
            throw CartridgeRuntimeError.ioError("dup(STDOUT_FILENO) failed: \(String(cString: strerror(errno)))")
        }
        // Redirect FD 1 → stderr so any stray stdout writes end up in the
        // log instead of injecting non-CBOR bytes into the frame pipe.
        dup2(STDERR_FILENO, STDOUT_FILENO)
        let stdoutHandle = FileHandle(fileDescriptor: safeFd, closeOnDealloc: true)

        let frameReader = FrameReader(handle: stdinHandle, limits: limits)
        let frameWriter = FrameWriter(handle: stdoutHandle, limits: limits)
        let writerLock = NSLock()
        let seqAssigner = SeqAssigner()

        // Perform handshake
        try performHandshake(reader: frameReader, writer: frameWriter)

        // Shared output sender — all outbound frames go through this.
        // Applies SeqAssigner and cleans up flow tracking on terminal frames.
        let outputSender = ChannelFrameSender(writer: frameWriter, writerLock: writerLock, seqAssigner: seqAssigner)

        // Track pending peer requests (cartridge invoking host caps)
        // Maps request ID to AsyncStream.Continuation for forwarding response frames
        let pendingPeerRequests = NSMutableDictionary()
        let pendingPeerRequestsLock = NSLock()

        // Track pending heartbeats (cartridge-initiated health probes)
        // Prevents infinite ping-pong: only respond to heartbeats we didn't send
        let pendingHeartbeats = NSMutableSet()
        let pendingHeartbeatsLock = NSLock()

        // Track pending incoming requests (host invoking cartridge caps)
        // Maps request ID to (capUrn, continuation) - forwards request frames to handler.
        // Created on REQ even for queued requests, so frames accumulate until
        // the handler thread is spawned and the demux drains them.
        struct PendingIncomingRequest {
            let capUrn: String
            let continuation: AsyncStream<Frame>.Continuation
        }
        var pendingIncoming: [MessageId: PendingIncomingRequest] = [:]
        let pendingIncomingLock = NSLock()

        // Queue for requests waiting for a handler slot.
        struct QueuedRequest {
            let factory: OpFactory
            let capUrn: String
            let routingId: MessageId?
            let requestId: MessageId
            let outputMediaUrn: String
            let stream: AsyncStream<Frame>
        }
        var requestQueue: [QueuedRequest] = []
        var runningHandlerCount = 0
        var cancelledRequests = Set<MessageId>()
        var handlerRoutingIds: [MessageId: MessageId?] = [:]

        // Event queue: both incoming frames and handler-done signals arrive here.
        // This unblocks the main loop when a handler finishes even if no frames
        // are arriving on stdin — without this, queued requests would never be
        // dequeued after all input frames have been sent.
        enum LoopEvent {
            case frame(Frame)
            case readError(Error)
            case eof
            case handlerDone(MessageId)
        }
        let eventQueue = BlockingQueue<LoopEvent>()

        // Spawn reader thread: reads frames from stdin and pushes to eventQueue.
        let readerEventQueue = eventQueue
        Thread.detachNewThread {
            while true {
                do {
                    guard let frame = try frameReader.read() else {
                        readerEventQueue.push(.eof)
                        return
                    }
                    readerEventQueue.push(.frame(frame))
                } catch {
                    readerEventQueue.push(.readError(error))
                    return
                }
            }
        }

        // Helper: spawn a handler thread for a request.
        func spawnHandler(
            requestId: MessageId,
            capUrn: String,
            routingId: MessageId?,
            outputMediaUrn: String,
            factory: @escaping OpFactory,
            stream: AsyncStream<Frame>,
            outputSender: any FrameSender,
            frameWriter: FrameWriter,
            writerLock: NSLock,
            seqAssigner: SeqAssigner,
            pendingPeerRequests: NSMutableDictionary,
            pendingPeerRequestsLock: NSLock,
            maxChunk: Int,
            eventQueue: BlockingQueue<LoopEvent>
        ) {
            Thread.detachNewThread {
                fputs("[CartridgeRuntime] handler started: cap='\(capUrn)' rid=\(requestId)\n", stderr)
                let framesQueue = BlockingQueue<Frame>()

                Task {
                    for await frame in stream {
                        framesQueue.enqueue(frame)
                    }
                    framesQueue.finish()
                }

                let frameIterator = AnyIterator<Frame> {
                    return framesQueue.dequeue()
                }

                let inputPackage = demuxMultiStream(frameIterator: frameIterator)

                let responseStreamId = UUID().uuidString
                let outputStream = OutputStream(
                    sender: outputSender,
                    streamId: responseStreamId,
                    mediaUrn: outputMediaUrn,
                    requestId: requestId,
                    routingId: routingId,
                    maxChunk: maxChunk
                )

                let peer = PeerInvokerImpl(
                    writer: frameWriter,
                    writerLock: writerLock,
                    seqAssigner: seqAssigner,
                    pendingRequests: pendingPeerRequests,
                    pendingRequestsLock: pendingPeerRequestsLock,
                    originRequestId: requestId,
                    maxChunk: maxChunk
                )

                do {
                    let op = factory()
                    try dispatchOp(op: op, input: inputPackage, output: outputStream, peer: peer)

                    fputs("[CartridgeRuntime] handler completed OK: cap='\(capUrn)' rid=\(requestId)\n", stderr)
                    var endFrame = Frame.endOk(id: requestId, finalPayload: nil)
                    endFrame.routingId = routingId
                    try? outputSender.send(endFrame)
                } catch {
                    fputs("[CartridgeRuntime] handler FAILED: cap='\(capUrn)' rid=\(requestId) error=\(error)\n", stderr)
                    var errFrame = Frame.err(id: requestId, code: "HANDLER_ERROR", message: "\(error)")
                    errFrame.routingId = routingId
                    try? outputSender.send(errFrame)
                }

                // Notify the main loop that a handler slot is free.
                eventQueue.push(.handlerDone(requestId))
            }
        }

        // Main loop: dequeue events (frames or handler-done signals).
        mainLoop: while true {
            // Reap finished handlers and drain the queue into freed slots.
            runningHandlerCount = max(0, runningHandlerCount)

            // Drain queue: spawn handlers for queued requests that now have capacity.
            let cap = capacity.get()
            while !requestQueue.isEmpty && (cap == 0 || runningHandlerCount < cap) {
                let queued = requestQueue.removeFirst()

                fputs("[CartridgeRuntime] dequeuing request: cap='\(queued.capUrn)' rid=\(queued.requestId) remaining_queue=\(requestQueue.count)\n", stderr)

                // Notify the caller that this request has been dequeued and is
                // starting. The "dequeued" level is the counterpart to "queued":
                // on the pipeline side, ActivityTimer unpauses and resets the
                // timeout clock, and the stall tracker is touched.
                var dequeuedLog = Frame.log(
                    id: queued.requestId,
                    level: "dequeued",
                    message: "Request dequeued, handler starting"
                )
                dequeuedLog.routingId = queued.routingId
                try? outputSender.send(dequeuedLog)

                spawnHandler(
                    requestId: queued.requestId,
                    capUrn: queued.capUrn,
                    routingId: queued.routingId,
                    outputMediaUrn: queued.outputMediaUrn,
                    factory: queued.factory,
                    stream: queued.stream,
                    outputSender: outputSender,
                    frameWriter: frameWriter,
                    writerLock: writerLock,
                    seqAssigner: seqAssigner,
                    pendingPeerRequests: pendingPeerRequests,
                    pendingPeerRequestsLock: pendingPeerRequestsLock,
                    maxChunk: self.limits.maxChunk,
                    eventQueue: eventQueue
                )
                handlerRoutingIds[queued.requestId] = queued.routingId
                runningHandlerCount += 1
            }

            guard let event = eventQueue.dequeue() else {
                break // Queue finished (should not happen)
            }

            let frame: Frame
            switch event {
            case .handlerDone(let rid):
                runningHandlerCount -= 1
                if cancelledRequests.remove(rid) != nil {
                    let routingId = handlerRoutingIds.removeValue(forKey: rid) ?? nil
                    var err = Frame.err(id: rid, code: "CANCELLED", message: "Request cancelled")
                    err.routingId = routingId
                    try? outputSender.send(err)
                    fputs("[CartridgeRuntime] Cancelled handler finished, sent ERR: rid=\(rid)\n", stderr)
                } else {
                    handlerRoutingIds.removeValue(forKey: rid)
                }
                continue
            case .frame(let f):
                frame = f
            case .eof:
                break mainLoop
            case .readError(let error):
                throw CartridgeRuntimeError.ioError("\(error)")
            }

            switch frame.frameType {
            case .req:
                // Extract routing_id (XID) FIRST — all error paths must include it
                let routingIdForErrors = frame.routingId

                guard let capUrn = frame.cap else {
                    var err = Frame.err(id: frame.id, code: "INVALID_REQUEST", message: "Request missing cap URN")
                    err.routingId = routingIdForErrors
                    try? outputSender.send(err)
                    continue
                }

                let rawPayload = frame.payload ?? Data()

                // Protocol v2: REQ must have empty payload — arguments come as streams
                if !rawPayload.isEmpty {
                    var err = Frame.err(
                        id: frame.id,
                        code: "PROTOCOL_ERROR",
                        message: "REQ frame must have empty payload — use STREAM_START for arguments"
                    )
                    err.routingId = routingIdForErrors
                    try? outputSender.send(err)
                    continue
                }

                // Find Op factory (using pattern matching to support wildcards)
                guard let factory = findHandler(capUrn: capUrn) else {
                    var err = Frame.err(id: frame.id, code: "NO_HANDLER", message: "No handler registered for cap: \(capUrn)")
                    err.routingId = routingIdForErrors
                    try? outputSender.send(err)
                    continue
                }

                // Parse cap URN for output media type
                let cap: CSCapUrn
                do {
                    cap = try CSCapUrn.fromString(capUrn)
                } catch {
                    var err = Frame.err(id: frame.id, code: "INVALID_CAP_URN", message: "Failed to parse cap URN: \(error)")
                    err.routingId = routingIdForErrors
                    try? outputSender.send(err)
                    continue
                }

                // Create AsyncStream for forwarding frames to handler.
                // Always created immediately so subsequent frames are routed here
                // even if the handler isn't spawned yet (queued).
                let (stream, continuation) = AsyncStream<Frame>.makeStream()

                // Register pending request
                pendingIncomingLock.lock()
                pendingIncoming[frame.id] = PendingIncomingRequest(
                    capUrn: capUrn,
                    continuation: continuation
                )
                pendingIncomingLock.unlock()

                let requestId = frame.id
                let routingId = frame.routingId
                let outputMediaUrn = cap.getOutSpec()

                let cap2 = capacity.get()
                if cap2 > 0 && runningHandlerCount >= cap2 {
                    // At capacity — queue the request, send "queued" LOG back to caller.
                    let queuePos = requestQueue.count + 1
                    var logFrame = Frame.log(
                        id: requestId,
                        level: "queued",
                        message: "Request queued (position \(queuePos), \(runningHandlerCount) active)"
                    )
                    logFrame.routingId = routingId
                    try? outputSender.send(logFrame)

                    fputs("[CartridgeRuntime] request queued: cap='\(capUrn)' rid=\(requestId) queue_pos=\(queuePos)\n", stderr)

                    requestQueue.append(QueuedRequest(
                        factory: factory,
                        capUrn: capUrn,
                        routingId: routingId,
                        requestId: requestId,
                        outputMediaUrn: outputMediaUrn,
                        stream: stream
                    ))
                } else {
                    // Under capacity — spawn handler immediately.
                    spawnHandler(
                        requestId: requestId,
                        capUrn: capUrn,
                        routingId: routingId,
                        outputMediaUrn: outputMediaUrn,
                        factory: factory,
                        stream: stream,
                        outputSender: outputSender,
                        frameWriter: frameWriter,
                        writerLock: writerLock,
                        seqAssigner: seqAssigner,
                        pendingPeerRequests: pendingPeerRequests,
                        pendingPeerRequestsLock: pendingPeerRequestsLock,
                        maxChunk: self.limits.maxChunk,
                        eventQueue: eventQueue
                    )
                    handlerRoutingIds[requestId] = routingId
                    runningHandlerCount += 1
                }
                continue

            case .heartbeat:
                // Check if this is a response to a heartbeat we sent
                pendingHeartbeatsLock.lock()
                let isOurProbe = pendingHeartbeats.contains(frame.id)
                if isOurProbe {
                    pendingHeartbeats.remove(frame.id)
                }
                pendingHeartbeatsLock.unlock()

                if isOurProbe {
                    // Response to our health probe - host is alive, no action needed
                } else {
                    // Host-initiated heartbeat — respond with
                    // self-reported memory. `proc_pid_rusage(getpid())`
                    // works under the cartridge sandbox (verified in
                    // run 20260501-143945; sandbox blocks queries
                    // against *other* pids, not self). The host's
                    // stats pump combines this footprint with its own
                    // proc_pidinfo measurement and pushes the result
                    // to the Mac app via reverse-XPC.
                    var response = Frame.heartbeat(id: frame.id)
                    if let mem = getOwnMemoryMb() {
                        response.meta = [
                            "footprint_mb": .unsignedInt(mem.footprintMb),
                            "rss_mb": .unsignedInt(mem.rssMb)
                        ]
                    } else {
                        os_log(.error, log: cartridgeRuntimeLog,
                               "Cartridge pid %{public}d failed to self-sample memory (proc_pid_rusage returned non-zero) — heartbeat response will omit memory meta",
                               getpid())
                    }
                    try outputSender.send(response)
                }

            case .hello:
                // Unexpected HELLO after handshake - protocol error
                try outputSender.send(Frame.err(id: frame.id, code: "PROTOCOL_ERROR", message: "Unexpected HELLO after handshake"))

            // case .res: REMOVED - old single-response protocol no longer supported

            case .chunk:
                // Forward frame to appropriate stream

                // Check if this is a chunk for an incoming request
                pendingIncomingLock.lock()
                if let pendingReq = pendingIncoming[frame.id] {
                    pendingReq.continuation.yield(frame)
                    pendingIncomingLock.unlock()
                    continue
                }
                pendingIncomingLock.unlock()

                // Not an incoming request chunk - must be a peer response chunk
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                }
                pendingPeerRequestsLock.unlock()

            case .end:
                // Forward frame to appropriate stream and finish it

                // Check if this is the end of an incoming request
                pendingIncomingLock.lock()
                if let pendingReq = pendingIncoming.removeValue(forKey: frame.id) {
                    fputs("[CartridgeRuntime] END routed to active_request rid=\(frame.id)\n", stderr)
                    pendingReq.continuation.yield(frame)
                    pendingReq.continuation.finish()
                    pendingIncomingLock.unlock()
                    continue
                }
                pendingIncomingLock.unlock()

                // Not an incoming request end - must be a peer response end
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    fputs("[CartridgeRuntime] PEER_END received: peer_rid=\(frame.id)\n", stderr)
                    pending.continuation.yield(frame)
                    pending.continuation.finish()
                    pendingPeerRequests.removeObject(forKey: frame.id)
                } else {
                    fputs("[CartridgeRuntime] END for unknown rid=\(frame.id)\n", stderr)
                }
                pendingPeerRequestsLock.unlock()

            case .err:
                // Error frame from host - forward to pending peer request and finish stream
                fputs("[CartridgeRuntime] ERR received: rid=\(frame.id) code=\(frame.errorCode ?? "?") msg=\(frame.errorMessage ?? "?")\n", stderr)
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                    pending.continuation.finish()
                    pendingPeerRequests.removeObject(forKey: frame.id)
                }
                pendingPeerRequestsLock.unlock()

            case .log:
                // Log frames from peer responses — forward to the pending peer request
                // so demuxSingleStream delivers them as PeerResponseItem.log items.
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                }
                pendingPeerRequestsLock.unlock()

            case .streamStart:
                // Forward frame to appropriate stream

                // Check if this is for an incoming request
                pendingIncomingLock.lock()
                if let pendingReq = pendingIncoming[frame.id] {
                    pendingReq.continuation.yield(frame)
                    pendingIncomingLock.unlock()
                    continue
                }
                pendingIncomingLock.unlock()

                // Not an incoming request - must be a peer response stream
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                }
                pendingPeerRequestsLock.unlock()

            case .streamEnd:
                // Forward frame to appropriate stream

                // Check if this is for an incoming request
                pendingIncomingLock.lock()
                if let pendingReq = pendingIncoming[frame.id] {
                    pendingReq.continuation.yield(frame)
                    pendingIncomingLock.unlock()
                    continue
                }
                pendingIncomingLock.unlock()

                // Not an incoming request - must be a peer response stream
                pendingPeerRequestsLock.lock()
                if let pending = pendingPeerRequests[frame.id] as? PendingPeerRequest {
                    pending.continuation.yield(frame)
                }
                pendingPeerRequestsLock.unlock()

            case .cancel:
                let targetRid = frame.id
                fputs("[CartridgeRuntime] Cancel received: rid=\(targetRid) forceKill=\(frame.forceKill ?? false)\n", stderr)

                // Skip if already cancelled
                if cancelledRequests.contains(targetRid) {
                    continue
                }

                // Case 1: Queued — remove from queue and send ERR
                if let idx = requestQueue.firstIndex(where: { $0.requestId == targetRid }) {
                    let queued = requestQueue.remove(at: idx)
                    pendingIncomingLock.lock()
                    if let pending = pendingIncoming.removeValue(forKey: targetRid) {
                        pending.continuation.finish()
                    }
                    pendingIncomingLock.unlock()
                    var err = Frame.err(id: targetRid, code: "CANCELLED", message: "Request cancelled while queued")
                    err.routingId = queued.routingId
                    try? outputSender.send(err)
                    fputs("[CartridgeRuntime] Cancelled queued request: rid=\(targetRid)\n", stderr)
                    continue
                }

                // Case 2: In-flight handler — finish continuation (cooperative cancel)
                pendingIncomingLock.lock()
                if let pending = pendingIncoming.removeValue(forKey: targetRid) {
                    pendingIncomingLock.unlock()
                    // Finishing the continuation ends the handler's frame iterator → handler exits
                    pending.continuation.finish()
                    cancelledRequests.insert(targetRid)

                    // Cancel peer calls originating from this request
                    pendingPeerRequestsLock.lock()
                    var peerRidsToCancel: [MessageId] = []
                    for key in pendingPeerRequests.allKeys {
                        if let rid = key as? MessageId,
                           let pending = pendingPeerRequests[rid] as? PendingPeerRequest,
                           pending.originRequestId == targetRid {
                            peerRidsToCancel.append(rid)
                            pending.continuation.finish()
                        }
                    }
                    for rid in peerRidsToCancel {
                        pendingPeerRequests.removeObject(forKey: rid)
                        // Send Cancel for each peer call to the host
                        let cancel = Frame.cancel(targetRid: rid, forceKill: frame.forceKill ?? false)
                        try? outputSender.send(cancel)
                    }
                    pendingPeerRequestsLock.unlock()

                    fputs("[CartridgeRuntime] Cancelled in-flight request (cooperative): rid=\(targetRid)\n", stderr)
                } else {
                    pendingIncomingLock.unlock()
                    // Case 3: Unknown — ignore
                    fputs("[CartridgeRuntime] Cancel for unknown rid=\(targetRid) — ignoring\n", stderr)
                }

            case .relayNotify, .relayState:
                // Relay frame types should NEVER reach the cartridge runtime — they are
                // intercepted by the relay layer. If one arrives here, it's a
                // protocol violation.
                throw CartridgeRuntimeError.protocolError("Relay frame type \(frame.frameType) must not reach cartridge runtime")
            }
        }

        // Handlers run asynchronously via Task - they complete on their own
    }

    // MARK: - Handshake

    private func performHandshake(reader: FrameReader, writer: FrameWriter) throws {
        // Read host's HELLO first (host initiates)
        let theirFrame: Frame
        do {
            guard let f = try reader.read() else {
                throw CartridgeRuntimeError.handshakeFailed("Connection closed before HELLO")
            }
            theirFrame = f
        } catch let error as FrameError {
            throw CartridgeRuntimeError.handshakeFailed("\(error)")
        }

        guard theirFrame.frameType == .hello else {
            throw CartridgeRuntimeError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
        }

        // Protocol v2: All three limit fields are REQUIRED
        guard let theirMaxFrame = theirFrame.helloMaxFrame else {
            throw CartridgeRuntimeError.handshakeFailed("Protocol violation: HELLO missing max_frame")
        }
        guard let theirMaxChunk = theirFrame.helloMaxChunk else {
            throw CartridgeRuntimeError.handshakeFailed("Protocol violation: HELLO missing max_chunk")
        }
        guard let theirMaxReorderBuffer = theirFrame.helloMaxReorderBuffer else {
            throw CartridgeRuntimeError.handshakeFailed("Protocol violation: HELLO missing max_reorder_buffer (required in protocol v2)")
        }

        // Negotiate minimum of both sides
        let ourLimits = Limits()
        let negotiatedLimits = Limits(
            maxFrame: min(ourLimits.maxFrame, theirMaxFrame),
            maxChunk: min(ourLimits.maxChunk, theirMaxChunk),
            maxReorderBuffer: min(ourLimits.maxReorderBuffer, theirMaxReorderBuffer)
        )

        self.limits = negotiatedLimits

        // Send our HELLO with negotiated limits AND manifest
        // The manifest is REQUIRED - this is the ONLY way to communicate cartridge capabilities
        let ourHello = Frame.helloWithManifest(limits: negotiatedLimits, manifest: manifestData)
        do {
            try writer.write(ourHello)
        } catch {
            throw CartridgeRuntimeError.handshakeFailed("Failed to send HELLO: \(error)")
        }

        // Update reader/writer limits
        reader.setLimits(negotiatedLimits)
        writer.setLimits(negotiatedLimits)
    }

    // MARK: - Accessors

    /// Get the negotiated protocol limits
    public var negotiatedLimits: Limits {
        return limits
    }
}
