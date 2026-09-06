import XCTest
@testable import CapDAG

final class CartridgeCapsTests: XCTestCase {

    private func makeCap(op: String) throws -> CSCap {
        let builder = CSCapUrnBuilder()
        builder.inSpec("media:void")
        builder.outSpec("media:void")
        builder.tag("op", value: op)
        let urn = try builder.build()
        return CSCap(urn: urn,
                     title: op,
                     aliases: [op],
                     description: nil,
                     documentation: nil,
                     metadata: [:],
                     args: [],
                     output: nil,
                     metadataJSON: nil)
    }

    /// Round-trip: adding a CSCap produces a urn string that parses back to a
    /// CSCapUrn whose `accepts(_:)` predicate holds against itself
    /// (reflexivity of the accepts relation).
    func test0001_AddCapRoundTripUrnViaTaggedPredicates() throws {
        let cap = try makeCap(op: "search")

        let caps = CSCartridgeCaps()
        caps.addCap(cap)

        let urns = caps.capUrns()
        XCTAssertEqual(urns.count, 1, "A single addCap: must yield a single urn string")

        // Parse the string back into a tagged URN and compare through the
        // accepts predicate. Never compare tagged URNs as strings.
        let parsed = try CSCapUrn.fromString(urns[0])
        XCTAssertTrue(parsed.accepts(cap.capUrn),
                      "A URN must accept itself (reflexivity of the accepts relation)")
        XCTAssertTrue(cap.capUrn.accepts(parsed),
                      "Round-tripped URN must be equivalent (double-sided conforms_to)")
    }

    /// Insertion order is preserved in both `caps` and `capUrns`.
    func test0002_InsertionOrderPreserved() throws {
        let caps = CSCartridgeCaps()
        try caps.addCap(makeCap(op: "alpha"))
        try caps.addCap(makeCap(op: "beta"))
        try caps.addCap(makeCap(op: "gamma"))

        XCTAssertEqual(caps.caps.count, 3)
        XCTAssertEqual(caps.caps[0].primaryAlias(), "alpha")
        XCTAssertEqual(caps.caps[1].primaryAlias(), "beta")
        XCTAssertEqual(caps.caps[2].primaryAlias(), "gamma")

        let urns = caps.capUrns()
        XCTAssertEqual(urns.count, 3)

        // Each surfaced urn accepts the corresponding cap's urn and vice versa.
        for i in 0..<3 {
            let parsed = try CSCapUrn.fromString(urns[i])
            XCTAssertTrue(parsed.accepts(caps.caps[i].capUrn))
            XCTAssertTrue(caps.caps[i].capUrn.accepts(parsed))
        }
    }

    /// Copy is independent: mutating the original must not affect the copy.
    /// Regression-guards against a shared mutable backing array.
    func test0003_CopyIsIndependent() throws {
        let original = CSCartridgeCaps()
        try original.addCap(makeCap(op: "first"))

        let copy = original.copy() as! CSCartridgeCaps

        try original.addCap(makeCap(op: "second"))

        XCTAssertEqual(original.caps.count, 2)
        XCTAssertEqual(copy.caps.count, 1, "Copy must not see mutations to the original")
    }
}
