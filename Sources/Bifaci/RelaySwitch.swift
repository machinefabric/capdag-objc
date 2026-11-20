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
    /// The cartridge that would serve this request left its host's inventory
    /// and did not come back within the admission grace window. Distinct from
    /// `protocolError` because nothing violated the protocol — the deployment
    /// changed under a valid request, which is an `environment` failure, not an
    /// engine defect (docs/failure-taxonomy.md).
    case cartridgeUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .noHandler(let cap): return "No handler for cap: \(cap)"
        case .unknownRequest(let reqId): return "Unknown request ID: \(reqId)"
        case .protocolError(let msg): return "Protocol violation: \(msg)"
        case .allMastersUnhealthy: return "All relay masters are unhealthy"
        case .cartridgeUnavailable(let msg): return "Cartridge unavailable: \(msg)"
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

/// Composite routing key: (XID, RID) — uniquely identifies a request flow.
/// Alias onto the unified request table's key type (L7).
typealias RoutingKey = RequestKey

public struct RelayNotifyCapabilitiesPayload: Codable {
    public let installedCartridges: [InstalledCartridgeRecord]
    /// Host-level protocol observability (L8): drop counters, routing-table
    /// sizes, GC totals. Refreshed with each stats republish so the engine
    /// can surface the state of communications per host. Absent on initial
    /// capability advertisements — a per-republish refresh, not a requirement.
    public let hostProtocolStats: HostProtocolStats?

    enum CodingKeys: String, CodingKey {
        case installedCartridges = "installed_cartridges"
        case hostProtocolStats = "host_protocol_stats"
    }

    public init(installedCartridges: [InstalledCartridgeRecord]) {
        self.installedCartridges = installedCartridges
        self.hostProtocolStats = nil
    }

    public init(installedCartridges: [InstalledCartridgeRecord], hostProtocolStats: HostProtocolStats?) {
        self.installedCartridges = installedCartridges
        self.hostProtocolStats = hostProtocolStats
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.installedCartridges = try c.decode([InstalledCartridgeRecord].self, forKey: .installedCartridges)
        self.hostProtocolStats = try c.decodeIfPresent(HostProtocolStats.self, forKey: .hostProtocolStats)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(installedCartridges, forKey: .installedCartridges)
        // Omitted when nil, mirroring Rust's skip_serializing_if.
        try c.encodeIfPresent(hostProtocolStats, forKey: .hostProtocolStats)
    }

    /// Attach the host's protocol stats snapshot.
    public func withHostProtocolStats(_ stats: HostProtocolStats) -> RelayNotifyCapabilitiesPayload {
        return RelayNotifyCapabilitiesPayload(installedCartridges: installedCartridges, hostProtocolStats: stats)
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

/// The switch's protocol observability snapshot (L8): live request state,
/// recent terminations, and per-reason drop counters. Serializable; field
/// names are the mirror contract. Mirrors Rust `RelaySwitchProtocolStats`.
public struct RelaySwitchProtocolStats: Codable, Sendable {
    public let requests: RequestTableSnapshot
    public let drops: DropSnapshot
    /// Benign post-terminal stragglers — the expected teardown crossing,
    /// counted per frame type. Indicated separately from `drops` because
    /// nothing went wrong.
    public let stragglers: StragglerSnapshot
    /// Per-master host protocol stats, keyed by master id, as reported in
    /// each host's latest RelayNotify. A master that has not yet advertised
    /// host stats is absent (never a zeroed placeholder). Decodes to empty
    /// when absent, mirroring Rust's `serde(default)`.
    public let hosts: [String: HostProtocolStats]

    enum CodingKeys: String, CodingKey {
        case requests
        case drops
        case stragglers
        case hosts
    }

    public init(
        requests: RequestTableSnapshot,
        drops: DropSnapshot,
        stragglers: StragglerSnapshot = StragglerSnapshot(),
        hosts: [String: HostProtocolStats] = [:]
    ) {
        self.requests = requests
        self.drops = drops
        self.stragglers = stragglers
        self.hosts = hosts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.requests = try c.decode(RequestTableSnapshot.self, forKey: .requests)
        self.drops = try c.decode(DropSnapshot.self, forKey: .drops)
        self.stragglers = try c.decodeIfPresent(StragglerSnapshot.self, forKey: .stragglers) ?? StragglerSnapshot()
        self.hosts = try c.decodeIfPresent([String: HostProtocolStats].self, forKey: .hosts) ?? [:]
    }
}

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
    /// Host protocol stats carried by this master's latest RelayNotify
    /// (L8). `nil` until a RelayNotify advertises them — initial
    /// capability advertisements typically omit the field. Retained (not
    /// parsed-and-discarded) so `protocolStats().hosts` can surface them.
    var hostProtocolStats: HostProtocolStats?
    var healthy: Bool
    /// True once the slot's CONNECTION is gone — its reader exited
    /// (EOF/error) or `handleMasterDeath` declared it dead — and false
    /// while a socket is attached, healthy or not. Attachment is decided
    /// by this, never by `healthy`: a slot with its identity probe
    /// pending is unhealthy yet attached, and reattaching over it would
    /// strand the host on the other end. Mirrors the Rust reference,
    /// which decides by the reader task's liveness. Guarded by the
    /// switch lock.
    var detached: Bool = false
    /// Last error message (if unhealthy). Mirrors Rust
    /// `MasterConnection.last_error`. Populated when an identity
    /// probe (synchronous in `addMaster`, or the deferred runtime
    /// probe) fails, or when the master dies; cleared when a
    /// deferred probe later passes and the master flips healthy.
    var lastError: String?
    /// The identity probe this master's health waits on, while one is
    /// open. Only its answer settles the master; the answer of a probe it
    /// replaced (a reattach, a later probe) is ignored. Guarded by the
    /// switch lock.
    var identityProbe: RoutingKey?

    init(id: String, socketWriter: FrameWriter, seqAssigner: SeqAssigner, reorderBuffer: ReorderBuffer? = nil, manifest: Data, limits: Limits, caps: [String], installedCartridges: [InstalledCartridgeRecord], hostProtocolStats: HostProtocolStats? = nil, healthy: Bool, lastError: String? = nil, identityProbe: RoutingKey? = nil) {
        self.id = id
        self.socketWriter = socketWriter
        self.seqAssigner = seqAssigner
        self.manifest = manifest
        self.limits = limits
        self.caps = caps
        self.installedCartridges = installedCartridges
        self.hostProtocolStats = hostProtocolStats
        self.healthy = healthy
        self.lastError = lastError
        self.identityProbe = identityProbe
        self.reorderBuffer = reorderBuffer ?? ReorderBuffer(maxBufferPerFlow: limits.maxReorderBuffer)
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

// MARK: - Identity probes

/// How long an identity probe may go unanswered before its master is
/// reported overdue. Starting the cartridge that answers identity is part
/// of the round trip, and a cold start can outlast any fixed bound, so the
/// window does not end the probe: past it the master is reported overdue,
/// stays unverified, and the answer, whenever it comes, settles it. Mirrors
/// Rust `IDENTITY_PROBE_WINDOW`.
public let IDENTITY_PROBE_WINDOW: TimeInterval = 30.0

/// An identity probe the switch has sent and whose answer it waits for.
/// Its answer is delivered on `channel` by the master's reader.
private final class OpenIdentityProbe: @unchecked Sendable {
    let masterIdx: Int
    let key: RoutingKey
    let channel: ResponseChannel
    let nonce: Data
    /// The echo received so far.
    var echoed: Data
    let sentAt: Date
    let window: TimeInterval
    /// Whether the master has been reported overdue.
    var overdue: Bool

    init(masterIdx: Int, key: RoutingKey, channel: ResponseChannel, nonce: Data, echoed: Data, sentAt: Date, window: TimeInterval, overdue: Bool) {
        self.masterIdx = masterIdx
        self.key = key
        self.channel = channel
        self.nonce = nonce
        self.echoed = echoed
        self.sentAt = sentAt
        self.window = window
        self.overdue = overdue
    }
}

/// A job for the identity-probe driver.
private enum IdentityProbeJob {
    /// Probe this master through the switch (its advertised caps went from
    /// empty to non-empty).
    case probe(Int)
    /// Wait for the answer to a probe already sent: `addMaster`'s, left
    /// unanswered when its window ended.
    case await(OpenIdentityProbe)
}

/// Where a master's reader puts what it reads until `addMaster` has
/// committed the master's slot (`diverting`), instead of handling it.
/// `addMaster` waits on its identity probe through this rather than reading
/// the socket itself, so the reader is the only reader of the socket and the
/// wait can end at its window without a read part-way through a frame. Each
/// read is a frame, EOF (`frame` and `error` both nil), or the error that
/// ended the connection.
private final class ReaderDiversion: @unchecked Sendable {
    let cond = NSCondition()
    var diverting = true
    var pending: [(frame: Frame?, error: Error?)] = []

    /// The oldest read not yet handled, waiting until `deadline` for one;
    /// nil when none came.
    func pop(until deadline: Date) -> (frame: Frame?, error: Error?)? {
        cond.lock()
        defer { cond.unlock() }
        while pending.isEmpty {
            if !cond.wait(until: deadline) { break }
        }
        return pending.isEmpty ? nil : pending.removeFirst()
    }
}

/// What one frame of an identity probe's answer does to the probe: the
/// answer is STREAM_START, CHUNK(nonce)…, STREAM_END, END, or an ERR.
/// Returns `done == false` while the answer is still coming; done with no
/// failure when it verified the probe.
private func identityAnswerStep(_ frame: Frame, nonce: Data, echoed: inout Data) -> (done: Bool, failure: String?) {
    switch frame.frameType {
    case .streamStart, .streamEnd:
        return (false, nil)
    case .chunk:
        if let payload = frame.payload {
            echoed.append(payload)
        }
        return (false, nil)
    case .end:
        if echoed != nonce {
            return (true, "identity payload mismatch (expected \(nonce.count) bytes, got \(echoed.count))")
        }
        return (true, nil)
    case .err:
        guard let code = frame.errorCode, !code.isEmpty else {
            return (true, "identity failed: ERR frame missing required text code")
        }
        guard let msg = frame.errorMessage, !msg.isEmpty else {
            return (true, "identity failed: ERR frame missing required text message")
        }
        return (true, "identity failed: [\(code)] \(msg)")
    case .log, .credit, .heartbeat:
        // Control/side-channel frames are legal ANYWHERE during the probe
        // (spec 12.4: LOG interleaves without affecting data flow;
        // CREDIT/HEARTBEAT are the control plane the writer gate itself
        // exempts, L4). A cartridge crediting its probe input as it
        // consumes (L10) must not fail identity verification.
        return (false, nil)
    default:
        return (true, "identity: unexpected frame type \(frame.frameType)")
    }
}

/// What a master still waiting on its identity probe reports.
private func identityProbeOverdueMessage(_ masterIdx: Int, _ window: TimeInterval) -> String {
    return "master \(masterIdx): identity probe unanswered after \(window)s — the master stays unverified until the host answers it " +
        "(the cartridge answering identity is still starting, or the probe or its answer was lost on the way)"
}

/// An identity probe's REQ and body — STREAM_START, CHUNK(nonce),
/// STREAM_END, END — on the flow (xid, rid). Seq is the writer's to assign.
private func identityProbeFrames(rid: MessageId, xid: MessageId, nonce: Data, streamId: String) -> [Frame] {
    var frames = [
        Frame.req(id: rid, capUrn: CSCapIdentity as String, payload: Data(), contentType: "application/cbor"),
        Frame.streamStart(reqId: rid, streamId: streamId, mediaUrn: "media:"),
        Frame.chunk(reqId: rid, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: Frame.computeChecksum(nonce)),
        Frame.streamEnd(reqId: rid, streamId: streamId, chunkCount: 1),
        Frame.end(id: rid),
    ]
    for i in frames.indices {
        frames[i].routingId = xid
    }
    return frames
}

// MARK: - Relay Switch

/// Cap-aware routing multiplexer for multiple RelayMasters.
///
/// Routes requests based on cap URN matching and tracks bidirectional request/response flows.
/// Uses XID (routing ID) presence to distinguish response direction from request direction.
@available(macOS 10.15.4, iOS 13.4, *)
public final class RelaySwitch: @unchecked Sendable {
    private var masters: [MasterConnection] = []
    /// Switch-side pool-chain admission (see Pools.swift): a dispatch is
    /// held against its cap's whole pool chain; a bounded pool limits how
    /// many requests the switch dispatches through it at a time. Mirrors
    /// the reference `RelaySwitch.admission`.
    internal let admission = AdmissionController()
    private var capTable: [(capUrn: String, masterIdx: Int)] = []

    /// Unified per-request state (L7): routing, origin, peer markers,
    /// cancel-cascade children, external response channel, per-stream flow
    /// stats, and the rid→xid index — one entry, one registration, one
    /// termination. Replaces the four parallel routing maps. Protected by
    /// `lock` (the table itself is unsynchronized, mirroring Rust's
    /// `RwLock<RequestTable>`).
    let requests = RequestTable()
    /// Dropped-frame accounting (L8): unroutable/post-terminal frames are
    /// counted drops, never silent losses and never protocol errors.
    let drops = DropCounters()
    /// Benign post-terminal stragglers — the expected teardown race,
    /// counted per frame type, never drops (nothing went wrong).
    let stragglers = StragglerCounters()
    /// XID counter for assigning unique routing IDs
    private var xidCounter: UInt64 = 0

    private var aggregateCapabilities: Data = Data()
    private var aggregateInstalledCartridges: [InstalledCartridgeRecord] = []
    private var negotiatedLimits: Limits = Limits()

    /// The destination master's negotiated initial credit — the ledger seed
    /// for requests routed to it (`RequestState.initialCredit`). When the
    /// slot has already detached (a resolve/attach race — the registration
    /// that follows will fail on delivery), the switch-level negotiated
    /// minimum is the correct window bound. Caller holds the switch lock.
    private func masterInitialCredit(_ destIdx: Int) -> UInt64 {
        guard masters.indices.contains(destIdx) else {
            return negotiatedLimits.initialCredit
        }
        return masters[destIdx].limits.initialCredit
    }
    private let lock = NSLock()
    /// One item of the switch's inbound stream.
    private enum Inbound {
        /// A frame from a master, or the end of its connection.
        case master(masterIdx: Int, frame: Frame?, error: Error?)
        /// Bringing the provider of held peer request `rid` ended.
        case settled(rid: MessageId, settlement: PeerSettlement)
    }
    /// The switch's inbound stream: frames from the master reader threads,
    /// and the end of bringing a held peer request's provider — one stream,
    /// handled in order, so a held request's replay is ordered with every
    /// frame its caller sends after.
    private var frameChannel: [Inbound] = []
    private let frameSemaphore = DispatchSemaphore(value: 0)

    /// What brings a provider for a peer request no master serves, and the
    /// requests held while it does (`setPeerProvider`). Nil: such a request is
    /// refused with NO_HANDLER. Guarded by `lock`.
    private var peerProviding: (provider: PeerProvider, holds: PeerHoldTable)?

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

    /// What the engine allows the cartridges behind this switch to do (12.2
    /// §Policy). Given at construction, so no master is ever connected without
    /// one; sent to each master before anything else, and to every master on
    /// each change (`setPolicy`). Guarded by `addMasterLock`, so a change
    /// cannot fall between a new master's send and its joining.
    private var policy: HostPolicy

    /// Shutdown flag — when true, reader threads and the probe driver exit.
    ///
    /// Deliberately NOT guarded by `lock`, and read/written through its own
    /// tiny lock instead. The reference stores this as an `AtomicBool`
    /// (`background_pump_stop`) for exactly one reason: `Drop` must be able to
    /// signal shutdown WITHOUT acquiring the switch mutex. Guarding it with
    /// `lock` made `deinit` take that mutex, so a deallocation racing anything
    /// that holds it deadlocks the deallocating thread — which is precisely the
    /// hang this suite showed (`RelaySwitch.deinit` parked in
    /// `__psynch_mutexwait` while every other thread sat in `read()`).
    ///
    /// A dedicated lock rather than an atomic keeps the change dependency-free;
    /// what matters is that it is a DIFFERENT lock from `lock`, so setting the
    /// flag can never contend with the switch's own critical sections.
    private let shutdownLock = NSLock()
    private var shutdownFlag = false

    /// The shutdown flag. Safe to read and write from any thread, including
    /// `deinit`, without holding `lock`.
    private var isShutdown: Bool {
        get {
            shutdownLock.lock()
            defer { shutdownLock.unlock() }
            return shutdownFlag
        }
        set {
            shutdownLock.lock()
            defer { shutdownLock.unlock() }
            shutdownFlag = newValue
        }
    }

    /// Response channels for open identity probes, keyed by the probe's
    /// (xid, rid), with the master each probes. The master reader thread
    /// diverts a frame whose (xid, rid) matches a registered channel here
    /// instead of enqueueing it for the engine — the mechanism that lets
    /// the probe driver await the host's nonce echo end-to-end — and when
    /// the master's connection ends, it ends the master's probes with a
    /// MASTER_DIED ERR. Mirrors Rust's request-table response channels.
    private var externalResponseChannels: [RoutingKey: (masterIdx: Int, channel: ResponseChannel)] = [:]

    /// Queue of identity-probe jobs: masters whose advertised cap set
    /// transitioned from empty to non-empty, and `addMaster` probes left
    /// unanswered at the end of their window. The probe driver thread runs
    /// each, gating cap-table publication on its answer. Mirrors Rust's
    /// `pending_identity_probes` channel.
    private var pendingIdentityProbes: [IdentityProbeJob] = []
    /// How long an identity probe may go unanswered before its master is
    /// reported overdue (`IDENTITY_PROBE_WINDOW`). The probe stays open
    /// after it. Guarded by `lock`.
    private var identityProbeWindow: TimeInterval = IDENTITY_PROBE_WINDOW
    /// Wakes the probe driver when a job is queued (or on shutdown).
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
    public init(sockets: [SocketPair], policy: HostPolicy) throws {
        self.policy = policy
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

            // The policy goes first, before the identity probe or anything
            // routed: the host gives it to each cartridge it connects.
            try socketWriter.write(Frame.policy(policy))

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
                    case .log, .credit, .heartbeat:
                        // Control/side-channel frames are legal ANYWHERE during the
                        // probe (spec 12.4: LOG interleaves without affecting data
                        // flow; CREDIT/HEARTBEAT are the control plane the writer
                        // gate itself exempts, L4). A cartridge crediting its
                        // probe input as it consumes (L10) must not fail identity
                        // verification.
                        break
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
                hostProtocolStats: notifyPayload.hostProtocolStats,
                healthy: true
            )
            masters.append(masterConn)
            // Seed admission from this master's inventory, so the very first
            // dispatch is gated exactly like every later one.
            try configureMasterAdmissionLocked(masters.count - 1, masterConn.installedCartridges)
        }

        // Phase 2: All masters verified — spawn reader threads
        for (masterIdx, reader) in pendingReaders {
            let diversion = ReaderDiversion()
            diversion.diverting = false
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.readerLoop(masterIdx: masterIdx, reader: reader, diversion: diversion)
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
        // The flag has its own lock, so signalling shutdown never waits on the
        // switch mutex — a caller must be able to stop a switch whose critical
        // sections are busy.
        isShutdown = true

        // Signal semaphores to wake any waiting readers and the probe driver
        frameSemaphore.signal()
        probeSemaphore.signal()
    }

    /// deinit signals shutdown — WITHOUT taking `lock`.
    ///
    /// Mirrors the reference's `Drop`, which stores into an `AtomicBool` and
    /// touches no mutex. Taking `lock` here meant deallocation could block on
    /// the switch's own critical sections, and a deallocation that blocks
    /// blocks the thread that happened to release the last reference — which
    /// is how this became a whole-suite hang with `deinit` parked in
    /// `__psynch_mutexwait`.
    deinit {
        isShutdown = true
        frameSemaphore.signal()
        probeSemaphore.signal()
    }

    // MARK: - Reader Loop

    /// Read a master's socket until its connection ends. Every read goes to
    /// `addMaster` while the diversion holds it, then is handled.
    private func readerLoop(masterIdx: Int, reader: FrameReader, diversion: ReaderDiversion) {
        var mutableReader = reader
        while true {
            // Check shutdown flag before reading
            if isShutdown { return }

            var frame: Frame? = nil
            var readError: Error? = nil
            do {
                frame = try mutableReader.read()
            } catch {
                readError = error
            }

            // Check shutdown after read
            if isShutdown { return }

            diversion.cond.lock()
            let diverted = diversion.diverting
            if diverted {
                diversion.pending.append((frame: frame, error: readError))
                diversion.cond.broadcast()
            }
            diversion.cond.unlock()

            if diverted {
                if frame == nil { return }
            } else if !handleMasterRead(masterIdx: masterIdx, frame: frame, error: readError) {
                return
            }
        }
    }

    /// Handle one read of a master's socket: a frame, EOF (`frame` and
    /// `error` both nil), or the error that ended the connection. Returns
    /// whether the connection goes on.
    private func handleMasterRead(masterIdx: Int, frame: Frame?, error: Error?) -> Bool {
        guard let frame = frame, error == nil else {
            // The connection is gone. The slot is detached from this moment,
            // whether or not the pump has processed the end yet, so a
            // reattach for this id is legitimate; and the master's open
            // identity probes end, as a death ends its other requests.
            if isShutdown { return false }
            lock.lock()
            if masterIdx < masters.count {
                masters[masterIdx].detached = true
            }
            endIdentityProbesLocked(ofMaster: masterIdx)
            lock.unlock()
            enqueueFrame(masterIdx: masterIdx, frame: nil, error: error)
            return false
        }

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
                // the lock held.
                do {
                    try applyRelayNotifyUpdate(sourceIdx: masterIdx, manifest: manifest, newLimits: limits)
                } catch {
                    fputs("[RelaySwitch] master \(masterIdx): RelayNotify update failed: \(error)\n", stderr)
                }
            }
            lock.unlock()
            return true
        }

        // Pass through reorder buffer
        lock.lock()
        let reorderBuffer = isShutdown ? nil : masters[masterIdx].reorderBuffer
        lock.unlock()

        guard let buffer = reorderBuffer else { return false }

        let readyFrames: [Frame]
        do {
            readyFrames = try buffer.accept(frame)
        } catch {
            return handleMasterRead(masterIdx: masterIdx, frame: nil, error: error)
        }

        for readyFrame in readyFrames {
            if readyFrame.frameType.isTerminal {
                let key = FlowKey.fromFrame(readyFrame)
                buffer.cleanupFlow(key)
            }

            // Divert frames belonging to an open identity probe to that
            // probe's response channel instead of surfacing them to the
            // engine. The probe registered the channel keyed by its
            // (xid, rid); the host echoes the nonce on that same flow.
            if let xid = readyFrame.routingId {
                let probeKey = RoutingKey(xid: xid, rid: readyFrame.id)
                lock.lock()
                let channel = externalResponseChannels[probeKey]?.channel
                lock.unlock()
                if let channel = channel {
                    channel.deliver(readyFrame)
                    continue
                }
            }

            enqueueFrame(masterIdx: masterIdx, frame: readyFrame, error: nil)
        }
        return true
    }

    /// End the open identity probes of a master whose connection is gone:
    /// each gets the MASTER_DIED ERR a death gives every request to the
    /// master, and its request ends. Caller holds `lock`.
    private func endIdentityProbesLocked(ofMaster masterIdx: Int) {
        for (key, entry) in externalResponseChannels where entry.masterIdx == masterIdx {
            externalResponseChannels.removeValue(forKey: key)
            requests.terminate(key, kind: .masterDied)
            var errFrame = Frame.err(
                id: key.rid,
                code: "MASTER_DIED",
                attributionClass: .environment,
                message: "Relay master \(masterIdx) connection closed"
            )
            errFrame.routingId = key.xid
            entry.channel.deliver(errFrame)
        }
    }

    private func enqueueFrame(masterIdx: Int, frame: Frame?, error: Error?) {
        enqueue(.master(masterIdx: masterIdx, frame: frame, error: error))
    }

    private func enqueue(_ item: Inbound) {
        lock.lock()
        frameChannel.append(item)
        lock.unlock()
        frameSemaphore.signal()
    }

    // MARK: - Frame Output

    /// Write a frame to a master, assigning seq via the per-master SeqAssigner.
    /// Cleans up seq tracking on terminal frames (END/ERR).
    private func writeToMasterIdx(_ masterIdx: Int, _ frame: inout Frame) throws {
        // Checked, not subscripted. A routing decision and the write that acts
        // on it are not atomic — a master can detach in between — and the
        // reference returns `Protocol("selected master index N no longer
        // exists")` for exactly that. Subscripting instead TRAPS, taking the
        // whole process down (`Fatal error: Index out of range`) on a race the
        // contract says to report.
        guard masters.indices.contains(masterIdx) else {
            throw RelaySwitchError.protocolError(
                "selected master index \(masterIdx) no longer exists"
            )
        }
        let master = masters[masterIdx]
        master.seqAssigner.assign(&frame)
        try master.socketWriter.write(frame)
        if frame.frameType.isTerminal {
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
    /// The policy in force (12.2 §Policy).
    public var currentPolicy: HostPolicy {
        addMasterLock.lock()
        defer { addMasterLock.unlock() }
        return policy
    }

    /// Replace the policy and send it to every attached master, whose hosts
    /// pass it to their cartridges (12.2 §Policy). Setting the policy in force
    /// sends nothing. A master that is not attached is given the current
    /// policy when it attaches; the masters a send failed on are thrown.
    public func setPolicy(_ newPolicy: HostPolicy) throws {
        addMasterLock.lock()
        defer { addMasterLock.unlock() }
        guard newPolicy != policy else { return }
        policy = newPolicy
        lock.lock()
        let attached = masters.enumerated().filter { !$0.element.detached }
        lock.unlock()
        var failures: [String] = []
        for (idx, master) in attached {
            do {
                try master.socketWriter.write(Frame.policy(newPolicy))
            } catch {
                failures.append("master \(idx): \(error)")
            }
        }
        if !failures.isEmpty {
            throw RelaySwitchError.protocolError(
                "the policy '\(newPolicy.network.asString)' did not reach every master: \(failures.joined(separator: "; "))"
            )
        }
    }

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
                if !m.detached {
                    let state = m.healthy ? "healthy" : "attached but unhealthy"
                    lock.unlock()
                    throw RelaySwitchError.protocolError(
                        "addMaster: id '\(socket.id)' is already attached to a \(state) slot at index \(idx) — " +
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

        // The current policy goes first, before the identity probe or
        // anything routed. `setPolicy` holds `addMasterLock`, which this call
        // holds.
        try socketWriter.write(Frame.policy(policy))

        let seqAssigner = SeqAssigner()
        // The master's inbound reorder buffer is in use from the first frame
        // the probe reads, so a probe answer half-read here and finished
        // after the slot joins is one flow to it.
        let reorderBuffer = ReorderBuffer(maxBufferPerFlow: masterLimits.maxReorderBuffer)

        // The master's reader starts now and is the only reader of its
        // socket from here on. Until the slot is committed below, the reader
        // hands what it reads to this call instead of handling it: to the
        // identity probe while it waits, and in any case so a capless
        // master's immediate empty→non-empty RelayNotify is not handled
        // before the slot exists (its runtime probe would never run).
        let diversion = ReaderDiversion()
        let boundIdx = masterIdx
        let boundReader = socketReader
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readerLoop(masterIdx: boundIdx, reader: boundReader, diversion: diversion)
        }

        // End-to-end identity verification. Only meaningful when the host
        // advertises at least one cap — otherwise there is no cartridge
        // chain to echo the nonce. The master still joins so its
        // `installed_cartridges` attachment errors reach the engine.
        //
        // Unlike `init`, a probe FAILURE here does NOT abort registration:
        // the master is registered UNHEALTHY with `lastError` set, so its
        // installed_cartridges remain visible to the inventory aggregate
        // while its caps are held back from routing (cap_table skips
        // unhealthy masters). Mirrors Rust `add_master`.
        //
        // Starting the cartridge that answers identity is part of the round
        // trip, and its cold start has no fixed bound, so the wait here is
        // bounded by the probe window and the master joins when it ends,
        // answered or not. A probe unanswered at the end of its window is
        // not a failure: the master joins unverified and reported overdue,
        // the probe stays open, and its answer, whenever it comes, verifies
        // the master (the probe driver waits for it).
        lock.lock()
        let window = identityProbeWindow
        lock.unlock()
        var identityFailure: String? = nil
        var openProbe: OpenIdentityProbe? = nil
        if !caps.isEmpty {
            lock.lock()
            xidCounter += 1
            let xid = MessageId.uint(xidCounter)
            lock.unlock()

            let nonce = identityNonce()
            let reqId = MessageId.newUUID()
            let sentAt = Date()
            var failure: String? = nil
            do {
                for var frame in identityProbeFrames(rid: reqId, xid: xid, nonce: nonce, streamId: "identity-verify") {
                    seqAssigner.assign(&frame)
                    try socketWriter.write(frame)
                }
                seqAssigner.remove(FlowKey(rid: reqId, xid: xid))
            } catch {
                failure = "identity send failed: \(error)"
            }

            var echoed = Data()
            var answered = failure != nil
            let deadline = sentAt.addingTimeInterval(window)
            probeLoop: while !answered {
                guard let read = diversion.pop(until: deadline) else { break }
                if let error = read.error {
                    failure = "identity read failed: \(error)"
                    break
                }
                guard let frame = read.frame else {
                    failure = "closed during identity verification"
                    break
                }
                if frame.frameType == .relayNotify {
                    if let manifest = frame.relayNotifyManifest {
                        do {
                            notifyPayload = try Self.parseRelayNotifyPayload(manifest)
                        } catch {
                            failure = "RelayNotify reparse failed: \(error)"
                            break probeLoop
                        }
                        capsPayload = manifest
                        caps = notifyPayload.capUrns()
                    }
                    if let newLimits = frame.relayNotifyLimits {
                        masterLimits = newLimits
                    }
                    continue
                }
                let readyFrames: [Frame]
                do {
                    readyFrames = try reorderBuffer.accept(frame)
                } catch {
                    failure = "identity read failed: \(error)"
                    break
                }
                for readyFrame in readyFrames {
                    if readyFrame.frameType.isTerminal {
                        reorderBuffer.cleanupFlow(FlowKey.fromFrame(readyFrame))
                    }
                    let step = identityAnswerStep(readyFrame, nonce: nonce, echoed: &echoed)
                    if step.done {
                        answered = true
                        failure = step.failure
                        break
                    }
                }
            }

            let elapsedMs = Int(Date().timeIntervalSince(sentAt) * 1000)
            if let failure = failure {
                identityFailure = "new master \(masterIdx): \(failure) (after \(elapsedMs) ms)"
                fputs("[RelaySwitch] addMaster: identity verification FAILED for master \(masterIdx) — registering unhealthy so installed_cartridges stay visible: \(identityFailure!)\n", stderr)
            } else if !answered {
                identityFailure = identityProbeOverdueMessage(masterIdx, window)
                fputs("[RelaySwitch] addMaster: \(identityFailure!) — registering it unverified; the probe stays open\n", stderr)
                openProbe = OpenIdentityProbe(
                    masterIdx: masterIdx,
                    key: RoutingKey(xid: xid, rid: reqId),
                    channel: ResponseChannel(),
                    nonce: nonce,
                    echoed: echoed,
                    sentAt: sentAt,
                    window: window,
                    overdue: true
                )
            }
        }
        let healthyAtRegister = identityFailure == nil

        // Commit the connection state into the slot.
        // `defer`, not hand-paired unlocks: this region contains throwing calls
        // (`configureMasterAdmissionLocked` rejects a cartridge record missing
        // mandatory runtime_stats), and an error unwinds straight past a
        // trailing `lock.unlock()`. Rust holds a `MutexGuard` here, which
        // releases on every exit including the error path; hand-pairing lost
        // that property in translation and turned one legitimate registration
        // error into a permanently held switch lock — after which every
        // acquirer blocks forever, `deinit` included.
        lock.lock()
        var registrationDone = false
        defer { if !registrationDone { lock.unlock() } }
        // An unanswered probe's answer will come through the reader: its
        // channel and request are registered before the reader stops handing
        // reads to this call, so no part of the answer misses them.
        if let probe = openProbe {
            let probeState = RequestState(
                routing: RoutingEntry(sourceMasterIdx: nil, destinationMasterIdx: masterIdx),
                origin: nil,
                externalChannel: nil,
                isPeer: false,
                initialCredit: masterLimits.initialCredit
            )
            probeState.capUrn = CSCapIdentity as String
            try requests.register(probe.key, probeState)
            externalResponseChannels[probe.key] = (masterIdx: masterIdx, channel: probe.channel)
        }
        if existingIdx == nil {
            // Append. The captured `masterIdx` MUST equal the new
            // length; if not, a concurrent appender bypassed
            // `addMasterLock`, which is a protocol violation.
            if masters.count != masterIdx {
                throw RelaySwitchError.protocolError(
                    "addMaster: append-index race for id '\(socket.id)': reserved \(masterIdx) but masters.count is now \(masters.count) " +
                    "(a concurrent caller bypassed addMasterLock)"
                )
            }
            let masterConn = MasterConnection(
                id: socket.id,
                socketWriter: socketWriter,
                seqAssigner: seqAssigner,
                reorderBuffer: reorderBuffer,
                manifest: capsPayload,
                limits: masterLimits,
                caps: caps,
                installedCartridges: notifyPayload.installedCartridges,
                hostProtocolStats: notifyPayload.hostProtocolStats,
                healthy: healthyAtRegister,
                lastError: identityFailure,
                identityProbe: openProbe?.key
            )
            masters.append(masterConn)
            // Seed admission from this master's inventory, so the very first
            // dispatch is gated exactly like every later one.
            try configureMasterAdmissionLocked(masters.count - 1, masterConn.installedCartridges)
        } else {
            let slot = masters[masterIdx]
            if slot.id != socket.id {
                throw RelaySwitchError.protocolError(
                    "addMaster: reattach-id mismatch at index \(masterIdx): expected '\(socket.id)' but found '\(slot.id)'"
                )
            }
            // In-place mutation. The dead master's reader thread
            // has already exited on EOF (Swift threads aren't
            // cancellable; we rely on the natural EOF exit).
            slot.socketWriter = socketWriter
            slot.seqAssigner = seqAssigner
            slot.reorderBuffer = reorderBuffer
            slot.manifest = capsPayload
            slot.limits = masterLimits
            slot.caps = caps
            slot.installedCartridges = notifyPayload.installedCartridges
            slot.hostProtocolStats = notifyPayload.hostProtocolStats
            slot.healthy = healthyAtRegister
            slot.lastError = identityFailure
            slot.identityProbe = openProbe?.key
            slot.detached = false
            try configureMasterAdmissionLocked(masterIdx, notifyPayload.installedCartridges)
        }

        // Rebuild tables
        rebuildCapTable()
        rebuildCapabilities()
        rebuildLimits()
        registrationDone = true
        lock.unlock()

        // The slot is in place: the reader handles its reads from now on,
        // after what this call left unread — under the diversion's lock, so
        // no later read overtakes them.
        diversion.cond.lock()
        diversion.diverting = false
        let leftovers = diversion.pending
        diversion.pending = []
        for read in leftovers {
            _ = handleMasterRead(masterIdx: masterIdx, frame: read.frame, error: read.error)
        }
        diversion.cond.unlock()

        if let probe = openProbe {
            // The probe driver waits for the answer.
            lock.lock()
            pendingIdentityProbes.append(.await(probe))
            ensureProbeDriverStarted()
            lock.unlock()
            probeSemaphore.signal()
        }

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

    /// Whether `addMaster(id)` is legitimate RIGHT NOW: no slot carries
    /// this id, or the slot's connection is gone. A host that reconnects
    /// on every control-plane event must ask this BEFORE dialling —
    /// `addMaster` can only learn the answer after consuming a fresh
    /// socket, and a socket dialled into an attached slot is a duplicate
    /// connection the host side has to refuse. A slot that is merely
    /// UNHEALTHY (identity probe pending or failed) with its socket open
    /// is still attached. Mirrors Rust `slot_accepts_attach`.
    public func slotAcceptsAttach(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = masters.first(where: { $0.id == id }) else { return true }
        return slot.detached
    }

    /// Test seam (internal): force a slot's health flag, to stage the
    /// "unhealthy but attached" state (a pending identity probe) without
    /// driving a RelayNotify transition. Mirrors the reference tests'
    /// direct store into `masters[idx].healthy`.
    internal func setMasterHealthyForTest(_ idx: Int, _ healthy: Bool) {
        lock.lock()
        defer { lock.unlock() }
        masters[idx].healthy = healthy
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
    /// Stable admission identity for one installed cartridge behind one master.
    /// Mirrors the reference `RelaySwitch::admission_key`.
    internal static func admissionKey(
        masterIdx: Int,
        record: InstalledCartridgeRecord
    ) -> AdmissionKey {
        AdmissionKey(
            masterIdx: masterIdx,
            registryURL: record.registryURL,
            channel: record.channel,
            id: record.id,
            version: record.version,
            sha256: record.sha256
        )
    }

    /// Refresh every admission slot this master advertises and mark the rest of
    /// its slots unavailable. Caller must hold `lock`. Mirrors
    /// `configure_master_admission`.
    internal func configureMasterAdmissionLocked(
        _ masterIdx: Int,
        _ cartridges: [InstalledCartridgeRecord]
    ) throws {
        var available = Set<AdmissionKey>()
        for record in cartridges {
            guard let stats = record.runtimeStats else {
                throw RelaySwitchError.protocolError(
                    "cartridge '\(record.id)' on master \(masterIdx) is missing mandatory runtime_stats"
                )
            }
            let key = Self.admissionKey(masterIdx: masterIdx, record: record)
            // A host may expose several process instances of the same logical
            // install. They share one admission identity: preserve the first
            // host-ordered record, matching host dispatch.
            if available.insert(key).inserted {
                admission.configurePools(
                    key, pools: try Self.poolCapacities(stats, cartridgeId: record.id))
            }
        }
        admission.reconcileMaster(masterIdx, available: available)
    }

    /// One record's advertised pool map as the admission controller's
    /// EFFECTIVE capacities. A NOT-RUNNING record's `all` pool is clamped
    /// to 1 — the cold-start canary: the first dispatch to a cold cartridge
    /// is a single body that proves the spawn before the advertised
    /// capacities apply (failure containment, not missing information). An
    /// EMPTY pool map on an operational record is a protocol error, never a
    /// free pass. (matches Rust pool_capacities)
    internal static func poolCapacities(
        _ stats: CartridgeRuntimeStats, cartridgeId: String
    ) throws -> [String: UInt64] {
        guard !stats.pools.isEmpty else {
            if stats.running {
                throw RelaySwitchError.protocolError(
                    "cartridge '\(cartridgeId)' is running but advertises no concurrency pools — the pool map is mandatory once HELLO has completed"
                )
            }
            // A cold record before its first HELLO legitimately has no pool
            // map yet (registered-dir cartridges spawn on first dispatch).
            // Admit through the canary alone: `all` clamped to 1, so the
            // first body proves the spawn before real capacities exist.
            return [poolAll: 1]
        }
        var capacities: [String: UInt64] = [:]
        for (name, state) in stats.pools {
            capacities[name] = advertisedCapacity(running: stats.running, pool: name, state: state)
        }
        return capacities
    }

    /// The cap's pool CHAIN over one record's advertised pool map — each
    /// admission domain paired with its effective capacity (0 = unlimited,
    /// with the not-running canary clamp on `all`). A cap the pool map does
    /// not cover is a protocol error, never a free pass. (matches Rust
    /// admission_chain)
    internal static func admissionChain(
        install: AdmissionKey,
        stats: CartridgeRuntimeStats,
        registeredCap: String,
        cartridgeId: String
    ) throws -> [(key: PoolKey, capacity: UInt64)] {
        if stats.pools.isEmpty {
            if stats.running {
                throw RelaySwitchError.protocolError(
                    "cartridge '\(cartridgeId)' is running but advertises no concurrency pools — the pool map is mandatory once HELLO has completed"
                )
            }
            // Cold record before its first HELLO: the whole dispatch is the
            // canary — one body through the clamped `all` pool, which is
            // what triggers the spawn and the real pool map.
            return [(PoolKey(install: install, pool: poolAll), 1)]
        }
        let canonical: String
        do {
            canonical = try CSCapUrn.fromString(registeredCap).toString()
        } catch {
            throw RelaySwitchError.protocolError(
                "registered cap '\(registeredCap)' is not a valid cap URN: \(error)")
        }
        let names: [String]
        do {
            names = try chainFromStates(stats.pools, cap: canonical)
        } catch {
            throw RelaySwitchError.protocolError(
                "cartridge '\(cartridgeId)' advertises cap '\(canonical)' with no pool coverage — \(error)"
            )
        }
        // The cold-start canary included — see poolCapacities.
        return names.map { name in
            (
                PoolKey(install: install, pool: name),
                advertisedCapacity(running: stats.running, pool: name, state: stats.pools[name]!)
            )
        }
    }

    /// The cap's admission CHAIN — each (install, pool) permit domain a
    /// dispatch is held against, in order (singleton, declared pools,
    /// `all`), paired with per-pool effective capacities — on this master.
    /// Caller must hold `lock`. Mirrors `cap_admission_target`.
    internal func capAdmissionTargetLocked(
        _ masterIdx: Int,
        _ registeredCap: String
    ) throws -> [(key: PoolKey, capacity: UInt64)] {
        guard masterIdx >= 0, masterIdx < masters.count else {
            throw RelaySwitchError.protocolError(
                "selected master index \(masterIdx) no longer exists")
        }
        var owner: InstalledCartridgeRecord?
        var ownerKey: AdmissionKey?
        for record in masters[masterIdx].installedCartridges {
            if record.attachmentError != nil { continue }
            guard record.capUrns().contains(registeredCap) else { continue }
            let key = Self.admissionKey(masterIdx: masterIdx, record: record)
            if owner == nil {
                owner = record
                ownerKey = key
                continue
            }
            if key != ownerKey {
                throw RelaySwitchError.protocolError(
                    "master \(masterIdx) has multiple distinct installed cartridges claiming "
                        + "cap '\(registeredCap)'; routing is ambiguous")
            }
        }
        guard let cartridge = owner, let key = ownerKey else {
            throw RelaySwitchError.protocolError(
                "master \(masterIdx) advertises cap '\(registeredCap)' without an "
                    + "installed-cartridge owner")
        }
        guard let stats = cartridge.runtimeStats else {
            throw RelaySwitchError.protocolError(
                "cartridge '\(cartridge.id)' on master \(masterIdx) is missing mandatory runtime_stats")
        }
        admission.configurePools(
            key, pools: try Self.poolCapacities(stats, cartridgeId: cartridge.id))
        return try Self.admissionChain(
            install: key, stats: stats, registeredCap: registeredCap, cartridgeId: cartridge.id)
    }

    /// The cap-table entry on this master that `capUrn` dispatches to. Caller
    /// must hold `lock`.
    internal func registeredCapForLocked(_ masterIdx: Int, _ capUrn: String) throws -> String {
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else {
            throw RelaySwitchError.noHandler(capUrn)
        }
        for entry in capTable where entry.masterIdx == masterIdx {
            guard let registeredUrn = try? CSCapUrn.fromString(entry.capUrn) else { continue }
            if registeredUrn.isDispatchable(requestUrn) {
                return entry.capUrn
            }
        }
        throw RelaySwitchError.noHandler(capUrn)
    }

    /// Authoritative minimum effective capacity across the pool chain
    /// serving a cap (0 = every pool unlimited). A positive capacity is an
    /// execution boundary: callers must not pre-acquire that request as
    /// part of a multi-cap live pipeline, because the permit represents
    /// actively owned pool slots. Mirrors `admission_capacity_for_cap`.
    public func admissionCapacityForCap(_ capUrn: String) throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard let destIdx = findMasterForCap(capUrn, preferredCap: nil) else {
            throw RelaySwitchError.noHandler(capUrn)
        }
        let registered = try registeredCapForLocked(destIdx, capUrn)
        let chain = try capAdmissionTargetLocked(destIdx, registered)
        let bounded = chain.map(\.capacity).filter { $0 > 0 }
        return bounded.min() ?? 0
    }

    /// Resolve the cartridge that will serve `capUrn` and take its admission
    /// slot, waiting for capacity. Called WITHOUT `lock` held: acquiring can
    /// block, and blocking under the switch lock would deadlock every path that
    /// must run for a slot to be released.
    internal func acquireCapAdmission(
        _ capUrn: String,
        preferredCap: String?
    ) throws -> AdmissionPermit {
        lock.lock()
        let chain: [PoolKey]
        do {
            guard let destIdx = findMasterForCap(capUrn, preferredCap: preferredCap) else {
                // Thrown, not returned: the single `catch` below owns unlocking
                // on every failure path. Unlocking here too would double-unlock.
                throw RelaySwitchError.noHandler(capUrn)
            }
            let registered = try registeredCapForLocked(destIdx, capUrn)
            chain = try capAdmissionTargetLocked(destIdx, registered).map(\.key)
        } catch {
            lock.unlock()
            throw error
        }
        lock.unlock()

        do {
            return try admission.acquire(chain)
        } catch let error as AdmissionError {
            throw RelaySwitchError.cartridgeUnavailable(error.reason)
        }
    }

    public func sendToMaster(_ frame: Frame, preferredCap: String? = nil) throws {
        // A REQ takes an admission permit BEFORE the switch lock: acquiring can
        // block waiting for a slot, and blocking under `lock` would deadlock
        // every path that must run for a slot to be released. Route resolution
        // needs the lock, so the sequence is resolve → unlock → acquire →
        // relock → register, exactly as the reference orders it. Direct
        // target_cartridge routing bypasses cap dispatch and so does not take a
        // cap-selected permit.
        var permit: AdmissionPermit?
        if frame.frameType == .req, let cap = frame.cap {
            let routesByCartridgeId: Bool = frame.meta.flatMap { meta in
                if case .utf8String = meta["target_cartridge"] { return true }
                return nil
            } ?? false
            if !routesByCartridgeId {
                permit = try acquireCapAdmission(cap, preferredCap: preferredCap)
            }
        }
        // Any throw past this point must give the slot back, or a bounded
        // cartridge loses capacity permanently.
        var admitted = false
        defer { if !admitted { permit?.release() } }

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

            // Register the request: origin nil (external caller via
            // sendToMaster), no response channel — responses return via
            // readFromMasters (L7). Duplicate registration is a protocol
            // violation and fails hard.
            do {
                let state = RequestState(
                    routing: RoutingEntry(sourceMasterIdx: nil, destinationMasterIdx: destIdx),
                    origin: nil,
                    externalChannel: nil,
                    isPeer: false,
                    initialCredit: masterInitialCredit(destIdx)
                )
                state.capUrn = mutableFrame.cap
                // The request table owns the permit now: it is released when
                // the request terminates (End | Err | Cancelled | MasterDied).
                state.admissionPermit = permit
                try requests.register(key, state)
            } catch {
                throw RelaySwitchError.protocolError("\(error.localizedDescription)")
            }
            admitted = true

            // Forward to destination with XID
            try writeToMasterIdx(destIdx, &mutableFrame)

        case .streamStart, .chunk, .streamEnd, .end, .err, .credit:
            // Continuation/control frames from engine: look up XID from RID
            // if missing, then the destination — one table read. Unknown RID
            // is a hard error back to the caller: the engine is a direct API
            // client and must observe that the request no longer exists
            // (already terminated) so it stops sending.
            let xid: MessageId
            if let existingXid = frame.routingId {
                xid = existingXid
            } else {
                guard let lookedUpXid = requests.xidForRid(frame.id) else {
                    throw RelaySwitchError.unknownRequest(frame.id.toString())
                }
                xid = lookedUpXid
                mutableFrame.routingId = xid
            }

            let key = RoutingKey(xid: xid, rid: frame.id)

            guard let entry = requests.get(key) else {
                throw RelaySwitchError.unknownRequest(frame.id.toString())
            }

            // RECORD the outbound frame in the request's flow ledger.
            // Engine-originated grants and chunks are half of every stream's
            // credit arithmetic; skipping them made the snapshot ledger read
            // healthy streams as deep-negative.
            requests.recordFrame(key, direction: .outbound, frame: mutableFrame)

            let destIdx = entry.routing.destinationMasterIdx

            // Forward to destination
            try writeToMasterIdx(destIdx, &mutableFrame)

        case .cancel, .closeStream:
            // Cancel / CloseStream route like a continuation frame — look up XID from RID
            let xid: MessageId
            if let existingXid = frame.routingId {
                xid = existingXid
            } else {
                guard let lookedUpXid = requests.xidForRid(frame.id) else {
                    throw RelaySwitchError.unknownRequest(frame.id.toString())
                }
                xid = lookedUpXid
                mutableFrame.routingId = xid
            }

            let key = RoutingKey(xid: xid, rid: frame.id)
            guard let entry = requests.get(key) else {
                throw RelaySwitchError.unknownRequest(frame.id.toString())
            }
            try writeToMasterIdx(entry.routing.destinationMasterIdx, &mutableFrame)

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

            switch try handleNextInbound() {
            case .none: continue
            case .allMastersClosed: return nil
            case .forEngine(let frame): return frame
            }
        }
    }

    /// What handling one item of the inbound stream came to.
    private enum InboundHandled {
        /// Nothing for the engine: the item was handled here, or the stream
        /// was empty.
        case none
        /// Every master has closed.
        case allMastersClosed
        /// A frame for the engine.
        case forEngine(Frame)
    }

    /// Take the next item of the inbound stream, if there is one, and handle
    /// it: a master's frame, its connection's end, or the end of bringing a
    /// held peer request's provider.
    private func handleNextInbound() throws -> InboundHandled {
        lock.lock()
        guard !frameChannel.isEmpty else {
            lock.unlock()
            return .none
        }
        let item = frameChannel.removeFirst()
        lock.unlock()

        switch item {
        case .settled(let rid, let settlement):
            try releaseHeldRequest(rid: rid, settlement)
            return .none
        case .master(let masterIdx, _, .some(let error)):
            fputs("[RelaySwitch] Error reading from master \(masterIdx): \(error)\n", stderr)
            try handleMasterDeath(masterIdx)
            return .none
        case .master(let masterIdx, .none, .none):
            try handleMasterDeath(masterIdx)
            lock.lock()
            let allDead = masters.allSatisfy { !$0.healthy }
            lock.unlock()
            return allDead ? .allMastersClosed : .none
        case .master(let masterIdx, .some(let frame), .none):
            if let resultFrame = try handleMasterFrame(sourceIdx: masterIdx, frame: frame) {
                return .forEngine(resultFrame)
            }
            return .none
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

            switch try handleNextInbound() {
            case .none: continue
            case .allMastersClosed: return nil
            case .forEngine(let frame): return frame
            }
        }
    }

    // MARK: - Internal Routing

    /// Find which master handles a given cap URN.
    /// Prefers the match whose specificity is CLOSEST to the request's specificity.
    /// This ensures generic requests (e.g., identity) route to generic handlers,
    /// and specific requests route to specific handlers.
    ///
    /// Uses `isDispatchable(candidate, request)` to find all masters that can
    /// legally handle the request.
    ///
    /// Among dispatchable matches, ranking prefers:
    /// 1. Equivalent matches (distance 0)
    /// 2. More specific candidates (positive distance) - refinements
    /// 3. More generic candidates (negative distance) - fallbacks
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

    // MARK: - Peer requests no master serves

    /// Bring a provider for the peer requests no master serves, holding each
    /// while it does, within `bound` (14.2 §Peer requests no master serves).
    /// Set once, before the switch routes anything that may need it; a second
    /// provider is refused.
    public func setPeerProvider(_ provider: PeerProvider, bound: PeerHoldBound) throws {
        lock.lock()
        defer { lock.unlock() }
        guard peerProviding == nil else {
            throw RelaySwitchError.protocolError("this switch already has a peer provider")
        }
        peerProviding = (provider: provider, holds: PeerHoldTable(bound: bound))
    }

    /// Hold peer REQ `frame` and start bringing the provider of its cap. The
    /// end of bringing it arrives on the inbound stream, in order with every
    /// frame the caller sends. Caller holds `lock`.
    private func holdPeerRequestLocked(sourceIdx: Int, frame: Frame) throws -> Frame? {
        guard let providing = peerProviding else {
            fatalError("BUG: only a switch with a peer provider holds requests")
        }
        if var err = providing.holds.hold(sourceIdx: sourceIdx, req: frame) {
            fputs("[RelaySwitch] peer REQ cap='\(frame.cap ?? "")' rid=\(frame.id) is more than a hold keeps — refused\n", stderr)
            try? writeToMasterIdx(sourceIdx, &err)
            return nil
        }
        fputs("[RelaySwitch] no master serves the peer REQ cap='\(frame.cap ?? "")' rid=\(frame.id) from_master=\(sourceIdx) — held while its provider is brought\n", stderr)
        let rid = frame.id
        let capUrn = frame.cap!
        let provider = providing.provider
        let deadline = providing.holds.bound.deadline
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let settlement = self.bringProvider(provider, capUrn: capUrn, deadline: deadline)
            self.enqueue(.settled(rid: rid, settlement: settlement))
        }
        return nil
    }

    /// A frame from master `sourceIdx` for one of the requests it made that is
    /// held: kept, or the end of the request. Returns whether the frame was
    /// the hold's. Caller holds `lock`.
    private func arriveForHeldRequestLocked(sourceIdx: Int, frame: Frame) throws -> Bool {
        guard let providing = peerProviding, providing.holds.isHeld(sourceIdx: sourceIdx, rid: frame.id) else {
            return false
        }
        if var err = providing.holds.arrive(frame) {
            fputs("[RelaySwitch] held peer request rid=\(frame.id) ended: \(err.errorCode ?? "")\n", stderr)
            try? writeToMasterIdx(sourceIdx, &err)
        }
        return true
    }

    /// Bringing held request `rid`'s provider ended: replay its frames, in the
    /// order they came, or answer its caller with why not.
    private func releaseHeldRequest(rid: MessageId, _ settlement: PeerSettlement) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let providing = peerProviding else {
            fatalError("BUG: only a switch with a peer provider holds requests")
        }
        // Nil: cancelled, overflowed, or its caller's master died meanwhile.
        guard let (request, err) = providing.holds.settle(rid: rid, settlement) else { return }
        if var err = err {
            fputs("[RelaySwitch] held peer request cap='\(request.capUrn)' rid=\(rid): its provider was not brought — ended\n", stderr)
            try? writeToMasterIdx(request.sourceIdx, &err)
            return
        }
        fputs("[RelaySwitch] held peer request cap='\(request.capUrn)' rid=\(rid) replayed (\(request.frames.count) frames)\n", stderr)
        _ = try routePeerRequestLocked(sourceIdx: request.sourceIdx, frame: request.frames[0], replayed: true)
        for frame in request.frames.dropFirst() {
            // A peer request's own frames are routed internally; none is ever
            // handed to the engine.
            _ = try handleMasterFrameLocked(sourceIdx: request.sourceIdx, frame: frame)
        }
    }

    /// Bring the provider of `capUrn` for a held request, within `deadline`:
    /// find it, wait for it to be ready, then for a master to serve the cap.
    /// Bringing it goes on past the deadline — only the wait ends. Blocking;
    /// called without `lock`.
    private func bringProvider(_ provider: PeerProvider, capUrn: String, deadline: TimeInterval) -> PeerSettlement {
        let expiry = DispatchTime.now() + deadline

        let found = DispatchSemaphore(value: 0)
        let provisionBox = PeerHandoff<Result<PeerProvision, PeerRefusal>>()
        DispatchQueue.global(qos: .userInitiated).async {
            provisionBox.value = provider.provision(capUrn: capUrn)
            found.signal()
        }
        if found.wait(timeout: expiry) == .timedOut {
            return .expired(PeerRefusal(
                code: PEER_PROVIDER_TIMEOUT,
                attributionClass: .environment,
                message: "no cartridge providing \(capUrn) was found within \(Int(deadline)) s"
            ))
        }
        let provision: PeerProvision
        switch provisionBox.value! {
        case .failure(let refusal): return .refused(refusal)
        case .success(let p): provision = p
        }

        let readied = DispatchSemaphore(value: 0)
        let readyBox = PeerHandoff<PeerRefusal?>()
        DispatchQueue.global(qos: .userInitiated).async {
            readyBox.value = .some(provision.ready())
            readied.signal()
        }
        if readied.wait(timeout: expiry) == .timedOut {
            return .expired(provision.onExpiry)
        }
        if case .some(.some(let refusal)) = readyBox.value {
            return .refused(refusal)
        }

        while true {
            lock.lock()
            let served = findMasterForCap(capUrn, preferredCap: nil) != nil
            lock.unlock()
            if served { return .provided }
            if DispatchTime.now() >= expiry { return .expired(provision.onExpiry) }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// Route peer REQ `frame` from master `sourceIdx`, already given its
    /// routing id: to the master that serves its cap; or, when none does,
    /// held while the switch's `PeerProvider` brings one, or refused with
    /// NO_HANDLER — as the model decides (formal/CapDAG/Bifaci/Hold.lean).
    /// `replayed` is a REQ that was held before: it is never held again.
    /// Caller holds `lock`.
    private func routePeerRequestLocked(sourceIdx: Int, frame: Frame, replayed: Bool) throws -> Frame? {
        guard let cap = frame.cap, let xid = frame.routingId else {
            fatalError("BUG: a peer REQ names its cap and is given its routing id before it is routed")
        }
        var mutableFrame = frame

        // Find destination master (no preference for peer requests).
        guard let destIdx = findMasterForCap(cap, preferredCap: nil) else {
            if ProtocolModel.holds(canProvide: peerProviding != nil, replayed: replayed) {
                return try holdPeerRequestLocked(sourceIdx: sourceIdx, frame: frame)
            }
            // No handler registered for this cap. Rather than throwing
            // — which aborts the pump and leaves the caller hanging
            // until its activity timeout — send an ERR frame straight
            // back to the source master so the peer call fails fast
            // with a clear error. Stamp the synthetic XID assigned
            // above so the receiving cartridge host runtime accepts it
            // (path-C invariant). Mirrors Rust's route_peer_request
            // NO_HANDLER branch (Ok(None) + ERR to caller).
            fputs("[RelaySwitch] NO_HANDLER for peer REQ cap='\(cap)' rid=\(frame.id) from_master=\(sourceIdx) — sending ERR to caller\n", stderr)
            // No master serving this cap is a deployment/manifest
            // mismatch — Environment (docs/failure-taxonomy.md).
            let message = replayed
                ? "No handler found for cap: \(cap) — its provider was brought, and no master serves it even so"
                : "No handler found for cap: \(cap)"
            var errFrame = Frame.err(id: frame.id, code: "NO_HANDLER", attributionClass: .environment, message: message)
            errFrame.routingId = xid
            try? writeToMasterIdx(sourceIdx, &errFrame)
            return nil
        }

        let rid = frame.id
        let key = RoutingKey(xid: xid, rid: rid)

        // Register the peer request and link it under its parent for
        // the cancel cascade — one table write (L7).
        fputs("[RelaySwitch] PEER_REQ: master \(sourceIdx) → master \(destIdx) cap='\(cap)' rid=\(rid) xid=\(xid)\n", stderr)
        do {
            let state = RequestState(
                routing: RoutingEntry(sourceMasterIdx: sourceIdx, destinationMasterIdx: destIdx),
                origin: sourceIdx,
                externalChannel: nil,
                isPeer: true,
                initialCredit: masterInitialCredit(destIdx)
            )
            state.capUrn = cap
            try requests.register(key, state)
        } catch {
            throw RelaySwitchError.protocolError("\(error.localizedDescription)")
        }

        // Track parent→child for cancel cascade
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
            if let parentRid = parentRid, let parentXid = requests.xidForRid(parentRid) {
                requests.linkChild(parent: RoutingKey(xid: parentXid, rid: parentRid), child: key)
            }
        }

        // Forward to destination with XID
        try writeToMasterIdx(destIdx, &mutableFrame)

        // Do NOT return to engine (internal routing)
        return nil
    }

    /// Handle a frame arriving from a master (cartridge → engine direction).
    ///
    /// Returns Some(frame) if the frame should be forwarded to the engine.
    /// Returns nil if the frame was handled internally (peer request or request continuation).
    func handleMasterFrame(sourceIdx: Int, frame: Frame) throws -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        return try handleMasterFrameLocked(sourceIdx: sourceIdx, frame: frame)
    }

    /// `handleMasterFrame`, with `lock` held.
    private func handleMasterFrameLocked(sourceIdx: Int, frame: Frame) throws -> Frame? {
        // A frame a cartridge sends for its own peer request that is held
        // (its argument streams, its grants, its cancel) is the hold's: kept
        // to be replayed after the REQ, or the request's end.
        let forOwnRequest: Bool
        switch frame.frameType {
        case .streamStart, .chunk, .streamEnd, .end, .err, .log, .credit:
            forOwnRequest = frame.routingId == nil
        case .cancel, .closeStream:
            forOwnRequest = true
        default:
            forOwnRequest = false
        }
        if forOwnRequest, try arriveForHeldRequestLocked(sourceIdx: sourceIdx, frame: frame) {
            return nil
        }

        var mutableFrame = frame

        switch frame.frameType {
        case .req:
            // Peer request: cartridge → cartridge via switch (no preference)
            guard frame.cap != nil else {
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
            mutableFrame.routingId = MessageId.uint(xidCounter)

            return try routePeerRequestLocked(sourceIdx: sourceIdx, frame: mutableFrame, replayed: false)

        case .streamStart, .chunk, .streamEnd, .end, .err, .log, .credit:
            // Branch based on XID presence to distinguish request vs response direction
            if frame.routingId != nil {
                // ========================================
                // HAS XID = RESPONSE CONTINUATION
                // ========================================
                // Frame already has XID, so it's a response flowing back to origin
                let xid = frame.routingId!
                let rid = frame.id
                let key = RoutingKey(xid: xid, rid: rid)

                let terminalKind = TerminalKind.of(frame: frame.frameType)
                let isTerminal = terminalKind != nil

                /// Where a response frame must go next.
                enum RouteBack {
                    case external(((Frame) -> Bool)?)
                    case master(Int)
                }

                // Record flow stats, resolve the return path, and — on
                // terminal — remove the whole entry atomically (L7). The
                // terminal is forwarded using the state `terminate` hands
                // back, so routing state release and terminal delivery
                // cannot disagree (L6). A frame for a released key is a
                // counted no_route drop, never a protocol error and never
                // silent (L8).
                requests.recordFrame(key, direction: .inbound, frame: frame)
                let route: RouteBack
                var capForLog: String? = nil
                if let kind = terminalKind {
                    guard let state = requests.terminate(key, kind: kind) else {
                        // Classify by the terminated ring: a frame for a
                        // request that JUST terminated is a benign
                        // straggler; only a RID the table never knew is a
                        // routing anomaly (`no_route` drop).
                        accountUnroutedFrame(
                            recentlyTerminated: requests.recentlyTerminatedRid(rid),
                            frame: frame,
                            context: "duplicate terminal for released request"
                        )
                        return nil
                    }
                    capForLog = state.capUrn
                    switch state.origin {
                    case nil: route = .external(state.externalChannel)
                    case .some(let idx): route = .master(idx)
                    }
                } else {
                    guard let state = requests.get(key) else {
                        accountUnroutedFrame(
                            recentlyTerminated: requests.recentlyTerminatedRid(rid),
                            frame: frame,
                            context: "response frame with no routing state"
                        )
                        return nil
                    }
                    capForLog = state.capUrn
                    switch state.origin {
                    case nil: route = .external(state.externalChannel)
                    case .some(let idx): route = .master(idx)
                    }
                }

                switch route {
                case .external(.some(let channel)):
                    // Deliver to the external response channel (keep XID).
                    if !channel(mutableFrame) {
                        let total = drops.record(.channelClosed, frame.frameType)
                        fputs("[RelaySwitch] response channel receiver gone (channel_closed) rid=\(rid) cap=\(capForLog ?? "?") channel_closed_total=\(total)\n", stderr)
                        // A dead consumer on a LIVE request means the caller
                        // abandoned it — cancel upstream so the cartridge
                        // stops producing for a dead channel (TEST7093).
                        // Dispatched off-lock: handleMasterFrame holds the
                        // switch lock for its whole body and cancelRequest
                        // re-acquires it (non-recursive NSLock).
                        if !isTerminal {
                            let cancelRid = rid
                            DispatchQueue.global(qos: .utility).async { [weak self] in
                                self?.cancelRequest(rid: cancelRid, reason: .host(.internal, "response channel receiver gone: the caller abandoned the request"))
                            }
                        }
                    }
                    return nil
                case .external(nil):
                    // No response channel (sent via sendToMaster, not an
                    // execute-style call). Strip XID and return to engine.
                    mutableFrame.routingId = nil
                    return mutableFrame
                case .master(let masterIdx):
                    // Route back to source master — KEEP XID.
                    if isTerminal {
                        fputs("[RelaySwitch] PEER_RESP: routing \(frame.frameType) back to master \(masterIdx) xid=\(xid) rid=\(rid)\n", stderr)
                    }
                    try writeToMasterIdx(masterIdx, &mutableFrame)
                    return nil
                }
            } else {
                // ========================================
                // NO XID = REQUEST CONTINUATION
                // ========================================
                // Frame has no XID, so it's a request continuation
                // (peer-call argument streams / grants) flowing to the
                // destination. An unknown RID means the request already
                // terminated: counted drop (L6), not an error.
                let rid = frame.id

                guard let xid = requests.xidForRid(rid) else {
                    accountUnroutedFrame(
                        recentlyTerminated: requests.recentlyTerminatedRid(rid),
                        frame: frame,
                        context: "continuation with no routing state"
                    )
                    return nil
                }

                let key = RoutingKey(xid: xid, rid: rid)
                requests.recordFrame(key, direction: .inbound, frame: frame)

                guard let entry = requests.get(key) else {
                    accountUnroutedFrame(
                        recentlyTerminated: requests.recentlyTerminatedRid(rid),
                        frame: frame,
                        context: "continuation with no routing state"
                    )
                    return nil
                }

                // Add XID to frame for forwarding
                mutableFrame.routingId = xid

                // Forward to destination master (keep XID)
                try writeToMasterIdx(entry.routing.destinationMasterIdx, &mutableFrame)
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

        case .cancel, .closeStream:
            // Cancel / CloseStream from cartridge — route to destination like a
            // continuation frame. Cartridge is cancelling (or closing the live
            // input of) its own peer call. Unknown RID means the request already
            // completed: a well-defined no-op.
            let rid = frame.id
            let xid: MessageId
            if let existingXid = frame.routingId {
                xid = existingXid
            } else {
                guard let lookedUpXid = requests.xidForRid(rid) else {
                    // Unknown RID — silently ignore (request may already be completed)
                    return nil
                }
                xid = lookedUpXid
                mutableFrame.routingId = xid
            }

            let key = RoutingKey(xid: xid, rid: rid)
            guard let entry = requests.get(key) else {
                // Unknown routing — silently ignore
                return nil
            }

            fputs("[RelaySwitch] Routing Cancel from master \(sourceIdx) to master \(entry.routing.destinationMasterIdx) xid=\(xid) rid=\(rid)\n", stderr)
            try writeToMasterIdx(entry.routing.destinationMasterIdx, &mutableFrame)
            return nil

        default:
            return frame
        }
    }

    func handleMasterDeath(_ masterIdx: Int) throws {
        // Every slot behind this master goes unavailable. Queued work is NOT
        // failed here: it rides the admission grace window in case the master
        // reconnects.
        admission.disableMaster(masterIdx)
        lock.lock()
        defer { lock.unlock() }

        // The slot is DETACHED from here on, whatever the health flag
        // said: the connection is declared dead, so the slot is
        // reattachable to `addMaster` / `slotAcceptsAttach`. Before the
        // already-handled short-circuit below — an unhealthy-but-attached
        // slot (probe pending) whose socket then closes must detach too,
        // or the host could never reconnect to it.
        masters[masterIdx].detached = true

        // The requests held for its cartridges have nobody left to answer.
        if let providing = peerProviding {
            let forgotten = providing.holds.forgetSource(masterIdx)
            if forgotten > 0 {
                fputs("[RelaySwitch] master \(masterIdx) died: its \(forgotten) held peer requests dropped\n", stderr)
            }
        }

        guard masters[masterIdx].healthy else {
            // Already unhealthy: its death was handled before, or it never
            // became routable (its identity probe is open or failed). No
            // route leads here, but a request to it — its open identity
            // probe — still ends: nobody is left to answer it.
            endIdentityProbesLocked(ofMaster: masterIdx)
            failRequestsToMasterLocked(masterIdx)
            return
        }

        fputs("[RelaySwitch] Master \(masterIdx) died\n", stderr)
        masters[masterIdx].healthy = false
        endIdentityProbesLocked(ofMaster: masterIdx)
        failRequestsToMasterLocked(masterIdx)

        rebuildCapTable()
        rebuildCapabilities()
        rebuildLimits()
    }

    /// End every request routed to a master whose connection died, each
    /// with a MASTER_DIED ERR to whoever waits on it. Caller holds `lock`.
    private func failRequestsToMasterLocked(_ masterIdx: Int) {
        let deadKeys = requests.keysWhere { $0.routing.destinationMasterIdx == masterIdx }

        // Terminate each pending request (masterDied) and deliver a synthetic
        // ERR to whoever was waiting on it. terminate() atomically removes
        // ALL state for the key (L7) and hands back the origin + channel
        // needed for delivery.
        for key in deadKeys {
            guard let state = requests.terminate(key, kind: .masterDied) else {
                continue // raced another terminal — already fully cleaned
            }

            // A dead relay master is a runtime-environment failure —
            // Environment (docs/failure-taxonomy.md).
            var errFrame = Frame.err(
                id: key.rid,
                code: "MASTER_DIED",
                attributionClass: .environment,
                message: "Relay master \(masterIdx) connection closed"
            )
            errFrame.routingId = key.xid

            switch state.origin {
            case nil:
                // External caller — deliver on the response channel if any.
                if let channel = state.externalChannel {
                    _ = channel(errFrame)
                }
            case .some(let srcMasterIdx):
                if masters[srcMasterIdx].healthy {
                    try? writeToMasterIdx(srcMasterIdx, &errFrame)
                }
            }
        }
    }

    // MARK: - Protocol Stats + Cancellation

    /// The switch's protocol observability snapshot (L8): live request state,
    /// recent terminations, and per-reason drop counters. Field names are the
    /// mirror contract.
    public func protocolStats() -> RelaySwitchProtocolStats {
        lock.lock()
        defer { lock.unlock() }
        // Per-master host protocol stats, keyed by master id, as reported
        // in each host's latest RelayNotify. A master that has not yet
        // advertised stats is absent — never a zeroed placeholder.
        var hosts: [String: HostProtocolStats] = [:]
        for master in masters {
            if let stats = master.hostProtocolStats {
                hosts[master.id] = stats
            }
        }
        return RelaySwitchProtocolStats(
            requests: requests.snapshot(),
            drops: drops.snapshot(),
            stragglers: stragglers.snapshot(),
            hosts: hosts
        )
    }

    /// Account a flow frame that found no routing state, for the narrow case
    /// it actually is: when the terminated ledger vouches the request JUST
    /// terminated, the frame is a benign post-terminal straggler — the
    /// expected teardown crossing, counted per frame type and logged as
    /// benign, never as a drop. Otherwise the RID is one the table never
    /// knew: a genuine routing anomaly, counted as a `no_route` drop.
    /// (matches Rust RelaySwitch::account_unrouted_frame)
    private func accountUnroutedFrame(recentlyTerminated: Bool, frame: Frame, context: String) {
        switch Disposition.of(live: false, endedLately: recentlyTerminated) {
        case .straggler:
            let total = stragglers.record(frame.frameType)
            fputs("[RelaySwitch] benign post-terminal straggler (\(context)): frame crossed its request's terminal in flight — expected teardown race, nothing lost. type=\(frame.frameType.asString) rid=\(frame.id) straggler_total=\(total)\n", stderr)
        case .noRoute:
            let total = drops.record(.noRoute, frame.frameType)
            fputs("[RelaySwitch] dropped \(context) — RID has no routing state and never terminated here (no_route). type=\(frame.frameType.asString) rid=\(frame.id) no_route_total=\(total)\n", stderr)
        case .route:
            fatalError("BUG: a frame with no routing state cannot be routed")
        }
    }

    /// STOP a feed-bearing request's live inputs (15.2 §Runs Stop): send a
    /// CloseStream FRAME to the request's destination WITHOUT touching
    /// host-side request state. The cartridge runtime closes the request's
    /// open taps and the request then ends NATURALLY — END after the drain.
    /// Not a cancel in any form: contrast `cancelRequest`, which terminates
    /// host state, cascades to children, and delivers a terminal ERR.
    ///
    /// Returns whether the request was live and the stop was sent. A request
    /// the switch does not know (already terminated) is not stopped, and the
    /// caller must not claim that it was. (matches Rust RelaySwitch::stop_request_feeds)
    @discardableResult
    public func stopRequestFeeds(rid: MessageId) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let xid = requests.xidForRid(rid),
              let state = requests.get(RoutingKey(xid: xid, rid: rid)) else {
            return false
        }
        var closeFrame = Frame.closeStream(targetRid: rid, streamId: nil)
        closeFrame.routingId = xid
        do {
            try writeToMasterIdx(state.routing.destinationMasterIdx, &closeFrame)
            return true
        } catch {
            return false
        }
    }

    /// Whether a RID is live in the request table.
    public func isRequestLive(rid: MessageId) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return requests.xidForRid(rid) != nil
    }

    /// How a recently terminated RID ended, or nil while it is live or once it
    /// has aged out of the terminated ring.
    public func recentTerminalOfRid(rid: MessageId) -> TerminatedSummary? {
        lock.lock()
        defer { lock.unlock() }
        return requests.recentTerminalOfRid(rid)
    }

    /// Cancel a specific in-flight request by RID, for a stated reason.
    ///
    /// 1. Terminates the request as cancelled WITH the reason FIRST — one
    ///    atomic removal yields the destination, the children for the cascade,
    ///    and the external channel for the final ERR (L7), and records the
    ///    attribution on the summary. A concurrent terminal for the same key
    ///    loses the race and becomes a counted no_route drop.
    /// 2. Sends the Cancel frame (attribution in meta, forceKill) to the
    ///    destination master
    /// 3. Recursively cancels the child peer calls recorded on the entry,
    ///    under the same reason
    /// 4. Sends the terminal ERR to the external response channel if present,
    ///    in the reason's own words: CANCELLED/user for an operator's cancel,
    ///    ABORTED_COLLATERAL with the originating failure's class for
    ///    collateral, ABORTED with the host's class for a host abort — so
    ///    "cancelled" is never said of an abort.
    ///
    /// The reason is optional attribution, never a precondition: an
    /// unattributed reason cancels all the same. Closing a live input without
    /// cancelling is `stopRequestFeeds`.
    public func cancelRequest(rid: MessageId, reason: CancelReason) {
        lock.lock()
        guard let xid = requests.xidForRid(rid) else {
            lock.unlock()
            return
        }
        let key = RoutingKey(xid: xid, rid: rid)
        guard let state = requests.terminateCancelled(key, reason: reason) else {
            lock.unlock()
            return
        }

        // Send Cancel frame to destination
        var cancelFrame = Frame.cancel(targetRid: rid, reason: reason)
        cancelFrame.routingId = xid
        try? writeToMasterIdx(state.routing.destinationMasterIdx, &cancelFrame)

        let children = state.children
        let externalChannel = state.externalChannel
        lock.unlock()

        // Recursively cancel children (outside the lock — each child cancel
        // re-acquires it), under the same reason.
        for child in children {
            cancelRequest(rid: child.rid, reason: reason)
        }

        // Send the terminal ERR to the external response channel if present
        if let channel = externalChannel {
            var errFrame = Frame.err(id: rid, code: reason.terminalCode, attributionClass: reason.terminalClass, message: reason.terminalMessage)
            errFrame.routingId = xid
            _ = channel(errFrame)
        }
    }

    /// Cancel all external-origin (engine-initiated) in-flight requests, for a
    /// stated reason. Returns the list of cancelled RIDs.
    @discardableResult
    public func cancelAllRequests(reason: CancelReason) -> [MessageId] {
        lock.lock()
        let rids = requests.keysWhere { $0.origin == nil }.map { $0.rid }
        lock.unlock()
        for rid in rids {
            cancelRequest(rid: rid, reason: reason)
        }
        return rids
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
        // Refresh admission from the fresh inventory: a cartridge that left it
        // goes unavailable (starting its grace window), one that returned is
        // configured again, which releases anything queued on it.
        try configureMasterAdmissionLocked(sourceIdx, payload.installedCartridges)
        masters[sourceIdx].hostProtocolStats = payload.hostProtocolStats
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
            pendingIdentityProbes.append(.probe(sourceIdx))
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
        // The driver must NOT keep the switch alive. `self?.loop()` looks weak
        // but is not: the optional-chained call retains `self` for the whole
        // duration of the callee, and the callee is a `while true` loop parked
        // in `probeSemaphore.wait()`. A switch that is never explicitly shut
        // down is then immortal, held by its own background thread — and its
        // deinit eventually runs at an arbitrary moment on whichever thread
        // happens to drop the last reference, taking `lock` while a stranded
        // driver still owns it.
        //
        // The reference does this correctly: `Arc::downgrade` once, then
        // `weak_probe.upgrade()` PER ITERATION, breaking when the upgrade
        // fails ("relay torn down"). This mirrors that — the semaphore is
        // captured by value so waiting needs no `self` at all, and the strong
        // reference exists only while an iteration is actually running.
        let semaphore = probeSemaphore
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while true {
                semaphore.wait()
                // Upgrade per iteration, exactly as the reference does. A nil
                // here is the switch having gone away: the driver's work is
                // over and holding on would be the leak this avoids.
                guard let switchRef = self else { return }
                if !switchRef.runOneQueuedProbe() { return }
                // `switchRef` goes out of scope HERE, before the next wait, so
                // the switch is never retained across a park.
            }
        }
    }

    /// One iteration of the probe driver: pop a queued job and start it on
    /// a thread of its own — a probe of a master whose caps went from empty
    /// to non-empty, or the wait for the answer to an `addMaster` probe left
    /// unanswered at the end of its window — so a probe waiting on a slow
    /// host never holds back another master's. Mirrors Rust's
    /// spawn_identity_probe_driver task body.
    /// Returns false when the driver must stop (the switch is shutting down).
    /// Split out from the loop so the strong reference the body needs is
    /// scoped to the iteration rather than to the driver's whole lifetime.
    private func runOneQueuedProbe() -> Bool {
        lock.lock()
        if isShutdown {
            lock.unlock()
            return false
        }
        guard !pendingIdentityProbes.isEmpty else {
            lock.unlock()
            return true
        }
        let job = pendingIdentityProbes.removeFirst()
        lock.unlock()

        // The probe's thread holds the switch only weakly: one waiting on a
        // host that never answers must not keep it alive.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let probe: OpenIdentityProbe
            switch job {
            case .await(let open):
                probe = open
            case .probe(let masterIdx):
                guard let switchRef = self else { return }
                switch switchRef.openIdentityProbe(masterIdx) {
                case .opened(let open):
                    probe = open
                case .notSent(let key, let detail):
                    switchRef.settleIdentityProbe(masterIdx: masterIdx, key: key, failure: detail)
                    return
                }
            }
            RelaySwitch.awaitIdentityAnswer(probe, of: { self })
        }
        return true
    }

    /// Shorten the identity probe window, so a test can watch a probe
    /// outlast it.
    internal func setIdentityProbeWindowForTest(_ window: TimeInterval) {
        lock.lock()
        identityProbeWindow = window
        lock.unlock()
    }

    private enum OpenedProbe {
        case opened(OpenIdentityProbe)
        /// The probe could not be sent; settle it with why.
        case notSent(RoutingKey, String)
    }

    /// Send an end-to-end identity probe to `masterIdx`: CAP_IDENTITY REQ +
    /// STREAM_START + CHUNK(nonce) + STREAM_END + END on a fresh `(xid, rid)`
    /// flow, its answer delivered on a response channel registered in
    /// `externalResponseChannels` (the master reader thread diverts the
    /// echo there) and its request registered in the table like any
    /// request's. The probe becomes the master's open probe before anything
    /// is sent. Mirrors Rust's open_identity_probe.
    private func openIdentityProbe(_ masterIdx: Int) -> OpenedProbe {
        let channel = ResponseChannel()

        // Register the probe and send the five frames under the lock,
        // matching the rest of the switch (handleMasterFrame / sendToMaster
        // also write under the lock); the frames are tiny so the unix-socket
        // write does not block.
        lock.lock()
        defer { lock.unlock() }
        xidCounter += 1
        let xid = MessageId.uint(xidCounter)
        let rid = MessageId.newUUID()
        let key = RoutingKey(xid: xid, rid: rid)
        guard !isShutdown, masters.indices.contains(masterIdx) else {
            return .notSent(key, "master \(masterIdx): identity probe for a master that does not exist")
        }
        masters[masterIdx].identityProbe = key
        let probeState = RequestState(
            routing: RoutingEntry(sourceMasterIdx: nil, destinationMasterIdx: masterIdx),
            origin: nil,
            externalChannel: nil,
            isPeer: false,
            initialCredit: masterInitialCredit(masterIdx)
        )
        probeState.capUrn = CSCapIdentity as String
        do {
            try requests.register(key, probeState)
        } catch {
            return .notSent(key, "master \(masterIdx): identity probe registration failed: \(error)")
        }
        externalResponseChannels[key] = (masterIdx: masterIdx, channel: channel)

        let nonce = identityNonce()
        let sentAt = Date()
        do {
            for var frame in identityProbeFrames(rid: rid, xid: xid, nonce: nonce, streamId: "identity-verify-runtime") {
                try writeToMasterIdx(masterIdx, &frame)
            }
        } catch {
            return .notSent(key, "master \(masterIdx): identity probe send failed: \(error)")
        }
        return .opened(OpenIdentityProbe(
            masterIdx: masterIdx,
            key: key,
            channel: channel,
            nonce: nonce,
            echoed: Data(),
            sentAt: sentAt,
            window: identityProbeWindow,
            overdue: false
        ))
    }

    /// Wait for an open identity probe's answer and settle its master with
    /// it. Past the probe's window the master is reported overdue and the
    /// wait goes on: the answer, whenever it comes, settles the master. The
    /// wait ends without an answer only when the master's connection ends
    /// (its reader gives the probe a MASTER_DIED ERR) or the switch goes
    /// away. Holds the switch only while it reports or settles. Mirrors
    /// Rust's await_identity_answer.
    private static func awaitIdentityAnswer(_ probe: OpenIdentityProbe, of owner: () -> RelaySwitch?) {
        var failure: String? = nil
        while true {
            // Past the window, wake now and then to notice a switch that
            // went away while the probe waited.
            let wake = probe.overdue
                ? DispatchTime.now() + 1.0
                : DispatchTime.now() + max(0, probe.window - Date().timeIntervalSince(probe.sentAt))
            guard let frame = probe.channel.recv(deadline: wake) else {
                guard let switchRef = owner(), !switchRef.isShutdown else { return }
                if !probe.overdue {
                    probe.overdue = true
                    switchRef.reportIdentityProbeOverdue(probe)
                }
                continue
            }
            let step = identityAnswerStep(frame, nonce: probe.nonce, echoed: &probe.echoed)
            if step.done {
                failure = step.failure.map { "master \(probe.masterIdx): \($0)" }
                break
            }
        }
        owner()?.settleIdentityProbe(masterIdx: probe.masterIdx, key: probe.key, failure: failure)
    }

    /// Report a master whose open identity probe outlasted its window.
    private func reportIdentityProbeOverdue(_ probe: OpenIdentityProbe) {
        lock.lock()
        defer { lock.unlock() }
        guard masters.indices.contains(probe.masterIdx),
              masters[probe.masterIdx].identityProbe == probe.key else { return }
        let message = identityProbeOverdueMessage(probe.masterIdx, probe.window)
        fputs("[RelaySwitch] \(message) — the probe stays open\n", stderr)
        masters[probe.masterIdx].lastError = message
    }

    /// Settle a master with its identity probe's outcome (no failure:
    /// verified, its caps become routable; a failure: it stays unhealthy
    /// with why). A probe that is no longer the master's open one (the
    /// master reattached, or was probed again) settles nothing. Mirrors
    /// Rust's settle_identity_probe.
    private func settleIdentityProbe(masterIdx: Int, key: RoutingKey, failure: String?) {
        lock.lock()
        defer { lock.unlock() }
        // The probe's channel and request end here whichever way it did;
        // ones its answer or a master death already ended are gone.
        externalResponseChannels.removeValue(forKey: key)
        requests.terminate(key, kind: failure == nil ? .end : .err)
        guard masters.indices.contains(masterIdx),
              masters[masterIdx].identityProbe == key else { return }
        masters[masterIdx].identityProbe = nil
        masters[masterIdx].healthy = failure == nil
        masters[masterIdx].lastError = failure
        rebuildCapTable()
        rebuildCapabilities()
        if let failure = failure {
            fputs("[RelaySwitch] identity probe FAILED — master \(masterIdx) remains unhealthy: \(failure)\n", stderr)
        } else {
            fputs("[RelaySwitch] identity probe answered — master \(masterIdx) is now healthy\n", stderr)
        }
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
        // 3D mixed-variance partial orders — see capdag/docs/02-formal-foundations.md §18.5
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
        // Element-wise min across all HEALTHY masters' proposals — including
        // initialCredit (the first-burst window). Mirrors the reference's
        // `rebuild_limits`: dropping a field here silently resets it to the
        // default, so a master proposing a smaller credit window would be
        // overrun by the switch's senders (credit violations at the master).
        var minFrame = Int.max
        var minChunk = Int.max
        var minInitialCredit = UInt64.max

        for master in masters {
            if master.healthy {
                if master.limits.maxFrame < minFrame {
                    minFrame = master.limits.maxFrame
                }
                if master.limits.maxChunk < minChunk {
                    minChunk = master.limits.maxChunk
                }
                if master.limits.initialCredit < minInitialCredit {
                    minInitialCredit = master.limits.initialCredit
                }
            }
        }

        if minFrame == Int.max { minFrame = DEFAULT_MAX_FRAME }
        if minChunk == Int.max { minChunk = DEFAULT_MAX_CHUNK }
        if minInitialCredit == UInt64.max { minInitialCredit = DEFAULT_INITIAL_CREDIT }

        negotiatedLimits = Limits(
            maxFrame: minFrame,
            maxChunk: minChunk,
            initialCredit: minInitialCredit
        )
    }

    // MARK: - Helper Functions

    public func installedCartridges() -> [InstalledCartridgeRecord] {
        lock.lock()
        defer { lock.unlock() }
        return aggregateInstalledCartridges
    }

    static func parseRelayNotifyPayload(_ manifest: Data) throws -> RelayNotifyCapabilitiesPayload {
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
    /// Recovery is "reinstall".
    ///
    /// This was `badInstallation` and meant two unrelated things: this one,
    /// and "the registry does not list this version" — now `.notListed`. One
    /// kind covering two situations with different remedies cannot state
    /// either of them.
    case misplaced
    /// The cartridge's registry verified, and does not list this
    /// (channel, id, version): the artefact says it came from somewhere that
    /// has never heard of it. Distinct from `.registryUnverified`, where the
    /// registry's answer could not be obtained or could not be trusted —
    /// there we do not know, here we do. Recovery is "wait for the publish,
    /// or rebuild as a dev cartridge".
    case notListed = "not_listed"
    /// Operator explicitly disabled this cartridge through the host
    /// UI. The cartridge is on disk and would otherwise have
    /// attached cleanly; the host treats it as if the binary were
    /// yanked out of the system. Re-enabling is a UI-driven
    /// operator action. Enforced at the host level (macfloom's
    /// XPC service); the engine doesn't act on it differently from
    /// any other failed attachment, but preserves the kind so
    /// consumers can render the right reason and offer the right
    /// recovery action.
    case disabled
    /// The cartridge declares a non-null `registry_url` and that registry's
    /// verdict is not `.verified`, so its provenance claim is unconfirmed and
    /// it is held back.
    ///
    /// WHY it is unconfirmed belongs to the REGISTRY, not to the cartridge: a
    /// `RegistryVerdict` is one fact per registry URL, shared by every
    /// cartridge from it, and consumers join on `registry_url` to state it
    /// once. This kind deliberately carries no reason of its own — the kind it
    /// replaces did, called itself `registryUnreachable`, and so reported a
    /// signature this build could not read as a network outage with "check
    /// your connection" as the remedy.
    ///
    /// Network fetch is performed by the main app (which has outbound network
    /// entitlement) and pushed to the XPC service as a verdict map; the XPC
    /// service is sandboxed and cannot fetch registries directly.
    case registryUnverified = "registry_unverified"
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
    /// The cartridge's full concurrency-pool state map (Pools.swift):
    /// declared/configured/available/active/queued per pool — singleton
    /// pools keyed by cap URN, declared shared pools, and `all`. This IS
    /// the capacity surface; there is no scalar.
    public let pools: PoolStates
    public let pid: UInt32?
    public let activeRequestCount: UInt64
    public let peerRequestCount: UInt64
    public let memoryFootprintMb: UInt64
    public let memoryRssMb: UInt64
    public let lastHeartbeatUnixSeconds: Int64?
    public let restartCount: UInt64
    /// Cumulative protocol drop count self-reported by the cartridge as
    /// `drops_total` in heartbeat response meta (writer-gate post-terminal
    /// drops, closed-channel sends, …). `nil` until the first heartbeat
    /// round-trip carries the counter — absent means "no reading yet",
    /// never a fabricated zero. Omitted from the wire when nil, mirroring
    /// Rust's `skip_serializing_if`.
    public let protocolDropsTotal: UInt64?

    enum CodingKeys: String, CodingKey {
        case running
        case pools
        case pid
        case activeRequestCount = "active_request_count"
        case peerRequestCount = "peer_request_count"
        case memoryFootprintMb = "memory_footprint_mb"
        case memoryRssMb = "memory_rss_mb"
        case lastHeartbeatUnixSeconds = "last_heartbeat_unix_seconds"
        case restartCount = "restart_count"
        case protocolDropsTotal = "protocol_drops_total"
    }

    public init(
        running: Bool,
        pools: PoolStates,
        pid: UInt32? = nil,
        activeRequestCount: UInt64,
        peerRequestCount: UInt64,
        memoryFootprintMb: UInt64,
        memoryRssMb: UInt64,
        lastHeartbeatUnixSeconds: Int64? = nil,
        restartCount: UInt64,
        protocolDropsTotal: UInt64? = nil
    ) {
        self.running = running
        self.pools = pools
        self.pid = pid
        self.activeRequestCount = activeRequestCount
        self.peerRequestCount = peerRequestCount
        self.memoryFootprintMb = memoryFootprintMb
        self.memoryRssMb = memoryRssMb
        self.lastHeartbeatUnixSeconds = lastHeartbeatUnixSeconds
        self.restartCount = restartCount
        self.protocolDropsTotal = protocolDropsTotal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.running = try c.decode(Bool.self, forKey: .running)
        self.pools = try c.decode(PoolStates.self, forKey: .pools)
        self.pid = try c.decodeIfPresent(UInt32.self, forKey: .pid)
        self.activeRequestCount = try c.decode(UInt64.self, forKey: .activeRequestCount)
        self.peerRequestCount = try c.decode(UInt64.self, forKey: .peerRequestCount)
        self.memoryFootprintMb = try c.decode(UInt64.self, forKey: .memoryFootprintMb)
        self.memoryRssMb = try c.decode(UInt64.self, forKey: .memoryRssMb)
        self.lastHeartbeatUnixSeconds = try c.decodeIfPresent(Int64.self, forKey: .lastHeartbeatUnixSeconds)
        self.restartCount = try c.decode(UInt64.self, forKey: .restartCount)
        self.protocolDropsTotal = try c.decodeIfPresent(UInt64.self, forKey: .protocolDropsTotal)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(running, forKey: .running)
        try c.encode(pools, forKey: .pools)
        try c.encodeIfPresent(pid, forKey: .pid)
        try c.encode(activeRequestCount, forKey: .activeRequestCount)
        try c.encode(peerRequestCount, forKey: .peerRequestCount)
        try c.encode(memoryFootprintMb, forKey: .memoryFootprintMb)
        try c.encode(memoryRssMb, forKey: .memoryRssMb)
        try c.encodeIfPresent(lastHeartbeatUnixSeconds, forKey: .lastHeartbeatUnixSeconds)
        try c.encode(restartCount, forKey: .restartCount)
        try c.encodeIfPresent(protocolDropsTotal, forKey: .protocolDropsTotal)
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
/// See `macfloom/docs/cartridge state machine.md` for the
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
/// URNs that differ only in tag order). See `capdag/docs/02-formal-foundations.md`
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
    /// `nil` only when attachment failed before a runtime could be established.
    /// Operational in-process hosts publish unlimited capacity explicitly.
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
