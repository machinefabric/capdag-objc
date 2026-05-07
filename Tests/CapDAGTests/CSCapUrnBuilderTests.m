//
//  CSCapUrnBuilderTests.m
//  Tests for CSCapUrnBuilder with required direction (in/out)
//
//  NOTE: Builder now requires inSpec and outSpec to be set before build().
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSCapUrnBuilderTests : XCTestCase
@end

@implementation CSCapUrnBuilderTests

- (void)testBuilderBasicConstruction {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:record;textable"];
    [builder tag:@"type" value:@"data_processing"];
    [builder marker:@"transform"];
    [builder tag:@"format" value:@"json"];
    CSCapUrn *capUrn = [builder build:&error];

    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    // Alphabetical order: format, in, out, transform, type.
    XCTAssertEqualObjects([capUrn toString], @"cap:format=json;in=media:void;out=\"media:record;textable\";transform;type=data_processing");
}

- (void)testBuilderFluentAPI {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [[[[[[builder inSpec:@"media:void"] outSpec:@"media:record;textable"]
        marker:@"generate"]
       tag:@"target" value:@"thumbnail"]
      tag:@"format" value:@"pdf"]
     tag:@"output" value:@"binary"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    XCTAssertTrue([cap hasMarkerTag:@"generate"]);
    XCTAssertEqualObjects([cap getTag:@"target"], @"thumbnail");
    XCTAssertEqualObjects([cap getTag:@"format"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
    XCTAssertEqualObjects([cap getInSpec], @"media:void");
    XCTAssertEqualObjects([cap getOutSpec], @"media:record;textable");
}

- (void)testBuilderDirectionAccess {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:string"];
    [builder outSpec:@"media:"];
    [builder marker:@"process"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    XCTAssertEqualObjects([cap getInSpec], @"media:string");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
    XCTAssertEqualObjects([cap getTag:@"in"], @"media:string");
    XCTAssertEqualObjects([cap getTag:@"out"], @"media:");
}

- (void)testBuilderCustomTags {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:record;textable"];
    [builder tag:@"engine" value:@"v2"];
    [builder tag:@"quality" value:@"high"];
    [builder tag:@"op" value:@"compress"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    XCTAssertEqualObjects([cap getTag:@"engine"], @"v2");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"high");
    XCTAssertEqualObjects([cap getTag:@"op"], @"compress");
}

- (void)testBuilderTagOverrides {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:record;textable"];
    [builder tag:@"op" value:@"old"];
    [builder tag:@"op" value:@"convert"]; // Override
    [builder tag:@"format" value:@"jpg"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    XCTAssertEqualObjects([cap getTag:@"op"], @"convert");
    XCTAssertEqualObjects([cap getTag:@"format"], @"jpg");
}

- (void)testBuilderMissingInSpecFails {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    // Only set outSpec, not inSpec
    [builder outSpec:@"media:record;textable"];
    [builder tag:@"op" value:@"test"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingInSpec);
}

- (void)testBuilderMissingOutSpecFails {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    // Only set inSpec, not outSpec
    [builder inSpec:@"media:void"];
    [builder tag:@"op" value:@"test"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingOutSpec);
}

- (void)testBuilderEmptyBuildFailsWithMissingInSpec {
    NSError *error;
    CSCapUrn *cap = [[CSCapUrnBuilder builder] build:&error];

    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingInSpec);
}

- (void)testBuilderTagIgnoresInOut {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:record;textable"];
    // Trying to set in/out via tag should be silently ignored
    [builder tag:@"in" value:@"different"];
    [builder tag:@"out" value:@"different"];
    [builder tag:@"op" value:@"test"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    // Direction should be from inSpec/outSpec, not from tag calls
    XCTAssertEqualObjects([cap getInSpec], @"media:void");
    XCTAssertEqualObjects([cap getOutSpec], @"media:record;textable");
}

- (void)testBuilderMinimalValid {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:record;textable"];
    // No other tags
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap toString], @"cap:in=media:void;out=\"media:record;textable\"");
    XCTAssertEqual(cap.tags.count, 0);
    // Cap-URN spec: 10000 * spec_U(out) + 100 * spec_U(in) + spec_U(y).
    //   out = media:record;textable -> 2 markers, score 4
    //   in  = media:void           -> 1 marker, score 2
    //   y   = empty                -> 0
    XCTAssertEqual([cap specificity], 10000 * 4 + 100 * 2 + 0);
}

- (void)testBuilderComplex {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:"];
    [builder outSpec:@"media:"];
    [builder tag:@"type" value:@"media"];
    [builder marker:@"transcode"];
    [builder tag:@"target" value:@"video"];
    [builder tag:@"format" value:@"mp4"];
    [builder tag:@"codec" value:@"h264"];
    [builder tag:@"quality" value:@"1080p"];
    [builder tag:@"framerate" value:@"30fps"];
    [builder tag:@"output" value:@"binary"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    // `media:` direction specs (top of the order, no tags) collapse
    // out of the canonical serialization. Alphabetical order across
    // the remaining y-tags: codec, format, framerate, output, quality,
    // target, transcode, type.
    NSString *expected = @"cap:codec=h264;format=mp4;framerate=30fps;output=binary;quality=1080p;target=video;transcode;type=media";
    XCTAssertEqualObjects([cap toString], expected);

    XCTAssertEqualObjects([cap getTag:@"type"], @"media");
    XCTAssertTrue([cap hasMarkerTag:@"transcode"]);
    XCTAssertEqualObjects([cap getTag:@"target"], @"video");
    XCTAssertEqualObjects([cap getTag:@"format"], @"mp4");
    XCTAssertEqualObjects([cap getTag:@"codec"], @"h264");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"1080p");
    XCTAssertEqualObjects([cap getTag:@"framerate"], @"30fps");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");

    // Cap-URN spec: 10000 * spec_U(out) + 100 * spec_U(in) + spec_U(y).
    //   out = media: -> 0
    //   in  = media: -> 0
    //   y   = 7 exact tags × 4 + 1 marker (transcode) × 2 = 28 + 2 = 30
    XCTAssertEqual([cap specificity], 10000 * 0 + 100 * 0 + 30);
}

- (void)testBuilderWildcards {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"*"]; // Wildcard in
    [builder outSpec:@"*"]; // Wildcard out
    [builder marker:@"convert"];
    [builder marker:@"ext"];     // bare marker, value=*
    [builder marker:@"quality"]; // bare marker, value=*
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    // `media:` collapses out of the canonical serialization. Three
    // markers, alphabetical: convert, ext, quality.
    XCTAssertEqualObjects([cap toString], @"cap:convert;ext;quality");
    // Cap-URN spec: out=0, in=0, y = 3 markers × 2 = 6.
    XCTAssertEqual([cap specificity], 6);

    XCTAssertEqualObjects([cap getTag:@"ext"], @"*");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"*");
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

- (void)testBuilderStaticFactory {
    CSCapUrnBuilder *builder1 = [CSCapUrnBuilder builder];
    CSCapUrnBuilder *builder2 = [CSCapUrnBuilder builder];

    XCTAssertNotEqual(builder1, builder2); // Should be different instances
    XCTAssertNotNil(builder1);
    XCTAssertNotNil(builder2);
}

- (void)testBuilderMatchingWithBuiltCap {
    NSError *error;

    // Create a specific cap (handler/instance)
    CSCapUrnBuilder *builder1 = [CSCapUrnBuilder builder];
    [builder1 inSpec:@"media:void"];
    [builder1 outSpec:@"media:record;textable"];
    [builder1 tag:@"op" value:@"generate"];
    [builder1 tag:@"target" value:@"thumbnail"];
    [builder1 tag:@"format" value:@"pdf"];
    [builder1 tag:@"ext" value:@"pdf"];  // Instance must have all tags that wildcard pattern requires
    CSCapUrn *specificCap = [builder1 build:&error];

    // Create a more general request (same direction)
    CSCapUrnBuilder *builder2 = [CSCapUrnBuilder builder];
    [builder2 inSpec:@"media:void"];
    [builder2 outSpec:@"media:record;textable"];
    [builder2 tag:@"op" value:@"generate"];
    CSCapUrn *generalRequest = [builder2 build:&error];

    // Create a wildcard request (same direction)
    CSCapUrnBuilder *builder3 = [CSCapUrnBuilder builder];
    [builder3 inSpec:@"media:void"];
    [builder3 outSpec:@"media:record;textable"];
    [builder3 tag:@"op" value:@"generate"];
    [builder3 tag:@"target" value:@"thumbnail"];
    [builder3 tag:@"ext" value:@"*"];
    CSCapUrn *wildcardRequest = [builder3 build:&error];

    XCTAssertNotNil(specificCap);
    XCTAssertNotNil(generalRequest);
    XCTAssertNotNil(wildcardRequest);

    // General request (pattern) should accept specific cap (instance)
    XCTAssertTrue([generalRequest accepts:specificCap]);

    // Wildcard request (pattern) should accept specific cap (instance)
    XCTAssertTrue([wildcardRequest accepts:specificCap]);

    // Cap-URN spec: 10000 * spec_U(out) + 100 * spec_U(in) + spec_U(y).
    XCTAssertTrue([specificCap isMoreSpecificThan:generalRequest]);
    //   specificCap: out=record;textable (4), in=void (2),
    //   y = op=generate(4)+target=thumbnail(4)+format=pdf(4)+ext=pdf(4) = 16
    XCTAssertEqual([specificCap specificity], 10000 * 4 + 100 * 2 + 16);
    //   generalRequest: out=4, in=2, y = op=generate(4) = 4
    XCTAssertEqual([generalRequest specificity], 10000 * 4 + 100 * 2 + 4);
    //   wildcardRequest: out=4, in=2, y = op=generate(4)+target=thumbnail(4)+ext=*(2) = 10
    XCTAssertEqual([wildcardRequest specificity], 10000 * 4 + 100 * 2 + 10);
}

- (void)testBuilderDirectionMismatchNoMatch {
    NSError *error;

    // Create caps with different directions
    CSCapUrnBuilder *builder1 = [CSCapUrnBuilder builder];
    [builder1 inSpec:@"media:string"];
    [builder1 outSpec:@"media:record;textable"];
    [builder1 tag:@"op" value:@"process"];
    CSCapUrn *cap1 = [builder1 build:&error];

    CSCapUrnBuilder *builder2 = [CSCapUrnBuilder builder];
    [builder2 inSpec:@"media:"]; // Different inSpec
    [builder2 outSpec:@"media:record;textable"];
    [builder2 tag:@"op" value:@"process"];
    CSCapUrn *cap2 = [builder2 build:&error];

    XCTAssertNotNil(cap1);
    XCTAssertNotNil(cap2);

    // cap1 (in=media:string) should NOT accept cap2 (in=media:) - more specific doesn't accept less specific
    XCTAssertFalse([cap1 accepts:cap2]);
    // cap2 (in=media:) SHOULD accept cap1 (in=media:string) - base accepts more specific
    XCTAssertTrue([cap2 accepts:cap1]);
}

@end
