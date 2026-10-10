import CapDAGFormal
import XCTest

final class FormalAssuranceTests: XCTestCase {
    // TEST12597: every function of the proved model this mirror calls carries a proved claim.
    //
    // The model's package carries what is proved of each function it exports (its assurance
    // document, generated from ../formal): each one decides, equals or keeps what its claim says,
    // and none rests on an assumption about the host — the model needs none.
    func test12597_EveryModelFunctionCarriesAProvedClaim() throws {
        let a = assurance
        XCTAssertTrue(a.facilities.isEmpty && a.assumptions.isEmpty, "the model assumes nothing of the host")
        XCTAssertFalse(a.exports.isEmpty)
        for e in a.exports {
            XCTAssertFalse(e.claims.isEmpty, "\(e.name) carries no claim")
            XCTAssertTrue(e.assumptions.isEmpty, "\(e.name) rests on \(e.assumptions)")
            for name in e.claims {
                let claim = try XCTUnwrap(a.claim(name), name)
                XCTAssertEqual(claim.status, "proved", name)
                XCTAssertTrue(claim.subjects.contains(e.name), "\(name) is about \(e.name)")
            }
        }
        let dispatch = try XCTUnwrap(a.claim("CapDAG.Exec.dispatch_decides"))
        XCTAssertEqual(dispatch.relation, "lungo.decides")
        XCTAssertEqual(dispatch.specifications, ["CapDAG.serves"])
    }
}
