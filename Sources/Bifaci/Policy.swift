import Foundation
@preconcurrency import SwiftCBOR

// What the host allows the cartridges it serves to do (12.2 §Policy).
//
// The engine holds the live policy and gives it to the RelaySwitch; a Policy
// frame carries it through every relay to each host, which keeps the latest
// and sends it to each of its cartridges after the handshake and on every
// change. A cartridge runtime keeps the latest in a `LivePolicy`, and a
// handler reads it through `NetworkAccess` before each call it makes to the
// network — never a copy taken when the request was dispatched, so a change
// to `offline` stops a running download or stream at its next call.
// (matches Rust bifaci::policy)

/// The wire key a Policy frame's meta names the network policy by.
public let POLICY_META_NETWORK = "network"

/// The code a call the policy does not allow fails with.
public let NETWORK_POLICY_CODE = "NETWORK_POLICY"

/// The code of a call refused because no policy has been given at all — a
/// defect, not the operator's decision.
public let NETWORK_POLICY_UNSET_CODE = "NETWORK_POLICY_UNSET"

/// How far a cartridge may reach on the network.
public enum NetworkPolicy: String, Sendable, Equatable {
    /// Nothing beyond this machine.
    case offline = "offline"
    /// Third-party services and MachineFabric's own, never analytics.
    case noTelemetry = "no_telemetry"
    /// The same, and analytics.
    case full = "full"

    /// The policy's wire word.
    public var asString: String { rawValue }

    /// The policy a wire word names; nil for any other word.
    public static func fromWire(_ word: String) -> NetworkPolicy? { NetworkPolicy(rawValue: word) }

    /// Whether this policy lets a call of this reach be made.
    public func allows(_ reach: Reach) -> Bool {
        switch self {
        case .offline: return false
        case .noTelemetry: return reach != .telemetry
        case .full: return true
        }
    }
}

/// What a call to the network reaches, which is what the policy decides on.
public enum Reach: Sendable, Equatable {
    /// A service MachineFabric does not run.
    case thirdParty
    /// A service MachineFabric runs for the product to work.
    case ourServices
    /// Analytics and crash reports.
    case telemetry

    var described: String {
        switch self {
        case .thirdParty: return "an outside service"
        case .ourServices: return "MachineFabric's services"
        case .telemetry: return "analytics"
        }
    }
}

/// Everything a Policy frame says.
public struct HostPolicy: Sendable, Equatable {
    public let network: NetworkPolicy

    public init(network: NetworkPolicy) {
        self.network = network
    }
}

/// A call that was not made. The operator's own setting refusing the work is
/// `user` — never retried, never tolerated (17.2); a call refused because no
/// policy was ever given is a defect, `internal`.
public struct NetworkRefused: ClassifiedFailure, CustomStringConvertible, Sendable, Equatable {
    /// The policy that refused it; nil when no policy had been given.
    public let policy: NetworkPolicy?
    public let reach: Reach

    public var failureCode: String { policy == nil ? NETWORK_POLICY_UNSET_CODE : NETWORK_POLICY_CODE }
    public var attributionClass: AttributionClass { policy == nil ? .internal : .user }
    public var failureMessage: String {
        guard let policy else {
            return "no network policy has been given to this cartridge, so nothing may reach \(reach.described)"
        }
        return "the network policy is '\(policy.asString)', which does not allow reaching \(reach.described)"
    }
    public var description: String { failureMessage }
}

/// The latest policy a runtime was given, shared with every handler it runs.
/// Empty until the first Policy frame arrives.
public final class LivePolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var policy: HostPolicy?

    public init(_ policy: HostPolicy? = nil) {
        self.policy = policy
    }

    /// Replace the policy; every reader sees it at its next read.
    public func set(_ policy: HostPolicy) {
        lock.lock(); defer { lock.unlock() }
        self.policy = policy
    }

    /// The policy in force, nil before the first one was given.
    public var current: HostPolicy? {
        lock.lock(); defer { lock.unlock() }
        return policy
    }
}

/// A handler's view of the live network policy: cheap to pass to the code
/// that opens connections, which asks it before every call.
public struct NetworkAccess: Sendable {
    private let live: LivePolicy

    public init(_ live: LivePolicy) {
        self.live = live
    }

    /// Throws `NetworkRefused` unless a call of this reach may be made now,
    /// under the policy in force at this moment.
    public func allow(_ reach: Reach) throws {
        guard let current = live.current else {
            throw NetworkRefused(policy: nil, reach: reach)
        }
        guard current.network.allows(reach) else {
            throw NetworkRefused(policy: current.network, reach: reach)
        }
    }

    /// The policy in force now, nil before the first one was given.
    public var policy: NetworkPolicy? { live.current?.network }
}

extension Frame {
    /// Create a POLICY frame: what the host allows its cartridges to do now
    /// (12.2 §Policy). (matches Rust Frame::policy)
    public static func policy(_ policy: HostPolicy) -> Frame {
        var frame = Frame(frameType: .policy, id: .uint(0))
        frame.meta = [POLICY_META_NETWORK: .utf8String(policy.network.asString)]
        return frame
    }

    /// The policy a POLICY frame carries: nil for any other frame type. A
    /// Policy frame whose meta.network is missing or names no policy throws;
    /// decode refuses such a frame, so a decoded Policy always reads.
    /// (matches Rust Frame::host_policy)
    public func hostPolicy() throws -> HostPolicy? {
        guard frameType == .policy else { return nil }
        guard let raw = meta?[POLICY_META_NETWORK] else {
            throw FrameError.protocolError("POLICY frame missing required meta.\(POLICY_META_NETWORK)")
        }
        guard case .utf8String(let word) = raw else {
            throw FrameError.protocolError("POLICY frame's meta.\(POLICY_META_NETWORK) is not text: \(raw)")
        }
        guard let network = NetworkPolicy.fromWire(word) else {
            throw FrameError.protocolError("POLICY frame's meta.\(POLICY_META_NETWORK) names no network policy: '\(word)'")
        }
        return HostPolicy(network: network)
    }
}
