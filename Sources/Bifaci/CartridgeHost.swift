//
//  CartridgeHost.swift
//  Bifaci
//
//  Multi-cartridge host runtime — manages N cartridge binaries with frame routing.
//
//  The CartridgeHost sits between the relay connection (to the engine) and
//  individual cartridge processes. It handles:
//
//  - HELLO handshake and limit negotiation per cartridge
//  - Cap-based routing (REQ by cap_urn, continuation frames by req_id)
//  - Heartbeat health monitoring per cartridge
//  - Cartridge death detection and ERR propagation
//  - Aggregate capability advertisement
//
//  Architecture:
//
//    Relay (engine) <-> CartridgeHost <-> Cartridge A (stdin/stdout)
//                                      <-> Cartridge B (stdin/stdout)
//                                      <-> Cartridge C (stdin/stdout)
//
//  Frame Routing:
//
//  Engine -> Cartridge:
//  - REQ: route by cap_urn to the cartridge that handles it
//  - STREAM_START/CHUNK/STREAM_END/END/ERR: route by req_id to the mapped cartridge
//
//  Cartridge -> Engine:
//  - HEARTBEAT: handled locally, never forwarded
//  - REQ (peer invoke): registered in routing table, forwarded to relay
//  - Everything else: forwarded to relay (pass-through)

import Foundation
import CommonCrypto
import os
@preconcurrency import SwiftCBOR
import CapDAG

private func sha256Hex(for data: Data) -> String {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { bytes in
        _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// Compute a deterministic SHA256 hash of a cartridge directory tree.
/// Walks all files recursively, sorts by relative path, hashes (path + content).
/// Excludes cartridge.json (install-time metadata that varies between installs).
private func computeCartridgeDirectoryHash(atPath dirPath: String) -> String? {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: dirPath) else { return nil }

    var files: [(relativePath: String, fullPath: String)] = []

    while let relativePath = enumerator.nextObject() as? String {
        let fullPath = (dirPath as NSString).appendingPathComponent(relativePath)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir),
              !isDir.boolValue else {
            continue
        }
        if relativePath == "cartridge.json" {
            continue
        }
        files.append((relativePath: relativePath, fullPath: fullPath))
    }

    files.sort { $0.relativePath < $1.relativePath }

    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)

    for file in files {
        if let pathData = file.relativePath.data(using: .utf8) {
            pathData.withUnsafeBytes { bytes in
                CC_SHA256_Update(&context, bytes.baseAddress, CC_LONG(pathData.count))
            }
        }
        guard let data = fileManager.contents(atPath: file.fullPath) else { return nil }
        data.withUnsafeBytes { bytes in
            CC_SHA256_Update(&context, bytes.baseAddress, CC_LONG(data.count))
        }
    }

    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&hash, &context)

    return hash.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Activity Timeout Constants

/// Default timeout (seconds) for inactivity during cap execution.
/// If a cartridge sends no frames for this duration, the cap is aborted.
public let DEFAULT_ACTIVITY_TIMEOUT_SECS: UInt64 = 120

/// Cap metadata key for per-cap activity timeout override.
/// If present, its value (seconds) replaces the default timeout.
public let ACTIVITY_TIMEOUT_METADATA_KEY: String = "activity_timeout_secs"

// MARK: - Error Types

/// Errors that can occur in the cartridge host
public enum CartridgeHostError: Error, LocalizedError, Sendable {
    case handshakeFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case cartridgeError(code: String, message: String)
    case unexpectedFrameType(FrameType)
    case protocolError(String)
    case processExited
    case closed
    case noHandler(String)
    case cartridgeDied(String)
    case peerInvokeNotSupported(String)
    // Protocol violation errors (per-request)
    case duplicateStreamId(String)
    case chunkAfterStreamEnd(String)
    case unknownStreamId(String)
    case chunkMissingStreamId
    case streamAfterRequestEnd

    public var errorDescription: String? {
        switch self {
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .sendFailed(let msg): return "Send failed: \(msg)"
        case .receiveFailed(let msg): return "Receive failed: \(msg)"
        case .cartridgeError(let code, let message): return "Cartridge error [\(code)]: \(message)"
        case .unexpectedFrameType(let t): return "Unexpected frame type: \(t)"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .processExited: return "Cartridge process exited unexpectedly"
        case .closed: return "Host is closed"
        case .noHandler(let cap): return "No handler found for cap: \(cap)"
        case .cartridgeDied(let msg): return "Cartridge died: \(msg)"
        case .duplicateStreamId(let streamId): return "Duplicate stream ID: \(streamId)"
        case .chunkAfterStreamEnd(let streamId): return "Chunk after stream end: \(streamId)"
        case .unknownStreamId(let streamId): return "Unknown stream ID: \(streamId)"
        case .chunkMissingStreamId: return "Chunk missing stream ID"
        case .streamAfterRequestEnd: return "Stream after request end"
        case .peerInvokeNotSupported(let cap): return "Peer invoke not supported for cap: \(cap)"
        }
    }
}

/// A response chunk from a cartridge
public struct ResponseChunk: Sendable {
    public let payload: Data
    public let seq: UInt64
    public let offset: UInt64?
    public let len: UInt64?
    public let isEof: Bool

    public init(payload: Data, seq: UInt64, offset: UInt64?, len: UInt64?, isEof: Bool) {
        self.payload = payload
        self.seq = seq
        self.offset = offset
        self.len = len
        self.isEof = isEof
    }
}

/// Response from a cartridge request (for convenience call() method)
public enum CartridgeResponse: Sendable {
    case single(Data)
    case streaming([ResponseChunk])

    public var finalPayload: Data? {
        switch self {
        case .single(let data): return data
        case .streaming(let chunks): return chunks.last?.payload
        }
    }

    public func concatenated() -> Data {
        switch self {
        case .single(let data): return data
        case .streaming(let chunks):
            var result = Data()
            for chunk in chunks {
                result.append(chunk.payload)
            }
            return result
        }
    }
}

// MARK: - Cartridge Process Info

/// Snapshot of a managed cartridge process, used for external monitoring
/// (e.g., memory pressure management).
public struct CartridgeProcessInfo: Sendable {
    /// Index of the cartridge in the host's cartridge list.
    public let cartridgeIndex: Int
    /// OS process ID.
    public let pid: pid_t
    /// Binary name (e.g. "ggufcartridge", "modelcartridge").
    public let name: String
    /// Whether the cartridge is currently running and responsive.
    public let running: Bool
    /// Cap URN strings this cartridge handles.
    public let caps: [String]
    /// Physical memory footprint in MB (self-reported by cartridge via heartbeat).
    /// This is `ri_phys_footprint` — the metric macOS jetsam uses for kill decisions.
    /// Updated every 30s when the cartridge responds to a heartbeat probe.
    public let memoryFootprintMb: UInt64
    /// Resident set size in MB (self-reported by cartridge via heartbeat).
    public let memoryRssMb: UInt64
}

// MARK: - Internal Types

/// Events from reader threads, delivered to the main run() loop.
private enum CartridgeEvent {
    case frame(cartridgeIdx: Int, frame: Frame)
    case death(cartridgeIdx: Int)
    case relayFrame(Frame)
    case relayClosed
}

/// Composite routing key: (XID, RID) — uniquely identifies a request flow from relay.
/// XID is assigned by RelaySwitch, RID is the request's MessageId.
private struct RxidKey: Hashable {
    let xid: MessageId
    let rid: MessageId
}

/// Interval between heartbeat probes (seconds).
private let HEARTBEAT_INTERVAL: TimeInterval = 30.0

/// Maximum time to wait for a heartbeat response (seconds).
private let HEARTBEAT_TIMEOUT: TimeInterval = 10.0

/// A managed cartridge binary.
@available(macOS 10.15.4, iOS 13.4, *)
/// Why a cartridge was killed. Determines whether pending requests get ERR frames.
enum ShutdownReason {
    /// App is exiting or cartridge binary removed. No ERR frames — relay connection
    /// is closing anyway and there are no callers left to notify.
    case appExit
    /// OOM watchdog killed the cartridge while it was actively processing requests.
    /// Pending requests MUST get ERR frames with code "OOM_KILLED" so callers
    /// can fail fast instead of hanging forever.
    case oomKill
    /// Request was cancelled. Pending requests get ERR frames with code "CANCELLED".
    case cancelled
}

private class ManagedCartridge {
    /// Absolute path to the entry point binary (resolved from cartridge.json).
    let path: String
    /// Absolute path to the version directory containing cartridge.json.
    /// This is the anchor — the entry point is relative to this directory.
    let cartridgeDir: String
    var pid: pid_t?
    var stdinHandle: FileHandle?
    var stdoutHandle: FileHandle?
    var stderrHandle: FileHandle?
    var writer: FrameWriter?
    let writerLock = NSLock()
    var manifest: Data
    var limits: Limits
    var caps: [String]
    var knownCaps: [String]
    var running: Bool
    var helloFailed: Bool
    var readerThread: Thread?
    var pendingHeartbeats: [MessageId: Date]
    /// Last death error message (includes stderr if available). Used for ERR frames
    /// sent when attempting to write to a dead cartridge.
    var lastDeathMessage: String?
    /// Set before calling killProcess() to signal why the death occurred.
    /// `handleCartridgeDeath` checks this to determine ERR frame behavior:
    /// - `nil` → unexpected crash → ERR "CARTRIDGE_DIED"
    /// - `.oomKill` → OOM watchdog kill → ERR "OOM_KILLED"
    /// - `.appExit` → clean shutdown → no ERR frames
    var shutdownReason: ShutdownReason?
    /// Physical memory footprint in MB (self-reported via heartbeat response meta).
    var memoryFootprintMb: UInt64
    /// Resident set size in MB (self-reported via heartbeat response meta).
    var memoryRssMb: UInt64

    init(path: String, cartridgeDir: String, knownCaps: [String]) {
        self.path = path
        self.cartridgeDir = cartridgeDir
        self.manifest = Data()
        self.limits = Limits()
        self.caps = []
        self.knownCaps = knownCaps
        self.running = false
        self.helloFailed = false
        self.pendingHeartbeats = [:]
        self.lastDeathMessage = nil
        self.shutdownReason = nil
        self.memoryFootprintMb = 0
        self.memoryRssMb = 0
    }

    func installedCartridgeIdentity() -> InstalledCartridgeIdentity? {
        guard !cartridgeDir.isEmpty else { return nil }

        // Read cartridge.json from the version directory (the anchor)
        let cartridgeJsonPath = (cartridgeDir as NSString).appendingPathComponent("cartridge.json")
        guard let data = FileManager.default.contents(atPath: cartridgeJsonPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let version = json["version"] as? String else {
            return nil
        }

        // Hash the directory tree (excluding cartridge.json)
        guard let sha256 = computeCartridgeDirectoryHash(atPath: cartridgeDir) else {
            fatalError("Installed cartridge directory must remain readable at \(cartridgeDir)")
        }

        return InstalledCartridgeIdentity(
            id: name.lowercased(),
            version: version,
            sha256: sha256
        )
    }

    static func attached(manifest: Data, limits: Limits, caps: [String]) -> ManagedCartridge {
        let cartridge = ManagedCartridge(path: "", cartridgeDir: "", knownCaps: caps)
        cartridge.manifest = manifest
        cartridge.limits = limits
        cartridge.caps = caps
        cartridge.running = true
        return cartridge
    }

    /// Kill the cartridge process if running. Waits for exit.
    func killProcess() {
        guard let p = pid else { return }
        kill(p, SIGTERM)
        var status: Int32 = 0
        let result = waitpid(p, &status, WNOHANG)
        if result == 0 {
            // Still running after SIGTERM
            Thread.sleep(forTimeInterval: 0.5)
            let result2 = waitpid(p, &status, WNOHANG)
            if result2 == 0 {
                kill(p, SIGKILL)
                _ = waitpid(p, &status, 0)
            }
        }
        pid = nil
    }

    /// Write a frame to this cartridge's stdin (thread-safe).
    /// Returns false if the cartridge is dead or write fails.
    @discardableResult
    func writeFrame(_ frame: Frame) -> Bool {
        writerLock.lock()
        defer { writerLock.unlock() }
        guard let w = writer else { return false }
        do {
            try w.write(frame)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - CartridgeHost

/// Multi-cartridge host runtime managing N cartridge processes.
///
/// Routes CBOR protocol frames between a relay connection (engine) and
/// individual cartridge processes. Handles HELLO handshake, heartbeat health
/// monitoring, and capability advertisement.
///
/// Usage:
/// ```swift
/// let host = CartridgeHost()
/// try host.attachCartridge(stdinHandle: cartridgeStdin, stdoutHandle: cartridgeStdout)
/// try host.run(relayRead: relayReadHandle, relayWrite: relayWriteHandle) { Data() }
/// ```
@available(macOS 10.15.4, iOS 13.4, *)
public final class CartridgeHost: @unchecked Sendable {

    // MARK: - Properties

    private static let log = OSLog(subsystem: "com.machinefabric.bifaci", category: "CartridgeHost")

    /// Managed cartridge binaries.
    private var cartridges: [ManagedCartridge] = []

    /// Routing: cap_urn -> cartridge index.
    private var capTable: [(String, Int)] = []

    /// List 1: OUTGOING_RIDS — tracks peer requests sent BY cartridges (RID → cartridge_idx).
    /// Used for death cleanup (ERR all pending peer requests when cartridge dies).
    /// Cleaned up only on cartridge death, never on terminal frames.
    private var outgoingRids: [MessageId: Int] = [:]

    /// List 2: INCOMING_RXIDS — tracks incoming requests FROM relay ((XID, RID) → cartridge_idx).
    /// Routes continuation frames (STREAM_START/CHUNK/STREAM_END/END/ERR) to the correct cartridge.
    /// NEVER cleaned up on terminal frames — intentionally leaked until cartridge death.
    /// This avoids premature cleanup in self-loop peer request scenarios where the same RID
    /// appears in both outgoing and incoming maps.
    private var incomingRxids: [RxidKey: Int] = [:]

    /// Tracks which incoming request spawned which outgoing peer RIDs.
    /// Maps parent (xid, rid) → list of child peer RIDs. Used for cancel cascade.
    private var incomingToPeerRids: [RxidKey: [MessageId]] = [:]

    /// Aggregate capabilities (serialized JSON manifest of all cartridge caps).
    private var _capabilities: Data = Data()

    /// State lock — protects cartridges, capTable, outgoingRids, incomingRxids, capabilities, closed.
    private let stateLock = NSLock()

    /// Outbound writer — writes frames to the relay (toward engine).
    private var outboundWriter: FrameWriter?
    private let outboundLock = NSLock()

    /// Max-seen seq per flow for cartridge-originated frames.
    /// Used to set seq on host-generated ERR frames (max_seen + 1).
    /// Protected by stateLock (same as outgoingRids/incomingRxids).
    private var outgoingMaxSeq: [FlowKey: UInt64] = [:]

    /// Cartridge events from reader threads.
    private var eventQueue: [CartridgeEvent] = []
    private let eventLock = NSLock()
    private let eventSemaphore = DispatchSemaphore(value: 0)

    /// Whether the host is closed.
    private var closed = false

    // MARK: - Initialization

    /// Create a new cartridge host runtime.
    ///
    /// After creation, register cartridges with `registerCartridge()` or
    /// attach pre-connected cartridges with `attachCartridge()`, then call `run()`.
    public init() {}

    // MARK: - Cartridge Management

    /// Register a cartridge for on-demand spawning.
    ///
    /// The cartridge is NOT spawned immediately. It will be spawned on demand when
    /// a REQ arrives for one of its known caps.
    ///
    /// - Parameters:
    ///   - path: Path to the entry point binary (resolved from cartridge.json)
    ///   - cartridgeDir: Path to the version directory containing cartridge.json
    ///   - knownCaps: Cap URNs this cartridge is expected to handle
    public func registerCartridge(path: String, cartridgeDir: String, knownCaps: [String]) {
        stateLock.lock()
        let cartridge = ManagedCartridge(path: path, cartridgeDir: cartridgeDir, knownCaps: knownCaps)
        let idx = cartridges.count
        cartridges.append(cartridge)
        for cap in knownCaps {
            capTable.append((cap, idx))
        }
        rebuildCapabilities()
        stateLock.unlock()
    }

    /// Reconcile the host's cartridge state with the current on-disk truth.
    ///
    /// After a rescan, the XPC service calls this instead of accumulating
    /// registerCartridge() calls.  This ensures stale entries (old binary paths)
    /// are removed so findCartridgeForCap() never routes to a dead binary.
    ///
    /// Semantics:
    /// - **Same path** (binary unchanged): no-op (caps updated if they changed).
    /// - **Path gone** (in host, not in `current`): kill process, remove from capTable.
    /// - **New path** (in `current`, not in host): append.
    ///
    /// Matches by **path**, not by cap set — URN strings are not stable across
    /// rescans (quoting and tag order may differ), but the binary path is.
    ///
    /// - Parameter current: The ground-truth list of `(binaryPath, capURNs)` from disk.
    public func syncRegistrations(_ current: [(path: String, cartridgeDir: String, knownCaps: [String])]) {
        stateLock.lock()
        defer {
            rebuildCapabilities()
            stateLock.unlock()
        }

        // Build a lookup: path → index in `current`.
        let currentByPath: [String: Int] = {
            var map = [String: Int]()
            for (i, entry) in current.enumerated() {
                map[entry.path] = i
            }
            return map
        }()

        var matchedCurrentIndices = Set<Int>()

        // Walk existing cartridges and reconcile.
        for cartridge in cartridges {
            if let currentIdx = currentByPath[cartridge.path] {
                // Same entry point path still on disk — keep it.
                matchedCurrentIndices.insert(currentIdx)
                let entry = current[currentIdx]
                // Update knownCaps in case they changed (harmless if identical).
                cartridge.knownCaps = entry.knownCaps
                // Clear helloFailed so the cartridge can be respawned on demand.
                cartridge.helloFailed = false
            } else {
                // Cartridge path no longer on disk — removed or replaced by new version.
                cartridge.shutdownReason = .appExit
                cartridge.killProcess()
                cartridge.writerLock.lock()
                cartridge.writer = nil
                cartridge.writerLock.unlock()
                cartridge.stdinHandle = nil
                cartridge.stdoutHandle = nil
                cartridge.stderrHandle = nil
                cartridge.helloFailed = true  // Prevent on-demand spawn
                cartridge.knownCaps = []      // Remove from capTable rebuild
                cartridge.caps = []
            }
        }

        // Append genuinely new cartridges (path not in host).
        for (i, entry) in current.enumerated() where !matchedCurrentIndices.contains(i) {
            let cartridge = ManagedCartridge(path: entry.path, cartridgeDir: entry.cartridgeDir, knownCaps: entry.knownCaps)
            cartridges.append(cartridge)
        }

        // Rebuild capTable from scratch — covers new, updated, and removed cartridges.
        capTable.removeAll()
        for (idx, cartridge) in cartridges.enumerated() where !cartridge.helloFailed {
            for cap in cartridge.knownCaps {
                capTable.append((cap, idx))
            }
        }
    }

    /// Attach a pre-connected cartridge (already running, ready for handshake).
    ///
    /// Performs HELLO handshake synchronously. Extracts manifest and caps.
    /// Starts a reader thread for this cartridge.
    ///
    /// - Parameters:
    ///   - stdinHandle: FileHandle to write to the cartridge's stdin
    ///   - stdoutHandle: FileHandle to read from the cartridge's stdout
    /// - Returns: Cartridge index
    /// - Throws: CartridgeHostError if handshake fails
    @discardableResult
    public func attachCartridge(stdinHandle: FileHandle, stdoutHandle: FileHandle) throws -> Int {
        let reader = FrameReader(handle: stdoutHandle)
        let writer = FrameWriter(handle: stdinHandle)

        // Perform HELLO handshake
        let ourLimits = Limits()
        let ourHello = Frame.hello(limits: ourLimits)
        try writer.write(ourHello)

        guard let theirHello = try reader.read() else {
            throw CartridgeHostError.handshakeFailed("Cartridge closed connection before HELLO")
        }
        guard theirHello.frameType == .hello else {
            throw CartridgeHostError.handshakeFailed("Expected HELLO, got \(theirHello.frameType)")
        }
        guard let manifest = theirHello.helloManifest else {
            throw CartridgeHostError.handshakeFailed("Cartridge HELLO missing required manifest")
        }

        // Protocol v2: All three limit fields are REQUIRED
        guard let theirMaxFrame = theirHello.helloMaxFrame else {
            throw CartridgeHostError.handshakeFailed("Protocol violation: HELLO missing max_frame")
        }
        guard let theirMaxChunk = theirHello.helloMaxChunk else {
            throw CartridgeHostError.handshakeFailed("Protocol violation: HELLO missing max_chunk")
        }
        guard let theirMaxReorderBuffer = theirHello.helloMaxReorderBuffer else {
            throw CartridgeHostError.handshakeFailed("Protocol violation: HELLO missing max_reorder_buffer (required in protocol v2)")
        }

        let negotiatedLimits = Limits(
            maxFrame: min(ourLimits.maxFrame, theirMaxFrame),
            maxChunk: min(ourLimits.maxChunk, theirMaxChunk),
            maxReorderBuffer: min(ourLimits.maxReorderBuffer, theirMaxReorderBuffer)
        )
        writer.setLimits(negotiatedLimits)
        reader.setLimits(negotiatedLimits)

        // Parse caps from manifest (validates CAP_IDENTITY presence)
        let caps = try Self.extractCaps(from: manifest)

        // Perform identity verification - send nonce, expect echo
        try Self.verifyCartridgeIdentity(reader: reader, writer: writer)

        // Create managed cartridge
        let cartridge = ManagedCartridge.attached(manifest: manifest, limits: negotiatedLimits, caps: caps)
        cartridge.stdinHandle = stdinHandle
        cartridge.stdoutHandle = stdoutHandle
        cartridge.writer = writer

        stateLock.lock()
        let idx = cartridges.count
        cartridges.append(cartridge)
        for cap in caps {
            capTable.append((cap, idx))
        }
        rebuildCapabilities()
        stateLock.unlock()

        // Start reader thread for this cartridge
        startCartridgeReaderThread(cartridgeIdx: idx, reader: reader)

        return idx
    }

    /// Get the aggregate capabilities manifest (JSON-encoded list of all cartridge caps).
    public var capabilities: Data {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _capabilities
    }

    /// Find which cartridge handles a given cap URN.
    ///
    /// Uses exact string match first, then URN-level accepts() for semantic matching.
    ///
    /// - Parameter capUrn: The cap URN to look up
    /// - Returns: Cartridge index, or nil if no cartridge handles this cap
    public func findCartridgeForCap(_ capUrn: String) -> Int? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return findCartridgeForCapLocked(capUrn)
    }

    /// Internal: find cartridge for cap (must hold stateLock).
    ///
    /// Uses `isDispatchable(provider, request)` to find cartridges that can
    /// legally handle the request, then ranks by specificity.
    ///
    /// Ranking prefers:
    /// 1. Equivalent matches (distance 0)
    /// 2. More specific providers (positive distance) - refinements
    /// 3. More generic providers (negative distance) - fallbacks
    private func findCartridgeForCapLocked(_ capUrn: String) -> Int? {
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else { return nil }

        let requestSpecificity = Int(requestUrn.specificity())
        var matches: [(cartridgeIdx: Int, signedDistance: Int)] = []

        for (registeredCap, cartridgeIdx) in capTable {
            if let registeredUrn = try? CSCapUrn.fromString(registeredCap) {
                if registeredUrn.isDispatchable(requestUrn) {
                    let specificity = Int(registeredUrn.specificity())
                    let signedDistance = specificity - requestSpecificity
                    matches.append((cartridgeIdx, signedDistance))
                }
            }
        }

        guard !matches.isEmpty else { return nil }

        // Ranking: prefer equivalent (0), then more specific (+), then more generic (-)
        matches.sort { a, b in
            let (_, distA) = a
            let (_, distB) = b
            if distA >= 0 && distB < 0 { return true }
            if distA < 0 && distB >= 0 { return false }
            return abs(distA) < abs(distB)
        }

        return matches.first?.cartridgeIdx
    }

    // MARK: - Main Run Loop

    /// Main run loop. Reads frames from the relay, routes to cartridges.
    /// Cartridge reader threads forward cartridge frames to the relay.
    ///
    /// Blocks until the relay closes or a fatal error occurs.
    ///
    /// - Parameters:
    ///   - relayRead: FileHandle to read frames from (relay/engine side)
    ///   - relayWrite: FileHandle to write frames to (relay/engine side)
    ///   - resourceFn: Callback to get current system resource state
    /// - Throws: CartridgeHostError on fatal errors
    public func run(
        relayRead: FileHandle,
        relayWrite: FileHandle,
        resourceFn: @escaping () -> Data
    ) throws {
        outboundLock.lock()
        outboundWriter = FrameWriter(handle: relayWrite)
        outboundLock.unlock()

        // Send initial RelayNotify with capabilities from any already-attached cartridges.
        // Cartridges attached before run() was called won't have sent their RelayNotify yet.
        stateLock.lock()
        rebuildCapabilities()
        stateLock.unlock()

        // Start relay reader thread — feeds into the same event queue as cartridge readers
        let relayReader = FrameReader(handle: relayRead)
        let relayThread = Thread { [weak self] in
            while true {
                do {
                    guard let frame = try relayReader.read() else {
                        self?.pushEvent(.relayClosed)
                        break
                    }
                    self?.pushEvent(.relayFrame(frame))
                } catch {
                    self?.pushEvent(.relayClosed)
                    break
                }
            }
        }
        relayThread.name = "CartridgeHost.relay"
        relayThread.start()

        // Main loop: wait for events from any source (relay or cartridges)
        while true {
            eventSemaphore.wait()

            eventLock.lock()
            guard !eventQueue.isEmpty else {
                eventLock.unlock()
                continue
            }
            let event = eventQueue.removeFirst()
            eventLock.unlock()

            switch event {
            case .relayFrame(let frame):
                handleRelayFrame(frame)
            case .relayClosed:
                // Clean shutdown
                stateLock.lock()
                closed = true
                stateLock.unlock()
                return
            case .frame(let cartridgeIdx, let frame):
                handleCartridgeFrame(cartridgeIdx: cartridgeIdx, frame: frame)
            case .death(let cartridgeIdx):
                handleCartridgeDeath(cartridgeIdx: cartridgeIdx)
            }
        }
    }

    // MARK: - Relay Frame Handling (Engine -> Cartridge)

    /// Handle a frame received from the relay (engine side).
    ///
    /// All relay frames MUST have XID (assigned by RelaySwitch).
    /// Routes incoming REQs to cartridges by cap URN, continuation frames by (XID, RID).
    /// NEVER cleans up incomingRxids on terminal frames — intentionally leaked until cartridge death.
    private func handleRelayFrame(_ frame: Frame) {
        if frame.frameType != .log {
            os_log(.debug, log: Self.log, "[handleRelayFrame] %{public}@ id=%{public}@ xid=%{public}@", String(describing: frame.frameType), String(describing: frame.id), String(describing: frame.routingId))
        }
        switch frame.frameType {
        case .req:
            // REQ from relay MUST have XID
            guard let xid = frame.routingId else {
                sendToRelay(Frame.err(id: frame.id, code: "PROTOCOL_ERROR", message: "REQ from relay missing XID"))
                return
            }

            guard let capUrn = frame.cap else {
                var err = Frame.err(id: frame.id, code: "INVALID_REQUEST", message: "REQ missing cap URN")
                err.routingId = xid
                sendToRelay(err)
                return
            }

            // Check for target_cartridge in meta — if present, route directly
            let targetCartridgeId: String? = frame.meta.flatMap { meta in
                if case let .utf8String(s) = meta["target_cartridge"] {
                    return s
                }
                return nil
            }

            stateLock.lock()
            let cartridgeIdx: Int
            if let targetId = targetCartridgeId {
                // Direct routing by cartridge identity
                if let foundIdx = cartridges.firstIndex(where: {
                    $0.installedCartridgeIdentity()?.id == targetId
                }) {
                    if cartridges[foundIdx].helloFailed {
                        stateLock.unlock()
                        var err = Frame.err(id: frame.id, code: "CARTRIDGE_UNAVAILABLE",
                                           message: "Cartridge '\(targetId)' failed handshake and cannot be spawned")
                        err.routingId = xid
                        sendToRelay(err)
                        return
                    }
                    cartridgeIdx = foundIdx
                } else {
                    stateLock.unlock()
                    var err = Frame.err(id: frame.id, code: "CARTRIDGE_NOT_FOUND",
                                       message: "Cartridge '\(targetId)' not found on this host")
                    err.routingId = xid
                    sendToRelay(err)
                    return
                }
            } else {
                // Standard cap-based dispatch
                guard let foundIdx = findCartridgeForCapLocked(capUrn) else {
                    stateLock.unlock()
                    var err = Frame.err(id: frame.id, code: "NO_HANDLER", message: "No cartridge handles cap: \(capUrn)")
                    err.routingId = xid
                    sendToRelay(err)
                    return
                }
                cartridgeIdx = foundIdx
            }
            let needsSpawn = !cartridges[cartridgeIdx].running && !cartridges[cartridgeIdx].helloFailed
            stateLock.unlock()

            // Spawn on demand if registered but not running
            if needsSpawn {
                do {
                    try spawnCartridge(at: cartridgeIdx)
                } catch {
                    var err = Frame.err(id: frame.id, code: "SPAWN_FAILED", message: "Failed to spawn cartridge: \(error.localizedDescription)")
                    err.routingId = xid
                    sendToRelay(err)
                    return
                }
            }

            // Record in INCOMING_RXIDS: (XID, RID) → cartridge_idx
            let key = RxidKey(xid: xid, rid: frame.id)
            stateLock.lock()
            incomingRxids[key] = cartridgeIdx
            let cartridge = cartridges[cartridgeIdx]
            stateLock.unlock()

            os_log(.debug, log: Self.log, "[handleRelayFrame] REQ dispatched to cartridge %d cap=%{public}@ xid=%{public}@ rid=%{public}@", cartridgeIdx, String(describing: frame.cap), String(describing: xid), String(describing: frame.id))
            if !cartridge.writeFrame(frame) {
                // Cartridge is dead — send ERR with XID and clean up
                let deathMsg = cartridge.lastDeathMessage ?? "Cartridge exited while processing request"
                var err = Frame.err(id: frame.id, code: "CARTRIDGE_DIED", message: deathMsg)
                err.routingId = xid
                sendToRelay(err)
                stateLock.lock()
                incomingRxids.removeValue(forKey: key)
                stateLock.unlock()
            }

        case .streamStart, .chunk, .streamEnd, .end, .err:
            // Continuation from relay MUST have XID
            guard let xid = frame.routingId else {
                fputs("[CartridgeHost] Protocol error: continuation from relay missing XID\n", stderr)
                return
            }

            let key = RxidKey(xid: xid, rid: frame.id)

            // Route by (XID, RID) to the mapped cartridge
            stateLock.lock()
            var cartridgeIdx = incomingRxids[key]
            if cartridgeIdx == nil {
                // Not an incoming engine request — check if it's a peer response.
                // outgoingRids[RID] tracks which cartridge made a peer request with this RID.
                cartridgeIdx = outgoingRids[frame.id]
            }
            guard let resolvedIdx = cartridgeIdx else {
                stateLock.unlock()
                // Already cleaned up (e.g., cartridge died, death handler sent ERR)
                return
            }
            let cartridge = cartridges[resolvedIdx]
            stateLock.unlock()

            // If the cartridge is dead, send ERR to engine with XID and clean up
            if !cartridge.writeFrame(frame) {
                let flowKey = FlowKey(rid: frame.id, xid: xid)
                stateLock.lock()
                let nextSeq = (outgoingMaxSeq.removeValue(forKey: flowKey) ?? 0) + 1
                outgoingRids.removeValue(forKey: frame.id)
                incomingRxids.removeValue(forKey: key)
                stateLock.unlock()
                let deathMsg = cartridge.lastDeathMessage ?? "Cartridge exited while processing request"
                var err = Frame.err(id: frame.id, code: "CARTRIDGE_DIED", message: deathMsg)
                err.routingId = xid
                err.seq = nextSeq
                sendToRelay(err)
                return
            }

            // NOTE: Do NOT cleanup incomingRxids here!
            // Frames arrive asynchronously — END can arrive before StreamStart/Chunk.
            // We can't know when "all frames for (XID, RID) have arrived" without full stream tracking.
            // Accept the leak: entries cleaned up on cartridge death.

        case .log:
            // LOG frames from peer responses — route back to the cartridge that
            // made the peer request. Identified by outgoingRids[RID].
            stateLock.lock()
            let cartridgeIdx = outgoingRids[frame.id]
            stateLock.unlock()

            if let idx = cartridgeIdx {
                let cartridge = cartridges[idx]
                let _ = cartridge.writeFrame(frame)
            }
            // If not a peer response LOG, ignore silently (e.g., stale routing)

        case .hello, .heartbeat:
            // These should never arrive from the engine through the relay
            fputs("[CartridgeHost] Protocol error: \(frame.frameType) from relay\n", stderr)

        case .cancel:
            // Cancel from relay — route to the cartridge handling this request.
            guard let xid = frame.routingId else {
                fputs("[CartridgeHost] Cancel frame missing XID — ignoring\n", stderr)
                return
            }
            let rid = frame.id
            let key = RxidKey(xid: xid, rid: rid)
            let forceKill = frame.forceKill ?? false

            stateLock.lock()
            guard let cartridgeIdx = incomingRxids[key] else {
                stateLock.unlock()
                fputs("[CartridgeHost] Cancel for unknown request (\(xid), \(rid)) — ignoring\n", stderr)
                return
            }

            if forceKill {
                // Force kill: set shutdown reason and kill the process
                fputs("[CartridgeHost] Cancel force_kill=true for cartridge \(cartridgeIdx) rid=\(rid)\n", stderr)
                cartridges[cartridgeIdx].shutdownReason = .cancelled
                let pid = cartridges[cartridgeIdx].pid
                stateLock.unlock()
                if let pid = pid {
                    kill(pid, SIGKILL)
                }
            } else {
                // Cooperative cancel: forward Cancel frame to the cartridge
                fputs("[CartridgeHost] Cancel cooperative for cartridge \(cartridgeIdx) rid=\(rid)\n", stderr)
                let cartridge = cartridges[cartridgeIdx]
                stateLock.unlock()
                let _ = cartridge.writeFrame(frame)

                // Also cascade: send Cancel to relay for each peer call spawned by this request
                stateLock.lock()
                if let peerRids = incomingToPeerRids[key] {
                    stateLock.unlock()
                    for peerRid in peerRids {
                        fputs("[CartridgeHost] Cascading Cancel to peer call rid=\(peerRid)\n", stderr)
                        let cancel = Frame.cancel(targetRid: peerRid, forceKill: false)
                        sendToRelay(cancel)
                    }
                } else {
                    stateLock.unlock()
                }
            }

        case .relayNotify, .relayState:
            // Relay frames should be intercepted by the relay layer, never reach here
            fputs("[CartridgeHost] Protocol error: relay frame \(frame.frameType) reached host\n", stderr)
        }
    }

    // MARK: - Cartridge Frame Handling (Cartridge -> Engine)

    /// Handle a frame received from a cartridge.
    ///
    /// REQ frames register in outgoingRids (peer invoke tracking).
    /// All frames track max-seen seq per FlowKey for host-generated ERR frames.
    /// All other frames are forwarded to relay as-is — no routing decisions needed
    /// (there's only one relay destination).
    private func handleCartridgeFrame(cartridgeIdx: Int, frame: Frame) {
        if frame.frameType != .log {
            os_log(.debug, log: Self.log, "[handleCartridgeFrame] cartridge=%d %{public}@ id=%{public}@ xid=%{public}@", cartridgeIdx, String(describing: frame.frameType), String(describing: frame.id), String(describing: frame.routingId))
        }
        switch frame.frameType {
        case .hello:
            // HELLO should be consumed during handshake, never during run
            fputs("[CartridgeHost] Protocol error: HELLO from cartridge \(cartridgeIdx) during run\n", stderr)

        case .heartbeat:
            // Handle heartbeat locally, never forward
            stateLock.lock()
            let cartridge = cartridges[cartridgeIdx]
            let wasOurs = cartridge.pendingHeartbeats.removeValue(forKey: frame.id) != nil

            if wasOurs {
                // Response to our health probe — cartridge is alive.
                // Extract self-reported memory from heartbeat response meta.
                if let meta = frame.meta {
                    if case .unsignedInt(let v) = meta["footprint_mb"] {
                        cartridge.memoryFootprintMb = v
                    }
                    if case .unsignedInt(let v) = meta["rss_mb"] {
                        cartridge.memoryRssMb = v
                    }
                }
            }
            stateLock.unlock()

            if !wasOurs {
                // Cartridge-initiated heartbeat — respond
                cartridge.writeFrame(Frame.heartbeat(id: frame.id))
            }

        case .relayNotify, .relayState:
            // Cartridges must never send relay frames
            fputs("[CartridgeHost] Protocol error: relay frame \(frame.frameType) from cartridge \(cartridgeIdx)\n", stderr)

        case .req:
            // Cartridge peer invoke — record in OUTGOING_RIDS and track max-seen seq.
            // Cartridges MUST NOT send XID (that's a relay-level concept).
            stateLock.lock()
            outgoingRids[frame.id] = cartridgeIdx
            let flowKey = FlowKey.fromFrame(frame)
            outgoingMaxSeq[flowKey] = frame.seq

            // Track parent→child peer call mapping for cancel cascade
            if let meta = frame.meta, let parentRidCbor = meta["parent_rid"] {
                let parentRid: MessageId?
                switch parentRidCbor {
                case .byteString(let bytes) where bytes.count == 16:
                    parentRid = .uuid(Data(bytes))
                case .unsignedInt(let n):
                    parentRid = .uint(n)
                default:
                    parentRid = nil
                }
                if let parentRid = parentRid {
                    // Find the parent's incoming key
                    let parentKey = incomingRxids.first(where: { $0.key.rid == parentRid })?.key
                    if let pk = parentKey {
                        incomingToPeerRids[pk, default: []].append(frame.id)
                    }
                }
            }
            stateLock.unlock()
            sendToRelay(frame)

        default:
            // Everything else: forward as-is to relay.
            // Track max-seen seq for flow, clean up on terminal.
            if frame.isFlowFrame() {
                let flowKey = FlowKey.fromFrame(frame)
                stateLock.lock()
                let isTerminal = frame.frameType == .end || frame.frameType == .err
                if isTerminal {
                    outgoingMaxSeq.removeValue(forKey: flowKey)
                } else {
                    outgoingMaxSeq[flowKey] = frame.seq
                }
                stateLock.unlock()
            }
            sendToRelay(frame)
        }
    }

    // MARK: - Cartridge Death Handling

    /// Handle a cartridge death (reader thread detected EOF/error).
    ///
    /// Three cases based on `shutdownReason`:
    /// 1. **`nil`** (unexpected death): Genuine crash. Send ERR "CARTRIDGE_DIED"
    ///    for all pending requests, store death message.
    /// 2. **`.oomKill`**: OOM watchdog killed the cartridge while it was
    ///    actively processing. Send ERR "OOM_KILLED" for all pending requests
    ///    so callers fail fast instead of hanging.
    /// 3. **`.appExit`**: Clean shutdown. No ERR frames — the relay
    ///    connection is closing anyway.
    private func handleCartridgeDeath(cartridgeIdx: Int) {
        stateLock.lock()
        let cartridge = cartridges[cartridgeIdx]
        cartridge.running = false
        cartridge.writer = nil
        let reason = cartridge.shutdownReason
        cartridge.shutdownReason = nil  // Reset for potential respawn

        // Check process status and kill if still running.
        // The reader thread got EOF on stdout, but the process may still be alive
        // (e.g. if a library closed stdout). We must kill before reading stderr,
        // because readToEnd blocks until the pipe's write end closes.
        var exitInfo = ""
        if let p = cartridge.pid {
            var status: Int32 = 0
            var wpid = waitpid(p, &status, WNOHANG)
            if wpid == 0 {
                // Process still running — stdout closed but process alive.
                // Kill it so we can collect stderr.
                kill(p, SIGTERM)
                Thread.sleep(forTimeInterval: 0.1)
                wpid = waitpid(p, &status, WNOHANG)
                if wpid == 0 {
                    kill(p, SIGKILL)
                    wpid = waitpid(p, &status, 0)  // blocking wait
                }
                exitInfo = "stdout closed while process still running"
            }
            if wpid > 0 {
                if (status & 0x7F) != 0 {
                    let sig = status & 0x7F
                    let info = "killed by signal \(sig)"
                    exitInfo = exitInfo.isEmpty ? info : "\(exitInfo), \(info)"
                } else {
                    let code = (status >> 8) & 0xFF
                    let info = "exit code \(code)"
                    exitInfo = exitInfo.isEmpty ? info : "\(exitInfo), \(info)"
                }
            } else if wpid < 0 {
                exitInfo = "waitpid failed (errno=\(errno))"
            }
            cartridge.pid = nil
        }

        // Now that the process is dead, read stderr — readToEnd will get
        // EOF immediately since the write end is closed.
        var stderrContent = ""
        if let stderrHandle = cartridge.stderrHandle {
            var allData = Data()
            if let data = try? stderrHandle.readToEnd(), !data.isEmpty {
                allData = data
            }
            if !allData.isEmpty {
                if let text = String(data: allData, encoding: .utf8) {
                    let maxLen = 2000
                    if text.count > maxLen {
                        stderrContent = String(text.prefix(maxLen)) + "... [truncated]"
                    } else {
                        stderrContent = text
                    }
                }
            }
            try? stderrHandle.close()
            cartridge.stderrHandle = nil
        }

        if let stdinHandle = cartridge.stdinHandle {
            try? stdinHandle.close()
            cartridge.stdinHandle = nil
        }

        // Clean up routing tables regardless of death cause.
        // outgoingRids: peer requests the cartridge initiated
        var failedOutgoing: [(rid: MessageId, nextSeq: UInt64)] = []
        for (rid, idx) in outgoingRids {
            if idx == cartridgeIdx {
                let flowKey = FlowKey(rid: rid, xid: nil)
                let nextSeq = (outgoingMaxSeq.removeValue(forKey: flowKey) ?? 0) + 1
                failedOutgoing.append((rid: rid, nextSeq: nextSeq))
            }
        }
        for entry in failedOutgoing {
            outgoingRids.removeValue(forKey: entry.rid)
        }

        // incomingRxids: requests routed to this cartridge (intentionally leaked)
        var failedIncoming: [(key: RxidKey, xid: MessageId, rid: MessageId, nextSeq: UInt64)] = []
        for (key, idx) in incomingRxids {
            if idx == cartridgeIdx {
                let flowKey = FlowKey(rid: key.rid, xid: key.xid)
                let nextSeq = (outgoingMaxSeq.removeValue(forKey: flowKey) ?? 0) + 1
                failedIncoming.append((key: key, xid: key.xid, rid: key.rid, nextSeq: nextSeq))
            }
        }
        for entry in failedIncoming {
            incomingRxids.removeValue(forKey: entry.key)
            incomingToPeerRids.removeValue(forKey: entry.key)
        }

        // Determine error code and message based on shutdown reason.
        // Both unexpected deaths and OOM kills send ERR frames for pending work.
        // Only appExit suppresses ERR frames (relay is closing, no callers left).
        let cartridgePath = cartridge.path

        let errInfo: (code: String, message: String)?
        switch reason {
        case nil:
            // Unexpected death — genuine crash mid-flight
            let exitSuffix = exitInfo.isEmpty ? "" : " (\(exitInfo))"
            let msg = stderrContent.isEmpty
                ? "Cartridge \(cartridgePath) exited unexpectedly\(exitSuffix)."
                : "Cartridge \(cartridgePath) exited unexpectedly\(exitSuffix). stderr:\n\(stderrContent)"
            errInfo = (code: "CARTRIDGE_DIED", message: msg)
            cartridge.lastDeathMessage = msg
        case .oomKill:
            // OOM watchdog killed the cartridge — callers must be notified
            let exitSuffix = exitInfo.isEmpty ? "" : " (\(exitInfo))"
            let msg = stderrContent.isEmpty
                ? "Cartridge \(cartridgePath) killed by OOM watchdog\(exitSuffix)."
                : "Cartridge \(cartridgePath) killed by OOM watchdog\(exitSuffix). stderr:\n\(stderrContent)"
            errInfo = (code: "OOM_KILLED", message: msg)
            cartridge.lastDeathMessage = msg
        case .cancelled:
            // Cancel-triggered kill — ERR "CANCELLED" for all pending work
            let msg = "Cartridge \(cartridgePath) killed by cancel request."
            errInfo = (code: "CANCELLED", message: msg)
            cartridge.lastDeathMessage = msg
        case .appExit:
            // Clean shutdown — no ERR frames, relay is closing
            errInfo = nil
            cartridge.lastDeathMessage = nil
        }

        // Rebuild capTable for on-demand respawn routing.
        capTable.removeAll { $0.1 == cartridgeIdx }
        if !cartridge.helloFailed {
            for cap in cartridge.knownCaps {
                capTable.append((cap, cartridgeIdx))
            }
        }
        rebuildCapabilities()
        stateLock.unlock()

        // Send ERR frames for all pending work (unexpected death and OOM kill).
        if let info = errInfo {
            for entry in failedOutgoing {
                var err = Frame.err(id: entry.rid, code: info.code, message: info.message)
                err.seq = entry.nextSeq
                sendToRelay(err)
            }
            for entry in failedIncoming {
                var err = Frame.err(id: entry.rid, code: info.code, message: info.message)
                err.routingId = entry.xid
                err.seq = entry.nextSeq
                sendToRelay(err)
            }
        }
    }

    // MARK: - Cartridge Reader Thread

    /// Start a background reader thread for a cartridge.
    private func startCartridgeReaderThread(cartridgeIdx: Int, reader: FrameReader) {
        let thread = Thread { [weak self] in
            while true {
                do {
                    guard let frame = try reader.read() else {
                        // EOF — cartridge closed stdout
                        self?.pushEvent(.death(cartridgeIdx: cartridgeIdx))
                        break
                    }
                    self?.pushEvent(.frame(cartridgeIdx: cartridgeIdx, frame: frame))
                } catch {
                    // Read error — treat as death
                    self?.pushEvent(.death(cartridgeIdx: cartridgeIdx))
                    break
                }
            }
        }
        thread.name = "CartridgeHost.cartridge[\(cartridgeIdx)]"

        stateLock.lock()
        cartridges[cartridgeIdx].readerThread = thread
        stateLock.unlock()

        thread.start()
    }

    // MARK: - Event Queue

    /// Push an event from a cartridge reader thread.
    private func pushEvent(_ event: CartridgeEvent) {
        eventLock.lock()
        eventQueue.append(event)
        eventLock.unlock()
        eventSemaphore.signal()
    }

    /// Drain and process all pending events (used internally).
    private func processEvents() {
        eventLock.lock()
        let events = eventQueue
        eventQueue.removeAll()
        eventLock.unlock()

        for event in events {
            switch event {
            case .frame(let cartridgeIdx, let frame):
                handleCartridgeFrame(cartridgeIdx: cartridgeIdx, frame: frame)
            case .death(let cartridgeIdx):
                handleCartridgeDeath(cartridgeIdx: cartridgeIdx)
            case .relayFrame(let frame):
                handleRelayFrame(frame)
            case .relayClosed:
                break // Handled in run() loop
            }
        }
    }

    // MARK: - Outbound Writing

    /// Write a frame to the relay (toward engine). Thread-safe.
    /// Frames arrive with seq already assigned by CartridgeRuntime — no modification needed.
    private func sendToRelay(_ frame: Frame) {
        if frame.frameType != .log {
            os_log(.debug, log: Self.log, "[sendToRelay] %{public}@ id=%{public}@ xid=%{public}@", String(describing: frame.frameType), String(describing: frame.id), String(describing: frame.routingId))
        }
        outboundLock.lock()
        defer { outboundLock.unlock() }
        guard let w = outboundWriter else {
            os_log(.error, log: Self.log, "[sendToRelay] outboundWriter is nil — frame dropped: %{public}@ id=%{public}@", String(describing: frame.frameType), String(describing: frame.id))
            return
        }
        try? w.write(frame)
    }

    // MARK: - Internal Helpers

    /// Rebuild aggregate capabilities from all known/discovered cartridges.
    /// Must hold stateLock when calling.
    /// Creates a JSON array of URN strings (not objects).
    ///
    /// Includes caps from ALL registered cartridges that haven't permanently failed HELLO.
    /// Running cartridges use their actual manifest caps; non-running cartridges use knownCaps.
    /// This ensures the relay always advertises all caps that CAN be handled, regardless
    /// of whether the cartridge process is currently alive (on-demand spawn handles restarts).
    ///
    /// If running in relay mode (outboundWriter is set), sends a RelayNotify frame
    /// to the relay interface with the updated capabilities.
    private func rebuildCapabilities() {
        // CAP_IDENTITY is always present — structural, not cartridge-dependent
        var capUrns: [String] = [CSCapIdentity]

        for cartridge in cartridges where !cartridge.helloFailed {
            if cartridge.running {
                // Running: use actual caps from manifest (verified via HELLO handshake)
                if !cartridge.manifest.isEmpty,
                   let json = try? JSONSerialization.jsonObject(with: cartridge.manifest) as? [String: Any] {
                    // Extract caps from cap_groups
                    if let capGroups = json["cap_groups"] as? [[String: Any]] {
                        for group in capGroups {
                            if let groupCaps = group["caps"] as? [[String: Any]] {
                                for cap in groupCaps {
                                    if let urn = cap["urn"] as? String, urn != CSCapIdentity {
                                        capUrns.append(urn)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                // Not running: use knownCaps (from discovery, available for on-demand spawn)
                for cap in cartridge.knownCaps where cap != CSCapIdentity {
                    capUrns.append(cap)
                }
            }
        }

        let installedCartridges = cartridges.compactMap { $0.installedCartridgeIdentity() }

        let capsData: Data
        if let data = try? JSONSerialization.data(withJSONObject: [
            "caps": capUrns,
            "installed_cartridges": installedCartridges.map { [
                "id": $0.id,
                "version": $0.version,
                "sha256": $0.sha256,
            ] },
        ]) {
            capsData = data
            _capabilities = data
        } else {
            fatalError("BUG: failed to serialize RelayNotify capabilities payload")
        }

        // Send RelayNotify to relay if in relay mode
        outboundLock.lock()
        if let writer = outboundWriter {
            let notify = Frame.relayNotify(manifest: capsData, limits: Limits())
            try? writer.write(notify) // Ignore error if relay closed
        }
        outboundLock.unlock()
    }

    /// Extract cap URN strings from a manifest JSON blob.
    /// Validates that CAP_IDENTITY is present (mandatory for all cartridges).
    private static func extractCaps(from manifest: Data) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let capGroups = json["cap_groups"] as? [[String: Any]] else {
            throw CartridgeHostError.handshakeFailed("Invalid manifest JSON or missing cap_groups array")
        }

        // Collect URNs from all cap groups
        var capUrns: [String] = []
        for group in capGroups {
            if let groupCaps = group["caps"] as? [[String: Any]] {
                capUrns.append(contentsOf: groupCaps.compactMap { $0["urn"] as? String })
            }
        }

        // Verify CAP_IDENTITY is declared — mandatory for every cartridge
        guard let identityUrn = try? CSCapUrn.fromString(CSCapIdentity) else {
            fatalError("BUG: CAP_IDENTITY constant '\(CSCapIdentity)' is invalid")
        }

        let hasIdentity = capUrns.contains { capUrnStr in
            guard let capUrn = try? CSCapUrn.fromString(capUrnStr) else { return false }
            return identityUrn.conforms(to: capUrn)
        }

        guard hasIdentity else {
            throw CartridgeHostError.handshakeFailed(
                "Cartridge manifest missing required CAP_IDENTITY (\(CSCapIdentity))"
            )
        }

        return capUrns
    }

    /// Generate identity verification nonce — CBOR-encoded "bifaci" text.
    private static func identityNonce() -> Data {
        return Data(CBOR.utf8String("bifaci").encode())
    }

    /// Verify cartridge identity by sending nonce and expecting echo response.
    ///
    /// This proves the transport works end-to-end and the cartridge correctly
    /// implements the identity capability (echo behavior).
    ///
    /// - Parameters:
    ///   - reader: FrameReader for cartridge stdout
    ///   - writer: FrameWriter for cartridge stdin
    /// - Throws: CartridgeHostError if verification fails
    private static func verifyCartridgeIdentity(reader: FrameReader, writer: FrameWriter) throws {
        let nonce = identityNonce()
        let reqId = MessageId.newUUID()
        let streamId = "identity-verify"

        // Send REQ with CAP_IDENTITY
        let req = Frame.req(id: reqId, capUrn: CSCapIdentity as String, payload: Data(), contentType: "application/cbor")
        try writer.write(req)

        // Send STREAM_START
        let ss = Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: "media:")
        try writer.write(ss)

        // Send CHUNK with nonce
        let checksum = Frame.computeChecksum(nonce)
        let chunk = Frame.chunk(reqId: reqId, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum)
        try writer.write(chunk)

        // Send STREAM_END
        let se = Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: 1)
        try writer.write(se)

        // Send END
        let end = Frame.end(id: reqId)
        try writer.write(end)

        // Read response - expect STREAM_START → CHUNK(s) → STREAM_END → END
        var accumulated = Data()
        while true {
            guard let frame = try reader.read() else {
                throw CartridgeHostError.handshakeFailed("Cartridge closed connection during identity verification")
            }

            switch frame.frameType {
            case .streamStart:
                break // Expected, no action needed
            case .chunk:
                if let payload = frame.payload {
                    accumulated.append(payload)
                }
            case .streamEnd:
                break // Expected, no action needed
            case .end:
                // Verify nonce matches
                if accumulated != nonce {
                    throw CartridgeHostError.handshakeFailed(
                        "Identity verification payload mismatch (expected \(nonce.count) bytes, got \(accumulated.count))")
                }
                return // Success
            case .err:
                let code = frame.errorCode ?? "UNKNOWN"
                let msg = frame.errorMessage ?? "no message"
                throw CartridgeHostError.handshakeFailed("Identity verification failed: [\(code)] \(msg)")
            default:
                throw CartridgeHostError.handshakeFailed("Identity verification: unexpected frame type \(frame.frameType)")
            }
        }
    }

    // MARK: - Spawn On Demand

    /// Spawn a registered cartridge binary on demand.
    ///
    /// Performs posix_spawn + HELLO handshake + starts reader thread.
    /// Does NOT hold stateLock during blocking operations (handshake).
    ///
    /// - Parameter idx: Cartridge index in the cartridges array
    /// - Throws: CartridgeHostError if spawn or handshake fails
    private func spawnCartridge(at idx: Int) throws {
        // Read cartridge info without holding lock during blocking ops
        stateLock.lock()
        let path = cartridges[idx].path
        let alreadyRunning = cartridges[idx].running
        let alreadyFailed = cartridges[idx].helloFailed
        stateLock.unlock()

        guard !path.isEmpty else {
            throw CartridgeHostError.handshakeFailed("No binary path for cartridge \(idx)")
        }
        guard !alreadyRunning else { return }
        guard !alreadyFailed else {
            throw CartridgeHostError.handshakeFailed("Cartridge previously failed HELLO — permanently removed")
        }

        // Setup pipes
        let inputPipe = Pipe()   // host writes → cartridge reads (stdin)
        let outputPipe = Pipe()  // cartridge writes → host reads (stdout)
        let errorPipe = Pipe()   // cartridge writes → host reads (stderr)

        var pid: pid_t = 0

        // Build argv (null-terminated for posix_spawn)
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        defer { argv.compactMap { $0 }.forEach { free($0) } }

        // File actions for pipe redirection
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        posix_spawn_file_actions_adddup2(&fileActions, inputPipe.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, outputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errorPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        // Close all pipe descriptors in child
        posix_spawn_file_actions_addclose(&fileActions, inputPipe.fileHandleForReading.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, inputPipe.fileHandleForWriting.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, outputPipe.fileHandleForReading.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, outputPipe.fileHandleForWriting.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, errorPipe.fileHandleForReading.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, errorPipe.fileHandleForWriting.fileDescriptor)

        // Spawn
        let spawnResult = posix_spawn(&pid, path, &fileActions, nil, argv, nil)
        guard spawnResult == 0 else {
            let desc = String(cString: strerror(spawnResult))
            throw CartridgeHostError.handshakeFailed("posix_spawn failed for \(path): \(desc)")
        }

        // Close child's ends in parent
        inputPipe.fileHandleForReading.closeFile()
        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()

        let stdinHandle = inputPipe.fileHandleForWriting
        let stdoutHandle = outputPipe.fileHandleForReading
        let stderrHandle = errorPipe.fileHandleForReading

        // HELLO handshake (blocking — stateLock NOT held)
        let reader = FrameReader(handle: stdoutHandle)
        let writer = FrameWriter(handle: stdinHandle)

        let handshakeResult: HandshakeResult
        do {
            handshakeResult = try performHandshakeWithManifest(reader: reader, writer: writer)
        } catch {
            // HELLO failure → permanent removal (binary is broken)
            kill(pid, SIGKILL)
            _ = waitpid(pid, nil, 0)
            stdinHandle.closeFile()
            stdoutHandle.closeFile()
            stderrHandle.closeFile()

            stateLock.lock()
            cartridges[idx].helloFailed = true
            capTable.removeAll { $0.1 == idx }
            rebuildCapabilities()
            stateLock.unlock()

            throw CartridgeHostError.handshakeFailed("HELLO failed for \(path): \(error.localizedDescription)")
        }

        let caps = try Self.extractCaps(from: handshakeResult.manifest ?? Data())

        // Update cartridge state under lock
        stateLock.lock()
        let cartridge = cartridges[idx]
        cartridge.pid = pid
        cartridge.stdinHandle = stdinHandle
        cartridge.stdoutHandle = stdoutHandle
        cartridge.stderrHandle = stderrHandle
        cartridge.writer = writer
        cartridge.manifest = handshakeResult.manifest ?? Data()
        cartridge.limits = handshakeResult.limits
        cartridge.caps = caps
        cartridge.running = true

        // Update capTable with actual caps from manifest
        capTable.removeAll { $0.1 == idx }
        for cap in caps {
            capTable.append((cap, idx))
        }
        rebuildCapabilities()
        stateLock.unlock()

        // Start reader thread
        startCartridgeReaderThread(cartridgeIdx: idx, reader: reader)
    }

    // MARK: - Lifecycle

    /// Close the host, killing all managed cartridge processes.
    ///
    /// After close(), the run() loop will exit. Any pending requests get ERR frames.
    public func close() {
        stateLock.lock()
        guard !closed else {
            stateLock.unlock()
            return
        }
        closed = true

        // Kill all running cartridges
        for cartridge in cartridges {
            cartridge.writerLock.lock()
            cartridge.writer = nil
            cartridge.writerLock.unlock()

            if let stdin = cartridge.stdinHandle {
                try? stdin.close()
                cartridge.stdinHandle = nil
            }
            if let stderr = cartridge.stderrHandle {
                try? stderr.close()
                cartridge.stderrHandle = nil
            }
            cartridge.shutdownReason = .appExit
            cartridge.killProcess()
            cartridge.running = false
        }
        stateLock.unlock()

        // Signal the event loop to wake up and exit
        pushEvent(.relayClosed)
    }

    // MARK: - Cartridge Process Monitoring

    /// Get a snapshot of all running cartridge processes.
    /// Thread-safe — can be called from any thread while `run()` is active.
    public func runningCartridges() -> [CartridgeProcessInfo] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cartridges.enumerated().compactMap { (idx, cartridge) in
            guard let pid = cartridge.pid, cartridge.running else { return nil }
            let name = (cartridge.path as NSString).lastPathComponent
            return CartridgeProcessInfo(
                cartridgeIndex: idx,
                pid: pid,
                name: name,
                running: cartridge.running,
                caps: cartridge.caps,
                memoryFootprintMb: cartridge.memoryFootprintMb,
                memoryRssMb: cartridge.memoryRssMb
            )
        }
    }

    /// Kill a specific cartridge process by PID for memory pressure.
    /// Sets `shutdownReason = .oomKill` so the death handler sends ERR frames
    /// with "OOM_KILLED" for all pending requests, allowing callers to fail
    /// fast instead of hanging forever.
    /// Thread-safe — can be called from any thread while `run()` is active.
    /// Returns `true` if the cartridge was found and killed.
    @discardableResult
    public func killCartridge(pid: pid_t) -> Bool {
        stateLock.lock()
        guard let cartridge = cartridges.first(where: { $0.pid == pid && $0.running }) else {
            stateLock.unlock()
            return false
        }
        cartridge.shutdownReason = .oomKill
        stateLock.unlock()
        cartridge.killProcess()
        return true
    }
}
