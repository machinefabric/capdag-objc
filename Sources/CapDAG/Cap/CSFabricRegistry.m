//
//  CSFabricRegistry.m
//  CapDAG
//
//  Unified registry implementation. Replaces the previous split between
//  a cap-only registry and a media-only registry. Holds:
//
//    - cachedCaps: in-memory map of normalised cap URN → CSCap.
//    - cachedSpecs: in-memory map of normalised media URN → spec dict.
//    - extensionIndex: lowercase extension → array of URNs, populated
//      as media defs land in cachedSpecs.
//    - cachedAliases / cachedDims: name → stored alias / dim, versioned-only.
//
//  Atomic cap fetch: getCapWithUrn: refuses to cache a cap until every
//  media URN it references has also been successfully fetched. The bare
//  `media:` wildcard is excluded from the recursive fetch.
//
//  A cap or media def is likewise cached only once every dim it names
//  (`dims`) is cached, at the version the manifest pins, with the value it
//  names (ensureDimsCached:owner:completion:).
//

#import "CSFabricRegistry.h"
#import "CSCharter.h"
#import "CSCapValidator.h"
#import "CSFabricManifestVersion.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSMediaUrn.h"
#import "CSDim.h"
#import <CommonCrypto/CommonDigest.h>

NSErrorDomain const CSFabricRegistryErrorDomain = @"CSFabricRegistryError";

static NSError *CSRegistryError(NSInteger code, NSString *message, NSError *_Nullable underlying) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:CSFabricRegistryErrorDomain code:code userInfo:info];
}

// The anchor of MachineFabric's production fabric, used when nothing names
// another. Only the anchor: where its objects are is read from its charter.
static NSString * const DEFAULT_FABRIC_ANCHOR = @"https://fabric.capdag.com";
static const NSTimeInterval CACHE_DURATION_HOURS = 24.0;
static const NSTimeInterval HTTP_TIMEOUT_SECONDS = 10.0;

// MARK: - CSFabricRegistryConfig

@implementation CSFabricRegistryConfig

+ (instancetype)defaultConfig {
    NSString *anchor = [[NSProcessInfo processInfo] environment][@"CDG_FABRIC_REGISTRY_URL"];
    return [self configWithAnchor:anchor.length > 0 ? anchor : DEFAULT_FABRIC_ANCHOR];
}

+ (instancetype)configWithAnchor:(NSString *)anchor {
    CSFabricRegistryConfig *config = [[CSFabricRegistryConfig alloc] init];
    config.anchor = anchor;
    return config;
}

@end

// MARK: - Alias primitives (free functions)

BOOL CSTokenIsURN(NSString *token) {
    return [token rangeOfString:@":"].location != NSNotFound;
}

BOOL CSIsAliasToken(NSString *token) {
    return !CSTokenIsURN(token);
}

NSString *_Nullable CSNormalizeAliasName(NSString *name, NSError *_Nullable *_Nullable error) {
    NSError *(^mk)(NSString *) = ^NSError *(NSString *msg) {
        return [NSError errorWithDomain:@"CSFabricRegistryError"
                                   code:1020
                               userInfo:@{NSLocalizedDescriptionKey: msg}];
    };
    if (name.length == 0) {
        if (error) *error = mk(@"alias name is empty");
        return nil;
    }
    if ([name rangeOfString:@":"].location != NSNotFound) {
        if (error) *error = mk([NSString stringWithFormat:
            @"alias name '%@' contains ':' — aliases must never look like a tagged URN", name]);
        return nil;
    }
    if ([name rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
        if (error) *error = mk([NSString stringWithFormat:@"alias name '%@' contains whitespace", name]);
        return nil;
    }
    NSString *lowered = [name lowercaseString];
    static NSCharacterSet *allowed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"abcdefghijklmnopqrstuvwxyz0123456789._-"];
    });
    NSCharacterSet *disallowed = [allowed invertedSet];
    if ([lowered rangeOfCharacterFromSet:disallowed].location != NSNotFound) {
        if (error) *error = mk([NSString stringWithFormat:
            @"alias name '%@' contains invalid characters; allowed: lowercase letters, digits, '.', '_', '-'", name]);
        return nil;
    }
    return lowered;
}

BOOL CSClassifyAliasTarget(NSString *target, CSAliasTargetKind *_Nullable outKind) {
    NSError *e = nil;
    if ([CSCapUrn fromString:target error:&e]) {
        if (outKind) *outKind = CSAliasTargetKindCap;
        return YES;
    }
    e = nil;
    if ([CSMediaUrn fromString:target error:&e]) {
        if (outKind) *outKind = CSAliasTargetKindMedia;
        return YES;
    }
    return NO;
}

// MARK: - Cache entries

@interface CSCapCacheEntry : NSObject
@property (nonatomic, strong) CSCap *definition;
@property (nonatomic) NSTimeInterval cachedAt;
@property (nonatomic) NSTimeInterval ttlHours;
- (BOOL)isExpired;
@end

@implementation CSCapCacheEntry
- (BOOL)isExpired {
    return [[NSDate date] timeIntervalSince1970] > (self.cachedAt + (self.ttlHours * 3600));
}
@end

@interface CSMediaCacheEntry : NSObject
@property (nonatomic, strong) NSDictionary *spec;
@property (nonatomic) NSTimeInterval cachedAt;
@property (nonatomic) NSTimeInterval ttlHours;
- (BOOL)isExpired;
@end

@implementation CSMediaCacheEntry
- (BOOL)isExpired {
    return [[NSDate date] timeIntervalSince1970] > (self.cachedAt + (self.ttlHours * 3600));
}
@end

// MARK: - CSFabricRegistry

@interface CSFabricRegistry ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSString *cacheDirectory;
@property (nonatomic, strong) NSString *capsCacheDirectory;
@property (nonatomic, strong) NSString *mediaCacheDirectory;
@property (nonatomic, strong) NSString *aliasesCacheDirectory;
@property (nonatomic, strong) NSString *dimsCacheDirectory;
@property (nonatomic, strong) NSString *manifestsCacheDirectory;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSCap *> *cachedCaps;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *cachedSpecs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *cachedAliases;
// Dim name → stored dim, filtered to the pinned manifest's defvers.
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSStoredDim *> *cachedDims;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *extensionIndex;
@property (nonatomic, strong) NSLock *cacheLock;
@property (nonatomic, strong, readwrite) CSFabricRegistryConfig *config;
@property (nonatomic, strong, readwrite) CSCharter *charter;
// The charter's `manifest` and `definition` templates. Its shape check
// guarantees each uses exactly the placeholders filled here, so filling one
// cannot fail, and nothing composes a fabric URL any other way.
@property (nonatomic, copy) NSString *manifestTemplate;
@property (nonatomic, copy) NSString *definitionTemplate;
// Manifest pin. >= 1 ⇒ manifest-driven; the test constructors may pin 0, where
// no manifest is consulted and there are no aliases or dims.
// The four maps are name/urn → defver, mirroring the Rust Manifest.
@property (nonatomic) uint32_t manifestVersion;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestCaps;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestMedia;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestAliases;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestDims;
@end

@implementation CSFabricRegistry

+ (NSString *)capdagCacheRoot {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [[paths firstObject] stringByAppendingPathComponent:@"capdag"];
}

+ (CSCharter *)publisherLayoutCharterForAnchor:(NSString *)anchor slug:(NSString *)slug {
    NSError *error = nil;
    CSCharter *charter = [CSCharter charterWithDictionary:@{
        @"format": CSCharterFormat,
        @"anchor": anchor,
        @"kind": CSRegistryKindName(CSRegistryKindFabric),
        @"slug": slug,
        @"environment": @"prod",
        @"locations": @{
            @"manifest": [anchor stringByAppendingString:@"/manifest/{manifest_version}.json"],
            @"latest": [anchor stringByAppendingString:@"/manifest/latest.json"],
            @"definition": [anchor stringByAppendingString:@"/{kind}/{urn_hash}/{version}.json"],
        },
        @"issued_at": @0,
        @"not_after": [NSNull null],
    } error:&error];
    if (!charter) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"the publisher-layout charter has a charter's fields: %@", error.localizedDescription];
    }
    return charter;
}

+ (nullable CSCharter *)resolveCharterForAnchor:(NSString *)anchor
                                      cacheRoot:(NSString *)cacheRoot
                                        session:(NSURLSession *)session
                                          error:(NSError **)error {
    CSCharter *stored = [CSCharter storedUnder:cacheRoot forAnchor:anchor kind:CSRegistryKindFabric folder:nil];
    if (stored) return stored;
    CSFetchedCharter *fetched = [CSFetchedCharter fetchFromAnchor:anchor kind:CSRegistryKindFabric session:session error:error];
    if (!fetched) return nil;
    NSString *folder = [cacheRoot stringByAppendingPathComponent:fetched.charter.slug];
    NSError *storeError = nil;
    if (![fetched storeInFolder:folder error:&storeError]) {
        if (error) *error = CSRegistryError(1061, [NSString stringWithFormat:@"Failed to store the charter of %@ in %@: %@",
                                                   anchor, folder, storeError.localizedDescription], storeError);
        return nil;
    }
    return fetched.charter;
}

+ (NSURLSession *)registrySession {
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = HTTP_TIMEOUT_SECONDS;
    sessionConfig.timeoutIntervalForResource = HTTP_TIMEOUT_SECONDS;
    return [NSURLSession sessionWithConfiguration:sessionConfig];
}

- (instancetype)init {
    return [self initWithConfig:[CSFabricRegistryConfig defaultConfig]];
}

- (instancetype)initWithAnchor:(NSString *)anchor {
    return [self initWithConfig:[CSFabricRegistryConfig configWithAnchor:anchor]];
}

- (instancetype)initWithConfig:(CSFabricRegistryConfig *)config {
    // The production path: resolve the registry's charter, then pin at the
    // baked manifest version and bootstrap the manifest from disk/network.
    // Mirrors Rust with_config (which delegates to
    // with_config_and_manifest_version at the baked version).
    NSError *error = nil;
    CSCharter *charter = [[self class] resolveCharterForAnchor:config.anchor
                                                     cacheRoot:[[self class] capdagCacheRoot]
                                                       session:[[self class] registrySession]
                                                         error:&error];
    if (!charter) {
        [NSException raise:@"CSFabricRegistryCharterUnavailable"
                    format:@"the fabric registry %@ has no charter this client can use: %@",
                           config.anchor, error.localizedDescription];
    }
    return [self initWithCharter:charter
                          config:config
                 manifestVersion:CSBakedFabricManifestVersion
            bootstrapFromNetwork:YES];
}

// Designated initializer, over a charter already resolved. Everything is read
// from it: the cache folder is its slug, and the manifest and definitions are
// where its locations say. `bootstrapFromNetwork == YES` mirrors Rust's
// `with_config_and_manifest_version`: it loads the pinned manifest from the
// local cache, else blocks on a network fetch, and fails hard if neither can
// supply it. `bootstrapFromNetwork == NO` mirrors Rust's `new_for_test_*`: an
// EMPTY manifest pinned at the requested version, no network, so test helpers
// populate the manifest maps as they insert caps/media/aliases.
- (instancetype)initWithCharter:(CSCharter *)charter
                         config:(CSFabricRegistryConfig *)config
                manifestVersion:(uint32_t)manifestVersion
           bootstrapFromNetwork:(BOOL)bootstrapFromNetwork {
    self = [super init];
    if (self) {
        _config = config;
        _charter = charter;
        if (charter.kind != CSRegistryKindFabric) {
            [NSException raise:@"CSFabricRegistryCharterUnavailable"
                        format:@"%@ is chartered as a %@ registry, not a fabric",
                               charter.anchor, CSRegistryKindName(charter.kind)];
        }
        for (NSString *name in @[@"manifest", @"definition"]) {
            if (charter.locations[name] == nil) {
                [NSException raise:@"CSFabricRegistryCharterUnavailable"
                            format:@"the fabric charter of %@ declares no '%@' location", charter.anchor, name];
            }
        }
        _manifestTemplate = [charter.locations[@"manifest"] copy];
        _definitionTemplate = [charter.locations[@"definition"] copy];
        _session = [[self class] registrySession];

        // The cache folder is the charter's slug. Prod and staging serve
        // different bytes for the same URN/version; two registries have two
        // charters and two slugs, so a prod-populated cache can never satisfy a
        // staging lookup. The caps/ and media/ subdirs derive from it.
        _cacheDirectory = [[[self class] capdagCacheRoot] stringByAppendingPathComponent:charter.slug];
        _capsCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"caps"];
        _mediaCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"media"];
        _aliasesCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"aliases"];
        _dimsCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"dims"];
        _manifestsCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"manifests"];

        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:_capsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:_mediaCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:_aliasesCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:_dimsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:_manifestsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];

        _cachedCaps = [[NSMutableDictionary alloc] init];
        _cachedSpecs = [[NSMutableDictionary alloc] init];
        _cachedAliases = [[NSMutableDictionary alloc] init];
        _cachedDims = [[NSMutableDictionary alloc] init];
        _extensionIndex = [[NSMutableDictionary alloc] init];
        _cacheLock = [[NSLock alloc] init];

        // Manifest pin. The production path passes CSBakedFabricManifestVersion
        // (CSFabricManifestVersion.m, regenerated by scripts/lib/config.sh from
        // fabric/manifest-version.txt) — the ObjC analogue of Rust's
        // compile-time FABRIC_MANIFEST_VERSION. We do NOT read
        // MFR_FABRIC_MANIFEST_VERSION from the process environment and do NOT
        // fall back to v0: a process that happened to lack the env var (e.g. the
        // app's UI process) silently degraded to legacy flat-path lookups that
        // 404 every versioned cap/media def. A baked value < 1 is a hard failure
        // here, mirroring build.rs's refusal to build below v1.
        if (CSBakedFabricManifestVersion < 1) {
            [NSException raise:@"CSFabricRegistryManifestVersionInvalid"
                        format:@"CSBakedFabricManifestVersion is %u; it must be >= 1. v0 is the implicit pre-versioning state and is never a valid target (see capdag/build.rs and scripts/lib/config.sh).",
                               CSBakedFabricManifestVersion];
        }
        _manifestVersion = manifestVersion;
        _manifestCaps = [[NSMutableDictionary alloc] init];
        _manifestMedia = [[NSMutableDictionary alloc] init];
        _manifestAliases = [[NSMutableDictionary alloc] init];
        _manifestDims = [[NSMutableDictionary alloc] init];

        // Bootstrap the manifest BEFORE hydrating the on-disk caches, mirroring
        // Rust with_config_and_manifest_version: the manifest's per-URN defvers
        // are what the cache loaders are filtered against and what every fetch
        // resolves a path from. At v >= 1 this BLOCKS on a network round-trip to
        // fetch `manifest/<N>.json` if no local cache copy exists (exactly the
        // reference's behaviour), and FAILS HARD if neither disk nor network can
        // produce it — there is no v0 fallback. The faithful mirror of Rust's
        // async constructor that `.await`s load_or_fetch_manifest before
        // returning Self. The test path (bootstrapFromNetwork == NO) leaves the
        // manifest maps empty — mirroring Rust's Manifest::empty(version).
        if (bootstrapFromNetwork) {
            [self bootstrapManifest];
        }

        [self loadAllCachedCaps];
        [self loadAllCachedMediaDefs];
        [self loadAllCachedAliases];
        [self loadAllCachedDims];
        // Filter the loaded caches to the pinned manifest's defvers (v >= 1):
        // only retain a cached entry whose own version matches the defver the
        // manifest pins its URN at. A v0-flat or stale-version blob left on disk
        // from a different snapshot must never satisfy a v >= 1 lookup. Then
        // keep a cap or media def only when every dim it names survived. Mirrors
        // retain_pinned in Rust's constructor.
        [self filterCachesToManifest];
    }
    return self;
}

/// Test constructor: an empty registry pinned at manifest v1, so test helpers
/// (insertCachedCapForTest:/insertCachedAliasForTest:/addMediaDef:) flow into
/// the manifest at their declared version — mirrors Rust new_for_test, which
/// builds Manifest::empty(1) and never touches the network.
- (instancetype)initForTest {
    CSFabricRegistryConfig *config = [CSFabricRegistryConfig defaultConfig];
    return [self initWithCharter:[[self class] publisherLayoutCharterForAnchor:config.anchor slug:@"test-fabric"]
                          config:config
                 manifestVersion:1
            bootstrapFromNetwork:NO];
}

// MARK: - URN normalization helpers

// URN normalisation no longer falls back to the raw input on a parse failure.
// A malformed URN returns nil and (when an error-out is supplied) populates an
// NSError. Callers MUST decide: propagate the error (resolution paths with an
// error/completion channel), log+nil (nullable cache lookups), or log+skip
// (void mutator/loader loops). A non-canonical/garbage string must NEVER reach
// a cache or manifest key. Mirrors Rust normalize_cap_urn/normalize_media_urn.

- (nullable NSString *)normalizeCapUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error {
    NSError *parseError = nil;
    CSCapUrn *parsed = [CSCapUrn fromString:urn error:&parseError];
    if (!parsed) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1030
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"malformed cap URN '%@': %@", urn, parseError.localizedDescription ?: @"parse failed"]}];
        }
        return nil;
    }
    return [parsed toString];
}

- (nullable NSString *)normalizeMediaUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error {
    NSError *parseError = nil;
    CSMediaUrn *parsed = [CSMediaUrn fromString:urn error:&parseError];
    if (!parsed) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1031
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"malformed media URN '%@': %@", urn, parseError.localizedDescription ?: @"parse failed"]}];
        }
        return nil;
    }
    return [parsed toString];
}

- (NSString *)sha256HexForString:(NSString *)s {
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [out appendFormat:@"%02x", digest[i]];
    }
    return out;
}

- (NSString *)normalizeExtension:(NSString *)extension {
    NSString *ext = [extension lowercaseString];
    if ([ext hasPrefix:@"."]) {
        ext = [ext substringFromIndex:1];
    }
    return ext;
}

// MARK: - Manifest bootstrap

// Load the pinned manifest BEFORE any cache hydrate or fetch. Tries the local
// cache (`manifests/<N>.json`) first, then BLOCKS on a network GET. If neither
// produces a parseable manifest at the pinned version this raises — there is no
// v0 fallback (the caller pinned v >= 1 by baking it in). Exact behavioural
// mirror of Rust load_or_fetch_manifest + the constructor that .awaits it.
- (void)bootstrapManifest {
    NSString *cacheFile = [self.manifestsCacheDirectory
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%u.json", self.manifestVersion]];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSData *body = nil;
    if ([fm fileExistsAtPath:cacheFile]) {
        NSData *cached = [NSData dataWithContentsOfFile:cacheFile];
        if (cached) {
            NSError *parseErr = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:cached options:0 error:&parseErr];
            uint32_t cachedVersion = [json isKindOfClass:[NSDictionary class]]
                ? (uint32_t)[json[@"version"] unsignedIntValue] : 0;
            NSError *ingestErr = nil;
            if ([json isKindOfClass:[NSDictionary class]] && cachedVersion == self.manifestVersion
                && [self ingestManifestDictionary:json error:&ingestErr]) {
                return;
            }
            // A cached manifest whose version disagrees with the file name (or
            // that no longer parses, or is not a manifest this library reads)
            // is corrupt; drop it and re-fetch from the network rather than
            // trusting the wrong snapshot.
            NSLog(@"[CSFabricRegistry] cached manifest at %@ did not parse, reported version %u (expected %u) or was refused (%@); re-fetching",
                  cacheFile, cachedVersion, self.manifestVersion, ingestErr.localizedDescription ?: @"-");
            [fm removeItemAtPath:cacheFile error:nil];
        }
    }

    NSString *urlString = [self.manifestTemplate
        stringByReplacingOccurrencesOfString:@"{manifest_version}"
                                  withString:[NSString stringWithFormat:@"%u", self.manifestVersion]];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Manifest v%u URL is malformed: %@", self.manifestVersion, urlString];
    }

    // Synchronous fetch: the reference constructor blocks on the manifest round
    // trip before the registry is usable, so the ObjC init blocks the same way.
    __block NSData *fetched = nil;
    __block NSURLResponse *response = nil;
    __block NSError *netError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        fetched = data;
        response = resp;
        netError = error;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    if (netError) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Failed to fetch manifest v%u at %@: %@",
                           self.manifestVersion, urlString, netError.localizedDescription];
    }
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    if (http.statusCode != 200) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Manifest v%u not found in registry (HTTP %ld) at %@",
                           self.manifestVersion, (long)http.statusCode, urlString];
    }
    body = fetched;

    NSError *parseErr = nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseErr];
    if (![manifest isKindOfClass:[NSDictionary class]]) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Failed to parse manifest v%u: %@",
                           self.manifestVersion, parseErr.localizedDescription ?: @"not a JSON object"];
    }
    uint32_t fetchedVersion = (uint32_t)[manifest[@"version"] unsignedIntValue];
    if (fetchedVersion != self.manifestVersion) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Manifest fetched as v%u reports version %u",
                           self.manifestVersion, fetchedVersion];
    }

    NSError *ingestErr = nil;
    if (![self ingestManifestDictionary:manifest error:&ingestErr]) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Manifest v%u at %@ is refused: %@",
                           self.manifestVersion, urlString, ingestErr.localizedDescription];
    }
    [body writeToFile:cacheFile atomically:YES];
}

// Replace the in-memory manifest maps with the snapshot's `caps`/`media`/
// `aliases`/`dims` URN→defver mappings. The published manifest is the single
// source of truth for which URNs belong to the snapshot and at which defver each
// resolves. `dims` is required: a manifest without it is not one this library
// reads, and is refused (NO + *error) without touching the maps.
- (BOOL)ingestManifestDictionary:(NSDictionary *)manifest error:(NSError *_Nullable *_Nullable)error {
    NSDictionary *caps = manifest[@"caps"];
    NSDictionary *media = manifest[@"media"];
    NSDictionary *aliases = manifest[@"aliases"];
    id dims = manifest[@"dims"];
    if (![dims isKindOfClass:[NSDictionary class]]) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorManifestInvalid, [NSString stringWithFormat:
            @"manifest v%@ %@ 'dims' map (dim name -> defver); every manifest names the dims of its snapshot",
            manifest[@"version"], dims ? @"has a malformed" : @"has no"], nil);
        return NO;
    }
    for (id name in (NSDictionary *)dims) {
        id defver = ((NSDictionary *)dims)[name];
        if (![name isKindOfClass:[NSString class]] || ![defver isKindOfClass:[NSNumber class]]) {
            if (error) *error = CSRegistryError(CSFabricRegistryErrorManifestInvalid, [NSString stringWithFormat:
                @"manifest v%@ 'dims' entry '%@' is not a dim name mapped to a defver", manifest[@"version"], name], nil);
            return NO;
        }
    }
    [self.cacheLock lock];
    [self.manifestCaps removeAllObjects];
    [self.manifestMedia removeAllObjects];
    [self.manifestAliases removeAllObjects];
    [self.manifestDims removeAllObjects];
    [self.manifestDims addEntriesFromDictionary:dims];
    if ([caps isKindOfClass:[NSDictionary class]]) {
        [self.manifestCaps addEntriesFromDictionary:caps];
    }
    if ([media isKindOfClass:[NSDictionary class]]) {
        [self.manifestMedia addEntriesFromDictionary:media];
    }
    if ([aliases isKindOfClass:[NSDictionary class]]) {
        [self.manifestAliases addEntriesFromDictionary:aliases];
    }
    [self.cacheLock unlock];
    return YES;
}

// After hydrating the on-disk caches, drop any entry whose version does NOT
// match the defver the manifest pins its URN at — a stale-snapshot or v0-flat
// blob must never satisfy a v >= 1 lookup. At v0 the manifest is empty and the
// alias and dim caches are cleared (aliases and dims are versioned-regime
// concepts). Then keep a cap or media def only when every dim it names
// survived with the value it names: one whose dims did not is dropped here and
// fetched again, with its dims, when it is next asked for — so a cached
// definition always has its dims cached. Mirrors Rust retain_pinned.
- (void)filterCachesToManifest {
    [self.cacheLock lock];
    if (self.manifestVersion >= 1) {
        NSArray<NSString *> *capKeys = [self.cachedCaps allKeys];
        for (NSString *urn in capKeys) {
            CSCap *cap = self.cachedCaps[urn];
            uint32_t pinned = (uint32_t)[self.manifestCaps[urn] unsignedIntValue];
            if (pinned != cap.version) {
                [self.cachedCaps removeObjectForKey:urn];
            }
        }
        NSArray<NSString *> *specKeys = [self.cachedSpecs allKeys];
        for (NSString *urn in specKeys) {
            NSDictionary *spec = self.cachedSpecs[urn];
            uint32_t specVersion = (uint32_t)[spec[@"version"] unsignedIntValue];
            uint32_t pinned = (uint32_t)[self.manifestMedia[urn] unsignedIntValue];
            if (pinned != specVersion) {
                [self.cachedSpecs removeObjectForKey:urn];
            }
        }
        NSArray<NSString *> *aliasKeys = [self.cachedAliases allKeys];
        for (NSString *name in aliasKeys) {
            NSDictionary *alias = self.cachedAliases[name];
            uint32_t aliasVersion = (uint32_t)[alias[@"version"] unsignedIntValue];
            uint32_t pinned = (uint32_t)[self.manifestAliases[name] unsignedIntValue];
            if (pinned != aliasVersion) {
                [self.cachedAliases removeObjectForKey:name];
            }
        }
        for (NSString *name in [self.cachedDims allKeys]) {
            uint32_t pinned = (uint32_t)[self.manifestDims[name] unsignedIntValue];
            if (pinned != self.cachedDims[name].version) {
                [self.cachedDims removeObjectForKey:name];
            }
        }
    } else {
        // v0: aliases and dims never exist on the flat path.
        [self.cachedAliases removeAllObjects];
        [self.cachedDims removeAllObjects];
    }
    for (NSString *urn in [self.cachedCaps allKeys]) {
        if (![self dimRefs:self.cachedCaps[urn].dims resolveIn:self.cachedDims]) {
            [self.cachedCaps removeObjectForKey:urn];
        }
    }
    for (NSString *urn in [self.cachedSpecs allKeys]) {
        NSArray<CSDimRef *> *refs = [CSDimRef refsFromField:self.cachedSpecs[urn][@"dims"]
                                                       owner:[NSString stringWithFormat:@"media def '%@'", urn]
                                                       error:nil];
        if (!refs || ![self dimRefs:refs resolveIn:self.cachedDims]) {
            [self.cachedSpecs removeObjectForKey:urn];
        }
    }
    // The extension index is derived from cachedSpecs; rebuild it so it
    // reflects only the retained specs.
    [self.extensionIndex removeAllObjects];
    NSArray<NSDictionary *> *retainedSpecs = [self.cachedSpecs allValues];
    [self.cacheLock unlock];
    for (NSDictionary *spec in retainedSpecs) {
        [self indexExtensionsForSpec:spec urn:spec[@"urn"]];
    }
}

// Whether every dim `refs` names is in `cached` with the value it names.
// Mirrors Rust dims_resolve_in.
- (BOOL)dimRefs:(NSArray<CSDimRef *> *)refs resolveIn:(NSDictionary<NSString *, CSStoredDim *> *)cached {
    for (CSDimRef *ref in refs) {
        CSStoredDim *dim = cached[ref.dim];
        if (!dim || ![dim valueNamed:ref.value]) return NO;
    }
    return YES;
}

// MARK: - Defver resolution (manifest pin)

// Resolve a normalized cap URN to its defver under the pinned manifest. At v0 →
// 0 (flat path). At v >= 1 the URN MUST be in the manifest's caps map; absence
// is a hard NotFound (no fallback to flat paths, which would 404 against a
// versioned registry and mix snapshot versions). Mirrors Rust cap_defver.
- (BOOL)capDefver:(uint32_t *)outDefver
    forNormalized:(NSString *)normalizedUrn
            error:(NSError *_Nullable *_Nullable)error {
    if (self.manifestVersion == 0) {
        *outDefver = 0;
        return YES;
    }
    [self.cacheLock lock];
    NSNumber *defver = self.manifestCaps[normalizedUrn];
    uint32_t mv = self.manifestVersion;
    [self.cacheLock unlock];
    if (!defver) {
        if (error) *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1040
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"cap '%@' is not part of manifest v%u", normalizedUrn, mv]}];
        return NO;
    }
    *outDefver = (uint32_t)[defver unsignedIntValue];
    return YES;
}

// Resolve a normalized media URN to its defver. Same rules as capDefver. The
// bare `media:` wildcard is a sentinel with no published spec, so it resolves
// to 0 (the fetch path special-cases it and never reaches a request for it).
// Mirrors Rust media_defver.
- (BOOL)mediaDefver:(uint32_t *)outDefver
      forNormalized:(NSString *)normalizedUrn
              error:(NSError *_Nullable *_Nullable)error {
    if (self.manifestVersion == 0) {
        *outDefver = 0;
        return YES;
    }
    if ([normalizedUrn isEqualToString:@"media:"]) {
        *outDefver = 0;
        return YES;
    }
    [self.cacheLock lock];
    NSNumber *defver = self.manifestMedia[normalizedUrn];
    uint32_t mv = self.manifestVersion;
    [self.cacheLock unlock];
    if (!defver) {
        if (error) *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1041
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"media def '%@' is not part of manifest v%u", normalizedUrn, mv]}];
        return NO;
    }
    *outDefver = (uint32_t)[defver unsignedIntValue];
    return YES;
}

// Public defver-resolution surface (normalize-then-resolve), mirroring Rust
// cap_defver_for / media_defver_for. A malformed URN is a hard error; a URN
// outside the snapshot is a hard NotFound.
- (BOOL)capDefverFor:(NSString *)urn
              defver:(uint32_t *)outDefver
               error:(NSError *_Nullable *_Nullable)error {
    NSString *normalized = [self normalizeCapUrn:urn error:error];
    if (!normalized) return NO;
    return [self capDefver:outDefver forNormalized:normalized error:error];
}

- (BOOL)mediaDefverFor:(NSString *)urn
                defver:(uint32_t *)outDefver
                 error:(NSError *_Nullable *_Nullable)error {
    NSString *normalized = [self normalizeMediaUrn:urn error:error];
    if (!normalized) return NO;
    return [self mediaDefver:outDefver forNormalized:normalized error:error];
}

// MARK: - Object-path construction

// The registry URL of one definition at the given defver, from the charter's
// `definition` location: `kind` is caps, media, aliases or dims. Exact mirror
// of the URL half of Rust cap_url_and_cache_path/media_url_and_cache_path.
- (NSString *)objectURLForKind:(NSString *)kind digest:(NSString *)digest defver:(uint32_t)defver {
    NSString *url = [self.definitionTemplate stringByReplacingOccurrencesOfString:@"{kind}" withString:kind];
    url = [url stringByReplacingOccurrencesOfString:@"{urn_hash}" withString:digest];
    return [url stringByReplacingOccurrencesOfString:@"{version}"
                                          withString:[NSString stringWithFormat:@"%u", defver]];
}

// The on-disk cache file of a definition: `<dir>/<sha>/<defver>.json`.
// Mirrors the cache-path half of the Rust helpers.
- (NSString *)cacheFileInDir:(NSString *)dir digest:(NSString *)digest defver:(uint32_t)defver {
    NSString *subdir = [dir stringByAppendingPathComponent:digest];
    [[NSFileManager defaultManager] createDirectoryAtPath:subdir withIntermediateDirectories:YES attributes:nil error:nil];
    return [subdir stringByAppendingPathComponent:[NSString stringWithFormat:@"%u.json", defver]];
}

// MARK: - Public cap surface

- (void)getCapWithUrn:(NSString *)urn
           completion:(void (^)(CSCap *_Nullable cap, NSError *_Nullable error))completion {
    // An alias (a colon-free token) is resolved first; because this is the
    // typed cap boundary, an alias whose target is not a cap URN is a hard
    // error.
    if (CSIsAliasToken(urn)) {
        [self resolveAliasTyped:urn expected:CSAliasTargetKindCap completion:^(NSString *target, NSError *error) {
            if (error) { completion(nil, error); return; }
            [self getCapWithUrn:target completion:completion];
        }];
        return;
    }

    NSError *normError = nil;
    NSString *normalized = [self normalizeCapUrn:urn error:&normError];
    if (!normalized) {
        completion(nil, normError);
        return;
    }

    [self.cacheLock lock];
    CSCap *cached = self.cachedCaps[normalized];
    [self.cacheLock unlock];

    if (cached) {
        completion(cached, nil);
        return;
    }

    [self fetchCapAtomic:urn completion:completion];
}

- (void)getCapsWithUrns:(NSArray<NSString *> *)urns
             completion:(void (^)(NSArray<CSCap *> *_Nullable caps, NSError *_Nullable error))completion {
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<CSCap *> *caps = [NSMutableArray array];
    __block NSError *firstError = nil;

    for (NSString *urn in urns) {
        dispatch_group_enter(group);
        [self getCapWithUrn:urn completion:^(CSCap *cap, NSError *error) {
            if (error && !firstError) {
                firstError = error;
            } else if (cap) {
                @synchronized (caps) {
                    [caps addObject:cap];
                }
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (firstError) {
            completion(nil, firstError);
        } else {
            completion([caps copy], nil);
        }
    });
}

- (void)validateCap:(CSCap *)cap completion:(void (^)(NSError *error))completion {
    NSString *urn = [cap.capUrn toString];
    [self getCapWithUrn:urn completion:^(CSCap *canonicalCap, NSError *error) {
        if (error) { completion(error); return; }

        // A cartridge responds to a SUBSET of the fabric cap's aliases (never
        // an alias the fabric does not define).
        NSSet<NSString *> *canonicalAliasSet = [NSSet setWithArray:canonicalCap.aliases];
        for (NSString *a in cap.aliases) {
            if (![canonicalAliasSet containsObject:a]) {
                completion([NSError errorWithDomain:@"CSFabricRegistryError"
                                               code:1003
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                          [NSString stringWithFormat:@"Alias mismatch: '%@' not among the fabric cap's aliases %@",
                                                           a, canonicalCap.aliases]}]);
                return;
            }
        }
        if (cap.isAbstract != canonicalCap.isAbstract) {
            completion([NSError errorWithDomain:@"CSFabricRegistryError"
                                           code:1003
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                      [NSString stringWithFormat:@"Abstract-flag mismatch. Local: %d, Canonical: %d",
                                                       cap.isAbstract, canonicalCap.isAbstract]}]);
            return;
        }

        NSString *capStdin = [cap getStdinMediaUrn];
        NSString *canonStdin = [canonicalCap getStdinMediaUrn];
        BOOL stdinMatches = (capStdin == nil && canonStdin == nil) ||
                            (capStdin != nil && canonStdin != nil && [capStdin isEqualToString:canonStdin]);
        if (!stdinMatches) {
            completion([NSError errorWithDomain:@"CSFabricRegistryError"
                                           code:1004
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                      [NSString stringWithFormat:@"stdin mismatch. Local: %@, Canonical: %@",
                                                       capStdin ?: @"(none)", canonStdin ?: @"(none)"]}]);
            return;
        }

        completion(nil);
    }];
}

- (NSArray<CSCap *> *)getCachedCaps {
    [self.cacheLock lock];
    NSArray<CSCap *> *caps = [self.cachedCaps allValues];
    [self.cacheLock unlock];
    return caps;
}

- (void)getCachedCaps:(void (^)(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error))completion {
    completion([self getCachedCaps], nil);
}

- (BOOL)capExists:(NSString *)urn {
    NSError *normError = nil;
    NSString *normalized = [self normalizeCapUrn:urn error:&normError];
    if (!normalized) {
        NSLog(@"[CSFabricRegistry] capExists: malformed cap URN treated as not-present: %@", normError.localizedDescription);
        return NO;
    }
    [self.cacheLock lock];
    BOOL exists = (self.cachedCaps[normalized] != nil);
    [self.cacheLock unlock];
    return exists;
}

// MARK: - Public media-def surface

- (void)getMediaDef:(NSString *)urn
          completion:(void (^)(NSDictionary * _Nullable spec, NSError * _Nullable error))completion {
    // An alias (a colon-free token) is resolved first; because this is the
    // typed media boundary, an alias whose target is not a media URN is a
    // hard error.
    if (CSIsAliasToken(urn)) {
        [self resolveAliasTyped:urn expected:CSAliasTargetKindMedia completion:^(NSString *target, NSError *error) {
            if (error) { completion(nil, error); return; }
            [self getMediaDef:target completion:completion];
        }];
        return;
    }

    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:urn error:&normError];
    if (!normalized) {
        completion(nil, normError);
        return;
    }

    [self.cacheLock lock];
    NSDictionary *cached = self.cachedSpecs[normalized];
    [self.cacheLock unlock];

    if (cached) {
        completion(cached, nil);
        return;
    }

    [self fetchMediaDefAtomic:urn completion:completion];
}

- (NSDictionary *)getCachedMediaDef:(NSString *)urn {
    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:urn error:&normError];
    if (!normalized) {
        NSLog(@"[CSFabricRegistry] getCachedMediaDef: malformed media URN treated as not-found: %@", normError.localizedDescription);
        return nil;
    }
    [self.cacheLock lock];
    NSDictionary *spec = self.cachedSpecs[normalized];
    [self.cacheLock unlock];
    return spec;
}

// Seed a media def directly (test/local hydrate, e.g. from a cartridge
// manifest). Unlike the fetch path this REGISTERS the def in the manifest map at
// its declared version (stamping a version-0 spec to the pinned manifest
// version), so subsequent lookups resolve its defver without a network round
// trip. Mirrors Rust insert_cached_media_def_for_test.
- (void)addMediaDef:(NSDictionary *)spec {
    NSString *rawUrn = spec[@"urn"];
    if (![rawUrn isKindOfClass:[NSString class]] || rawUrn.length == 0) {
        return;
    }
    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:rawUrn error:&normError];
    if (!normalized) {
        NSLog(@"[CSFabricRegistry] addMediaDef: skipping spec with malformed media URN '%@': %@",
              rawUrn, normError.localizedDescription);
        return;
    }
    uint32_t specVersion = 0;
    NSNumber *v = spec[@"version"];
    if ([v isKindOfClass:[NSNumber class]]) {
        specVersion = (uint32_t)[v unsignedIntValue];
    }
    if (specVersion == 0 && self.manifestVersion >= 1) {
        specVersion = self.manifestVersion;
        NSMutableDictionary *stamped = [spec mutableCopy];
        stamped[@"version"] = @(specVersion);
        spec = [stamped copy];
    }
    [self insertMediaDefInMemory:spec];
    if (self.manifestVersion >= 1) {
        [self.cacheLock lock];
        self.manifestMedia[normalized] = @(specVersion);
        [self.cacheLock unlock];
    }
}

- (NSArray<NSString *> *)mediaUrnsForExtension:(NSString *)extension {
    NSString *ext = [self normalizeExtension:extension];
    [self.cacheLock lock];
    NSArray<NSString *> *urns = self.extensionIndex[ext];
    NSArray<NSString *> *snapshot = urns ? [urns copy] : @[];
    [self.cacheLock unlock];
    return snapshot;
}

- (NSString *)primaryMediaUrnForExtension:(NSString *)extension {
    return [self mediaUrnsForExtension:extension].firstObject;
}

- (BOOL)hasExtension:(NSString *)extension {
    NSString *ext = [self normalizeExtension:extension];
    [self.cacheLock lock];
    BOOL has = self.extensionIndex[ext] != nil;
    [self.cacheLock unlock];
    return has;
}

- (NSArray<NSString *> *)allExtensions {
    [self.cacheLock lock];
    NSArray<NSString *> *exts = [self.extensionIndex allKeys];
    [self.cacheLock unlock];
    return exts;
}

// MARK: - Cache lifecycle

- (void)clearCache {
    [self.cacheLock lock];
    [self.cachedCaps removeAllObjects];
    [self.cachedSpecs removeAllObjects];
    [self.cachedAliases removeAllObjects];
    [self.cachedDims removeAllObjects];
    [self.extensionIndex removeAllObjects];
    [self.cacheLock unlock];

    NSFileManager *fm = [NSFileManager defaultManager];
    // Clear the per-object caches (caps/media/aliases/dims) but PRESERVE the manifest
    // cache: the registry stays pinned and usable after a clear, and re-fetching
    // every object lazily must still resolve defvers from the same snapshot. The
    // in-memory manifest maps are likewise left intact (cleared only by a new
    // construction). Recreate the per-object dirs so subsequent writes succeed.
    [fm removeItemAtPath:self.capsCacheDirectory error:nil];
    [fm removeItemAtPath:self.mediaCacheDirectory error:nil];
    [fm removeItemAtPath:self.aliasesCacheDirectory error:nil];
    [fm removeItemAtPath:self.dimsCacheDirectory error:nil];
    [fm createDirectoryAtPath:self.capsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:self.mediaCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:self.aliasesCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:self.dimsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:self.manifestsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
}

// MARK: - Atomic cap fetch

/// Walk every media URN a cap definition references (in_spec, out_spec,
/// each arg.media_urn, each stdin source, output.media_urn). Skip the
/// bare `media:` wildcard. Order is deterministic and de-duplicated.
- (NSArray<NSString *> *)collectReferencedMediaUrnsForCap:(CSCap *)cap {
    NSMutableArray<NSString *> *seen = [NSMutableArray array];
    void (^push)(NSString *) = ^(NSString *urn) {
        if (urn.length == 0) return;
        NSError *err = nil;
        CSMediaUrn *parsed = [CSMediaUrn fromString:urn error:&err];
        if (!parsed) return;
        if ([parsed isTop]) return; // bare media: wildcard
        NSString *normalized = [parsed toString];
        if (![seen containsObject:normalized]) {
            [seen addObject:normalized];
        }
    };

    push([cap.capUrn inSpec]);
    push([cap.capUrn outSpec]);
    for (CSCapArg *arg in cap.args) {
        push(arg.mediaUrn);
        // What the arg accepts: its stdin source's URN, or its `accepts`.
        push([arg acceptedUrn]);
    }
    for (CSCapOutput *output in cap.outputs) {
        push(output.mediaUrn);
    }
    return seen;
}

- (void)fetchCapAtomic:(NSString *)urn
            completion:(void (^)(CSCap *_Nullable cap, NSError *_Nullable error))completion {
    [self fetchCapFromRegistry:urn completion:^(CSCap *cap, NSError *error) {
        if (!cap) {
            completion(nil, error);
            return;
        }

        NSArray<NSString *> *referenced = [self collectReferencedMediaUrnsForCap:cap];
        [self ensureMediaDefsCached:referenced
                          forCapUrn:urn
                         completion:^(NSError *mediaError) {
            if (mediaError) {
                // Atomic: every referenced media URN must land before
                // the cap is cached. Failure leaves the cap out of both
                // in-memory and on-disk caches.
                completion(nil, mediaError);
                return;
            }
            NSError *normError = nil;
            NSString *normalized = [self normalizeCapUrn:[cap.capUrn toString] error:&normError];
            if (!normalized) {
                completion(nil, normError);
                return;
            }
            // Every dim the cap names, at its pinned version, with the value
            // named.
            [self ensureDimsCached:cap.dims
                             owner:[NSString stringWithFormat:@"cap '%@'", normalized]
                        completion:^(NSError *dimError) {
                if (dimError) {
                    completion(nil, dimError);
                    return;
                }
                // All referenced media defs and dims in cache. Write the cap.
                [self saveCapToCache:cap];
                [self.cacheLock lock];
                self.cachedCaps[normalized] = cap;
                [self.cacheLock unlock];
                completion(cap, nil);
            }];
        }];
    }];
}

// Atomic media-def fetch: the media def is cached only once every dim it names
// is cached (ensureDimsCached:owner:completion:). A `dims` entry this capdag
// cannot hold refuses the body. Mirrors Rust fetch_one_media_def.
- (void)fetchMediaDefAtomic:(NSString *)urn
                 completion:(void (^)(NSDictionary *_Nullable spec, NSError *_Nullable error))completion {
    [self fetchMediaDefFromRegistry:urn completion:^(NSDictionary *spec, NSError *error) {
        if (!spec) {
            completion(nil, error);
            return;
        }
        NSString *owner = [NSString stringWithFormat:@"media def '%@'", [self normalizeMediaUrn:urn error:nil] ?: urn];
        NSError *dimsError = nil;
        NSArray<CSDimRef *> *dims = [CSDimRef refsFromField:spec[@"dims"] owner:owner error:&dimsError];
        if (!dims) {
            completion(nil, CSRegistryError(1001, [NSString stringWithFormat:
                @"Failed to parse registry response for %@: %@", owner, dimsError.localizedDescription], dimsError));
            return;
        }
        [self ensureDimsCached:dims owner:owner completion:^(NSError *dimError) {
            if (dimError) {
                completion(nil, dimError);
                return;
            }
            [self saveMediaDefToCache:spec];
            [self insertMediaDefInMemory:spec];
            completion(spec, nil);
        }];
    }];
}

- (void)ensureMediaDefsCached:(NSArray<NSString *> *)urns
                     forCapUrn:(NSString *)capUrn
                    completion:(void (^)(NSError * _Nullable error))completion {
    if (urns.count == 0) {
        completion(nil);
        return;
    }
    __block NSUInteger remaining = urns.count;
    __block NSError *firstError = nil;
    __block NSString *firstFailingUrn = nil;
    NSObject *guard = [[NSObject alloc] init];

    for (NSString *mediaUrn in urns) {
        [self.cacheLock lock];
        BOOL alreadyCached = (self.cachedSpecs[mediaUrn] != nil);
        [self.cacheLock unlock];

        if (alreadyCached) {
            @synchronized (guard) {
                if (--remaining == 0) {
                    completion(firstError);
                }
            }
            continue;
        }

        [self fetchMediaDefAtomic:mediaUrn completion:^(NSDictionary *spec, NSError *error) {
            @synchronized (guard) {
                if (error && !firstError) {
                    firstError = error;
                    firstFailingUrn = mediaUrn;
                }
                if (--remaining == 0) {
                    if (firstError) {
                        NSString *msg = [NSString stringWithFormat:
                            @"Cap '%@' fetch aborted: referenced media URN '%@' could not be resolved: %@",
                            capUrn, firstFailingUrn, firstError.localizedDescription];
                        completion([NSError errorWithDomain:@"CSFabricRegistryError"
                                                       code:1010
                                                   userInfo:@{NSLocalizedDescriptionKey: msg,
                                                              NSUnderlyingErrorKey: firstError}]);
                    } else {
                        completion(nil);
                    }
                }
            }
        }];
    }
}

// Insert a fetched/cached media spec into the in-memory cache and extension
// index — and ONLY those. The manifest map is NOT written here: the manifest is
// authoritative (loaded from R2 / seeded by the test helper) and the path this
// spec was fetched from was already derived from it. Mirrors the cache-only
// insert at the tail of Rust fetch_one_media_def. The test/local seeding path
// (addMediaDef:) is the one that registers the manifest defver.
- (void)insertMediaDefInMemory:(NSDictionary *)spec {
    NSString *rawUrn = spec[@"urn"];
    if (![rawUrn isKindOfClass:[NSString class]] || rawUrn.length == 0) {
        return;
    }
    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:rawUrn error:&normError];
    if (!normalized) {
        NSLog(@"[CSFabricRegistry] insertMediaDefInMemory: skipping spec with malformed media URN '%@': %@",
              rawUrn, normError.localizedDescription);
        return;
    }
    [self.cacheLock lock];
    self.cachedSpecs[normalized] = spec;
    [self.cacheLock unlock];
    [self indexExtensionsForSpec:spec urn:rawUrn];
}

// Update the extension index for a spec's declared extensions. Takes the cache
// lock internally; never call it while already holding the lock.
- (void)indexExtensionsForSpec:(NSDictionary *)spec urn:(NSString *)rawUrn {
    if (![rawUrn isKindOfClass:[NSString class]]) return;
    NSArray *extensions = spec[@"extensions"];
    if (![extensions isKindOfClass:[NSArray class]]) return;
    [self.cacheLock lock];
    for (id ext in extensions) {
        if (![ext isKindOfClass:[NSString class]]) continue;
        NSString *extLower = [self normalizeExtension:ext];
        NSMutableArray *list = self.extensionIndex[extLower];
        if (!list) {
            list = [NSMutableArray array];
            self.extensionIndex[extLower] = list;
        }
        if (![list containsObject:rawUrn]) {
            [list addObject:rawUrn];
        }
    }
    [self.cacheLock unlock];
}

// MARK: - Disk cache I/O

- (nullable NSString *)capCacheFilePathForUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error {
    NSString *normalized = [self normalizeCapUrn:urn error:error];
    if (!normalized) return nil;
    uint32_t defver = 0;
    if (![self capDefver:&defver forNormalized:normalized error:error]) return nil;
    return [self cacheFileInDir:self.capsCacheDirectory
                         digest:[self sha256HexForString:normalized]
                         defver:defver];
}

- (nullable NSString *)mediaCacheFilePathForUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error {
    NSString *normalized = [self normalizeMediaUrn:urn error:error];
    if (!normalized) return nil;
    uint32_t defver = 0;
    if (![self mediaDefver:&defver forNormalized:normalized error:error]) return nil;
    return [self cacheFileInDir:self.mediaCacheDirectory
                         digest:[self sha256HexForString:normalized]
                         defver:defver];
}

- (void)saveCapToCache:(CSCap *)cap {
    NSError *pathError = nil;
    NSString *cacheFile = [self capCacheFilePathForUrn:[cap.capUrn toString] error:&pathError];
    if (!cacheFile) {
        NSLog(@"[CSFabricRegistry] saveCapToCache: skipping cap with malformed URN: %@", pathError.localizedDescription);
        return;
    }
    NSDictionary *capDict = [cap toDictionary];
    NSDictionary *entry = @{
        @"definition": capDict,
        @"cached_at": @([[NSDate date] timeIntervalSince1970]),
        @"ttl_hours": @(CACHE_DURATION_HOURS),
    };
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:entry options:NSJSONWritingPrettyPrinted error:&err];
    if (data) {
        [data writeToFile:cacheFile atomically:YES];
    }
}

- (void)saveMediaDefToCache:(NSDictionary *)spec {
    NSString *rawUrn = spec[@"urn"];
    if (![rawUrn isKindOfClass:[NSString class]]) return;
    NSError *pathError = nil;
    NSString *cacheFile = [self mediaCacheFilePathForUrn:rawUrn error:&pathError];
    if (!cacheFile) {
        NSLog(@"[CSFabricRegistry] saveMediaDefToCache: skipping spec with malformed URN '%@': %@",
              rawUrn, pathError.localizedDescription);
        return;
    }
    NSDictionary *entry = @{
        @"spec": spec,
        @"cached_at": @([[NSDate date] timeIntervalSince1970]),
        @"ttl_hours": @(CACHE_DURATION_HOURS),
    };
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:entry options:NSJSONWritingPrettyPrinted error:&err];
    if (data) {
        [data writeToFile:cacheFile atomically:YES];
    }
}

// Enumerate every cached `.json` file under a cache dir, covering BOTH the flat
// v0 layout (`<dir>/<sha>.json`) and the versioned v >= 1 layout
// (`<dir>/<sha>/<defver>.json`). A shallow scan would miss the versioned files,
// leaving a populated disk cache invisible to the in-memory hydrate. Mirrors
// the recursive walk in Rust load_all_cached_caps/media_defs/aliases.
- (NSArray<NSString *> *)cachedJSONFilePathsInDir:(NSString *)dir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:dir];
    for (NSString *rel in en) {
        if (![rel hasSuffix:@".json"]) continue;
        [paths addObject:[dir stringByAppendingPathComponent:rel]];
    }
    return paths;
}

- (void)loadAllCachedCaps {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [self cachedJSONFilePathsInDir:self.capsCacheDirectory];
    for (NSString *filePath in files) {
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (!data) continue;
        NSError *err = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (![json isKindOfClass:[NSDictionary class]]) continue;

        CSCapCacheEntry *entry = [[CSCapCacheEntry alloc] init];
        entry.cachedAt = [json[@"cached_at"] doubleValue];
        entry.ttlHours = [json[@"ttl_hours"] doubleValue];

        NSDictionary *capDict = json[@"definition"];
        CSCap *cap = [CSCap capWithDictionary:capDict error:&err];
        if (!cap) continue;

        // TTL applies only to v0 (flat) entries; versioned entries are immutable
        // by protocol. Mirrors the `version == 0 && is_expired()` guard in Rust.
        if (cap.version == 0 && [entry isExpired]) {
            [fm removeItemAtPath:filePath error:nil];
            continue;
        }

        NSError *normError = nil;
        NSString *normalized = [self normalizeCapUrn:[cap.capUrn toString] error:&normError];
        if (!normalized) {
            NSLog(@"[CSFabricRegistry] loadAllCachedCaps: skipping cached cap with malformed URN: %@", normError.localizedDescription);
            continue;
        }
        [self.cacheLock lock];
        self.cachedCaps[normalized] = cap;
        [self.cacheLock unlock];
    }
}

- (void)loadAllCachedMediaDefs {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [self cachedJSONFilePathsInDir:self.mediaCacheDirectory];
    for (NSString *filePath in files) {
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (!data) continue;
        NSError *err = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (![json isKindOfClass:[NSDictionary class]]) continue;

        CSMediaCacheEntry *entry = [[CSMediaCacheEntry alloc] init];
        entry.cachedAt = [json[@"cached_at"] doubleValue];
        entry.ttlHours = [json[@"ttl_hours"] doubleValue];

        NSDictionary *spec = json[@"spec"];
        if (![spec isKindOfClass:[NSDictionary class]]) continue;

        uint32_t specVersion = (uint32_t)[spec[@"version"] unsignedIntValue];
        if (specVersion == 0 && [entry isExpired]) {
            [fm removeItemAtPath:filePath error:nil];
            continue;
        }
        [self insertMediaDefInMemory:spec];
    }
}

// Load the alias cache (`aliases/<sha>/<defver>.json`). Aliases are
// versioned-only — no v0 flat path, no TTL (a published defver is immutable).
// Mirrors Rust load_all_cached_aliases.
- (void)loadAllCachedAliases {
    NSArray<NSString *> *files = [self cachedJSONFilePathsInDir:self.aliasesCacheDirectory];
    for (NSString *filePath in files) {
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (!data) continue;
        NSError *err = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (![json isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *alias = json[@"alias"];
        if (![alias isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = alias[@"name"];
        if (![name isKindOfClass:[NSString class]]) continue;
        [self.cacheLock lock];
        self.cachedAliases[name] = alias;
        [self.cacheLock unlock];
    }
}

// Load the dim cache (`dims/<sha>/<defver>.json`, each `{"dim": <body>,
// "cached_at", "ttl_hours"}`). Dims are versioned-only — no v0 flat path, no
// TTL (a published defver is immutable). A cached body this library cannot
// hold is dropped like an unparseable one, and fetched anew. Of two cached
// versions of one dim, the one the manifest pins is kept. Mirrors Rust
// load_all_cached_dims.
- (void)loadAllCachedDims {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [self cachedJSONFilePathsInDir:self.dimsCacheDirectory];
    for (NSString *filePath in files) {
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (!data) continue;
        NSError *err = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        id body = [json isKindOfClass:[NSDictionary class]] ? json[@"dim"] : nil;
        CSStoredDim *dim = [body isKindOfClass:[NSDictionary class]] ? [CSStoredDim dimWithDictionary:body error:&err] : nil;
        if (!dim || ![dim validate:&err]) {
            NSLog(@"[CSFabricRegistry] dropping dim cache file %@: %@", filePath,
                  err.localizedDescription ?: @"not a dim cache entry");
            [fm removeItemAtPath:filePath error:nil];
            continue;
        }
        [self.cacheLock lock];
        CSStoredDim *held = self.cachedDims[dim.name];
        uint32_t pinned = (uint32_t)[self.manifestDims[dim.name] unsignedIntValue];
        if (!(held && held.version == pinned)) {
            self.cachedDims[dim.name] = dim;
        }
        [self.cacheLock unlock];
    }
}

// MARK: - HTTP fetch

- (void)fetchCapFromRegistry:(NSString *)urn
                  completion:(void (^)(CSCap *cap, NSError *error))completion {
    NSError *normError = nil;
    NSString *normalized = [self normalizeCapUrn:urn error:&normError];
    if (!normalized) {
        completion(nil, normError);
        return;
    }
    // Resolve the defver from the pinned manifest. A URN that is not part of the
    // snapshot is a hard NotFound here — we do NOT fetch a flat v0 path as a
    // fallback (that path 404s against a versioned registry and would mix
    // snapshots). Mirrors Rust get_cap → cap_defver.
    NSError *defverError = nil;
    uint32_t defver = 0;
    if (![self capDefver:&defver forNormalized:normalized error:&defverError]) {
        completion(nil, defverError);
        return;
    }
    NSString *digest = [self sha256HexForString:normalized];
    NSString *urlString = [self objectURLForKind:@"caps" digest:digest defver:defver];
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode != 200) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:http.statusCode
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Cap '%@' (defver %u) not found in registry (HTTP %ld) at %@",
                                                            normalized, defver, (long)http.statusCode, urlString]}]);
            return;
        }
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:1001
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to parse registry response for cap '%@'", urn]}]);
            return;
        }
        CSCap *cap = [CSCap capWithDictionary:json error:&parseError];
        if (!cap) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:1001
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to parse registry response for cap '%@': %@", urn, parseError.localizedDescription]}]);
            return;
        }
        // A definition is held to the definition rules by the side that
        // receives it as well as the side that sends it, before anything
        // caches it.
        NSError *ruleError = nil;
        if (![CSCapValidator validateCapDefinition:cap error:&ruleError]) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:1006
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"the registry's definition of cap '%@' breaks a definition rule: %@", urn, ruleError.localizedDescription]}]);
            return;
        }
        completion(cap, nil);
    }];
    [task resume];
}

- (void)fetchMediaDefFromRegistry:(NSString *)urn
                        completion:(void (^)(NSDictionary *spec, NSError *error))completion {
    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:urn error:&normError];
    if (!normalized) {
        completion(nil, normError);
        return;
    }
    // Manifest-driven defver; a URN outside the snapshot is a hard NotFound, not
    // a silent v0-flat fetch. Mirrors Rust get_media_def → media_defver.
    NSError *defverError = nil;
    uint32_t defver = 0;
    if (![self mediaDefver:&defver forNormalized:normalized error:&defverError]) {
        completion(nil, defverError);
        return;
    }
    NSString *digest = [self sha256HexForString:normalized];
    NSString *urlString = [self objectURLForKind:@"media" digest:digest defver:defver];
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode != 200) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:http.statusCode
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Media def '%@' (defver %u) not found in registry (HTTP %ld) at %@",
                                                            normalized, defver, (long)http.statusCode, urlString]}]);
            return;
        }
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:1001
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to parse registry response for media def '%@'", urn]}]);
            return;
        }
        completion(json, nil);
    }];
    [task resume];
}

// MARK: - Alias surface

- (uint32_t)aliasDefverFor:(NSString *)name error:(NSError *_Nullable *_Nullable)error {
    NSError *nerr = nil;
    NSString *normalized = CSNormalizeAliasName(name, &nerr);
    if (!normalized) {
        if (error) *error = nerr;
        return 0;
    }
    [self.cacheLock lock];
    uint32_t mv = self.manifestVersion;
    NSNumber *defver = self.manifestAliases[normalized];
    [self.cacheLock unlock];
    if (mv == 0) {
        if (error) *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1021
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"alias '%@' cannot resolve: registry is pinned at v0 (aliases are a versioned-regime concept)", normalized]}];
        return 0;
    }
    if (!defver) {
        if (error) *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1022
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"alias '%@' is not part of manifest v%u", normalized, mv]}];
        return 0;
    }
    return (uint32_t)[defver unsignedIntValue];
}

- (void)getAlias:(NSString *)name
      completion:(void (^)(NSDictionary *_Nullable alias, NSError *_Nullable error))completion {
    NSError *nerr = nil;
    NSString *normalized = CSNormalizeAliasName(name, &nerr);
    if (!normalized) {
        completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError" code:1020
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"invalid alias name: %@",
                nerr.localizedDescription]}]);
        return;
    }
    [self.cacheLock lock];
    NSDictionary *cached = self.cachedAliases[normalized];
    [self.cacheLock unlock];
    if (cached) {
        completion(cached, nil);
        return;
    }
    // Not cached: confirm manifest membership so an unknown alias is a hard
    // not-found rather than a silent miss. (The objc media registry does not
    // fetch aliases over the network; they are seeded or loaded from disk.)
    NSError *defErr = nil;
    [self aliasDefverFor:normalized error:&defErr];
    if (defErr) {
        completion(nil, defErr);
        return;
    }
    completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError" code:1023
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
            @"alias '%@' is in manifest v%u but not present in cache", normalized, self.manifestVersion]}]);
}

- (void)resolveAlias:(NSString *)name
          completion:(void (^)(NSString *_Nullable target, NSError *_Nullable error))completion {
    [self getAlias:name completion:^(NSDictionary *alias, NSError *error) {
        if (error) { completion(nil, error); return; }
        completion(alias[@"target"], nil);
    }];
}

- (void)resolveAliasTyped:(NSString *)name
                 expected:(NSInteger)expected
               completion:(void (^)(NSString *_Nullable target, NSError *_Nullable error))completion {
    [self getAlias:name completion:^(NSDictionary *alias, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *target = alias[@"target"];
        CSAliasTargetKind actual;
        if (!CSClassifyAliasTarget(target, &actual)) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError" code:1024
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"alias '%@' target '%@' is neither a cap nor a media URN", alias[@"name"], target]}]);
            return;
        }
        if (expected >= 0 && actual != (CSAliasTargetKind)expected) {
            NSString *actualStr = (actual == CSAliasTargetKindCap) ? @"cap" : @"media";
            NSString *expStr = ((CSAliasTargetKind)expected == CSAliasTargetKindCap) ? @"cap" : @"media";
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError" code:1025
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"alias '%@' resolves to a %@ URN ('%@') but a %@ was required here",
                    alias[@"name"], actualStr, target, expStr]}]);
            return;
        }
        completion(target, nil);
    }];
}

- (NSString *)resolveAliasCached:(NSString *)name {
    NSError *nerr = nil;
    NSString *normalized = CSNormalizeAliasName(name, &nerr);
    if (!normalized) return nil;
    [self.cacheLock lock];
    NSDictionary *alias = self.cachedAliases[normalized];
    [self.cacheLock unlock];
    return alias ? alias[@"target"] : nil;
}

- (void)insertCachedAliasForTest:(NSDictionary *)alias {
    NSString *name = alias[@"name"];
    NSNumber *version = alias[@"version"];
    if (![name isKindOfClass:[NSString class]]) return;
    [self.cacheLock lock];
    self.cachedAliases[name] = alias;
    if (self.manifestVersion >= 1 && [version isKindOfClass:[NSNumber class]]) {
        self.manifestAliases[name] = version;
    }
    [self.cacheLock unlock];
}

// MARK: - Dim surface

// Resolve a dim name to its defver under the pinned manifest. Dims exist only in
// the versioned regime: at v0 any dim lookup is a hard NotFound. At v >= 1 the
// name must be in the manifest's `dims` map. Mirrors Rust dim_defver.
- (uint32_t)dimDefverFor:(NSString *)name error:(NSError *_Nullable *_Nullable)error {
    [self.cacheLock lock];
    uint32_t mv = self.manifestVersion;
    NSNumber *defver = self.manifestDims[name];
    [self.cacheLock unlock];
    if (mv == 0) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimAtV0, [NSString stringWithFormat:
            @"dim '%@' cannot resolve: registry is pinned at v0 (dims are a versioned-regime concept)", name], nil);
        return 0;
    }
    if (!defver) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimNotInManifest, [NSString stringWithFormat:
            @"dim '%@' is not part of manifest v%u", name, mv], nil);
        return 0;
    }
    return (uint32_t)[defver unsignedIntValue];
}

- (void)getDim:(NSString *)name
    completion:(void (^)(CSStoredDim *_Nullable dim, NSError *_Nullable error))completion {
    if (!CSIsDimName(name)) {
        completion(nil, CSRegistryError(CSFabricRegistryErrorInvalidDimName,
            [NSString stringWithFormat:@"'%@' is not a dim name", name], nil));
        return;
    }
    CSStoredDim *cached = [self getCachedDim:name];
    if (cached) {
        completion(cached, nil);
        return;
    }
    NSError *defverError = nil;
    uint32_t defver = [self dimDefverFor:name error:&defverError];
    if (defverError) {
        completion(nil, defverError);
        return;
    }
    [self fetchDimFromRegistry:name defver:defver completion:completion];
}

- (nullable CSStoredDim *)getCachedDim:(NSString *)name {
    [self.cacheLock lock];
    CSStoredDim *dim = self.cachedDims[name];
    [self.cacheLock unlock];
    return dim;
}

- (void)insertCachedDimForTest:(CSStoredDim *)dim {
    [self.cacheLock lock];
    self.cachedDims[dim.name] = dim;
    if (self.manifestVersion >= 1) {
        self.manifestDims[dim.name] = @(dim.version);
    }
    [self.cacheLock unlock];
}

// The registry URL of a dim at a defver: `<base>/dims/<sha256-of-name>/<defver>.json`.
// Dims are versioned-only. Mirrors the URL half of Rust dim_url_and_cache_path.
- (NSString *)dimURLForName:(NSString *)name defver:(uint32_t)defver {
    return [self objectURLForKind:@"dims" digest:[self sha256HexForString:name] defver:defver];
}

// The cache file of a dim at a defver: `<cache>/dims/<sha256-of-name>/<defver>.json`.
// Mirrors the cache-path half of Rust dim_url_and_cache_path.
- (NSString *)dimCacheFileForName:(NSString *)name defver:(uint32_t)defver {
    return [self cacheFileInDir:self.dimsCacheDirectory digest:[self sha256HexForString:name] defver:defver];
}

// A dim body as a registry served it, for the dim `name` at `defver`: parsed
// (unknown fields refused), named and versioned as requested, and holding
// (-[CSStoredDim validate:]). Mirrors Rust checked_dim.
- (nullable CSStoredDim *)checkedDimFromData:(NSData *)data
                                        name:(NSString *)name
                                      defver:(uint32_t)defver
                                       error:(NSError *_Nullable *_Nullable)error {
    NSError *parseError = nil;
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError] : nil;
    CSStoredDim *dim = [json isKindOfClass:[NSDictionary class]] ? [CSStoredDim dimWithDictionary:json error:&parseError] : nil;
    if (!dim) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimParse, [NSString stringWithFormat:
            @"Failed to parse dim '%@': %@", name, parseError.localizedDescription ?: @"not a JSON object"], parseError);
        return nil;
    }
    if (![dim.name isEqualToString:name]) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimParse, [NSString stringWithFormat:
            @"dim object name '%@' does not match requested name '%@'", dim.name, name], nil);
        return nil;
    }
    if (dim.version != defver) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimParse, [NSString stringWithFormat:
            @"dim '%@' object reports version %u but manifest pins defver %u", dim.name, dim.version, defver], nil);
        return nil;
    }
    NSError *validateError = nil;
    if (![dim validate:&validateError]) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimInvalid, validateError.localizedDescription, validateError);
        return nil;
    }
    return dim;
}

// Fetch a single dim body at its pinned defver, check it, and cache it in memory
// and on disk. A registry that serves another object is a hard error, never
// silently accepted. Mirrors Rust fetch_one_dim.
- (void)fetchDimFromRegistry:(NSString *)name
                      defver:(uint32_t)defver
                  completion:(void (^)(CSStoredDim *_Nullable dim, NSError *_Nullable error))completion {
    if (defver < 1) {
        completion(nil, CSRegistryError(CSFabricRegistryErrorDimNotInManifest, [NSString stringWithFormat:
            @"dim '%@' has non-positive defver %u; dims are versioned-only", name, defver], nil));
        return;
    }
    NSString *urlString = [self dimURLForName:name defver:defver];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *netError) {
        if (netError) {
            completion(nil, CSRegistryError(CSFabricRegistryErrorDimUnavailable, [NSString stringWithFormat:
                @"Failed to fetch dim '%@': %@", name, netError.localizedDescription], netError));
            return;
        }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode != 200) {
            completion(nil, CSRegistryError(CSFabricRegistryErrorDimHTTPNotFound, [NSString stringWithFormat:
                @"dim '%@' not found in registry (HTTP %ld) at %@", name, (long)http.statusCode, urlString], nil));
            return;
        }
        NSError *checkError = nil;
        CSStoredDim *dim = [self checkedDimFromData:data name:name defver:defver error:&checkError];
        if (!dim) {
            completion(nil, checkError);
            return;
        }
        NSDictionary *entry = @{
            @"dim": [dim toDictionary],
            @"cached_at": @([[NSDate date] timeIntervalSince1970]),
            @"ttl_hours": @(CACHE_DURATION_HOURS),
        };
        NSError *writeError = nil;
        NSString *cacheFile = [self dimCacheFileForName:name defver:defver];
        NSData *serialized = [NSJSONSerialization dataWithJSONObject:entry options:NSJSONWritingPrettyPrinted error:&writeError];
        if (!serialized || ![serialized writeToFile:cacheFile options:NSDataWritingAtomic error:&writeError]) {
            completion(nil, CSRegistryError(CSFabricRegistryErrorDimUnavailable, [NSString stringWithFormat:
                @"Failed to write dim cache file %@: %@", cacheFile, writeError.localizedDescription], writeError));
            return;
        }
        [self.cacheLock lock];
        self.cachedDims[dim.name] = dim;
        [self.cacheLock unlock];
        completion(dim, nil);
    }];
    [task resume];
}

// Make sure every dim a definition names is cached, fetching the ones that are
// not at the defver the manifest pins, and that each names a value the dim
// declares. `owner` names the definition in errors. Nothing about the
// definition itself is cached here: its fetcher caches it only once this
// succeeds. A dim the manifest does not list is refused before any fetch.
// Mirrors Rust ensure_dims_cached.
- (void)ensureDimsCached:(NSArray<CSDimRef *> *)refs
                   owner:(NSString *)owner
              completion:(void (^)(NSError *_Nullable error))completion {
    NSError *refsError = nil;
    if (!CSCheckDimRefs(refs, &refsError)) {
        completion(CSRegistryError(CSFabricRegistryErrorDimRefsInvalid, [NSString stringWithFormat:
            @"%@ dims: %@", owner, refsError.localizedDescription], refsError));
        return;
    }
    [self ensureDimsCached:refs fromIndex:0 owner:owner completion:completion];
}

- (void)ensureDimsCached:(NSArray<CSDimRef *> *)refs
               fromIndex:(NSUInteger)index
                   owner:(NSString *)owner
              completion:(void (^)(NSError *_Nullable error))completion {
    if (index == refs.count) {
        completion(nil);
        return;
    }
    CSDimRef *ref = refs[index];
    void (^holdValue)(CSStoredDim *) = ^(CSStoredDim *dim) {
        if (![dim valueNamed:ref.value]) {
            completion(CSRegistryError(CSFabricRegistryErrorDimValueUndeclared, [NSString stringWithFormat:
                @"%@ names value '%@' of dim '%@', which the dim does not declare", owner, ref.value, ref.dim], nil));
            return;
        }
        [self ensureDimsCached:refs fromIndex:index + 1 owner:owner completion:completion];
    };
    [self.cacheLock lock];
    CSStoredDim *cached = self.cachedDims[ref.dim];
    NSNumber *defver = self.manifestDims[ref.dim];
    uint32_t mv = self.manifestVersion;
    [self.cacheLock unlock];
    if (cached) {
        holdValue(cached);
        return;
    }
    if (mv == 0) {
        completion(CSRegistryError(CSFabricRegistryErrorDimAtV0, [NSString stringWithFormat:
            @"%@ names dim '%@', but the registry is pinned at v0 (dims are a versioned-regime concept)", owner, ref.dim], nil));
        return;
    }
    if (!defver) {
        completion(CSRegistryError(CSFabricRegistryErrorDimNotInManifest, [NSString stringWithFormat:
            @"%@ names dim '%@', which is not in manifest v%u", owner, ref.dim, mv], nil));
        return;
    }
    [self fetchDimFromRegistry:ref.dim defver:(uint32_t)[defver unsignedIntValue]
                    completion:^(CSStoredDim *dim, NSError *error) {
        if (!dim) {
            completion(CSRegistryError(CSFabricRegistryErrorDimUnavailable, [NSString stringWithFormat:
                @"%@ names dim '%@', which could not be fetched: %@", owner, ref.dim, error.localizedDescription], error));
            return;
        }
        holdValue(dim);
    }];
}

- (void)insertCachedCapForTest:(CSCap *)cap {
    if (cap.version == 0 && self.manifestVersion >= 1) {
        cap.version = self.manifestVersion;
    }
    NSError *normError = nil;
    NSString *normalized = [self normalizeCapUrn:[cap.capUrn toString] error:&normError];
    if (!normalized) {
        NSLog(@"[CSFabricRegistry] insertCachedCapForTest: skipping cap with malformed URN: %@", normError.localizedDescription);
        return;
    }
    [self.cacheLock lock];
    self.cachedCaps[normalized] = cap;
    if (self.manifestVersion >= 1) {
        self.manifestCaps[normalized] = @(cap.version);
    }
    [self.cacheLock unlock];
}

- (NSDictionary *)manifestDictionary {
    [self.cacheLock lock];
    NSDictionary *dict = @{
        @"version": @(self.manifestVersion),
        @"previous": @(self.manifestVersion > 0 ? self.manifestVersion - 1 : 0),
        @"caps": [self.manifestCaps copy],
        @"media": [self.manifestMedia copy],
        @"aliases": [self.manifestAliases copy],
        @"dims": [self.manifestDims copy],
    };
    [self.cacheLock unlock];
    return dict;
}

@end

// MARK: - Validation Functions

void CSValidateCapCanonical(CSFabricRegistry *registry, CSCap *cap, void (^completion)(NSError *error)) {
    [registry validateCap:cap completion:completion];
}
