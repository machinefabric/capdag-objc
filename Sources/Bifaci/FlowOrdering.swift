import Foundation

// MARK: - FlowKey

/// Composite key identifying a frame flow for seq ordering.
/// Absence of routingId (XID) is a valid separate flow from presence of routingId.
public struct FlowKey: Hashable, Sendable {
    public let rid: MessageId
    public let xid: MessageId?

    public init(rid: MessageId, xid: MessageId?) {
        self.rid = rid
        self.xid = xid
    }

    /// Extract flow key from a frame.
    public static func fromFrame(_ frame: Frame) -> FlowKey {
        return FlowKey(rid: frame.id, xid: frame.routingId)
    }
}

// MARK: - SeqAssigner

/// Assigns monotonically increasing seq numbers per request ID.
/// Used at output stages (writer threads) to ensure each flow's frames
/// carry a contiguous, gap-free seq sequence starting at 0.
///
/// Non-flow frames (Hello, Heartbeat, RelayNotify, RelayState) are skipped
/// and their seq stays at 0.
/// Assigns monotonically increasing seq numbers per FlowKey (RID + optional XID).
/// Keyed by FlowKey to match ReorderBuffer's key space exactly:
/// (RID=A, XID=nil) and (RID=A, XID=5) are separate flows with independent counters.
public final class SeqAssigner: @unchecked Sendable {
    private var counters: [FlowKey: UInt64] = [:]
    private let lock = NSLock()

    public init() {}

    /// Assign the next seq number to a frame.
    /// Non-flow frames are left unchanged (seq stays 0).
    public func assign(_ frame: inout Frame) {
        guard frame.isFlowFrame() else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        let key = FlowKey.fromFrame(frame)
        let counter = counters[key, default: 0]
        frame.seq = counter
        counters[key] = counter + 1
    }

    /// Remove tracking for a flow (call after END/ERR delivery).
    public func remove(_ key: FlowKey) {
        lock.lock()
        defer { lock.unlock() }
        counters.removeValue(forKey: key)
    }
}

// MARK: - ReorderBuffer

/// Per-flow state for the reorder buffer: the model's picture of the flow —
/// the number expected next and the numbers held — and the held frames
/// themselves.
private class FlowState {
    var order = ProtocolModel.reorderStart()
    var buffer: [UInt64: Frame] = [:]
}

/// Reorder buffer for validating and reordering frames at relay boundaries.
/// Keyed by FlowKey (RID + optional XID). Each flow tracks expected seq
/// and buffers out-of-order frames until gaps are filled.
///
/// What an arriving frame does — delivered with those it releases, held, or
/// refused — is the proved model's decision (`formal/CapDAG/Bifaci/Flow.lean`):
/// frames are handed on in the order they were written, and none is lost.
///
/// Protocol errors:
/// - Stale/duplicate seq (frame.seq < expected_seq)
/// - Buffer overflow (buffered frames exceed max_buffer_per_flow)
public final class ReorderBuffer: @unchecked Sendable {
    private var flows: [FlowKey: FlowState] = [:]
    private let maxBufferPerFlow: Int
    private let lock = NSLock()

    public init(maxBufferPerFlow: Int) {
        self.maxBufferPerFlow = maxBufferPerFlow
    }

    /// Accept a frame into the reorder buffer.
    /// Returns an array of frames ready for delivery (in seq order).
    /// Non-flow frames bypass reordering and are returned immediately.
    public func accept(_ frame: Frame) throws -> [Frame] {
        // Non-flow frames bypass reordering
        if !frame.isFlowFrame() {
            return [frame]
        }

        lock.lock()
        defer { lock.unlock() }

        let key = FlowKey.fromFrame(frame)
        let state = flows[key] ?? FlowState()
        if flows[key] == nil {
            flows[key] = state
        }

        let expected = ProtocolModel.expected(state.order)
        switch ProtocolModel.accept(state.order, seq: frame.seq, limit: maxBufferPerFlow) {
        case .deliver(let order, let seqs):
            // In order: this frame, then every held frame it releases.
            state.buffer[frame.seq] = frame
            var ready: [Frame] = []
            for seq in seqs {
                guard let held = state.buffer.removeValue(forKey: seq) else {
                    fatalError("BUG: seq \(seq) is delivered but not held")
                }
                ready.append(held)
            }
            state.order = order
            return ready

        case .hold(let order):
            state.buffer[frame.seq] = frame
            state.order = order
            return []

        case .duplicate:
            throw FrameError.protocolError(
                "Stale/duplicate seq: seq \(frame.seq) already buffered (expected >= \(expected))"
            )

        case .overflow:
            throw FrameError.protocolError(
                "Reorder buffer overflow: flow has \(state.buffer.count) buffered frames (max \(maxBufferPerFlow)), " +
                "expected seq \(expected) but got seq \(frame.seq)"
            )

        case .stale:
            throw FrameError.protocolError(
                "Stale/duplicate seq: expected >= \(expected) but got \(frame.seq)"
            )
        }
    }

    /// Remove flow state after terminal frame delivery (END/ERR).
    public func cleanupFlow(_ key: FlowKey) {
        lock.lock()
        defer { lock.unlock() }
        flows.removeValue(forKey: key)
    }
}
