//
//  CSFileMediaTests.m
//  CapDAGTests
//
//  The file media types a file's extension names, from the whole manifest,
//  and what a file is. Mirrors the Rust reference's tests/file_media.rs
//  (TEST7177-7184), the registry's file media tests (TEST607-609) and its
//  kept file types tests (TEST7186-7187).
//
//  A stub registry serves, at its `definition` location, every media
//  definition of fabric manifest 13 that carries the `ext=` file-type tag,
//  and the JSON records that list an extension without one, as published
//  (../Fixtures/fabric13_file_media.json). The registry's manifest names them
//  all; what its cache holds is up to each test.
//
//  Tests use // TEST###: comments matching the Rust implementation for
//  cross-tracking.
//

#import <XCTest/XCTest.h>
#import <CommonCrypto/CommonDigest.h>
#import "CSFabricRegistry.h"
#import "CSCharter.h"
#import "CSFileMediaDetection.h"
#import "CSInputResolver.h"
#import "CSMediaUrn.h"

/// Registry internals these tests hold to their contract (not in the public
/// header): its session, the designated initializer, the cache folder of a
/// manifest version, and the file types of a manifest.
@interface CSFabricRegistry (CSFileMediaTestsInternal)
@property (nonatomic, strong) NSURLSession *session;
- (instancetype)initWithCharter:(CSCharter *)charter
                         config:(CSFabricRegistryConfig *)config
                manifestVersion:(uint32_t)manifestVersion
           bootstrapFromNetwork:(BOOL)bootstrapFromNetwork;
+ (NSString *)cacheFolderOfRegistryFolder:(NSString *)registryFolder manifestVersion:(uint32_t)manifestVersion;
+ (nullable NSArray<NSArray *> *)fileTypesInCacheFolder:(NSString *)folder
                                           manifestFile:(nullable NSString *)manifestFile
                                        manifestVersion:(uint32_t)manifestVersion
                                                  media:(NSDictionary<NSString *, NSNumber *> *)media
                                                  error:(NSError *_Nullable *_Nullable)error;
@end

static const uint32_t CSFileMediaManifestVersion = 13;

/// What the stub registry serves: `media/<sha256 of URN>/<defver>.json` →
/// the definition's body.
static NSDictionary<NSString *, NSData *> *CSFileMediaBodies;
/// How many definitions the stub served.
static NSUInteger CSFileMediaServed;
/// Whether the stub is a machine with no network: every request fails as
/// not connected.
static BOOL CSFileMediaOffline;

@interface CSFileMediaRegistryProtocol : NSURLProtocol
@end

@implementation CSFileMediaRegistryProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSData *body = nil;
    BOOL offline = NO;
    NSArray<NSString *> *parts = self.request.URL.pathComponents;
    NSString *key = parts.count >= 3
        ? [[parts subarrayWithRange:NSMakeRange(parts.count - 3, 3)] componentsJoinedByString:@"/"]
        : @"";
    @synchronized ([CSFileMediaRegistryProtocol class]) {
        offline = CSFileMediaOffline;
        if (!offline) {
            body = CSFileMediaBodies[key];
            if (body) CSFileMediaServed += 1;
        }
    }
    if (offline) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                           code:NSURLErrorNotConnectedToInternet
                                                                       userInfo:nil]];
        return;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:body ? 200 : 404
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Content-Type": @"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (body) [self.client URLProtocol:self didLoadData:body];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static NSString *CSFileMediaSha256(NSString *s) {
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [out appendFormat:@"%02x", digest[i]];
    return out;
}

/// The fixture's definitions, by URN.
static NSDictionary<NSString *, NSDictionary *> *CSFileMediaDefinitions(void) {
    NSString *path = [NSString stringWithUTF8String:__FILE__];
    path = [[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"Fixtures/fabric13_file_media.json"];
    NSData *raw = [NSData dataWithContentsOfFile:path];
    NSDictionary *fixture = raw ? [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil] : nil;
    return fixture[@"definitions"];
}

static BOOL CSFileMediaIsFileType(NSString *urn) {
    return [[CSMediaUrn fromString:urn error:nil] getTag:@"ext"] != nil;
}

/// The adapter answers of datacartridge and txtcartridge for the files of
/// TEST7182; any other question is recorded as unexpected.
@interface CSBundledAdaptersInvoker : NSObject <CSCartridgeAdapterInvoker>
@property (nonatomic, strong) NSMutableArray<NSString *> *unexpected;
@end

@implementation CSBundledAdaptersInvoker
- (instancetype)init {
    self = [super init];
    if (self) _unexpected = [NSMutableArray array];
    return self;
}
- (void)invokeAdapterSelectionForCartridge:(NSString *)cartridgeId
                                  filePath:(NSString *)filePath
                                completion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    NSString *name = [filePath lastPathComponent];
    NSDictionary<NSString *, NSArray<NSString *> *> *answers = @{
        @"datacartridge record.json": @[@"media:enc=utf8;ext=json;fmt=json;record", @"media:enc=utf8;ext=json;fmt=json"],
        @"datacartridge rows.json": @[@"media:enc=utf8;ext=json;fmt=json;list;record",
                                      @"media:enc=utf8;ext=json;fmt=json;list",
                                      @"media:enc=utf8;ext=json;fmt=json"],
        @"datacartridge people.csv": @[@"media:enc=utf8;ext=csv;fmt=csv;list;record"],
        @"txtcartridge notes.txt": @[@"media:enc=utf8;ext=txt;plain-text"],
    };
    NSArray<NSString *> *claims = answers[[NSString stringWithFormat:@"%@ %@", cartridgeId, name]];
    if (!claims) {
        @synchronized (self.unexpected) {
            [self.unexpected addObject:[NSString stringWithFormat:@"%@ was asked about %@", cartridgeId, name]];
        }
    }
    completion(claims, nil);
}
@end

@interface CSFileMediaTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSString *> *scratchFolders;
@property (nonatomic, copy) NSString *filesDir;
@end

@implementation CSFileMediaTests

- (void)setUp {
    [super setUp];
    self.scratchFolders = [NSMutableArray array];
    @synchronized ([CSFileMediaRegistryProtocol class]) {
        CSFileMediaBodies = @{};
        CSFileMediaServed = 0;
        CSFileMediaOffline = NO;
    }
    self.filesDir = [self scratch];
}

- (void)tearDown {
    for (NSString *folder in self.scratchFolders) {
        [[NSFileManager defaultManager] removeItemAtPath:folder error:nil];
    }
    [super tearDown];
}

#pragma mark - Helpers

/// A new, empty folder of this test's own, removed in tearDown.
- (NSString *)scratch {
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"capdag-file-media-tests-%@", [NSUUID UUID].UUIDString.lowercaseString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    [self.scratchFolders addObject:folder];
    return folder;
}

/// Serve `definitions` from the stub registry.
- (void)serve:(NSDictionary<NSString *, NSDictionary *> *)definitions {
    NSMutableDictionary<NSString *, NSData *> *bodies = [NSMutableDictionary dictionary];
    for (NSString *urn in definitions) {
        NSDictionary *definition = definitions[urn];
        NSString *normalized = [[CSMediaUrn fromString:urn error:nil] toString];
        NSString *key = [NSString stringWithFormat:@"media/%@/%@.json", CSFileMediaSha256(normalized), definition[@"version"]];
        bodies[key] = [NSJSONSerialization dataWithJSONObject:definition options:0 error:nil];
    }
    @synchronized ([CSFileMediaRegistryProtocol class]) {
        CSFileMediaBodies = bodies;
    }
}

- (NSUInteger)served {
    @synchronized ([CSFileMediaRegistryProtocol class]) {
        return CSFileMediaServed;
    }
}

- (void)setOffline:(BOOL)offline {
    @synchronized ([CSFileMediaRegistryProtocol class]) {
        CSFileMediaOffline = offline;
    }
}

/// A registry pinned at manifest 13, with a cache folder of its own, whose
/// manifest names every fixture definition and which fetches from the stub;
/// the definitions in `cached` are in its cache already.
- (CSFabricRegistry *)registryCaching:(NSArray<NSString *> *)cached {
    NSString *unique = [NSUUID UUID].UUIDString.lowercaseString;
    NSString *anchor = [NSString stringWithFormat:@"https://127.0.0.1:9/capdag-file-media-tests/%@", unique];
    NSString *slug = [NSString stringWithFormat:@"file-media-tests-%@", unique];
    [self.scratchFolders addObject:[[CSFabricRegistry capdagCacheRoot] stringByAppendingPathComponent:slug]];
    CSCharter *charter = [CSFabricRegistry publisherLayoutCharterForAnchor:anchor slug:slug];
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initWithCharter:charter
                                                                    config:[CSFabricRegistryConfig configWithAnchor:anchor]
                                                           manifestVersion:CSFileMediaManifestVersion
                                                      bootstrapFromNetwork:NO];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.protocolClasses = @[[CSFileMediaRegistryProtocol class]];
    registry.session = [NSURLSession sessionWithConfiguration:config];
    NSDictionary<NSString *, NSDictionary *> *definitions = CSFileMediaDefinitions();
    for (NSString *urn in definitions) {
        if ([cached containsObject:urn]) {
            [registry addMediaDef:definitions[urn]];
        } else {
            [registry listMediaInManifestForTest:urn defver:[definitions[urn][@"version"] unsignedIntValue]];
        }
    }
    return registry;
}

/// A registry over the fixture whose cache holds what a machine that has run
/// a model download and an OCR cap holds.
- (CSFabricRegistry *)warmMachineRegistry {
    [self serve:CSFileMediaDefinitions()];
    return [self registryCaching:@[@"media:download-result;enc=utf8;fmt=json;record",
                                   @"media:digitized;enc=utf8;ext=txt;plain-text"]];
}

- (nullable NSArray<NSDictionary *> *)fileMediaOf:(CSFabricRegistry *)registry
                                        extension:(NSString *)extension
                                            error:(NSError **)error {
    XCTestExpectation *done = [self expectationWithDescription:[NSString stringWithFormat:@"file media of .%@", extension]];
    __block NSArray<NSDictionary *> *found = nil;
    __block NSError *failure = nil;
    [registry fileMediaForExtension:extension completion:^(NSArray<NSDictionary *> *definitions, NSError *e) {
        found = definitions;
        failure = e;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:60];
    if (error) *error = failure;
    return found;
}

/// The URNs of the file media types `extension` names.
- (NSArray<NSString *> *)urnsOf:(CSFabricRegistry *)registry extension:(NSString *)extension {
    NSError *error = nil;
    NSArray<NSDictionary *> *definitions = [self fileMediaOf:registry extension:extension error:&error];
    XCTAssertNotNil(definitions, @".%@: %@", extension, error.localizedDescription);
    NSMutableArray<NSString *> *urns = [NSMutableArray array];
    for (NSDictionary *definition in definitions) [urns addObject:definition[@"urn"]];
    return urns;
}

- (NSString *)write:(NSString *)name content:(NSString *)content {
    NSString *path = [self.filesDir stringByAppendingPathComponent:name];
    [content writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
    return path;
}

- (nullable CSFileMedia *)detect:(NSString *)path
                        registry:(CSFabricRegistry *)registry
                        adapters:(id<CSAdapterSource>)adapters
                         invoker:(id<CSCartridgeAdapterInvoker>)invoker
                           error:(NSError **)error {
    XCTestExpectation *done = [self expectationWithDescription:[NSString stringWithFormat:@"detect %@", path.lastPathComponent]];
    __block CSFileMedia *found = nil;
    __block NSError *failure = nil;
    CSDetectFileMedia(path, registry, adapters, invoker, ^(CSFileMedia *media, NSError *e) {
        found = media;
        failure = e;
        [done fulfill];
    });
    [self waitForExpectations:@[done] timeout:60];
    if (error) *error = failure;
    return found;
}

- (nullable CSFileMedia *)detectWithoutAdapters:(NSString *)path
                                       registry:(CSFabricRegistry *)registry
                                          error:(NSError **)error {
    return [self detect:path registry:registry adapters:[[CSNoAdapters alloc] init]
                invoker:[[CSNoInvoker alloc] init] error:error];
}

- (nullable NSArray<NSString *> *)extensionMedia:(NSString *)extension
                                        registry:(CSFabricRegistry *)registry
                                           error:(NSError **)error {
    XCTestExpectation *done = [self expectationWithDescription:[NSString stringWithFormat:@"media of .%@", extension]];
    __block NSArray<NSString *> *found = nil;
    __block NSError *failure = nil;
    CSExtensionMedia(extension, registry, ^(NSArray<NSString *> *media, NSError *e) {
        found = media;
        failure = e;
        [done fulfill];
    });
    [self waitForExpectations:@[done] timeout:60];
    if (error) *error = failure;
    return found;
}

#pragma mark - The file media types an extension names (Rust registry.rs: TEST607-TEST609)

// TEST607: fileMediaForExtension answers no file type for an extension no
// definition of the manifest declares
- (void)test607_fileMediaForAnUnknownExtensionIsNone {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    [registry addMediaDef:@{@"urn": @"media:document;ext=pdf", @"title": @"PDF Document",
                            @"media_type": @"application/pdf", @"extensions": @[@"pdf"]}];
    NSError *error = nil;
    NSArray<NSDictionary *> *definitions = [self fileMediaOf:registry extension:@"zzzzunknown" error:&error];
    XCTAssertNotNil(definitions, @"%@", error);
    XCTAssertEqual(definitions.count, 0u, @"no definition declares .zzzzunknown, got %@", definitions);
}

// TEST608: fileMediaForExtension answers the file media definitions that list
// the extension, whatever its case
- (void)test608_fileMediaForExtensionListsTheDeclaringDefinitions {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    [registry addMediaDef:@{@"urn": @"media:document;ext=pdf", @"title": @"PDF Document",
                            @"media_type": @"application/pdf", @"extensions": @[@"pdf"]}];
    NSArray<NSString *> *lower = [self urnsOf:registry extension:@"pdf"];
    XCTAssertEqualObjects(lower, @[@"media:document;ext=pdf"]);
    XCTAssertEqualObjects([self urnsOf:registry extension:@"PDF"], lower);
}

// TEST609: a definition that lists an extension but carries no `ext=`
// file-type tag is content, not a file type: it is never a file type of the
// extension, even when it is cached
- (void)test609_contentTypesThatListAnExtensionAreNoFileTypes {
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    [registry addMediaDef:@{@"urn": @"media:download-result;enc=utf8;fmt=json;record", @"title": @"Model Download Result",
                            @"media_type": @"application/json", @"extensions": @[@"json"]}];
    [registry addMediaDef:@{@"urn": @"media:enc=utf8;ext=json;fmt=json", @"title": @"JSON File",
                            @"media_type": @"application/json", @"extensions": @[@"json"]}];
    XCTAssertEqualObjects([self urnsOf:registry extension:@"json"], @[@"media:enc=utf8;ext=json;fmt=json"]);
}

#pragma mark - The manifest-wide file type index (Rust tests/file_media.rs: TEST7177-TEST7180)

// TEST7177: on a cold cache, a file's extension names every file media type
// the manifest declares for it, fetched from the registry: .csv and .yaml are
// known although nothing has cached them, and the content-only JSON records a
// machine has cached (a model download result) are no file types
- (void)test7177_extensionsNameTheManifestsFileTypesOnAColdCache {
    NSDictionary<NSString *, NSDictionary *> *definitions = CSFileMediaDefinitions();
    XCTAssertNotNil(definitions, @"the fixture is read");
    [self serve:definitions];
    CSFabricRegistry *registry = [self registryCaching:@[@"media:download-result;enc=utf8;fmt=json;record"]];

    XCTAssertEqualObjects([self urnsOf:registry extension:@"csv"], @[@"media:enc=utf8;ext=csv;fmt=csv;list;record"]);
    NSArray<NSString *> *yaml = @[
        @"media:enc=utf8;ext=yaml;fmt=yaml",
        @"media:enc=utf8;ext=yaml;fmt=yaml;list",
        @"media:enc=utf8;ext=yaml;fmt=yaml;list;record",
        @"media:enc=utf8;ext=yaml;fmt=yaml;record",
    ];
    XCTAssertEqualObjects([self urnsOf:registry extension:@"yaml"], yaml);
    XCTAssertEqualObjects([self urnsOf:registry extension:@"YML"], yaml);
    NSArray<NSString *> *json = @[
        @"media:enc=utf8;ext=json;fmt=json",
        @"media:enc=utf8;ext=json;fmt=json;list",
        @"media:enc=utf8;ext=json;fmt=json;list;record",
        @"media:enc=utf8;ext=json;fmt=json;record",
    ];
    XCTAssertEqualObjects([self urnsOf:registry extension:@"json"], json);
    NSArray<NSString *> *txt = @[
        @"media:digitized;enc=utf8;ext=txt;plain-text",
        @"media:enc=utf8;ext=requirements",
        @"media:enc=utf8;ext=txt;image-description;plain-text",
        @"media:enc=utf8;ext=txt;page;plain-text",
        @"media:enc=utf8;ext=txt;plain-text",
    ];
    XCTAssertEqualObjects([self urnsOf:registry extension:@"txt"], txt);

    NSUInteger fileTypes = 0;
    for (NSString *urn in definitions) {
        if (CSFileMediaIsFileType(urn)) fileTypes += 1;
    }
    XCTAssertEqual(fileTypes, 156u, @"manifest 13 has 156 file media types");
    XCTAssertEqual([self served], fileTypes, @"every file media type is fetched once, and nothing else");
}

// TEST7178: the file media types load only when a file's type is first asked,
// once: making the registry and reading other definitions fetches none of
// them, and a second question fetches nothing more
- (void)test7178_fileMediaTypesLoadLazilyAndOnce {
    [self serve:CSFileMediaDefinitions()];
    CSFabricRegistry *registry = [self registryCaching:@[]];
    XCTAssertEqual([self served], 0u, @"making the registry fetches nothing");

    XCTestExpectation *fetched = [self expectationWithDescription:@"a definition that is no file type"];
    [registry getMediaDef:@"media:enc=utf8;fmt=json;model-list;record" completion:^(NSDictionary *spec, NSError *error) {
        XCTAssertNotNil(spec, @"%@", error);
        [fetched fulfill];
    }];
    [self waitForExpectations:@[fetched] timeout:60];
    XCTAssertEqual([self served], 1u, @"only the definition asked for is fetched");

    [self urnsOf:registry extension:@"pdf"];
    NSUInteger afterFirst = [self served];
    XCTAssertEqual(afterFirst, 1u + 156u);
    [self urnsOf:registry extension:@"csv"];
    [self urnsOf:registry extension:@"md"];
    XCTAssertEqual([self served], afterFirst, @"the index is loaded once");
}

// TEST7179: file media types already cached are not fetched again
- (void)test7179_cachedFileMediaTypesAreNotFetched {
    NSDictionary<NSString *, NSDictionary *> *definitions = CSFileMediaDefinitions();
    [self serve:definitions];
    CSFabricRegistry *registry = [self registryCaching:definitions.allKeys];
    XCTAssertEqualObjects([self urnsOf:registry extension:@"csv"], @[@"media:enc=utf8;ext=csv;fmt=csv;list;record"]);
    XCTAssertEqual([self served], 0u);
}

// TEST7180: with no network and a cold cache, a file's type cannot be told:
// the question fails, naming every file media type it could not load and why,
// and never answers from the part of the fabric that is cached. (The
// reference blocks its network with its offline switch; this library has
// none, so the stub answers every request as a machine with no network does.)
- (void)test7180_offlineOnAColdCacheFailsNamingWhatItCouldNotLoad {
    [self serve:CSFileMediaDefinitions()];
    CSFabricRegistry *registry = [self registryCaching:@[@"media:enc=utf8;ext=txt;plain-text", @"media:document;ext=pdf"]];
    [self setOffline:YES];

    NSError *error = nil;
    XCTAssertNil([self fileMediaOf:registry extension:@"txt" error:&error]);
    XCTAssertEqualObjects(error.domain, CSFabricRegistryErrorDomain);
    XCTAssertEqual(error.code, CSFabricRegistryErrorFileTypes, @"%@", error);
    NSString *message = error.localizedDescription;
    XCTAssertTrue([message hasPrefix:@"154 of the 156 file media types of manifest v13 could not be loaded"], @"%@", message);
    XCTAssertTrue([message containsString:@"media:enc=utf8;ext=csv;fmt=csv;list;record: the fetch of media def "
                                          @"'media:enc=utf8;ext=csv;fmt=csv;list;record'"], @"%@", message);
    XCTAssertFalse([message containsString:@"media:enc=utf8;ext=txt;plain-text:"], @"a cached type is not reported: %@", message);
    XCTAssertEqual([self served], 0u);

    [self setOffline:NO];
    XCTAssertEqualObjects([self urnsOf:registry extension:@"csv"], @[@"media:enc=utf8;ext=csv;fmt=csv;list;record"]);
}

#pragma mark - What a file is (Rust tests/file_media.rs: TEST7181-TEST7184)

// TEST7181: with no cartridge to ask (the capdag CLI, a host before its
// cartridges attach), each common extension is the file type the fabric
// declares for it: a .txt is plain text, not digitized text; a .json is JSON,
// not a model download result; .csv, .tsv, .yaml and .yml are known; a
// refinement nothing proves (a JSON record, digitized text, a filing document)
// is never claimed
- (void)test7181_commonExtensionsAreTheirFileTypesWithoutAdapters {
    CSFabricRegistry *registry = [self warmMachineRegistry];
    NSString *png = [NSString stringWithFormat:@"%CPNG", (unichar)0x89];
    NSString *jpeg = [NSString stringWithFormat:@"%C%C", (unichar)0xFF, (unichar)0xD8];
    NSArray<NSArray<NSString *> *> *table = @[
        @[@"notes.txt", @"A line of text.\n", @"media:enc=utf8;ext=txt;plain-text"],
        @[@"people.csv", @"name,age\nann,30\n", @"media:enc=utf8;ext=csv;fmt=csv;list;record"],
        @[@"rows.tsv", @"name\tage\nann\t30\n", @"media:enc=utf8;ext=tsv;fmt=tsv;list;record"],
        @[@"config.yaml", @"name: ann\nage: 30\n", @"media:enc=utf8;ext=yaml;fmt=yaml"],
        @[@"config.yml", @"name: ann\n", @"media:enc=utf8;ext=yaml;fmt=yaml"],
        @[@"a.json", @"{\"name\": \"ann\"}", @"media:enc=utf8;ext=json;fmt=json"],
        @[@"events.ndjson", @"{\"a\":1}\n{\"a\":2}\n", @"media:enc=utf8;ext=ndjson;fmt=ndjson"],
        @[@"events.jsonl", @"{\"a\":1}\n", @"media:enc=utf8;ext=ndjson;fmt=ndjson"],
        @[@"data.xml", @"<a><b/></a>", @"media:enc=utf8;ext=xml;fmt=xml"],
        @[@"config.toml", @"a = 1\n", @"media:enc=utf8;ext=toml"],
        @[@"README.md", @"# Title\n", @"media:enc=utf8;ext=md;plain-text"],
        @[@"run.log", @"started\n", @"media:enc=utf8;ext=log;plain-text"],
        @[@"page.html", @"<html></html>", @"media:enc=utf8;ext=html"],
        @[@"notebook.ipynb", @"{\"cells\": []}", @"media:enc=utf8;ext=jupyter;record"],
        @[@"report.pdf", @"%PDF-1.4\n", @"media:document;ext=pdf"],
        @[@"letter.docx", @"PK", @"media:document;ext=docx"],
        @[@"sheet.xlsx", @"PK", @"media:document;ext=xlsx"],
        @[@"photo.png", png, @"media:ext=png;image"],
        @[@"photo.jpg", jpeg, @"media:ext=jpeg;image"],
        @[@"song.mp3", @"ID3", @"media:audio;ext=mp3"],
        @[@"clip.mp4", @"ftyp", @"media:ext=mp4;video"],
        @[@"bundle.zip", @"PK", @"media:archive;ext=zip"],
    ];
    NSMutableArray<NSString *> *wrong = [NSMutableArray array];
    for (NSArray<NSString *> *row in table) {
        NSString *path = [self write:row[0] content:row[1]];
        NSError *error = nil;
        CSFileMedia *found = [self detectWithoutAdapters:path registry:registry error:&error];
        NSString *got = found ? [found primary] : [NSString stringWithFormat:@"error: %@", error.localizedDescription];
        if (![got isEqualToString:row[2]]) {
            [wrong addObject:[NSString stringWithFormat:@"%@: %@, expected %@", row[0], got, row[2]]];
        }
    }
    XCTAssertEqual(wrong.count, 0u, @"wrongly identified:\n  %@", [wrong componentsJoinedByString:@"\n  "]);

    NSError *error = nil;
    XCTAssertNil([self detectWithoutAdapters:[self write:@"thing.zzzz" content:@"x"] registry:registry error:&error]);
    XCTAssertEqualObjects(error.domain, CSInputResolverErrorDomain);
    XCTAssertEqual(error.code, CSInputResolverErrorUnknownExtension, @"%@", error);
    XCTAssertEqualObjects(error.userInfo[CSInputResolverExtensionKey], @"zzzz");

    error = nil;
    XCTAssertNil([self detectWithoutAdapters:[self write:@"Makefile" content:@"all:\n"] registry:registry error:&error]);
    XCTAssertEqual(error.code, CSInputResolverErrorNoExtension, @"%@", error);
}

// TEST7182: with the bundled cartridges' adapters (a desktop client), what a
// cartridge claims proves a refinement: a JSON object is a JSON record, an
// array of objects a list of records, and a .txt the cartridge reads as plain
// text is plain text, never digitized text
- (void)test7182_cartridgeClaimsProveRefinements {
    CSFabricRegistry *fabric = [self warmMachineRegistry];
    CSMediaAdapterRegistry *adapters = [[CSMediaAdapterRegistry alloc] initWithFabricRegistry:fabric];
    NSArray<NSString *> *data = @[
        @"media:enc=utf8;fmt=json",
        @"media:enc=utf8;fmt=ndjson",
        @"media:enc=utf8;fmt=csv",
        @"media:ext=tsv",
        @"media:ext=psv",
        @"media:enc=utf8;fmt=yaml",
        @"media:ext=xml",
        @"media:ext=toml",
    ];
    NSError *error = nil;
    XCTAssertTrue([adapters registerCapGroup:@"data-formats" adapterUrns:data cartridgeId:@"datacartridge" error:&error], @"%@", error);
    NSArray<NSString *> *text = @[@"media:plain-text", @"media:ext=html"];
    XCTAssertTrue([adapters registerCapGroup:@"text-formats" adapterUrns:text cartridgeId:@"txtcartridge" error:&error], @"%@", error);
    CSBundledAdaptersInvoker *invoker = [[CSBundledAdaptersInvoker alloc] init];

    CSFileMedia *found = [self detect:[self write:@"record.json" content:@"{\"name\": \"ann\"}"]
                             registry:fabric adapters:adapters invoker:invoker error:&error];
    XCTAssertEqualObjects(found.media, @[@"media:enc=utf8;ext=json;fmt=json;record"], @"%@", error);

    found = [self detect:[self write:@"rows.json" content:@"[{\"name\": \"ann\"}]"]
                registry:fabric adapters:adapters invoker:invoker error:&error];
    XCTAssertEqualObjects(found.media, @[@"media:enc=utf8;ext=json;fmt=json;list;record"], @"%@", error);

    found = [self detect:[self write:@"people.csv" content:@"name\nann\n"]
                registry:fabric adapters:adapters invoker:invoker error:&error];
    XCTAssertEqualObjects(found.media, @[@"media:enc=utf8;ext=csv;fmt=csv;list;record"], @"%@", error);

    // pip's requirements files claim .txt too, and no cartridge speaks for
    // them, so a .txt is offered as either; a host that cannot ask takes the
    // plain text, the more specific.
    found = [self detect:[self write:@"notes.txt" content:@"A line of text.\n"]
                registry:fabric adapters:adapters invoker:invoker error:&error];
    NSArray<NSString *> *either = @[@"media:enc=utf8;ext=requirements", @"media:enc=utf8;ext=txt;plain-text"];
    XCTAssertEqualObjects(found.media, either, @"%@", error);
    XCTAssertEqualObjects([found primary], @"media:enc=utf8;ext=txt;plain-text");

    XCTAssertEqual(invoker.unexpected.count, 0u, @"%@", invoker.unexpected);
}

// TEST7183: what a file is from its name alone is its extension's base types,
// never a refinement
- (void)test7183_aFilesMediaByNameAloneIsItsExtensionsBaseTypes {
    CSFabricRegistry *registry = [self warmMachineRegistry];
    NSError *error = nil;
    XCTAssertEqualObjects([self extensionMedia:@"json" registry:registry error:&error],
                          @[@"media:enc=utf8;ext=json;fmt=json"], @"%@", error);
    NSArray<NSString *> *txt = [self extensionMedia:@"TXT" registry:registry error:&error];
    NSArray<NSString *> *bases = @[@"media:enc=utf8;ext=requirements", @"media:enc=utf8;ext=txt;plain-text"];
    XCTAssertEqualObjects(txt, bases, @"%@", error);
    NSError *primaryError = nil;
    XCTAssertEqualObjects(CSPrimaryMedia(txt, &primaryError), @"media:enc=utf8;ext=txt;plain-text", @"%@", primaryError);

    error = nil;
    XCTAssertNil([self extensionMedia:@"zzzz" registry:registry error:&error]);
    XCTAssertEqual(error.code, CSInputResolverErrorUnknownExtension, @"%@", error);
}

// TEST7184: a refinement whose declared validation rules the content meets
// stands without a cartridge; one whose rules it fails falls; a definition
// with an invalid pattern is an error naming it
- (void)test7184_validationRulesProveOrDisproveARefinement {
    NSDictionary *(^script)(NSString *, NSString *) = ^NSDictionary *(NSString *urn, NSString *pattern) {
        return @{@"urn": urn, @"version": @1, @"media_type": @"text/plain", @"title": @"t",
                 @"extensions": @[@"txt"], @"validation": @{@"pattern": pattern}};
    };
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    [registry addMediaDef:@{@"urn": @"media:enc=utf8;ext=txt;plain-text", @"version": @1, @"media_type": @"text/plain",
                            @"title": @"Plain Text", @"extensions": @[@"txt"]}];
    [registry addMediaDef:script(@"media:enc=utf8;ext=txt;plain-text;shebang", @"^#!")];

    NSError *error = nil;
    CSFileMedia *found = [self detectWithoutAdapters:[self write:@"run.txt" content:@"#!/bin/sh\n"] registry:registry error:&error];
    XCTAssertEqualObjects(found.media, @[@"media:enc=utf8;ext=txt;plain-text;shebang"], @"%@", error);
    found = [self detectWithoutAdapters:[self write:@"prose.txt" content:@"hello\n"] registry:registry error:&error];
    XCTAssertEqualObjects(found.media, @[@"media:enc=utf8;ext=txt;plain-text"], @"%@", error);

    CSFabricRegistry *broken = [[CSFabricRegistry alloc] initForTest];
    [broken addMediaDef:script(@"media:broken;enc=utf8;ext=txt;plain-text", @"((")];
    error = nil;
    XCTAssertNil([self detectWithoutAdapters:[self write:@"x.txt" content:@"x"] registry:broken error:&error]);
    XCTAssertEqual(error.code, CSInputResolverErrorInspectionFailed, @"%@", error);
    XCTAssertTrue([error.localizedDescription containsString:@"media:broken;enc=utf8;ext=txt;plain-text"], @"%@", error);
}

#pragma mark - The file types kept beside the manifest (Rust registry.rs: TEST7186-TEST7187)

/// A manifest at 13 naming a file type and a content-only JSON record, kept
/// in `cacheDir` as a fetched manifest is. Answers its media map, and the
/// manifest file's path in *manifestFile.
- (NSDictionary<NSString *, NSNumber *> *)keepManifestIn:(NSString *)cacheDir manifestFile:(NSString *_Nullable *_Nonnull)manifestFile {
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary<NSString *, NSNumber *> *media = @{
        @"media:enc=utf8;ext=csv;fmt=csv;list;record": @2,
        @"media:download-result;enc=utf8;fmt=json;record": @1,
    };
    NSDictionary *manifest = @{@"version": @13, @"previous": @12, @"caps": @{}, @"media": media,
                               @"aliases": @{}, @"dims": @{}};
    NSString *file = [cacheDir stringByAppendingPathComponent:@"manifest.json"];
    [[NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil] writeToFile:file atomically:NO];
    *manifestFile = file;
    return media;
}

// TEST7186: the file types a manifest names are worked out once and kept
// beside it, in its version's folder; read back while that manifest file is
// unchanged, its media URNs are not parsed again; a manifest file that changed
// (fetched again) is read afresh; a manifest made in memory, with no file,
// leaves nothing behind
- (void)test7186_fileTypesAreKeptBesideTheManifestTheyWereReadFrom {
    NSString *cacheDir = [CSFabricRegistry cacheFolderOfRegistryFolder:[self scratch] manifestVersion:13];
    NSString *manifestFile = nil;
    NSDictionary<NSString *, NSNumber *> *media = [self keepManifestIn:cacheDir manifestFile:&manifestFile];
    NSString *indexFile = [cacheDir stringByAppendingPathComponent:@"file_types.json"];
    NSArray *csv = @[@[@"media:enc=utf8;ext=csv;fmt=csv;list;record", @2]];
    NSError *error = nil;

    XCTAssertEqualObjects([CSFabricRegistry fileTypesInCacheFolder:cacheDir manifestFile:manifestFile
                                                   manifestVersion:13 media:media error:&error], csv, @"%@", error);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:indexFile], @"the file types are kept beside the manifest");

    // The same manifest file, with an entry that is no media URN in the
    // manifest held in memory: the kept answer is given, so no URN of the
    // manifest was parsed.
    NSMutableDictionary<NSString *, NSNumber *> *unparsable = [media mutableCopy];
    unparsable[@"not a media urn"] = @1;
    XCTAssertEqualObjects([CSFabricRegistry fileTypesInCacheFolder:cacheDir manifestFile:manifestFile
                                                   manifestVersion:13 media:unparsable error:&error], csv, @"%@", error);

    // The manifest file changed: the kept file types are not its own.
    NSDictionary *changed = @{@"version": @13, @"previous": @12, @"caps": @{}, @"media": unparsable,
                              @"aliases": @{}, @"dims": @{}};
    [[NSJSONSerialization dataWithJSONObject:changed options:0 error:nil] writeToFile:manifestFile atomically:NO];
    error = nil;
    XCTAssertNil([CSFabricRegistry fileTypesInCacheFolder:cacheDir manifestFile:manifestFile
                                          manifestVersion:13 media:unparsable error:&error],
                 @"a manifest file that changed is read afresh");
    XCTAssertEqual(error.code, CSFabricRegistryErrorFileTypes, @"%@", error);
    XCTAssertTrue([error.localizedDescription containsString:@"'not a media urn'"], @"%@", error);

    NSString *memoryDir = [CSFabricRegistry cacheFolderOfRegistryFolder:[self scratch] manifestVersion:13];
    [[NSFileManager defaultManager] createDirectoryAtPath:memoryDir withIntermediateDirectories:YES attributes:nil error:nil];
    error = nil;
    XCTAssertEqualObjects([CSFabricRegistry fileTypesInCacheFolder:memoryDir manifestFile:nil
                                                   manifestVersion:13 media:media error:&error], csv, @"%@", error);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[memoryDir stringByAppendingPathComponent:@"file_types.json"]],
                   @"nothing is kept for a manifest with no file");
}

// TEST7187: kept file types that cannot be read are an error naming their
// file, never worked out again in silence
- (void)test7187_corruptKeptFileTypesAreAnErrorNamingTheFile {
    NSString *cacheDir = [CSFabricRegistry cacheFolderOfRegistryFolder:[self scratch] manifestVersion:13];
    NSString *manifestFile = nil;
    NSDictionary<NSString *, NSNumber *> *media = [self keepManifestIn:cacheDir manifestFile:&manifestFile];
    NSString *indexFile = [cacheDir stringByAppendingPathComponent:@"file_types.json"];
    [@"{\"manifest_sha256\": \"ab" writeToFile:indexFile atomically:NO encoding:NSUTF8StringEncoding error:nil];

    NSError *error = nil;
    XCTAssertNil([CSFabricRegistry fileTypesInCacheFolder:cacheDir manifestFile:manifestFile
                                          manifestVersion:13 media:media error:&error], @"a corrupt file is an error");
    XCTAssertEqualObjects(error.domain, CSFabricRegistryErrorDomain);
    XCTAssertEqual(error.code, CSFabricRegistryErrorCache, @"%@", error);
    XCTAssertTrue([error.localizedDescription containsString:indexFile], @"names the file: %@", error);
    XCTAssertTrue([error.localizedDescription containsString:@"corrupt"], @"%@", error);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:indexFile], @"the file is left for whoever reads the error");
}

@end
