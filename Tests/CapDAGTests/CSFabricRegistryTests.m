//
//  CSFabricRegistryTests.m
//  CapDAGTests
//
//  Tests for registry functionality
//

#import <XCTest/XCTest.h>
#import <CommonCrypto/CommonDigest.h>
#import "CSFabricRegistry.h"
#import "CSCap.h"
#import "CSCapUrn.h"

@interface CSFabricRegistryTests : XCTestCase

@end

// Per-cap URL construction. The new scheme uses /caps/<sha256>,
// where the hash is computed over the canonical URN's UTF-8 bytes.
// This replicates the construction logic from CSFabricRegistry.
static NSString *buildRegistryURL(NSString *urn) {
    NSString *registryBaseURL = @"https://fabric.capdag.com";

    // Normalize the cap URN using the proper parser
    NSString *normalizedUrn = urn;
    NSError *parseError = nil;
    CSCapUrn *parsedUrn = [CSCapUrn fromString:urn error:&parseError];
    if (parsedUrn) {
        normalizedUrn = [parsedUrn toString];
    }

    NSData *data = [normalizedUrn dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [NSString stringWithFormat:@"%@/caps/%@", registryBaseURL, hex];
}

@implementation CSFabricRegistryTests

- (void)testRegistryCreation {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] init];
    XCTAssertNotNil(registry);
}

// Registry validator tests removed - not part of current API

- (void)testRegistryValidCapCheck {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] init];
    
    // Test that registry checks if cap exists in cache
    BOOL exists1 = [registry capExists:@"cap:in=media:void;extract;out=\"media:record;textable\";target=metadata"];
    BOOL exists2 = [registry capExists:@"cap:in=media:void;different;out=\"media:record;textable\""];
    
    // These should both be NO since cache is empty initially
    XCTAssertFalse(exists1);
    XCTAssertFalse(exists2);
}

// MARK: - Per-cap URL Construction Tests

/// Per-cap URLs use /caps/<sha256-hex> — no URN-grammar characters
/// in the path, so no percent-encoding gymnastics.
- (void)testPerCapURLUsesSHA256 {
    NSString *registryURL = buildRegistryURL(@"cap:in=media:string;test;out=\"media:record;textable\"");

    XCTAssertTrue([registryURL containsString:@"/caps/"], @"URL must use the /caps/ path prefix");
    XCTAssertFalse([registryURL containsString:@"cap:"] || [registryURL containsString:@"cap%3A"],
                   @"URL must not contain raw or percent-encoded URN syntax");
    XCTAssertFalse([registryURL containsString:@"%3A"], @"URL must not contain percent-encoded URN characters");
    XCTAssertFalse([registryURL containsString:@"%3D"], @"URL must not contain percent-encoded URN characters");
    XCTAssertFalse([registryURL containsString:@"%3B"], @"URL must not contain percent-encoded URN characters");
}

/// TEST140: Equivalent URNs (different tag order, etc.) hash to the
/// same key. This is the property that makes cross-language lookups
/// land at the same registry object regardless of which capdag
/// implementation issued the request. Inputs MUST quote any
/// multi-tag media URN value — the previous unquoted spelling
/// `out=media:task;id` was actually a different URN (the bare
/// `media:task` plus a separate `id` op tag), and treating those
/// two URNs as equivalent here masked a real spec violation.
- (void)test140_sameCapDifferentSpellingsSameURL {
    NSString *urlA = buildRegistryURL(@"cap:in=\"media:listing-id\";use-grinder;out=\"media:task;id\"");
    NSString *urlB = buildRegistryURL(@"cap:out=\"media:task;id\";in=\"media:listing-id\";use-grinder");
    XCTAssertEqualObjects(urlA, urlB, @"Equivalent URNs must hash to the same registry key");
}

/// TEST141: URL has the right shape — protocol, host, /caps/ prefix,
/// 64 hex chars, no extension.
- (void)test141_perCapURLShape {
    NSString *registryURL = buildRegistryURL(@"cap:in=\"media:listing-id\";use-grinder;out=\"media:task;id\"");

    NSURL *url = [NSURL URLWithString:registryURL];
    XCTAssertNotNil(url, @"Generated URL must be valid");
    XCTAssertEqualObjects(url.host, @"fabric.capdag.com", @"Default host is fabric.capdag.com");
    XCTAssertTrue([url.path hasPrefix:@"/caps/"]);
    NSString *hashPart = [url.path stringByReplacingOccurrencesOfString:@"/caps/" withString:@""];
    XCTAssertEqual(hashPart.length, 64u, @"SHA-256 hex digest is 64 characters");
}

/// TEST142: Different tag orders normalise to the same URL — the
/// canonicaliser strips the variation before hashing.
- (void)test142_normalizeHandlesDifferentTagOrders {
    NSString *url1 = buildRegistryURL(@"cap:test;in=\"media:string\";out=\"media:object\"");
    NSString *url2 = buildRegistryURL(@"cap:in=\"media:string\";out=\"media:object\";test");
    XCTAssertEqualObjects(url1, url2, @"Different tag orders should produce the same URL");
}

// Note: These tests would make actual HTTP requests to capdag.com
// Uncomment to test with real registry
/*
- (void)testGetCapDefinitionReal {
    CSFabricRegistry *registry = [CSFabricRegistry registry];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Get cap definition"];
    
    [registry getCapDefinition:@"cap:in=media:void;extract;out=\"media:record;textable\";target=metadata" completion:^(CSRegistryCapDefinition *definition, NSError *error) {
        if (error) {
            NSLog(@"Skipping real registry test: %@", error);
        } else {
            XCTAssertNotNil(definition);
            XCTAssertEqualObjects(definition.urn, @"cap:in=media:void;extract;out=\"media:record;textable\";target=metadata");
            XCTAssertNotNil(definition.version);
            XCTAssertNotNil(definition.command);
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testValidateCapCanonical {
    CSRegistryValidator *validator = [CSRegistryValidator validator];
    
    NSError *error;
    CSCapUrn *urn = [CSCapUrn fromString:@"cap:in=media:void;extract;out=\"media:record;textable\";target=metadata" error:&error];
    XCTAssertNotNil(urn);
    
    CSCap *cap = [CSCap capWithUrn:urn
                             title:@"Extract Metadata"
                           command:@"extract-metadata"
                       description:nil
                     documentation:nil
                          metadata:@{}
                        mediaSpecs:@[]
                              args:@[]
                            output:nil
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