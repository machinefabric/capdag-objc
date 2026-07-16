import Foundation
@preconcurrency import SwiftCBOR

/// Protocol version. Version 3: credit-based per-stream flow control, unbounded
/// streams, terminal metadata on END (final progress rides in the terminal frame),
/// counted drops, handshake version enforcement. Version 2 handshakes are rejected.
public let CBOR_PROTOCOL_VERSION: UInt8 = 3

/// Default maximum frame size (3.5 MB) - safe margin below 3.75MB limit
/// Larger payloads automatically use CHUNK frames
public let DEFAULT_MAX_FRAME: Int = 3_670_016

/// Default maximum chunk size (256 KB)
public let DEFAULT_MAX_CHUNK: Int = 262_144

/// Default maximum reorder buffer size (per-flow frame count)
public let DEFAULT_MAX_REORDER_BUFFER: Int = 64

/// Default initial credit window per stream, in CHUNK frames.
/// A sender may emit this many CHUNKs per stream before it must wait for a
/// CREDIT grant. 32 chunks ≈ 8 MiB at the default max_chunk (256 KiB).
public let DEFAULT_INITIAL_CREDIT: UInt64 = 32

/// Hard limit for frame size (16 MB) - prevents memory exhaustion
public let MAX_FRAME_HARD_LIMIT: Int = 16 * 1024 * 1024

/// Frame type discriminator
public enum FrameType: UInt8, Sendable {
    /// Handshake frame for negotiating limits
    case hello = 0
    /// Request to invoke a cap
    case req = 1
    // res = 2 REMOVED - old single-response protocol no longer supported
    /// Streaming data chunk
    case chunk = 3
    /// Stream complete marker
    case end = 4
    /// Log/progress message
    case log = 5
    /// Error message
    case err = 6
    /// Health monitoring ping/pong - either side can send, receiver must respond with same ID
    case heartbeat = 7
    /// Announce new stream for a request (multiplexed streaming)
    case streamStart = 8
    /// End a specific stream (multiplexed streaming)
    case streamEnd = 9
    /// Relay capability advertisement (slave → master). Carries aggregate manifest + limits.
    case relayNotify = 10
    /// Relay host system resources + cap demands (master → slave). Carries opaque resource payload.
    case relayState = 11
    /// Cancel a specific in-flight request by RID. Carries optional force_kill flag.
    case cancel = 12
    /// Grant per-stream flow-control credit (in CHUNK units) to the sender of a
    /// stream. Non-flow: bypasses seq assignment and reorder buffers, and is
    /// forwarded end-to-end by intermediaries (never originated or absorbed).
    case credit = 13
}

/// Message ID - either a 16-byte UUID or a simple integer
public enum MessageId: Equatable, Hashable, Sendable {
    case uuid(Data)
    case uint(UInt64)

    /// Create a new random UUID message ID
    public static func newUUID() -> MessageId {
        return .uuid(UUID().data)
    }

    /// Create from a UUID
    public init(uuid: UUID) {
        self = .uuid(uuid.data)
    }

    /// Create from a UUID string
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self = .uuid(uuid.data)
    }

    /// Convert to UUID if this is a UUID
    public var uuid: UUID? {
        if case .uuid(let data) = self, data.count == 16 {
            return UUID(data: data)
        }
        return nil
    }

    /// Get the UUID string if this is a UUID
    public var uuidString: String? {
        return uuid?.uuidString
    }

    /// Get the byte representation of this message ID
    /// - For UUID: returns 16 bytes
    /// - For Uint: returns 8 bytes (big-endian)
    public func asBytes() -> Data {
        switch self {
        case .uuid(let data):
            return data
        case .uint(let n):
            var bytes = Data(count: 8)
            bytes[0] = UInt8((n >> 56) & 0xFF)
            bytes[1] = UInt8((n >> 48) & 0xFF)
            bytes[2] = UInt8((n >> 40) & 0xFF)
            bytes[3] = UInt8((n >> 32) & 0xFF)
            bytes[4] = UInt8((n >> 24) & 0xFF)
            bytes[5] = UInt8((n >> 16) & 0xFF)
            bytes[6] = UInt8((n >> 8) & 0xFF)
            bytes[7] = UInt8(n & 0xFF)
            return bytes
        }
    }
}

extension MessageId: CustomStringConvertible {
    public var description: String {
        switch self {
        case .uuid(let data):
            if let uuid = UUID(data: data) {
                return uuid.uuidString
            }
            return "<invalid-uuid>"
        case .uint(let n):
            return "\(n)"
        }
    }
}

/// Negotiated protocol limits
public struct Limits: Sendable {
    /// Maximum frame size in bytes
    public var maxFrame: Int
    /// Maximum chunk payload size in bytes
    public var maxChunk: Int
    /// Maximum reorder buffer size per flow (frame count)
    public var maxReorderBuffer: Int
    /// Initial per-stream credit window in CHUNK frames
    public var initialCredit: UInt64

    public init(maxFrame: Int = DEFAULT_MAX_FRAME, maxChunk: Int = DEFAULT_MAX_CHUNK, maxReorderBuffer: Int = DEFAULT_MAX_REORDER_BUFFER, initialCredit: UInt64 = DEFAULT_INITIAL_CREDIT) {
        self.maxFrame = maxFrame
        self.maxChunk = maxChunk
        self.maxReorderBuffer = maxReorderBuffer
        self.initialCredit = initialCredit
    }

    /// Negotiate minimum of both limits
    public func negotiate(with other: Limits) -> Limits {
        return Limits(
            maxFrame: min(self.maxFrame, other.maxFrame),
            maxChunk: min(self.maxChunk, other.maxChunk),
            maxReorderBuffer: min(self.maxReorderBuffer, other.maxReorderBuffer),
            initialCredit: min(self.initialCredit, other.initialCredit)
        )
    }
}

/// A CBOR protocol frame
public struct Frame: @unchecked Sendable {
    /// Protocol version (always CBOR_PROTOCOL_VERSION)
    public var version: UInt8 = CBOR_PROTOCOL_VERSION
    /// Frame type
    public var frameType: FrameType
    /// Message ID for correlation (request ID)
    public var id: MessageId
    /// Routing ID assigned by RelaySwitch for routing decisions
    /// Separates logical request ID (id) from routing concerns
    /// RelaySwitch assigns this when REQ arrives, all response frames carry it
    public var routingId: MessageId?
    /// Stream ID for multiplexed streams (used in STREAM_START, CHUNK, STREAM_END)
    public var streamId: String?
    /// Media URN for stream type identification (used in STREAM_START)
    public var mediaUrn: String?
    /// Sequence number within a flow (per request ID).
    /// Assigned centrally by SeqAssigner at the output stage (writer thread).
    /// Monotonically increasing for all frame types within the same RID.
    public var seq: UInt64 = 0
    /// Content type of payload (MIME-like)
    public var contentType: String?
    /// Metadata map
    public var meta: [String: CBOR]?
    /// Binary payload
    public var payload: Data?
    /// Total length for chunked transfers (first chunk only)
    public var len: UInt64?
    /// Byte offset in chunked stream
    public var offset: UInt64?
    /// End of stream marker
    public var eof: Bool?
    /// Cap URN (for requests)
    public var cap: String?
    /// Chunk sequence index within stream (CHUNK frames only, starts at 0)
    public var chunkIndex: UInt64?
    /// Total chunk count (STREAM_END frames only, by source's reckoning)
    public var chunkCount: UInt64?
    /// FNV-1a checksum of payload (CHUNK frames only)
    public var checksum: UInt64?
    /// Whether the producer used emit_list_item (true) or write (false).
    /// Set on STREAM_START frames. nil means legacy producer that didn't set it.
    public var isSequence: Bool?
    /// Whether Cancel should force-kill the cartridge process (true) or cooperatively cancel (false).
    /// Present on Cancel frames only.
    public var forceKill: Bool?
    /// Flow-control credit grant in CHUNK units. Present on Credit frames only.
    public var credit: UInt64?
    /// Whether the stream makes no length promise (no chunk_count on STREAM_END,
    /// receivers must consume incrementally). Present on STREAM_START frames only.
    public var unbounded: Bool?

    public init(frameType: FrameType, id: MessageId) {
        self.frameType = frameType
        self.id = id
    }

    // MARK: - Factory Methods

    /// Create a HELLO frame for handshake (host side - no manifest)
    public static func hello(limits: Limits) -> Frame {
        var frame = Frame(frameType: .hello, id: .uint(0))
        frame.meta = [
            "max_frame": .unsignedInt(UInt64(limits.maxFrame)),
            "max_chunk": .unsignedInt(UInt64(limits.maxChunk)),
            "max_reorder_buffer": .unsignedInt(UInt64(limits.maxReorderBuffer)),
            "initial_credit": .unsignedInt(limits.initialCredit),
            "version": .unsignedInt(UInt64(CBOR_PROTOCOL_VERSION))
        ]
        return frame
    }

    /// Create a HELLO frame for handshake with manifest (cartridge side)
    /// The manifest is JSON-encoded cartridge metadata including name, version, and caps.
    /// This is the ONLY way for cartridges to communicate their capabilities.
    public static func helloWithManifest(limits: Limits, manifest: Data) -> Frame {
        var frame = Frame(frameType: .hello, id: .uint(0))
        frame.meta = [
            "max_frame": .unsignedInt(UInt64(limits.maxFrame)),
            "max_chunk": .unsignedInt(UInt64(limits.maxChunk)),
            "max_reorder_buffer": .unsignedInt(UInt64(limits.maxReorderBuffer)),
            "initial_credit": .unsignedInt(limits.initialCredit),
            "version": .unsignedInt(UInt64(CBOR_PROTOCOL_VERSION)),
            "manifest": .byteString([UInt8](manifest))
        ]
        return frame
    }

    /// Create a REQ frame for invoking a cap
    public static func req(id: MessageId, capUrn: String, payload: Data, contentType: String) -> Frame {
        var frame = Frame(frameType: .req, id: id)
        frame.cap = capUrn
        frame.payload = payload
        frame.contentType = contentType
        return frame
    }

    // Frame.res() REMOVED - old single-response protocol no longer supported
    // Use stream multiplexing: STREAM_START + CHUNK + STREAM_END + END

    /// Create a CHUNK frame for multiplexed streaming.
    /// Each chunk belongs to a specific stream within a request.
    ///
    /// - Parameters:
    ///   - reqId: The request ID this chunk belongs to
    ///   - streamId: The stream ID this chunk belongs to
    ///   - seq: Sequence number within the stream
    ///   - payload: Chunk data
    ///   - chunkIndex: Chunk sequence index (starts at 0)
    ///   - checksum: FNV-1a checksum of payload
    public static func chunk(reqId: MessageId, streamId: String, seq: UInt64, payload: Data, chunkIndex: UInt64, checksum: UInt64) -> Frame {
        var frame = Frame(frameType: .chunk, id: reqId)
        frame.streamId = streamId
        frame.seq = seq
        frame.payload = payload
        frame.chunkIndex = chunkIndex
        frame.checksum = checksum
        return frame
    }

    /// Create a CHUNK frame with offset info (for large binary transfers).
    /// Used for multiplexed streaming with offset tracking.
    public static func chunkWithOffset(
        reqId: MessageId,
        streamId: String,
        seq: UInt64,
        payload: Data,
        offset: UInt64,
        totalLen: UInt64?,
        isLast: Bool,
        chunkIndex: UInt64,
        checksum: UInt64
    ) -> Frame {
        var frame = Frame(frameType: .chunk, id: reqId)
        frame.streamId = streamId
        frame.seq = seq
        frame.payload = payload
        frame.offset = offset
        frame.chunkIndex = chunkIndex
        frame.checksum = checksum
        if chunkIndex == 0 {
            frame.len = totalLen
        }
        if isLast {
            frame.eof = true
        }
        return frame
    }

    /// Create an END frame to mark stream completion.
    /// Does NOT set exit_code — absence of exit_code in meta means failure.
    /// Use `endOk` for successful completion (exit_code=0).
    public static func end(id: MessageId, finalPayload: Data? = nil) -> Frame {
        var frame = Frame(frameType: .end, id: id)
        frame.payload = finalPayload
        frame.eof = true
        return frame
    }

    /// Create an END frame with exit_code=0 (success).
    /// Only exit_code=0 means success. Absence of exit_code or any non-zero value means failure.
    public static func endOk(id: MessageId, finalPayload: Data? = nil) -> Frame {
        var frame = Frame(frameType: .end, id: id)
        frame.payload = finalPayload
        frame.eof = true
        frame.meta = ["exit_code": .unsignedInt(0)]
        return frame
    }

    /// Create an END frame with exit_code=0 (success) carrying terminal metadata.
    /// `progress` is the authoritative final progress value delivered with the
    /// terminal frame itself (so it can never race it); `message` is an optional
    /// final status message. A successful END without an explicit progress reads
    /// as 1.0 via `finalProgress()`.
    public static func endOkWith(id: MessageId, finalPayload: Data? = nil, progress: Double? = nil, message: String? = nil) -> Frame {
        var frame = Frame.endOk(id: id, finalPayload: finalPayload)
        var meta = frame.meta ?? [:]
        if let progress = progress {
            meta["progress"] = .double(progress)
        }
        if let message = message {
            meta["message"] = .utf8String(message)
        }
        frame.meta = meta
        return frame
    }

    /// Read the final progress from an END frame's terminal metadata.
    /// Returns the explicit `progress` meta value when present; a successful END
    /// (exit_code=0) without an explicit value reads as 1.0. Non-END frames and
    /// unsuccessful ENDs without a value return nil.
    public func finalProgress() -> Double? {
        guard frameType == .end else { return nil }
        if let value = meta?["progress"] {
            switch value {
            case .double(let d): return d
            case .float(let f): return Double(f)
            case .half(let h): return Double(h)
            case .unsignedInt(let n): return Double(n)
            case .negativeInt(let n): return Double(-1 - Int64(n))
            default: break
            }
        }
        if exitCode == 0 {
            return 1.0
        }
        return nil
    }

    /// Read the final status message from an END frame's terminal metadata.
    public func finalMessage() -> String? {
        guard frameType == .end, let meta = meta, case .utf8String(let s) = meta["message"] else {
            return nil
        }
        return s
    }

    /// Read exit_code from an END frame's meta. Returns nil if absent.
    public var exitCode: Int64? {
        guard let meta = meta, let value = meta["exit_code"] else { return nil }
        switch value {
        case .unsignedInt(let n): return Int64(n)
        case .negativeInt(let n): return -1 - Int64(n)
        default: return nil
        }
    }

    /// Create a LOG frame for progress/status
    public static func log(id: MessageId, level: String, message: String) -> Frame {
        var frame = Frame(frameType: .log, id: id)
        frame.meta = [
            "level": .utf8String(level),
            "message": .utf8String(message)
        ]
        return frame
    }

    /// Create a LOG frame with progress (0.0–1.0) and a human-readable status message.
    public static func progress(id: MessageId, progress: Float, message: String) -> Frame {
        var frame = Frame(frameType: .log, id: id)
        frame.meta = [
            "level": .utf8String("progress"),
            "message": .utf8String(message),
            "progress": .float(progress)
        ]
        return frame
    }

    /// Create an ERR frame. The class defaults to `.internal` — an error
    /// that reaches the wire without a declared class is the emitter's
    /// problem by definition; emitters with a classified error use
    /// `errClassified`.
    public static func err(id: MessageId, code: String, message: String) -> Frame {
        return errClassified(id: id, code: code, failureClass: .internal, message: message)
    }

    /// Create an ERR frame carrying the full failure identity: the emitter's
    /// machine-readable `code` (e.g. `CONTEXT_OVERFLOW`), the failure CLASS
    /// (whose problem it is — declared at the error's definition site, see
    /// `FailureClass`), and the human message. ERR meta contract
    /// (docs/12.2): `code` + `class` + `message`, all text.
    public static func errClassified(id: MessageId, code: String, failureClass: FailureClass, message: String) -> Frame {
        var frame = Frame(frameType: .err, id: id)
        frame.meta = [
            "code": .utf8String(code),
            "class": .utf8String(failureClass.rawValue),
            "message": .utf8String(message)
        ]
        return frame
    }

    /// Create a HEARTBEAT frame for health monitoring.
    /// Either side can send; receiver must respond with HEARTBEAT using the same ID.
    public static func heartbeat(id: MessageId) -> Frame {
        return Frame(frameType: .heartbeat, id: id)
    }

    /// Create a STREAM_START frame to announce a new stream within a request.
    /// Used for multiplexed streaming - multiple streams can exist per request.
    ///
    /// - Parameters:
    ///   - reqId: The request ID this stream belongs to
    ///   - streamId: Unique ID for this stream (UUID generated by sender)
    ///   - mediaUrn: Media URN identifying the stream's data type
    ///   - isSequence: Whether the producer will use emit_list_item (true) or write (false).
    ///     nil for host/relay frames where the wire format isn't relevant.
    public static func streamStart(reqId: MessageId, streamId: String, mediaUrn: String, isSequence: Bool? = nil) -> Frame {
        var frame = Frame(frameType: .streamStart, id: reqId)
        frame.streamId = streamId
        frame.mediaUrn = mediaUrn
        frame.isSequence = isSequence
        return frame
    }

    /// Create a STREAM_START frame for an UNBOUNDED stream — one that makes no
    /// length promise. Its STREAM_END may omit chunk_count, and receivers must
    /// consume it incrementally (never buffer to completion).
    public static func streamStartUnbounded(reqId: MessageId, streamId: String, mediaUrn: String, isSequence: Bool? = nil) -> Frame {
        var frame = Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: mediaUrn, isSequence: isSequence)
        frame.unbounded = true
        return frame
    }

    /// Whether this STREAM_START announces an unbounded stream.
    /// Absent flag means bounded.
    public var isUnbounded: Bool {
        return unbounded ?? false
    }

    /// Create a STREAM_END frame to mark completion of a specific stream.
    /// After this, any CHUNK for this stream_id is a fatal protocol error.
    ///
    /// - Parameters:
    ///   - reqId: The request ID this stream belongs to
    ///   - streamId: The stream being ended
    ///   - chunkCount: Total number of chunks sent in this stream (by source's reckoning)
    public static func streamEnd(reqId: MessageId, streamId: String, chunkCount: UInt64) -> Frame {
        var frame = Frame(frameType: .streamEnd, id: reqId)
        frame.streamId = streamId
        frame.chunkCount = chunkCount
        return frame
    }

    /// Create a STREAM_END frame for an unbounded stream — no chunk_count promise.
    /// Valid only for streams announced with `streamStartUnbounded`.
    public static func streamEndUnbounded(reqId: MessageId, streamId: String) -> Frame {
        var frame = Frame(frameType: .streamEnd, id: reqId)
        frame.streamId = streamId
        return frame
    }

    /// Create a RELAY_NOTIFY frame for capability advertisement (slave → master).
    /// Carries the aggregate manifest and negotiated limits.
    public static func relayNotify(manifest: Data, limits: Limits) -> Frame {
        var frame = Frame(frameType: .relayNotify, id: .uint(0))
        frame.meta = [
            "manifest": CBOR.byteString([UInt8](manifest)),
            "max_frame": CBOR.unsignedInt(UInt64(limits.maxFrame)),
            "max_chunk": CBOR.unsignedInt(UInt64(limits.maxChunk)),
            "max_reorder_buffer": CBOR.unsignedInt(UInt64(limits.maxReorderBuffer)),
            "initial_credit": CBOR.unsignedInt(limits.initialCredit),
        ]
        return frame
    }

    /// Create a RELAY_STATE frame for host system resources + cap demands (master → slave).
    /// Carries an opaque resource payload.
    public static func relayState(resources: Data) -> Frame {
        var frame = Frame(frameType: .relayState, id: .uint(0))
        frame.payload = resources
        return frame
    }

    /// Create a CANCEL frame targeting a specific request by RID.
    ///
    /// - Parameters:
    ///   - targetRid: The request ID to cancel
    ///   - forceKill: If true, force-kill the cartridge process. If false, cooperative cancel.
    public static func cancel(targetRid: MessageId, forceKill: Bool) -> Frame {
        var frame = Frame(frameType: .cancel, id: targetRid)
        frame.forceKill = forceKill
        return frame
    }

    /// Create a CREDIT frame granting per-stream flow-control credit to the
    /// sender of a stream.
    ///
    /// - Parameters:
    ///   - targetRid: The request whose stream is being credited
    ///   - streamId: The stream being credited (nil credits the request's
    ///     sole/default stream)
    ///   - credits: Number of additional CHUNK frames the sender may emit
    ///   - direction: Which side's stream is being credited. Hosts route
    ///     grants by this: a `request` grant travels toward the requester (the
    ///     sender of argument streams), a `response` grant toward the handler
    ///     (the sender of output streams). Required — the (xid, rid) key alone
    ///     is ambiguous for self-loop peer calls.
    public static func credit(targetRid: MessageId, streamId: String?, credits: UInt64, direction: CreditDirection) -> Frame {
        var frame = Frame(frameType: .credit, id: targetRid)
        frame.streamId = streamId
        frame.credit = credits
        frame.meta = ["credit_dir": .utf8String(direction.rawValue)]
        return frame
    }

    /// Read the credit grant from a CREDIT frame. nil for other frame types.
    public var creditCount: UInt64? {
        guard frameType == .credit else { return nil }
        return credit
    }

    /// Read the direction of a CREDIT frame's grant. nil for other frame
    /// types or a Credit frame without the mandatory direction (a protocol
    /// violation the receiving router treats as unroutable).
    public var creditDirection: CreditDirection? {
        guard frameType == .credit, let meta = meta,
              case .utf8String(let s) = meta["credit_dir"] else {
            return nil
        }
        return CreditDirection(rawValue: s)
    }

    // MARK: - Accessors

    /// Check if this is the final frame in a stream
    public var isEof: Bool {
        return eof ?? false
    }

    /// Get error code if this is an ERR frame
    public var errorCode: String? {
        guard frameType == .err, let meta = meta, case .utf8String(let s) = meta["code"] else {
            return nil
        }
        return s
    }

    /// Get the failure class if this is an ERR frame. A frame without a
    /// `class` entry (or with an unknown token) classifies as `.internal`:
    /// unclassified means "the emitter's problem", never a guess about the
    /// user's input. Returns nil for non-ERR frames.
    public var errorClass: FailureClass? {
        guard frameType == .err else { return nil }
        guard let meta = meta, case .utf8String(let token) = meta["class"],
              let parsed = FailureClass(rawValue: token) else {
            return .internal
        }
        return parsed
    }

    /// Get error message if this is an ERR frame
    public var errorMessage: String? {
        guard frameType == .err, let meta = meta, case .utf8String(let s) = meta["message"] else {
            return nil
        }
        return s
    }

    /// Get log level if this is a LOG frame
    public var logLevel: String? {
        guard frameType == .log, let meta = meta, case .utf8String(let s) = meta["level"] else {
            return nil
        }
        return s
    }

    /// Get log message if this is a LOG frame
    public var logMessage: String? {
        guard frameType == .log, let meta = meta, case .utf8String(let s) = meta["message"] else {
            return nil
        }
        return s
    }

    /// Get progress value (0.0–1.0) if this is a LOG frame with level="progress".
    /// Accepts float32, float64, and half-precision floats from CBOR encoding.
    public var logProgress: Float? {
        guard frameType == .log,
              let meta = meta,
              case .utf8String(let level) = meta["level"],
              level == "progress",
              let progressValue = meta["progress"]
        else { return nil }
        switch progressValue {
        case .float(let f): return f
        case .double(let d): return Float(d)
        case .half(let h): return h
        default: return nil
        }
    }

    /// Extract manifest from RELAY_NOTIFY metadata
    public var relayNotifyManifest: Data? {
        guard frameType == .relayNotify, let meta = meta, case .byteString(let bytes) = meta["manifest"] else {
            return nil
        }
        return Data(bytes)
    }

    /// Extract limits from RELAY_NOTIFY metadata
    /// Returns nil if any required field is missing (protocol violation in v3)
    public var relayNotifyLimits: Limits? {
        guard frameType == .relayNotify, let meta = meta,
              case .unsignedInt(let maxFrame) = meta["max_frame"],
              case .unsignedInt(let maxChunk) = meta["max_chunk"],
              case .unsignedInt(let maxReorderBuffer) = meta["max_reorder_buffer"] else {
            return nil
        }
        var initialCredit = DEFAULT_INITIAL_CREDIT
        if case .unsignedInt(let n) = meta["initial_credit"], n > 0 {
            initialCredit = n
        }
        return Limits(maxFrame: Int(maxFrame), maxChunk: Int(maxChunk), maxReorderBuffer: Int(maxReorderBuffer), initialCredit: initialCredit)
    }

    /// Extract max_frame from HELLO metadata
    public var helloMaxFrame: Int? {
        guard frameType == .hello, let meta = meta, case .unsignedInt(let n) = meta["max_frame"] else {
            return nil
        }
        return Int(n)
    }

    /// Extract max_chunk from HELLO metadata
    public var helloMaxChunk: Int? {
        guard frameType == .hello, let meta = meta, case .unsignedInt(let n) = meta["max_chunk"] else {
            return nil
        }
        return Int(n)
    }

    /// Extract max_reorder_buffer from HELLO metadata
    /// Returns nil if missing (protocol violation in v2)
    public var helloMaxReorderBuffer: Int? {
        guard frameType == .hello, let meta = meta, case .unsignedInt(let n) = meta["max_reorder_buffer"] else {
            return nil
        }
        return Int(n)
    }

    /// Extract initial_credit from HELLO metadata
    public var helloInitialCredit: UInt64? {
        guard frameType == .hello, let meta = meta, case .unsignedInt(let n) = meta["initial_credit"], n > 0 else {
            return nil
        }
        return n
    }

    /// Extract the protocol version declared in HELLO metadata.
    public var helloVersion: UInt8? {
        guard frameType == .hello, let meta = meta, case .unsignedInt(let n) = meta["version"] else {
            return nil
        }
        return UInt8(truncatingIfNeeded: n)
    }

    /// Extract manifest from HELLO metadata (cartridge side sends this)
    /// Returns nil if no manifest present (host HELLO) or not a HELLO frame.
    /// The manifest is JSON-encoded cartridge metadata.
    public var helloManifest: Data? {
        guard frameType == .hello, let meta = meta, case .byteString(let bytes) = meta["manifest"] else {
            return nil
        }
        return Data(bytes)
    }

    // MARK: - Checksum and Flow Control

    /// Compute FNV-1a 64-bit checksum of bytes.
    /// This is a simple, fast hash function suitable for detecting transmission errors.
    public static func computeChecksum(_ data: Data) -> UInt64 {
        let FNV_OFFSET_BASIS: UInt64 = 0xcbf29ce484222325
        let FNV_PRIME: UInt64 = 0x100000001b3

        var hash = FNV_OFFSET_BASIS
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* FNV_PRIME  // wrapping multiply
        }
        return hash
    }

    /// Returns true if this frame type participates in flow ordering (seq tracking).
    /// Non-flow frames (Hello, Heartbeat, RelayNotify, RelayState, Cancel, Credit)
    /// bypass seq assignment and reorder buffers entirely — Credit in particular must
    /// never queue behind the data it is flow-controlling.
    public func isFlowFrame() -> Bool {
        switch frameType {
        case .hello, .heartbeat, .relayNotify, .relayState, .cancel, .credit:
            return false
        default:
            return true
        }
    }
}

// MARK: - Progress Mapping

/// Map child progress [0.0, 1.0] into parent range [base, base + weight].
///
/// This is the canonical progress mapping formula. Every place in the system
/// that subdivides progress must use this function — no ad-hoc derivations.
/// Mirrors capdag (Rust) `map_progress()`.
public func mapProgress(_ childProgress: Float, base: Float, weight: Float) -> Float {
    base + min(max(childProgress, 0.0), 1.0) * weight
}

// MARK: - UUID Extension

extension UUID {
    var data: Data {
        return withUnsafeBytes(of: uuid) { Data($0) }
    }

    init?(data: Data) {
        guard data.count == 16 else { return nil }
        let bytes = [UInt8](data)
        let uuid = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        self.init(uuid: uuid)
    }
}

/// Integer keys for CBOR map fields (must match Rust side)
public enum FrameKey: UInt64 {
    case version = 0
    case frameType = 1
    case id = 2
    case seq = 3
    case contentType = 4
    case meta = 5
    case payload = 6
    case len = 7
    case offset = 8
    case eof = 9
    case cap = 10
    case streamId = 11
    case mediaUrn = 12
    case routingId = 13
    case chunkIndex = 14
    case chunkCount = 15
    case checksum = 16
    case isSequence = 17
    case forceKill = 18
    case credit = 19       // Flow-control credit grant in CHUNK units (Credit frames)
    case unbounded = 20    // Stream makes no length promise (STREAM_START frames)
}

// MARK: - Credit Direction

/// Which side's stream a CREDIT frame credits (L11 routing discriminator).
/// `request` credits a request-direction stream (arguments flowing toward the
/// handler): the grant travels toward the REQUESTER. `response` credits a
/// response-direction stream (handler output): the grant travels toward the
/// HANDLER. Required on every CREDIT frame — (xid, rid) alone cannot
/// disambiguate grant direction for self-loop peer calls.
///
/// The raw values are the stable snake_case wire names carried in the
/// `credit_dir` meta entry (mirrors Rust `CreditDirection`).
public enum CreditDirection: String, CaseIterable, Hashable, Sendable, Codable {
    case request
    case response
}

// MARK: - Drop Reasons

/// Why a frame was dropped instead of delivered. The shared vocabulary for
/// counted drops across every runtime (cartridge writer, host, relay switch,
/// executor); every dropped frame increments exactly one of these counters,
/// observable via the protocol stats snapshots. Frames are never dropped
/// silently.
///
/// The raw values are the stable snake_case names — the wire/snapshot
/// contract mirrored from the Rust reference.
public enum DropReason: String, CaseIterable, Hashable, Sendable, Codable {
    /// Flow frame enqueued/received after the request's terminal (END/ERR) frame.
    case postTerminal = "post_terminal"
    /// Flow frame for a request with no routing state (already released or never
    /// registered).
    case noRoute = "no_route"
    /// Send attempted on a closed channel (receiver gone).
    case channelClosed = "channel_closed"
    /// CHUNK received beyond the granted credit window.
    case creditViolation = "credit_violation"
    /// Frame discarded because its request was cancelled.
    case cancelled = "cancelled"
    /// Frame discarded because the owning master/host connection died.
    case masterDied = "master_died"

    /// All variants, for counter arrays and snapshot serialization.
    public static let all: [DropReason] = [
        .postTerminal, .noRoute, .channelClosed, .creditViolation, .cancelled, .masterDied,
    ]

    /// Stable snake_case name (the wire/snapshot contract for mirrors).
    public var asString: String {
        return rawValue
    }
}
