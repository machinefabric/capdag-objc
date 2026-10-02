import Foundation

// =============================================================================
// Credit-based per-stream flow control (protocol v4).
//
// One credit = permission to send one CHUNK frame. A sender starts each stream
// with the negotiated `initial_credit` window and must wait when the window is
// exhausted; the receiving endpoint replenishes it with CREDIT frames as it
// consumes chunks (L9/L10 in the normative bifaci protocol documentation).
//
// `CreditGate` mirrors the Rust reference's mutex + notify pair with a lock +
// continuation queue, per the v4 portability mapping for Swift. The observable
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

/// The credit window two ends start every stream with (L9): the smaller of
/// the two proposals, decided by the proved model. `nil` when the window would
/// be zero — under a zero window no chunk could be sent and, with nothing
/// consumed, none would ever be granted: every stream would stop at its first
/// chunk, for good.
public func negotiateInitialCredit(ours: UInt64, theirs: UInt64) -> UInt64? {
    ProtocolModel.negotiate(ours: ours, theirs: theirs)
}

/// A replenishable per-stream credit window for one sender.
///
/// - `acquire(1)` before each CHUNK: returns immediately while the window is
///   open, waits when it is exhausted.
/// - `grant(n)` when a CREDIT frame arrives: wakes waiters.
/// - `close(reason)` on request terminal/cancel: releases all waiters with
///   `CreditClosed` (L13 — a credit-blocked sender must never hang).
///
/// What an acquire, a grant and a close do to the window is the proved
/// model's decision (`formal/CapDAG/Bifaci/Credit.lean`); the gate keeps the
/// window and wakes whoever waits on it.
public final class CreditGate: @unchecked Sendable {
    private let lock = NSLock()
    private var state: ProtocolModel.Gate
    /// Async waiters parked until a grant or close arrives. Each is resumed
    /// exactly once with `false`, and then loops and asks again; the `Bool`
    /// payload also carries the fast path: a continuation resumed
    /// synchronously with `true` inside the registration closure acquired
    /// without waiting.
    private var waiters: [CheckedContinuation<Bool, Error>] = []

    public init(initialCredit: UInt64) {
        self.state = ProtocolModel.gateOpened(initialCredit)
    }

    /// Ask the model for `n` credits. Caller holds `lock`.
    private func acquireLocked(_ n: UInt64) throws -> Bool {
        switch ProtocolModel.acquire(state, n) {
        case .acquired(let gate):
            state = gate
            return true
        case .wait:
            return false
        case .closed(let reason):
            throw CreditClosed(reason: reason)
        }
    }

    /// Acquire `n` credits, waiting if the window is exhausted.
    /// Throws `CreditClosed` if the gate closes before (or while) waiting.
    ///
    /// Swift concurrency forbids holding an `NSLock` across a suspension
    /// point, so the locked check-or-park runs entirely inside the
    /// continuation's synchronous registration closure: the window check and
    /// the waiter registration happen under one lock hold (a racing
    /// grant/close cannot be missed), and the fast path resumes the
    /// continuation synchronously with `true` (acquired). A grant or a close
    /// resumes parked waiters with `false` — they loop and ask again.
    public func acquire(_ n: UInt64) async throws {
        while true {
            let acquired: Bool = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Bool, Error>) in
                lock.lock()
                do {
                    if try acquireLocked(n) {
                        lock.unlock()
                        continuation.resume(returning: true)
                        return
                    }
                } catch {
                    lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
                waiters.append(continuation)
                lock.unlock()
            }
            if acquired {
                return
            }
        }
    }

    /// Non-waiting acquire. Returns false when the window is exhausted.
    /// Throws `CreditClosed` if the gate is closed.
    public func tryAcquire(_ n: UInt64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return try acquireLocked(n)
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

    /// Wake every parked waiter to ask again. Caller holds `lock`, which this
    /// releases.
    private func wakeAllAndUnlock() {
        let woken = waiters
        waiters.removeAll()
        lock.unlock()
        for continuation in woken {
            continuation.resume(returning: false)
        }
    }

    /// Replenish the window by `n` chunks and wake all waiters.
    /// Grants after close are no-ops.
    public func grant(_ n: UInt64) {
        lock.lock()
        state = ProtocolModel.grant(state, n)
        wakeAllAndUnlock()
    }

    /// Close the gate: all current and future acquires fail with `CreditClosed`.
    public func close(reason: String) {
        lock.lock()
        state = ProtocolModel.close(state, reason: reason)
        wakeAllAndUnlock()
    }

    /// Currently available credit (diagnostic/stats).
    public var available: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return ProtocolModel.available(state)
    }

    /// Whether the gate has been closed.
    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.closed != nil
    }
}

/// The receiving end of one stream's credit window: what is left of what the
/// sender was granted, and what this end has consumed and not yet granted
/// back.
///
/// - `arrive()` for each CHUNK: `false` is a CREDIT_VIOLATION — the sender
///   sent past its window (L12).
/// - `consumed()` once the chunk is consumed: the grant that is now due, `0`
///   when the batch has not built up yet (L10: half the window, at least 1).
/// - `flush()` when nothing more will be consumed for a while: whatever is
///   pending is granted, so a sender never waits on a batch that will not
///   fill.
/// - `continued()` for a chunk that only continues an item: granted back at
///   once, since nothing can consume it before the item is whole.
///
/// Every decision is the proved model's (`formal/CapDAG/Bifaci/Credit.lean`).
public final class CreditWindow: @unchecked Sendable {
    private let lock = NSLock()
    private var state: ProtocolModel.Window

    public init(initialCredit: UInt64) {
        self.state = ProtocolModel.windowOpened(initialCredit)
    }

    /// Account for one arriving CHUNK. `false`: the chunk is beyond the
    /// granted window, and the window is unchanged.
    public func arrive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let accepted = ProtocolModel.arrive(state) else {
            return false
        }
        state = accepted
        return true
    }

    private func granted(_ step: (ProtocolModel.Window, UInt64)) -> UInt64 {
        state = step.0
        return step.1
    }

    /// Account for one consumed chunk; the grant now due (0: none yet).
    public func consumed() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return granted(ProtocolModel.consume(state))
    }

    /// The grant for everything consumed and not yet granted (0: nothing is
    /// pending).
    public func flush() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return granted(ProtocolModel.flush(state))
    }

    /// Account for a chunk that continues an item; the grant that gives it
    /// back at once.
    public func continued() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return granted(ProtocolModel.continued(state))
    }

    /// How many more chunks the sender may send before a grant.
    public var remaining: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return ProtocolModel.remaining(state)
    }

    /// How many chunks were consumed and not yet granted back.
    public var pending: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return ProtocolModel.pending(state)
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
        // Which of the request's streams the grant is for is the model's
        // decision: the one it names, or — naming none — the only one there is.
        lock.lock()
        let streams = gates.keys.filter { $0.rid == frame.id }.map { $0.streamId }
        var matched: CreditGate?
        if let target = ProtocolModel.grantTarget(streams: streams, named: frame.streamId) {
            matched = gates[GateKey(rid: frame.id, streamId: target)]
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
