import Foundation
@preconcurrency import SwiftCBOR

/// Errors that can occur during CBOR I/O
public enum FrameError: Error, @unchecked Sendable {
    case ioError(String)
    case encodeError(String)
    case decodeError(String)
    case frameTooLarge(size: Int, max: Int)
    case invalidFrame(String)
    case unexpectedEof
    case protocolError(String)
    case handshakeFailed(String)
}

extension FrameError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .ioError(let msg): return "I/O error: \(msg)"
        case .encodeError(let msg): return "CBOR encode error: \(msg)"
        case .decodeError(let msg): return "CBOR decode error: \(msg)"
        case .frameTooLarge(let size, let max): return "Frame too large: \(size) bytes (max \(max))"
        case .invalidFrame(let msg): return "Invalid frame: \(msg)"
        case .unexpectedEof: return "Unexpected end of stream"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        }
    }
}

// MARK: - Frame Encoding

/// Encode a frame to CBOR bytes
public func encodeFrame(_ frame: Frame) throws -> Data {
    var map: [CBOR: CBOR] = [:]

    // Required fields
    map[.unsignedInt(FrameKey.version.rawValue)] = .unsignedInt(UInt64(frame.version))
    map[.unsignedInt(FrameKey.frameType.rawValue)] = .unsignedInt(UInt64(frame.frameType.rawValue))

    // Message ID
    switch frame.id {
    case .uuid(let data):
        map[.unsignedInt(FrameKey.id.rawValue)] = .byteString([UInt8](data))
    case .uint(let n):
        map[.unsignedInt(FrameKey.id.rawValue)] = .unsignedInt(n)
    }

    // Sequence number
    map[.unsignedInt(FrameKey.seq.rawValue)] = .unsignedInt(frame.seq)

    // Optional fields
    if let ct = frame.contentType {
        map[.unsignedInt(FrameKey.contentType.rawValue)] = .utf8String(ct)
    }

    if let meta = frame.meta {
        var metaMap: [CBOR: CBOR] = [:]
        for (k, v) in meta {
            metaMap[.utf8String(k)] = v
        }
        map[.unsignedInt(FrameKey.meta.rawValue)] = .map(metaMap)
    }

    if let payload = frame.payload {
        map[.unsignedInt(FrameKey.payload.rawValue)] = .byteString([UInt8](payload))
    }

    if let len = frame.len {
        map[.unsignedInt(FrameKey.len.rawValue)] = .unsignedInt(len)
    }

    if let offset = frame.offset {
        map[.unsignedInt(FrameKey.offset.rawValue)] = .unsignedInt(offset)
    }

    if let eof = frame.eof {
        map[.unsignedInt(FrameKey.eof.rawValue)] = .boolean(eof)
    }

    if let cap = frame.cap {
        map[.unsignedInt(FrameKey.cap.rawValue)] = .utf8String(cap)
    }

    if let streamId = frame.streamId {
        map[.unsignedInt(FrameKey.streamId.rawValue)] = .utf8String(streamId)
    }

    if let mediaUrn = frame.mediaUrn {
        map[.unsignedInt(FrameKey.mediaUrn.rawValue)] = .utf8String(mediaUrn)
    }

    if let routingId = frame.routingId {
        switch routingId {
        case .uuid(let data):
            map[.unsignedInt(FrameKey.routingId.rawValue)] = .byteString([UInt8](data))
        case .uint(let n):
            map[.unsignedInt(FrameKey.routingId.rawValue)] = .unsignedInt(n)
        }
    }

    if let chunkIndex = frame.chunkIndex {
        map[.unsignedInt(FrameKey.chunkIndex.rawValue)] = .unsignedInt(chunkIndex)
    }

    if let chunkCount = frame.chunkCount {
        map[.unsignedInt(FrameKey.chunkCount.rawValue)] = .unsignedInt(chunkCount)
    }

    if let checksum = frame.checksum {
        map[.unsignedInt(FrameKey.checksum.rawValue)] = .unsignedInt(checksum)
    }

    if let isSequence = frame.isSequence {
        map[.unsignedInt(FrameKey.isSequence.rawValue)] = .boolean(isSequence)
    }

    if let forceKill = frame.forceKill {
        map[.unsignedInt(FrameKey.forceKill.rawValue)] = .boolean(forceKill)
    }

    let cbor = CBOR.map(map)
    return Data(cbor.encode())
}

/// Decode a frame from CBOR bytes
public func decodeFrame(_ data: Data) throws -> Frame {
    guard let cbor = try? CBOR.decode([UInt8](data)) else {
        throw FrameError.decodeError("Failed to parse CBOR")
    }

    guard case .map(let map) = cbor else {
        throw FrameError.invalidFrame("Expected map")
    }

    // Helper to get integer key value
    func getUInt(_ key: FrameKey) -> UInt64? {
        if case .unsignedInt(let n) = map[.unsignedInt(key.rawValue)] {
            return n
        }
        return nil
    }

    // Extract required fields
    guard let versionRaw = getUInt(.version) else {
        throw FrameError.invalidFrame("Missing version")
    }
    let version = UInt8(versionRaw)

    guard let frameTypeRaw = getUInt(.frameType),
          let frameType = FrameType(rawValue: UInt8(frameTypeRaw)) else {
        throw FrameError.invalidFrame("Missing or invalid frame_type")
    }

    // Extract ID
    let id: MessageId
    if let idValue = map[.unsignedInt(FrameKey.id.rawValue)] {
        switch idValue {
        case .byteString(let bytes):
            if bytes.count == 16 {
                id = .uuid(Data(bytes))
            } else {
                id = .uint(0)
            }
        case .unsignedInt(let n):
            id = .uint(n)
        default:
            id = .uint(0)
        }
    } else {
        throw FrameError.invalidFrame("Missing id")
    }

    var frame = Frame(frameType: frameType, id: id)
    frame.version = version
    frame.seq = getUInt(.seq) ?? 0

    // Optional fields
    if case .utf8String(let s) = map[.unsignedInt(FrameKey.contentType.rawValue)] {
        frame.contentType = s
    }

    if case .map(let metaMap) = map[.unsignedInt(FrameKey.meta.rawValue)] {
        var meta: [String: CBOR] = [:]
        for (k, v) in metaMap {
            if case .utf8String(let key) = k {
                meta[key] = v
            }
        }
        frame.meta = meta
    }

    if case .byteString(let bytes) = map[.unsignedInt(FrameKey.payload.rawValue)] {
        frame.payload = Data(bytes)
    }

    if let len = getUInt(.len) {
        frame.len = len
    }

    if let offset = getUInt(.offset) {
        frame.offset = offset
    }

    if case .boolean(let b) = map[.unsignedInt(FrameKey.eof.rawValue)] {
        frame.eof = b
    }

    if case .utf8String(let s) = map[.unsignedInt(FrameKey.cap.rawValue)] {
        frame.cap = s
    }

    if case .utf8String(let s) = map[.unsignedInt(FrameKey.streamId.rawValue)] {
        frame.streamId = s
    }

    if case .utf8String(let s) = map[.unsignedInt(FrameKey.mediaUrn.rawValue)] {
        frame.mediaUrn = s
    }

    // Extract routingId
    if let routingIdValue = map[.unsignedInt(FrameKey.routingId.rawValue)] {
        switch routingIdValue {
        case .byteString(let bytes):
            if bytes.count == 16 {
                frame.routingId = .uuid(Data(bytes))
            }
        case .unsignedInt(let n):
            frame.routingId = .uint(n)
        default:
            break
        }
    }

    if let chunkIndex = getUInt(.chunkIndex) {
        frame.chunkIndex = chunkIndex
    }

    if let chunkCount = getUInt(.chunkCount) {
        frame.chunkCount = chunkCount
    }

    // Checksum can be encoded as signed or unsigned (Rust uses signed i64 which may become negativeInt for large values)
    if let value = map[.unsignedInt(FrameKey.checksum.rawValue)] {
        switch value {
        case .unsignedInt(let n):
            frame.checksum = n
        case .negativeInt(let n):
            // Rust encodes checksum as i64, which becomes negativeInt for values > i64::MAX
            // Convert back using two's complement: negativeInt(n) represents -(n+1)
            frame.checksum = UInt64(bitPattern: Int64(-1 - Int64(n)))
        default:
            break
        }
    }

    if case .boolean(let b) = map[.unsignedInt(FrameKey.isSequence.rawValue)] {
        frame.isSequence = b
    }

    if case .boolean(let b) = map[.unsignedInt(FrameKey.forceKill.rawValue)] {
        frame.forceKill = b
    }

    // Protocol v2 validation: CHUNK frames MUST have chunkIndex and checksum
    if frame.frameType == .chunk {
        guard frame.chunkIndex != nil else {
            throw FrameError.protocolError("CHUNK frame missing required chunkIndex field")
        }
        guard frame.checksum != nil else {
            throw FrameError.protocolError("CHUNK frame missing required checksum field")
        }
    }

    // Protocol v2 validation: STREAM_END frames MUST have chunkCount
    if frame.frameType == .streamEnd {
        guard frame.chunkCount != nil else {
            throw FrameError.protocolError("STREAM_END frame missing required chunkCount field")
        }
    }

    return frame
}

// MARK: - Length-Prefixed I/O

/// Encode a frame and append its length-prefixed bytes to `buffer`,
/// then drain the buffer to `fd` via POSIX `write(2)`.
///
/// `fd` must be the cached file descriptor from a `FrameWriter` —
/// callers never derive `fd` from a `FileHandle` at write time, since
/// `FileHandle.fileDescriptor` raises `NSFileHandleOperationException`
/// when invoked on a closed handle and Swift cannot catch ObjC
/// exceptions, which crashes the entire process. `FrameWriter` snapshots
/// the fd once at construction (while the handle is guaranteed open)
/// and switches to `-1` on `close()`; passing `-1` here is a programming
/// error in the writer state machine and is rejected with a clean
/// `FrameError.ioError`.
@available(macOS 10.15.4, iOS 13.4, *)
public func writeFrame(_ frame: Frame, toFD fd: Int32, limits: Limits, buffer: inout Data) throws {
    if fd < 0 {
        throw FrameError.ioError("writer closed")
    }

    let data = try encodeFrame(frame)

    if data.count > limits.maxFrame {
        throw FrameError.frameTooLarge(size: data.count, max: limits.maxFrame)
    }

    if data.count > MAX_FRAME_HARD_LIMIT {
        throw FrameError.frameTooLarge(size: data.count, max: MAX_FRAME_HARD_LIMIT)
    }

    let length = UInt32(data.count)
    var lengthBytes = Data(count: 4)
    lengthBytes[0] = UInt8((length >> 24) & 0xFF)
    lengthBytes[1] = UInt8((length >> 16) & 0xFF)
    lengthBytes[2] = UInt8((length >> 8) & 0xFF)
    lengthBytes[3] = UInt8(length & 0xFF)

    // Accumulate length + data in buffer
    buffer.append(lengthBytes)
    buffer.append(data)

    // Use POSIX write() directly to bypass FileHandle buffering.
    // FileHandle.write() may internally buffer data, causing frames
    // to not reach the pipe reader immediately; POSIX write() is
    // unbuffered and writes directly to the file descriptor.
    try buffer.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        var totalWritten = 0
        while totalWritten < buffer.count {
            let result = Darwin.write(fd, baseAddress.advanced(by: totalWritten), buffer.count - totalWritten)
            if result < 0 {
                throw FrameError.ioError("write failed: \(String(cString: strerror(errno)))")
            }
            totalWritten += result
        }
    }
    buffer.removeAll(keepingCapacity: true)
}

/// Read a length-prefixed CBOR frame
/// Returns nil on clean EOF
public func readFrame(from handle: FileHandle, limits: Limits) throws -> Frame? {
    // Read 4-byte length prefix
    let lengthData = handle.readData(ofLength: 4)

    if lengthData.isEmpty {
        return nil  // Clean EOF
    }

    guard lengthData.count == 4 else {
        throw FrameError.unexpectedEof
    }

    let bytes = [UInt8](lengthData)
    let length = Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))

    // Validate length
    if length > limits.maxFrame || length > MAX_FRAME_HARD_LIMIT {
        throw FrameError.frameTooLarge(size: length, max: min(limits.maxFrame, MAX_FRAME_HARD_LIMIT))
    }

    // Read payload
    let payloadData = handle.readData(ofLength: length)
    guard payloadData.count == length else {
        throw FrameError.unexpectedEof
    }

    return try decodeFrame(payloadData)
}

// MARK: - Frame Reader/Writer Classes

/// CBOR frame reader with incremental decoding
public class FrameReader: @unchecked Sendable {
    private let handle: FileHandle
    private var limits: Limits
    private let lock = NSLock()

    public init(handle: FileHandle, limits: Limits = Limits()) {
        self.handle = handle
        self.limits = limits
    }

    /// Update limits (after handshake)
    public func setLimits(_ limits: Limits) {
        lock.lock()
        defer { lock.unlock() }
        self.limits = limits
    }

    /// Get current limits
    public func getLimits() -> Limits {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }

    /// Read the next frame (blocking)
    public func read() throws -> Frame? {
        lock.lock()
        let currentLimits = limits
        lock.unlock()
        return try readFrame(from: handle, limits: currentLimits)
    }
}

/// CBOR frame writer.
///
/// Owns a `FileHandle` and a cached POSIX file descriptor. The
/// descriptor is read **once** at construction, while the handle is
/// guaranteed open by the caller's lifetime contract; thereafter all
/// I/O uses the cached `Int32` directly. This is required to avoid
/// `NSFileHandleOperationException` from `-[NSConcreteFileHandle
/// fileDescriptor]` on a closed handle: that exception is an Objective-C
/// `NSException`, which Swift cannot catch — it tears down the entire
/// process. A single cartridge dying must never bring down the host,
/// so the writer must not invoke that accessor under any circumstance.
///
/// The writer has two states:
///   - **open**: `fd >= 0`, writes/flushes go through; `handle` is
///     retained but never accessed.
///   - **closed**: `fd == -1`, all writes/flushes throw
///     `FrameError.ioError("writer closed")` cleanly. Reaching the
///     closed state is irreversible.
///
/// `close()` transitions open → closed under the writer's lock; it
/// also closes the underlying handle exactly once. Callers must always
/// close the writer (not the handle directly) to keep the cached fd
/// and handle state consistent.
///
/// `deinit` does no I/O. A destructor must not write to file
/// descriptors because the descriptor's lifetime is no longer pinned
/// at that point (e.g. the peer pipe may have been closed under us).
/// Buffered data left at deinit is dropped — callers that care about
/// flush durability must call `flush()` before releasing the writer.
@available(macOS 10.15.4, iOS 13.4, *)
public class FrameWriter: @unchecked Sendable {
    /// Underlying handle, retained for the lifetime of the writer.
    /// Not exposed as `public` because callers must never invoke
    /// `.fileDescriptor` on it (that accessor raises an Objective-C
    /// exception on a closed handle and aborts the process). All I/O
    /// flows through the cached fd inside this class.
    private let handle: FileHandle
    private var cachedFD: Int32
    private var limits: Limits
    private let lock = NSLock()
    private var buffer: Data = Data()  // 8KB buffer matching Rust's BufWriter

    public init(handle: FileHandle, limits: Limits = Limits()) {
        self.handle = handle
        // Snapshot the descriptor while the handle is open. After this
        // point we never call `handle.fileDescriptor` again, so a
        // later close on the same handle (or the underlying fd) cannot
        // raise NSFileHandleOperationException through this writer.
        let fd = handle.fileDescriptor
        // Suppress SIGPIPE on this descriptor. A write() to a pipe
        // whose reader has closed (e.g. the peer cartridge OOM-died)
        // returns EPIPE — but by default the kernel also raises
        // SIGPIPE on the writer process, which would terminate the
        // host. With F_SETNOSIGPIPE the write just returns -1/EPIPE
        // and we surface a clean `FrameError.ioError("write failed:
        // ...")` to the caller, who can fail the in-flight request
        // and move on. This must be set per-fd at construction
        // because Foundation's FileHandle does not set it for
        // arbitrary descriptors and the global signal handler is
        // process-wide policy we don't want to impose.
        if fd >= 0 {
            _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        }
        self.cachedFD = fd
        self.limits = limits
    }

    /// Update limits (after handshake)
    public func setLimits(_ limits: Limits) {
        lock.lock()
        defer { lock.unlock() }
        self.limits = limits
    }

    /// Get current limits
    public func getLimits() -> Limits {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }

    /// Whether the writer has been closed. Once closed, all writes
    /// and flushes fail with `FrameError.ioError("writer closed")`.
    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedFD < 0
    }

    /// Close the writer: drop any buffered data, close the underlying
    /// handle (best-effort), and transition to the closed state.
    /// Idempotent — second and subsequent calls are no-ops. After
    /// `close()`, all writes and flushes throw cleanly.
    ///
    /// Callers must use this in preference to closing the handle
    /// directly: closing the handle while the writer still believes
    /// its cached fd is valid invites a write into a closed (or
    /// recycled) descriptor, which is silent corruption rather than
    /// a clean error.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if cachedFD < 0 {
            return
        }
        cachedFD = -1
        buffer.removeAll(keepingCapacity: false)
        try? handle.close()
    }

    /// Write a frame (buffered).
    /// Throws `FrameError.ioError("writer closed")` if the writer
    /// has been closed.
    public func write(_ frame: Frame) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeFrame(frame, toFD: cachedFD, limits: limits, buffer: &buffer)
    }

    /// Flush buffered data.
    /// Throws `FrameError.ioError("writer closed")` if the writer
    /// has been closed; throws `FrameError.ioError("write failed: ...")`
    /// on POSIX write failure.
    public func flush() throws {
        lock.lock()
        defer { lock.unlock() }
        if buffer.isEmpty {
            // Even with nothing to flush, an explicit flush on a
            // closed writer is a programmer error worth surfacing.
            if cachedFD < 0 {
                throw FrameError.ioError("writer closed")
            }
            return
        }
        if cachedFD < 0 {
            throw FrameError.ioError("writer closed")
        }
        let fd = cachedFD
        try buffer.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var totalWritten = 0
            while totalWritten < buffer.count {
                let result = Darwin.write(fd, baseAddress.advanced(by: totalWritten), buffer.count - totalWritten)
                if result < 0 {
                    throw FrameError.ioError("write failed: \(String(cString: strerror(errno)))")
                }
                totalWritten += result
            }
        }
        buffer.removeAll(keepingCapacity: true)
    }

    /// Write a large payload as multiple chunks for multiplexed streaming.
    /// - Parameters:
    ///   - id: Request ID
    ///   - streamId: Stream ID for multiplexing
    ///   - contentType: Content type
    ///   - data: Data to chunk
    public func writeChunked(id: MessageId, streamId: String, contentType: String, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        let totalLen = UInt64(data.count)
        let maxChunk = limits.maxChunk

        if data.isEmpty {
            // Empty payload - single chunk with eof
            let emptyData = Data()
            let checksum = Frame.computeChecksum(emptyData)
            var frame = Frame.chunk(reqId: id, streamId: streamId, seq: 0, payload: emptyData, chunkIndex: 0, checksum: checksum)
            frame.contentType = contentType
            frame.len = 0
            frame.offset = 0
            frame.eof = true
            try writeFrame(frame, toFD: cachedFD, limits: limits, buffer: &buffer)
            return
        }

        var chunkIndex: UInt64 = 0
        var offset = 0

        while offset < data.count {
            let chunkSize = min(maxChunk, data.count - offset)
            let isLast = offset + chunkSize >= data.count

            let chunkData = data.subdata(in: offset..<(offset + chunkSize))
            let checksum = Frame.computeChecksum(chunkData)

            // seq=0 for all chunks - SeqAssigner handles seq assignment at output stage
            var frame = Frame.chunk(reqId: id, streamId: streamId, seq: 0, payload: chunkData, chunkIndex: chunkIndex, checksum: checksum)
            frame.offset = UInt64(offset)

            // Set content_type and total len on first chunk (chunk_index-based, not seq-based)
            if chunkIndex == 0 {
                frame.contentType = contentType
                frame.len = totalLen
            }

            if isLast {
                frame.eof = true
            }

            try writeFrame(frame, toFD: cachedFD, limits: limits, buffer: &buffer)

            chunkIndex += 1
            offset += chunkSize
        }
    }
}

// MARK: - Handshake

/// Handshake result including manifest (host side - receives cartridge's HELLO with manifest)
public struct HandshakeResult: Sendable {
    /// Negotiated protocol limits
    public let limits: Limits
    /// Cartridge manifest JSON data (from cartridge's HELLO response)
    public let manifest: Data?
}

/// Perform HELLO handshake and extract cartridge manifest (host side - sends first)
/// Returns HandshakeResult containing negotiated limits and cartridge manifest.
@available(macOS 10.15.4, iOS 13.4, *)
public func performHandshakeWithManifest(reader: FrameReader, writer: FrameWriter) throws -> HandshakeResult {
    // Send our HELLO with our current limits
    let ourLimits = writer.getLimits()
    let ourHello = Frame.hello(limits: ourLimits)
    try writer.write(ourHello)

    // Read their HELLO (should include manifest)
    guard let theirFrame = try reader.read() else {
        throw FrameError.handshakeFailed("Connection closed before receiving HELLO")
    }

    guard theirFrame.frameType == .hello else {
        throw FrameError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
    }

    // Extract manifest - REQUIRED for cartridges
    guard let manifest = theirFrame.helloManifest else {
        throw FrameError.handshakeFailed("Cartridge HELLO missing required manifest")
    }

    // Protocol v2: All three limit fields are REQUIRED
    guard let theirMaxFrame = theirFrame.helloMaxFrame else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_frame")
    }
    guard let theirMaxChunk = theirFrame.helloMaxChunk else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_chunk")
    }
    guard let theirMaxReorderBuffer = theirFrame.helloMaxReorderBuffer else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_reorder_buffer (required in protocol v2)")
    }

    // Negotiate minimum of both sides
    let limits = Limits(
        maxFrame: min(ourLimits.maxFrame, theirMaxFrame),
        maxChunk: min(ourLimits.maxChunk, theirMaxChunk),
        maxReorderBuffer: min(ourLimits.maxReorderBuffer, theirMaxReorderBuffer)
    )

    // Update both reader and writer with negotiated limits
    reader.setLimits(limits)
    writer.setLimits(limits)

    return HandshakeResult(limits: limits, manifest: manifest)
}

/// Accept HELLO handshake with manifest (cartridge side - receives first, sends manifest in response)
/// - Parameters:
///   - reader: Frame reader for incoming data
///   - writer: Frame writer for outgoing data
///   - manifest: Cartridge manifest JSON data to include in HELLO response
/// - Returns: Negotiated protocol limits
@available(macOS 10.15.4, iOS 13.4, *)
public func acceptHandshakeWithManifest(reader: FrameReader, writer: FrameWriter, manifest: Data) throws -> Limits {
    // Read their HELLO first (host initiates)
    guard let theirFrame = try reader.read() else {
        throw FrameError.handshakeFailed("Connection closed before receiving HELLO")
    }

    guard theirFrame.frameType == .hello else {
        throw FrameError.handshakeFailed("Expected HELLO, got \(theirFrame.frameType)")
    }

    // Protocol v2: All three limit fields are REQUIRED
    guard let theirMaxFrame = theirFrame.helloMaxFrame else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_frame")
    }
    guard let theirMaxChunk = theirFrame.helloMaxChunk else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_chunk")
    }
    guard let theirMaxReorderBuffer = theirFrame.helloMaxReorderBuffer else {
        throw FrameError.handshakeFailed("Protocol violation: HELLO missing max_reorder_buffer (required in protocol v2)")
    }

    // Negotiate minimum of both sides
    let ourLimits = writer.getLimits()
    let limits = Limits(
        maxFrame: min(ourLimits.maxFrame, theirMaxFrame),
        maxChunk: min(ourLimits.maxChunk, theirMaxChunk),
        maxReorderBuffer: min(ourLimits.maxReorderBuffer, theirMaxReorderBuffer)
    )

    // Send our HELLO with manifest and negotiated limits
    let ourHello = Frame.helloWithManifest(limits: ourLimits, manifest: manifest)
    try writer.write(ourHello)

    // Update both reader and writer with negotiated limits
    reader.setLimits(limits)
    writer.setLimits(limits)

    return limits
}

