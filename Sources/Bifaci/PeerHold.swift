import Foundation

// =============================================================================
// A peer request held while its provider is brought (14.2 §Peer requests no
// master serves).
//
// A cartridge's peer request names a cap. When no master behind the switch
// serves it, a switch that has a `PeerProvider` holds the request instead of
// refusing it: the REQ and every frame the caller sends for it after are kept,
// in the order they came, while the provider finds the cartridge that serves
// the cap, installs it if it is not installed, and hosts it. When a master
// serves the cap, the held frames are replayed in that order; when the
// provider cannot be brought, or not in time, the request ends with the ERR
// the provider words, naming the cartridge and what to do.
//
// Every decision about a held request — whether to hold it, what each frame
// does to the hold, how the hold ends — is the proved model's
// (formal/CapDAG/Bifaci/Hold.lean). This file keeps the held frames and asks
// it.
// =============================================================================

/// The ERR code of a held request that sent more than its hold keeps.
public let PEER_HOLD_OVERFLOW = "PEER_HOLD_OVERFLOW"
/// The ERR code of a held request whose provider was not found in time,
/// before it could say what it was bringing.
public let PEER_PROVIDER_TIMEOUT = "PEER_PROVIDER_TIMEOUT"

/// Why a held request ends without its provider: the ERR its caller is
/// answered with, in the vocabulary of every ERR (docs/failure-taxonomy.md).
/// The message is for the person who reads the run's failure: it names what
/// is missing and the command that brings it.
public struct PeerRefusal: Error, Equatable, Sendable {
    public let code: String
    public let attributionClass: AttributionClass
    public let message: String

    public init(code: String, attributionClass: AttributionClass, message: String) {
        self.code = code
        self.attributionClass = attributionClass
        self.message = message
    }

    /// The ERR answering request `rid` (routing id `xid`) with this refusal.
    func errFrame(rid: MessageId, xid: MessageId) -> Frame {
        var frame = Frame.err(id: rid, code: code, attributionClass: attributionClass, message: message)
        frame.routingId = xid
        return frame
    }
}

/// Bringing a provider, once `PeerProvider.provision` has found it.
public struct PeerProvision: Sendable {
    /// Brings it, blocking, and returns nil when a master behind the switch
    /// serves the cap: the cartridge is installed and its host attached. It
    /// runs to its end even when the hold it was started for does not wait
    /// that long, so a provider that took longer than one request could wait
    /// is there for the next.
    public let ready: @Sendable () -> PeerRefusal?
    /// What the caller is told when the hold's deadline passes before `ready`
    /// is done: the provider names the cartridge and the command that
    /// installs it outside a run.
    public let onExpiry: PeerRefusal

    public init(ready: @escaping @Sendable () -> PeerRefusal?, onExpiry: PeerRefusal) {
        self.ready = ready
        self.onExpiry = onExpiry
    }
}

/// What brings the master that serves a cap no master serves yet.
public protocol PeerProvider: AnyObject, Sendable {
    /// Find what provides `capUrn` — the cap a cartridge's peer request named
    /// — and how to bring it; or say why nothing can. Blocking.
    func provision(capUrn: String) -> Result<PeerProvision, PeerRefusal>
}

/// How much a hold may keep, and for how long.
public struct PeerHoldBound: Equatable, Sendable {
    /// Frames kept, the REQ among them.
    public var frames: UInt64
    /// Payload bytes kept.
    public var bytes: UInt64
    /// How long a request is held before it ends with the provider's
    /// `onExpiry`, or a refusal saying nothing was found in time.
    public var deadline: TimeInterval

    public init(frames: UInt64, bytes: UInt64, deadline: TimeInterval) {
        self.frames = frames
        self.bytes = bytes
        self.deadline = deadline
    }

    var model: ProtocolModel.HoldBound {
        ProtocolModel.holdBound(frames: frames, bytes: bytes)
    }
}

/// How bringing a held request's provider ended. A refused or expired one
/// carries the ERR its caller is answered with.
enum PeerSettlement {
    case provided
    case refused(PeerRefusal)
    case expired(PeerRefusal)

    var model: ProtocolModel.Bringing {
        switch self {
        case .provided: return .provided
        case .refused: return .refused
        case .expired: return .expired
        }
    }

    var refusal: PeerRefusal? {
        switch self {
        case .provided: return nil
        case .refused(let refusal), .expired(let refusal): return refusal
        }
    }
}

/// What one thread hands another across a semaphore: written before the
/// signal, read after the wait.
final class PeerHandoff<Value>: @unchecked Sendable {
    var value: Value?
}

/// One held request: who asked, the routing id its answers carry, its cap,
/// and its frames in the order they came — the REQ first.
struct HeldRequest {
    let sourceIdx: Int
    let xid: MessageId
    let capUrn: String
    var frames: [Frame]
    var held: ProtocolModel.HoldState
}

/// The held requests, by request id. Guarded by the switch's lock.
final class PeerHoldTable {
    let bound: PeerHoldBound
    private var held: [MessageId: HeldRequest] = [:]

    init(bound: PeerHoldBound) {
        self.bound = bound
    }

    private static func size(_ frame: Frame) -> UInt64 {
        UInt64(frame.payload?.count ?? 0)
    }

    /// Hold `req` — a peer REQ from master `sourceIdx`, already given its
    /// routing id. Returns the ERR the request ends with instead when the REQ
    /// alone is more than a hold may keep, else nil.
    func hold(sourceIdx: Int, req: Frame) -> Frame? {
        guard let xid = req.routingId, let capUrn = req.cap else {
            fatalError("BUG: a held REQ names its cap and has been given its routing id")
        }
        switch ProtocolModel.holdArrive(bound.model, ProtocolModel.holdInitial(), .req, size: Self.size(req)) {
        case .keep(let state):
            held[req.id] = HeldRequest(sourceIdx: sourceIdx, xid: xid, capUrn: capUrn, frames: [req], held: state)
            return nil
        case .overflow:
            return overflowRefusal(capUrn).errFrame(rid: req.id, xid: xid)
        case .cancel:
            fatalError("BUG: the model cancels only on a CANCEL frame, and this is a REQ")
        }
    }

    /// Whether `rid` from master `sourceIdx` is a held request.
    func isHeld(sourceIdx: Int, rid: MessageId) -> Bool {
        held[rid]?.sourceIdx == sourceIdx
    }

    /// A frame the caller sent for a held request: kept, and nil returned; or
    /// the request ends, and the ERR its caller is answered with is returned.
    func arrive(_ frame: Frame) -> Frame? {
        guard var request = held[frame.id] else {
            fatalError("BUG: arrive is asked only of a held request")
        }
        switch ProtocolModel.holdArrive(bound.model, request.held, frame.frameType, size: Self.size(frame)) {
        case .keep(let state):
            request.held = state
            request.frames.append(frame)
            held[frame.id] = request
            return nil
        case .overflow:
            held[frame.id] = nil
            return overflowRefusal(request.capUrn).errFrame(rid: frame.id, xid: request.xid)
        case .cancel:
            held[frame.id] = nil
            let reason = frame.cancelReason() ?? CancelReason()
            var err = Frame.err(
                id: frame.id,
                code: reason.terminalCode,
                attributionClass: reason.terminalClass,
                message: reason.terminalMessage
            )
            err.routingId = request.xid
            return err
        }
    }

    /// The end of bringing the provider of held request `rid`: the request,
    /// and — when it is not to be replayed — the ERR its caller is answered
    /// with. Nil when it is no longer held: it was cancelled, it overflowed,
    /// or its caller's master died.
    func settle(rid: MessageId, _ settlement: PeerSettlement) -> (request: HeldRequest, err: Frame?)? {
        guard let request = held.removeValue(forKey: rid) else { return nil }
        if ProtocolModel.replays(settlement.model) {
            return (request, nil)
        }
        guard let refusal = settlement.refusal else {
            fatalError("BUG: the model fails only a hold that was refused or expired")
        }
        return (request, refusal.errFrame(rid: rid, xid: request.xid))
    }

    /// Every request master `sourceIdx` asked for: it is gone, and so are
    /// they — nobody is left to answer. Returns how many it held.
    func forgetSource(_ sourceIdx: Int) -> Int {
        let before = held.count
        held = held.filter { $0.value.sourceIdx != sourceIdx }
        return before - held.count
    }

    private func overflowRefusal(_ capUrn: String) -> PeerRefusal {
        PeerRefusal(
            code: PEER_HOLD_OVERFLOW,
            attributionClass: .resource,
            message: "the peer call to \(capUrn) sent more than \(bound.frames) frames or \(bound.bytes) bytes " +
                "while the cartridge that provides it was being installed"
        )
    }
}
