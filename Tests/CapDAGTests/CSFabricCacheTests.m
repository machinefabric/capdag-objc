//
//  CSFabricCacheTests.m
//  CapDAGTests
//
//  The fabric definition cache on disk — mirror the Rust reference
//  (capdag-rs registry.rs `concurrent_cache_tests`) test-for-test: the disk
//  cache shared by processes that run at once, and by capdag releases pinned
//  at different fabric manifests. Shared test numbers 1990-1993.
//

#import <XCTest/XCTest.h>
#import <stdatomic.h>
#import "CSFabricRegistry.h"
#import "CSCharter.h"
#import "CSCap.h"
#import "CSCapUrn.h"

/// Registry internals these tests hold to their contract (not in the public
/// header): the designated initializer, and the cache folder, entry path,
/// whole-entry write, pinned-entry load and clear of the disk cache.
@interface CSFabricRegistry (CSFabricCacheTestsInternal)
- (instancetype)initWithCharter:(CSCharter *)charter
                         config:(CSFabricRegistryConfig *)config
                manifestVersion:(uint32_t)manifestVersion
           bootstrapFromNetwork:(BOOL)bootstrapFromNetwork;
+ (NSString *)cacheFolderOfRegistryFolder:(NSString *)registryFolder manifestVersion:(uint32_t)manifestVersion;
+ (NSString *)cacheEntryPathInFolder:(NSString *)folder
                                kind:(NSString *)kind
                                 key:(NSString *)key
                              defver:(uint32_t)defver;
+ (BOOL)storeCacheEntry:(NSDictionary *)entry
                 atPath:(NSString *)path
                   what:(NSString *)what
                  error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary *)loadPinnedEntriesFromCacheFolder:(NSString *)folder
                                                   manifest:(NSDictionary *)manifest
                                                      error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)clearCacheFolder:(NSString *)folder error:(NSError *_Nullable *_Nullable)error;
@end

@interface CSFabricCacheTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSString *> *scratchFolders;
@end

static NSString * const URN = @"cap:in=\"media:void\";shared-entry;out=\"media:record\"";

static NSString *normalizedURN(void) {
    return [[CSCapUrn fromString:URN error:nil] toString];
}

/// The cap `URN` at defver 3, titled `title`, as a definition dictionary, with
/// a documentation large enough that writing it is not one step for the file
/// system.
static NSDictionary *variant(NSString *title) {
    NSString *line = [title stringByAppendingString:@"\n"];
    NSString *documentation = [@"" stringByPaddingToLength:line.length * 2000 withString:line startingAtIndex:0];
    return @{
        @"urn": URN,
        @"version": @3,
        @"title": title,
        @"aliases": @[@"shared-entry"],
        @"documentation": documentation,
        @"outputs": @[@{@"media_urn": @"media:record", @"name": @"record", @"output_description": @"The record"}],
    };
}

/// A manifest at `version` pinning the cap `URN` at defver 3.
static NSDictionary *pinned(uint32_t version) {
    return @{@"version": @(version), @"previous": @(version - 1), @"caps": @{normalizedURN(): @3},
             @"media": @{}, @"aliases": @{}, @"dims": @{}};
}

/// The file the cap `URN` at defver 3 is kept in, in the cache folder `folder`.
static NSString *entryPath(NSString *folder) {
    return [CSFabricRegistry cacheEntryPathInFolder:folder kind:@"caps" key:normalizedURN() defver:3];
}

/// Write `definition` as the cache entry of the cap `URN` at defver 3 in
/// `folder`, whole. Answers the error, or nil when it is written.
static NSError *_Nullable store(NSString *folder, NSDictionary *definition) {
    NSError *error = nil;
    NSDictionary *entry = @{@"definition": definition, @"cached_at": @0, @"ttl_hours": @0};
    if (![CSFabricRegistry storeCacheEntry:entry atPath:entryPath(folder) what:@"cap" error:&error]) return error;
    return nil;
}

static void writeString(NSString *path, NSString *contents) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [[contents dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO];
}

static NSString *jsonString(id object) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:object options:0 error:nil]
                                 encoding:NSUTF8StringEncoding];
}

@implementation CSFabricCacheTests

- (void)setUp {
    [super setUp];
    self.scratchFolders = [NSMutableArray array];
}

- (void)tearDown {
    for (NSString *folder in self.scratchFolders) {
        [[NSFileManager defaultManager] removeItemAtPath:folder error:nil];
    }
    [super tearDown];
}

/// A new, empty folder of this test's own, removed in tearDown.
- (NSString *)scratch {
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"capdag-cache-tests-%@", [NSUUID UUID].UUIDString.lowercaseString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    [self.scratchFolders addObject:folder];
    return folder;
}

/// The charter of a fabric registry no fetch can reach (127.0.0.1:9, the
/// discard port), with a slug — and so a registry folder — of its own,
/// removed in tearDown.
- (CSCharter *)unreachableCharter:(NSString *)tag {
    NSString *unique = [NSUUID UUID].UUIDString.lowercaseString;
    NSString *anchor = [NSString stringWithFormat:@"https://127.0.0.1:9/capdag-cache-tests/%@-%@", tag, unique];
    NSString *slug = [NSString stringWithFormat:@"cache-tests-%@-%@", tag, unique];
    [self.scratchFolders addObject:[[CSFabricRegistry capdagCacheRoot] stringByAppendingPathComponent:slug]];
    return [CSFabricRegistry publisherLayoutCharterForAnchor:anchor slug:slug];
}

- (CSFabricRegistry *)registryOver:(CSCharter *)charter version:(uint32_t)version bootstrap:(BOOL)bootstrap {
    return [[CSFabricRegistry alloc] initWithCharter:charter
                                              config:[CSFabricRegistryConfig configWithAnchor:charter.anchor]
                                     manifestVersion:version
                                bootstrapFromNetwork:bootstrap];
}

/// The exception constructing a registry over `charter` at `version`,
/// bootstrapping its manifest, raises; nil when it raises none.
- (nullable NSException *)exceptionConstructingOver:(CSCharter *)charter version:(uint32_t)version {
    @try {
        [self registryOver:charter version:version bootstrap:YES];
    } @catch (NSException *exception) {
        return exception;
    }
    return nil;
}

/// The title of the one cap the cache folder `folder` holds for manifest
/// `version`, or nil when it holds none.
- (nullable NSString *)titleIn:(NSString *)folder version:(uint32_t)version {
    NSError *error = nil;
    NSDictionary *entries = [CSFabricRegistry loadPinnedEntriesFromCacheFolder:folder manifest:pinned(version) error:&error];
    XCTAssertNotNil(entries, @"%@", error);
    return ((CSCap *)[entries[@"caps"] allValues].firstObject).title;
}

// TEST1990: many readers and writers on one cache entry at once: every read
// finds no entry or one whole entry a writer wrote, never part of one and
// never an error, and no temporary file is left behind. The readers read for as
// long as any writer writes, so every write overlaps reads.
- (void)test1990_ConcurrentReadersAndWritersNeverSeeATornEntry {
    NSString *cacheDir = [CSFabricRegistry cacheFolderOfRegistryFolder:[self scratch] manifestVersion:11];
    NSDictionary *manifest = pinned(11);
    NSMutableArray<NSDictionary *> *variants = [NSMutableArray array];
    for (int n = 0; n < 4; n++) {
        [variants addObject:variant([NSString stringWithFormat:@"written by writer %d", n])];
    }

    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    void (^fail)(NSString *) = ^(NSString *failure) {
        @synchronized (failures) {
            [failures addObject:failure];
        }
    };
    // The readers read for as long as any writer writes, so every write
    // overlaps reads.
    dispatch_group_t writers = dispatch_group_create();
    dispatch_group_t readers = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    // The blocks reach these through pointers: they outlive every block,
    // since this method waits for both groups before it returns.
    atomic_bool done = false;
    atomic_long reads = 0;
    atomic_bool *donePointer = &done;
    atomic_long *readsPointer = &reads;
    for (NSDictionary *definition in variants) {
        dispatch_group_async(writers, queue, ^{
            for (int i = 0; i < 400; i++) {
                NSError *error = store(cacheDir, definition);
                if (error) fail([NSString stringWithFormat:@"a write failed: %@", error.localizedDescription]);
            }
        });
    }
    for (int reader = 0; reader < 4; reader++) {
        dispatch_group_async(readers, queue, ^{
            while (!atomic_load(donePointer)) {
                atomic_fetch_add(readsPointer, 1);
                NSError *error = nil;
                NSDictionary *entries = [CSFabricRegistry loadPinnedEntriesFromCacheFolder:cacheDir
                                                                                  manifest:manifest
                                                                                     error:&error];
                if (!entries) {
                    fail(error.localizedDescription ?: @"a read failed without an error");
                    continue;
                }
                CSCap *cap = [entries[@"caps"] allValues].firstObject;
                if (!cap) continue;
                BOOL written = NO;
                for (NSDictionary *v in variants) {
                    if ([v[@"title"] isEqualToString:cap.title] && [v[@"documentation"] isEqualToString:cap.documentation]) {
                        written = YES;
                    }
                }
                if (!written) fail([NSString stringWithFormat:@"read a cap no writer wrote: %@", cap.title]);
            }
        });
    }
    XCTAssertEqual(dispatch_group_wait(writers, dispatch_time(DISPATCH_TIME_NOW, (int64_t)600 * NSEC_PER_SEC)), 0L,
                   @"every writer finishes");
    atomic_store(&done, true);
    XCTAssertEqual(dispatch_group_wait(readers, dispatch_time(DISPATCH_TIME_NOW, (int64_t)60 * NSEC_PER_SEC)), 0L,
                   @"every reader finishes");
    XCTAssertGreaterThan(atomic_load(&reads), 0L, @"the readers read while the writers wrote");

    XCTAssertEqual(failures.count, 0u, @"%lu torn or failed reads, first: %@",
                   (unsigned long)failures.count, failures.firstObject);
    NSError *error = nil;
    NSDictionary *loaded = [CSFabricRegistry loadPinnedEntriesFromCacheFolder:cacheDir manifest:manifest error:&error];
    XCTAssertEqual([loaded[@"caps"] count], 1u, @"the entry is there at the end: %@", error);
    NSArray<NSString *> *left = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:[entryPath(cacheDir) stringByDeletingLastPathComponent] error:nil];
    XCTAssertEqualObjects(left, @[@"3.json"], @"no temporary file is left behind");
}

// TEST1991: two fabric manifest versions share one registry folder: each keeps
// its entries in a folder of its own, and reads only what was cached for it,
// even where both manifests pin the same definition at the same defver.
- (void)test1991_TwoManifestVersionsReadOnlyTheirOwnEntries {
    NSString *registryFolder = [self scratch];
    NSString *v10 = [CSFabricRegistry cacheFolderOfRegistryFolder:registryFolder manifestVersion:10];
    NSString *v13 = [CSFabricRegistry cacheFolderOfRegistryFolder:registryFolder manifestVersion:13];
    XCTAssertNotEqualObjects(v10, v13, @"each manifest version has a folder of its own");

    XCTAssertNil(store(v10, variant(@"cached for manifest 10")));
    XCTAssertNil([self titleIn:v13 version:13], @"manifest 13 does not read what was cached for manifest 10");

    XCTAssertNil(store(v13, variant(@"cached for manifest 13")));
    XCTAssertEqualObjects([self titleIn:v10 version:10], @"cached for manifest 10");
    XCTAssertEqualObjects([self titleIn:v13 version:13], @"cached for manifest 13");

    CSCharter *charter = [self unreachableCharter:@"1991"];
    CSFabricRegistry *a = [self registryOver:charter version:10 bootstrap:NO];
    CSFabricRegistry *b = [self registryOver:charter version:13 bootstrap:NO];
    XCTAssertNotEqualObjects(a.cacheDirectory, b.cacheDirectory, @"registries at two manifests cache in two folders");
    XCTAssertEqualObjects([a.cacheDirectory stringByDeletingLastPathComponent],
                          [b.cacheDirectory stringByDeletingLastPathComponent], @"under one registry folder");
    XCTAssertEqualObjects([a.cacheDirectory stringByDeletingLastPathComponent],
                          [[CSFabricRegistry capdagCacheRoot] stringByAppendingPathComponent:charter.slug],
                          @"the registry folder is the charter's slug");
}

// TEST1992: an entry that is there and is not what its path names is reported
// naming its file, and left where it is; it is never taken for a missing
// entry. That covers a body that does not parse, one holding another
// definition or defver, and a cached manifest that does not parse or is
// another version's. Each fails the construction of a registry over the cache.
- (void)test1992_ACorruptEntryIsReportedNamingItsFile {
    NSString *cacheDir = [CSFabricRegistry cacheFolderOfRegistryFolder:[self scratch] manifestVersion:11];
    NSDictionary *manifest = pinned(11);
    NSString *file = entryPath(cacheDir);
    NSFileManager *fm = [NSFileManager defaultManager];

    writeString(file, @"{\"definition\": {\"urn\": \"cap:in=");
    NSError *error = nil;
    XCTAssertNil([CSFabricRegistry loadPinnedEntriesFromCacheFolder:cacheDir manifest:manifest error:&error],
                 @"a truncated entry is an error");
    XCTAssertEqualObjects(error.domain, CSFabricRegistryErrorDomain);
    XCTAssertEqual(error.code, CSFabricRegistryErrorCache, @"%@", error);
    XCTAssertTrue([error.localizedDescription containsString:file], @"names the file: %@", error);
    XCTAssertTrue([error.localizedDescription containsString:@"corrupt"], @"%@", error);
    XCTAssertTrue([error.localizedDescription containsString:@"capdag cache clear"], @"%@", error);
    XCTAssertTrue([fm fileExistsAtPath:file], @"the file is left for whoever reads the error");

    NSMutableDictionary *other = [variant(@"another defver") mutableCopy];
    other[@"version"] = @4;
    XCTAssertNil(store(cacheDir, other));
    error = nil;
    XCTAssertNil([CSFabricRegistry loadPinnedEntriesFromCacheFolder:cacheDir manifest:manifest error:&error],
                 @"another defver is an error");
    XCTAssertTrue([error.localizedDescription containsString:file], @"%@", error);
    XCTAssertTrue([error.localizedDescription containsString:@"defver 4"], @"%@", error);
    XCTAssertTrue([fm fileExistsAtPath:file]);

    // A registry refuses to open on the cache: a corrupt entry it pins, with
    // a cached manifest that is sound.
    CSCharter *charter = [self unreachableCharter:@"1992"];
    NSString *registryCache = [CSFabricRegistry cacheFolderOfRegistryFolder:
        [[CSFabricRegistry capdagCacheRoot] stringByAppendingPathComponent:charter.slug] manifestVersion:11];
    NSString *manifestFile = [registryCache stringByAppendingPathComponent:@"manifest.json"];
    NSString *registryEntry = entryPath(registryCache);
    writeString(manifestFile, jsonString(manifest));
    writeString(registryEntry, @"{\"definition\": {\"urn\": \"cap:in=");
    NSException *exception = [self exceptionConstructingOver:charter version:11];
    XCTAssertEqualObjects(exception.name, @"CSFabricRegistryCacheError", @"%@", exception);
    XCTAssertTrue([exception.reason containsString:registryEntry], @"%@", exception.reason);
    XCTAssertTrue([fm fileExistsAtPath:registryEntry]);

    // A cached manifest that does not parse is an error naming it, not a fetch:
    // a fetch from this anchor raises CSFabricRegistryManifestUnavailable.
    writeString(manifestFile, @"{\"version\": 11, \"prev");
    exception = [self exceptionConstructingOver:charter version:11];
    XCTAssertEqualObjects(exception.name, @"CSFabricRegistryCacheError", @"a corrupt manifest is an error, not a fetch: %@", exception);
    XCTAssertTrue([exception.reason containsString:manifestFile], @"%@", exception.reason);
    XCTAssertTrue([fm fileExistsAtPath:manifestFile]);

    // Nor is another version's manifest in this version's folder.
    writeString(manifestFile, jsonString(pinned(12)));
    exception = [self exceptionConstructingOver:charter version:11];
    XCTAssertEqualObjects(exception.name, @"CSFabricRegistryCacheError", @"%@", exception);
    XCTAssertTrue([exception.reason containsString:manifestFile], @"%@", exception.reason);
    XCTAssertTrue([exception.reason containsString:@"it is manifest 12, in the folder of manifest 11"], @"%@", exception.reason);
}

// TEST1993: clearing a manifest version's cache empties its folder and removes
// the folders the shared layout before it kept in the registry's folder; other
// manifest versions' folders and the stored charter stay.
- (void)test1993_ClearingEmptiesOneVersionAndRemovesTheOldSharedFolders {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *registryFolder = [[self scratch] stringByAppendingPathComponent:@"example-fabric"];
    NSString *v11 = [CSFabricRegistry cacheFolderOfRegistryFolder:registryFolder manifestVersion:11];
    NSString *v10 = [CSFabricRegistry cacheFolderOfRegistryFolder:registryFolder manifestVersion:10];
    XCTAssertNil(store(v11, variant(@"eleven")));
    XCTAssertNil(store(v10, variant(@"ten")));
    writeString([v11 stringByAppendingPathComponent:@"manifest.json"], @"{}");
    writeString([v11 stringByAppendingPathComponent:@".manifest.json.1-0.tmp"], @"half");
    writeString([registryFolder stringByAppendingPathComponent:@"charter.json"], @"{}");
    NSArray<NSString *> *legacyFolders = @[@"caps", @"media", @"aliases", @"dims", @"manifests"];
    for (NSString *legacy in legacyFolders) {
        writeString([[[registryFolder stringByAppendingPathComponent:legacy] stringByAppendingPathComponent:@"ab"]
                     stringByAppendingPathComponent:@"1.json"], @"{}");
    }

    NSError *error = nil;
    XCTAssertTrue([CSFabricRegistry clearCacheFolder:v11 error:&error], @"clears: %@", error);

    NSArray<NSString *> *kinds = @[@"caps", @"media", @"aliases", @"dims"];
    for (NSString *kind in kinds) {
        NSString *folder = [v11 stringByAppendingPathComponent:kind];
        BOOL isFolder = NO;
        XCTAssertTrue([fm fileExistsAtPath:folder isDirectory:&isFolder] && isFolder, @"%@ stays", kind);
        XCTAssertEqual([fm contentsOfDirectoryAtPath:folder error:nil].count, 0u, @"%@ is empty", kind);
    }
    XCTAssertEqualObjects([[fm contentsOfDirectoryAtPath:v11 error:nil] sortedArrayUsingSelector:@selector(compare:)],
                          [kinds sortedArrayUsingSelector:@selector(compare:)], @"only the kinds' folders are left");
    for (NSString *legacy in legacyFolders) {
        XCTAssertFalse([fm fileExistsAtPath:[registryFolder stringByAppendingPathComponent:legacy]],
                       @"the old shared %@ folder is removed", legacy);
    }
    XCTAssertEqualObjects([self titleIn:v10 version:10], @"ten", @"manifest 10's cache stays");
    XCTAssertTrue([fm fileExistsAtPath:[registryFolder stringByAppendingPathComponent:@"charter.json"]], @"the charter stays");
}

@end
