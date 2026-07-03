import Foundation

// =============================================================================
// Credit-based per-stream flow control (protocol v3).
//
// One credit = permission to send one CHUNK frame. A sender starts each stream
// with the negotiated `initial_credit` window and must wait when the window is
// exhausted; the receiving endpoint replenishes it with CREDIT frames as it
// consumes chunks (L9/L10 in `docs/capdag-improvement/03-protocol-v3-design.md`).
//
// `CreditGate` mirrors the Rust reference's mutex + notify pair with a lock +
// continuation queue, per the v3 portability mapping for Swift. The observable
// contract is identical everywhere: `acquire` waits until credit is available
// or the gate closes; `close` releases all waiters with an error; grants never
// block.
// =============================================================================

/// Error thrown to a credit waiter when its gate closes (request terminal,
/// cancellation, or connection death) — the waiter must stop sending.
public struct CreditClosed: Error, Equatable, Sendable {
    /// Human-readable reason the gate closed (e.g. "CANCELLED", "END").
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

extension CreditClosed: LocalizedError {
    public var errorDescription: String? {
        return "credit gate closed: \(reason)"
    }
}

/// A replenishable per-stream credit window for one sender.
///
/// - `acquire(1)` before each CHUNK: returns immediately while the window is
///   open, waits when it is exhausted.
/// - `grant(n)` when a CREDIT frame arrives: wakes waiters.
/// - `close(reason)` on request terminal/cancel: releases all waiters with
///   `CreditClosed` (L13 — a credit-blocked sender must never hang).
public final class CreditGate: @unchecked Sendable {
    private let lock = NSLock()
    /// Chunks the sender may still emit before waiting.
    private var availableCredit: UInt64
    /// Set when the gate is closed; all current and future acquires fail.
    private var closedReason: String?
    /// Async waiters parked until a grant or close arrives. Each is resumed
    /// exactly once: with success on grant (the waiter then re-checks the
    /// window) or by throwing `CreditClosed` on close.
    private var waiters: [CheckedContinuation<Void, Error>] = []

    public init(initialCredit: UInt64) {
        self.availableCredit = initialCredit
    }

    /// Acquire `n` credits, waiting if the window is exhausted.
    /// Throws `CreditClosed` if the gate closes before (or while) waiting.
    public func acquire(_ n: UInt64) async throws {
        while true {
            lock.lock()
            if let reason = closedReason {
                lock.unlock()
                throw CreditClosed(reason: reason)
            }
            if availableCredit >= n {
                availableCredit -= n
                lock.unlock()
                return
            }
            // Exhausted: park until a grant or close arrives. The lock is
            // held from the check to the waiter registration so a grant/close
            // that lands in between cannot be missed; the continuation closure
            // runs synchronously before suspension and releases it.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    /// Non-waiting acquire. Returns false when the window is exhausted.
    /// Throws `CreditClosed` if the gate is closed.
    public func tryAcquire(_ n: UInt64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let reason = closedReason {
            throw CreditClosed(reason: reason)
        }
        if availableCredit >= n {
            availableCredit -= n
            return true
        }
        return false
    }

    /// Blocking acquire for non-async contexts (writer threads, FFI).
    /// Spins on tryAcquire with a short park; the park interval is invisible
    /// to the protocol (only wall-clock throughput of a blocked sender).
    public func blockingAcquire(_ n: UInt64) throws {
        while true {
            if try tryAcquire(n) {
                return
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    /// Replenish the window by `n` chunks and wake all waiters.
    /// Grants after close are no-ops.
    public func grant(_ n: UInt64) {
        lock.lock()
        if closedReason != nil {
            lock.unlock()
            return // grants after close are no-ops
        }
        let (sum, overflow) = availableCredit.addingReportingOverflow(n)
        availableCredit = overflow ? UInt64.max : sum
        let woken = waiters
        waiters.removeAll()
        lock.unlock()
        for continuation in woken {
            continuation.resume()
        }
    }

    /// Close the gate: all current and future acquires fail with `CreditClosed`.
    public func close(reason: String) {
        lock.lock()
        if closedReason == nil {
            closedReason = reason
        }
        let effectiveReason = closedReason!
        let woken = waiters
        waiters.removeAll()
        lock.unlock()
        for continuation in woken {
            continuation.resume(throwing: CreditClosed(reason: effectiveReason))
        }
    }

    /// Currently available credit (diagnostic/stats).
    public var available: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return availableCredit
    }

    /// Whether the gate has been closed.
    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closedReason != nil
    }
}

/// Routes inbound CREDIT frames to the gates of the streams they credit.
///
/// Keyed by (rid, streamId). A CREDIT frame with no streamId credits the
/// request's sole/default stream: it matches the request's single registered
/// gate when exactly one exists.
public final class CreditRouter: @unchecked Sendable {
    private struct GateKey: Hashable {
        let rid: MessageId
        let streamId: String?
    }

    private var gates: [GateKey: CreditGate] = [:]
    private let lock = NSLock()

    public init() {}

    /// Register a gate for a stream a local sender is about to write.
    public func register(rid: MessageId, streamId: String?, gate: CreditGate) {
        lock.lock()
        defer { lock.unlock() }
        gates[GateKey(rid: rid, streamId: streamId)] = gate
    }

    /// Remove and close every gate belonging to a request (terminal/cancel).
    /// Waiters blocked on those gates are released with `CreditClosed` (L13).
    public func closeRequest(rid: MessageId, reason: String) {
        lock.lock()
        let keys = gates.keys.filter { $0.rid == rid }
        var closing: [CreditGate] = []
        for key in keys {
            if let gate = gates.removeValue(forKey: key) {
                closing.append(gate)
            }
        }
        lock.unlock()
        for gate in closing {
            gate.close(reason: reason)
        }
    }

    /// Deliver a CREDIT frame's grant to the matching gate.
    /// Returns false when no gate matches (request finished or the sender is
    /// not credit-registered) — a correct no-op, since grants only unblock.
    @discardableResult
    public func grant(_ frame: Frame) -> Bool {
        guard frame.frameType == .credit, let credits = frame.creditCount else {
            return false
        }
        lock.lock()
        var matched: CreditGate?
        if let exact = gates[GateKey(rid: frame.id, streamId: frame.streamId)] {
            matched = exact
        } else if frame.streamId == nil {
            // No streamId on the grant: match the request's sole gate if exactly one.
            let requestGates = gates.filter { $0.key.rid == frame.id }
            if requestGates.count == 1 {
                matched = requestGates.first!.value
            }
        }
        lock.unlock()
        guard let gate = matched else {
            return false
        }
        gate.grant(credits)
        return true
    }

    /// Number of registered gates (diagnostic/stats).
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return gates.count
    }

    public var isEmpty: Bool {
        return count == 0
    }
}
