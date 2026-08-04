//
//  RequestState.swift
//  Bifaci
//
//  Unified per-request state for routing runtimes (protocol v4, L7/L8).
//
//  One `RequestState` per in-flight request replaces the parallel routing maps
//  (routing entry, origin, peer markers, parent→child links, response channel,
//  rid→xid index) that previously had to be mutated consistently by hand.
//  Registration and termination are single operations: a request is registered
//  once and terminated once (end | err | cancelled | masterDied); after
//  `terminate` returns, zero state for the key remains (L7).
//
//  The table is also the observability substrate: per-stream flow counters,
//  phase tracking, and a bounded ring of recently-terminated summaries feed the
//  protocol stats snapshots (L8) without retaining routing state.
//
//  Mirrors capdag/src/bifaci/request_state.rs. The snapshot types are Codable
//  with snake_case JSON field names matching Rust's serde output exactly —
//  the snapshot shape is the mirror contract (TEST7087).

import Foundation

// MARK: - Errors

/// Protocol violations raised by the unified request table (duplicate
/// registration, rid re-indexing). Mirrors Rust's `Result<(), String>`.
public enum RequestStateError: Error, LocalizedError {
    case protocolViolation(String)

    public var errorDescription: String? {
        switch self {
        case .protocolViolation(let msg): return msg
        }
    }
}

// MARK: - RequestKey

/// (XID, RID) — the unique key of a routed request.
public struct RequestKey: Hashable, Sendable {
    public let xid: MessageId
    public let rid: MessageId

    public init(xid: MessageId, rid: MessageId) {
        self.xid = xid
        self.rid = rid
    }
}

// MARK: - RoutingEntry

/// Where a request came from and where it is going, as master indices.
public struct RoutingEntry: Equatable, Sendable {
    /// Master the request arrived from (nil = external caller / engine).
    public let sourceMasterIdx: Int?
    /// Master the request was dispatched to.
    public let destinationMasterIdx: Int

    public init(sourceMasterIdx: Int?, destinationMasterIdx: Int) {
        self.sourceMasterIdx = sourceMasterIdx
        self.destinationMasterIdx = destinationMasterIdx
    }
}

// MARK: - TerminalKind

/// How a request's lifecycle ended. Raw values are the stable snake_case
/// names the snapshots serialize (mirror contract).
public enum TerminalKind: String, Codable, Sendable {
    case end = "end"
    case err = "err"
    case cancelled = "cancelled"
    case masterDied = "master_died"
}

// MARK: - RequestPhase

/// Live phase of a request. A terminated request never appears in the active
/// table — termination removes the entry (L7) and leaves a
/// `TerminatedSummary` in the recent ring instead.
public enum RequestPhase: String, Codable, Sendable {
    /// Registered; no flow frames observed yet.
    case created = "created"
    /// At least one flow frame has moved through the runtime.
    case streaming = "streaming"
}

// MARK: - FrameDirection

/// Direction of a recorded frame relative to this runtime.
public enum FrameDirection: Sendable {
    case inbound
    case outbound
}

// MARK: - StreamFlowStats

/// Per-stream flow accounting. Keyed by stream_id (nil = frames not tied to a
/// specific stream: REQ, END, ERR, LOG).
public struct StreamFlowStats: Codable, Sendable {
    public var framesIn: UInt64 = 0
    public var framesOut: UInt64 = 0
    public var bytesIn: UInt64 = 0
    public var bytesOut: UInt64 = 0
    public var chunksIn: UInt64 = 0
    public var chunksOut: UInt64 = 0
    /// Credits granted through this runtime minus chunks that consumed them.
    /// Diagnostic — the endpoints hold the authoritative windows.
    public var creditOutstanding: Int64 = 0
    /// Stream announced with unbounded=true (no length promise).
    public var unbounded: Bool = false
    /// STREAM_END observed.
    public var ended: Bool = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case framesIn = "frames_in"
        case framesOut = "frames_out"
        case bytesIn = "bytes_in"
        case bytesOut = "bytes_out"
        case chunksIn = "chunks_in"
        case chunksOut = "chunks_out"
        case creditOutstanding = "credit_outstanding"
        case unbounded
        case ended
    }
}

// MARK: - RequestState

/// Everything a routing runtime knows about one in-flight request.
public final class RequestState {
    public let routing: RoutingEntry
    /// Master index the response must return to (nil = external caller).
    public let origin: Int?
    /// Response delivery channel for externally-registered requests.
    /// Returns `false` when the receiving side is gone (channel closed) —
    /// the caller counts that as a `channel_closed` drop (L8).
    public let externalChannel: ((Frame) -> Bool)?
    /// Whether this is a cartridge-initiated peer invocation.
    public let isPeer: Bool
    /// Cap URN of the originating REQ, when known at registration — the
    /// request's nameable identity on the L8 surface (TEST7092). Set after
    /// init (mirrors Rust's `with_cap_urn` builder).
    public var capUrn: String?
    /// The process slot this request owns, released exactly once when the
    /// request terminates. `nil` for requests that took no permit (peer calls
    /// and relay-internal probes).
    public var admissionPermit: AdmissionPermit?
    /// Child peer calls spawned under this request (cancel cascade).
    public internal(set) var children: [RequestKey] = []
    public internal(set) var phase: RequestPhase = .created
    /// Per-stream flow stats (nil key = non-stream frames).
    public internal(set) var streams: [String?: StreamFlowStats] = [:]
    /// Monotonic timestamps (nanoseconds, `DispatchTime.uptimeNanoseconds`).
    public let createdAtNanos: UInt64
    public internal(set) var lastActivityNanos: UInt64

    public init(
        routing: RoutingEntry,
        origin: Int?,
        externalChannel: ((Frame) -> Bool)?,
        isPeer: Bool
    ) {
        let now = DispatchTime.now().uptimeNanoseconds
        self.routing = routing
        self.origin = origin
        self.externalChannel = externalChannel
        self.isPeer = isPeer
        self.createdAtNanos = now
        self.lastActivityNanos = now
    }

    func record(direction: FrameDirection, frame: Frame) {
        lastActivityNanos = DispatchTime.now().uptimeNanoseconds
        if frame.isFlowFrame() {
            phase = .streaming
        }
        var stats = streams[frame.streamId] ?? StreamFlowStats()
        let bytes = UInt64(frame.payload?.count ?? 0)
        switch direction {
        case .inbound:
            stats.framesIn += 1
            stats.bytesIn += bytes
            if frame.frameType == .chunk {
                stats.chunksIn += 1
                stats.creditOutstanding -= 1
            }
        case .outbound:
            stats.framesOut += 1
            stats.bytesOut += bytes
            if frame.frameType == .chunk {
                stats.chunksOut += 1
            }
        }
        switch frame.frameType {
        case .streamStart where frame.isUnbounded:
            stats.unbounded = true
        case .streamEnd:
            stats.ended = true
        case .credit:
            stats.creditOutstanding += Int64(frame.creditCount ?? 0)
        default:
            break
        }
        streams[frame.streamId] = stats
    }
}

// MARK: - TerminatedSummary

/// Summary of a finished request, retained in a bounded ring for stats.
public struct TerminatedSummary: Codable, Sendable {
    public let xid: String
    public let rid: String
    public let kind: TerminalKind
    public let isPeer: Bool
    /// Cap URN of the originating REQ, when known at registration — the
    /// request's nameable identity on the L8 surface (TEST7092).
    public let capUrn: String?
    public let lifetimeMs: UInt64
    public let framesIn: UInt64
    public let framesOut: UInt64
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    enum CodingKeys: String, CodingKey {
        case xid
        case rid
        case kind
        case isPeer = "is_peer"
        case capUrn = "cap_urn"
        case lifetimeMs = "lifetime_ms"
        case framesIn = "frames_in"
        case framesOut = "frames_out"
        case bytesIn = "bytes_in"
        case bytesOut = "bytes_out"
    }
}

// MARK: - RequestTable

/// The unified request table (L7): one entry per in-flight request, one
/// registration, one termination, plus the rid→xid secondary index and the
/// recently-terminated ring.
///
/// NOT internally synchronized — the owning runtime guards it with its own
/// lock, mirroring Rust's `RwLock<RequestTable>`.
public final class RequestTable {
    /// How many terminated-request summaries the ring retains.
    public static let recentTerminatedCap = 64

    private var entries: [RequestKey: RequestState] = [:]
    private var ridIndex: [MessageId: MessageId] = [:]
    private var recentTerminated: [TerminatedSummary] = []
    private var totalRegistered: UInt64 = 0
    private var terminatedByKind: [String: UInt64] = [:]

    public init() {}

    /// Register a request. A request is registered exactly once (L7):
    /// re-registering a live key, or a RID already indexed to a different
    /// XID, is a protocol violation and is rejected.
    public func register(_ key: RequestKey, _ state: RequestState) throws {
        if entries[key] != nil {
            throw RequestStateError.protocolViolation(
                "request (\(key.xid), \(key.rid)) already registered — a request is registered exactly once (L7)"
            )
        }
        if let existingXid = ridIndex[key.rid], existingXid != key.xid {
            throw RequestStateError.protocolViolation(
                "rid \(key.rid) already indexed to xid \(existingXid) — cannot re-index to xid \(key.xid) (L7)"
            )
        }
        ridIndex[key.rid] = key.xid
        entries[key] = state
        totalRegistered += 1
    }

    public func get(_ key: RequestKey) -> RequestState? {
        return entries[key]
    }

    public func contains(_ key: RequestKey) -> Bool {
        return entries[key] != nil
    }

    /// Look up the XID a bare RID belongs to (continuation frames arriving
    /// without routing IDs).
    public func xidForRid(_ rid: MessageId) -> MessageId? {
        return ridIndex[rid]
    }

    /// Terminate a request: remove the entry and its rid index atomically,
    /// record a summary, and return the removed state (children for cancel
    /// cascades, the external channel for final delivery). After this returns,
    /// zero state for the key remains (L7). Returns nil if the key is not
    /// live (already terminated — termination happens exactly once).
    @discardableResult
    public func terminate(_ key: RequestKey, kind: TerminalKind) -> RequestState? {
        guard let state = entries.removeValue(forKey: key) else {
            return nil
        }
        // Terminal state reached: give the cartridge its slot back. Exactly
        // once — the entry is removed above, so no other path can
        // double-release.
        state.admissionPermit?.release()
        // Only remove the rid index if it points at THIS xid — a re-used RID
        // under another XID (never valid per register, but defensive against
        // the impossible) must not lose its index.
        if ridIndex[key.rid] == key.xid {
            ridIndex.removeValue(forKey: key.rid)
        }

        var framesIn: UInt64 = 0
        var framesOut: UInt64 = 0
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        for stats in state.streams.values {
            framesIn += stats.framesIn
            framesOut += stats.framesOut
            bytesIn += stats.bytesIn
            bytesOut += stats.bytesOut
        }
        if recentTerminated.count == Self.recentTerminatedCap {
            recentTerminated.removeFirst()
        }
        let nowNanos = DispatchTime.now().uptimeNanoseconds
        let lifetimeMs = (nowNanos &- state.createdAtNanos) / 1_000_000
        recentTerminated.append(TerminatedSummary(
            xid: key.xid.description,
            rid: key.rid.description,
            kind: kind,
            isPeer: state.isPeer,
            capUrn: state.capUrn,
            lifetimeMs: lifetimeMs,
            framesIn: framesIn,
            framesOut: framesOut,
            bytesIn: bytesIn,
            bytesOut: bytesOut
        ))
        terminatedByKind[kind.rawValue, default: 0] += 1
        return state
    }

    /// Record a frame moving through the runtime for this request.
    /// Unknown keys are ignored — the caller decides whether that is a
    /// counted drop (it is, at the routing layer) — recording is accounting,
    /// not routing.
    public func recordFrame(_ key: RequestKey, direction: FrameDirection, frame: Frame) {
        entries[key]?.record(direction: direction, frame: frame)
    }

    /// Register a child peer call under its parent (cancel cascade).
    public func linkChild(parent: RequestKey, child: RequestKey) {
        entries[parent]?.children.append(child)
    }

    /// Keys of all live requests (for sweeps). Copied so the caller can
    /// mutate the table while iterating.
    public func keys() -> [RequestKey] {
        return Array(entries.keys)
    }

    /// Keys of live requests matching a predicate on their state.
    public func keysWhere(_ pred: (RequestState) -> Bool) -> [RequestKey] {
        return entries.filter { pred($0.value) }.map { $0.key }
    }

    public var count: Int {
        return entries.count
    }

    public var isEmpty: Bool {
        return entries.isEmpty
    }

    /// Serializable snapshot of the table: live requests + recent terminations
    /// + lifetime totals. Field names are the mirror contract.
    public func snapshot() -> RequestTableSnapshot {
        let nowNanos = DispatchTime.now().uptimeNanoseconds
        var active: [RequestSnapshot] = entries.map { key, state in
            RequestSnapshot(
                xid: key.xid.description,
                rid: key.rid.description,
                phase: state.phase,
                isPeer: state.isPeer,
                capUrn: state.capUrn,
                originMaster: state.origin,
                destinationMaster: state.routing.destinationMasterIdx,
                ageMs: (nowNanos &- state.createdAtNanos) / 1_000_000,
                idleMs: (nowNanos &- state.lastActivityNanos) / 1_000_000,
                children: UInt64(state.children.count),
                streams: state.streams.map { id, stats in
                    StreamSnapshot(streamId: id, stats: stats)
                }
            )
        }
        active.sort { $0.rid < $1.rid }
        return RequestTableSnapshot(
            active: active,
            recentTerminated: recentTerminated,
            totalRegistered: totalRegistered,
            terminatedByKind: terminatedByKind
        )
    }
}

// MARK: - Snapshot types

/// One stream's stats in a snapshot. Serializes `stream_id` alongside the
/// flattened `StreamFlowStats` fields, matching Rust's `#[serde(flatten)]`.
public struct StreamSnapshot: Codable, Sendable {
    public let streamId: String?
    public let stats: StreamFlowStats

    public init(streamId: String?, stats: StreamFlowStats) {
        self.streamId = streamId
        self.stats = stats
    }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Explicit-null tolerant: the encoder always writes the key.
        self.streamId = try c.decodeIfPresent(String.self, forKey: .streamId)
        self.stats = try StreamFlowStats(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Rust serializes `Option::None` as an explicit null — keep the key
        // present so the field-name contract holds for stream-less entries.
        try c.encode(streamId, forKey: .streamId)
        try stats.encode(to: encoder)
    }
}

/// One live request in a snapshot.
public struct RequestSnapshot: Codable, Sendable {
    public let xid: String
    public let rid: String
    public let phase: RequestPhase
    public let isPeer: Bool
    /// Cap URN of the originating REQ — the request's nameable identity
    /// (TEST7092). Absent when unknown, never invented.
    public let capUrn: String?
    public let originMaster: Int?
    public let destinationMaster: Int
    public let ageMs: UInt64
    public let idleMs: UInt64
    public let children: UInt64
    public let streams: [StreamSnapshot]

    enum CodingKeys: String, CodingKey {
        case xid
        case rid
        case phase
        case isPeer = "is_peer"
        case capUrn = "cap_urn"
        case originMaster = "origin_master"
        case destinationMaster = "destination_master"
        case ageMs = "age_ms"
        case idleMs = "idle_ms"
        case children
        case streams
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.xid = try c.decode(String.self, forKey: .xid)
        self.rid = try c.decode(String.self, forKey: .rid)
        self.phase = try c.decode(RequestPhase.self, forKey: .phase)
        self.isPeer = try c.decode(Bool.self, forKey: .isPeer)
        self.capUrn = try c.decodeIfPresent(String.self, forKey: .capUrn)
        self.originMaster = try c.decodeIfPresent(Int.self, forKey: .originMaster)
        self.destinationMaster = try c.decode(Int.self, forKey: .destinationMaster)
        self.ageMs = try c.decode(UInt64.self, forKey: .ageMs)
        self.idleMs = try c.decode(UInt64.self, forKey: .idleMs)
        self.children = try c.decode(UInt64.self, forKey: .children)
        self.streams = try c.decode([StreamSnapshot].self, forKey: .streams)
    }

    public init(
        xid: String,
        rid: String,
        phase: RequestPhase,
        isPeer: Bool,
        capUrn: String? = nil,
        originMaster: Int?,
        destinationMaster: Int,
        ageMs: UInt64,
        idleMs: UInt64,
        children: UInt64,
        streams: [StreamSnapshot]
    ) {
        self.xid = xid
        self.rid = rid
        self.phase = phase
        self.isPeer = isPeer
        self.capUrn = capUrn
        self.originMaster = originMaster
        self.destinationMaster = destinationMaster
        self.ageMs = ageMs
        self.idleMs = idleMs
        self.children = children
        self.streams = streams
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(xid, forKey: .xid)
        try c.encode(rid, forKey: .rid)
        try c.encode(phase, forKey: .phase)
        try c.encode(isPeer, forKey: .isPeer)
        // Rust serializes `Option::None` as an explicit null — keep the key
        // present so the field-name contract holds for unattributed requests.
        try c.encode(capUrn, forKey: .capUrn)
        // Explicit null for the external-caller case — the key is part of
        // the field-name contract (mirrors serde's Option serialization).
        try c.encode(originMaster, forKey: .originMaster)
        try c.encode(destinationMaster, forKey: .destinationMaster)
        try c.encode(ageMs, forKey: .ageMs)
        try c.encode(idleMs, forKey: .idleMs)
        try c.encode(children, forKey: .children)
        try c.encode(streams, forKey: .streams)
    }
}

/// Full table snapshot: the L8 observability surface for request state.
public struct RequestTableSnapshot: Codable, Sendable {
    public let active: [RequestSnapshot]
    public let recentTerminated: [TerminatedSummary]
    public let totalRegistered: UInt64
    public let terminatedByKind: [String: UInt64]

    enum CodingKeys: String, CodingKey {
        case active
        case recentTerminated = "recent_terminated"
        case totalRegistered = "total_registered"
        case terminatedByKind = "terminated_by_kind"
    }
}


// =============================================================================
// Admission control (mirrors Rust src/bifaci/request_state.rs).
//
// FIFO admission per cartridge install identity behind one relay master. The
// cartridge-side `handler_capacity` gate (CartridgeRuntime.swift) bounds what
// one process runs at a time; THIS gate bounds what the switch dispatches to
// it, so work queues in the switch instead of piling up unacknowledged on the
// wire.
// =============================================================================

/// How long a queued request waits for an admission target that has gone
/// unavailable before it is failed.
///
/// A cartridge disappearing from its host's inventory is not, by itself, a
/// reason to fail work that has not started: the process may be respawning, the
/// host may be re-publishing its roster, or a transient registry outage may
/// have briefly retired and then restored the install. 17.2 requires that
/// queued bodies are NOT assigned terminal failure from another body's process
/// loss and that "once a replacement instance advertises capacity, subsequent
/// queued work is admitted to that live instance" — this window is how long the
/// queue is held open for that replacement to appear.
///
/// It is a bound, not a retry: when it expires the wait fails hard and the
/// failure is classified `environment`, so a target that is genuinely gone
/// surfaces promptly instead of hanging the run.
public let admissionUnavailableGrace: TimeInterval = 60

/// A request could not take an admission slot. Carries the operator-facing
/// reason; the switch maps it to a cartridge-unavailable routing error.
public struct AdmissionError: Error, LocalizedError, Sendable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var errorDescription: String? { reason }
}

/// Stable admission identity for one cartridge behind one relay master.
public struct AdmissionKey: Hashable, Sendable {
    public let masterIdx: Int
    public let registryURL: String?
    public let channel: String
    public let id: String
    public let version: String
    public let sha256: String

    public init(
        masterIdx: Int,
        registryURL: String?,
        channel: String,
        id: String,
        version: String,
        sha256: String
    ) {
        self.masterIdx = masterIdx
        self.registryURL = registryURL
        self.channel = channel
        self.id = id
        self.version = version
        self.sha256 = sha256
    }
}

private final class AdmissionSlot {
    /// `nil` while the target is available; the instant it went unavailable
    /// otherwise. Kept as an instant rather than a flag so the grace window
    /// measures the OUTAGE, not the arrival time of each waiter — a request
    /// that queues late into an outage does not get a fresh window.
    var unavailableSince: Date?
    var capacity: UInt64 = 0
    var active: UInt64 = 0
    var queue: [UInt64] = []

    var available: Bool { unavailableSince == nil }

    /// Mark unavailable, preserving the start of an outage already in progress.
    func markUnavailable(_ now: Date) {
        if unavailableSince == nil { unavailableSince = now }
    }

    /// Remaining grace for an outage, or `nil` when available. Zero means the
    /// window has expired.
    func graceRemaining(_ now: Date, grace: TimeInterval) -> TimeInterval? {
        guard let since = unavailableSince else { return nil }
        return max(0, grace - now.timeIntervalSince(since))
    }
}

/// An actively owned process slot. Released exactly once.
public final class AdmissionPermit {
    private weak var controller: AdmissionController?
    private let key: AdmissionKey
    private var released = false
    private let lock = NSLock()

    fileprivate init(controller: AdmissionController, key: AdmissionKey) {
        self.controller = controller
        self.key = key
    }

    public func release() {
        lock.lock()
        let alreadyReleased = released
        released = true
        lock.unlock()
        if alreadyReleased { return }
        controller?.releaseSlot(key)
    }
}

/// FIFO admission shared by every request path in a RelaySwitch.
public final class AdmissionController: @unchecked Sendable {
    private let condition = NSCondition()
    private var slots: [AdmissionKey: AdmissionSlot] = [:]
    private var tickets: UInt64 = 0
    /// `admissionUnavailableGrace` in production. Tests shorten it to drive the
    /// expiry path without sleeping through a real minute.
    internal var grace: TimeInterval = admissionUnavailableGrace

    public init() {}

    /// Register or update a target's capacity. A configure is the target
    /// advertising itself: it ENDS any outage, which is what releases waiters
    /// queued through a respawn or a roster round-trip.
    public func configure(_ key: AdmissionKey, capacity: UInt64) {
        condition.lock()
        let slot = slots[key] ?? AdmissionSlot()
        slots[key] = slot
        slot.unavailableSince = nil
        slot.capacity = capacity
        condition.broadcast()
        condition.unlock()
    }

    /// Mark every slot of this master absent from the advertised set
    /// unavailable.
    public func reconcileMaster(_ masterIdx: Int, available: Set<AdmissionKey>) {
        let now = Date()
        condition.lock()
        for (key, slot) in slots where key.masterIdx == masterIdx && !available.contains(key) {
            slot.markUnavailable(now)
        }
        condition.broadcast()
        condition.unlock()
    }

    /// Mark every slot of this master unavailable (the master died).
    public func disableMaster(_ masterIdx: Int) {
        let now = Date()
        condition.lock()
        for (key, slot) in slots where key.masterIdx == masterIdx {
            slot.markUnavailable(now)
        }
        condition.broadcast()
        condition.unlock()
    }

    /// Take a FIFO admission slot for `key`, waiting for capacity.
    ///
    /// An UNAVAILABLE target does not fail the caller immediately. The request
    /// stays queued for `admissionUnavailableGrace` measured from the start of
    /// the outage, so a cartridge that is respawning — or that a transient
    /// registry outage briefly retired — resumes serving its queue instead of
    /// terminally failing every body waiting on it (17.2: one body's process
    /// loss must not terminate unrelated queued bodies). Only when the window
    /// expires does the wait fail, and it fails hard.
    ///
    /// `isCancelled`, when supplied, abandons the wait (the caller gave up);
    /// the ticket is removed so it cannot strand the queue behind a dead head.
    public func acquire(
        _ key: AdmissionKey,
        isCancelled: (() -> Bool)? = nil
    ) throws -> AdmissionPermit {
        condition.lock()
        defer { condition.unlock() }

        guard let slot = slots[key] else {
            throw AdmissionError("cartridge '\(key.id)' has no configured admission target")
        }
        let ticket = tickets
        tickets += 1
        // Queue even while unavailable: the loop below owns the grace window,
        // so a request arriving mid-outage gets the same treatment as one that
        // was already waiting when the outage began.
        slot.queue.append(ticket)

        while true {
            if isCancelled?() == true {
                removeTicketLocked(key, ticket)
                throw AdmissionError("admission wait for '\(key.id)' was cancelled")
            }
            guard let slot = slots[key] else {
                throw AdmissionError("admission slot for '\(key.id)' disappeared while queued")
            }
            let hasCapacity = slot.capacity == 0 || slot.active < slot.capacity
            if slot.available, hasCapacity, slot.queue.first == ticket {
                slot.queue.removeFirst()
                slot.active += 1
                condition.broadcast()
                return AdmissionPermit(controller: self, key: key)
            }
            let remaining = slot.graceRemaining(Date(), grace: grace)
            if let remaining, remaining <= 0 {
                // Outage outlived the window — the target is gone, not slow.
                removeTicketLocked(key, ticket)
                throw AdmissionError(
                    "cartridge '\(key.id)' was unavailable for longer than \(Int(grace))s "
                        + "while this request waited for capacity"
                )
            }
            // Available: wait for capacity. Mid-outage: wait no longer than
            // what is left of the window — a timeout there is not an error, the
            // next iteration re-reads the slot and decides. A cancellable wait
            // polls, because NSCondition cannot select on a cancel flag.
            var budget = remaining ?? .greatestFiniteMagnitude
            if isCancelled != nil { budget = min(budget, 0.02) }
            if budget == .greatestFiniteMagnitude {
                condition.wait()
            } else {
                _ = condition.wait(until: Date().addingTimeInterval(budget))
            }
        }
    }

    /// Drop a ticket so an abandoned waiter cannot strand the queue behind it.
    /// Caller must hold `condition`.
    private func removeTicketLocked(_ key: AdmissionKey, _ ticket: UInt64) {
        guard let slot = slots[key] else { return }
        if let idx = slot.queue.firstIndex(of: ticket) {
            slot.queue.remove(at: idx)
        }
        condition.broadcast()
    }

    fileprivate func releaseSlot(_ key: AdmissionKey) {
        condition.lock()
        if let slot = slots[key], slot.active > 0 {
            slot.active -= 1
        }
        condition.broadcast()
        condition.unlock()
    }
}
