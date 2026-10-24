//
//  CSCharterTests.m
//  CapDAGTests
//
//  Charters, read as a client of this mirror reads them. Mirrors the
//  structural half of Rust `bifaci/charter_tests.rs`: the shape, the
//  locations, the folder a stored charter proves and the anchor a fetched one
//  must be for. The signature half (TEST12910, 12911, 12914–12918) has no
//  counterpart here, because this mirror verifies no chain (see CSCharter.h).
//  Every refusal below starts from a charter that reads, changes one thing,
//  and checks that the one thing is what is refused.
//

#import <XCTest/XCTest.h>
#import "CSCharter.h"

static NSString * const CartridgesAnchor = @"https://registry.example/cartridges";
static NSString * const CartridgesSlug = @"example-cartridges";

/// A prod cartridges charter's fields.
static NSMutableDictionary *cartridgesFields(void) {
    return [@{
        @"format": CSCharterFormat,
        @"anchor": CartridgesAnchor,
        @"kind": @"cartridges",
        @"slug": CartridgesSlug,
        @"environment": @"prod",
        @"locations": @{@"manifest": [CartridgesAnchor stringByAppendingString:@"/v{registry_version}/manifest"]},
        @"fabric": @"https://registry.example/fabric",
        @"issued_at": @1792800000,
        @"not_after": [NSNull null],
    } mutableCopy];
}

/// A prod fabric charter's fields, at `anchor`.
static NSMutableDictionary *fabricFields(NSString *anchor) {
    return [@{
        @"format": CSCharterFormat,
        @"anchor": anchor,
        @"kind": @"fabric",
        @"slug": @"test-fabric",
        @"environment": @"prod",
        @"locations": @{
            @"manifest": [anchor stringByAppendingString:@"/manifest/{manifest_version}.json"],
            @"latest": [anchor stringByAppendingString:@"/manifest/latest.json"],
            @"definition": [anchor stringByAppendingString:@"/{kind}/{urn_hash}/{version}.json"],
        },
        @"issued_at": @1792800000,
        @"not_after": [NSNull null],
    } mutableCopy];
}

/// A lab cartridges charter's fields, with an expiry of its own.
static NSMutableDictionary *labFields(void) {
    NSMutableDictionary *fields = cartridgesFields();
    NSString *anchor = @"https://lab.example/exp/t1/cartridges";
    fields[@"anchor"] = anchor;
    fields[@"slug"] = @"lab-t1-cartridges";
    fields[@"environment"] = @"lab";
    fields[@"experiment"] = @"t1";
    fields[@"locations"] = @{@"manifest": [anchor stringByAppendingString:@"/v{registry_version}/manifest"]};
    fields[@"not_after"] = @1800576000;
    return fields;
}

static NSData *jsonOf(NSDictionary *fields) {
    return [NSJSONSerialization dataWithJSONObject:fields options:0 error:nil];
}

/// `fields` as its anchor would serve it. The signature is opaque here: this
/// mirror carries it and never reads it.
static CSFetchedCharter *fetchedOf(NSDictionary *fields) {
    NSData *body = jsonOf(fields);
    CSCharter *charter = [CSCharter charterWithData:body error:nil];
    return [[CSFetchedCharter alloc] initWithCharter:charter body:body
                                           signature:[@"{\"format\":\"machinefabric-charter-sig/1\"}" dataUsingEncoding:NSUTF8StringEncoding]];
}

/// Store `fields` in `{root}/{folder}`, as an installer does — under another
/// name than the slug by writing the files directly, which the store refuses.
static void storeCharter(NSString *root, NSString *folder, NSDictionary *fields) {
    CSFetchedCharter *fetched = fetchedOf(fields);
    NSString *dir = [root stringByAppendingPathComponent:folder];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [fetched.body writeToFile:[dir stringByAppendingPathComponent:CSCharterFile] atomically:YES];
    [fetched.signature writeToFile:[dir stringByAppendingPathComponent:CSCharterSigFile] atomically:YES];
}

// MARK: - A registry served from memory

/// Path → body; anything else answers 404.
static NSDictionary<NSString *, NSData *> *CSCharterServed;

@interface CSCharterServingProtocol : NSURLProtocol
@end

@implementation CSCharterServingProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSData *body = CSCharterServed[self.request.URL.path];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:body ? 200 : 404
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (body) [self.client URLProtocol:self didLoadData:body];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

/// A session whose requests are answered by `served`.
static NSURLSession *servingSession(NSDictionary<NSString *, NSData *> *served) {
    CSCharterServed = served;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.protocolClasses = @[[CSCharterServingProtocol class]];
    return [NSURLSession sessionWithConfiguration:config];
}

@interface CSCharterTests : XCTestCase
@property (nonatomic, copy) NSString *root;
@end

@implementation CSCharterTests

- (void)setUp {
    [super setUp];
    self.root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                 [@"capdag-charter-tests-" stringByAppendingString:[NSUUID UUID].UUIDString]];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.root error:nil];
    [super tearDown];
}

// TEST12912: a valid charter served under another anchor is refused — a
// registry cannot borrow another's charter. Nothing at an anchor's
// charter.json makes it no registry at all.
- (void)test12912_aCharterForAnotherAnchorIsRefused {
    NSString *anchor = @"https://served.example/fabric";
    NSData *sig = [@"sig" dataUsingEncoding:NSUTF8StringEncoding];
    NSURLSession *own = servingSession(@{@"/fabric/charter.json": jsonOf(fabricFields(anchor)),
                                         @"/fabric/charter.json.sig": sig});
    NSError *error = nil;
    CSFetchedCharter *got = [CSFetchedCharter fetchFromAnchor:anchor kind:CSRegistryKindFabric session:own error:&error];
    XCTAssertNotNil(got, @"the charter served for its own anchor reads: %@", error);
    XCTAssertEqualObjects(got.charter.anchor, anchor);

    error = nil;
    XCTAssertNil([CSFetchedCharter fetchFromAnchor:@"https://served.example/nowhere" kind:CSRegistryKindFabric
                                           session:own error:&error]);
    XCTAssertEqual(error.code, CSCharterErrorUnchartered, @"%@", error);

    NSURLSession *borrowed = servingSession(@{@"/fabric/charter.json": jsonOf(fabricFields(@"https://registry.example/fabric")),
                                              @"/fabric/charter.json.sig": sig});
    error = nil;
    XCTAssertNil([CSFetchedCharter fetchFromAnchor:anchor kind:CSRegistryKindFabric session:borrowed error:&error]);
    XCTAssertEqual(error.code, CSCharterErrorRefused, @"%@", error);
}

// TEST12913: a charter of one kind does not stand for another kind — fetched,
// or stored in a registry's folder.
- (void)test12913_aCharterOfAnotherKindIsRefused {
    NSString *anchor = @"https://served.example/fabric";
    NSURLSession *session = servingSession(@{@"/fabric/charter.json": jsonOf(fabricFields(anchor)),
                                             @"/fabric/charter.json.sig": [@"sig" dataUsingEncoding:NSUTF8StringEncoding]});
    NSError *error = nil;
    XCTAssertNil([CSFetchedCharter fetchFromAnchor:anchor kind:CSRegistryKindCartridges session:session error:&error]);
    XCTAssertEqual(error.code, CSCharterErrorRefused, @"%@", error);

    storeCharter(self.root, @"test-fabric", fabricFields(@"https://registry.example/fabric"));
    NSString *folder = [self.root stringByAppendingPathComponent:@"test-fabric"];
    error = nil;
    XCTAssertNil([CSCharter storedInFolder:folder kind:CSRegistryKindCartridges error:&error],
                 @"a fabric's charter does not open a cartridges folder");
    XCTAssertEqual(error.code, CSCharterErrorRefused, @"%@", error);
    XCTAssertNotNil([CSCharter storedInFolder:folder kind:CSRegistryKindFabric error:nil]);
}

// TEST12919: a location is filled with exactly the placeholders it takes —
// one missing, or one it does not take, is refused rather than guessed.
- (void)test12919_aLocationTakesExactlyItsPlaceholders {
    CSCharter *fabric = [CSCharter charterWithData:jsonOf(fabricFields(@"https://registry.example/fabric")) error:nil];
    XCTAssertEqualObjects(([fabric locationNamed:@"definition"
                                          values:@{@"kind": @"caps", @"urn_hash": @"ab12", @"version": @"3"}
                                           error:nil]),
                          @"https://registry.example/fabric/caps/ab12/3.json");
    XCTAssertNil(([fabric locationNamed:@"definition" values:@{@"kind": @"caps", @"urn_hash": @"ab12"} error:nil]),
                 @"a placeholder left unfilled");
    XCTAssertNil([fabric locationNamed:@"latest" values:@{@"version": @"3"} error:nil],
                 @"a placeholder the location does not take");
    XCTAssertNil([fabric locationNamed:@"schema" values:@{} error:nil], @"a fabric charter has no schema location");
}

// TEST12920: the shape every charter must have. Each case is a charter that
// reads with one thing wrong; the unchanged charter passes, so each refusal is
// about the one change.
- (void)test12920_aCharterOutOfShapeIsMalformed {
    NSError *error = nil;
    XCTAssertNotNil([CSCharter charterWithData:jsonOf(cartridgesFields()) error:&error], @"%@", error);
    XCTAssertNotNil([CSCharter charterWithData:jsonOf(labFields()) error:&error], @"%@", error);

    void (^refused)(NSString *, void (^)(NSMutableDictionary *)) = ^(NSString *why, void (^change)(NSMutableDictionary *)) {
        NSMutableDictionary *fields = cartridgesFields();
        change(fields);
        NSError *refusal = nil;
        XCTAssertNil([CSCharter charterWithData:jsonOf(fields) error:&refusal], @"%@ was accepted", why);
        XCTAssertEqual(refusal.code, CSCharterErrorMalformed, @"%@: %@", why, refusal);
    };
    NSString *manifest = @"manifest";
    refused(@"an http anchor", ^(NSMutableDictionary *f) { f[@"anchor"] = @"http://registry.example/cartridges"; });
    refused(@"an anchor ending in /", ^(NSMutableDictionary *f) { f[@"anchor"] = [CartridgesAnchor stringByAppendingString:@"/"]; });
    refused(@"the reserved dev slug", ^(NSMutableDictionary *f) { f[@"slug"] = CSCharterDevSlug; });
    refused(@"a slug outside [a-z0-9.-]", ^(NSMutableDictionary *f) { f[@"slug"] = @"Has_Upper"; });
    refused(@"no manifest location", ^(NSMutableDictionary *f) { f[@"locations"] = @{}; });
    refused(@"a manifest location without {registry_version}",
            ^(NSMutableDictionary *f) { f[@"locations"] = @{manifest: @"https://r.example/manifest"}; });
    refused(@"a placeholder the location does not take",
            ^(NSMutableDictionary *f) { f[@"locations"] = @{manifest: @"https://r.example/v{registry_version}/{app_id}"}; });
    refused(@"a location of another kind", ^(NSMutableDictionary *f) {
        NSMutableDictionary *locations = [f[@"locations"] mutableCopy];
        locations[@"latest"] = @"https://r.example/latest";
        f[@"locations"] = locations;
    });
    refused(@"a cartridges registry with no fabric", ^(NSMutableDictionary *f) { [f removeObjectForKey:@"fabric"]; });
    refused(@"an experiment that is not an id", ^(NSMutableDictionary *f) { f[@"experiment"] = @"Not An Id"; });
    refused(@"a not_after that is not after issue", ^(NSMutableDictionary *f) { f[@"not_after"] = f[@"issued_at"]; });
    refused(@"a field no charter has", ^(NSMutableDictionary *f) { f[@"surprise"] = @1; });
    refused(@"a document of another format", ^(NSMutableDictionary *f) { f[@"format"] = @"machinefabric-manifest-sig/1"; });
}

// TEST12921: a stored charter proves its folder only under its own slug: a
// folder renamed after install is refused, though the charter reads.
- (void)test12921_aStoredCharterHoldsItsFolderToItsSlug {
    storeCharter(self.root, CartridgesSlug, cartridgesFields());
    NSError *error = nil;
    CSCharter *opened = [CSCharter storedInFolder:[self.root stringByAppendingPathComponent:CartridgesSlug]
                                             kind:CSRegistryKindCartridges error:&error];
    XCTAssertEqualObjects(opened.anchor, CartridgesAnchor, @"a stored charter reads offline: %@", error);

    NSString *renamed = [self.root stringByAppendingPathComponent:@"cartridges.machinefabric.com"];
    [[NSFileManager defaultManager] moveItemAtPath:[self.root stringByAppendingPathComponent:CartridgesSlug]
                                            toPath:renamed error:nil];
    error = nil;
    XCTAssertNil([CSCharter storedInFolder:renamed kind:CSRegistryKindCartridges error:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"stored in a folder named 'cartridges.machinefabric.com'"],
                  @"%@", error);
    XCTAssertFalse([fetchedOf(cartridgesFields()) storeInFolder:renamed error:nil],
                   @"a charter is never stored under another name");
}

// TEST12922: a registry folder is opened through its charter, and found by
// its anchor — never by its name.
- (void)test12922_registryFoldersAreFoundByTheirCharters {
    storeCharter(self.root, CartridgesSlug, cartridgesFields());
    storeCharter(self.root, @"lab-t1-cartridges", labFields());
    // A folder named like the anchor's host holds no charter, and is not it.
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.root stringByAppendingPathComponent:@"registry.example"]
                              withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *folder = nil;
    CSCharter *found = [CSCharter storedUnder:self.root forAnchor:CartridgesAnchor kind:CSRegistryKindCartridges folder:&folder];
    XCTAssertEqualObjects(found.slug, CartridgesSlug, @"the registry's folder is found by its anchor");
    XCTAssertEqualObjects(folder, [self.root stringByAppendingPathComponent:CartridgesSlug]);
    XCTAssertNil([CSCharter storedUnder:self.root forAnchor:@"https://registry.example/elsewhere"
                                   kind:CSRegistryKindCartridges folder:nil],
                 @"an anchor with no stored charter finds nothing");
    NSError *error = nil;
    XCTAssertNil([CSCharter storedInFolder:[self.root stringByAppendingPathComponent:@"registry.example"]
                                      kind:CSRegistryKindCartridges error:&error],
                 @"a folder with no charter is no registry's");
}

@end
