//
//  PoolsTests.swift
//  Concurrency-pool model tests (Pools.swift) — shared-range TEST numbers
//  with the Rust reference (TEST1520–TEST1523).
//

import XCTest
@testable import Bifaci
import CapDAG

final class PoolsTests: XCTestCase {
    private func caps(_ urns: [String]) throws -> [String] {
        try urns.map { try CSCapUrn.fromString($0).toString() }
    }

    // TEST1520: effective capacity is min(configured, available) under the
    // 0-as-unlimited convention, with absent available treated as unlimited
    // — the one formula every admission decision reduces to.
    func test1520_effective_capacity_min_semantics() {
        XCTAssertEqual(effectiveCapacity(configured: 0, available: nil), 0, "unlimited stays unlimited")
        XCTAssertEqual(effectiveCapacity(configured: 4, available: nil), 4, "absent available is a free pass")
        XCTAssertEqual(effectiveCapacity(configured: 4, available: 0), 4, "available 0 is unlimited, not zero slots")
        XCTAssertEqual(effectiveCapacity(configured: 0, available: 2), 2, "self-limit binds an unlimited configured")
        XCTAssertEqual(effectiveCapacity(configured: 4, available: 1), 1, "the smaller bound wins")
        XCTAssertEqual(effectiveCapacity(configured: 1, available: 4), 1, "in either direction")
    }

    // TEST1521: a cap is a pool of one and `all` always exists — the
    // declared state map materializes every singleton, every declared pool,
    // and `all`, with capacities resolved by pool name uniformly.
    func test1521_declared_states_materialize_every_pool() throws {
        let declaredCaps = try caps([
            "cap:generate;in=\"media:enc=utf-8\";out=\"media:enc=utf-8\"",
            "cap:embed;in=\"media:enc=utf-8\";out=\"media:embeddings\"",
        ])
        let generate = declaredCaps[0]
        let embed = declaredCaps[1]
        let declarations = try PoolDeclarations(
            pools: ["gpu": [generate, embed]],
            capacities: [generate: 1, "gpu": 1, poolAll: 8]
        ).validated(declaredCaps: declaredCaps)
        let states = declarations.declaredStates(declaredCaps: declaredCaps)

        XCTAssertEqual(states.count, 4, "two singletons + gpu + all")
        XCTAssertEqual(states[generate]?.declared, 1)
        XCTAssertEqual(states[generate]?.configured, 1, "configured starts at declared")
        XCTAssertEqual(states[embed]?.declared, 0, "undeclared singleton is unlimited")
        XCTAssertEqual(states["gpu"]?.declared, 1)
        XCTAssertEqual(states["gpu"]?.caps, [generate, embed])
        XCTAssertEqual(states[poolAll]?.declared, 8)
        XCTAssertEqual(states[poolAll]?.caps.count, 2, "all contains every cap")

        // The chain: singleton, declared pools containing the cap, all.
        XCTAssertEqual(declarations.chainFor(cap: generate), [generate, "gpu", poolAll])
        // And the same chain derived from the materialized states.
        XCTAssertEqual(chainFromStates(states, cap: generate), [generate, "gpu", poolAll])
    }

    // TEST1522: pool declarations are validated hard — reserved name, a
    // pool named like a cap URN, an unknown member, a duplicate member, and
    // an unknown capacity key are each refused with the offender named.
    func test1522_pool_declaration_validation_refuses_illegal_shapes() throws {
        let declaredCaps = try caps(["cap:generate;in=\"media:enc=utf-8\";out=\"media:enc=utf-8\""])
        let generate = declaredCaps[0]

        XCTAssertThrowsError(
            try PoolDeclarations(pools: [poolAll: [generate]]).validated(declaredCaps: declaredCaps)
        ) { error in
            XCTAssertTrue("\(error)".contains("reserved"))
        }
        XCTAssertThrowsError(
            try PoolDeclarations(pools: [generate: [generate]]).validated(declaredCaps: declaredCaps)
        ) { error in
            XCTAssertTrue("\(error)".contains("parses as a cap URN"))
        }
        XCTAssertThrowsError(
            try PoolDeclarations(pools: ["gpu": ["cap:absent;in=\"media:\";out=\"media:\""]])
                .validated(declaredCaps: declaredCaps)
        ) { error in
            XCTAssertTrue("\(error)".contains("names no cap"))
        }
        XCTAssertThrowsError(
            try PoolDeclarations(pools: ["gpu": [generate, generate]]).validated(declaredCaps: declaredCaps)
        ) { error in
            XCTAssertTrue("\(error)".contains("more than once"))
        }
        XCTAssertThrowsError(
            try PoolDeclarations(capacities: ["warp": 3]).validated(declaredCaps: declaredCaps)
        ) { error in
            XCTAssertTrue("\(error)".contains("neither"))
        }
    }

    // TEST1523: the wire codec round-trips the full map — including the
    // absent-vs-present distinction on `available`, which is the
    // static-vs-self-limited distinction and must never collapse.
    func test1523_pool_state_wire_round_trip() throws {
        let singleton = "cap:x;in=\"media:\";out=\"media:\""
        let states: PoolStates = [
            singleton: PoolState(declared: 2, configured: 4, available: 1, active: 1, queued: 3),
            poolAll: PoolState.declaredAtRest(0, caps: [singleton]),
        ]

        let decoded = try decodePoolStates(encodePoolStates(states))
        XCTAssertEqual(decoded, states)
        XCTAssertEqual(decoded[singleton]?.effective(), 1)
        XCTAssertNil(decoded[poolAll]?.available, "static stays static")

        XCTAssertThrowsError(try decodePoolStates(Data("not json".utf8)))

        let desired: DesiredCapacities = [poolAll: 6]
        XCTAssertEqual(try decodeDesired(encodeDesired(desired)), desired)
    }
}
