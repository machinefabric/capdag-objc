import Foundation

// =============================================================================
// Protocol observability primitives shared by every bifaci runtime.
//
// `DropCounters` is the L8 substrate: every frame a runtime drops increments
// exactly one `DropReason` counter — frames are never dropped silently. The
// counters are lock-protected so they can be bumped from writer threads,
// async tasks, and blocking contexts alike, and snapshot into Codable
// structs for the protocol stats surfaces.
// =============================================================================

/// Per-reason dropped-frame counters (L8). Cheap to bump, snapshot on demand.
public final class DropCounters: @unchecked Sendable {
    private var counters: [DropReason: UInt64] = [:]
    private let lock = NSLock()

    public init() {}

    /// Record one dropped frame. Returns the new total for that reason.
    @discardableResult
    public func record(_ reason: DropReason) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let count = (counters[reason] ?? 0) + 1
        counters[reason] = count
        return count
    }

    /// Current count for one reason.
    public func get(_ reason: DropReason) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return counters[reason] ?? 0
    }

    /// Total drops across all reasons.
    public var total: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return counters.values.reduce(0, +)
    }

    /// Serializable snapshot keyed by the stable snake_case reason names —
    /// the field-name contract mirrors replicate. Zero-count reasons are omitted.
    public func snapshot() -> DropSnapshot {
        lock.lock()
        defer { lock.unlock() }
        var byReason: [String: UInt64] = [:]
        var total: UInt64 = 0
        for reason in DropReason.all {
            let count = counters[reason] ?? 0
            total += count
            if count > 0 {
                byReason[reason.rawValue] = count
            }
        }
        return DropSnapshot(total: total, byReason: byReason)
    }
}

/// Serializable view of the drop counters.
public struct DropSnapshot: Codable, Equatable, Sendable {
    public var total: UInt64
    /// reason name (snake_case) → count; zero-count reasons omitted.
    public var byReason: [String: UInt64]

    enum CodingKeys: String, CodingKey {
        case total
        case byReason = "by_reason"
    }

    public init(total: UInt64 = 0, byReason: [String: UInt64] = [:]) {
        self.total = total
        self.byReason = byReason
    }
}

/// Terminated-flow set for the writer-side terminal gate (L4).
///
/// After a flow's END/ERR is written, any later flow frame for the same
/// FlowKey is post-terminal: it is dropped and counted instead of written.
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
