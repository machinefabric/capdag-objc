import Foundation
import CapDAGFormal
import LungoKit

// =============================================================================
// The decisions of the wire protocol's state machines — flow control, the
// order of a flow's frames, a request's lifecycle, admission through
// concurrency pools — are code generated from the proved model in ../../formal
// (CapDAG/Bifaci). This file is where this package's own types meet the
// model's; everything else here keeps what the model has no use for: the keyed
// containers, the waiting and waking, the I/O.
// =============================================================================

/// The model's answer, or a trap: a call into the generated program fails only
/// when its runtime does, never on a value this package built.
private func decided<T>(_ ask: () throws -> T) -> T {
    do {
        return try ask()
    } catch {
        fatalError("bifaci: the model could not decide: \(error)")
    }
}

/// A number out of the model that was put in as a `UInt64`, or counts
/// something this process holds in memory.
private func count(_ n: LungoNat) -> UInt64 {
    guard let value = n.uint64 else {
        fatalError("bifaci: the model's count \(n) does not fit a UInt64")
    }
    return value
}

extension FrameType {
    /// The model's frame type for this one. The mapping is by hand; that each
    /// type is the one the model means by its wire number is TEST12375.
    fileprivate var model: CapDAGFormal.FrameType {
        switch self {
        case .hello: return .hello
        case .req: return .req
        case .chunk: return .chunk
        case .end: return .fin
        case .log: return .log
        case .err: return .err
        case .heartbeat: return .heartbeat
        case .streamStart: return .streamStart
        case .streamEnd: return .streamEnd
        case .relayNotify: return .relayNotify
        case .relayState: return .relayState
        case .cancel: return .cancel
        case .credit: return .credit
        case .closeStream: return .closeStream
        }
    }

    /// Whether frames of this type are part of a request's flow: numbered in
    /// order, reordered at a relay boundary, and gated behind the flow's end.
    /// HELLO, HEARTBEAT, the relay frames, CANCEL, CREDIT and CLOSE_STREAM are
    /// not — CREDIT in particular must never wait behind a gap in the flow it
    /// is unblocking. The model's decision.
    public var isFlow: Bool { ProtocolModel.facts[self]!.flow }

    /// Whether a frame of this type ends its flow: END or ERR. The model's
    /// decision.
    public var isTerminal: Bool { ProtocolModel.facts[self]!.terminal }
}

/// The proved model's decisions, in this package's own types.
enum ProtocolModel {
    typealias Gate = CapDAGFormal.Gate
    typealias Window = CapDAGFormal.Window
    typealias Reorder = CapDAGFormal.Reorder
    typealias Pools = CapDAGFormal.State
    typealias Emitted = CapDAGFormal.Emitted
    typealias Violation = CapDAGFormal.Violation

    // MARK: Frame types

    /// What the model says of each frame type, asked once: it is asked of
    /// every frame that moves.
    fileprivate static let facts: [FrameType: (flow: Bool, terminal: Bool)] = {
        var facts: [FrameType: (flow: Bool, terminal: Bool)] = [:]
        for frameType in FrameType.all {
            facts[frameType] = (
                flow: decided { try CapDAGFormal.isFlow(frameType.model) },
                terminal: decided { try CapDAGFormal.isTerminal(frameType.model) }
            )
        }
        return facts
    }()

    /// The wire number the model gives the type this one is mapped to.
    static func code(of frameType: FrameType) -> UInt64 {
        count(decided { try CapDAGFormal.code(frameType.model) })
    }

    // MARK: Credit

    /// The window two ends start every stream with: the smaller proposal; nil
    /// when it would be zero.
    static func negotiate(ours: UInt64, theirs: UInt64) -> UInt64? {
        decided { try CapDAGFormal.negotiate(LungoNat(ours), LungoNat(theirs)) }.map(count)
    }

    static func gateOpened(_ window: UInt64) -> Gate {
        decided { try CapDAGFormal.gateOpened(LungoNat(window)) }
    }

    enum Acquired {
        case acquired(Gate)
        case wait
        case closed(reason: String)
    }

    static func acquire(_ gate: Gate, _ n: UInt64) -> Acquired {
        switch decided({ try CapDAGFormal.acquire(gate, LungoNat(n)) }) {
        case .acquired(let gate): return .acquired(gate)
        case .wait: return .wait
        case .closed(let reason): return .closed(reason: reason)
        }
    }

    static func grant(_ gate: Gate, _ n: UInt64) -> Gate {
        decided { try CapDAGFormal.grant(gate, LungoNat(n)) }
    }

    static func close(_ gate: Gate, reason: String) -> Gate {
        decided { try CapDAGFormal.close(gate, reason) }
    }

    /// A gate's available credit. It may have been granted past a `UInt64`:
    /// the largest `UInt64` then.
    static func available(_ gate: Gate) -> UInt64 {
        gate.available.uint64 ?? UInt64.max
    }

    /// Which of a request's streams a grant is for: the one it names, or —
    /// naming none — the only one there is. The outer nil: none.
    static func grantTarget(streams: [String?], named: String?) -> String?? {
        decided { try CapDAGFormal.grantTarget(streams, named) }
    }

    static func windowOpened(_ window: UInt64) -> Window {
        decided { try CapDAGFormal.windowOpened(LungoNat(window)) }
    }

    /// The window after one more chunk arrived; nil when the chunk is beyond
    /// what was granted.
    static func arrive(_ window: Window) -> Window? {
        switch decided({ try CapDAGFormal.windowArrive(window) }) {
        case .accepted(let window): return window
        case .violation: return nil
        }
    }

    private static func granted(_ step: CapDAGFormal.Granted) -> (Window, UInt64) {
        (step.window, count(step.grant))
    }

    static func consume(_ window: Window) -> (Window, UInt64) {
        granted(decided { try CapDAGFormal.consume(window) })
    }

    static func flush(_ window: Window) -> (Window, UInt64) {
        granted(decided { try CapDAGFormal.flush(window) })
    }

    static func continued(_ window: Window) -> (Window, UInt64) {
        granted(decided { try CapDAGFormal.continued(window) })
    }

    static func remaining(_ window: Window) -> UInt64 {
        window.remaining.uint64 ?? UInt64.max
    }

    static func pending(_ window: Window) -> UInt64 {
        count(window.pending)
    }

    // MARK: Flow order

    static func reorderStart() -> Reorder {
        decided { try CapDAGFormal.start() }
    }

    static func expected(_ order: Reorder) -> UInt64 {
        count(order.expected)
    }

    enum Arrived {
        /// In order: these numbers are handed on, in this order.
        case deliver(Reorder, seqs: [UInt64])
        case hold(Reorder)
        case stale
        case duplicate
        case overflow
    }

    static func accept(_ order: Reorder, seq: UInt64, limit: Int) -> Arrived {
        switch decided({ try CapDAGFormal.accept(order, LungoNat(seq), LungoNat(UInt64(limit))) }) {
        case .deliver(let flow, let seqs): return .deliver(flow, seqs: seqs.map(count))
        case .hold(let flow): return .hold(flow)
        case .stale: return .stale
        case .duplicate: return .duplicate
        case .overflow: return .overflow
        }
    }

    /// The first thing wrong with a flow's frames, in order; nil when they
    /// are in order.
    static func check(_ frames: [Emitted]) -> Violation? {
        decided { try CapDAGFormal.check(frames) }
    }

    static func emittedChunk(stream: String, index: UInt64) -> Emitted {
        .chunk(stream: stream, index: LungoNat(index))
    }

    static func emittedStreamEnd(stream: String, count: UInt64?) -> Emitted {
        .streamEnd(stream: stream, count: count.map { LungoNat($0) })
    }

    // MARK: Request lifecycle

    enum Writing {
        /// The frame is written; `ends`: writing it ends its flow.
        case send(ends: Bool)
        /// The flow is over: the frame is a benign straggler.
        case suppress
    }

    static func write(over: Bool, _ frameType: FrameType) -> Writing {
        switch decided({ try CapDAGFormal.write(over, frameType.model) }) {
        case .send(let ends): return .send(ends: ends)
        case .suppress: return .suppress
        }
    }

    static func terminalKind(of frameType: FrameType) -> TerminalKind? {
        switch decided({ try CapDAGFormal.terminalOf(frameType.model) }) {
        case .none: return nil
        case .some(.finished): return .end
        case .some(.failed): return .err
        case .some(.cancelled): return .cancelled
        case .some(.masterDied): return .masterDied
        }
    }

    static func disposition(live: Bool, endedLately: Bool) -> Disposition {
        switch decided({ try CapDAGFormal.dispose(live, endedLately) }) {
        case .route: return .route
        case .straggler: return .straggler
        case .noRoute: return .noRoute
        }
    }

    static func phase(after phase: RequestPhase, frame frameType: FrameType) -> RequestPhase {
        let before: CapDAGFormal.Phase = phase == .streaming ? .streaming : .created
        switch decided({ try CapDAGFormal.after(before, frameType.model) }) {
        case .created: return .created
        case .streaming: return .streaming
        }
    }

    /// A stream's credit ledger after a frame: one less for a chunk, more by
    /// a grant, and by nothing else.
    static func ledger(remaining: Int64, frame frameType: FrameType, granted: UInt64) -> Int64 {
        let after = decided {
            try CapDAGFormal.ledger(LungoInt(remaining), frameType.model, LungoNat(granted))
        }
        guard let value = after.int64 else {
            fatalError("bifaci: stream credit ledger \(after) does not fit an Int64")
        }
        return value
    }

    // MARK: Pools

    static func effective(configured: UInt64, available: UInt64?) -> UInt64 {
        count(decided {
            try CapDAGFormal.effective(LungoNat(configured), available.map { LungoNat($0) })
        })
    }

    static func advertised(running: Bool, pool: String, configured: UInt64, available: UInt64?) -> UInt64 {
        count(decided {
            try CapDAGFormal.advertised(
                running, pool, LungoNat(configured), available.map { LungoNat($0) })
        })
    }

    /// A cap's chain: its own pool, the shared pools it is a member of (in the
    /// order given), then `all`.
    static func chain(cap: String, shared: [(String, [String])]) -> [String] {
        decided { try CapDAGFormal.chain(cap, shared) }
    }

    static func poolsEmpty() -> Pools {
        decided { try CapDAGFormal.empty() }
    }

    static func setCapacity(_ pools: Pools, _ name: String, _ capacity: UInt64) -> Pools {
        decided { try CapDAGFormal.setCapacity(pools, name, LungoNat(capacity)) }
    }

    enum Arrival {
        case admitted(Pools)
        case queued(Pools, ticket: UInt64, position: Int)
        case unknownPool(String)
    }

    private static func arrival(_ arrival: CapDAGFormal.PoolsArrival) -> Arrival {
        switch arrival {
        case .admitted(let state): return .admitted(state)
        case .queued(let state, let ticket, let position):
            return .queued(state, ticket: count(ticket), position: Int(count(position)))
        case .unknownPool(let name): return .unknownPool(name)
        }
    }

    /// A request arrives: admitted at once when its whole chain has room and
    /// nobody in line could go instead, and in line otherwise.
    static func arrive(_ pools: Pools, chain: [String]) -> Arrival {
        arrival(decided { try CapDAGFormal.stateArrive(pools, chain) })
    }

    /// A request arrives and waits its turn, whatever room there is.
    static func join(_ pools: Pools, chain: [String]) -> Arrival {
        arrival(decided { try CapDAGFormal.join(pools, chain) })
    }

    /// Admit this ticket, if it is the one that is next.
    static func admit(_ pools: Pools, ticket: UInt64) -> Pools? {
        decided { try CapDAGFormal.admit(pools, LungoNat(ticket)) }
    }

    /// Admit whoever is next, if anyone can be: its ticket, and the pools
    /// after.
    static func admitNext(_ pools: Pools) -> (ticket: UInt64, pools: Pools)? {
        decided { try CapDAGFormal.admitNext(pools) }.map { (ticket: count($0.0.ticket), pools: $0.1) }
    }

    static func leave(_ pools: Pools, ticket: UInt64) -> Pools {
        decided { try CapDAGFormal.leave(pools, LungoNat(ticket)) }
    }

    static func release(_ pools: Pools, chain: [String]) -> Pools {
        decided { try CapDAGFormal.release(pools, chain) }
    }

    static func heldBack(_ pools: Pools, _ name: String) -> UInt64 {
        count(decided { try CapDAGFormal.heldBack(pools, name) })
    }

    /// Each pool and how many requests hold a slot in it, in the pools' order.
    static func active(_ pools: Pools) -> [(name: String, active: UInt64)] {
        pools.pools.map { (name: $0.name, active: count($0.active)) }
    }

    /// The tickets in line, in order of arrival.
    static func waiting(_ pools: Pools) -> [UInt64] {
        pools.queue.map { count($0.ticket) }
    }

    enum Patience {
        case unbounded
        case atMost(milliseconds: UInt64)
        case exhausted
    }

    /// How much longer a request may wait, given how long its cartridge has
    /// been unavailable (nil: it is available) and how long an outage is
    /// waited out — both in milliseconds.
    static func patience(unavailableFor: UInt64?, grace: UInt64) -> Patience {
        switch decided({
            try CapDAGFormal.patience(unavailableFor.map { LungoNat($0) }, LungoNat(grace))
        }) {
        case .unbounded: return .unbounded
        case .atMost(let remaining): return .atMost(milliseconds: count(remaining))
        case .exhausted: return .exhausted
        }
    }
}
