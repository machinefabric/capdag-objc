//
//  CSStepTokenTests.m
//  CapDAGTests
//
//  Tests for CSStepToken and token-addressed step requirements — mirrors Rust
//  plan_builder.rs tests test1461/test1462.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"
#import "CSMediaUrn.h"

@interface CSStepTokenTests : XCTestCase
@end

@implementation CSStepTokenTests

// TEST1462: An unidentified step is not a state the program can hold. CSStepToken is the type that makes it so - minting is the only way to create one and +parse:error:, the sole path back from text, refuses an empty id
- (void)test1462_aStepTokenCannotBeEmpty {
    NSError *error = nil;
    XCTAssertNil([CSStepToken parse:@"" error:&error],
        @"an empty id names no step and is not a token");
    XCTAssertEqualObjects(error.domain, CSStepTokenErrorDomain);
    XCTAssertEqual(error.code, CSStepTokenErrorCodeEmpty);

    // A minted token round-trips through its text unchanged.
    CSStepToken *minted = [CSStepToken mint];
    NSError *parseError = nil;
    CSStepToken *recovered = [CSStepToken parse:minted.string error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertEqualObjects(recovered, minted);

    // Every step is born addressable — there is no window in which one exists
    // without an identity.
    CSStrandStep *step = [[CSStrandStep alloc] init];
    XCTAssertNotNil(step.tokenId);
    XCTAssertGreaterThan(step.tokenId.string.length, 0u);
    CSStrandStep *other = [[CSStrandStep alloc] init];
    XCTAssertNotEqualObjects(step.tokenId, other.tokenId,
        @"each step is minted with its own identity");
}

@end
