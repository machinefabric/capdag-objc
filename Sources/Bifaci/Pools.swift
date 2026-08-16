//
//  Pools.swift
//  Concurrency pools — the ONE capacity concept of the protocol.
//
//  A pool is a named concurrency domain on a cartridge process. Every
//  registered cap IS a pool of one, named by its canonical cap URN; the
//  reserved pool `poolAll` contains every cap (it is what the deleted
//  scalar `handler_capacity` used to be); the manifest may declare further
//  named pools over subsets of caps. A cap's POOL CHAIN — its own
//  singleton pool, every declared pool containing it, then `all` — is the
//  set of domains a dispatch must be admitted through. Queues lead to
//  pools: each request waits in its cap's singleton-pool queue; shared
//  pools own no queue of their own.
//
//  Three numbers per pool, one effective value:
//    - declared   — the manifest's shipped default (the cartridge's).
//    - configured — the operator's number (starts = declared; persisted by
//      the engine's cartridge configuration store).
//    - available  — OPTIONAL cartridge self-report: what the process can
//      serve right now from its OWN state. Absent means static: the
//      normal, fully-supported case.
//
//  effective = min(configured, available) with 0-as-unlimited treated as
//  infinity inside the min and absent available treated as infinity.
//
//  On the wire the pool-state map rides as JSON bytes in frame meta —
//  exactly the transport the manifest itself uses — under the `metaPools`
//  key (HELLO and every heartbeat reply) and, host→cartridge, the
//  `metaDesiredCapacities` key on a heartbeat probe. The roster's
//  runtime_stats carries the same map. (matches Rust bifaci::pools)
//

import Foundation
import CapDAG

/// The reserved pool containing every cap. Always exists; default
/// capacity 0 (unlimited). The exact replacement of the deleted scalar
/// handler_capacity. (matches Rust POOL_ALL)
public let poolAll = "all"

/// Frame-meta key carrying a JSON-encoded pool-state map (HELLO, every
/// heartbeat reply, and the roster's runtime stats).
public let metaPools = "pools"

/// Frame-meta key on a heartbeat PROBE carrying a JSON-encoded map of pool
/// name → desired configured value.
public let metaDesiredCapacities = "desired_capacities"

/// Unlimited, as a capacity value. Everywhere a capacity is read, 0 means
/// "no limit" — never "zero slots".
public let capacityUnlimited: UInt64 = 0

/// `min(configured, available)` under the 0-as-unlimited convention.
/// (matches Rust effective_capacity)
public func effectiveCapacity(configured: UInt64, available: UInt64?) -> UInt64 {
    let c = configured == capacityUnlimited ? UInt64.max : configured
    let a: UInt64
    if let available, available != capacityUnlimited {
        a = available
    } else {
        a = UInt64.max
    }
    let effective = min(c, a)
    return effective == UInt64.max ? capacityUnlimited : effective
}

/// One pool's full state. The same shape everywhere: manifest-derived
/// declarations, heartbeat replies, roster stats, and the clients'
/// cartridge views. (matches Rust PoolState)
public struct PoolState: Codable, Hashable, Sendable {
    /// The manifest's shipped default. 0 = unlimited.
    public var declared: UInt64
    /// The operator's number. Starts equal to `declared`. 0 = unlimited.
    public var configured: UInt64
    /// The cartridge's self-reported current limit. Absent = static (the
    /// cartridge never self-adjusts this pool) and is treated as unlimited
    /// inside `effective`.
    public var available: UInt64?
    /// Requests currently being served in this pool.
    public var active: UInt64
    /// Requests currently queued against this pool. For shared pools this
    /// counts waiters whose OWN pool has room but this pool does not.
    public var queued: UInt64
    /// Member caps (canonical URNs). Singleton pools omit the list — the
    /// pool's name IS its one member.
    public var caps: [String]

    enum CodingKeys: String, CodingKey {
        case declared, configured, available, active, queued, caps
    }

    public init(
        declared: UInt64 = 0,
        configured: UInt64 = 0,
        available: UInt64? = nil,
        active: UInt64 = 0,
        queued: UInt64 = 0,
        caps: [String] = []
    ) {
        self.declared = declared
        self.configured = configured
        self.available = available
        self.active = active
        self.queued = queued
        self.caps = caps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        declared = try c.decode(UInt64.self, forKey: .declared)
        configured = try c.decode(UInt64.self, forKey: .configured)
        available = try c.decodeIfPresent(UInt64.self, forKey: .available)
        active = try c.decode(UInt64.self, forKey: .active)
        queued = try c.decode(UInt64.self, forKey: .queued)
        caps = try c.decodeIfPresent([String].self, forKey: .caps) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(declared, forKey: .declared)
        try c.encode(configured, forKey: .configured)
        // Absent-vs-present on `available` is the static-vs-self-limited
        // distinction and must never collapse.
        try c.encodeIfPresent(available, forKey: .available)
        try c.encode(active, forKey: .active)
        try c.encode(queued, forKey: .queued)
        if !caps.isEmpty {
            try c.encode(caps, forKey: .caps)
        }
    }

    /// A declared pool at rest: configured = declared, nothing active,
    /// no self-report. (matches Rust PoolState::declared)
    public static func declaredAtRest(_ declared: UInt64, caps: [String]) -> PoolState {
        PoolState(declared: declared, configured: declared, caps: caps)
    }

    /// The effective admission bound: `min(configured, available)` with 0
    /// meaning unlimited on either input and on the output, and an absent
    /// `available` treated as unlimited.
    public func effective() -> UInt64 {
        effectiveCapacity(configured: configured, available: available)
    }
}

/// The full pool-state map of one cartridge process, keyed by pool name (a
/// canonical cap URN for singletons, a declared pool name, or `all`).
/// (matches Rust PoolStates)
public typealias PoolStates = [String: PoolState]

/// The host→cartridge desired-configured map delivered on a heartbeat
/// probe. (matches Rust DesiredCapacities)
public typealias DesiredCapacities = [String: UInt64]

public enum PoolError: Error, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}

/// The manifest's pool DECLARATIONS: shared-pool memberships plus a
/// capacities map whose keys are pool names uniformly (a canonical cap
/// URN, a declared pool name, or `all`). (matches Rust PoolDeclarations)
public struct PoolDeclarations: Codable, Equatable, Sendable {
    /// Declared shared pools: name → member caps (canonical URNs).
    public var pools: [String: [String]]
    /// Declared capacities by pool name. Absent = 0 = unlimited.
    public var capacities: [String: UInt64]

    enum CodingKeys: String, CodingKey {
        case pools, capacities
    }

    public init(pools: [String: [String]] = [:], capacities: [String: UInt64] = [:]) {
        self.pools = pools
        self.capacities = capacities
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pools = try c.decodeIfPresent([String: [String]].self, forKey: .pools) ?? [:]
        capacities = try c.decodeIfPresent([String: UInt64].self, forKey: .capacities) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !pools.isEmpty {
            try c.encode(pools, forKey: .pools)
        }
        if !capacities.isEmpty {
            try c.encode(capacities, forKey: .capacities)
        }
    }

    public var isEmpty: Bool { pools.isEmpty && capacities.isEmpty }

    /// Validate the declarations against the set of declared caps and
    /// canonicalize every cap reference. Hard errors, never coercion
    /// (matches Rust PoolDeclarations::validated):
    /// - a shared pool named `all` or parsing as a cap URN;
    /// - a pool member or capacity key that names no declared cap
    ///   (capacity keys may also name a declared pool or `all`);
    /// - a cap listed twice in one pool.
    public func validated(declaredCaps: [String]) throws -> PoolDeclarations {
        var canonical: [String] = []
        for raw in declaredCaps {
            let urn = try CSCapUrn.fromString(raw)
            canonical.append(urn.toString())
        }

        func canonicalize(_ raw: String) throws -> String {
            let canon: String
            do {
                canon = try CSCapUrn.fromString(raw).toString()
            } catch {
                throw PoolError.invalid(
                    "pool cap reference '\(raw)' is not a valid cap URN: \(error)")
            }
            guard canonical.contains(canon) else {
                throw PoolError.invalid(
                    "pool cap reference '\(raw)' names no cap declared by this manifest")
            }
            return canon
        }

        var validatedPools: [String: [String]] = [:]
        for name in pools.keys.sorted() {
            let members = pools[name]!
            if name == poolAll {
                throw PoolError.invalid(
                    "pool name '\(poolAll)' is reserved for the implicit all-caps pool")
            }
            if (try? CSCapUrn.fromString(name)) != nil {
                throw PoolError.invalid(
                    "pool name '\(name)' parses as a cap URN — cap URNs name the implicit singleton pools and cannot be redeclared"
                )
            }
            if members.isEmpty {
                throw PoolError.invalid("pool '\(name)' declares no member caps")
            }
            var canonMembers: [String] = []
            for member in members {
                let canon = try canonicalize(member)
                if canonMembers.contains(canon) {
                    throw PoolError.invalid(
                        "pool '\(name)' lists cap '\(canon)' more than once")
                }
                canonMembers.append(canon)
            }
            validatedPools[name] = canonMembers
        }

        var validatedCapacities: [String: UInt64] = [:]
        for key in capacities.keys.sorted() {
            let value = capacities[key]!
            let canonKey: String
            if key == poolAll || validatedPools[key] != nil {
                canonKey = key
            } else {
                do {
                    canonKey = try canonicalize(key)
                } catch {
                    throw PoolError.invalid(
                        "capacity key '\(key)' is neither '\(poolAll)', a declared pool, nor a declared cap: \(error)"
                    )
                }
            }
            if validatedCapacities[canonKey] != nil {
                throw PoolError.invalid(
                    "capacity for pool '\(canonKey)' is declared more than once (two spellings of one cap URN?)"
                )
            }
            validatedCapacities[canonKey] = value
        }

        return PoolDeclarations(pools: validatedPools, capacities: validatedCapacities)
    }

    /// Materialize the full declared pool-state map for a cap set: one
    /// singleton pool per cap, every declared shared pool, and `all`.
    /// `self` must already be validated against the same cap set.
    /// (matches Rust PoolDeclarations::declared_states)
    public func declaredStates(declaredCaps: [String]) -> PoolStates {
        var states: PoolStates = [:]
        for cap in declaredCaps {
            states[cap] = PoolState.declaredAtRest(
                capacities[cap] ?? capacityUnlimited, caps: [])
        }
        for (name, members) in pools {
            states[name] = PoolState.declaredAtRest(
                capacities[name] ?? capacityUnlimited, caps: members)
        }
        states[poolAll] = PoolState.declaredAtRest(
            capacities[poolAll] ?? capacityUnlimited, caps: declaredCaps)
        return states
    }

    /// The pool CHAIN of one cap, in admission order: its singleton pool,
    /// every declared pool containing it, then `all`. `cap` must be the
    /// canonical URN string. (matches Rust chain_for)
    public func chainFor(cap: String) -> [String] {
        var chain = [cap]
        for name in pools.keys.sorted() where pools[name]!.contains(cap) {
            chain.append(name)
        }
        chain.append(poolAll)
        return chain
    }
}

/// The chain of one cap over a MATERIALIZED state map (roster / heartbeat
/// truth): the singleton pool, every pool listing the cap as a member,
/// then `all`. Order: singleton, declared pools in sorted order, `all`.
/// (matches Rust chain_from_states)
public func chainFromStates(_ states: PoolStates, cap: String) -> [String] {
    var chain: [String] = []
    if states[cap] != nil {
        chain.append(cap)
    }
    for name in states.keys.sorted() where name != poolAll && name != cap {
        if states[name]!.caps.contains(cap) {
            chain.append(name)
        }
    }
    if states[poolAll] != nil {
        chain.append(poolAll)
    }
    return chain
}

/// Encode a pool-state map for frame meta (JSON bytes — the manifest's own
/// transport). (matches Rust encode_pool_states)
public func encodePoolStates(_ states: PoolStates) -> Data {
    guard let data = try? JSONEncoder().encode(states) else {
        fatalError("pool states are always JSON-encodable")
    }
    return data
}

/// Decode a pool-state map from frame meta. A malformed map is a protocol
/// error at the caller's boundary — never partially read.
/// (matches Rust decode_pool_states)
public func decodePoolStates(_ data: Data) throws -> PoolStates {
    do {
        return try JSONDecoder().decode(PoolStates.self, from: data)
    } catch {
        throw PoolError.invalid("malformed pool-state map: \(error)")
    }
}

/// Encode the desired-configured map for a heartbeat probe.
public func encodeDesired(_ desired: DesiredCapacities) -> Data {
    guard let data = try? JSONEncoder().encode(desired) else {
        fatalError("desired capacities are always JSON-encodable")
    }
    return data
}

/// Decode the desired-configured map from a heartbeat probe.
public func decodeDesired(_ data: Data) throws -> DesiredCapacities {
    do {
        return try JSONDecoder().decode(DesiredCapacities.self, from: data)
    } catch {
        throw PoolError.invalid("malformed desired-capacities map: \(error)")
    }
}
