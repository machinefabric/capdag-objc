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
//
//  Atomic cap fetch: getCapWithUrn: refuses to cache a cap until every
//  media URN it references has also been successfully fetched. The bare
//  `media:` wildcard is excluded from the recursive fetch.
//

#import "CSFabricRegistry.h"
#import "CSFabricManifestVersion.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSMediaUrn.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const DEFAULT_REGISTRY_BASE_URL = @"https://fabric.capdag.com";
static const NSTimeInterval CACHE_DURATION_HOURS = 24.0;
static const NSTimeInterval HTTP_TIMEOUT_SECONDS = 10.0;

// MARK: - CSFabricRegistryConfig

@implementation CSFabricRegistryConfig

+ (instancetype)defaultConfig {
    CSFabricRegistryConfig *config = [[CSFabricRegistryConfig alloc] init];
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *registryURL = env[@"CDG_FABRIC_REGISTRY_URL"];
    NSString *schemaURL = env[@"CDG_SCHEMA_BASE_URL"];
    config.registryBaseURL = registryURL ?: DEFAULT_REGISTRY_BASE_URL;
    config.schemaBaseURL = schemaURL ?: [config.registryBaseURL stringByAppendingString:@"/schema"];
    return config;
}

+ (instancetype)configWithRegistryURL:(NSString *)registryURL {
    CSFabricRegistryConfig *config = [[CSFabricRegistryConfig alloc] init];
    config.registryBaseURL = registryURL;
    config.schemaBaseURL = [registryURL stringByAppendingString:@"/schema"];
    return config;
}

+ (instancetype)configWithRegistryURL:(NSString *)registryURL schemaURL:(NSString *)schemaURL {
    CSFabricRegistryConfig *config = [[CSFabricRegistryConfig alloc] init];
    config.registryBaseURL = registryURL;
    config.schemaBaseURL = schemaURL;
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

// MARK: - Registry slug (cartridge-registry slug scheme)

NSString * const CSCartridgeDevSlug = @"dev";
const NSUInteger CSCartridgeSlugHexLen = 16;

NSString *CSSlugForRegistryURL(NSString *_Nullable registryURL) {
    if (registryURL == nil) {
        return CSCartridgeDevSlug;
    }
    // Hash the URL verbatim — no normalization, scheme stripping, or slash
    // trimming. Two URLs differing in any byte hash to distinct slugs.
    NSData *data = [registryURL dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [hex substringToIndex:CSCartridgeSlugHexLen];
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
@property (nonatomic, strong) NSString *manifestsCacheDirectory;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSCap *> *cachedCaps;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *cachedSpecs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *cachedAliases;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *extensionIndex;
@property (nonatomic, strong) NSLock *cacheLock;
@property (nonatomic, strong, readwrite) CSFabricRegistryConfig *config;
// Manifest pin. manifestVersion == 0 ⇒ legacy v0 / flat-path mode (no manifest
// consulted). >= 1 ⇒ manifest-driven (alias resolution requires >= 1). The
// three maps are name/urn → defver, mirroring the Rust Manifest.
@property (nonatomic) uint32_t manifestVersion;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestCaps;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestMedia;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestAliases;
@end

@implementation CSFabricRegistry

+ (NSString *)defaultCacheRootForRegistryURL:(NSString *)registryBaseURL {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDir = [paths firstObject];
    NSString *root = [cacheDir stringByAppendingPathComponent:@"capdag"];
    return [root stringByAppendingPathComponent:CSSlugForRegistryURL(registryBaseURL)];
}

- (instancetype)init {
    return [self initWithConfig:[CSFabricRegistryConfig defaultConfig]];
}

- (instancetype)initWithRegistryURL:(NSString *)registryURL {
    return [self initWithConfig:[CSFabricRegistryConfig configWithRegistryURL:registryURL]];
}

- (instancetype)initWithConfig:(CSFabricRegistryConfig *)config {
    // The production path: pin at the baked manifest version and bootstrap the
    // manifest from disk/network. Mirrors Rust with_config (which delegates to
    // with_config_and_manifest_version at the baked version).
    return [self initWithConfig:config
                manifestVersion:CSBakedFabricManifestVersion
              bootstrapFromNetwork:YES];
}

// Designated initializer. `bootstrapFromNetwork == YES` mirrors Rust's
// `with_config_and_manifest_version`: it loads `manifest/<N>.json` from the
// local cache, else blocks on a network fetch, and fails hard if neither can
// supply it. `bootstrapFromNetwork == NO` mirrors Rust's `new_for_test_*`: an
// EMPTY manifest pinned at the requested version, no network, so test helpers
// populate the manifest maps as they insert caps/media/aliases.
- (instancetype)initWithConfig:(CSFabricRegistryConfig *)config
               manifestVersion:(uint32_t)manifestVersion
          bootstrapFromNetwork:(BOOL)bootstrapFromNetwork {
    self = [super init];
    if (self) {
        _config = config;

        NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        sessionConfig.timeoutIntervalForRequest = HTTP_TIMEOUT_SECONDS;
        sessionConfig.timeoutIntervalForResource = HTTP_TIMEOUT_SECONDS;
        _session = [NSURLSession sessionWithConfiguration:sessionConfig];

        // Namespace the cache root by the registry origin. Prod and staging
        // serve different bytes for the same URN/version; a single shared
        // `capdag/` root would let a prod-populated cache satisfy a staging
        // lookup (and vice versa), silently resolving against the wrong
        // snapshot. The caps/ and media/ subdirs derive from this namespaced
        // root so no cache is left origin-blind.
        _cacheDirectory = [[self class] defaultCacheRootForRegistryURL:config.registryBaseURL];
        _capsCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"caps"];
        _mediaCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"media"];
        _aliasesCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"aliases"];
        _manifestsCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"manifests"];

        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:_capsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:_mediaCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:_aliasesCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:_manifestsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];

        _cachedCaps = [[NSMutableDictionary alloc] init];
        _cachedSpecs = [[NSMutableDictionary alloc] init];
        _cachedAliases = [[NSMutableDictionary alloc] init];
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
        // Filter the loaded caches to the pinned manifest's defvers (v >= 1):
        // only retain a cached entry whose own version matches the defver the
        // manifest pins its URN at. A v0-flat or stale-version blob left on disk
        // from a different snapshot must never satisfy a v >= 1 lookup. Mirrors
        // the retain() pass in Rust's constructor.
        [self filterCachesToManifest];
    }
    return self;
}

/// Test constructor: an empty registry pinned at manifest v1, so test helpers
/// (insertCachedCapForTest:/insertCachedAliasForTest:/addMediaDef:) flow into
/// the manifest at their declared version — mirrors Rust new_for_test, which
/// builds Manifest::empty(1) and never touches the network.
- (instancetype)initForTest {
    return [self initWithConfig:[CSFabricRegistryConfig defaultConfig]
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
            if ([json isKindOfClass:[NSDictionary class]] && cachedVersion == self.manifestVersion) {
                [self ingestManifestDictionary:json];
                return;
            }
            // A cached manifest whose version disagrees with the file name (or
            // that no longer parses) is corrupt; drop it and re-fetch from the
            // network rather than trusting the wrong snapshot.
            NSLog(@"[CSFabricRegistry] cached manifest at %@ did not parse or reported version %u (expected %u); re-fetching",
                  cacheFile, cachedVersion, self.manifestVersion);
            [fm removeItemAtPath:cacheFile error:nil];
        }
    }

    NSString *urlString = [NSString stringWithFormat:@"%@/manifest/%u.json",
                           self.config.registryBaseURL, self.manifestVersion];
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

    [self ingestManifestDictionary:manifest];
    [body writeToFile:cacheFile atomically:YES];
}

// Replace the in-memory manifest maps with the snapshot's `caps`/`media`/
// `aliases` URN→defver mappings. The published manifest is the single source of
// truth for which URNs belong to the snapshot and at which defver each resolves.
- (void)ingestManifestDictionary:(NSDictionary *)manifest {
    NSDictionary *caps = manifest[@"caps"];
    NSDictionary *media = manifest[@"media"];
    NSDictionary *aliases = manifest[@"aliases"];
    [self.cacheLock lock];
    [self.manifestCaps removeAllObjects];
    [self.manifestMedia removeAllObjects];
    [self.manifestAliases removeAllObjects];
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
}

// After hydrating the on-disk caches, drop any entry whose version does NOT
// match the defver the manifest pins its URN at — a stale-snapshot or v0-flat
// blob must never satisfy a v >= 1 lookup. At v0 the manifest is empty and the
// alias cache is cleared (aliases are a versioned-regime concept). Mirrors the
// retain() pass in the Rust/py constructors.
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
        // The extension index is derived from cachedSpecs; rebuild it so it
        // reflects only the retained specs.
        [self.extensionIndex removeAllObjects];
        [self.cacheLock unlock];
        for (NSDictionary *spec in [self.cachedSpecs allValues]) {
            [self indexExtensionsForSpec:spec urn:spec[@"urn"]];
        }
        return;
    }
    // v0: aliases never exist on the flat path.
    [self.cachedAliases removeAllObjects];
    [self.cacheLock unlock];
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

// MARK: - Object-path construction (defver → versioned vs flat path)

// Build the registry URL for a per-object path at the given defver. defver == 0
// addresses the frozen v0 flat path (`<base>/<kind>/<sha>`); defver >= 1
// addresses the versioned subpath (`<base>/<kind>/<sha>/<defver>.json`). Exact
// mirror of the URL half of Rust cap_url_and_cache_path/media_url_and_cache_path.
- (NSString *)objectURLForKind:(NSString *)kind digest:(NSString *)digest defver:(uint32_t)defver {
    if (defver == 0) {
        return [NSString stringWithFormat:@"%@/%@/%@", self.config.registryBaseURL, kind, digest];
    }
    return [NSString stringWithFormat:@"%@/%@/%@/%u.json", self.config.registryBaseURL, kind, digest, defver];
}

// Build the on-disk cache file path mirroring the object-path structure: flat
// `<dir>/<sha>.json` at defver 0, versioned `<dir>/<sha>/<defver>.json` at
// defver >= 1. Mirrors the cache-path half of the Rust helpers.
- (NSString *)cacheFileInDir:(NSString *)dir digest:(NSString *)digest defver:(uint32_t)defver {
    if (defver == 0) {
        return [dir stringByAppendingPathComponent:[digest stringByAppendingString:@".json"]];
    }
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

        if (![cap.command isEqualToString:canonicalCap.command]) {
            completion([NSError errorWithDomain:@"CSFabricRegistryError"
                                           code:1003
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                      [NSString stringWithFormat:@"Command mismatch. Local: %@, Canonical: %@",
                                                       cap.command, canonicalCap.command]}]);
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

    [self fetchMediaDefFromRegistry:urn completion:^(NSDictionary *spec, NSError *error) {
        if (spec) {
            [self saveMediaDefToCache:spec];
            [self insertMediaDefInMemory:spec];
        }
        completion(spec, error);
    }];
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
    [self.extensionIndex removeAllObjects];
    [self.cacheLock unlock];

    NSFileManager *fm = [NSFileManager defaultManager];
    // Clear the per-object caches (caps/media/aliases) but PRESERVE the manifest
    // cache: the registry stays pinned and usable after a clear, and re-fetching
    // every object lazily must still resolve defvers from the same snapshot. The
    // in-memory manifest maps are likewise left intact (cleared only by a new
    // construction). Recreate the per-object dirs so subsequent writes succeed.
    [fm removeItemAtPath:self.capsCacheDirectory error:nil];
    [fm removeItemAtPath:self.mediaCacheDirectory error:nil];
    [fm removeItemAtPath:self.aliasesCacheDirectory error:nil];
    [fm createDirectoryAtPath:self.capsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:self.mediaCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:self.aliasesCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
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
        for (CSArgSource *source in arg.sources) {
            if ([source isStdin]) {
                push(source.stdinMediaUrn);
            }
        }
    }
    if (cap.output) {
        push(cap.output.mediaUrn);
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
            [self saveCapToCache:cap];
            [self.cacheLock lock];
            self.cachedCaps[normalized] = cap;
            [self.cacheLock unlock];
            completion(cap, nil);
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

        [self fetchMediaDefFromRegistry:mediaUrn completion:^(NSDictionary *spec, NSError *error) {
            if (spec) {
                [self saveMediaDefToCache:spec];
                [self insertMediaDefInMemory:spec];
            }
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
                                                           [NSString stringWithFormat:@"Failed to construct cap from registry response for '%@'", urn]}]);
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
    };
    [self.cacheLock unlock];
    return dict;
}

@end

// MARK: - Validation Functions

void CSValidateCapCanonical(CSFabricRegistry *registry, CSCap *cap, void (^completion)(NSError *error)) {
    [registry validateCap:cap completion:completion];
}
