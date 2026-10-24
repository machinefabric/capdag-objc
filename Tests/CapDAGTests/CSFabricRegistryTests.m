//
//  CSFabricRegistryTests.m
//  CapDAGTests
//
//  Tests for registry functionality
//

#import <XCTest/XCTest.h>
#import <CommonCrypto/CommonDigest.h>
#import "CSFabricRegistry.h"
#import "CSCharter.h"
#import "CSFabricManifestVersion.h"
#import "CSCap.h"
#import "CSCapUrn.h"

@interface CSFabricRegistryTests : XCTestCase

@end

/// The URN-normalisation helpers and the manifest-version pin are internal to
/// CSFabricRegistry.m (not in the public header). Declare the selectors here
/// so TEST6396 can assert the normalisation contract and TEST0144 can assert
/// the registry's pinned manifest version directly.
@interface CSFabricRegistry (CSFabricRegistryTestsInternal)
- (nullable NSString *)normalizeCapUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)normalizeMediaUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error;
- (uint32_t)manifestVersion;
- (NSString *)sha256HexForString:(NSString *)s;
- (NSString *)objectURLForKind:(NSString *)kind digest:(NSString *)digest defver:(uint32_t)defver;
@end

// The per-cap URL at defver 1, from the charter's `definition` location of a
// test registry — built through the registry's own object-path rule, as
// production builds it. nil for a URN that does not parse.
static NSString *_Nullable buildRegistryURL(NSString *urn) {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    NSString *normalized = [registry normalizeCapUrn:urn error:nil];
    if (!normalized) return nil;
    return [registry objectURLForKind:@"caps" digest:[registry sha256HexForString:normalized] defver:1];
}

@implementation CSFabricRegistryTests

// TEST1899: a media def resolves to the charter's `definition` location at the
// defver its manifest pins — `/media/<sha>/<defver>.json` in the publisher's
// layout. There is no other path: the pre-manifest flat layout is gone, and a
// client that composed one would 404 every lookup, as the app's media-title
// resolver once did against a staging-v1 registry. This pins BOTH the URL rule
// and the manifest-driven defver resolution. Mirrors the Rust reference's
// test1899_media_def_resolves_to_versioned_object_path_under_manifest.
- (void)test1899_mediaDefResolvesToVersionedObjectPathUnderManifest {
    // The pin is baked, never read from the process environment: reproduce the
    // exact failure environment (NO MFR_FABRIC_MANIFEST_VERSION) and confirm the
    // registry still pins at v >= 1 rather than silently degrading to v0.
    XCTAssertGreaterThanOrEqual(CSBakedFabricManifestVersion, 1u,
        @"the baked fabric manifest version must be >= 1; v0 is never a valid target");
    unsetenv("MFR_FABRIC_MANIFEST_VERSION");

    // 1. Object-path rule: the charter's definition location, at the defver.
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest]; // pinned at manifest v1
    XCTAssertGreaterThanOrEqual(registry.manifestVersion, 1u,
        @"the production registry must be pinned at manifest v >= 1, never the legacy v0 flat-path mode");

    NSString *urn = @"media:enc=utf-8;ext=md";
    NSString *digest = [registry sha256HexForString:urn];
    // Assert against the registry's OWN anchor, not a hardcoded host: under a
    // workspace test run against staging the process env points the default
    // config at the staging fabric, and the URL rule is independent of which
    // registry is configured.
    NSString *base = registry.charter.anchor;

    NSString *versioned = [registry objectURLForKind:@"media" digest:digest defver:1];
    XCTAssertEqualObjects(versioned,
        ([NSString stringWithFormat:@"%@/media/%@/1.json", base, digest]),
        @"a def at manifest defver 1 must resolve to the versioned object path");

    // 2. Manifest-driven defver: a media def seeded under a v >= 1 manifest
    // resolves to its pinned defver (versioned), never 0.
    [registry addMediaDef:@{
        @"urn": urn,
        @"title": @"Markdown",
        @"version": @1,
        @"extensions": @[@"md"],
    }];
    NSError *defverError = nil;
    uint32_t defver = 0;
    XCTAssertTrue([registry mediaDefverFor:urn defver:&defver error:&defverError],
        @"a seeded media def must resolve a defver: %@", defverError.localizedDescription);
    XCTAssertEqual(defver, registry.manifestVersion,
        @"a published media def under a v >= 1 manifest must resolve to the pinned defver, not 0");

    // 3. A URN that is NOT part of the snapshot is a hard NotFound — the registry
    // does NOT silently fall back to defver 0 (the flat path that 404s). This is
    // the fail-hard contract that replaced the silent v0 fallback.
    NSError *missingError = nil;
    uint32_t missingDefver = 99;
    XCTAssertFalse([registry mediaDefverFor:@"media:enc=utf-8;ext=zzz-not-in-snapshot"
                                     defver:&missingDefver
                                      error:&missingError],
        @"a URN outside the manifest must NOT resolve to a defver");
    XCTAssertNotNil(missingError, @"an out-of-snapshot URN must surface a NotFound error");
    XCTAssertTrue([missingError.localizedDescription containsString:@"not part of manifest"],
        @"the error must name the missing-from-manifest cause, not a misleading 404: %@",
        missingError.localizedDescription);
}

// TEST614: Registry creation. Uses the network-free test constructor — the
// production `init` blocks on a manifest fetch (and fails hard if the registry
// is unreachable), so unit tests use initForTest, mirroring Rust new_for_test.
- (void)test614_RegistryCreation {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    XCTAssertNotNil(registry);
}

// Registry validator tests removed - not part of current API

- (void)test6435_RegistryValidCapCheck {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    
    // Test that registry checks if cap exists in cache
    BOOL exists1 = [registry capExists:@"cap:in=media:void;extract;out=\"media:enc=utf-8;record\";target=metadata"];
    BOOL exists2 = [registry capExists:@"cap:in=media:void;different;out=\"media:enc=utf-8;record\""];
    
    // These should both be NO since cache is empty initially
    XCTAssertFalse(exists1);
    XCTAssertFalse(exists2);
}

// MARK: - Per-cap URL Construction Tests

/// Per-cap URLs use /caps/<sha256-hex> — no URN-grammar characters
/// in the path, so no percent-encoding gymnastics.
- (void)test6388_PerCapURLUsesSHA256 {
    NSString *registryURL = buildRegistryURL(@"cap:in=media:string;test;out=\"media:enc=utf-8;record\"");

    XCTAssertTrue([registryURL containsString:@"/caps/"], @"URL must use the /caps/ path prefix");
    XCTAssertFalse([registryURL containsString:@"cap:"] || [registryURL containsString:@"cap%3A"],
                   @"URL must not contain raw or percent-encoded URN syntax");
    XCTAssertFalse([registryURL containsString:@"%3A"], @"URL must not contain percent-encoded URN characters");
    XCTAssertFalse([registryURL containsString:@"%3D"], @"URL must not contain percent-encoded URN characters");
    XCTAssertFalse([registryURL containsString:@"%3B"], @"URL must not contain percent-encoded URN characters");
}

/// TEST6391: Equivalent URNs (different tag order, etc.) hash to the
/// same key. This is the property that makes cross-language lookups
/// land at the same registry object regardless of which capdag
/// implementation issued the request. Inputs MUST quote any
/// multi-tag media URN value — the previous unquoted spelling
/// `out=media:task;id` was actually a different URN (the bare
/// `media:task` plus a separate `id` op tag), and treating those
/// two URNs as equivalent here masked a real spec violation.
- (void)test6391_sameCapDifferentSpellingsSameURL {
    NSString *urlA = buildRegistryURL(@"cap:in=\"media:listing-id\";use-grinder;out=\"media:task;id\"");
    NSString *urlB = buildRegistryURL(@"cap:out=\"media:task;id\";in=\"media:listing-id\";use-grinder");
    XCTAssertEqualObjects(urlA, urlB, @"Equivalent URNs must hash to the same registry key");
}

/// TEST141: URL has the right shape — /caps/ prefix, 64 hex chars, and the
/// defver as the last segment.
- (void)test141_perCapURLShape {
    NSString *registryURL = buildRegistryURL(@"cap:in=\"media:listing-id\";use-grinder;out=\"media:task;id\"");

    NSURL *url = [NSURL URLWithString:registryURL];
    XCTAssertNotNil(url, @"Generated URL must be valid");
    NSRange caps = [url.path rangeOfString:@"/caps/"];
    XCTAssertNotEqual(caps.location, (NSUInteger)NSNotFound);
    NSArray<NSString *> *rest = [[url.path substringFromIndex:NSMaxRange(caps)] componentsSeparatedByString:@"/"];
    XCTAssertEqual(rest.count, 2u, @"the URL is /caps/<hash>/<defver>.json: %@", registryURL);
    XCTAssertEqual(rest.firstObject.length, 64u, @"SHA-256 hex digest is 64 characters");
    XCTAssertEqualObjects(rest.lastObject, @"1.json", @"the defver is the last segment");
}

/// TEST142: Different tag orders normalise to the same URL — the
/// canonicaliser strips the variation before hashing.
- (void)test142_normalizeHandlesDifferentTagOrders {
    NSString *url1 = buildRegistryURL(@"cap:test;in=\"media:string\";out=\"media:object\"");
    NSString *url2 = buildRegistryURL(@"cap:in=\"media:string\";out=\"media:object\";test");
    XCTAssertEqualObjects(url1, url2, @"Different tag orders should produce the same URL");
}

// TEST1893: a fabric's cache folder is its CHARTER's slug, and a charter stored
// there is what an offline client finds its fabric by — matched by anchor,
// never by folder name. A prod-populated cache can therefore never satisfy a
// staging lookup: two registries have two charters and two slugs, whatever
// their URLs look like.
- (void)test1893_cacheFolderIsTheChartersSlugAndFoundByAnchor {
    NSString *cache = [NSTemporaryDirectory() stringByAppendingPathComponent:
                       [@"capdag-1893-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    void (^store)(NSString *, NSString *, NSString *) = ^(NSString *anchor, NSString *slug, NSString *manifest) {
        NSMutableDictionary *fields = [[[CSFabricRegistry publisherLayoutCharterForAnchor:anchor slug:slug]
                                        dictionaryRepresentation] mutableCopy];
        if (manifest) {
            NSMutableDictionary *locations = [fields[@"locations"] mutableCopy];
            locations[@"manifest"] = manifest;
            fields[@"locations"] = locations;
        }
        NSData *body = [NSJSONSerialization dataWithJSONObject:fields options:0 error:nil];
        NSError *error = nil;
        CSCharter *charter = [CSCharter charterWithData:body error:&error];
        XCTAssertNotNil(charter, @"%@", error);
        CSFetchedCharter *fetched = [[CSFetchedCharter alloc] initWithCharter:charter body:body
                                                                    signature:[@"sig" dataUsingEncoding:NSUTF8StringEncoding]];
        XCTAssertTrue([fetched storeInFolder:[cache stringByAppendingPathComponent:slug] error:&error], @"%@", error);
    };
    NSString *anchor = @"https://registry.example/fabric";
    // Another fabric's folder is beside it, with its own charter, and is not
    // taken for it; nor is a folder named like this anchor's host.
    store(@"https://fabric.capdag.com", @"fabric.capdag.com", nil);
    [[NSFileManager defaultManager] createDirectoryAtPath:[cache stringByAppendingPathComponent:@"registry.example"]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    store(anchor, @"example-fabric", [anchor stringByAppendingString:@"/m/{manifest_version}"]);

    // A session with no network: the stored charter is found without it.
    NSURLSessionConfiguration *offline = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    offline.protocolClasses = @[];
    offline.timeoutIntervalForResource = 1;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:offline];
    NSError *error = nil;
    CSCharter *found = [CSFabricRegistry resolveCharterForAnchor:anchor cacheRoot:cache session:session error:&error];
    XCTAssertNotNil(found, @"the stored charter is found offline, by its anchor: %@", error);
    XCTAssertEqualObjects(found.slug, @"example-fabric");
    XCTAssertEqualObjects([found locationNamed:@"manifest" values:@{@"manifest_version": @"11"} error:nil],
                          @"https://registry.example/fabric/m/11",
                          @"the manifest is where the charter says, not where a URL convention would put it");
    CSCharter *other = [CSFabricRegistry resolveCharterForAnchor:@"https://fabric.capdag.com" cacheRoot:cache
                                                         session:session error:&error];
    XCTAssertEqualObjects(other.slug, @"fabric.capdag.com", @"each anchor finds its own charter");
    [[NSFileManager defaultManager] removeItemAtPath:cache error:nil];
}

// TEST6396: A malformed cap URN must FAIL HARD — surfaced as an NSError, not
// passed through raw (the old fallback) to surface later as a misleading
// not-found. The `out` value below contains an unquoted `=`, which the cap
// grammar rejects. Against the old `parsed ? [parsed toString] : urn` fallback,
// normalizeCapUrn: returned the raw string and the cache lookup reported a
// (misleading) miss; this test asserts the truthful error and that the process
// never crashes. Mirrors Rust test6396_malformed_cap_urn_fails_hard.
- (void)test6396_malformedCapUrnFailsHard {
    NSString *malformed = @"cap:coerce;in=\"media:integer;numeric\";out=media:enc=utf-8";

    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];

    // Direct normalisation path: nil + populated NSError, never the raw string.
    NSError *normError = nil;
    NSString *normalized = [registry normalizeCapUrn:malformed error:&normError];
    XCTAssertNil(normalized, @"malformed cap URN must not normalise to a (raw) string");
    XCTAssertNotNil(normError, @"malformed cap URN must populate an NSError");
    XCTAssertNotEqualObjects(normalized, malformed,
        @"normalizeCapUrn: must not fall back to the raw input on parse failure");

    // Public resolution path (getCapWithUrn:) must surface a parse error, NOT a
    // misleading not-found, and must not crash.
    XCTestExpectation *expectation = [self expectationWithDescription:@"malformed cap URN resolution"];
    [registry getCapWithUrn:malformed completion:^(CSCap *cap, NSError *error) {
        XCTAssertNil(cap, @"malformed cap URN must not resolve to a cap");
        XCTAssertNotNil(error, @"malformed cap URN must surface an error through the resolution path");
        XCTAssertTrue([error.localizedDescription containsString:@"malformed cap URN"],
            @"error must identify the malformed URN, not report a misleading not-found: %@",
            error.localizedDescription);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

// Note: These tests would make actual HTTP requests to capdag.com
// Uncomment to test with real registry
/*
// TEST6441: Get cap definition real
- (void)test6441_GetCapDefinitionReal {
    CSFabricRegistry *registry = [CSFabricRegistry registry];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Get cap definition"];
    
    [registry getCapDefinition:@"cap:in=media:void;extract;out=\"media:enc=utf-8;record\";target=metadata" completion:^(CSRegistryCapDefinition *definition, NSError *error) {
        if (error) {
            NSLog(@"Skipping real registry test: %@", error);
        } else {
            XCTAssertNotNil(definition);
            XCTAssertEqualObjects(definition.urn, @"cap:in=media:void;extract;out=\"media:enc=utf-8;record\";target=metadata");
            XCTAssertNotNil(definition.version);
            XCTAssertNotNil(definition.primaryAlias);
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

// TEST6443: Validate cap canonical
- (void)test6443_ValidateCapCanonical {
    CSRegistryValidator *validator = [CSRegistryValidator validator];
    
    NSError *error;
    CSCapUrn *urn = [CSCapUrn fromString:@"cap:in=media:void;extract;out=\"media:enc=utf-8;record\";target=metadata" error:&error];
    XCTAssertNotNil(urn);
    
    CSCap *cap = [CSCap capWithUrn:urn
                             title:@"Extract Metadata"
                           aliases:@[@"extract-metadata"]
                       description:nil
                     documentation:nil
                          metadata:@{}
                        mediaDefs:@[]
                              args:@[]
                            outputs:@[]
                      metadataJSON:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Validate cap"];
    
    [validator validateCapCanonical:cap completion:^(NSError *error) {
        if (error) {
            NSLog(@"Validation error (expected if registry has different version): %@", error);
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}
*/

@end
