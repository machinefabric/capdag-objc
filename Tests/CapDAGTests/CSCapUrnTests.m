//
//  CSCapUrnTests.m
//  Tests for CSCapUrn tag-based system with required direction (in/out)
//
//  NOTE: All caps now require 'in' and 'out' tags for direction.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSCapUrnTests : XCTestCase
@end

@implementation CSCapUrnTests

#pragma mark - Helper Functions

// Helper function to create test URNs with default direction
// Use media:void for in (no input) and media:object for out by default
// Media URNs with record must be quoted because they contain = sign
static NSString* testUrn(NSString *tags) {
    if (tags == nil || tags.length == 0) {
        return @"cap:in=\"media:void\";out=\"media:record;textable\"";
    }
    return [NSString stringWithFormat:@"cap:in=\"media:void\";out=\"media:record;textable\";%@", tags];
}

#pragma mark - Basic Creation Tests

// TEST001: Test that cap URN is created with tags parsed correctly and direction specs accessible
- (void)test001_capUrnCreation {
    NSError *error;
    // Use type=data_processing key=value instead of flag
    CSCapUrn *capUrn = [CSCapUrn fromString:testUrn(@"transform;format=json;type=data_processing") error:&error];

    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);

    XCTAssertEqualObjects([capUrn getTag:@"type"], @"data_processing");
    XCTAssertTrue([capUrn hasMarkerTag:@"transform"]);
    XCTAssertEqualObjects([capUrn getTag:@"format"], @"json");
    // Direction should be accessible
    XCTAssertEqualObjects([capUrn getTag:@"in"], @"media:void");
    XCTAssertEqualObjects([capUrn getTag:@"out"], @"media:record;textable");
    XCTAssertEqualObjects([capUrn getInSpec], @"media:void");
    XCTAssertEqualObjects([capUrn getOutSpec], @"media:record;textable");
}

// TEST011: Test that serialization uses smart quoting (no quotes for simple lowercase, quotes for special chars/uppercase)
- (void)test011_serializationSmartQuoting {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:testUrn(@"generate;target=thumbnail;ext=pdf") error:&error];

    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);

    // Should be sorted alphabetically: ext, generate, in, out, target.
    // Note: out value contains ; so it must be quoted in the canonical form.
    XCTAssertEqualObjects([capUrn toString], @"cap:ext=pdf;generate;in=media:void;out=\"media:record;textable\";target=thumbnail");
}

// TEST015: Test that cap: prefix is required and case-insensitive
- (void)test015_capPrefixRequired {
    NSError *error;
    // Missing cap: prefix should fail
    CSCapUrn *capUrn = [CSCapUrn fromString:@"in=media:void;generate;out=\"media:record;textable\"" error:&error];
    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingCapPrefix);

    // Valid cap: prefix with in/out should work
    error = nil;
    capUrn = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    XCTAssertTrue([capUrn hasMarkerTag:@"generate"]);
}

// TEST016: Test that trailing semicolon is equivalent (same hash, same string, matches)
- (void)test016_trailingSemicolonEquivalence {
    NSError *error;
    // Both with and without trailing semicolon should be equivalent
    CSCapUrn *cap1 = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap1);

    CSCapUrn *cap2 = [CSCapUrn fromString:[testUrn(@"generate;ext=pdf") stringByAppendingString:@";"] error:&error];
    XCTAssertNotNil(cap2);

    // They should be equal
    XCTAssertEqualObjects(cap1, cap2);

    // They should have same hash
    XCTAssertEqual([cap1 hash], [cap2 hash]);

    // They should have same string representation (canonical form)
    XCTAssertEqualObjects([cap1 toString], [cap2 toString]);

    // They should match each other
    XCTAssertTrue([cap1 accepts:cap2]);
    XCTAssertTrue([cap2 accepts:cap1]);
}

// TEST001 variant: Test empty URN fails
- (void)testInvalidCapUrn {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"" error:&error];

    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidFormat);
}

// TEST1406: Value-less tags (bare keys like ";flag") parse as wildcards (mirror-local variant of TEST031)
- (void)test1406_valuelessTagParsing {
    NSError *error;
    // Value-less tags are now valid (parsed as wildcards)
    // Cap URN with valid in/out and a value-less tag should succeed
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;optimize;out=\"media:record;textable\"" error:&error];

    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    // Value-less tag is parsed as wildcard
    XCTAssertEqualObjects([capUrn getTag:@"optimize"], @"*");

    // Test value-less tag at end of input
    error = nil;
    capUrn = [CSCapUrn fromString:@"cap:in=media:void;out=\"media:record;textable\";flag" error:&error];
    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn getTag:@"flag"], @"*");
}

// TEST1402: Invalid characters (e.g. '@') in tag keys are rejected by the parser (mirror-local variant of TEST003)
- (void)test1402_invalidCharacters {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;type@invalid=value;out=\"media:record;textable\"" error:&error];

    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidCharacter);
}

#pragma mark - Required Direction Tests

// TEST002: Test that missing 'in' or 'out' defaults to media: wildcard
- (void)test002_directionSpecsDefaultToWildcard {
    NSError *error = nil;
    // Missing 'in' defaults to media:
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:out=\"media:record;textable\";generate" error:&error];
    XCTAssertNotNil(capUrn, @"Missing in should default to media:");
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn getInSpec], @"media:");
    XCTAssertEqualObjects([capUrn getOutSpec], @"media:record;textable");
}

// TEST1400: Missing 'out' defaults to media: wildcard (mirror-local variant of TEST002 covering the out-side case)
- (void)test1400_missingOutSpecDefaultsToWildcard {
    NSError *error = nil;
    // Missing 'out' defaults to media:
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;generate" error:&error];
    XCTAssertNotNil(capUrn, @"Missing out should default to media:");
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn getInSpec], @"media:void");
    XCTAssertEqualObjects([capUrn getOutSpec], @"media:");
}

// TEST028: Test empty cap URN defaults to media: wildcard
- (void)test028_emptyCapUrnDefaultsToWildcard {
    NSError *error = nil;
    // Empty cap URN defaults to media: for both in and out
    CSCapUrn *empty = [CSCapUrn fromString:@"cap:" error:&error];
    XCTAssertNotNil(empty, @"Empty cap should default to media: wildcard");
    XCTAssertNil(error);
    XCTAssertEqualObjects([empty getInSpec], @"media:");
    XCTAssertEqualObjects([empty getOutSpec], @"media:");

    // cap:in=media:;out=media:;raw also defaults - has tags but missing in/out defaults to media:
    error = nil;
    CSCapUrn *missingInOut = [CSCapUrn fromString:@"cap:raw" error:&error];
    XCTAssertNotNil(missingInOut, @"cap:in=media:;out=media:;raw should default in/out to media:");
    XCTAssertNil(error);
    XCTAssertEqualObjects([missingInOut getInSpec], @"media:");
    XCTAssertEqualObjects([missingInOut getOutSpec], @"media:");
    XCTAssertTrue([missingInOut hasMarkerTag:@"raw"]);
}

// TEST029: Test minimal valid cap URN has just in and out, empty tags
- (void)test029_minimalCapUrn {
    NSError *error = nil;
    // Minimal valid cap URN has just in and out
    CSCapUrn *minimal = [CSCapUrn fromString:@"cap:in=media:void;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(minimal);
    XCTAssertNil(error);
    XCTAssertEqualObjects([minimal getInSpec], @"media:void");
    XCTAssertEqualObjects([minimal getOutSpec], @"media:record;textable");
    XCTAssertEqual(minimal.tags.count, 0); // No extra tags
}

// TEST003: Test that direction specs must match exactly, different in/out types don't match, wildcard matches any
- (void)test003_directionMatching {
    NSError *error = nil;
    // Different inSpec should not match
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:in=media:string;test;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap1);
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:in=media:;test;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap2);
    XCTAssertFalse([cap1 accepts:cap2]);

    // Different outSpec should not match
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:in=media:void;test;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap3);
    CSCapUrn *cap4 = [CSCapUrn fromString:@"cap:in=media:void;test;out=media:binary" error:&error];
    XCTAssertNotNil(cap4);
    XCTAssertFalse([cap3 accepts:cap4]);
}

// TEST1401: Wildcard in/out specs accept any concrete value (mirror-local variant of TEST003's wildcard branch)
- (void)test1401_directionWildcardMatches {
    NSError *error = nil;
    // Wildcard inSpec matches any
    CSCapUrn *wildcardIn = [CSCapUrn fromString:@"cap:in=*;test;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(wildcardIn);
    CSCapUrn *specificIn = [CSCapUrn fromString:@"cap:in=media:string;test;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(specificIn);
    XCTAssertTrue([wildcardIn accepts:specificIn]);

    // Wildcard outSpec matches any
    CSCapUrn *wildcardOut = [CSCapUrn fromString:@"cap:in=media:void;test;out=*" error:&error];
    XCTAssertNotNil(wildcardOut);
    CSCapUrn *specificOut = [CSCapUrn fromString:@"cap:in=media:void;test;out=media:binary" error:&error];
    XCTAssertNotNil(specificOut);
    XCTAssertTrue([wildcardOut accepts:specificOut]);
}

#pragma mark - Tag Matching Tests

// TEST017: Test tag matching: exact match, subset match, wildcard match, value mismatch
- (void)test017_tagMatching {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate;ext=pdf;target=thumbnail") error:&error];
    XCTAssertNotNil(cap);

    // Exact match — both directions accept
    CSCapUrn *request1 = [CSCapUrn fromString:testUrn(@"generate;ext=pdf;target=thumbnail") error:&error];
    XCTAssertTrue([cap accepts:request1]);
    XCTAssertTrue([request1 accepts:cap]);

    // Routing direction: request(generate) accepts cap(op,ext,target) — request only needs op
    CSCapUrn *request2 = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    XCTAssertTrue([request2 accepts:cap]);
    // Reverse: cap(op,ext,target) as pattern rejects request missing ext,target
    XCTAssertFalse([cap accepts:request2]);

    // Routing direction: request(ext=*) accepts cap(ext=pdf) — wildcard matches specific
    CSCapUrn *request3 = [CSCapUrn fromString:testUrn(@"ext=*") error:&error];
    XCTAssertTrue([request3 accepts:cap]);

    // Conflicting value — neither direction accepts
    CSCapUrn *request4 = [CSCapUrn fromString:testUrn(@"extract") error:&error];
    XCTAssertFalse([cap accepts:request4]);
    XCTAssertFalse([request4 accepts:cap]);
}

// TEST019: Missing tag in instance causes rejection — pattern's tags are constraints
- (void)test019_missingTagHandling {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    CSCapUrn *request1 = [CSCapUrn fromString:testUrn(@"ext=pdf") error:&error];

    // cap(op) as pattern: instance(ext) missing op → reject
    XCTAssertFalse([cap accepts:request1]);
    // request(ext) as pattern: instance(cap) missing ext → reject
    XCTAssertFalse([request1 accepts:cap]);

    // Routing: request(op) accepts cap(op,ext) — instance has op → match
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    CSCapUrn *request2 = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    XCTAssertTrue([request2 accepts:cap2]);
    // Reverse: cap(op,ext) as pattern rejects request missing ext
    XCTAssertFalse([cap2 accepts:request2]);
}

// TEST020: Specificity is the sum of per-tag truth-table scores
// across in/out/y. Marker tags (bare segments and `key=*`) score 2
// (must-have-any), exact `key=value` tags score 3, missing/`?` score
// 0, `!` scores 1.
//
// testUrn() builds "cap:in=media:void;out=media:record;textable;<tags>"
// so the directional baseline is:
//   in:  media:void              -> {void=*}              -> 2
//   out: media:record;textable   -> {record=*, textable=*} -> 4
// Total directional baseline: 6.
- (void)test020_specificity {
    NSError *error;

    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:in=*;op;out=*" error:&error];
    XCTAssertNotNil(cap1);
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    XCTAssertNotNil(cap2);
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:in=*;op;out=*;ext=pdf" error:&error];
    XCTAssertNotNil(cap3);

    // testUrn() prepends in="media:void" (score 2) and
    // out="media:record;textable" (score 2+2=4). Cap-URN spec is
    // 10000*spec_U(out) + 100*spec_U(in) + spec_U(y).

    // cap1: out=media:(0), in=media:(0), y=op marker(2) = 2
    XCTAssertEqual([cap1 specificity], 10000*0 + 100*0 + 2);
    // cap2: out=4, in=2, y=2 (generate marker)
    XCTAssertEqual([cap2 specificity], 10000*4 + 100*2 + 2);
    // cap3: out=0, in=0, y=2+4 (op marker, ext=pdf exact)
    XCTAssertEqual([cap3 specificity], 10000*0 + 100*0 + 6);

    XCTAssertTrue([cap2 isMoreSpecificThan:cap1]);
}

// TEST024: Directional accepts — pattern's tags are constraints, instance must satisfy
- (void)test024_directionalAccepts {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"generate;format=*") error:&error];
    CSCapUrn *cap3 = [CSCapUrn fromString:testUrn(@"type=image;extract") error:&error];

    // cap1(op,ext) as pattern: cap2 missing ext → reject
    XCTAssertFalse([cap1 accepts:cap2]);
    // cap2(op,format) as pattern: cap1 missing format → reject
    XCTAssertFalse([cap2 accepts:cap1]);
    // op mismatch: neither direction accepts
    XCTAssertFalse([cap1 accepts:cap3]);
    XCTAssertFalse([cap3 accepts:cap1]);

    // Routing: general request(op) accepts specific cap(op,ext) — instance has op
    CSCapUrn *cap4 = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    XCTAssertTrue([cap4 accepts:cap1]); // cap4 only requires op, cap1 has it
    // Reverse: specific cap(op,ext) rejects general request missing ext
    XCTAssertFalse([cap1 accepts:cap4]);

    // Different direction specs: cap1 has in=media:void (specific), cap5 has in=media: (wildcard)
    CSCapUrn *cap5 = [CSCapUrn fromString:@"cap:in=media:;generate;out=\"media:record;textable\"" error:&error];
    // cap1 (in=media:void) cannot accept cap5 (in=media:) - specific doesn't accept wildcard
    XCTAssertFalse([cap1 accepts:cap5]);
    // cap5 (in=media:) CAN accept cap1 (in=media:void) - wildcard accepts specific
    XCTAssertTrue([cap5 accepts:cap1]);
}

#pragma mark - Convenience Methods Tests

// TEST039: Test get_tag returns direction specs (in/out) with case-insensitive lookup
- (void)test039_getTagReturnsDirectionSpecs {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate;ext=pdf;output=binary;target=thumbnail") error:&error];

    XCTAssertTrue([cap hasMarkerTag:@"generate"]);
    XCTAssertEqualObjects([cap getTag:@"target"], @"thumbnail");
    XCTAssertEqualObjects([cap getTag:@"ext"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
    // Direction via getTag
    XCTAssertEqualObjects([cap getTag:@"in"], @"media:void");
    XCTAssertEqualObjects([cap getTag:@"out"], @"media:record;textable");
}

// TEST036: Test with_tag preserves value case
- (void)test036_withTagPreservesValue {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    CSCapUrn *modified = [original withTag:@"ext" value:@"pdf"];

    // Direction preserved, new tag added in alphabetical order:
    // ext, generate, in, out.
    XCTAssertEqualObjects([modified toString], @"cap:ext=pdf;generate;in=media:void;out=\"media:record;textable\"");

    // Original should be unchanged: generate, in, out.
    XCTAssertEqualObjects([original toString], @"cap:generate;in=media:void;out=\"media:record;textable\"");
}

// TEST1407: withTag silently ignores attempts to set "in" or "out" tags (mirror-local)
- (void)test1407_withTagIgnoresInOut {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"generate") error:&error];

    // withTag for "in" or "out" should silently return self
    CSCapUrn *sameIn = [original withTag:@"in" value:@"different"];
    XCTAssertEqual(original, sameIn); // Same object

    CSCapUrn *sameOut = [original withTag:@"out" value:@"different"];
    XCTAssertEqual(original, sameOut); // Same object
}

// TEST1408: withInSpec returns a new URN with the in= spec replaced, leaving the original unchanged (mirror-local)
- (void)test1408_withInSpec {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    CSCapUrn *modified = [original withInSpec:@"media:string"];

    XCTAssertEqualObjects([modified getInSpec], @"media:string");
    XCTAssertEqualObjects([original getInSpec], @"media:void"); // Original unchanged
}

// TEST1409: withOutSpec returns a new URN with the out= spec replaced, leaving the original unchanged (mirror-local)
- (void)test1409_withOutSpec {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    CSCapUrn *modified = [original withOutSpec:@"media:"];

    XCTAssertEqualObjects([modified getOutSpec], @"media:");
    XCTAssertEqualObjects([original getOutSpec], @"media:record;textable"); // Original unchanged
}

// TEST1410: withoutTag removes a tag and returns a new URN, leaving the original unchanged (mirror-local)
- (void)test1410_withoutTag {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    CSCapUrn *modified = [original withoutTag:@"ext"];

    // Tags sort alphabetically: generate, in, out.
    XCTAssertEqualObjects([modified toString], @"cap:generate;in=media:void;out=\"media:record;textable\"");

    // Original should be unchanged. Tags sort alphabetically:
    // ext, generate, in, out.
    XCTAssertEqualObjects([original toString], @"cap:ext=pdf;generate;in=media:void;out=\"media:record;textable\"");
}

// TEST1411: withoutTag silently ignores attempts to remove "in" or "out" tags (mirror-local)
- (void)test1411_withoutTagIgnoresInOut {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"generate") error:&error];

    // withoutTag for "in" or "out" should silently return self
    CSCapUrn *sameIn = [original withoutTag:@"in"];
    XCTAssertEqual(original, sameIn); // Same object

    CSCapUrn *sameOut = [original withoutTag:@"out"];
    XCTAssertEqual(original, sameOut); // Same object
}

// TEST027: Test with_wildcard_tag sets tag to wildcard, including in/out
- (void)test027_wildcardTag {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"ext=pdf") error:&error];
    CSCapUrn *wildcarded = [cap withWildcardTag:@"ext"];

    XCTAssertEqualObjects([wildcarded getTag:@"ext"], @"*");

    // Test that wildcarded cap can match more requests
    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"ext=jpg") error:&error];
    XCTAssertFalse([cap accepts:request]);
    XCTAssertTrue([wildcarded accepts:request]);
}

// TEST1405: withWildcardTag resolves to withInSpec/withOutSpec for "in"/"out" tags, setting them to the wildcard "media:" (mirror-local variant of TEST027)
- (void)test1405_wildcardTagDirection {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate") error:&error];

    // withWildcardTag for "in" should use withInSpec - wildcard is "media:" now
    CSCapUrn *wildcardIn = [cap withWildcardTag:@"in"];
    XCTAssertEqualObjects([wildcardIn getInSpec], @"media:");

    // withWildcardTag for "out" should use withOutSpec - wildcard is "media:" now
    CSCapUrn *wildcardOut = [cap withWildcardTag:@"out"];
    XCTAssertEqualObjects([wildcardOut getOutSpec], @"media:");
}

// TEST026: Test merge combines tags from both caps, subset keeps only specified tags
- (void)test026_mergeAndSubset {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate;ext=pdf;output=binary;target=thumbnail") error:&error];
    CSCapUrn *subset = [cap subset:@[@"type", @"ext"]];

    // Direction is always preserved, only ext from the list
    XCTAssertEqualObjects([subset toString], @"cap:ext=pdf;in=media:void;out=\"media:record;textable\"");
}

// TEST1404: merge() combines tags from two cap URNs; direction comes from the other cap (mirror-local variant of TEST026's merge branch)
- (void)test1404_merge {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:in=media:void;generate;out=\"media:record;textable\"" error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:ext=pdf;in=media:string;out=media:;output=binary" error:&error];
    CSCapUrn *merged = [cap1 merge:cap2];

    // Direction comes from cap2 (other takes precedence)
    XCTAssertEqualObjects([merged getInSpec], @"media:string");
    XCTAssertEqualObjects([merged getOutSpec], @"media:");
    // Tags are merged
    XCTAssertTrue([merged hasMarkerTag:@"generate"]);
    XCTAssertEqualObjects([merged getTag:@"ext"], @"pdf");
    XCTAssertEqualObjects([merged getTag:@"output"], @"binary");
}

// TEST1403: Equality and hash of CSCapUrn identify identical URNs and distinguish direction/tag differences (mirror-local variant of TEST016)
- (void)test1403_equality {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    CSCapUrn *cap3 = [CSCapUrn fromString:testUrn(@"generate;image") error:&error];
    CSCapUrn *cap4 = [CSCapUrn fromString:@"cap:in=media:string;generate;out=\"media:record;textable\"" error:&error]; // Different in

    XCTAssertEqualObjects(cap1, cap2);
    XCTAssertNotEqualObjects(cap1, cap3);
    XCTAssertNotEqualObjects(cap1, cap4); // Different direction
    XCTAssertEqual([cap1 hash], [cap2 hash]);
}

// Obj-C specific: NSCoding support
- (void)testCoding {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    XCTAssertNotNil(original);
    XCTAssertNil(error);

    // Test NSCoding
    NSError *archiveError = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:original requiringSecureCoding:YES error:&archiveError];
    XCTAssertNil(archiveError, @"Archive should succeed");
    XCTAssertNotNil(data);

    NSError *unarchiveError = nil;
    CSCapUrn *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[CSCapUrn class] fromData:data error:&unarchiveError];
    XCTAssertNil(unarchiveError, @"Unarchive should succeed");
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(original, decoded);
    XCTAssertEqualObjects([decoded getInSpec], @"media:void");
    XCTAssertEqualObjects([decoded getOutSpec], @"media:record;textable");
}

// Obj-C specific: NSCopying support
- (void)testCopying {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    CSCapUrn *copy = [original copy];

    XCTAssertEqualObjects(original, copy);
    XCTAssertNotEqual(original, copy); // Different objects
    XCTAssertEqualObjects([copy getInSpec], [original getInSpec]);
    XCTAssertEqualObjects([copy getOutSpec], [original getOutSpec]);
}

#pragma mark - Extended Character Support Tests

// TEST030: Test extended characters (forward slashes, colons) in tag values
- (void)test030_extendedCharacterSupport {
    NSError *error = nil;
    // Test forward slashes and colons in tag components
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;out=\"media:record;textable\";url=https://example_org/api;path=/some/file" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"url"], @"https://example_org/api");
    XCTAssertEqualObjects([cap getTag:@"path"], @"/some/file");
}

// TEST031: Test wildcard rejected in keys but accepted in values
- (void)test031_wildcardRestrictions {
    NSError *error = nil;
    // Wildcard should be rejected in keys
    CSCapUrn *invalidKey = [CSCapUrn fromString:@"cap:in=media:void;out=\"media:record;textable\";*=value" error:&error];
    XCTAssertNil(invalidKey);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidCharacter);

    // Reset error for next test
    error = nil;

    // Wildcard should be accepted in values
    CSCapUrn *validValue = [CSCapUrn fromString:testUrn(@"key=*") error:&error];
    XCTAssertNotNil(validValue);
    XCTAssertNil(error);
    XCTAssertEqualObjects([validValue getTag:@"key"], @"*");
}

// TEST032: Test duplicate keys are rejected with DuplicateKey error
- (void)test032_duplicateKeyRejection {
    NSError *error = nil;
    // Duplicate keys should be rejected
    CSCapUrn *duplicate = [CSCapUrn fromString:@"cap:in=media:void;key=value1;key=value2;out=\"media:record;textable\"" error:&error];
    XCTAssertNil(duplicate);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorDuplicateKey);
}

// TEST033: Test pure numeric keys rejected, mixed alphanumeric allowed, numeric values allowed
- (void)test033_numericKeyRestriction {
    NSError *error = nil;

    // Pure numeric keys should be rejected
    CSCapUrn *numericKey = [CSCapUrn fromString:@"cap:in=media:void;123=value;out=\"media:record;textable\"" error:&error];
    XCTAssertNil(numericKey);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorNumericKey);

    // Reset error for next test
    error = nil;

    // Mixed alphanumeric keys should be allowed
    CSCapUrn *mixedKey1 = [CSCapUrn fromString:testUrn(@"key123=value") error:&error];
    XCTAssertNotNil(mixedKey1);
    XCTAssertNil(error);

    error = nil;
    CSCapUrn *mixedKey2 = [CSCapUrn fromString:testUrn(@"123key=value") error:&error];
    XCTAssertNotNil(mixedKey2);
    XCTAssertNil(error);

    error = nil;
    // Pure numeric values should be allowed
    CSCapUrn *numericValue = [CSCapUrn fromString:testUrn(@"key=123") error:&error];
    XCTAssertNotNil(numericValue);
    XCTAssertNil(error);
    XCTAssertEqualObjects([numericValue getTag:@"key"], @"123");
}

#pragma mark - Quoted Value Tests

// TEST004: Test that unquoted keys and values are normalized to lowercase
- (void)test004_unquotedValuesLowercased {
    NSError *error = nil;
    // Unquoted values are normalized to lowercase
    // Note: in/out values must be quoted since media URNs contain special chars
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:ext=pdf;generate;in=media:void;out=\"media:record;textable\";target=thumbnail" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    // Keys are always lowercase
    XCTAssertTrue([cap hasMarkerTag:@"generate"]);
    XCTAssertEqualObjects([cap getTag:@"ext"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"target"], @"thumbnail");

    // Key lookup is case-insensitive: uppercase variants of `ext`
    // resolve to the same keyed tag.
    XCTAssertEqualObjects([cap getTag:@"EXT"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"Ext"], @"pdf");

    // Both URNs parse to same lowercase values
    error = nil;
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"generate;ext=pdf;target=thumbnail") error:&error];
    XCTAssertEqualObjects([cap toString], [cap2 toString]);
    XCTAssertEqualObjects(cap, cap2);
}

// TEST005: Test that quoted values preserve case while unquoted are lowercased
- (void)test005_quotedValuesPreserveCase {
    NSError *error = nil;
    // Quoted values preserve their case
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"Value With Spaces\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"key"], @"Value With Spaces");

    // Key is still lowercase
    error = nil;
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:in=media:void;KEY=\"Value With Spaces\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap2);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap2 getTag:@"key"], @"Value With Spaces");

    // Unquoted vs quoted case difference
    error = nil;
    CSCapUrn *unquoted = [CSCapUrn fromString:testUrn(@"key=UPPERCASE") error:&error];
    XCTAssertNotNil(unquoted);
    error = nil;
    CSCapUrn *quoted = [CSCapUrn fromString:@"cap:in=media:void;key=\"UPPERCASE\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(quoted);

    XCTAssertEqualObjects([unquoted getTag:@"key"], @"uppercase"); // lowercase
    XCTAssertEqualObjects([quoted getTag:@"key"], @"UPPERCASE"); // preserved
    XCTAssertNotEqualObjects(unquoted, quoted); // NOT equal
}

// TEST006: Test that quoted values can contain special characters (semicolons, equals, spaces)
- (void)test006_quotedValueSpecialChars {
    NSError *error = nil;
    // Semicolons in quoted values
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"value;with;semicolons\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"key"], @"value;with;semicolons");

    // Equals in quoted values
    error = nil;
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:in=media:void;key=\"value=with=equals\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap2);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap2 getTag:@"key"], @"value=with=equals");

    // Spaces in quoted values
    error = nil;
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:in=media:void;key=\"hello world\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap3);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap3 getTag:@"key"], @"hello world");
}

// TEST007: Test that escape sequences in quoted values (\" and \\) are parsed correctly
- (void)test007_quotedValueEscapeSequences {
    NSError *error = nil;
    // Escaped quotes
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"value\\\"quoted\\\"\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"key"], @"value\"quoted\"");

    // Escaped backslashes
    error = nil;
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:in=media:void;key=\"path\\\\file\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap2);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap2 getTag:@"key"], @"path\\file");
}

// TEST008: Test that mixed quoted and unquoted values in same URN parse correctly
- (void)test008_mixedQuotedUnquoted {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:a=\"Quoted\";b=simple;in=media:void;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"a"], @"Quoted");
    XCTAssertEqualObjects([cap getTag:@"b"], @"simple");
}

// TEST009: Test that unterminated quote produces UnterminatedQuote error
- (void)test009_unterminatedQuoteError {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"unterminated;out=\"media:record;textable\"" error:&error];
    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorUnterminatedQuote);
}

// TEST010: Test that invalid escape sequences (like \n, \x) produce InvalidEscapeSequence error
- (void)test010_invalidEscapeSequenceError {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"bad\\n\";out=\"media:record;textable\"" error:&error];
    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidEscapeSequence);
}

// TEST012: Test that simple cap URN round-trips (parse -> serialize -> parse equals original)
- (void)test012_roundTripSimple {
    NSError *error = nil;
    NSString *original = testUrn(@"generate;ext=pdf");
    CSCapUrn *cap = [CSCapUrn fromString:original error:&error];
    XCTAssertNotNil(cap);
    NSString *serialized = [cap toString];
    CSCapUrn *reparsed = [CSCapUrn fromString:serialized error:&error];
    XCTAssertNotNil(reparsed);
    XCTAssertEqualObjects(cap, reparsed);
}

// TEST013: Test that quoted values round-trip preserving case and spaces
- (void)test013_roundTripQuoted {
    NSError *error = nil;
    NSString *original = @"cap:in=media:void;key=\"Value With Spaces\";out=\"media:record;textable\"";
    CSCapUrn *cap = [CSCapUrn fromString:original error:&error];
    XCTAssertNotNil(cap);
    NSString *serialized = [cap toString];
    CSCapUrn *reparsed = [CSCapUrn fromString:serialized error:&error];
    XCTAssertNotNil(reparsed);
    XCTAssertEqualObjects(cap, reparsed);
    XCTAssertEqualObjects([reparsed getTag:@"key"], @"Value With Spaces");
}

// TEST035: Test has_tag is case-sensitive for values, case-insensitive for keys, works for in/out
- (void)test035_hasTagCaseSensitive {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"Value\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap);

    // Exact case match works
    XCTAssertTrue([cap hasTag:@"key" withValue:@"Value"]);

    // Different case does not match
    XCTAssertFalse([cap hasTag:@"key" withValue:@"value"]);
    XCTAssertFalse([cap hasTag:@"key" withValue:@"VALUE"]);

    // Key lookup is case-insensitive
    XCTAssertTrue([cap hasTag:@"KEY" withValue:@"Value"]);
    XCTAssertTrue([cap hasTag:@"Key" withValue:@"Value"]);

    // hasTag works for direction too
    XCTAssertTrue([cap hasTag:@"in" withValue:@"media:void"]);
    XCTAssertTrue([cap hasTag:@"IN" withValue:@"media:void"]);
    XCTAssertTrue([cap hasTag:@"out" withValue:@"media:record;textable"]);
}

// TEST038: Test semantic equivalence of unquoted and quoted simple lowercase values
- (void)test038_semanticEquivalence {
    NSError *error = nil;
    // Unquoted and quoted simple lowercase values are equivalent
    CSCapUrn *unquoted = [CSCapUrn fromString:testUrn(@"key=simple") error:&error];
    XCTAssertNotNil(unquoted);
    CSCapUrn *quoted = [CSCapUrn fromString:@"cap:in=media:void;key=\"simple\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(quoted);
    XCTAssertEqualObjects(unquoted, quoted);

    // Both serialize the same way (unquoted)
    XCTAssertEqualObjects([unquoted toString], @"cap:in=media:void;key=simple;out=\"media:record;textable\"");
    XCTAssertEqualObjects([quoted toString], @"cap:in=media:void;key=simple;out=\"media:record;textable\"");
}

#pragma mark - Matching Semantics Specification Tests

// ============================================================================
// These tests verify the matching semantics with required direction
// All implementations (Rust, Go, JS, ObjC) must pass these identically
// ============================================================================

// TEST040: Matching semantics - exact match succeeds
- (void)test040_matchingSemantics_exactMatch {
    // Test 1: Exact match
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 1: Exact match should succeed");
}

// TEST041: Matching semantics - cap missing tag matches (implicit wildcard)
- (void)test041_matchingSemantics_capMissingTag {
    // Test 2: Cap missing tag (implicit wildcard)
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 2: Cap missing tag should match (implicit wildcard)");
}

// TEST042: Pattern rejects instance missing required tags
- (void)test042_matchingSemantics_capHasExtraTag {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate;ext=pdf;version=2") error:&error];
    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    // cap(op,ext,version) as pattern rejects request missing version
    XCTAssertFalse([cap accepts:request], @"Pattern rejects instance missing required tag");
    // Routing: request(op,ext) accepts cap(op,ext,version) — instance has all request needs
    XCTAssertTrue([request accepts:cap], @"Request pattern satisfied by more-specific cap");
}

// TEST043: Matching semantics - request wildcard matches specific cap value
- (void)test043_matchingSemantics_requestHasWildcard {
    // Test 4: Request has wildcard
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"generate;ext=*") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 4: Request wildcard should match");
}

// TEST044: Matching semantics - cap wildcard matches specific request value
- (void)test044_matchingSemantics_capHasWildcard {
    // Test 5: Cap has wildcard
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate;ext=*") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 5: Cap wildcard should match");
}

// TEST045: Matching semantics - value mismatch does not match
- (void)test045_matchingSemantics_valueMismatch {
    // Test 6: Value mismatch
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"generate;ext=docx") error:&error];
    XCTAssertNotNil(request);

    XCTAssertFalse([cap accepts:request], @"Test 6: Value mismatch should not match");
}

// TEST046: Matching semantics - fallback pattern (cap missing tag = implicit wildcard)
- (void)test046_matchingSemantics_fallbackPattern {
    // Test 7: Fallback pattern (cap missing tag = implicit wildcard)
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate-thumbnail") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"generate-thumbnail;ext=wav") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 7: Fallback pattern should match");
}

// TEST048: Matching semantics - wildcard direction matches anything
- (void)test048_matchingSemantics_wildcardDirectionMatchesAnything {
    // Test 8: Wildcard cap (in=*, out=*) matches anything
    // (This replaces the old "empty cap" test since empty caps are no longer valid)
    NSError *error = nil;
    CSCapUrn *wildcardCap = [CSCapUrn fromString:@"cap:in=*;out=*" error:&error];
    XCTAssertNotNil(wildcardCap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([wildcardCap accepts:request], @"Test 8: Wildcard cap should match anything");
}

// TEST049: Non-overlapping tags — neither direction accepts
- (void)test049_matchingSemantics_crossDimensionIndependence {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"ext=pdf") error:&error];
    // cap(op) rejects request missing op; request(ext) rejects cap missing ext
    XCTAssertFalse([cap accepts:request], @"Pattern rejects instance missing required tag");
    XCTAssertFalse([request accepts:cap], @"Reverse also rejects — non-overlapping tags");
}

// TEST050: Matching semantics - direction mismatch prevents matching
- (void)test050_matchingSemantics_directionMismatch {
    // Test 10: Direction mismatch prevents match even with matching tags
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:string;generate;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=media:;generate;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(request);

    XCTAssertFalse([cap accepts:request], @"Test 10: Direction mismatch should prevent match");
}

// TEST1412: Semantic direction matching - generic provider matches specific request (mirror-local variant of TEST051)
- (void)test1412_directionSemanticMatching {
    NSError *error = nil;

    // A cap accepting media: (generic) should match a request with media:pdf (specific)
    CSCapUrn *genericCap = [CSCapUrn fromString:@"cap:in=\"media:\";generate-thumbnail;out=\"media:image;png;thumbnail\"" error:&error];
    XCTAssertNotNil(genericCap, @"Failed to parse generic cap: %@", error);
    CSCapUrn *pdfRequest = [CSCapUrn fromString:@"cap:in=\"media:pdf\";generate-thumbnail;out=\"media:image;png;thumbnail\"" error:&error];
    XCTAssertNotNil(pdfRequest, @"Failed to parse pdf request: %@", error);
    XCTAssertTrue([genericCap accepts:pdfRequest],
        @"Generic provider must match specific pdf request");

    // Generic cap also matches epub (any subtype)
    CSCapUrn *epubRequest = [CSCapUrn fromString:@"cap:in=\"media:epub\";generate-thumbnail;out=\"media:image;png;thumbnail\"" error:&error];
    XCTAssertNotNil(epubRequest, @"Failed to parse epub request: %@", error);
    XCTAssertTrue([genericCap accepts:epubRequest],
        @"Generic provider must match epub request");

    // Reverse: specific cap does NOT match generic request
    CSCapUrn *pdfCap = [CSCapUrn fromString:@"cap:in=\"media:pdf\";generate-thumbnail;out=\"media:image;png;thumbnail\"" error:&error];
    XCTAssertNotNil(pdfCap, @"Failed to parse pdf cap: %@", error);
    CSCapUrn *genericRequest = [CSCapUrn fromString:@"cap:in=\"media:\";generate-thumbnail;out=\"media:image;png;thumbnail\"" error:&error];
    XCTAssertNotNil(genericRequest, @"Failed to parse generic request: %@", error);
    XCTAssertFalse([pdfCap accepts:genericRequest],
        @"Specific pdf cap must NOT match generic request");

    // Incompatible types: pdf cap does NOT match epub request
    XCTAssertFalse([pdfCap accepts:epubRequest],
        @"PDF-specific cap must NOT match epub request (epub lacks pdf marker)");

    // Output direction: cap producing more specific output matches less specific request
    CSCapUrn *specificOutCap = [CSCapUrn fromString:@"cap:in=\"media:\";generate-thumbnail;out=\"media:image;png;thumbnail\"" error:&error];
    XCTAssertNotNil(specificOutCap);
    CSCapUrn *genericOutRequest = [CSCapUrn fromString:@"cap:in=\"media:\";generate-thumbnail;out=\"media:image\"" error:&error];
    XCTAssertNotNil(genericOutRequest);
    XCTAssertTrue([specificOutCap accepts:genericOutRequest],
        @"Cap producing image;png;thumbnail must satisfy request for image");

    // Reverse output: generic output cap does NOT match specific output request
    CSCapUrn *genericOutCap = [CSCapUrn fromString:@"cap:in=\"media:\";generate-thumbnail;out=\"media:image\"" error:&error];
    XCTAssertNotNil(genericOutCap);
    CSCapUrn *specificOutRequest = [CSCapUrn fromString:@"cap:in=\"media:\";generate-thumbnail;out=\"media:image;png;thumbnail\"" error:&error];
    XCTAssertNotNil(specificOutRequest);
    XCTAssertFalse([genericOutCap accepts:specificOutRequest],
        @"Cap producing generic image must NOT satisfy request requiring image;png;thumbnail");
}

// TEST1413: Semantic direction specificity - more media URN tags = higher specificity (mirror-local variant of TEST052)
- (void)test1413_directionSemanticSpecificity {
    NSError *error = nil;

    CSCapUrn *genericCap = [CSCapUrn fromString:@"cap:in=\"media:\";generate-thumbnail;out=\"media:image;png;thumbnail\"" error:&error];
    XCTAssertNotNil(genericCap, @"Failed to parse generic cap: %@", error);
    CSCapUrn *specificCap = [CSCapUrn fromString:@"cap:in=\"media:pdf\";generate-thumbnail;out=\"media:image;png;thumbnail\"" error:&error];
    XCTAssertNotNil(specificCap, @"Failed to parse specific cap: %@", error);

    // Cap-URN spec: 10000*spec_U(out) + 100*spec_U(in) + spec_U(y).
    // generic:
    //   out = media:image;png;thumbnail -> 3 markers, score 6
    //   in  = media:                    -> 0
    //   y   = generate-thumbnail marker -> 2
    //   spec_C = 10000*6 + 100*0 + 2 = 60002
    XCTAssertEqual([genericCap specificity], 10000 * 6 + 100 * 0 + 2);
    // specific:
    //   out = media:image;png;thumbnail -> 6
    //   in  = media:pdf                 -> 2
    //   y   = generate-thumbnail marker -> 2
    //   spec_C = 10000*6 + 100*2 + 2 = 60202
    XCTAssertEqual([specificCap specificity], 10000 * 6 + 100 * 2 + 2);

    XCTAssertGreaterThan([specificCap specificity], [genericCap specificity],
        @"pdf cap must be more specific than generic cap");
}

// TEST_WILDCARD_001: cap: (empty) defaults to in=media:;out=media:
- (void)testWildcard001EmptyCapDefaultsToMediaWildcard {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:" error:&error];
    XCTAssertNotNil(cap, @"Empty cap should default to media: wildcard");
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
    XCTAssertEqual(cap.tags.count, 0);
}

// TEST_WILDCARD_002: cap:in defaults out to media:
- (void)testWildcard002InOnlyDefaultsOutToMedia {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in" error:&error];
    XCTAssertNotNil(cap, @"in without out should default out to media:");
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_003: cap:out defaults in to media:
- (void)testWildcard003OutOnlyDefaultsInToMedia {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:out" error:&error];
    XCTAssertNotNil(cap, @"out without in should default in to media:");
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_004: cap:in;out both become media:
- (void)testWildcard004InOutNoValuesBecomeMedia {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in;out" error:&error];
    XCTAssertNotNil(cap, @"in;out should both become media:");
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_005: cap:in=*;out=* becomes media:
- (void)testWildcard005ExplicitAsteriskBecomesMedia {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=*;out=*" error:&error];
    XCTAssertNotNil(cap, @"in=*;out=* should become media:");
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_006: cap:in=media:;out=* has specific in, wildcard out
- (void)testWildcard006SpecificInWildcardOut {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:;out=*" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_007: cap:in=*;out=media:text has wildcard in, specific out
- (void)testWildcard007WildcardInSpecificOut {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=*;out=media:text" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:text");
}

// TEST_WILDCARD_008: cap:in=foo fails (invalid media URN)
- (void)testWildcard008InvalidInSpecFails {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=foo;out=media:" error:&error];
    XCTAssertNil(cap, @"Invalid in spec should fail");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidInSpec);
}

// TEST_WILDCARD_009: cap:in=media:;out=bar fails (invalid media URN)
- (void)testWildcard009InvalidOutSpecFails {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:;out=bar" error:&error];
    XCTAssertNil(cap, @"Invalid out spec should fail");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidOutSpec);
}

// TEST_WILDCARD_010: Wildcard in/out match specific caps
- (void)testWildcard010WildcardAcceptsSpecific {
    NSError *error = nil;
    CSCapUrn *wildcard = [CSCapUrn fromString:@"cap:" error:&error];
    CSCapUrn *specific = [CSCapUrn fromString:@"cap:in=media:;out=media:text" error:&error];
    
    XCTAssertTrue([wildcard accepts:specific], @"Wildcard should accept specific cap");
    XCTAssertTrue([specific conformsTo:wildcard], @"Specific should conform to wildcard");
}

// TEST_WILDCARD_011: Specificity - wildcard has 0, specific has tag count
- (void)testWildcard011SpecificityScoring {
    NSError *error = nil;
    CSCapUrn *wildcard = [CSCapUrn fromString:@"cap:" error:&error];
    CSCapUrn *specific = [CSCapUrn fromString:@"cap:in=media:;out=media:text" error:&error];
    
    XCTAssertEqual([wildcard specificity], 0, @"Wildcard should have 0 specificity");
    XCTAssertGreaterThan([specific specificity], 0, @"Specific cap should have non-zero specificity");
}

// TEST_WILDCARD_012: cap:in=media:;out=media:;test preserves other tags
- (void)testWildcard012PreserveOtherTags {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in;out;test" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
    XCTAssertTrue([cap hasMarkerTag:@"test"]);
}

#pragma mark - Dispatch Predicate Tests

// TEST823: is_dispatchable — exact match provider dispatches request
- (void)test823_isDispatchable_exactMatch {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:record;textable\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertTrue([provider isDispatchable:request], @"Exact match should dispatch");
}

// TEST824: is_dispatchable — provider with broader input handles specific request (contravariance)
- (void)test824_isDispatchable_broaderInputHandlesSpecific {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:in=\"media:\";analyze;out=\"media:record;textable\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:pdf\";analyze;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertTrue([provider isDispatchable:request], @"Provider accepting any input should dispatch request with specific pdf input");
}

// TEST825: is_dispatchable — request with unconstrained input dispatches to specific provider media: on the request input axis means "unconstrained" — vacuously true
// media: on the request input axis means "unconstrained" — vacuously true
- (void)test825_isDispatchable_unconstrainedInput {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:in=\"media:pdf\";analyze;out=\"media:record;textable\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:\";analyze;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertTrue([provider isDispatchable:request], @"Request in=media: is unconstrained — axis is vacuously true");
}

// TEST826: is_dispatchable — provider output must satisfy request output (covariance)
- (void)test826_isDispatchable_providerOutputSatisfiesRequest {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:record;textable\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:textable\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertTrue([provider isDispatchable:request], @"Provider output record;textable should satisfy request needing textable");
}

// TEST827: is_dispatchable — provider with generic output cannot satisfy specific request
- (void)test827_isDispatchable_genericOutputCannotSatisfySpecific {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertFalse([provider isDispatchable:request], @"Provider with generic output cannot guarantee specific output");
}

// TEST828: is_dispatchable — wildcard * tag in request, provider missing tag → reject
- (void)test828_isDispatchable_wildcardRequestProviderMissingTag {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:in=\"media:\";infer;out=\"media:textable\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:\";candle=*;infer;out=\"media:textable\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertFalse([provider isDispatchable:request], @"Provider missing candle tag should NOT dispatch request requiring candle=*");
}

// TEST829: is_dispatchable — wildcard * tag in request, provider has tag → accept
- (void)test829_isDispatchable_wildcardRequestProviderHasTag {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:candle=v2;in=\"media:\";infer;out=\"media:textable\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:\";candle=*;infer;out=\"media:textable\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertTrue([provider isDispatchable:request], @"Provider with candle=v2 should dispatch request requiring candle=*");
}

// TEST830: is_dispatchable — provider extra tags are refinement, always OK
- (void)test830_isDispatchable_providerExtraTags {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:backend=mlx;in=\"media:pdf\";extract;out=\"media:textable\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:textable\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertTrue([provider isDispatchable:request], @"Provider with extra backend tag should still dispatch");
}

// TEST831: is_dispatchable — cross-backend mismatch prevented
- (void)test831_isDispatchable_crossBackendMismatch {
    NSError *error;
    CSCapUrn *ggufProvider = [CSCapUrn fromString:@"cap:gguf=*;in=\"media:model-spec;gguf;textable\";infer;out=\"media:textable\"" error:&error];
    CSCapUrn *candleRequest = [CSCapUrn fromString:@"cap:candle=*;in=\"media:model-spec;candle;textable\";infer;out=\"media:textable\"" error:&error];
    XCTAssertNotNil(ggufProvider);
    XCTAssertNotNil(candleRequest);
    XCTAssertFalse([ggufProvider isDispatchable:candleRequest], @"GGUF provider must not dispatch candle request");
}

// TEST832: is_dispatchable is NOT symmetric
- (void)test832_isDispatchable_asymmetric {
    NSError *error;
    CSCapUrn *broad = [CSCapUrn fromString:@"cap:in=\"media:\";process;out=\"media:record;textable\"" error:&error];
    CSCapUrn *narrow = [CSCapUrn fromString:@"cap:in=\"media:pdf\";process;out=\"media:textable\"" error:&error];
    XCTAssertNotNil(broad);
    XCTAssertNotNil(narrow);
    XCTAssertTrue([broad isDispatchable:narrow], @"Broad provider should dispatch narrow request");
    XCTAssertFalse([narrow isDispatchable:broad], @"Narrow provider should NOT dispatch broad request");
}

// TEST833: is_comparable — both directions checked
- (void)test833_isComparable_symmetric {
    NSError *error;
    CSCapUrn *a = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:textable\"" error:&error];
    CSCapUrn *b = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(a);
    XCTAssertNotNil(b);
    XCTAssertTrue([a isComparable:b]);
    XCTAssertTrue([b isComparable:a]);
}

// TEST834: is_comparable — unrelated caps are NOT comparable
- (void)test834_isComparable_unrelated {
    NSError *error;
    CSCapUrn *a = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:textable\"" error:&error];
    CSCapUrn *b = [CSCapUrn fromString:@"cap:in=\"media:audio\";transcribe;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(a);
    XCTAssertNotNil(b);
    XCTAssertFalse([a isComparable:b]);
    XCTAssertFalse([b isComparable:a]);
}

// TEST835: is_equivalent — identical caps
- (void)test835_isEquivalent_identical {
    NSError *error;
    CSCapUrn *a = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:textable\"" error:&error];
    CSCapUrn *b = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:textable\"" error:&error];
    XCTAssertNotNil(a);
    XCTAssertNotNil(b);
    XCTAssertTrue([a isEquivalent:b]);
}

// TEST836: is_equivalent — non-equivalent comparable caps
- (void)test836_isEquivalent_nonEquivalent {
    NSError *error;
    CSCapUrn *a = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:textable\"" error:&error];
    CSCapUrn *b = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(a);
    XCTAssertNotNil(b);
    XCTAssertTrue([a isComparable:b], @"Should be comparable");
    XCTAssertFalse([a isEquivalent:b], @"Should NOT be equivalent — different specificity");
}

// TEST837: is_dispatchable — op tag mismatch rejects
- (void)test837_isDispatchable_opTagMismatch {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:textable\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:pdf\";transform;out=\"media:textable\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertFalse([provider isDispatchable:request], @"Different op tags should prevent dispatch");
}

// TEST838: is_dispatchable — request with wildcard output accepts any provider output
- (void)test838_isDispatchable_requestWildcardOutput {
    NSError *error;
    CSCapUrn *provider = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:record;textable\"" error:&error];
    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=\"media:pdf\";extract;out=\"media:\"" error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNotNil(request);
    XCTAssertTrue([provider isDispatchable:request], @"Request with wildcard output should accept any provider output");
}

// TEST014: Test that escape sequences round-trip correctly
- (void)test014_roundTripEscapes {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=\"media:void\";key=\"value\\\"with\\\\escapes\";out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects([cap getTag:@"key"], @"value\"with\\escapes");
    NSString *serialized = [cap toString];
    CSCapUrn *reparsed = [CSCapUrn fromString:serialized error:&error];
    XCTAssertNotNil(reparsed);
    XCTAssertEqualObjects([cap toString], [reparsed toString]);
}

// TEST018: Test that quoted values with different case do NOT match (case-sensitive)
- (void)test018_matchingCaseSensitiveValues {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:testUrn(@"key=\"Value\"") error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"key=\"value\"") error:&error];
    XCTAssertNotNil(cap1);
    XCTAssertNotNil(cap2);
    XCTAssertFalse([cap1 accepts:cap2]);
    XCTAssertFalse([cap2 accepts:cap1]);

    // Same case should match
    CSCapUrn *cap3 = [CSCapUrn fromString:testUrn(@"key=\"Value\"") error:&error];
    XCTAssertTrue([cap1 accepts:cap3]);
}

// TEST021: Test builder creates cap URN with correct tags and direction specs
- (void)test021_builder {
    NSError *error;
    CSCapUrn *cap = [[[[[[[CSCapUrnBuilder builder]
        inSpec:@"media:void"]
        outSpec:@"media:record;textable"]
        marker:@"generate"]
        tag:@"target" value:@"thumbnail"]
        tag:@"ext" value:@"pdf"]
        build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertTrue([cap hasMarkerTag:@"generate"]);
    XCTAssertEqualObjects([cap getInSpec], @"media:void");
    XCTAssertEqualObjects([cap getOutSpec], @"media:record;textable");
}

// TEST022: Test builder requires both in_spec and out_spec
- (void)test022_builderRequiresDirection {
    NSError *error;

    // Missing in_spec should fail
    CSCapUrn *result1 = [[[[CSCapUrnBuilder builder]
        outSpec:@"media:record;textable"]
        tag:@"op" value:@"test"]
        build:&error];
    XCTAssertNil(result1);

    // Missing out_spec should fail
    error = nil;
    CSCapUrn *result2 = [[[[CSCapUrnBuilder builder]
        inSpec:@"media:void"]
        tag:@"op" value:@"test"]
        build:&error];
    XCTAssertNil(result2);

    // Both present should succeed
    error = nil;
    CSCapUrn *result3 = [[[[CSCapUrnBuilder builder]
        inSpec:@"media:void"]
        outSpec:@"media:record;textable"]
        build:&error];
    XCTAssertNotNil(result3);
}

// TEST023: Test builder lowercases keys but preserves value case
- (void)test023_builderPreservesCase {
    NSError *error;
    CSCapUrn *cap = [[[[[CSCapUrnBuilder builder]
        inSpec:@"media:void"]
        outSpec:@"media:record;textable"]
        tag:@"KEY" value:@"ValueWithCase"]
        build:&error];

    XCTAssertNotNil(cap);
    // Key is lowercase
    XCTAssertEqualObjects([cap getTag:@"key"], @"ValueWithCase");
}

// TEST025: Test find_best_match returns most specific matching cap
- (void)test025_bestMatch {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:testUrn(@"op") error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    CSCapUrn *cap3 = [CSCapUrn fromString:testUrn(@"generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap1);
    XCTAssertNotNil(cap2);
    XCTAssertNotNil(cap3);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"generate") error:&error];
    XCTAssertNotNil(request);
    CSCapUrn *best = [CSCapMatcher findBestMatchInCaps:@[cap1, cap2, cap3] forRequest:request];

    // Most specific cap that accepts the request
    XCTAssertNotNil(best);
    XCTAssertEqualObjects([best getTag:@"ext"], @"pdf");
}

// TEST034: Test empty values are rejected
- (void)test034_emptyValueError {
    NSError *error;
    CSCapUrn *result1 = [CSCapUrn fromString:testUrn(@"key=") error:&error];
    XCTAssertNil(result1);

    error = nil;
    CSCapUrn *result2 = [CSCapUrn fromString:testUrn(@"key=;other=value") error:&error];
    XCTAssertNil(result2);
}

// TEST037: Test with_tag rejects empty value
- (void)test037_withTagRejectsEmptyValue {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"") error:&error];
    XCTAssertNotNil(cap);
    // withTag with empty value — tag should NOT be set
    CSCapUrn *result = [cap withTag:@"key" value:@""];
    XCTAssertNil([result getTag:@"key"]);
}

// TEST047: Matching semantics - thumbnail fallback with void input
- (void)test047_matchingSemantics_thumbnailVoidInput {
    NSError *error;
    NSString *outBin = @"media:binary";
    CSCapUrn *cap = [CSCapUrn fromString:[NSString stringWithFormat:
        @"cap:in=\"media:void\";generate-thumbnail;out=\"%@\"", outBin] error:&error];
    CSCapUrn *request = [CSCapUrn fromString:[NSString stringWithFormat:
        @"cap:ext=wav;in=\"media:void\";generate-thumbnail;out=\"%@\"", outBin] error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNotNil(request);
    XCTAssertTrue([cap accepts:request],
                  @"Thumbnail fallback with void input should match");
}

#pragma mark - CapKind classifier tests (test1800–test1805)
//
// Mirrored across every language port (Rust, Go, Python, Swift/ObjC,
// JS) under the SAME numbers. Any divergence is a wire-level
// inconsistency — the kind taxonomy is part of the protocol's public
// surface, not a per-port detail.

// TEST1800: Identity classifier — only the bare cap: form qualifies.
// Adding any tag (even one that doesn't constrain in/out) demotes
// the cap to Transform because the operation/metadata axis is no
// longer fully generic.
- (void)test1800_kind_identity_only_for_bare_cap {
    NSError *error = nil;

    CSCapUrn *identity = [CSCapUrn fromString:@"cap:" error:&error];
    XCTAssertNotNil(identity, @"%@", error.localizedDescription);
    XCTAssertEqual([identity kind], CSCapKindIdentity);

    NSArray<NSString *> *spellings = @[
        @"cap:in=media:;out=media:",
        @"cap:in=*;out=*",
        @"cap:in=media:",
        @"cap:out=media:",
    ];
    for (NSString *spelling in spellings) {
        CSCapUrn *cap = [CSCapUrn fromString:spelling error:&error];
        XCTAssertNotNil(cap, @"%@: %@", spelling, error.localizedDescription);
        XCTAssertEqual([cap kind], CSCapKindIdentity,
                       @"%@ should classify as Identity (canonical form is `cap:`)",
                       spelling);
    }

    CSCapUrn *withOp = [CSCapUrn fromString:@"cap:passthrough" error:&error];
    XCTAssertNotNil(withOp);
    XCTAssertEqual([withOp kind], CSCapKindTransform,
                   @"cap:passthrough specifies the operation axis — not Identity");
}

// TEST1801: Source classifier — in=media:void, out non-void.
- (void)test1801_kind_source_when_input_is_void {
    NSError *error = nil;

    CSCapUrn *warm = [CSCapUrn fromString:@"cap:in=\"media:void\";out=\"media:model-artifact\";warm" error:&error];
    XCTAssertNotNil(warm);
    XCTAssertEqual([warm kind], CSCapKindSource);

    CSCapUrn *gen = [CSCapUrn fromString:@"cap:in=media:void;out=media:textable" error:&error];
    XCTAssertNotNil(gen);
    XCTAssertEqual([gen kind], CSCapKindSource);
}

// TEST1802: Sink classifier — out=media:void, in non-void.
- (void)test1802_kind_sink_when_output_is_void {
    NSError *error = nil;

    CSCapUrn *discard = [CSCapUrn fromString:@"cap:discard;in=media:;out=media:void" error:&error];
    XCTAssertNotNil(discard);
    XCTAssertEqual([discard kind], CSCapKindSink);

    CSCapUrn *log = [CSCapUrn fromString:@"cap:in=\"media:json;textable\";log;out=media:void" error:&error];
    XCTAssertNotNil(log);
    XCTAssertEqual([log kind], CSCapKindSink);
}

// TEST1803: Effect classifier — both sides void. Reads as `() → ()`.
- (void)test1803_kind_effect_when_both_sides_void {
    NSError *error = nil;

    CSCapUrn *ping = [CSCapUrn fromString:@"cap:in=media:void;out=media:void;ping" error:&error];
    XCTAssertNotNil(ping);
    XCTAssertEqual([ping kind], CSCapKindEffect);

    CSCapUrn *bare = [CSCapUrn fromString:@"cap:in=media:void;out=media:void" error:&error];
    XCTAssertNotNil(bare);
    XCTAssertEqual([bare kind], CSCapKindEffect);
}

// TEST1804: Transform classifier — at least one side non-void, and
// the cap is not the bare identity.
- (void)test1804_kind_transform_for_normal_data_processors {
    NSError *error = nil;

    CSCapUrn *extract = [CSCapUrn fromString:@"cap:extract;in=media:pdf;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(extract);
    XCTAssertEqual([extract kind], CSCapKindTransform);

    CSCapUrn *labeled = [CSCapUrn fromString:@"cap:passthrough;in=media:;out=media:" error:&error];
    XCTAssertNotNil(labeled);
    XCTAssertEqual([labeled kind], CSCapKindTransform);
}

// TEST1805: Kind is invariant under canonicalization. The same
// morphism written in many surface forms must classify the same way
// once parsed.
- (void)test1805_kind_invariant_under_canonical_spellings {
    NSError *error = nil;

    NSArray *cases = @[
        @[@"cap:", @"cap:in=media:;out=media:", @(CSCapKindIdentity)],
        @[@"cap:extract;in=media:pdf;out=media:textable",
          @"cap:extract;in=\"media:pdf\";out=\"media:textable\"",
          @(CSCapKindTransform)],
        @[@"cap:in=media:void;out=media:textable;warm",
          @"cap:warm;out=media:textable;in=media:void",
          @(CSCapKindSource)],
    ];

    for (NSArray *c in cases) {
        NSString *a = c[0];
        NSString *b = c[1];
        CSCapKind expected = (CSCapKind)[c[2] integerValue];

        CSCapUrn *capA = [CSCapUrn fromString:a error:&error];
        XCTAssertNotNil(capA, @"%@", a);
        CSCapUrn *capB = [CSCapUrn fromString:b error:&error];
        XCTAssertNotNil(capB, @"%@", b);

        CSCapKind kindA = [capA kind];
        CSCapKind kindB = [capB kind];

        XCTAssertEqual(kindA, expected, @"%@ should classify as %@", a, CSCapKindToString(expected));
        XCTAssertEqual(kindB, expected, @"%@ should classify as %@", b, CSCapKindToString(expected));
        XCTAssertEqual(kindA, kindB,
                       @"%@ and %@ parse to the same cap and must classify identically",
                       a, b);
    }
}

#pragma mark - Truth-table specificity tests (test1820–test1824)
//
// Mirrored across every language port (Rust, Go, Python, Swift/ObjC,
// JS) under the SAME numbers. Specificity must be the truth-table
// sum across all three axes using the six-form ladder:
//
//   ?x or missing     -> 0   (no constraint)
//   x?=v              -> 1   (absent OR not v)
//   x (=x=*) marker   -> 2   (must-have-any)
//   x!=v              -> 3   (present and not v)
//   x=v exact         -> 4   (must-have-this-value)
//   !x                -> 5   (must-not-have)

// TEST1820: A `?`-valued cap-tag scores 0. Same as missing.
- (void)test1820_specificity_question_is_zero {
    NSError *error = nil;

    CSCapUrn *bare = [CSCapUrn fromString:@"cap:" error:&error];
    XCTAssertNotNil(bare);
    XCTAssertEqual([bare specificity], 0u);

    CSCapUrn *withQ = [CSCapUrn fromString:@"cap:?target" error:&error];
    XCTAssertNotNil(withQ);
    XCTAssertEqual([withQ specificity], 0u,
        @"?x must score 0 (explicit no-constraint, same as missing)");
}

// TEST1821: A `!`-valued cap-tag scores 5 (top of negative chain).
- (void)test1821_specificity_must_not_have_is_five {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:!constrained" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqual([cap specificity], 5u,
        @"!constrained (must-not-have) must score 5");
}

// TEST1822: A `*`-valued cap-tag (including bare markers) scores 2.
- (void)test1822_specificity_must_have_any_is_two {
    NSError *error = nil;

    CSCapUrn *bareMarker = [CSCapUrn fromString:@"cap:extract" error:&error];
    XCTAssertNotNil(bareMarker);
    XCTAssertEqual([bareMarker specificity], 2u,
        @"bare `extract` parses as extract=* (must-have-any) and scores 2");

    CSCapUrn *explicitStar = [CSCapUrn fromString:@"cap:extract=*" error:&error];
    XCTAssertNotNil(explicitStar);
    XCTAssertEqual([explicitStar specificity], 2u,
        @"explicit key=* must score 2 (same as bare marker)");

    XCTAssertEqual([bareMarker specificity], [explicitStar specificity],
        @"bare marker and explicit key=* are the same form and must score identically");
}

// TEST1823: An exact-valued cap-tag scores 4.
- (void)test1823_specificity_exact_value_is_four {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:target=metadata" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqual([cap specificity], 4u,
        @"target=metadata (exact value) must score 4");
}

// TEST1824: All six forms compose additively on a single cap.
// y combining 0+1+2+3+4+5 must sum to 15.
- (void)test1824_specificity_combined_y_axis {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:!constrained;?target;extract;stage!=alpha;target2=metadata;ver?=draft" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqual([cap specificity], 15u,
        @"y combining all six forms (0+1+2+3+4+5) must sum to 15");
}

#pragma mark - Six-form canonicalization tests (test1830–test1835)

- (void)test1830_canonicalize_no_constraint {
    NSError *error = nil;
    NSString *canonical = @"cap:?x";
    for (NSString *input in @[@"cap:?x", @"cap:x?", @"cap:x=?"]) {
        CSCapUrn *cap = [CSCapUrn fromString:input error:&error];
        XCTAssertNotNil(cap, @"input %@ must parse", input);
        XCTAssertEqualObjects([cap toString], canonical,
            @"input %@ must canonicalize to %@", input, canonical);
    }
}

// TEST1831: ?x=v and x?=v both canonicalize to x?=v. The third
// hypothetical form `x=?v` is NOT recognized as a qualifier — a
// value starting with `?` is just an exact value beginning with
// a `?` character.
- (void)test1831_canonicalize_absent_or_not_value {
    NSError *error = nil;
    NSString *canonical = @"cap:x?=foo";
    for (NSString *input in @[@"cap:?x=foo", @"cap:x?=foo"]) {
        CSCapUrn *cap = [CSCapUrn fromString:input error:&error];
        XCTAssertNotNil(cap, @"input %@ must parse", input);
        XCTAssertEqualObjects([cap toString], canonical,
            @"input %@ must canonicalize to %@", input, canonical);
    }

    // `x=?foo` is a plain exact tag whose value is the string `?foo`
    // — NOT a canonicalization alias.
    CSCapUrn *exact = [CSCapUrn fromString:@"cap:x=?foo" error:&error];
    XCTAssertNotNil(exact);
    XCTAssertEqualObjects([exact toString], @"cap:x=?foo");
    XCTAssertEqualObjects([exact getTag:@"x"], @"?foo");
}

- (void)test1832_canonicalize_must_have_any {
    NSError *error = nil;
    NSString *canonical = @"cap:x";
    for (NSString *input in @[@"cap:x", @"cap:x=*"]) {
        CSCapUrn *cap = [CSCapUrn fromString:input error:&error];
        XCTAssertNotNil(cap, @"input %@ must parse", input);
        XCTAssertEqualObjects([cap toString], canonical,
            @"input %@ must canonicalize to %@", input, canonical);
    }
}

// TEST1833: !x=v and x!=v both canonicalize to x!=v. The third
// hypothetical form `x=!v` is NOT recognized as a qualifier — a
// value starting with `!` is just an exact value beginning with
// a `!` character.
- (void)test1833_canonicalize_present_not_value {
    NSError *error = nil;
    NSString *canonical = @"cap:x!=foo";
    for (NSString *input in @[@"cap:!x=foo", @"cap:x!=foo"]) {
        CSCapUrn *cap = [CSCapUrn fromString:input error:&error];
        XCTAssertNotNil(cap, @"input %@ must parse", input);
        XCTAssertEqualObjects([cap toString], canonical,
            @"input %@ must canonicalize to %@", input, canonical);
    }

    // `x=!foo` is a plain exact tag whose value is the string `!foo`
    // — NOT a canonicalization alias.
    CSCapUrn *exact = [CSCapUrn fromString:@"cap:x=!foo" error:&error];
    XCTAssertNotNil(exact);
    XCTAssertEqualObjects([exact toString], @"cap:x=!foo");
    XCTAssertEqualObjects([exact getTag:@"x"], @"!foo");
}

- (void)test1834_canonicalize_exact_value {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:x=foo" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects([cap toString], @"cap:x=foo");
}

- (void)test1835_canonicalize_must_not_have {
    NSError *error = nil;
    NSString *canonical = @"cap:!x";
    for (NSString *input in @[@"cap:!x", @"cap:x!", @"cap:x=!"]) {
        CSCapUrn *cap = [CSCapUrn fromString:input error:&error];
        XCTAssertNotNil(cap, @"input %@ must parse", input);
        XCTAssertEqualObjects([cap toString], canonical,
            @"input %@ must canonicalize to %@", input, canonical);
    }
}

// TEST1842: Full 6×6 truth table.
- (void)test1842_truth_table_full_cross_product {
    NSError *error = nil;
    NSArray *forms = @[@"", @"?x", @"x?=v", @"x", @"x!=v", @"x=v", @"!x"];
    BOOL expected[7][7] = {
        // miss   ?x    x?=v   x      x!=v   x=v    !x
        {YES,  YES,  YES,  NO,    NO,    NO,    YES},   // missing
        {YES,  YES,  YES,  YES,   YES,   YES,   YES},   // ?x
        {YES,  YES,  YES,  NO,    NO,    NO,    YES},   // x?=v
        {YES,  YES,  YES,  YES,   YES,   YES,   NO},    // x
        {YES,  YES,  YES,  YES,   YES,   NO,    NO},    // x!=v
        {YES,  YES,  NO,   YES,   NO,    YES,   NO},    // x=v
        {YES,  YES,  YES,  NO,    NO,    NO,    YES},   // !x
    };
    for (NSUInteger i = 0; i < forms.count; i++) {
        for (NSUInteger j = 0; j < forms.count; j++) {
            NSString *instForm = forms[i];
            NSString *pattForm = forms[j];
            NSString *instStr = instForm.length == 0 ? @"cap:" : [@"cap:" stringByAppendingString:instForm];
            NSString *pattStr = pattForm.length == 0 ? @"cap:" : [@"cap:" stringByAppendingString:pattForm];
            CSCapUrn *inst = [CSCapUrn fromString:instStr error:&error];
            CSCapUrn *patt = [CSCapUrn fromString:pattStr error:&error];
            XCTAssertNotNil(inst);
            XCTAssertNotNil(patt);
            BOOL actual = [patt accepts:inst];
            XCTAssertEqual(actual, expected[i][j],
                @"cell (inst=%@, patt=%@) expected %d got %d",
                instForm, pattForm, expected[i][j], actual);
        }
    }
}

// TEST1843: Invalid qualifier combinations must be rejected.
- (void)test1843_reject_invalid_combinations {
    NSError *error = nil;
    NSArray *invalid = @[
        @"cap:?x?=v", @"cap:!x!=v", @"cap:?!x", @"cap:!?x",
        @"cap:?x=*", @"cap:!x=*",
        @"cap:?x=?", @"cap:?x=!", @"cap:!x=?", @"cap:!x=!",
        @"cap:?", @"cap:!",
    ];
    for (NSString *input in invalid) {
        error = nil;
        CSCapUrn *cap = [CSCapUrn fromString:input error:&error];
        XCTAssertNil(cap, @"input %@ must be rejected", input);
    }
}

// TEST1844: out-axis difference dominates combined in+y differences.
- (void)test1844_axis_weighting_out_dominates {
    NSError *error = nil;
    CSCapUrn *bigOut = [CSCapUrn fromString:@"cap:in=media:;out=\"media:record;textable\"" error:&error];
    XCTAssertNotNil(bigOut);
    CSCapUrn *bigInAndY = [CSCapUrn fromString:
        @"cap:in=media:pdf;out=media:record;!constrained;?target;extract;stage!=alpha;target2=metadata;ver?=draft"
        error:&error];
    XCTAssertNotNil(bigInAndY);
    XCTAssertGreaterThan([bigOut specificity], [bigInAndY specificity],
        @"out-axis difference must dominate combined in+y differences");
}

// TEST1845: With equal out, in-axis dominates over y-axis.
- (void)test1845_axis_weighting_in_dominates_y {
    NSError *error = nil;
    CSCapUrn *bigIn = [CSCapUrn fromString:@"cap:in=media:pdf;out=media:record" error:&error];
    XCTAssertNotNil(bigIn);
    CSCapUrn *bigY = [CSCapUrn fromString:
        @"cap:in=media:;out=media:record;!constrained;?target;extract;stage!=alpha;target2=metadata;ver?=draft"
        error:&error];
    XCTAssertNotNil(bigY);
    XCTAssertGreaterThan([bigIn specificity], [bigY specificity],
        @"in-axis difference must dominate y-axis");
}

// TEST1846: Decoded layout — 10000*out + 100*in + y.
- (void)test1846_axis_weighting_decoded_layout {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=\"media:a;b\";out=\"media:a;b;c;d\";extract" error:&error];
    XCTAssertNotNil(cap);
    // out=4 markers (8), in=2 markers (4), y=1 marker (2)
    // 10000*8 + 100*4 + 2 = 80402
    XCTAssertEqual([cap specificity], (NSUInteger)(10000*8 + 100*4 + 2));
}

@end
