//
//  CSFabricAliasTests.m
//  CapDAGTests
//
//  Fabric alias tests — mirror the Rust reference (capdag) test-for-test.
//  Shared test numbers (1880-1892) test the same behavior, with the same
//  method, across every capdag implementation. The objc mirror has no
//  machine-notation parser, so the notation-parser tests 1883-1886 do not
//  apply here (they belong only to mirrors that implement that parser).
//

#import <XCTest/XCTest.h>
#import "CSFabricRegistry.h"
#import "CSCap.h"
#import "CSCapUrn.h"

@interface CSFabricAliasTests : XCTestCase
@end

@implementation CSFabricAliasTests

static CSCap *buildExtractCap(void) {
    NSError *e = nil;
    CSCapUrn *urn = [CSCapUrn fromString:@"cap:extract;in=\"media:ext=pdf\";out=\"media:enc=utf-8\"" error:&e];
    return [CSCap capWithUrn:urn
                       title:@"extract"
                     command:@"extract"
                 description:nil
               documentation:nil
                    metadata:@{}
                        args:@[]
                      output:nil
                metadataJSON:nil];
}

// TEST1880: alias name normalization lowercases and accepts the allowed char
// class; rejects colon, whitespace, and out-of-class chars.
- (void)test1880_AliasNameNormalizationRules {
    NSError *err = nil;
    XCTAssertEqualObjects(CSNormalizeAliasName(@"JSONDoc", &err), @"jsondoc");
    XCTAssertEqualObjects(CSNormalizeAliasName(@"my.alias-1_x", &err), @"my.alias-1_x");

    XCTAssertNil(CSNormalizeAliasName(@"", &err));
    XCTAssertNil(CSNormalizeAliasName(@"pdf:text", &err));
    XCTAssertNil(CSNormalizeAliasName(@"my alias", &err));
    XCTAssertNil(CSNormalizeAliasName(@"a/b", &err));
}

// TEST1881: URN-vs-alias detection keys purely on the presence of ':'.
- (void)test1881_TokenURNvsAliasDetection {
    XCTAssertTrue(CSTokenIsURN(@"cap:in=\"media:ext=pdf\";extract;out=\"media:enc=utf-8\""));
    XCTAssertTrue(CSTokenIsURN(@"media:fmt=json;record"));
    XCTAssertFalse(CSTokenIsURN(@"pdf2text"));
    XCTAssertTrue(CSIsAliasToken(@"pdf2text"));
    XCTAssertFalse(CSIsAliasToken(@"media:enc=utf-8"));
}

// TEST1882: alias target classification distinguishes cap from media by
// prefix and rejects a non-URN target.
- (void)test1882_ClassifyAliasTargetByPrefix {
    CSAliasTargetKind kind;
    XCTAssertTrue(CSClassifyAliasTarget(@"media:fmt=json;record", &kind));
    XCTAssertEqual(kind, CSAliasTargetKindMedia);

    XCTAssertTrue(CSClassifyAliasTarget(@"cap:effect=patch;in=\"media:image\";name;out=\"media:ext=png;image\"", &kind));
    XCTAssertEqual(kind, CSAliasTargetKindCap);

    XCTAssertFalse(CSClassifyAliasTarget(@"not-a-urn", NULL));
}

// TEST1887: the Manifest type round-trips an `aliases` map.
- (void)test1887_ManifestRoundTripsAliases {
    CSFabricRegistry *reg = [[CSFabricRegistry alloc] initForTest];
    [reg insertCachedAliasForTest:@{@"name": @"pdf2text", @"target": @"cap:effect=none", @"version": @3}];
    [reg insertCachedAliasForTest:@{@"name": @"jsondoc", @"target": @"media:fmt=json;record", @"version": @1}];
    NSDictionary *m = [reg manifestDictionary];
    NSDictionary *aliases = m[@"aliases"];
    XCTAssertEqualObjects(aliases[@"pdf2text"], @3);
    XCTAssertEqualObjects(aliases[@"jsondoc"], @1);
}

// TEST1888: resolve alias returns the alias target untyped; case-insensitive; malformed name rejected.
- (void)test1888_ResolveAliasReturnsTarget {
    CSFabricRegistry *reg = [[CSFabricRegistry alloc] initForTest];
    [reg insertCachedAliasForTest:@{@"name": @"jsondoc", @"target": @"media:fmt=json;record", @"version": @1}];

    XCTestExpectation *e1 = [self expectationWithDescription:@"lower"];
    [reg resolveAlias:@"jsondoc" completion:^(NSString *target, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(target, @"media:fmt=json;record");
        [e1 fulfill];
    }];
    XCTestExpectation *e2 = [self expectationWithDescription:@"mixed-case"];
    [reg resolveAlias:@"JSONDoc" completion:^(NSString *target, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(target, @"media:fmt=json;record");
        [e2 fulfill];
    }];
    XCTestExpectation *e3 = [self expectationWithDescription:@"malformed"];
    [reg resolveAlias:@"bad:name" completion:^(NSString *target, NSError *error) {
        XCTAssertNotNil(error);
        [e3 fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

// TEST1889: resolve alias typed enforces the expected kind.
- (void)test1889_ResolveAliasTypedEnforcesKind {
    CSFabricRegistry *reg = [[CSFabricRegistry alloc] initForTest];
    [reg insertCachedAliasForTest:@{@"name": @"jsondoc", @"target": @"media:fmt=json;record", @"version": @1}];

    XCTestExpectation *ok = [self expectationWithDescription:@"media ok"];
    [reg resolveAliasTyped:@"jsondoc" expected:CSAliasTargetKindMedia completion:^(NSString *target, NSError *error) {
        XCTAssertNil(error);
        [ok fulfill];
    }];
    XCTestExpectation *any = [self expectationWithDescription:@"untyped ok"];
    [reg resolveAliasTyped:@"jsondoc" expected:-1 completion:^(NSString *target, NSError *error) {
        XCTAssertNil(error);
        [any fulfill];
    }];
    XCTestExpectation *bad = [self expectationWithDescription:@"wrong kind"];
    [reg resolveAliasTyped:@"jsondoc" expected:CSAliasTargetKindCap completion:^(NSString *target, NSError *error) {
        XCTAssertNotNil(error, @"a media alias demanded as a cap must fail hard");
        [bad fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

// TEST1890: getCap accepts a cap alias and returns the aliased cap; a media
// alias passed to getCap fails hard (typed boundary).
- (void)test1890_GetCapViaAliasAndTypeMismatch {
    CSFabricRegistry *reg = [[CSFabricRegistry alloc] initForTest];
    CSCap *cap = buildExtractCap();
    NSString *canonical = [cap.capUrn toString];
    [reg insertCachedCapForTest:cap];
    [reg insertCachedAliasForTest:@{@"name": @"pdf2text", @"target": canonical, @"version": @1}];

    XCTestExpectation *ok = [self expectationWithDescription:@"cap alias"];
    [reg getCapWithUrn:@"pdf2text" completion:^(CSCap *got, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects([got.capUrn toString], canonical);
        [ok fulfill];
    }];

    [reg insertCachedAliasForTest:@{@"name": @"jsondoc", @"target": @"media:fmt=json;record", @"version": @1}];
    XCTestExpectation *bad = [self expectationWithDescription:@"media alias at getCap"];
    [reg getCapWithUrn:@"jsondoc" completion:^(CSCap *got, NSError *error) {
        XCTAssertNotNil(error, @"a media alias at getCap must fail hard");
        [bad fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

// TEST1891: getMediaDef accepts a media alias and returns the aliased spec; a
// cap alias passed to getMediaDef fails hard.
- (void)test1891_GetMediaDefViaAliasAndTypeMismatch {
    CSFabricRegistry *reg = [[CSFabricRegistry alloc] initForTest];
    [reg addMediaDef:@{@"urn": @"media:fmt=json;record", @"media_type": @"application/json", @"title": @"JSON"}];
    [reg insertCachedAliasForTest:@{@"name": @"jsondoc", @"target": @"media:fmt=json;record", @"version": @1}];

    XCTestExpectation *ok = [self expectationWithDescription:@"media alias"];
    [reg getMediaDef:@"jsondoc" completion:^(NSDictionary *spec, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(spec[@"urn"], @"media:fmt=json;record");
        [ok fulfill];
    }];

    [reg insertCachedAliasForTest:@{@"name": @"pdf2text",
                                    @"target": @"cap:extract;in=\"media:ext=pdf\";out=\"media:enc=utf-8\"",
                                    @"version": @1}];
    XCTestExpectation *bad = [self expectationWithDescription:@"cap alias at getMediaDef"];
    [reg getMediaDef:@"pdf2text" completion:^(NSDictionary *spec, NSError *error) {
        XCTAssertNotNil(error, @"a cap alias at getMediaDef must fail hard");
        [bad fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

// TEST1892: an unknown alias name is a hard not-found, never a silent empty.
- (void)test1892_UnknownAliasIsNotFound {
    CSFabricRegistry *reg = [[CSFabricRegistry alloc] initForTest];

    XCTestExpectation *e1 = [self expectationWithDescription:@"getAlias unknown"];
    [reg getAlias:@"nosuchalias" completion:^(NSDictionary *alias, NSError *error) {
        XCTAssertNil(alias);
        XCTAssertNotNil(error);
        [e1 fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    NSError *err = nil;
    [reg aliasDefverFor:@"nosuchalias" error:&err];
    XCTAssertNotNil(err);

    XCTAssertNil([reg resolveAliasCached:@"nosuchalias"]);
    XCTAssertNil([reg resolveAliasCached:@"bad:name"]);
}

@end
