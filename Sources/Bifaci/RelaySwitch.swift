/// RelaySwitch — Cap-aware routing multiplexer for multiple RelayMasters.
///
/// The RelaySwitch sits above multiple RelayMasters and provides deterministic
/// request routing based on cap URN matching. It plays the same role for RelayMasters
/// that CartridgeHost plays for cartridges.
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────┐
/// │   Test Engine / API Client  │
/// └──────────────┬──────────────┘
///                │
/// ┌──────────────▼──────────────┐
/// │       RelaySwitch           │
/// │  • Aggregates capabilities  │
/// │  • Routes REQ by cap URN    │
/// │  • Routes frames by (XID,RID) │
/// │  • Tracks peer requests     │
/// └─┬───┬───┬───┬──────────────┘
///   │   │   │   │
///   ▼   ▼   ▼   ▼
///  RM  RM  RM  RM   (Relay Masters - via socket pairs)
/// ```
///
/// ## Routing Semantics
///
/// XID (routing ID) distinguishes direction:
/// - HAS XID → response flowing back toward origin
/// - NO XID  → request flowing forward toward destination
///
/// Origin tracking:
/// - nil = external caller (via sendToMaster)
/// - Some(masterIdx) = peer request from another master

import Foundation
import CommonCrypto
@preconcurrency import SwiftCBOR
import CapDAG

// MARK: - Helper Extensions

extension MessageId {
    /// Convert message ID to string for use as dictionary key
    func toString() -> String {
        switch self {
        case .uuid(let data):
            return data.base64EncodedString()
        case .uint(let value):
            return String(value)
        }
    }
}

// MARK: - Error Types

/// Errors specific to RelaySwitch operations
public enum RelaySwitchError: Error, LocalizedError, Sendable {
    case noHandler(String)
    case unknownRequest(String)
    case protocolError(String)
    case allMastersUnhealthy

    public var errorDescription: String? {
        switch self {
        case .noHandler(let cap): return "No handler for cap: \(cap)"
        case .unknownRequest(let reqId): return "Unknown request ID: \(reqId)"
        case .protocolError(let msg): return "Protocol violation: \(msg)"
        case .allMastersUnhealthy: return "All relay masters are unhealthy"
        }
    }
}

// MARK: - Data Structures

/// Socket pair for master connection
public struct SocketPair: Sendable {
    public let read: FileHandle
    public let write: FileHandle

    public init(read: FileHandle, write: FileHandle) {
        self.read = read
        self.write = write
    }
}

/// Composite routing key: (XID, RID) — uniquely identifies a request flow
private struct RoutingKey: Hashable {
    let xid: MessageId
    let rid: MessageId
}

/// Routing entry for request tracking
private struct RoutingEntry {
    /// Source master index, or nil if from external caller
    let sourceMasterIdx: Int?
    /// Destination master index (where request is being handled)
    let destinationMasterIdx: Int
}

public struct RelayNotifyCapabilitiesPayload: Codable {
    public let caps: [String]
    public let installedCartridges: [InstalledCartridgeIdentity]

    enum CodingKeys: String, CodingKey {
        case caps
        case installedCartridges = "installed_cartridges"
    }

    public init(caps: [String], installedCartridges: [InstalledCartridgeIdentity]) {
        self.caps = caps
        self.installedCartridges = installedCartridges
    }
}

/// Sentinel value for engine-initiated requests (used in origin tracking)
private let ENGINE_SOURCE = Int.max

// MARK: - Identity Nonce

/// Generate identity verification nonce — CBOR-encoded "bifaci" text.
/// Must match Rust's identity_nonce() exactly.
private func identityNonce() -> Data {
    return Data(CBOR.utf8String("bifaci").encode())
}

// MARK: - Master Connection

/// Connection to a single RelayMaster
@available(macOS 10.15.4, iOS 13.4, *)
private final class MasterConnection: @unchecked Sendable {
    let socketWriter: FrameWriter
    /// SeqAssigner for outbound frames to this master (output stage)
    let seqAssigner: SeqAssigner
    /// ReorderBuffer for inbound frames from this master
    let reorderBuffer: ReorderBuffer
    var manifest: Data
    var limits: Limits
    var caps: [String]
    var installedCartridges: [InstalledCartridgeIdentity]
    var healthy: Bool

    init(socketWriter: FrameWriter, seqAssigner: SeqAssigner, manifest: Data, limits: Limits, caps: [String], installedCartridges: [InstalledCartridgeIdentity], healthy: Bool) {
        self.socketWriter = socketWriter
        self.seqAssigner = seqAssigner
        self.manifest = manifest
        self.limits = limits
        self.caps = caps
        self.installedCartridges = installedCartridges
        self.healthy = healthy
        self.reorderBuffer = ReorderBuffer(maxBufferPerFlow: limits.maxReorderBuffer)
    }
}

// MARK: - Relay Switch

/// Cap-aware routing multiplexer for multiple RelayMasters.
///
/// Routes requests based on cap URN matching and tracks bidirectional request/response flows.
/// Uses XID (routing ID) presence to distinguish response direction from request direction.
@available(macOS 10.15.4, iOS 13.4, *)
public final class RelaySwitch: @unchecked Sendable {
    private var masters: [MasterConnection] = []
    private var capTable: [(capUrn: String, masterIdx: Int)] = []

    /// Routing: (xid, rid) → source/destination masters
    private var requestRouting: [RoutingKey: RoutingEntry] = [:]
    /// Peer-initiated request keys for cleanup tracking
    private var peerRequests: Set<RoutingKey> = Set()
    /// Origin tracking: (xid, rid) → upstream master index (nil = external caller)
    private var originMap: [RoutingKey: Int?] = [:]
    /// RID → XID mapping for engine-initiated requests (continuation frames need XID lookup)
    private var ridToXid: [MessageId: MessageId] = [:]
    /// XID counter for assigning unique routing IDs
    private var xidCounter: UInt64 = 0

    private var aggregateCapabilities: Data = Data()
    private var aggregateInstalledCartridges: [InstalledCartridgeIdentity] = []
    private var negotiatedLimits: Limits = Limits()
    private let lock = NSLock()
    private var frameChannel: [(masterIdx: Int, frame: Frame?, error: Error?)] = []
    private let frameSemaphore = DispatchSemaphore(value: 0)

    /// Shutdown flag - when true, reader threads should exit
    private var isShutdown = false

    /// Create a RelaySwitch from socket pairs.
    ///
    /// Two-phase construction:
    /// 1. For each master: read RelayNotify, verify identity (blocking)
    /// 2. After all verified: spawn reader threads
    ///
    /// Identity verification sends CAP_IDENTITY request with nonce, expects echo response.
    /// Updated RelayNotify frames during verification are captured (hosts send full caps after cartridge startup).
    ///
    /// - Parameter sockets: Array of socket pairs (one per master). Can be empty — use add_master later.
    /// - Throws: RelaySwitchError if construction or identity verification fails
    public init(sockets: [SocketPair]) throws {
        // Allow empty sockets — creates empty switch. Use addMaster() to add masters later.
        // Matches Rust TEST432: Empty masters list creates empty switch, add_master works.
        if sockets.isEmpty {
            aggregateCapabilities = Data("[]".utf8)
            return
        }

        // Phase 1: For each master, read RelayNotify and verify identity (blocking).
        // Reader threads are spawned only after verification succeeds.
        var pendingReaders: [(masterIdx: Int, reader: FrameReader)] = []

        for (masterIdx, sockPair) in sockets.enumerated() {
            var socketReader = FrameReader(handle: sockPair.read)
            let socketWriter = FrameWriter(handle: sockPair.write)

            // Read initial RelayNotify (blocking — first frame from each master)
            guard let notifyFrame = try socketReader.read() else {
                throw RelaySwitchError.protocolError("master \(masterIdx): connection closed before RelayNotify")
            }

            guard notifyFrame.frameType == .relayNotify else {
                throw RelaySwitchError.protocolError("master \(masterIdx): expected RelayNotify, got \(notifyFrame.frameType)")
            }

            guard var capsPayload = notifyFrame.relayNotifyManifest,
                  var masterLimits = notifyFrame.relayNotifyLimits else {
                throw RelaySwitchError.protocolError("master \(masterIdx): RelayNotify missing manifest or limits")
            }

            var notifyPayload = try Self.parseRelayNotifyPayload(capsPayload)
            var caps = notifyPayload.caps

            // Per-master SeqAssigner that persists into the MasterConnection
            // regardless of whether we run the identity probe.
            let seqAssigner = SeqAssigner()

            // End-to-end identity verification. The probe traverses the
            // relay chain to a cartridge — it is only meaningful when the
            // host has at least one advertised cap. An empty cap list
            // means "no cartridges attached successfully"; the master
            // still joins so its `installed_cartridges` attachment errors
            // reach the engine.
            if !caps.isEmpty {
                xidCounter += 1
                let xid = MessageId.uint(xidCounter)

                let nonce = identityNonce()
                let reqId = MessageId.newUUID()
                let streamId = "identity-verify"

                var req = Frame.req(id: reqId, capUrn: CSCapIdentity as String, payload: Data(), contentType: "application/cbor")
                req.routingId = xid
                seqAssigner.assign(&req)
                try socketWriter.write(req)

                var ss = Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: "media:")
                ss.routingId = xid
                seqAssigner.assign(&ss)
                try socketWriter.write(ss)

                let checksum = Frame.computeChecksum(nonce)
                var chunk = Frame.chunk(reqId: reqId, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum)
                chunk.routingId = xid
                seqAssigner.assign(&chunk)
                try socketWriter.write(chunk)

                var se = Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: 1)
                se.routingId = xid
                seqAssigner.assign(&se)
                try socketWriter.write(se)

                var end = Frame.end(id: reqId)
                end.routingId = xid
                seqAssigner.assign(&end)
                try socketWriter.write(end)

                seqAssigner.remove(FlowKey(rid: reqId, xid: xid))

                // Read response — expect STREAM_START → CHUNK(s) → STREAM_END → END
                // Also handle updated RelayNotify frames (host sends full caps after cartridge startup)
                var accumulated = Data()
                while true {
                    guard let frame = try socketReader.read() else {
                        throw RelaySwitchError.protocolError("master \(masterIdx): connection closed during identity verification")
                    }

                    switch frame.frameType {
                    case .relayNotify:
                        // CartridgeHostRuntime sends the full RelayNotify (with all caps)
                        // through RelaySlave during identity verification. Update caps.
                        if let manifest = frame.relayNotifyManifest {
                            capsPayload = manifest
                            notifyPayload = try Self.parseRelayNotifyPayload(capsPayload)
                            caps = notifyPayload.caps
                        }
                        if let newLimits = frame.relayNotifyLimits {
                            masterLimits = newLimits
                        }
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
                            throw RelaySwitchError.protocolError(
                                "master \(masterIdx): identity verification payload mismatch (expected \(nonce.count) bytes, got \(accumulated.count))")
                        }
                        break // Done — fall through to next master
                    case .err:
                        let code = frame.errorCode ?? "UNKNOWN"
                        let msg = frame.errorMessage ?? "no message"
                        throw RelaySwitchError.protocolError("master \(masterIdx): identity verification failed: [\(code)] \(msg)")
                    default:
                        throw RelaySwitchError.protocolError("master \(masterIdx): identity verification: unexpected frame type \(frame.frameType)")
                    }

                    // Break out of loop after END
                    if frame.frameType == .end { break }
                }
            }

            // Stash reader for spawning after all masters verified
            pendingReaders.append((masterIdx: masterIdx, reader: socketReader))

            let masterConn = MasterConnection(
                socketWriter: socketWriter,
                seqAssigner: seqAssigner,
                manifest: capsPayload,
                limits: masterLimits,
                caps: caps,
                installedCartridges: notifyPayload.installedCartridges,
                healthy: true
            )
            masters.append(masterConn)
        }

        // Phase 2: All masters verified — spawn reader threads
        for (masterIdx, reader) in pendingReaders {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.readerLoop(masterIdx: masterIdx, reader: reader)
            }
        }

        // Build routing tables from already-populated caps
        rebuildCapTable()
        rebuildCapabilities()
        rebuildLimits()
    }

    // MARK: - Shutdown

    /// Shutdown the relay switch, stopping all reader threads.
    /// Call this before closing file handles to prevent crashes.
    public func shutdown() {
        lock.lock()
        isShutdown = true
        lock.unlock()

        // Signal semaphore to wake any waiting readers
        frameSemaphore.signal()
    }

    /// deinit sets shutdown flag
    deinit {
        lock.lock()
        isShutdown = true
        lock.unlock()
    }

    // MARK: - Reader Loop

    private func readerLoop(masterIdx: Int, reader: FrameReader) {
        var mutableReader = reader
        while true {
            // Check shutdown flag before reading
            lock.lock()
            let shouldStop = isShutdown
            lock.unlock()
            if shouldStop { return }

            do {
                guard let frame = try mutableReader.read() else {
                    enqueueFrame(masterIdx: masterIdx, frame: nil, error: nil)
                    return
                }

                // Check shutdown after read
                lock.lock()
                let shouldStopAfterRead = isShutdown
                lock.unlock()
                if shouldStopAfterRead { return }

                // Intercept RelayNotify before sending to queue
                if frame.frameType == .relayNotify {
                    lock.lock()
                    if !isShutdown,
                       let manifest = frame.relayNotifyManifest,
                       let limits = frame.relayNotifyLimits {
                        let payload = try Self.parseRelayNotifyPayload(manifest)
                        masters[masterIdx].manifest = manifest
                        masters[masterIdx].limits = limits
                        masters[masterIdx].caps = payload.caps
                        masters[masterIdx].installedCartridges = payload.installedCartridges
                        rebuildCapTable()
                        rebuildCapabilities()
                        rebuildLimits()
                    }
                    lock.unlock()
                    continue
                }

                // Pass through reorder buffer
                lock.lock()
                let shutdownDuringReorder = isShutdown
                let reorderBuffer = shutdownDuringReorder ? nil : masters[masterIdx].reorderBuffer
                lock.unlock()

                guard let buffer = reorderBuffer else { return }

                let readyFrames = try buffer.accept(frame)

                for readyFrame in readyFrames {
                    if readyFrame.frameType == .end || readyFrame.frameType == .err {
                        let key = FlowKey.fromFrame(readyFrame)
                        buffer.cleanupFlow(key)
                    }
                    enqueueFrame(masterIdx: masterIdx, frame: readyFrame, error: nil)
                }
            } catch {
                // Don't enqueue errors if we're shutting down
                lock.lock()
                let shuttingDown = isShutdown
                lock.unlock()
                if shuttingDown { return }

                enqueueFrame(masterIdx: masterIdx, frame: nil, error: error)
                return
            }
        }
    }

    private func enqueueFrame(masterIdx: Int, frame: Frame?, error: Error?) {
        lock.lock()
        frameChannel.append((masterIdx: masterIdx, frame: frame, error: error))
        lock.unlock()
        frameSemaphore.signal()
    }

    // MARK: - Frame Output

    /// Write a frame to a master, assigning seq via the per-master SeqAssigner.
    /// Cleans up seq tracking on terminal frames (END/ERR).
    private func writeToMasterIdx(_ masterIdx: Int, _ frame: inout Frame) throws {
        let master = masters[masterIdx]
        master.seqAssigner.assign(&frame)
        try master.socketWriter.write(frame)
        if frame.frameType == .end || frame.frameType == .err {
            master.seqAssigner.remove(FlowKey.fromFrame(frame))
        }
    }

    // MARK: - Dynamic Master Management

    /// Add a new master to a running switch.
    /// Performs identity verification before adding the master.
    ///
    /// - Parameter socket: Socket pair for the new master
    /// - Returns: Index of the new master
    /// - Throws: RelaySwitchError if identity verification fails
    public func addMaster(_ socket: SocketPair) throws -> Int {
        var socketReader = FrameReader(handle: socket.read)
        let socketWriter = FrameWriter(handle: socket.write)

        lock.lock()
        let masterIdx = masters.count
        lock.unlock()

        // Read initial RelayNotify (blocking)
        guard let notifyFrame = try socketReader.read() else {
            throw RelaySwitchError.protocolError("new master \(masterIdx): connection closed before RelayNotify")
        }

        guard notifyFrame.frameType == .relayNotify else {
            throw RelaySwitchError.protocolError("new master \(masterIdx): expected RelayNotify, got \(notifyFrame.frameType)")
        }

        guard var capsPayload = notifyFrame.relayNotifyManifest,
              var masterLimits = notifyFrame.relayNotifyLimits else {
            throw RelaySwitchError.protocolError("new master \(masterIdx): RelayNotify missing manifest or limits")
        }

        var notifyPayload = try Self.parseRelayNotifyPayload(capsPayload)
        var caps = notifyPayload.caps

        let seqAssigner = SeqAssigner()

        // End-to-end identity verification. Only meaningful when the host
        // advertises at least one cap — otherwise there is no cartridge
        // chain to echo the nonce. The master still joins so its
        // `installed_cartridges` attachment errors reach the engine.
        if !caps.isEmpty {
            lock.lock()
            xidCounter += 1
            let xid = MessageId.uint(xidCounter)
            lock.unlock()

            let nonce = identityNonce()
            let reqId = MessageId.newUUID()
            let streamId = "identity-verify"

            var req = Frame.req(id: reqId, capUrn: CSCapIdentity as String, payload: Data(), contentType: "application/cbor")
            req.routingId = xid
            seqAssigner.assign(&req)
            try socketWriter.write(req)

            var ss = Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: "media:")
            ss.routingId = xid
            seqAssigner.assign(&ss)
            try socketWriter.write(ss)

            let checksum = Frame.computeChecksum(nonce)
            var chunk = Frame.chunk(reqId: reqId, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum)
            chunk.routingId = xid
            seqAssigner.assign(&chunk)
            try socketWriter.write(chunk)

            var se = Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: 1)
            se.routingId = xid
            seqAssigner.assign(&se)
            try socketWriter.write(se)

            var end = Frame.end(id: reqId)
            end.routingId = xid
            seqAssigner.assign(&end)
            try socketWriter.write(end)

            seqAssigner.remove(FlowKey(rid: reqId, xid: xid))

            // Read response
            var accumulated = Data()
            while true {
                guard let frame = try socketReader.read() else {
                    throw RelaySwitchError.protocolError("new master \(masterIdx): connection closed during identity verification")
                }

                switch frame.frameType {
                case .relayNotify:
                    if let manifest = frame.relayNotifyManifest {
                        capsPayload = manifest
                        notifyPayload = try Self.parseRelayNotifyPayload(capsPayload)
                        caps = notifyPayload.caps
                    }
                    if let newLimits = frame.relayNotifyLimits {
                        masterLimits = newLimits
                    }
                case .streamStart:
                    break
                case .chunk:
                    if let payload = frame.payload {
                        accumulated.append(payload)
                    }
                case .streamEnd:
                    break
                case .end:
                    if accumulated != nonce {
                        throw RelaySwitchError.protocolError(
                            "new master \(masterIdx): identity verification payload mismatch")
                    }
                    break
                case .err:
                    let code = frame.errorCode ?? "UNKNOWN"
                    let msg = frame.errorMessage ?? "no message"
                    throw RelaySwitchError.protocolError("new master \(masterIdx): identity verification failed: [\(code)] \(msg)")
                default:
                    throw RelaySwitchError.protocolError("new master \(masterIdx): identity verification: unexpected frame type \(frame.frameType)")
                }

                if frame.frameType == .end { break }
            }
        }

        // Add master
        lock.lock()
        let masterConn = MasterConnection(
            socketWriter: socketWriter,
            seqAssigner: seqAssigner,
            manifest: capsPayload,
            limits: masterLimits,
            caps: caps,
            installedCartridges: notifyPayload.installedCartridges,
            healthy: true
        )
        let newIdx = masters.count
        masters.append(masterConn)

        // Spawn reader thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readerLoop(masterIdx: newIdx, reader: socketReader)
        }

        // Rebuild tables
        rebuildCapTable()
        rebuildCapabilities()
        rebuildLimits()
        lock.unlock()

        return newIdx
    }

    // MARK: - Public API

    /// Get aggregate capabilities (union of all masters)
    public func capabilities() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return aggregateCapabilities
    }

    /// Get negotiated limits (minimum across all masters)
    public func limits() -> Limits {
        lock.lock()
        defer { lock.unlock() }
        return negotiatedLimits
    }

    /// Send a frame to the appropriate master (engine → cartridge direction).
    ///
    /// REQ frames: Assigned XID if absent, routed by cap URN.
    /// Continuation frames: Routed by (XID, RID) pair.
    ///
    /// - Parameters:
    ///   - frame: The frame to send
    ///   - preferredCap: Optional capability URN for exact routing.
    ///                   When provided, uses comparable matching and prefers masters
    ///                   whose registered cap is equivalent to this URN.
    ///                   When nil, uses standard accepts + closest-specificity routing.
    public func sendToMaster(_ frame: Frame, preferredCap: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }

        var mutableFrame = frame

        switch frame.frameType {
        case .req:
            guard let cap = frame.cap else {
                throw RelaySwitchError.noHandler("nil")
            }

            // Check for target_cartridge in meta — if present, route to that
            // cartridge's master directly instead of using cap-based dispatch
            let targetCartridgeId: String? = frame.meta.flatMap { meta in
                if case let .utf8String(s) = meta["target_cartridge"] {
                    return s
                }
                return nil
            }

            let destIdx: Int
            if let cartridgeId = targetCartridgeId {
                // Direct routing by cartridge ID
                var found: Int? = nil
                for (idx, master) in masters.enumerated() {
                    if master.installedCartridges.contains(where: { $0.id == cartridgeId }) {
                        found = idx
                        break
                    }
                }
                guard let foundIdx = found else {
                    throw RelaySwitchError.protocolError("Unknown cartridge '\(cartridgeId)': not reported by any master")
                }
                guard masters[foundIdx].healthy else {
                    throw RelaySwitchError.protocolError("Master for cartridge '\(cartridgeId)' is unhealthy")
                }
                destIdx = foundIdx
            } else {
                // Standard cap-based dispatch
                guard let foundIdx = findMasterForCap(cap, preferredCap: preferredCap) else {
                    throw RelaySwitchError.noHandler(cap)
                }
                destIdx = foundIdx
            }

            // Assign XID if absent (engine frames arrive without XID)
            let xid: MessageId
            if let existingXid = frame.routingId {
                xid = existingXid
            } else {
                xidCounter += 1
                xid = .uint(xidCounter)
                mutableFrame.routingId = xid
            }

            let rid = frame.id
            let key = RoutingKey(xid: xid, rid: rid)

            // Record origin (nil = external caller via sendToMaster)
            originMap[key] = nil as Int?

            // Register routing
            requestRouting[key] = RoutingEntry(
                sourceMasterIdx: nil,
                destinationMasterIdx: destIdx
            )

            // Record RID → XID mapping for continuation frames from engine
            ridToXid[rid] = xid

            // Forward to destination with XID
            try writeToMasterIdx(destIdx, &mutableFrame)

        case .streamStart, .chunk, .streamEnd, .end, .err:
            // Continuation frames from engine: look up XID from RID if missing
            let xid: MessageId
            if let existingXid = frame.routingId {
                xid = existingXid
            } else {
                guard let lookedUpXid = ridToXid[frame.id] else {
                    throw RelaySwitchError.unknownRequest(frame.id.toString())
                }
                xid = lookedUpXid
                mutableFrame.routingId = xid
            }

            let key = RoutingKey(xid: xid, rid: frame.id)

            guard let entry = requestRouting[key] else {
                throw RelaySwitchError.unknownRequest(frame.id.toString())
            }

            let destIdx = entry.destinationMasterIdx

            // Forward to destination
            try writeToMasterIdx(destIdx, &mutableFrame)

        case .cancel:
            // Cancel routes like a continuation frame — look up XID from RID
            let xid: MessageId
            if let existingXid = frame.routingId {
                xid = existingXid
            } else {
                guard let lookedUpXid = ridToXid[frame.id] else {
                    throw RelaySwitchError.unknownRequest(frame.id.toString())
                }
                xid = lookedUpXid
                mutableFrame.routingId = xid
            }

            let key = RoutingKey(xid: xid, rid: frame.id)
            guard let entry = requestRouting[key] else {
                throw RelaySwitchError.unknownRequest(frame.id.toString())
            }
            try writeToMasterIdx(entry.destinationMasterIdx, &mutableFrame)

        default:
            throw RelaySwitchError.protocolError("Unexpected frame type from engine: \(frame.frameType)")
        }
    }

    /// Read the next frame from any master (cartridge → engine direction).
    ///
    /// Blocks until a frame is available from any master. Returns nil when all masters have closed.
    /// Peer requests (cartridge → cartridge) are handled internally and not returned.
    public func readFromMasters() throws -> Frame? {
        while true {
            frameSemaphore.wait()

            lock.lock()
            guard !frameChannel.isEmpty else {
                lock.unlock()
                continue
            }
            let masterFrame = frameChannel.removeFirst()
            lock.unlock()

            if let error = masterFrame.error {
                fputs("[RelaySwitch] Error reading from master \(masterFrame.masterIdx): \(error)\n", stderr)
                try handleMasterDeath(masterFrame.masterIdx)
                continue
            }

            guard let frame = masterFrame.frame else {
                try handleMasterDeath(masterFrame.masterIdx)
                lock.lock()
                let allDead = masters.allSatisfy { !$0.healthy }
                lock.unlock()
                if allDead { return nil }
                continue
            }

            if let resultFrame = try handleMasterFrame(sourceIdx: masterFrame.masterIdx, frame: frame) {
                return resultFrame
            }
        }
    }

    /// Read the next frame from any master with timeout.
    ///
    /// Like readFromMasters() but returns nil after timeout instead of blocking forever.
    public func readFromMasters(timeout: TimeInterval) throws -> Frame? {
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return nil }

            let result = frameSemaphore.wait(timeout: DispatchTime.now() + remaining)
            if result == .timedOut { return nil }

            lock.lock()
            guard !frameChannel.isEmpty else {
                lock.unlock()
                continue
            }
            let masterFrame = frameChannel.removeFirst()
            lock.unlock()

            if let error = masterFrame.error {
                fputs("[RelaySwitch] Error reading from master \(masterFrame.masterIdx): \(error)\n", stderr)
                try handleMasterDeath(masterFrame.masterIdx)
                continue
            }

            guard let frame = masterFrame.frame else {
                try handleMasterDeath(masterFrame.masterIdx)
                lock.lock()
                let allDead = masters.allSatisfy { !$0.healthy }
                lock.unlock()
                if allDead { return nil }
                continue
            }

            if let resultFrame = try handleMasterFrame(sourceIdx: masterFrame.masterIdx, frame: frame) {
                return resultFrame
            }
        }
    }

    // MARK: - Internal Routing

    /// Find which master handles a given cap URN.
    /// Prefers the match whose specificity is CLOSEST to the request's specificity.
    /// This ensures generic requests (e.g., identity) route to generic handlers,
    /// and specific requests route to specific handlers.
    ///
    /// Uses `isDispatchable(provider, request)` to find all masters that can
    /// legally handle the request.
    ///
    /// Among dispatchable matches, ranking prefers:
    /// 1. Equivalent matches (distance 0)
    /// 2. More specific providers (positive distance) - refinements
    /// 3. More generic providers (negative distance) - fallbacks
    ///
    /// With preference (`preferredCap`): among dispatchable matches, the master
    /// whose registered cap is equivalent to the preferred cap wins. If no
    /// equivalent match, falls back to specificity-based ranking.
    ///
    /// - Parameters:
    ///   - capUrn: The capability URN to find a handler for
    ///   - preferredCap: Optional capability URN for exact routing.
    private func findMasterForCap(_ capUrn: String, preferredCap: String? = nil) -> Int? {
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else {
            return nil
        }

        let requestSpecificity = Int(requestUrn.specificity())

        // Parse preferred cap URN if provided
        let preferredUrn = preferredCap.flatMap { try? CSCapUrn.fromString($0) }

        // Collect ALL dispatchable masters with their specificity scores
        var matches: [(masterIdx: Int, signedDistance: Int, isPreferred: Bool)] = []

        for (registeredCap, masterIdx) in capTable {
            guard let registeredUrn = try? CSCapUrn.fromString(registeredCap) else {
                continue
            }

            if registeredUrn.isDispatchable(requestUrn) {
                let specificity = Int(registeredUrn.specificity())
                let signedDistance = specificity - requestSpecificity
                let isPreferred = preferredUrn.map { pref in
                    pref.isEquivalent(registeredUrn)
                } ?? false
                matches.append((masterIdx: masterIdx, signedDistance: signedDistance, isPreferred: isPreferred))
            }
        }

        if matches.isEmpty { return nil }

        // If any match is preferred, pick the first preferred match
        if let preferred = matches.first(where: { $0.isPreferred }) {
            return preferred.masterIdx
        }

        // Ranking: prefer equivalent (0), then more specific (+), then more generic (-)
        matches.sort { a, b in
            let (_, distA, _) = a
            let (_, distB, _) = b
            if distA >= 0 && distB < 0 { return true }
            if distA < 0 && distB >= 0 { return false }
            return abs(distA) < abs(distB)
        }

        return matches.first?.masterIdx
    }

    /// Handle a frame arriving from a master (cartridge → engine direction).
    ///
    /// Returns Some(frame) if the frame should be forwarded to the engine.
    /// Returns nil if the frame was handled internally (peer request or request continuation).
    private func handleMasterFrame(sourceIdx: Int, frame: Frame) throws -> Frame? {
        lock.lock()
        defer { lock.unlock() }

        var mutableFrame = frame

        switch frame.frameType {
        case .req:
            // Peer request: cartridge → cartridge via switch (no preference)
            guard let cap = frame.cap, let destIdx = findMasterForCap(cap, preferredCap: nil) else {
                throw RelaySwitchError.noHandler(frame.cap ?? "nil")
            }

            // REQs from cartridges should NOT have XID (per protocol spec)
            if frame.routingId != nil {
                throw RelaySwitchError.protocolError("REQ from cartridge should not have XID")
            }

            // Assign fresh XID
            xidCounter += 1
            let xid = MessageId.uint(xidCounter)
            mutableFrame.routingId = xid

            let rid = frame.id
            let key = RoutingKey(xid: xid, rid: rid)

            // Record RID → XID mapping for continuation frames
            ridToXid[rid] = xid

            // Record origin (where this request came from)
            fputs("[RelaySwitch] PEER_REQ: master \(sourceIdx) → master \(destIdx) cap='\(cap)' rid=\(rid) xid=\(xid)\n", stderr)
            originMap[key] = sourceIdx

            // Register routing
            requestRouting[key] = RoutingEntry(
                sourceMasterIdx: sourceIdx,
                destinationMasterIdx: destIdx
            )

            // Mark as peer request (for cleanup tracking)
            peerRequests.insert(key)

            // Forward to destination with XID
            try writeToMasterIdx(destIdx, &mutableFrame)

            // Do NOT return to engine (internal routing)
            return nil

        case .streamStart, .chunk, .streamEnd, .end, .err, .log:
            // Branch based on XID presence to distinguish request vs response direction
            if frame.routingId != nil {
                // ========================================
                // HAS XID = RESPONSE CONTINUATION
                // ========================================
                // Frame already has XID, so it's a response flowing back to origin
                let xid = frame.routingId!
                let rid = frame.id
                let key = RoutingKey(xid: xid, rid: rid)

                guard requestRouting[key] != nil else {
                    throw RelaySwitchError.unknownRequest(rid.toString())
                }

                // Get origin (where request came from)
                guard let originIdx = originMap[key] else {
                    throw RelaySwitchError.protocolError("No origin recorded for request \(rid.toString())")
                }

                let isTerminal = frame.frameType == .end || frame.frameType == .err

                // Route back to origin
                if let masterIdx = originIdx {
                    // Peer response — route back to source master (keep XID for relay protocol)
                    if isTerminal {
                        fputs("[RelaySwitch] PEER_RESP: routing \(frame.frameType) back to master \(masterIdx) xid=\(xid) rid=\(rid)\n", stderr)
                    }
                    try writeToMasterIdx(masterIdx, &mutableFrame)
                    if isTerminal {
                        fputs("[RelaySwitch] PEER_RESP: write to master \(masterIdx) completed\n", stderr)
                        requestRouting.removeValue(forKey: key)
                        originMap.removeValue(forKey: key)
                        peerRequests.remove(key)
                        ridToXid.removeValue(forKey: rid)
                    }

                    return nil
                } else {
                    // External caller (via sendToMaster) — strip XID and return to engine
                    mutableFrame.routingId = nil

                    if isTerminal {
                        requestRouting.removeValue(forKey: key)
                        originMap.removeValue(forKey: key)
                        peerRequests.remove(key)
                        ridToXid.removeValue(forKey: rid)
                    }

                    return mutableFrame
                }
            } else {
                // ========================================
                // NO XID = REQUEST CONTINUATION
                // ========================================
                // Frame has no XID, so it's a request continuation flowing to destination
                let rid = frame.id

                // Look up XID from RID → XID mapping (added by the REQ)
                guard let xid = ridToXid[rid] else {
                    throw RelaySwitchError.unknownRequest(rid.toString())
                }

                let key = RoutingKey(xid: xid, rid: rid)

                guard let entry = requestRouting[key] else {
                    throw RelaySwitchError.unknownRequest(rid.toString())
                }

                // Add XID to frame for forwarding
                mutableFrame.routingId = xid

                // Forward to destination master (keep XID)
                try writeToMasterIdx(entry.destinationMasterIdx, &mutableFrame)
                return nil
            }

        case .relayNotify:
            // Capability update from host — update our cap table
            if let manifest = frame.relayNotifyManifest,
               let newLimits = frame.relayNotifyLimits {
                let payload = try Self.parseRelayNotifyPayload(manifest)
                masters[sourceIdx].caps = payload.caps
                masters[sourceIdx].installedCartridges = payload.installedCartridges
                masters[sourceIdx].manifest = manifest
                masters[sourceIdx].limits = newLimits
                rebuildCapTable()
                rebuildCapabilities()
                rebuildLimits()
            }
            // Pass through to engine (for visibility)
            return frame

        case .cancel:
            // Cancel from cartridge — route to destination like a continuation frame.
            let rid = frame.id
            let xid: MessageId
            if let existingXid = frame.routingId {
                xid = existingXid
            } else {
                guard let lookedUpXid = ridToXid[rid] else {
                    // Unknown RID — silently ignore (request may already be completed)
                    return nil
                }
                xid = lookedUpXid
                mutableFrame.routingId = xid
            }

            let key = RoutingKey(xid: xid, rid: rid)
            guard let entry = requestRouting[key] else {
                // Unknown routing — silently ignore
                return nil
            }

            fputs("[RelaySwitch] Routing Cancel from master \(sourceIdx) to master \(entry.destinationMasterIdx) xid=\(xid) rid=\(rid)\n", stderr)
            try writeToMasterIdx(entry.destinationMasterIdx, &mutableFrame)
            return nil

        default:
            return frame
        }
    }

    private func handleMasterDeath(_ masterIdx: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        guard masters[masterIdx].healthy else {
            return
        }

        fputs("[RelaySwitch] Master \(masterIdx) died\n", stderr)
        masters[masterIdx].healthy = false

        // Find all pending requests to this master and ERR them
        var deadKeys: [(key: RoutingKey, sourceMasterIdx: Int?)] = []
        for (key, entry) in requestRouting {
            if entry.destinationMasterIdx == masterIdx {
                deadKeys.append((key: key, sourceMasterIdx: entry.sourceMasterIdx))
            }
        }

        for (key, sourceMasterIdx) in deadKeys {
            // Create ERR frame
            var errFrame = Frame.err(id: key.rid, code: "MASTER_DIED", message: "Relay master connection closed")
            errFrame.routingId = key.xid

            if let masterIdx = sourceMasterIdx, masters[masterIdx].healthy {
                // Send ERR back to source master
                try? writeToMasterIdx(masterIdx, &errFrame)
            }

            // Cleanup routing
            requestRouting.removeValue(forKey: key)
            originMap.removeValue(forKey: key)
            peerRequests.remove(key)
        }

        rebuildCapTable()
        rebuildCapabilities()
        rebuildLimits()
    }

    // MARK: - Capability Management

    private func rebuildCapTable() {
        capTable.removeAll()
        for (idx, master) in masters.enumerated() {
            if master.healthy {
                for cap in master.caps {
                    capTable.append((capUrn: cap, masterIdx: idx))
                }
            }
        }
    }

    private func rebuildCapabilities() {
        var allCaps = Set<String>()
        var allInstalledCartridges = Set<InstalledCartridgeIdentity>()
        for master in masters {
            if master.healthy {
                allCaps.formUnion(master.caps)
                allInstalledCartridges.formUnion(master.installedCartridges)
            }
        }

        let capsArray = Array(allCaps).sorted()
        aggregateInstalledCartridges = Array(allInstalledCartridges).sorted {
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.version != $1.version { return $0.version < $1.version }
            return $0.sha256 < $1.sha256
        }
        aggregateCapabilities = (try? JSONSerialization.data(withJSONObject: capsArray)) ?? Data()
    }

    private func rebuildLimits() {
        var minFrame = Int.max
        var minChunk = Int.max

        for master in masters {
            if master.healthy {
                if master.limits.maxFrame < minFrame {
                    minFrame = master.limits.maxFrame
                }
                if master.limits.maxChunk < minChunk {
                    minChunk = master.limits.maxChunk
                }
            }
        }

        if minFrame == Int.max { minFrame = DEFAULT_MAX_FRAME }
        if minChunk == Int.max { minChunk = DEFAULT_MAX_CHUNK }

        negotiatedLimits = Limits(maxFrame: minFrame, maxChunk: minChunk)
    }

    // MARK: - Helper Functions

    public func installedCartridges() -> [InstalledCartridgeIdentity] {
        lock.lock()
        defer { lock.unlock() }
        return aggregateInstalledCartridges
    }

    private static func parseRelayNotifyPayload(_ manifest: Data) throws -> RelayNotifyCapabilitiesPayload {
        let payload: RelayNotifyCapabilitiesPayload
        do {
            payload = try JSONDecoder().decode(RelayNotifyCapabilitiesPayload.self, from: manifest)
        } catch {
            throw RelaySwitchError.protocolError("RelayNotify payload must contain caps and installed_cartridges: \(error)")
        }

        // If the host advertises any caps, CAP_IDENTITY must be among them —
        // that is the contract that makes end-to-end identity verification
        // meaningful. An empty cap set is a valid state meaning "this host
        // has no cartridges that passed the attachment checklist"; the
        // `installed_cartridges` list may still report attachment failures
        // the UI needs to surface.
        if !payload.caps.isEmpty {
            let identityUrn = try? CSCapUrn.fromString(CSCapIdentity)
            let hasIdentity = payload.caps.contains { capStr in
                guard let capUrn = try? CSCapUrn.fromString(capStr),
                      let identity = identityUrn else { return false }
                return identity.conforms(to: capUrn)
            }

            guard hasIdentity else {
                throw RelaySwitchError.protocolError("RelayNotify advertised caps but is missing required CAP_IDENTITY (\(CSCapIdentity))")
            }
        }

        return payload
    }
}
/// Kinds of attachment failure for a cartridge. Matches the Rust
/// `CartridgeAttachmentErrorKind` and the `CartridgeAttachmentErrorKind` enum
/// in `cartridge.proto`.
public enum CartridgeAttachmentErrorKind: String, Codable, Hashable, Sendable {
    case incompatible
    case manifestInvalid = "manifest_invalid"
    case handshakeFailed = "handshake_failed"
    case identityRejected = "identity_rejected"
    case entryPointMissing = "entry_point_missing"
    case quarantined
}

/// Structured per-cartridge attachment failure. Mirrors the Rust
/// `CartridgeAttachmentError` struct wire-for-wire over RelayNotify JSON.
public struct CartridgeAttachmentError: Codable, Hashable, Sendable {
    public let kind: CartridgeAttachmentErrorKind
    public let message: String
    public let detectedAtUnixSeconds: Int64

    enum CodingKeys: String, CodingKey {
        case kind
        case message
        case detectedAtUnixSeconds = "detected_at_unix_seconds"
    }

    public init(kind: CartridgeAttachmentErrorKind, message: String, detectedAtUnixSeconds: Int64) {
        self.kind = kind
        self.message = message
        self.detectedAtUnixSeconds = detectedAtUnixSeconds
    }

    public static func now(kind: CartridgeAttachmentErrorKind, message: String) -> CartridgeAttachmentError {
        let seconds = Int64(Date().timeIntervalSince1970)
        return CartridgeAttachmentError(kind: kind, message: message, detectedAtUnixSeconds: seconds)
    }
}

/// Live runtime statistics for an attached cartridge. Mirrors
/// `capdag::CartridgeRuntimeStats` wire-for-wire over RelayNotify JSON.
public struct CartridgeRuntimeStats: Codable, Hashable, Sendable {
    public let running: Bool
    public let pid: UInt32?
    public let activeRequestCount: UInt64
    public let peerRequestCount: UInt64
    public let memoryFootprintMb: UInt64
    public let memoryRssMb: UInt64
    public let lastHeartbeatUnixSeconds: Int64?
    public let restartCount: UInt64

    enum CodingKeys: String, CodingKey {
        case running
        case pid
        case activeRequestCount = "active_request_count"
        case peerRequestCount = "peer_request_count"
        case memoryFootprintMb = "memory_footprint_mb"
        case memoryRssMb = "memory_rss_mb"
        case lastHeartbeatUnixSeconds = "last_heartbeat_unix_seconds"
        case restartCount = "restart_count"
    }

    public init(
        running: Bool,
        pid: UInt32? = nil,
        activeRequestCount: UInt64,
        peerRequestCount: UInt64,
        memoryFootprintMb: UInt64,
        memoryRssMb: UInt64,
        lastHeartbeatUnixSeconds: Int64? = nil,
        restartCount: UInt64
    ) {
        self.running = running
        self.pid = pid
        self.activeRequestCount = activeRequestCount
        self.peerRequestCount = peerRequestCount
        self.memoryFootprintMb = memoryFootprintMb
        self.memoryRssMb = memoryRssMb
        self.lastHeartbeatUnixSeconds = lastHeartbeatUnixSeconds
        self.restartCount = restartCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.running = try c.decode(Bool.self, forKey: .running)
        self.pid = try c.decodeIfPresent(UInt32.self, forKey: .pid)
        self.activeRequestCount = try c.decode(UInt64.self, forKey: .activeRequestCount)
        self.peerRequestCount = try c.decode(UInt64.self, forKey: .peerRequestCount)
        self.memoryFootprintMb = try c.decode(UInt64.self, forKey: .memoryFootprintMb)
        self.memoryRssMb = try c.decode(UInt64.self, forKey: .memoryRssMb)
        self.lastHeartbeatUnixSeconds = try c.decodeIfPresent(Int64.self, forKey: .lastHeartbeatUnixSeconds)
        self.restartCount = try c.decode(UInt64.self, forKey: .restartCount)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(running, forKey: .running)
        try c.encodeIfPresent(pid, forKey: .pid)
        try c.encode(activeRequestCount, forKey: .activeRequestCount)
        try c.encode(peerRequestCount, forKey: .peerRequestCount)
        try c.encode(memoryFootprintMb, forKey: .memoryFootprintMb)
        try c.encode(memoryRssMb, forKey: .memoryRssMb)
        try c.encodeIfPresent(lastHeartbeatUnixSeconds, forKey: .lastHeartbeatUnixSeconds)
        try c.encode(restartCount, forKey: .restartCount)
    }
}

public struct InstalledCartridgeIdentity: Codable, Hashable, Sendable {
    /// Verbatim URL of the registry the cartridge was published from.
    /// `nil` ⇔ dev install (built locally without a registry URL).
    /// Compared byte-wise; never normalized. `(registryURL, channel,
    /// id, version)` is the install's full identity — installs of
    /// the same id from different registries × channels are
    /// independent records. Required-but-nullable on the wire:
    /// missing field is a parse error so an old-schema payload
    /// never silently passes; null means dev.
    public let registryURL: String?
    public let id: String
    public let channel: String
    public let version: String
    public let sha256: String
    /// Present when the cartridge failed to attach; absent when healthy.
    public let attachmentError: CartridgeAttachmentError?
    /// Live runtime statistics from the host that owns this cartridge.
    /// `nil` for cartridges that aren't host-tracked (e.g. identities
    /// emitted by an in-process host with no routing tables).
    public let runtimeStats: CartridgeRuntimeStats?

    enum CodingKeys: String, CodingKey {
        case registryURL = "registry_url"
        case id
        case channel
        case version
        case sha256
        case attachmentError = "attachment_error"
        case runtimeStats = "runtime_stats"
    }

    public init(
        registryURL: String?,
        id: String,
        channel: String,
        version: String,
        sha256: String,
        attachmentError: CartridgeAttachmentError? = nil,
        runtimeStats: CartridgeRuntimeStats? = nil
    ) {
        self.registryURL = registryURL
        self.id = id
        self.channel = channel
        self.version = version
        self.sha256 = sha256
        self.attachmentError = attachmentError
        self.runtimeStats = runtimeStats
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `registry_url` is required-but-nullable on the wire. The
        // key MUST be present; the value MAY be null. `decodeNil`
        // plus `contains` distinguishes "key absent" (parse error)
        // from "key present with null value" (dev install).
        guard c.contains(.registryURL) else {
            throw DecodingError.keyNotFound(
                CodingKeys.registryURL,
                DecodingError.Context(
                    codingPath: c.codingPath,
                    debugDescription:
                        "InstalledCartridgeIdentity is missing required `registry_url` field. "
                        + "It must be present, with value null for dev installs or a URL "
                        + "string for registry installs."
                )
            )
        }
        self.registryURL = try c.decode(String?.self, forKey: .registryURL)
        self.id = try c.decode(String.self, forKey: .id)
        self.channel = try c.decode(String.self, forKey: .channel)
        self.version = try c.decode(String.self, forKey: .version)
        self.sha256 = try c.decode(String.self, forKey: .sha256)
        self.attachmentError = try c.decodeIfPresent(CartridgeAttachmentError.self, forKey: .attachmentError)
        self.runtimeStats = try c.decodeIfPresent(CartridgeRuntimeStats.self, forKey: .runtimeStats)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Always emit `registry_url` — even for dev installs it
        // serializes as explicit null. `encodeIfPresent` would elide
        // the key for nil, which the decoder explicitly rejects.
        try c.encode(registryURL, forKey: .registryURL)
        try c.encode(id, forKey: .id)
        try c.encode(channel, forKey: .channel)
        try c.encode(version, forKey: .version)
        try c.encode(sha256, forKey: .sha256)
        try c.encodeIfPresent(attachmentError, forKey: .attachmentError)
        try c.encodeIfPresent(runtimeStats, forKey: .runtimeStats)
    }
}
