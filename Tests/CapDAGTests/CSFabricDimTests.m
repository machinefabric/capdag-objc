//
//  CSFabricDimTests.m
//  CapDAGTests
//
//  Fabric dim tests — mirror the Rust reference (capdag-rs `dim_tests`)
//  test-for-test. Shared test numbers (1966-1968, 1971-1972) test the same
//  behaviour across every capdag implementation; 1969 (cap dims) lives in
//  CSCapTests.m and 1970 (media def dims) in CSMediaDefTests.m.
//
//  The reference proves "decided before any fetch" with an offline registry.
//  This registry has no offline switch, so these tests point it at a registry
//  chartered where nothing can be reached (127.0.0.1:9, the discard port): a
//  fetch would fail with CSFabricRegistryErrorDimUnavailable, never the error
//  asserted.
//

#import <XCTest/XCTest.h>
#import <CommonCrypto/CommonDigest.h>
#import "CSFabricRegistry.h"
#import "CSCharter.h"
#import "CSDim.h"
#import "CSCap.h"
#import "CSCapUrn.h"

/// Registry internals these tests hold to their contract (not in the public
/// header): the designated initializer, manifest ingestion, the dim object
/// address, the dim body check and the definition admission rule.
@interface CSFabricRegistry (CSFabricDimTestsInternal)
- (instancetype)initWithCharter:(CSCharter *)charter
                         config:(CSFabricRegistryConfig *)config
                manifestVersion:(uint32_t)manifestVersion
           bootstrapFromNetwork:(BOOL)bootstrapFromNetwork;
- (BOOL)ingestManifestDictionary:(NSDictionary *)manifest error:(NSError *_Nullable *_Nullable)error;
- (NSString *)dimURLForName:(NSString *)name defver:(uint32_t)defver;
- (NSString *)dimCacheFileForName:(NSString *)name defver:(uint32_t)defver;
- (nullable CSStoredDim *)checkedDimFromData:(NSData *)data
                                        name:(NSString *)name
                                      defver:(uint32_t)defver
                                       error:(NSError *_Nullable *_Nullable)error;
- (void)ensureDimsCached:(NSArray<CSDimRef *> *)refs
                   owner:(NSString *)owner
              completion:(void (^)(NSError *_Nullable error))completion;
@end

@interface CSFabricDimTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSString *> *cacheRoots;
@end

static CSStoredDim *dim(NSString *name, uint32_t version, NSArray<NSString *> *values) {
    NSMutableArray<CSStoredDimValue *> *vs = [NSMutableArray array];
    for (NSString *v in values) {
        [vs addObject:[CSStoredDimValue valueWithName:v
                                                title:[v uppercaseString]
                                                 tags:@[[CSDimTag tagWithKey:name value:v]]
                                        documentation:[NSString stringWithFormat:@"The %@ value.", v]
                                            mediaType:nil
                                           extensions:@[]]];
    }
    return [CSStoredDim dimWithName:name
                            version:version
                              title:[NSString stringWithFormat:@"Title of %@", name]
                      documentation:[NSString stringWithFormat:@"## %@\nWhat %@ is.", name, name]
                             values:vs];
}

static NSString *sha256Hex(NSString *s) {
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

static NSData *jsonData(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

@implementation CSFabricDimTests

- (void)setUp {
    [super setUp];
    self.cacheRoots = [NSMutableArray array];
}

- (void)tearDown {
    for (NSString *root in self.cacheRoots) {
        [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
    }
    [super tearDown];
}

/// The charter of a fabric registry no fetch can reach, with a slug — and so a
/// cache folder — of its own (removed in tearDown).
- (CSCharter *)unreachableCharter:(NSString *)tag {
    NSString *unique = [[NSUUID UUID].UUIDString lowercaseString];
    NSString *anchor = [NSString stringWithFormat:@"https://127.0.0.1:9/capdag-dim-tests/%@-%@", tag, unique];
    NSString *slug = [NSString stringWithFormat:@"dim-tests-%@-%@", tag, unique];
    [self.cacheRoots addObject:[[CSFabricRegistry capdagCacheRoot] stringByAppendingPathComponent:slug]];
    return [CSFabricRegistry publisherLayoutCharterForAnchor:anchor slug:slug];
}

/// A registry over `charter`, pinned at `version`.
- (CSFabricRegistry *)registryOver:(CSCharter *)charter version:(uint32_t)version bootstrap:(BOOL)bootstrap {
    return [[CSFabricRegistry alloc] initWithCharter:charter
                                              config:[CSFabricRegistryConfig configWithAnchor:charter.anchor]
                                     manifestVersion:version
                                bootstrapFromNetwork:bootstrap];
}

/// An empty registry pinned at `version`, chartered where no fetch can reach.
- (CSFabricRegistry *)unreachableRegistry:(NSString *)tag version:(uint32_t)version {
    return [self registryOver:[self unreachableCharter:tag] version:version bootstrap:NO];
}

// TEST1966: the manifest carries a `dims` map (name -> defver), and a manifest
// without one is refused: every manifest this library reads names the dims of
// its snapshot.
- (void)test1966_ManifestCarriesADimsMapAndRequiresIt {
    CSFabricRegistry *reg = [self unreachableRegistry:@"1966" version:11];
    NSDictionary *withDims = @{@"version": @11, @"previous": @10, @"caps": @{}, @"media": @{},
                               @"aliases": @{}, @"dims": @{@"language": @1, @"file-type": @2}};
    NSError *error = nil;
    XCTAssertTrue([reg ingestManifestDictionary:withDims error:&error], @"%@", error);
    XCTAssertEqualObjects(reg.manifestDictionary[@"dims"][@"language"], @1);
    XCTAssertEqualObjects(reg.manifestDictionary[@"dims"][@"file-type"], @2);
    NSDictionary *back = [NSJSONSerialization JSONObjectWithData:jsonData(reg.manifestDictionary) options:0 error:nil];
    XCTAssertEqualObjects(back[@"dims"][@"file-type"], @2);

    NSDictionary *without = @{@"version": @11, @"previous": @10, @"caps": @{}, @"media": @{}, @"aliases": @{}};
    error = nil;
    XCTAssertFalse([reg ingestManifestDictionary:without error:&error], @"a manifest without dims is refused");
    XCTAssertEqual(error.code, CSFabricRegistryErrorManifestInvalid);
    XCTAssertTrue([error.localizedDescription containsString:@"dims"], @"%@", error);
    XCTAssertEqualObjects(reg.manifestDictionary[@"dims"][@"language"], @1,
                          @"a refused manifest leaves the pinned one in place");
}

// TEST1967: getDim returns a dim the registry holds; a name the pinned manifest
// does not list is NotFound naming the manifest version, decided before any
// fetch (the registry is unreachable, and the error is not the fetch one); a
// string that is no dim name is refused as such.
- (void)test1967_GetDimResolvesThroughTheManifest {
    CSFabricRegistry *reg = [self unreachableRegistry:@"1967" version:1];
    [reg insertCachedDimForTest:dim(@"language", 1, @[@"en", @"es"])];

    XCTestExpectation *held = [self expectationWithDescription:@"held dim"];
    [reg getDim:@"language" completion:^(CSStoredDim *got, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects([got valueNamed:@"es"].title, @"ES");
        [held fulfill];
    }];
    NSError *defverError = nil;
    XCTAssertEqual([reg dimDefverFor:@"language" error:&defverError], 1u);
    XCTAssertNil(defverError);

    XCTestExpectation *unlisted = [self expectationWithDescription:@"unlisted dim"];
    [reg getDim:@"tone" completion:^(CSStoredDim *got, NSError *error) {
        XCTAssertNil(got);
        XCTAssertEqual(error.code, CSFabricRegistryErrorDimNotInManifest, @"%@", error);
        XCTAssertTrue([error.localizedDescription containsString:@"dim 'tone' is not part of manifest v1"], @"%@", error);
        [unlisted fulfill];
    }];

    XCTestExpectation *invalid = [self expectationWithDescription:@"not a dim name"];
    [reg getDim:@"Tone" completion:^(CSStoredDim *got, NSError *error) {
        XCTAssertNil(got);
        XCTAssertEqual(error.code, CSFabricRegistryErrorInvalidDimName, @"%@", error);
        [invalid fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

// TEST1968: a dim is addressed at dims/<sha256-of-name>/<defver>.json, on the
// registry and in the cache; a body served for it must be that dim at that
// version, with no field this library does not know, and must hold (values
// present, names unique).
- (void)test1968_ADimObjectIsTheDimAndVersionAskedFor {
    CSCharter *charter = [self unreachableCharter:@"1968"];
    CSFabricRegistry *reg = [self registryOver:charter version:1 bootstrap:NO];
    NSString *hash = sha256Hex(@"language");
    XCTAssertEqualObjects([reg dimURLForName:@"language" defver:3],
                          ([NSString stringWithFormat:@"%@/dims/%@/3.json", charter.anchor, hash]));
    NSString *root = [[CSFabricRegistry capdagCacheRoot] stringByAppendingPathComponent:charter.slug];
    XCTAssertEqualObjects([reg dimCacheFileForName:@"language" defver:3],
                          ([[[root stringByAppendingPathComponent:@"dims"] stringByAppendingPathComponent:hash]
                            stringByAppendingPathComponent:@"3.json"]));

    NSData *good = jsonData([dim(@"language", 3, @[@"en"]) toDictionary]);
    NSError *error = nil;
    XCTAssertEqualObjects([reg checkedDimFromData:good name:@"language" defver:3 error:&error].name, @"language", @"%@", error);

    error = nil;
    XCTAssertNil([reg checkedDimFromData:good name:@"file-type" defver:3 error:&error]);
    XCTAssertEqual(error.code, CSFabricRegistryErrorDimParse);
    XCTAssertTrue([error.localizedDescription containsString:@"does not match requested name"], @"%@", error);

    error = nil;
    XCTAssertNil([reg checkedDimFromData:good name:@"language" defver:2 error:&error]);
    XCTAssertEqual(error.code, CSFabricRegistryErrorDimParse);
    XCTAssertTrue([error.localizedDescription containsString:@"manifest pins defver 2"], @"%@", error);

    NSMutableDictionary *extra = [[dim(@"language", 3, @[@"en"]) toDictionary] mutableCopy];
    extra[@"predicates"] = @[];
    error = nil;
    XCTAssertNil([reg checkedDimFromData:jsonData(extra) name:@"language" defver:3 error:&error]);
    XCTAssertEqual(error.code, CSFabricRegistryErrorDimParse);
    XCTAssertTrue([error.localizedDescription containsString:@"predicates"], @"%@", error);

    error = nil;
    XCTAssertNil([reg checkedDimFromData:jsonData([dim(@"language", 3, @[@"en", @"en"]) toDictionary])
                                    name:@"language" defver:3 error:&error]);
    XCTAssertEqual(error.code, CSFabricRegistryErrorDimInvalid);
    XCTAssertTrue([error.localizedDescription containsString:@"declares value 'en' more than once"], @"%@", error);

    error = nil;
    XCTAssertNil([reg checkedDimFromData:jsonData([dim(@"language", 3, @[]) toDictionary])
                                    name:@"language" defver:3 error:&error]);
    XCTAssertEqual(error.code, CSFabricRegistryErrorDimInvalid);
}

/// Write `object` as JSON at `path`, creating its directory.
static void writeJSON(NSString *path, id object) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [jsonData(object) writeToFile:path atomically:YES];
}

static NSString *normalizedCapUrn(NSString *urn) {
    return [[CSCapUrn fromString:urn error:nil] toString];
}

static NSArray *dimsJSON(NSArray<NSArray<NSString *> *> *pairs) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray<NSString *> *pair in pairs) {
        [out addObject:@{@"dim": pair[0], @"value": pair[1]}];
    }
    return out;
}

// TEST1971: what is loaded from the disk cache is kept only as the pinned
// manifest names it — a dim at another version is dropped — and a definition
// is kept only when every dim it names survives with the value it names. At v0
// there are no dims.
- (void)test1971_TheDiskCacheKeepsDefinitionsOnlyWithTheirPinnedDims {
    CSCharter *charter = [self unreachableCharter:@"1971"];
    NSString *root = [[CSFabricRegistry capdagCacheRoot] stringByAppendingPathComponent:charter.slug];
    NSArray<NSString *> *capUrns = @[@"cap:a;in=media:;out=media:", @"cap:b;in=media:;out=media:", @"cap:c;in=media:;out=media:"];
    NSArray *capDims = @[dimsJSON(@[@[@"medium", @"text"]]), dimsJSON(@[@[@"language", @"en"]]), @[]];
    NSMutableDictionary *manifestCaps = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < capUrns.count; i++) {
        NSString *normalized = normalizedCapUrn(capUrns[i]);
        XCTAssertNotNil(normalized);
        manifestCaps[normalized] = @1;
        NSMutableDictionary *def = [@{@"urn": capUrns[i], @"version": @1, @"title": @"t", @"aliases": @[@"t"]} mutableCopy];
        if ([capDims[i] count] > 0) def[@"dims"] = capDims[i];
        writeJSON([NSString stringWithFormat:@"%@/caps/%@/1.json", root, sha256Hex(normalized)],
                  @{@"definition": def, @"cached_at": @([[NSDate date] timeIntervalSince1970]), @"ttl_hours": @24});
    }
    NSDictionary *specs = @{@"media:x": dimsJSON(@[@[@"medium", @"text"]]), @"media:y": dimsJSON(@[@[@"medium", @"audio"]])};
    for (NSString *urn in specs) {
        writeJSON([NSString stringWithFormat:@"%@/media/%@/1.json", root, sha256Hex(urn)],
                  @{@"spec": @{@"urn": urn, @"version": @1, @"media_type": @"text/plain", @"title": @"t", @"dims": specs[urn]},
                    @"cached_at": @([[NSDate date] timeIntervalSince1970]), @"ttl_hours": @24});
    }
    // The manifest pins language at 2; only version 1 is cached.
    writeJSON([NSString stringWithFormat:@"%@/dims/%@/1.json", root, sha256Hex(@"language")],
              @{@"dim": [dim(@"language", 1, @[@"en"]) toDictionary], @"cached_at": @0, @"ttl_hours": @24});
    writeJSON([NSString stringWithFormat:@"%@/dims/%@/1.json", root, sha256Hex(@"medium")],
              @{@"dim": [dim(@"medium", 1, @[@"text"]) toDictionary], @"cached_at": @0, @"ttl_hours": @24});
    writeJSON([NSString stringWithFormat:@"%@/manifests/11.json", root],
              @{@"version": @11, @"previous": @10, @"caps": manifestCaps, @"media": @{@"media:x": @1, @"media:y": @1},
                @"aliases": @{}, @"dims": @{@"language": @2, @"medium": @1}});

    // Bootstraps from the cached manifest, then hydrates the disk cache.
    CSFabricRegistry *reg = [self registryOver:charter version:11 bootstrap:YES];
    XCTAssertNil([reg getCachedDim:@"language"], @"a dim at another version is dropped");
    XCTAssertEqualObjects([reg getCachedDim:@"medium"].name, @"medium");
    XCTAssertTrue([reg capExists:capUrns[0]], @"a cap whose dim survived is kept");
    XCTAssertFalse([reg capExists:capUrns[1]], @"the cap naming the dropped dim is dropped with it");
    XCTAssertTrue([reg capExists:capUrns[2]], @"a cap naming no dim is kept");
    XCTAssertNotNil([reg getCachedMediaDef:@"media:x"]);
    XCTAssertNil([reg getCachedMediaDef:@"media:y"], @"a value the dim lacks drops the definition");

    CSFabricRegistry *v0 = [self registryOver:charter version:0 bootstrap:NO];
    XCTAssertNil([v0 getCachedDim:@"medium"], @"v0 has no dims");
    XCTAssertFalse([v0 capExists:capUrns[0]], @"so a cap naming one is not held at v0");
}

// TEST1972: a definition is cached only once every dim it names is held, with
// the value it names. A dim the manifest does not list is refused naming the
// definition, the dim and the manifest version, before any fetch; a value the
// dim does not declare is refused naming all three; one dim named twice is
// refused.
- (void)test1972_ADefinitionNeedsEveryDimItNames {
    CSFabricRegistry *reg = [self unreachableRegistry:@"1972" version:1];
    [reg insertCachedDimForTest:dim(@"language", 1, @[@"en"])];
    NSError *(^ensure)(NSArray<CSDimRef *> *) = ^NSError *(NSArray<CSDimRef *> *refs) {
        __block NSError *result = nil;
        XCTestExpectation *done = [self expectationWithDescription:@"ensure"];
        [reg ensureDimsCached:refs owner:@"cap 'cap:probe'" completion:^(NSError *error) {
            result = error;
            [done fulfill];
        }];
        [self waitForExpectations:@[done] timeout:5.0];
        return result;
    };

    XCTAssertNil(ensure(@[[CSDimRef refWithDim:@"language" value:@"en"]]), @"a held dim and value pass");

    NSError *error = ensure(@[[CSDimRef refWithDim:@"language" value:@"fr"]]);
    XCTAssertEqual(error.code, CSFabricRegistryErrorDimValueUndeclared, @"%@", error);
    XCTAssertEqualObjects(error.localizedDescription,
                          @"cap 'cap:probe' names value 'fr' of dim 'language', which the dim does not declare");

    error = ensure(@[[CSDimRef refWithDim:@"tone" value:@"formal"]]);
    XCTAssertEqual(error.code, CSFabricRegistryErrorDimNotInManifest, @"%@", error);
    XCTAssertEqualObjects(error.localizedDescription, @"cap 'cap:probe' names dim 'tone', which is not in manifest v1");

    error = ensure(@[[CSDimRef refWithDim:@"language" value:@"en"], [CSDimRef refWithDim:@"language" value:@"en"]]);
    XCTAssertEqual(error.code, CSFabricRegistryErrorDimRefsInvalid, @"%@", error);
    XCTAssertTrue([error.localizedDescription containsString:@"named more than once"], @"%@", error);
}

@end
