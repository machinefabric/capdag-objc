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
//      as media specs land in cachedSpecs.
//
//  Atomic cap fetch: getCapWithUrn: refuses to cache a cap until every
//  media URN it references has also been successfully fetched. The bare
//  `media:` wildcard is excluded from the recursive fetch.
//

#import "CSFabricRegistry.h"
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
    NSString *registryURL = env[@"CAPDAG_REGISTRY_URL"];
    NSString *schemaURL = env[@"CAPDAG_SCHEMA_BASE_URL"];
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSCap *> *cachedCaps;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *cachedSpecs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *extensionIndex;
@property (nonatomic, strong) NSLock *cacheLock;
@property (nonatomic, strong, readwrite) CSFabricRegistryConfig *config;
@end

@implementation CSFabricRegistry

+ (CSFabricRegistry *)shared {
    static CSFabricRegistry *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CSFabricRegistry alloc] init];
    });
    return instance;
}

- (instancetype)init {
    return [self initWithConfig:[CSFabricRegistryConfig defaultConfig]];
}

- (instancetype)initWithRegistryURL:(NSString *)registryURL {
    return [self initWithConfig:[CSFabricRegistryConfig configWithRegistryURL:registryURL]];
}

- (instancetype)initWithConfig:(CSFabricRegistryConfig *)config {
    self = [super init];
    if (self) {
        _config = config;

        NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        sessionConfig.timeoutIntervalForRequest = HTTP_TIMEOUT_SECONDS;
        sessionConfig.timeoutIntervalForResource = HTTP_TIMEOUT_SECONDS;
        _session = [NSURLSession sessionWithConfiguration:sessionConfig];

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDir = [paths firstObject];
        _cacheDirectory = [cacheDir stringByAppendingPathComponent:@"capdag"];
        _capsCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"caps"];
        _mediaCacheDirectory = [_cacheDirectory stringByAppendingPathComponent:@"media"];

        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:_capsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:_mediaCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];

        _cachedCaps = [[NSMutableDictionary alloc] init];
        _cachedSpecs = [[NSMutableDictionary alloc] init];
        _extensionIndex = [[NSMutableDictionary alloc] init];
        _cacheLock = [[NSLock alloc] init];

        [self loadAllCachedCaps];
        [self loadAllCachedMediaSpecs];
    }
    return self;
}

// MARK: - URN normalization helpers

- (NSString *)normalizeCapUrn:(NSString *)urn {
    NSError *error = nil;
    CSCapUrn *parsed = [CSCapUrn fromString:urn error:&error];
    return parsed ? [parsed toString] : urn;
}

- (NSString *)normalizeMediaUrn:(NSString *)urn {
    NSError *error = nil;
    CSMediaUrn *parsed = [CSMediaUrn fromString:urn error:&error];
    return parsed ? [parsed toString] : urn;
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

// MARK: - Public cap surface

- (void)getCapWithUrn:(NSString *)urn
           completion:(void (^)(CSCap *_Nullable cap, NSError *_Nullable error))completion {
    NSString *normalized = [self normalizeCapUrn:urn];

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
    NSString *normalized = [self normalizeCapUrn:urn];
    [self.cacheLock lock];
    BOOL exists = (self.cachedCaps[normalized] != nil);
    [self.cacheLock unlock];
    return exists;
}

// MARK: - Public media-spec surface

- (void)getMediaSpec:(NSString *)urn
          completion:(void (^)(NSDictionary * _Nullable spec, NSError * _Nullable error))completion {
    NSString *normalized = [self normalizeMediaUrn:urn];

    [self.cacheLock lock];
    NSDictionary *cached = self.cachedSpecs[normalized];
    [self.cacheLock unlock];

    if (cached) {
        completion(cached, nil);
        return;
    }

    [self fetchMediaSpecFromRegistry:urn completion:^(NSDictionary *spec, NSError *error) {
        if (spec) {
            [self saveMediaSpecToCache:spec];
            [self insertMediaSpecInMemory:spec];
        }
        completion(spec, error);
    }];
}

- (NSDictionary *)getCachedMediaSpec:(NSString *)urn {
    NSString *normalized = [self normalizeMediaUrn:urn];
    [self.cacheLock lock];
    NSDictionary *spec = self.cachedSpecs[normalized];
    [self.cacheLock unlock];
    return spec;
}

- (void)addMediaSpec:(NSDictionary *)spec {
    [self insertMediaSpecInMemory:spec];
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
    [self.extensionIndex removeAllObjects];
    [self.cacheLock unlock];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.cacheDirectory error:nil];
    [fm createDirectoryAtPath:self.capsCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:self.mediaCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
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
        [self ensureMediaSpecsCached:referenced
                          forCapUrn:urn
                         completion:^(NSError *mediaError) {
            if (mediaError) {
                // Atomic: every referenced media URN must land before
                // the cap is cached. Failure leaves the cap out of both
                // in-memory and on-disk caches.
                completion(nil, mediaError);
                return;
            }
            [self saveCapToCache:cap];
            [self.cacheLock lock];
            self.cachedCaps[[self normalizeCapUrn:[cap.capUrn toString]]] = cap;
            [self.cacheLock unlock];
            completion(cap, nil);
        }];
    }];
}

- (void)ensureMediaSpecsCached:(NSArray<NSString *> *)urns
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

        [self fetchMediaSpecFromRegistry:mediaUrn completion:^(NSDictionary *spec, NSError *error) {
            if (spec) {
                [self saveMediaSpecToCache:spec];
                [self insertMediaSpecInMemory:spec];
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

- (void)insertMediaSpecInMemory:(NSDictionary *)spec {
    NSString *rawUrn = spec[@"urn"];
    if (![rawUrn isKindOfClass:[NSString class]] || rawUrn.length == 0) {
        return;
    }
    NSString *normalized = [self normalizeMediaUrn:rawUrn];
    [self.cacheLock lock];
    self.cachedSpecs[normalized] = spec;
    NSArray *extensions = spec[@"extensions"];
    if ([extensions isKindOfClass:[NSArray class]]) {
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
    }
    [self.cacheLock unlock];
}

// MARK: - Disk cache I/O

- (NSString *)capCacheFilePathForUrn:(NSString *)urn {
    return [self.capsCacheDirectory stringByAppendingPathComponent:
            [[self sha256HexForString:[self normalizeCapUrn:urn]] stringByAppendingString:@".json"]];
}

- (NSString *)mediaCacheFilePathForUrn:(NSString *)urn {
    return [self.mediaCacheDirectory stringByAppendingPathComponent:
            [[self sha256HexForString:[self normalizeMediaUrn:urn]] stringByAppendingString:@".json"]];
}

- (void)saveCapToCache:(CSCap *)cap {
    NSString *cacheFile = [self capCacheFilePathForUrn:[cap.capUrn toString]];
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

- (void)saveMediaSpecToCache:(NSDictionary *)spec {
    NSString *rawUrn = spec[@"urn"];
    if (![rawUrn isKindOfClass:[NSString class]]) return;
    NSString *cacheFile = [self mediaCacheFilePathForUrn:rawUrn];
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

- (void)loadAllCachedCaps {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:self.capsCacheDirectory error:nil];
    for (NSString *filename in files) {
        if (![filename hasSuffix:@".json"]) continue;
        NSString *filePath = [self.capsCacheDirectory stringByAppendingPathComponent:filename];
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (!data) continue;
        NSError *err = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (![json isKindOfClass:[NSDictionary class]]) continue;

        CSCapCacheEntry *entry = [[CSCapCacheEntry alloc] init];
        entry.cachedAt = [json[@"cached_at"] doubleValue];
        entry.ttlHours = [json[@"ttl_hours"] doubleValue];
        if ([entry isExpired]) {
            [fm removeItemAtPath:filePath error:nil];
            continue;
        }

        NSDictionary *capDict = json[@"definition"];
        CSCap *cap = [CSCap capWithDictionary:capDict error:&err];
        if (!cap) continue;

        NSString *normalized = [self normalizeCapUrn:[cap.capUrn toString]];
        [self.cacheLock lock];
        self.cachedCaps[normalized] = cap;
        [self.cacheLock unlock];
    }
}

- (void)loadAllCachedMediaSpecs {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:self.mediaCacheDirectory error:nil];
    for (NSString *filename in files) {
        if (![filename hasSuffix:@".json"]) continue;
        NSString *filePath = [self.mediaCacheDirectory stringByAppendingPathComponent:filename];
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (!data) continue;
        NSError *err = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (![json isKindOfClass:[NSDictionary class]]) continue;

        CSMediaCacheEntry *entry = [[CSMediaCacheEntry alloc] init];
        entry.cachedAt = [json[@"cached_at"] doubleValue];
        entry.ttlHours = [json[@"ttl_hours"] doubleValue];
        if ([entry isExpired]) {
            [fm removeItemAtPath:filePath error:nil];
            continue;
        }

        NSDictionary *spec = json[@"spec"];
        if ([spec isKindOfClass:[NSDictionary class]]) {
            [self insertMediaSpecInMemory:spec];
        }
    }
}

// MARK: - HTTP fetch

- (void)fetchCapFromRegistry:(NSString *)urn
                  completion:(void (^)(CSCap *cap, NSError *error))completion {
    NSString *normalized = [self normalizeCapUrn:urn];
    NSString *digest = [self sha256HexForString:normalized];
    NSString *urlString = [NSString stringWithFormat:@"%@/caps/%@", self.config.registryBaseURL, digest];
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode != 200) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:http.statusCode
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Cap '%@' not found in registry (HTTP %ld)",
                                                            urn, (long)http.statusCode]}]);
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

- (void)fetchMediaSpecFromRegistry:(NSString *)urn
                        completion:(void (^)(NSDictionary *spec, NSError *error))completion {
    NSString *normalized = [self normalizeMediaUrn:urn];
    NSString *digest = [self sha256HexForString:normalized];
    NSString *urlString = [NSString stringWithFormat:@"%@/media/%@", self.config.registryBaseURL, digest];
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode != 200) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:http.statusCode
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Media spec '%@' not found in registry (HTTP %ld)",
                                                            urn, (long)http.statusCode]}]);
            return;
        }
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:1001
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to parse registry response for media spec '%@'", urn]}]);
            return;
        }
        completion(json, nil);
    }];
    [task resume];
}

@end

// MARK: - Validation Functions

void CSValidateCapCanonical(CSFabricRegistry *registry, CSCap *cap, void (^completion)(NSError *error)) {
    [registry validateCap:cap completion:completion];
}
