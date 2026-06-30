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

/// Socket pair for master connection.
///
/// `id` is the stable identity of the cardinality slot this socket
/// fills. The relay's `addMaster` reattach-by-id contract uses it
/// on subsequent reconnects to find the slot to reattach to —
/// preserving slot indices across the death-and-reconnect cycle.
/// Re-adding the same id while the slot is still healthy is a
/// wiring bug and is rejected.
public struct SocketPair: Sendable {
    public let id: String
    public let read: FileHandle
    public let write: FileHandle

    public init(id: String, read: FileHandle, write: FileHandle) {
        self.id = id
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
    public let installedCartridges: [InstalledCartridgeRecord]

    enum CodingKeys: String, CodingKey {
        case installedCartridges = "installed_cartridges"
    }

    public init(installedCartridges: [InstalledCartridgeRecord]) {
        self.installedCartridges = installedCartridges
    }

    /// Flat cap-URN union across every cartridge in the payload,
    /// deduplicated while preserving first-seen order. Computed view —
    /// not stored on the wire.
    public func capUrns() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for cart in installedCartridges {
            for urn in cart.capUrns() {
                if seen.insert(urn).inserted {
                    out.append(urn)
                }
            }
        }
        return out
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

/// Connection to a single RelayMaster.
///
/// `id` is the stable identity of this slot. Reattach-by-id matches
/// against it on subsequent reconnects so the slot index stays
/// constant across the death-and-reconnect cycle. Once set at slot
/// creation `id` is never overwritten; the writer / seqAssigner /
/// reorderBuffer / caps are replaced wholesale on reattach.
@available(macOS 10.15.4, iOS 13.4, *)
private final class MasterConnection: @unchecked Sendable {
    let id: String
    var socketWriter: FrameWriter
    /// SeqAssigner for outbound frames to this master (output stage).
    /// Reset on reattach (new session restarts sequence numbering).
    var seqAssigner: SeqAssigner
    /// ReorderBuffer for inbound frames from this master.
    /// Reset on reattach.
    var reorderBuffer: ReorderBuffer
    var manifest: Data
    var limits: Limits
    var caps: [String]
    var installedCartridges: [InstalledCartridgeRecord]
    var healthy: Bool
    /// Last error message (if unhealthy). Mirrors Rust
    /// `MasterConnection.last_error`. Populated when an identity
    /// probe (synchronous in `addMaster`, or the deferred runtime
    /// probe) fails, or when the master dies; cleared when a
    /// deferred probe later passes and the master flips healthy.
    var lastError: String?

    init(id: String, socketWriter: FrameWriter, seqAssigner: SeqAssigner, manifest: Data, limits: Limits, caps: [String], installedCartridges: [InstalledCartridgeRecord], healthy: Bool, lastError: String? = nil) {
        self.id = id
        self.socketWriter = socketWriter
        self.seqAssigner = seqAssigner
        self.manifest = manifest
        self.limits = limits
        self.caps = caps
        self.installedCartridges = installedCartridges
        self.healthy = healthy
        self.lastError = lastError
        self.reorderBuffer = ReorderBuffer(maxBufferPerFlow: limits.maxReorderBuffer)
    }
}

// MARK: - Master Health Status

/// Snapshot of a single master's health, mirroring Rust
/// `MasterHealthStatus`. Surfaced via `RelaySwitch.getMasterHealth()`
/// so callers (and parity tests) can observe routability gating and
/// the `last_error` an identity-probe failure stamps without reaching
/// into the switch's private master list.
public struct MasterHealthStatus: Sendable {
    public let index: Int
    public let healthy: Bool
    public let capCount: Int
    public let lastError: String?

    public init(index: Int, healthy: Bool, capCount: Int, lastError: String?) {
        self.index = index
        self.healthy = healthy
        self.capCount = capCount
        self.lastError = lastError
    }
}

// MARK: - Watch (Rust tokio::sync::watch parity)

/// Single-producer / multi-consumer value cell with change notification.
///
/// Mirrors the subset of `tokio::sync::watch` that `RelaySwitch` relies
/// on: the latest value is stored centrally (so it persists across
/// windows with zero receivers — the `send_replace` semantics Rust
/// depends on at construction time, before the engine-facing relay has
/// subscribed), and a monotonically increasing version lets receivers
/// block until the next change.
///
/// `sendReplace` takes only this cell's own `NSCondition`, never the
/// `RelaySwitch` lock, so it is safe to call from inside a
/// `RelaySwitch`-locked region (e.g. `rebuildCapabilities`).
final class Watch<Value: Sendable>: @unchecked Sendable {
    private let cond = NSCondition()
    private var current: Value
    private var version: UInt64 = 0

    init(_ initial: Value) {
        self.current = initial
    }

    func currentValue() -> Value {
        cond.lock(); defer { cond.unlock() }
        return current
    }

    func currentVersion() -> UInt64 {
        cond.lock(); defer { cond.unlock() }
        return version
    }

    /// Store a new value and wake all waiters. Always stores (never a
    /// no-op), matching `watch::Sender::send_replace`.
    func sendReplace(_ value: Value) {
        cond.lock()
        current = value
        version &+= 1
        cond.broadcast()
        cond.unlock()
    }

    /// Block until `version` advances past `lastSeen` or `deadline`
    /// passes. Returns the fresh `(value, version)` on change, or `nil`
    /// on timeout.
    func waitForChange(after lastSeen: UInt64, deadline: Date) -> (Value, UInt64)? {
        cond.lock(); defer { cond.unlock() }
        while version == lastSeen {
            if !cond.wait(until: deadline) {
                return nil
            }
        }
        return (current, version)
    }
}

/// Receiver handle for a `Watch`. Mirrors `tokio::sync::watch::Receiver`:
/// `value()` is `borrow().clone()`, `changed(timeout:)` is
/// `changed().await` followed by `borrow().clone()`. A freshly created
/// receiver treats the current value as already seen, so `changed`
/// waits for the NEXT update — exactly like `subscribe()`.
public final class WatchReceiver<Value: Sendable>: @unchecked Sendable {
    private let watch: Watch<Value>
    private var lastSeen: UInt64

    fileprivate init(_ watch: Watch<Value>) {
        self.watch = watch
        self.lastSeen = watch.currentVersion()
    }

    /// Current snapshot. Always the latest stored value, regardless of
    /// whether this receiver existed when it was stored.
    public func value() -> Value {
        return watch.currentValue()
    }

    /// Block until the watched value changes or `timeout` elapses.
    /// Returns the new value, or `nil` on timeout.
    @discardableResult
    public func changed(timeout: TimeInterval) -> Value? {
        let deadline = Date().addingTimeInterval(timeout)
        guard let (value, version) = watch.waitForChange(after: lastSeen, deadline: deadline) else {
            return nil
        }
        lastSeen = version
        return value
    }
}

// MARK: - Response Channel (deferred identity probe)

/// Blocking single-flow frame channel used to deliver an in-flight
/// probe's reply frames from the master reader thread to the probe
/// driver thread. Mirrors the `(xid, rid)`-keyed
/// `external_response_channels` entry Rust's
/// `run_identity_probe_via_relay` registers: the reader path delivers
/// the echo here instead of surfacing it to the engine.
private final class ResponseChannel: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var frames: [Frame] = []

    func deliver(_ frame: Frame) {
        lock.lock()
        frames.append(frame)
        lock.unlock()
        semaphore.signal()
    }

    /// Wait for the next delivered frame up to `deadline`. Returns nil
    /// on timeout.
    func recv(deadline: DispatchTime) -> Frame? {
        if semaphore.wait(timeout: deadline) == .timedOut {
            return nil
        }
        lock.lock(); defer { lock.unlock() }
        return frames.isEmpty ? nil : frames.removeFirst()
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
    private var aggregateInstalledCartridges: [InstalledCartridgeRecord] = []
    private var negotiatedLimits: Limits = Limits()
    private let lock = NSLock()
    private var frameChannel: [(masterIdx: Int, frame: Frame?, error: Error?)] = []
    private let frameSemaphore = DispatchSemaphore(value: 0)

    /// Serialises `addMaster` across the whole switch.
    /// `masterIdx` is the routing key for capTable / requestRouting;
    /// it must be decided once per slot and stay stable for the
    /// slot's lifetime. Concurrent addMaster calls would race on
    /// `masters.count` — two appenders could both decide they are
    /// slot N. The lock covers the I/O too (RelayNotify read +
    /// identity probe) so the reattach branch sees a stable view
    /// of `masters` for the duration; contention is bounded by the
    /// small slot count.
    private let addMasterLock = NSLock()

    /// Shutdown flag - when true, reader threads should exit
    private var isShutdown = false

    /// Response channels for in-flight deferred identity probes, keyed
    /// by the probe's (xid, rid). The master reader thread diverts a
    /// frame whose (xid, rid) matches a registered channel here instead
    /// of enqueueing it for the engine — the mechanism that lets the
    /// probe driver await the host's nonce echo end-to-end. Mirrors
    /// Rust's `external_response_channels`.
    private var externalResponseChannels: [RoutingKey: ResponseChannel] = [:]

    /// Queue of master indexes whose advertised cap set transitioned
    /// from empty to non-empty since the last identity probe. The probe
    /// driver thread drains this and runs an end-to-end identity probe
    /// against each, gating cap-table publication on probe success —
    /// the runtime counterpart to the synchronous `addMaster` probe.
    /// Mirrors Rust's `pending_identity_probes` channel.
    private var pendingIdentityProbes: [Int] = []
    /// Wakes the probe driver when a master index is queued (or on
    /// shutdown).
    private let probeSemaphore = DispatchSemaphore(value: 0)
    /// Whether the probe driver thread has been spawned. Spawned lazily
    /// the first time a probe is queued; idempotent thereafter.
    private var probeDriverStarted = false

    /// Watch broadcasting the latest *routable* capability bytes (the
    /// JSON array of cap URNs from HEALTHY masters only). Subscribers
    /// receive the current value on subscribe and a fresh value every
    /// time `rebuildCapabilities` changes the routable set — including
    /// when a deferred identity probe completes and a previously
    /// unhealthy master's caps become routable. This is the
    /// health-tied readiness signal. Mirrors `aggregate_capabilities_tx`.
    private let capabilitiesWatch = Watch<Data>(Data("[]".utf8))
    /// Watch broadcasting the latest installed-cartridge inventory
    /// aggregate. Deliberately NOT health-filtered. Mirrors
    /// `aggregate_installed_cartridges_tx`.
    private let installedCartridgesWatch = Watch<[InstalledCartridgeRecord]>([])

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

        // Reject duplicate ids up front. Without this, two slots
        // would be created with the same id; the first reconnect
        // would reattach to whichever slot is found first by the
        // linear scan in `addMaster`, leaving the other stuck
        // unhealthy forever — the exact bug class this contract
        // closes.
        var seenIds: Set<String> = Set()
        for sp in sockets {
            if !seenIds.insert(sp.id).inserted {
                throw RelaySwitchError.protocolError(
                    "RelaySwitch.init: duplicate master id '\(sp.id)' in cardinality list — " +
                    "each slot must have a unique stable id"
                )
            }
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
            var caps = notifyPayload.capUrns()

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
                            caps = notifyPayload.capUrns()
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
                id: sockPair.id,
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

        // Signal semaphores to wake any waiting readers and the probe driver
        frameSemaphore.signal()
        probeSemaphore.signal()
    }

    /// deinit sets shutdown flag
    deinit {
        lock.lock()
        isShutdown = true
        lock.unlock()
        probeSemaphore.signal()
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
                        // Detect an empty→non-empty cap transition and, if so,
                        // hold the master unhealthy and queue a deferred
                        // runtime identity probe before its new caps become
                        // routable. See applyRelayNotifyUpdate. A malformed
                        // payload is logged and skipped — never thrown with
                        // the lock held (that would deadlock this thread's
                        // own catch handler below).
                        do {
                            try applyRelayNotifyUpdate(sourceIdx: masterIdx, manifest: manifest, newLimits: limits)
                        } catch {
                            fputs("[RelaySwitch] master \(masterIdx): RelayNotify update failed: \(error)\n", stderr)
                        }
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

                    // Divert frames belonging to an in-flight deferred
                    // identity probe to that probe's response channel
                    // instead of surfacing them to the engine. The probe
                    // driver registered the channel keyed by the probe's
                    // (xid, rid); the host echoes the nonce on that same
                    // flow. Mirrors Rust's external_response_channels
                    // delivery in the master-read path.
                    if let xid = readyFrame.routingId {
                        let probeKey = RoutingKey(xid: xid, rid: readyFrame.id)
                        lock.lock()
                        let channel = externalResponseChannels[probeKey]
                        lock.unlock()
                        if let channel = channel {
                            channel.deliver(readyFrame)
                            continue
                        }
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

    /// Add or reattach a master.
    ///
    /// `socket.id` is the stable identity of the cardinality slot:
    ///
    /// - Existing slot, currently UNHEALTHY → reattach in place at
    ///   the existing slot index. The dead master's reader thread
    ///   has already exited on EOF; the new connection installs a
    ///   fresh writer / reader thread and clears the unhealthy
    ///   flag. Routing entries keyed by `masterIdx` stay coherent
    ///   because the index does not change.
    /// - Existing slot, currently HEALTHY → caller bug (the same
    ///   master must not be added twice). Throws
    ///   `RelaySwitchError.protocolError` so the wiring mistake is
    ///   fixed instead of silently growing zombie slots.
    /// - No existing slot with that id → append a fresh slot at
    ///   `masters.count`. The reader thread is spawned with that
    ///   index baked in.
    ///
    /// Returns the slot index (stable across reattach).
    public func addMaster(_ socket: SocketPair) throws -> Int {
        addMasterLock.lock()
        defer { addMasterLock.unlock() }

        var socketReader = FrameReader(handle: socket.read)
        let socketWriter = FrameWriter(handle: socket.write)

        // Existing-slot lookup under the inner lock so the linear
        // scan observes a stable `masters`.
        lock.lock()
        var existingIdx: Int? = nil
        for (idx, m) in masters.enumerated() {
            if m.id == socket.id {
                if m.healthy {
                    lock.unlock()
                    throw RelaySwitchError.protocolError(
                        "addMaster: id '\(socket.id)' is already attached to a healthy slot at index \(idx) — " +
                        "cardinality violation (each id may only be attached once at a time)"
                    )
                }
                existingIdx = idx
                break
            }
        }
        // Reserve the slot index. For the append case this is the
        // current length under `addMasterLock`; for reattach it is
        // the existing slot index. The reader thread captures this
        // value so per-frame routing always carries the right index.
        let masterIdx = existingIdx ?? masters.count
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
        var caps = notifyPayload.capUrns()

        let seqAssigner = SeqAssigner()

        // End-to-end identity verification. Only meaningful when the host
        // advertises at least one cap — otherwise there is no cartridge
        // chain to echo the nonce. The master still joins so its
        // `installed_cartridges` attachment errors reach the engine.
        //
        // Unlike `init`, a probe FAILURE here does NOT abort registration:
        // the master is registered UNHEALTHY with `lastError` set, so its
        // installed_cartridges remain visible to the inventory aggregate
        // while its caps are held back from routing (cap_table skips
        // unhealthy masters). Mirrors Rust `add_master`, which captures the
        // failure into `identity_failure` and registers unhealthy rather
        // than returning Err.
        var identityFailure: String? = nil
        if !caps.isEmpty {
            lock.lock()
            xidCounter += 1
            let xid = MessageId.uint(xidCounter)
            lock.unlock()

            let nonce = identityNonce()
            let reqId = MessageId.newUUID()
            let streamId = "identity-verify"

            do {
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
                probeLoop: while true {
                    guard let frame = try socketReader.read() else {
                        identityFailure = "new master \(masterIdx): connection closed during identity verification"
                        break
                    }

                    switch frame.frameType {
                    case .relayNotify:
                        if let manifest = frame.relayNotifyManifest {
                            capsPayload = manifest
                            notifyPayload = try Self.parseRelayNotifyPayload(capsPayload)
                            caps = notifyPayload.capUrns()
                        }
                        if let newLimits = frame.relayNotifyLimits {
                            masterLimits = newLimits
                        }
                    case .streamStart, .streamEnd:
                        break
                    case .chunk:
                        if let payload = frame.payload {
                            accumulated.append(payload)
                        }
                    case .end:
                        if accumulated != nonce {
                            identityFailure = "new master \(masterIdx): identity verification payload mismatch (expected \(nonce.count) bytes, got \(accumulated.count))"
                        }
                        break probeLoop
                    case .err:
                        let code = frame.errorCode ?? "UNKNOWN"
                        let msg = frame.errorMessage ?? "no message"
                        identityFailure = "new master \(masterIdx): identity verification failed: [\(code)] \(msg)"
                        break probeLoop
                    default:
                        identityFailure = "new master \(masterIdx): identity verification: unexpected frame type \(frame.frameType)"
                        break probeLoop
                    }
                }
            } catch {
                identityFailure = "new master \(masterIdx): identity verification error: \(error)"
            }

            if let failure = identityFailure {
                fputs("[RelaySwitch] addMaster: identity verification FAILED for master \(masterIdx) — registering unhealthy so installed_cartridges stay visible: \(failure)\n", stderr)
            }
        }
        let healthyAtRegister = identityFailure == nil

        // Commit the connection state into the slot.
        lock.lock()
        if existingIdx == nil {
            // Append. The captured `masterIdx` MUST equal the new
            // length; if not, a concurrent appender bypassed
            // `addMasterLock`, which is a protocol violation.
            if masters.count != masterIdx {
                lock.unlock()
                throw RelaySwitchError.protocolError(
                    "addMaster: append-index race for id '\(socket.id)': reserved \(masterIdx) but masters.count is now \(masters.count) " +
                    "(a concurrent caller bypassed addMasterLock)"
                )
            }
            let masterConn = MasterConnection(
                id: socket.id,
                socketWriter: socketWriter,
                seqAssigner: seqAssigner,
                manifest: capsPayload,
                limits: masterLimits,
                caps: caps,
                installedCartridges: notifyPayload.installedCartridges,
                healthy: healthyAtRegister,
                lastError: identityFailure
            )
            masters.append(masterConn)
        } else {
            let slot = masters[masterIdx]
            if slot.id != socket.id {
                lock.unlock()
                throw RelaySwitchError.protocolError(
                    "addMaster: reattach-id mismatch at index \(masterIdx): expected '\(socket.id)' but found '\(slot.id)'"
                )
            }
            // In-place mutation. The dead master's reader thread
            // has already exited on EOF (Swift threads aren't
            // cancellable; we rely on the natural EOF exit). The
            // new reader thread is wired in below.
            slot.socketWriter = socketWriter
            slot.seqAssigner = seqAssigner
            slot.reorderBuffer = ReorderBuffer(maxBufferPerFlow: masterLimits.maxReorderBuffer)
            slot.manifest = capsPayload
            slot.limits = masterLimits
            slot.caps = caps
            slot.installedCartridges = notifyPayload.installedCartridges
            slot.healthy = healthyAtRegister
            slot.lastError = identityFailure
        }

        // Spawn reader thread bound to the slot's index. For
        // reattach this is the existing index; for append it's
        // `masters.count - 1`. Either way captured by value here.
        let boundIdx = masterIdx
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readerLoop(masterIdx: boundIdx, reader: socketReader)
        }

        // Rebuild tables
        rebuildCapTable()
        rebuildCapabilities()
        rebuildLimits()
        lock.unlock()

        return masterIdx
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

    /// Per-master health snapshot, mirroring Rust `get_master_health`.
    /// Includes each master's `lastError` so callers can see why a
    /// master is unhealthy (e.g. a failed identity probe).
    public func getMasterHealth() -> [MasterHealthStatus] {
        lock.lock()
        defer { lock.unlock() }
        return masters.enumerated().map { (idx, m) in
            MasterHealthStatus(index: idx, healthy: m.healthy, capCount: m.caps.count, lastError: m.lastError)
        }
    }

    /// Count of healthy masters. Mirrors Rust `healthy_master_count`.
    public func healthyMasterCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return masters.filter { $0.healthy }.count
    }

    /// Diagnostic / test hook: which master (if any) a REQ for `capUrn`
    /// would route to right now. Goes through the real dispatch path
    /// (`findMasterForCap` → `isDispatchable` + specificity ranking over
    /// the HEALTHY-only cap table) — never a string comparison of URNs.
    /// Mirrors Rust's `find_master_for_cap(cap, preferred)` used by the
    /// parity tests to assert routability.
    func routableMaster(forCap capUrn: String, preferredCap: String? = nil) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return findMasterForCap(capUrn, preferredCap: preferredCap)
    }

    /// Subscribe to changes in the *routable* capability set. The
    /// returned receiver yields the current `aggregateCapabilities`
    /// bytes (a JSON array of cap URNs) immediately via `value()` and a
    /// fresh snapshot on every routable-set change — including when a
    /// deferred identity probe completes and a previously-unhealthy
    /// master's caps become routable. Mirrors Rust
    /// `subscribe_capabilities`.
    public func subscribeCapabilities() -> WatchReceiver<Data> {
        return WatchReceiver(capabilitiesWatch)
    }

    /// Subscribe to per-cartridge inventory changes. The returned
    /// receiver yields the current (NOT health-filtered) inventory
    /// aggregate immediately and a fresh snapshot on every change.
    /// Mirrors Rust `subscribe_installed_cartridges`.
    public func subscribeInstalledCartridges() -> WatchReceiver<[InstalledCartridgeRecord]> {
        return WatchReceiver(installedCartridgesWatch)
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
            guard let cap = frame.cap else {
                throw RelaySwitchError.protocolError("REQ frame missing cap URN")
            }

            // Validate XID-absence and assign the XID FIRST, before any
            // dispatch-failure path: every frame the switch emits toward
            // a master must carry an XID (the host runtime's path-C
            // invariant), including the synthetic ERR we may produce
            // below for an unhandled cap. Assigning up-front lets the
            // failure-path ERR carry the same XID the request would have.
            //
            // REQs from cartridges should NOT have XID (per protocol spec).
            if frame.routingId != nil {
                throw RelaySwitchError.protocolError("REQ from cartridge should not have XID")
            }

            // Assign fresh XID
            xidCounter += 1
            let xid = MessageId.uint(xidCounter)
            mutableFrame.routingId = xid

            // Find destination master (no preference for peer requests).
            guard let destIdx = findMasterForCap(cap, preferredCap: nil) else {
                // No handler registered for this cap. Rather than throwing
                // — which aborts the pump and leaves the caller hanging
                // until its activity timeout — send an ERR frame straight
                // back to the source master so the peer call fails fast
                // with a clear error. Stamp the synthetic XID assigned
                // above so the receiving cartridge host runtime accepts it
                // (path-C invariant). Mirrors Rust's handle_master_frame
                // NO_HANDLER branch (Ok(None) + ERR to caller).
                fputs("[RelaySwitch] NO_HANDLER for peer REQ cap='\(cap)' rid=\(frame.id) from_master=\(sourceIdx) — sending ERR to caller\n", stderr)
                var errFrame = Frame.err(id: frame.id, code: "NO_HANDLER", message: "No handler found for cap: \(cap)")
                errFrame.routingId = xid
                try? writeToMasterIdx(sourceIdx, &errFrame)
                return nil
            }

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
            // Capability update from host — update our cap table. Detect
            // an empty→non-empty cap transition and, if so, hold the
            // master unhealthy and queue a deferred runtime identity probe
            // before its new caps become routable (see
            // applyRelayNotifyUpdate). This branch is reached only when a
            // RelayNotify is delivered through the frame queue rather than
            // intercepted in the reader loop; both sites share the helper
            // so the behaviour is identical. Mirrors Rust's
            // handle_master_frame RelayNotify branch.
            if let manifest = frame.relayNotifyManifest,
               let newLimits = frame.relayNotifyLimits {
                try applyRelayNotifyUpdate(sourceIdx: sourceIdx, manifest: manifest, newLimits: newLimits)
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

    func handleMasterDeath(_ masterIdx: Int) throws {
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

    // MARK: - Deferred Runtime Identity Probe

    /// Apply a RelayNotify capability update for `sourceIdx` and, if the
    /// master transitioned from EMPTY caps to NON-EMPTY caps, hold it
    /// unhealthy and queue a deferred runtime identity probe before its
    /// new caps become routable.
    ///
    /// The initial RelayNotify during construction / `addMaster` skipped
    /// the synchronous identity probe when caps were empty (no cartridge
    /// chain to echo the nonce). If the host now advertises a real handler
    /// chain we must probe it end-to-end before letting the new caps
    /// become dispatch targets — the master is held unhealthy until the
    /// probe driver confirms identity. Mirrors Rust's
    /// handle_master_frame RelayNotify branch.
    ///
    /// Caller MUST hold `lock`.
    private func applyRelayNotifyUpdate(sourceIdx: Int, manifest: Data, newLimits: Limits) throws {
        let payload = try Self.parseRelayNotifyPayload(manifest)
        let newCaps = payload.capUrns()

        // Detect the empty→non-empty transition BEFORE overwriting caps.
        let priorCapsEmpty = masters[sourceIdx].caps.isEmpty
        let probeRequired = priorCapsEmpty && !newCaps.isEmpty

        // Always apply installed_cartridges / limits / manifest (inventory
        // is observation-only data the engine surfaces immediately). Caps
        // are written too so RelayNotify-update lookups stay consistent —
        // but when probeRequired we mark the master unhealthy below so the
        // cap_table rebuild excludes it.
        masters[sourceIdx].caps = newCaps
        masters[sourceIdx].installedCartridges = payload.installedCartridges
        masters[sourceIdx].manifest = manifest
        masters[sourceIdx].limits = newLimits

        if probeRequired {
            masters[sourceIdx].healthy = false
            masters[sourceIdx].lastError = "runtime identity probe pending — caps held back from routing"
        }

        rebuildCapTable()
        rebuildCapabilities()
        rebuildLimits()

        if probeRequired {
            // Hand off to the probe driver thread. Queue + signal under
            // the lock; the driver pops and runs the probe outside it.
            pendingIdentityProbes.append(sourceIdx)
            ensureProbeDriverStarted()
            probeSemaphore.signal()
        }
    }

    /// Spawn the probe driver thread once. Idempotent. Caller MUST hold
    /// `lock`. Mirrors Rust's `spawn_identity_probe_driver` (which is
    /// likewise spawned at most once and serially drains the queue).
    private func ensureProbeDriverStarted() {
        if probeDriverStarted { return }
        probeDriverStarted = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.identityProbeDriverLoop()
        }
    }

    /// Serially drains `pendingIdentityProbes`, running an end-to-end
    /// identity probe against each queued master. On success the master
    /// flips healthy and its caps become routable; on failure it stays
    /// unhealthy with `lastError` set. Mirrors Rust's
    /// spawn_identity_probe_driver task body.
    private func identityProbeDriverLoop() {
        while true {
            probeSemaphore.wait()

            lock.lock()
            if isShutdown {
                lock.unlock()
                return
            }
            guard !pendingIdentityProbes.isEmpty else {
                lock.unlock()
                continue
            }
            let masterIdx = pendingIdentityProbes.removeFirst()
            lock.unlock()

            runIdentityProbeViaRelay(masterIdx)
        }
    }

    /// Run the end-to-end runtime identity probe against `masterIdx`.
    ///
    /// Sends CAP_IDENTITY REQ + STREAM_START + CHUNK(nonce) + STREAM_END +
    /// END (all on a fresh `(xid, rid)` flow) and awaits the host's nonce
    /// echo via a response channel registered in
    /// `externalResponseChannels` — the master reader thread diverts the
    /// echo frames there. On success flips the master healthy and rebuilds
    /// the cap table so its caps become routable; on failure keeps it
    /// unhealthy and stamps `lastError`. Mirrors Rust's
    /// run_identity_probe_via_relay + the driver's success/failure arms.
    private func runIdentityProbeViaRelay(_ masterIdx: Int) {
        let runtimeProbeTimeout: TimeInterval = 10.0
        let channel = ResponseChannel()

        // Build the probe flow and register its response channel + routing
        // under the lock, then send the five frames. Holding the lock for
        // the sends matches the rest of the switch (handleMasterFrame /
        // sendToMaster also write under the lock); the frames are tiny so
        // the unix-socket write does not block.
        lock.lock()
        if isShutdown || masterIdx >= masters.count {
            lock.unlock()
            return
        }
        xidCounter += 1
        let xid = MessageId.uint(xidCounter)
        let rid = MessageId.newUUID()
        let key = RoutingKey(xid: xid, rid: rid)

        externalResponseChannels[key] = channel
        originMap[key] = nil as Int?
        requestRouting[key] = RoutingEntry(sourceMasterIdx: nil, destinationMasterIdx: masterIdx)
        ridToXid[rid] = xid

        let nonce = identityNonce()
        let streamId = "identity-verify-runtime"

        var sendError: String? = nil
        do {
            var req = Frame.req(id: rid, capUrn: CSCapIdentity as String, payload: Data(), contentType: "application/cbor")
            req.routingId = xid
            try writeToMasterIdx(masterIdx, &req)

            var ss = Frame.streamStart(reqId: rid, streamId: streamId, mediaUrn: "media:")
            ss.routingId = xid
            try writeToMasterIdx(masterIdx, &ss)

            let checksum = Frame.computeChecksum(nonce)
            var chunk = Frame.chunk(reqId: rid, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum)
            chunk.routingId = xid
            try writeToMasterIdx(masterIdx, &chunk)

            var se = Frame.streamEnd(reqId: rid, streamId: streamId, chunkCount: 1)
            se.routingId = xid
            try writeToMasterIdx(masterIdx, &se)

            var end = Frame.end(id: rid)
            end.routingId = xid
            try writeToMasterIdx(masterIdx, &end)
        } catch {
            sendError = "identity probe send failed: \(error)"
        }
        lock.unlock()

        if let sendError = sendError {
            failProbe(masterIdx: masterIdx, key: key, rid: rid, detail: sendError)
            return
        }

        // Await the echo OUTSIDE the lock so the reader thread can deliver
        // frames to the channel. Cartridge contract: the identity handler
        // echoes the nonce back as STREAM_START + CHUNK(nonce) + STREAM_END
        // + END on the same flow.
        let deadline = DispatchTime.now() + runtimeProbeTimeout
        var accumulated = Data()
        // Failure detail, or `nil` once the probe has succeeded. Starts as a
        // timeout failure so a silent channel resolves to the timeout error,
        // matching Rust's `Result<(), String>` default. (Swift `Result`
        // requires `Failure: Error`, which a bare `String` is not, so the
        // outcome is modelled as an optional detail rather than a Result.)
        var failureDetail: String? = "runtime identity probe timed out after \(runtimeProbeTimeout)s"

        recvLoop: while true {
            guard let frame = channel.recv(deadline: deadline) else {
                failureDetail = "runtime identity probe timed out after \(runtimeProbeTimeout)s"
                break
            }
            switch frame.frameType {
            case .streamStart, .streamEnd:
                continue
            case .chunk:
                if let payload = frame.payload {
                    accumulated.append(payload)
                }
            case .end:
                if accumulated != nonce {
                    failureDetail = "identity probe payload mismatch (expected \(nonce.count) bytes, got \(accumulated.count))"
                } else {
                    failureDetail = nil
                }
                break recvLoop
            case .err:
                let code = frame.errorCode ?? "UNKNOWN"
                let msg = frame.errorMessage ?? "no message"
                failureDetail = "identity probe failed: [\(code)] \(msg)"
                break recvLoop
            default:
                failureDetail = "identity probe: unexpected frame type \(frame.frameType)"
                break recvLoop
            }
        }

        if let detail = failureDetail {
            failProbe(masterIdx: masterIdx, key: key, rid: rid, detail: detail)
        } else {
            // Probe passed — flip the master back to healthy and rebuild
            // the cap table so its caps become routable. We held it
            // unhealthy from the moment caps went non-empty until
            // verification completed; this is the natural reverse.
            lock.lock()
            cleanupProbeRouting(key: key, rid: rid)
            if masterIdx < masters.count {
                masters[masterIdx].healthy = true
                masters[masterIdx].lastError = nil
            }
            rebuildCapTable()
            rebuildCapabilities()
            lock.unlock()
            fputs("[RelaySwitch] runtime identity probe passed — master \(masterIdx) is now healthy\n", stderr)
        }
    }

    /// Keep the master unhealthy, stamp `lastError`, purge the probe's
    /// routing entries, and rebuild tables. Used for both probe-send
    /// failures and a failed / timed-out echo.
    private func failProbe(masterIdx: Int, key: RoutingKey, rid: MessageId, detail: String) {
        fputs("[RelaySwitch] runtime identity probe FAILED for master \(masterIdx) — remains unhealthy: \(detail)\n", stderr)
        lock.lock()
        cleanupProbeRouting(key: key, rid: rid)
        if masterIdx < masters.count {
            masters[masterIdx].healthy = false
            masters[masterIdx].lastError = detail
        }
        rebuildCapTable()
        rebuildCapabilities()
        lock.unlock()
    }

    /// Purge the routing/response-channel entries a probe registered.
    /// Caller MUST hold `lock`.
    private func cleanupProbeRouting(key: RoutingKey, rid: MessageId) {
        externalResponseChannels.removeValue(forKey: key)
        originMap.removeValue(forKey: key)
        requestRouting.removeValue(forKey: key)
        ridToXid.removeValue(forKey: rid)
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
        // Caps stay a Set<String> — strings are Hashable. Installed
        // cartridges, on the other hand, can no longer be Hashable
        // (their `capGroups` carry CapDefinitions whose URNs are
        // 3D mixed-variance partial orders — see capdag/docs/02 §18.5
        // on why Cap URNs intentionally have no total/Hashable order).
        // We dedupe by identity tuple manually using a dictionary
        // keyed by `(registryURL, channel, id, version, sha256)`,
        // matching the Rust relay's `dedup_by` rule.
        //
        // ROUTABLE caps are HEALTH-FILTERED (only healthy masters
        // contribute), but the installed-cartridge INVENTORY is NOT — it
        // is collected from ALL masters regardless of health. A master
        // held unhealthy by a failed identity probe (or a transient flap)
        // must still surface its installed cartridges to the engine's
        // inventory view; only ROUTING is gated. Filtering inventory by
        // master health caused the "all cartridges disappeared" symptom on
        // every transient flap. See the Rust rebuild_capabilities comment
        // (~3475-3490).
        var allCaps = Set<String>()
        var byIdentity: [String: InstalledCartridgeRecord] = [:]
        for master in masters {
            if master.healthy {
                allCaps.formUnion(master.caps)
            }
            // Inventory: collected unconditionally (NOT under the health gate).
            for cart in master.installedCartridges {
                byIdentity[Self.identityKey(cart)] = cart
            }
        }

        let capsArray = Array(allCaps).sorted()
        let newCapabilities = (try? JSONSerialization.data(withJSONObject: capsArray)) ?? Data()
        // Sort by the FULL identity tuple `(registryURL, channel, id,
        // version, sha256)`, matching Rust's `InstalledCartridgeRecord::
        // identity_cmp`. A nil registryURL (dev install) sorts before any
        // Some, matching Rust's `Option` ordering (None < Some). Sorting by
        // only id/version/sha256 left two installs that differ solely in
        // registry or channel in a non-deterministic order.
        let newInstalled = byIdentity.values.sorted { a, b in
            if a.registryURL != b.registryURL {
                switch (a.registryURL, b.registryURL) {
                case (nil, _): return true
                case (_, nil): return false
                case let (x?, y?): return x < y
                }
            }
            if a.channel != b.channel { return a.channel < b.channel }
            if a.id != b.id { return a.id < b.id }
            if a.version != b.version { return a.version < b.version }
            return a.sha256 < b.sha256
        }

        // Detect changes BEFORE storing, then publish to the watches only
        // on an actual change — mirroring Rust's `changed` guard so a
        // deferred probe completing wakes subscribers without a notify
        // storm from unrelated rebuilds. `sendReplace` always stores the
        // new value (even with zero receivers), which is required because
        // `init` rebuilds capabilities before any subscriber exists.
        let capsChanged = newCapabilities != aggregateCapabilities
        let installedChanged = !Self.installedCartridgesEqual(aggregateInstalledCartridges, newInstalled)

        aggregateCapabilities = newCapabilities
        aggregateInstalledCartridges = newInstalled

        if capsChanged {
            capabilitiesWatch.sendReplace(newCapabilities)
        }
        if installedChanged {
            installedCartridgesWatch.sendReplace(newInstalled)
        }
    }

    /// Structural equality for the inventory aggregate. `InstalledCartridgeRecord`
    /// is deliberately not `Equatable` (its cap URNs have no total order),
    /// so we compare the canonical JSON encodings — which captures every
    /// field including `runtimeStats`, matching Rust's `Vec` `PartialEq`
    /// used to guard the change-notify. On encode failure we conservatively
    /// report "changed" so a subscriber is never starved of an update.
    private static func installedCartridgesEqual(_ a: [InstalledCartridgeRecord], _ b: [InstalledCartridgeRecord]) -> Bool {
        if a.count != b.count { return false }
        let encoder = JSONEncoder()
        guard let ea = try? encoder.encode(a), let eb = try? encoder.encode(b) else {
            return false
        }
        return ea == eb
    }

    /// Stable inventory key — the same five fields the Rust side
    /// uses for `dedup_by`. `\u{1F}` (US — Unit Separator) is the
    /// natural ASCII delimiter for combining fixed-position fields
    /// and never appears in any of the field values (URLs, IDs,
    /// version strings, SHA hex digests).
    private static func identityKey(_ cart: InstalledCartridgeRecord) -> String {
        let registry = cart.registryURL ?? ""
        return "\(registry)\u{1F}\(cart.channel)\u{1F}\(cart.id)\u{1F}\(cart.version)\u{1F}\(cart.sha256)"
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

    public func installedCartridges() -> [InstalledCartridgeRecord] {
        lock.lock()
        defer { lock.unlock() }
        return aggregateInstalledCartridges
    }

    private static func parseRelayNotifyPayload(_ manifest: Data) throws -> RelayNotifyCapabilitiesPayload {
        let payload: RelayNotifyCapabilitiesPayload
        do {
            payload = try JSONDecoder().decode(RelayNotifyCapabilitiesPayload.self, from: manifest)
        } catch {
            throw RelaySwitchError.protocolError("RelayNotify payload must contain installed_cartridges: \(error)")
        }

        // If the host advertises any caps, CAP_IDENTITY must be among them —
        // that is the contract that makes end-to-end identity verification
        // meaningful. The cap-urn list is computed from cap_groups inside
        // every installed cartridge; a non-empty list must include identity.
        let capUrns = payload.capUrns()
        if !capUrns.isEmpty {
            let identityUrn = try? CSCapUrn.fromString(CSCapIdentity)
            let hasIdentity = capUrns.contains { capStr in
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
    /// The on-disk install context (slug folder, channel folder,
    /// name/version directory components) disagrees with what
    /// `cartridge.json` declares. The cartridge is structurally
    /// well-formed but cannot be trusted because its placement on
    /// disk does not match what it claims to be. Hosts grace-period
    /// the offending directory and then delete it; the record is
    /// surfaced so the operator sees what landed where before it
    /// disappears. Distinct from `quarantined` (host decided after a
    /// crash) and from `manifestInvalid` (cartridge.json itself is
    /// unreadable or schema-broken).
    case badInstallation = "bad_installation"
    /// Operator explicitly disabled this cartridge through the host
    /// UI. The cartridge is on disk and would otherwise have
    /// attached cleanly; the host treats it as if the binary were
    /// yanked out of the system. Re-enabling is a UI-driven
    /// operator action. Enforced at the host level (machfab-mac's
    /// XPC service); the engine doesn't act on it differently from
    /// any other failed attachment, but preserves the kind so
    /// consumers can render the right reason and offer the right
    /// recovery action.
    case disabled
    /// The cartridge declares a non-null `registry_url`, but the
    /// host could not reach that registry to verify the cartridge
    /// is listed. Distinct from `.badInstallation` (= registry
    /// confirmed the version is missing) — `.registryUnreachable`
    /// means we don't know. Recovery is "check network + retry"
    /// rather than "rebuild as dev". The cartridge is held back
    /// from attaching until verification succeeds. Network fetch
    /// is performed by the main app (which has outbound network
    /// entitlement) and pushed to the XPC service as a verdict
    /// map; the XPC service is sandboxed and cannot fetch
    /// registries directly.
    case registryUnreachable = "registry_unreachable"
    /// The cartridge was built against a different fabric registry
    /// manifest version than this host is pinned to. Both host and
    /// cartridge bake their fabric manifest version at build time from
    /// `MFR_FABRIC_MANIFEST_VERSION` (sourced from
    /// `fabric/manifest-version.txt`); the host refuses to load any
    /// cartridge whose baked version does not match its own. Recovery
    /// action is "rebuild the cartridge against the host's fabric
    /// manifest version" — there is no in-host fallback because URN
    /// resolution between mismatched versions is fundamentally unsafe
    /// (cap and media definitions may have changed shape across manifest
    /// versions).
    case fabricManifestVersionMismatch = "fabric_manifest_version_mismatch"
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

/// Positive lifecycle phase that runs BEFORE a cartridge becomes
/// dispatchable. Mirrors the Rust `CartridgeLifecycle` and the
/// `CartridgeLifecycle` enum in `cartridge.proto`.
///
/// Mutually exclusive with `attachmentError` on
/// `InstalledCartridgeRecord`: when the cartridge has a failed
/// terminal classification, `attachmentError` is `non-nil` and
/// `lifecycle` is irrelevant. When `attachmentError` is `nil`, the
/// cartridge is in one of the in-progress phases or has reached
/// `.operational`; only `.operational` cartridges are dispatchable.
///
/// See `machfab-mac/docs/cartridge state machine.md` for the
/// canonical state diagram.
public enum CartridgeLifecycle: String, Codable, Hashable, Sendable {
    /// Discovery scan has found the version directory and is about
    /// to inspect it. Transient — the host normally moves to
    /// `.inspecting` in the same scan tick.
    case discovered
    /// Reading `cartridge.json`, computing directory hash,
    /// validating on-disk install context. Hashing can take
    /// seconds for large model cartridges; runs on a background
    /// queue so other cartridges' inspections proceed in parallel.
    case inspecting
    /// Inspection succeeded. Awaiting a verdict from the registry
    /// verifier service. Skipped for dev cartridges
    /// (`registry_url == nil`) and bundle cartridges.
    case verifying
    /// Cleared every gate. Caps are registered with the engine
    /// and dispatch can route requests to this cartridge.
    case operational
}

/// Order/Hash-theoretic note: this struct conforms to `Codable` and
/// `Sendable` but NOT to `Equatable` or `Hashable`. The reason: the
/// `capGroups` field carries `CapDefinition`s whose `urn` strings
/// represent Cap URNs — a 3-dimensional product `(in, out, y)` with
/// mixed variance (input contravariant, output covariant, y-tags
/// refinement). Cap URNs are intentionally NOT one-dimensional and
/// have no canonical structural equality or hash beyond exact byte
/// identity of the canonical form (which would conflate equivalent
/// URNs that differ only in tag order). See `capdag/docs/02-FORMAL-FOUNDATIONS.md`
/// §18.5 — "treating Cap URNs as one-dimensional" is a documented
/// failure mode.
///
/// Code that needs to dedupe installs uses the identity tuple
/// `(registryURL, channel, id, version, sha256)` directly — five
/// flat strings/enums that DO have an unambiguous total order and
/// hash. See `RelaySwitch.identityKey(_:)` for the convention.
public struct InstalledCartridgeRecord: Codable, Sendable {
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
    /// Cap groups exactly as the cartridge declared them in its
    /// manifest. Each group bundles caps with the `adapter_urns` it
    /// volunteers to inspect. Empty when the cartridge failed
    /// attachment before its manifest could be parsed. The flat cap
    /// snapshot is computed from these groups, not stored alongside
    /// them on the wire.
    public let capGroups: [CapGroup]
    /// Present when the cartridge failed to attach; absent when healthy.
    public let attachmentError: CartridgeAttachmentError?
    /// Live runtime statistics from the host that owns this cartridge.
    /// `nil` for cartridges that aren't host-tracked (e.g. identities
    /// emitted by an in-process host with no routing tables).
    public let runtimeStats: CartridgeRuntimeStats?
    /// Positive lifecycle phase. Mutually exclusive with
    /// `attachmentError`: when the cartridge has a failed terminal
    /// classification, `attachmentError` is non-nil and this field
    /// is irrelevant. When `attachmentError` is nil, the cartridge
    /// is dispatchable iff `lifecycle == .operational`.
    ///
    /// Defaults to `.discovered` when missing on the wire (a
    /// producer that forgets to set it never accidentally appears
    /// as `.operational`). Producers MUST set this explicitly;
    /// relying on the default is a bug.
    public let lifecycle: CartridgeLifecycle

    enum CodingKeys: String, CodingKey {
        case registryURL = "registry_url"
        case id
        case channel
        case version
        case sha256
        case capGroups = "cap_groups"
        case attachmentError = "attachment_error"
        case runtimeStats = "runtime_stats"
        case lifecycle
    }

    public init(
        registryURL: String?,
        id: String,
        channel: String,
        version: String,
        sha256: String,
        capGroups: [CapGroup] = [],
        attachmentError: CartridgeAttachmentError? = nil,
        runtimeStats: CartridgeRuntimeStats? = nil,
        lifecycle: CartridgeLifecycle = .discovered
    ) {
        self.registryURL = registryURL
        self.id = id
        self.channel = channel
        self.version = version
        self.sha256 = sha256
        self.capGroups = capGroups
        self.attachmentError = attachmentError
        self.runtimeStats = runtimeStats
        self.lifecycle = lifecycle
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
                        "InstalledCartridgeRecord is missing required `registry_url` field. "
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
        self.capGroups = try c.decodeIfPresent([CapGroup].self, forKey: .capGroups) ?? []
        self.attachmentError = try c.decodeIfPresent(CartridgeAttachmentError.self, forKey: .attachmentError)
        self.runtimeStats = try c.decodeIfPresent(CartridgeRuntimeStats.self, forKey: .runtimeStats)
        // Missing `lifecycle` defaults to `.discovered` rather
        // than `.operational` — the safe-default rule. A producer
        // that forgets to emit the field never accidentally
        // exposes an un-inspected cartridge for dispatch.
        self.lifecycle = try c.decodeIfPresent(CartridgeLifecycle.self, forKey: .lifecycle) ?? .discovered
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
        if !capGroups.isEmpty {
            try c.encode(capGroups, forKey: .capGroups)
        }
        try c.encodeIfPresent(attachmentError, forKey: .attachmentError)
        try c.encodeIfPresent(runtimeStats, forKey: .runtimeStats)
        try c.encode(lifecycle, forKey: .lifecycle)
    }

    /// Flat cap-URN view across this cartridge's groups, deduplicated
    /// while preserving the order in which urns first appear. Computed
    /// — never stored on the wire.
    public func capUrns() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for group in capGroups {
            for cap in group.caps {
                if seen.insert(cap.urn).inserted {
                    out.append(cap.urn)
                }
            }
        }
        return out
    }
}
