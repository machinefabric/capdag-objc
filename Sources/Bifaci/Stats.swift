import Foundation

// =============================================================================
// Protocol observability primitives shared by every bifaci runtime.
//
// Two counter families, deliberately distinct because they mean opposite
// things:
//
// - `DropCounters` is the L8 substrate for frames lost to something going
//   WRONG: every dropped frame increments exactly one `DropReason` ×
//   `FrameType` counter — frames are never dropped silently, and a non-zero
//   drop total is always worth investigating.
// - `StragglerCounters` counts the benign teardown crossing: flow frames
//   that arrive after their request's terminal, which the protocol expects
//   (in-flight frames legally race END/ERR). Stragglers are moot by
//   protocol — nothing went wrong, no data was lost — and every stats
//   surface indicates them as benign, never as drops or failures.
//
// The counters are lock-protected so they can be bumped from writer
// threads, async tasks, and blocking contexts alike, and snapshot into
// Codable structs for the protocol stats surfaces.
// =============================================================================

/// Per-reason × per-frame-type dropped-frame counters (L8). Cheap to bump,
/// snapshot on demand. Drops mean something went wrong — the benign
/// post-terminal case is NOT recorded here (see `StragglerCounters`).
public final class DropCounters: @unchecked Sendable {
    private var counters: [DropReason: [FrameType: UInt64]] = [:]
    private let lock = NSLock()

    public init() {}

    /// Record one dropped frame of the given type. Returns the new total
    /// for that reason (across frame types).
    @discardableResult
    public func record(_ reason: DropReason, _ frameType: FrameType) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        var row = counters[reason] ?? [:]
        row[frameType] = (row[frameType] ?? 0) + 1
        counters[reason] = row
        return row.values.reduce(0, +)
    }

    /// Current count for one reason, summed across frame types.
    public func get(_ reason: DropReason) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return (counters[reason] ?? [:]).values.reduce(0, +)
    }

    /// Current count for one (reason, frame type) cell.
    public func getFrame(_ reason: DropReason, _ frameType: FrameType) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return counters[reason]?[frameType] ?? 0
    }

    /// Total drops across all reasons.
    public var total: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return counters.values.reduce(0) { $0 + $1.values.reduce(0, +) }
    }

    /// Serializable snapshot keyed by the stable snake_case reason names —
    /// the field-name contract mirrors replicate. `byReason` carries the
    /// per-reason totals; `byReasonFrameType` breaks each reason down by
    /// the dropped frame's type. Zero-count entries are omitted from both.
    public func snapshot() -> DropSnapshot {
        lock.lock()
        defer { lock.unlock() }
        var byReason: [String: UInt64] = [:]
        var byReasonFrameType: [String: [String: UInt64]] = [:]
        var total: UInt64 = 0
        for reason in DropReason.all {
            let row = counters[reason] ?? [:]
            let count = row.values.reduce(0, +)
            total += count
            if count > 0 {
                byReason[reason.rawValue] = count
                var byFrame: [String: UInt64] = [:]
                for (frameType, cell) in row where cell > 0 {
                    byFrame[frameType.asString] = cell
                }
                byReasonFrameType[reason.rawValue] = byFrame
            }
        }
        return DropSnapshot(total: total, byReason: byReason, byReasonFrameType: byReasonFrameType)
    }
}

/// Serializable view of the drop counters.
public struct DropSnapshot: Codable, Equatable, Sendable {
    public var total: UInt64
    /// reason name (snake_case) → count; zero-count reasons omitted.
    public var byReason: [String: UInt64]
    /// reason name → (frame type name → count); zero cells omitted.
    public var byReasonFrameType: [String: [String: UInt64]]

    enum CodingKeys: String, CodingKey {
        case total
        case byReason = "by_reason"
        case byReasonFrameType = "by_reason_frame_type"
    }

    public init(
        total: UInt64 = 0,
        byReason: [String: UInt64] = [:],
        byReasonFrameType: [String: [String: UInt64]] = [:]
    ) {
        self.total = total
        self.byReason = byReason
        self.byReasonFrameType = byReasonFrameType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decodeIfPresent(UInt64.self, forKey: .total) ?? 0
        byReason = try container.decodeIfPresent([String: UInt64].self, forKey: .byReason) ?? [:]
        byReasonFrameType =
            try container.decodeIfPresent([String: [String: UInt64]].self, forKey: .byReasonFrameType) ?? [:]
    }
}

/// Per-frame-type counters for BENIGN post-terminal stragglers.
///
/// A straggler is a flow frame that arrives after its request's terminal
/// (END/ERR) — the ordinary, protocol-legal teardown crossing (L13): a
/// callee may END before draining its input, a final CREDIT grant may cross
/// the terminal in flight. Nothing went wrong and no data was lost; the
/// frame is simply moot. Counted per frame type so surfaces can say exactly
/// what crossed ("late credit" vs "late chunk") — and always indicated as
/// benign, never as a drop or failure. (matches Rust StragglerCounters)
public final class StragglerCounters: @unchecked Sendable {
    private var counters: [FrameType: UInt64] = [:]
    private let lock = NSLock()

    public init() {}

    /// Record one benign post-terminal straggler. Returns the new total.
    @discardableResult
    public func record(_ frameType: FrameType) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        counters[frameType] = (counters[frameType] ?? 0) + 1
        return counters.values.reduce(0, +)
    }

    /// Current count for one frame type.
    public func get(_ frameType: FrameType) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return counters[frameType] ?? 0
    }

    /// Total stragglers across all frame types.
    public var total: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return counters.values.reduce(0, +)
    }

    /// Serializable snapshot keyed by the stable snake_case frame-type
    /// names; zero-count types omitted.
    public func snapshot() -> StragglerSnapshot {
        lock.lock()
        defer { lock.unlock() }
        var byFrameType: [String: UInt64] = [:]
        for (frameType, count) in counters where count > 0 {
            byFrameType[frameType.asString] = count
        }
        return StragglerSnapshot(total: counters.values.reduce(0, +), byFrameType: byFrameType)
    }
}

/// Serializable view of the straggler counters — benign by definition.
public struct StragglerSnapshot: Codable, Equatable, Sendable {
    public var total: UInt64
    /// frame type name (snake_case) → count; zero-count types omitted.
    public var byFrameType: [String: UInt64]

    enum CodingKeys: String, CodingKey {
        case total
        case byFrameType = "by_frame_type"
    }

    public init(total: UInt64 = 0, byFrameType: [String: UInt64] = [:]) {
        self.total = total
        self.byFrameType = byFrameType
    }
}

/// Terminated-flow set for the writer-side terminal gate (L4).
///
/// After a flow's END/ERR is written, any later flow frame for the same
/// FlowKey is a benign post-terminal straggler: it is suppressed and counted
/// as such (never a drop) instead of written.
/// The set is capacity-bounded FIFO — with seq state already removed at the
/// terminal, an evicted entry can only readmit a straggler that the receiving
/// side's reorder/routing layers then reject; the cap bounds memory on
/// long-lived cartridges, it does not change protocol correctness.
public final class TerminatedFlows: @unchecked Sendable {
    private var order: [FlowKey] = []
    private var set: Set<FlowKey> = []
    private let cap: Int
    private let lock = NSLock()

    public init(cap: Int) {
        precondition(cap > 0, "TerminatedFlows cap must be positive")
        self.cap = cap
        self.order.reserveCapacity(cap)
        self.set.reserveCapacity(cap)
    }

    /// Mark a flow terminated. Evicts the oldest entry at capacity.
    public func insert(_ key: FlowKey) {
        lock.lock()
        defer { lock.unlock() }
        if set.contains(key) {
            return
        }
        if order.count == cap {
            let oldest = order.removeFirst()
            set.remove(oldest)
        }
        order.append(key)
        set.insert(key)
    }

    /// Whether this flow has already seen its terminal frame.
    public func contains(_ key: FlowKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return set.contains(key)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return set.count
    }

    public var isEmpty: Bool {
        return count == 0
    }
}
