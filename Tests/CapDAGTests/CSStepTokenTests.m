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

// Build a cap with one stdin main input and one defaulted option.
static CSCap *makeRewriteCap(void) {
    NSError *error = nil;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:ext=txt;text"];
    [builder outSpec:@"media:ext=txt;text"];
    [builder tag:@"op" value:@"rewrite"];
    CSCapUrn *urn = [builder build:&error];
    NSCAssert(urn != nil, @"Failed to build rewrite cap URN: %@", error);

    CSCap *cap = [CSCap capWithUrn:urn title:@"Rewrite" aliases:@[@"rewrite"]];
    [cap addArg:[CSCapArg argWithMediaUrn:@"media:ext=txt;text"
                                 required:YES
                                  sources:@[[CSArgSource stdinSourceWithMediaUrn:@"media:ext=txt;text"]]]];
    [cap addArg:[CSCapArg argWithMediaUrn:@"media:numeric;temperature"
                                 required:NO
                                  sources:@[[CSArgSource cliFlagSource:@"--temperature"]]
                           argDescription:@"Sampling temperature"
                             defaultValue:@(0.7)]];
    return cap;
}

// Two steps running the SAME cap — the shape where positional identity is
// indistinguishable from token identity unless the tokens are actually carried.
static CSStrand *makeRepeatedCapStrand(CSCap *cap) {
    CSStrandStep *(^step)(void) = ^CSStrandStep *{
        CSStrandStep *s = [[CSStrandStep alloc] init];
        s.stepType = CSStrandStepTypeCap;
        s.capUrn = [[cap capUrn] toString];
        s.fromSpec = @"media:ext=txt;text";
        s.toSpec = @"media:ext=txt;text";
        s.specificity = 1;
        return s;
    };

    CSStrand *strand = [[CSStrand alloc] init];
    strand.sourceMediaUrn = @"media:ext=txt;text";
    strand.targetMediaUrn = @"media:ext=txt;text";
    strand.steps = @[step(), step()];
    strand.totalSteps = 2;
    strand.capStepCount = 2;
    strand.pathDescription = @"Rewrite twice";
    return strand;
}

// TEST1461: Step requirements are addressed by the plan's own token. Two steps of the SAME cap must yield the two DISTINCT CSStrandStep.tokenId values the planner minted, in correspondence with the steps they describe
- (void)test1461_stepRequirementsCarryThePlansOwnTokens {
    CSCap *cap = makeRewriteCap();
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    [registry insertCachedCapForTest:cap];
    CSMachinePlanBuilder *builder = [[CSMachinePlanBuilder alloc] initWithFabricRegistry:registry];
    CSStrand *strand = makeRepeatedCapStrand(cap);

    NSArray<CSStepToken *> *strandTokens = @[
        ((CSStrandStep *)strand.steps[0]).tokenId,
        ((CSStrandStep *)strand.steps[1]).tokenId,
    ];
    XCTAssertNotEqualObjects(strandTokens[0], strandTokens[1],
        @"the planner mints a distinct token per step even for a repeated cap");

    XCTestExpectation *done = [self expectationWithDescription:@"analyze"];
    __block CSPathArgumentRequirements *requirements = nil;
    [builder analyzePathArgumentsForStrand:strand
                                completion:^(CSPathArgumentRequirements *result, NSError *error) {
        XCTAssertNil(error, @"step-requirements assembly must succeed");
        requirements = result;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5.0];

    XCTAssertEqual(requirements.steps.count, 2u);
    NSArray<CSStepToken *> *requirementTokens = @[
        requirements.steps[0].tokenId,
        requirements.steps[1].tokenId,
    ];
    XCTAssertEqualObjects(requirementTokens, strandTokens,
        @"each requirement carries the token of the step it describes — the address a "
        @"value is bound to, not a position to be counted");
}

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
