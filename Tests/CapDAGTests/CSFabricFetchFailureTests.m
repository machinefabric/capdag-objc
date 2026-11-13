//
//  CSFabricFetchFailureTests.m
//  A fetch the registry refused, or did not answer, is reported as itself —
//  the URL, the status and the manifest version — and never as a definition
//  the registry does not have. The registry's session is answered by a stub
//  protocol.
//
//  Tests use // TEST###: comments matching the Rust implementation for
//  cross-tracking.
//
//  Three of the reference's fetch-failure tests have no port here, because
//  this library has none of the code they exercise:
//  - 7174 (a refused alias in a machine fails with the refusal) and 7176 (a
//    constant whose media definition was refused reports the refusal) parse
//    machine notation; this library has no machine-notation parser.
//  - 7175 (a refused alias fetch is remembered by the lookups that cannot
//    wait) needs an alias fetch; this library never fetches an alias over
//    the network, it reads only the aliases in the pinned cache. What 7175
//    checks of media definitions, Pending and then the refusal, is 7173 here.
//

#import <XCTest/XCTest.h>
#import "CSFabricRegistry.h"

/// What the stub answers every request with: an HTTP status, or 0 for a
/// request that times out.
static NSInteger CSFetchFailureAnswer = 403;
/// How many requests the stub was asked, by path.
static NSMutableDictionary<NSString *, NSNumber *> *CSFetchFailureAsked;

@interface CSFetchFailureProtocol : NSURLProtocol
@end

@implementation CSFetchFailureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSString *path = self.request.URL.path;
    @synchronized (CSFetchFailureAsked) {
        CSFetchFailureAsked[path] = @([CSFetchFailureAsked[path] integerValue] + 1);
    }
    if (CSFetchFailureAnswer == 0) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                           code:NSURLErrorTimedOut
                                                                       userInfo:nil]];
        return;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:CSFetchFailureAnswer
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[@"stub" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

/// The registry's session and manifest maps, which the class extension
/// declares, reached from the tests.
@interface CSFabricRegistry (FetchFailureTesting)
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestMedia;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestCaps;
@property (nonatomic, copy) NSString *manifestTemplate;
- (void)bootstrapManifest;
- (nullable NSString *)normalizeMediaUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)normalizeCapUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error;
@end

static NSString * const CSFailureMedia = @"media:refusal-probe;enc=utf8";
static NSString * const CSFailureCap = @"cap:in=\"media:refusal-probe;enc=utf8\";refusal-probe;out=\"media:refusal-probe;enc=utf8\"";

@interface CSFabricFetchFailureTests : XCTestCase
@end

@implementation CSFabricFetchFailureTests

/// A test registry whose every fetch is answered `answer`, its manifest
/// naming the probe cap and media def, neither of them in memory.
- (CSFabricRegistry *)registryAnswering:(NSInteger)answer {
    CSFetchFailureAnswer = answer;
    CSFetchFailureAsked = [NSMutableDictionary dictionary];
    CSFabricRegistry *registry = [[CSFabricRegistry alloc] initForTest];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.protocolClasses = @[[CSFetchFailureProtocol class]];
    registry.session = [NSURLSession sessionWithConfiguration:config];
    registry.manifestMedia[[registry normalizeMediaUrn:CSFailureMedia error:nil]] = @1;
    registry.manifestCaps[[registry normalizeCapUrn:CSFailureCap error:nil]] = @1;
    return registry;
}

- (NSError *)mediaFetchErrorOf:(CSFabricRegistry *)registry {
    XCTestExpectation *done = [self expectationWithDescription:@"media fetch"];
    __block NSError *failure = nil;
    [registry getMediaDef:CSFailureMedia completion:^(NSDictionary *spec, NSError *error) {
        XCTAssertNil(spec);
        failure = error;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:10];
    return failure;
}

- (NSError *)capFetchErrorOf:(CSFabricRegistry *)registry {
    XCTestExpectation *done = [self expectationWithDescription:@"cap fetch"];
    __block NSError *failure = nil;
    [registry getCapWithUrn:CSFailureCap completion:^(CSCap *cap, NSError *error) {
        XCTAssertNil(cap);
        failure = error;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:10];
    return failure;
}

// TEST7167: a manifest fetch the registry refuses (403) is reported as the
// refusal — the URL, the status and the manifest version — and not as a
// manifest that is not found.
- (void)test7167_aRefusedManifestFetchIsReportedAsTheRefusal {
    CSFabricRegistry *registry = [self registryAnswering:403];
    [[NSFileManager defaultManager] removeItemAtPath:[registry.cacheDirectory stringByAppendingPathComponent:@"manifest.json"]
                                               error:nil];
    NSException *raised = nil;
    @try {
        [registry bootstrapManifest];
    } @catch (NSException *exception) {
        raised = exception;
    }
    XCTAssertNotNil(raised, @"a refused manifest stops the registry");
    NSError *refusal = raised.userInfo[NSUnderlyingErrorKey];
    XCTAssertEqual(refusal.code, CSFabricRegistryErrorFetchFailed);
    XCTAssertEqualObjects(refusal.userInfo[CSFabricFetchWhatKey], @"manifest v1");
    XCTAssertEqualObjects(refusal.userInfo[CSFabricFetchStatusKey], @403);
    XCTAssertEqualObjects(refusal.userInfo[CSFabricFetchManifestVersionKey], @1);
    for (NSString *part in @[@"refused", @"HTTP 403", refusal.userInfo[CSFabricFetchURLKey], @"fabric manifest v1"]) {
        XCTAssertTrue([raised.reason containsString:part], @"'%@' is missing from: %@", part, raised.reason);
    }
    XCTAssertFalse([raised.reason.lowercaseString containsString:@"not found"], @"%@", raised.reason);
}

// TEST7168: a manifest the registry answers 404 for is the registry's word
// that it has no such manifest: NotFound, naming the URL and the status.
- (void)test7168_aManifestTheRegistryDoesNotHaveIsNotFound {
    CSFabricRegistry *registry = [self registryAnswering:404];
    [[NSFileManager defaultManager] removeItemAtPath:[registry.cacheDirectory stringByAppendingPathComponent:@"manifest.json"]
                                               error:nil];
    NSString *url = [registry.manifestTemplate stringByReplacingOccurrencesOfString:@"{manifest_version}" withString:@"1"];
    NSException *raised = nil;
    @try {
        [registry bootstrapManifest];
    } @catch (NSException *exception) {
        raised = exception;
    }
    XCTAssertNotNil(raised, @"a manifest the registry does not have stops the registry");
    NSError *absent = raised.userInfo[NSUnderlyingErrorKey];
    XCTAssertEqual(absent.code, CSFabricRegistryErrorNotFound, @"%@", absent);
    XCTAssertTrue([absent.localizedDescription containsString:@"HTTP 404"], @"%@", absent.localizedDescription);
    XCTAssertTrue([absent.localizedDescription containsString:url], @"'%@' is missing from: %@", url, absent.localizedDescription);
    XCTAssertEqualObjects(raised.reason, absent.localizedDescription);
}

// TEST7169: a refused fetch of a cap or a media def is reported as the
// refusal, each with its own URL, the status and the manifest version it was
// fetched for.
- (void)test7169_aRefusedDefinitionFetchIsReportedAsTheRefusal {
    CSFabricRegistry *registry = [self registryAnswering:403];
    NSString *mediaWhat = [NSString stringWithFormat:@"media def '%@' (defver 1)", [registry normalizeMediaUrn:CSFailureMedia error:nil]];
    NSString *capWhat = [NSString stringWithFormat:@"cap '%@' (defver 1)", [registry normalizeCapUrn:CSFailureCap error:nil]];
    NSArray *cases = @[@[[self mediaFetchErrorOf:registry], mediaWhat], @[[self capFetchErrorOf:registry], capWhat]];
    for (NSArray *c in cases) {
        NSError *refusal = c[0];
        XCTAssertEqual(refusal.code, CSFabricRegistryErrorFetchFailed, @"%@", refusal);
        XCTAssertEqualObjects(refusal.userInfo[CSFabricFetchWhatKey], c[1]);
        XCTAssertEqualObjects(refusal.userInfo[CSFabricFetchStatusKey], @403);
        XCTAssertEqualObjects(refusal.userInfo[CSFabricFetchManifestVersionKey], @1);
        NSString *url = refusal.userInfo[CSFabricFetchURLKey];
        XCTAssertEqualObjects(CSFetchFailureAsked[[NSURL URLWithString:url].path], @1, @"fetched once from %@", url);
        XCTAssertTrue([refusal.localizedDescription containsString:url], @"%@", refusal.localizedDescription);
    }
}

// TEST7170: a registry that answers 503 is reported with the 503 — never as a
// missing definition. (This mirror has no retry layer: the reference asks a
// 503 again before it reports it.)
- (void)test7170_aRegistryThatKeepsFailingIsReportedWithItsStatus {
    NSError *failure = [self mediaFetchErrorOf:[self registryAnswering:503]];
    XCTAssertEqual(failure.code, CSFabricRegistryErrorFetchFailed);
    XCTAssertEqualObjects(failure.userInfo[CSFabricFetchStatusKey], @503);
}

// TEST7171: a registry that does not answer is reported as a fetch that timed
// out, with the URL and the manifest version.
- (void)test7171_aRegistryThatDoesNotAnswerIsReportedAsATimeout {
    NSError *timeout = [self mediaFetchErrorOf:[self registryAnswering:0]];
    XCTAssertEqual(timeout.code, CSFabricRegistryErrorFetchFailed);
    XCTAssertEqualObjects(timeout.userInfo[CSFabricFetchCauseKey], @"timed_out");
    XCTAssertEqualObjects(timeout.userInfo[CSFabricFetchManifestVersionKey], @1);
    XCTAssertTrue([timeout.localizedDescription containsString:@"timed out"], @"%@", timeout.localizedDescription);
}

// TEST7172: a definition the registry answers 404 for is the registry's word
// that it does not have it, and only that is NotFound.
- (void)test7172_aDefinitionTheRegistryDoesNotHaveIsNotFound {
    CSFabricRegistry *registry = [self registryAnswering:404];
    for (NSError *absent in @[[self mediaFetchErrorOf:registry], [self capFetchErrorOf:registry]]) {
        XCTAssertEqual(absent.code, CSFabricRegistryErrorNotFound, @"%@", absent);
        XCTAssertTrue([absent.localizedDescription containsString:@"HTTP 404"], @"%@", absent.localizedDescription);
    }
}

// TEST7173: the synchronous lookup reports a refused fetch as the refusal,
// where it used to come back empty — says a def that has not been fetched is
// pending — and reports one the manifest does not name as not found.
- (void)test7173_aSynchronousLookupReportsARefusedFetch {
    CSFabricRegistry *registry = [self registryAnswering:403];
    NSError *pending = nil;
    XCTAssertNil([registry getCachedMediaDef:CSFailureMedia error:&pending]);
    XCTAssertEqual(pending.code, CSFabricRegistryErrorPending, @"%@", pending);

    [self mediaFetchErrorOf:registry];
    NSError *refusal = nil;
    XCTAssertNil([registry getCachedMediaDef:CSFailureMedia error:&refusal]);
    XCTAssertEqual(refusal.code, CSFabricRegistryErrorFetchFailed, @"%@", refusal);
    XCTAssertEqualObjects(refusal.userInfo[CSFabricFetchStatusKey], @403);

    NSError *absent = nil;
    XCTAssertNil([registry getCachedMediaDef:@"media:named-by-no-manifest" error:&absent]);
    XCTAssertNotNil(absent, @"a media def the manifest does not name says so");
    XCTAssertNotEqual(absent.code, CSFabricRegistryErrorFetchFailed);
    XCTAssertNotEqual(absent.code, CSFabricRegistryErrorPending);
}

@end
