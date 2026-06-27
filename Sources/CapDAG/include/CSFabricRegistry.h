//
//  CSFabricRegistry.h
//  CapDAG
//
//  Unified Fabric Registry — replaces what used to be a separate
//  cap registry and media-URN registry. Holds cap definitions and
//  media defs together with a single HTTP client and one disk
//  cache root (`caps/` and `media/` subdirectories).
//

#import <Foundation/Foundation.h>

@class CSCap, CSCapUrn;

NS_ASSUME_NONNULL_BEGIN

/// The kind of thing a fabric alias resolves to. An alias target is always a
/// URN; the kind is determined by the URN prefix.
typedef NS_ENUM(NSInteger, CSAliasTargetKind) {
    CSAliasTargetKindCap,
    CSAliasTargetKindMedia,
};

/// A contiguous token "looks like a URN" iff it contains ':'. Every tagged
/// URN has the shape prefix:..., so the presence of ':' is the unambiguous
/// discriminator between a URN and an alias name.
BOOL CSTokenIsURN(NSString *token);

/// Complement of CSTokenIsURN: a colon-free token is an alias candidate
/// (still subject to CSNormalizeAliasName validation).
BOOL CSIsAliasToken(NSString *token);

/// Normalize and validate an alias name. Lowercases the input, then requires
/// it non-empty, free of ':' (so it can never look like a tagged URN), free
/// of whitespace, and matching [a-z0-9._-]+. Returns the canonical lowercased
/// name, or nil + error — there is no lenient path.
NSString *_Nullable CSNormalizeAliasName(NSString *name, NSError *_Nullable *_Nullable error);

/// Classify an alias target URN by prefix. Returns YES + writes *outKind on a
/// cap or media URN; returns NO for anything else.
BOOL CSClassifyAliasTarget(NSString *target, CSAliasTargetKind *_Nullable outKind);

/**
 * CSFabricRegistryConfig holds configuration for the unified registry.
 */
@interface CSFabricRegistryConfig : NSObject

/** Base URL for the registry API (e.g., "https://fabric.capdag.com") */
@property (nonatomic, copy) NSString *registryBaseURL;

/** Base URL for schema profiles (defaults to {registryBaseURL}/schema) */
@property (nonatomic, copy) NSString *schemaBaseURL;

/// Defaults from environment variables CDG_FABRIC_REGISTRY_URL and
/// CDG_SCHEMA_BASE_URL, falling back to https://fabric.capdag.com.
+ (instancetype)defaultConfig;

/// Custom registry URL; schema URL is set to {registryURL}/schema.
+ (instancetype)configWithRegistryURL:(NSString *)registryURL;

/// Custom registry and schema URLs.
+ (instancetype)configWithRegistryURL:(NSString *)registryURL schemaURL:(NSString *)schemaURL;

@end

/**
 * CSFabricRegistry: unified registry for cap definitions AND media
 * specs, with local caching.
 *
 * Atomic cap fetch: a cap is only cached after every media URN it
 * references (in_spec, out_spec, every arg.media_urn, every stdin
 * source, output.media_urn) has also been successfully fetched. The
 * bare `media:` wildcard is excluded from the recursive fetch.
 *
 * Extension lookups (mediaUrnsForExtension:) consult the in-memory
 * media-def cache: extensions become known as their owning specs
 * land — there is no compiled-in fallback table.
 */
@interface CSFabricRegistry : NSObject

/** The current registry configuration */
@property (nonatomic, readonly) CSFabricRegistryConfig *config;

/// Initialize with default configuration.
- (instancetype)init;

/// Initialize with the supplied configuration.
- (instancetype)initWithConfig:(CSFabricRegistryConfig *)config;

/// Initialize with a custom registry URL.
- (instancetype)initWithRegistryURL:(NSString *)registryURL;

/// Test constructor: empty registry pinned at manifest v1 so test helpers flow
/// caps/media/aliases into the manifest at their declared version.
- (instancetype)initForTest;

// MARK: Cap surface

/// Get a cap from the in-memory cache or fetch it (atomically — see
/// class-level docs). Completion always fires with cap or error.
- (void)getCapWithUrn:(NSString *)urn
           completion:(void (^)(CSCap *_Nullable cap, NSError *_Nullable error))completion;

/// Get multiple caps. Fails if any cap is not available.
- (void)getCapsWithUrns:(NSArray<NSString *> *)urns
             completion:(void (^)(NSArray<CSCap *> *_Nullable caps, NSError *_Nullable error))completion;

/// Validate a local cap against its canonical definition.
- (void)validateCap:(CSCap *)cap completion:(void (^)(NSError * _Nullable error))completion;

/// Check whether a cap URN is currently in the in-memory cap cache.
/// Synchronous, network-free.
- (BOOL)capExists:(NSString *)urn;

/// All currently cached caps (snapshot).
- (NSArray<CSCap *> *)getCachedCaps;

// MARK: Media-def surface

/// Get a media def from the in-memory cache or fetch it.
- (void)getMediaDef:(NSString *)urn
          completion:(void (^)(NSDictionary * _Nullable spec, NSError * _Nullable error))completion;

/// Synchronous in-memory probe for a cached media def. Returns nil
/// when not cached; never touches the network.
- (nullable NSDictionary *)getCachedMediaDef:(NSString *)urn;

/// Insert a media def directly into the in-memory cache.
/// Updates the extension index as a side effect. Used for tests and
/// for hydrating from local sources (e.g. cartridge manifests).
- (void)addMediaDef:(NSDictionary *)spec;

/// All media URNs registered for the given extension. Returns an
/// empty array when the extension hasn't been seen yet (specs
/// hydrate on demand through getMediaDef / getCapWithUrn — there is
/// no compiled-in fallback). The leading dot is stripped if present;
/// matching is case-insensitive.
- (NSArray<NSString *> *)mediaUrnsForExtension:(NSString *)extension;

/// Convenience: the first registered URN for the extension, or nil.
- (nullable NSString *)primaryMediaUrnForExtension:(NSString *)extension;

/// YES if the extension index currently has any URNs for the extension.
- (BOOL)hasExtension:(NSString *)extension;

/// All extensions currently in the index.
- (NSArray<NSString *> *)allExtensions;

// MARK: Alias surface

/// Resolve an alias to the cap or media URN it points at (untyped): the
/// completion fires with whatever the alias targets, or an error.
- (void)resolveAlias:(NSString *)name
          completion:(void (^)(NSString *_Nullable target, NSError *_Nullable error))completion;

/// Resolve an alias and assert its target kind. The completion fires with the
/// target URN, or an error if the resolved target is the wrong kind. Pass a
/// negative `expected` (e.g. -1) to accept either kind.
- (void)resolveAliasTyped:(NSString *)name
                 expected:(NSInteger)expected
               completion:(void (^)(NSString *_Nullable target, NSError *_Nullable error))completion;

/// Fetch the full stored alias dict ({name,target,version}) for a name.
- (void)getAlias:(NSString *)name
      completion:(void (^)(NSDictionary *_Nullable alias, NSError *_Nullable error))completion;

/// Synchronous, in-memory-only alias resolution. Returns the target URN if the
/// alias is cached, nil otherwise (including for a malformed name).
- (nullable NSString *)resolveAliasCached:(NSString *)name;

/// Look up an alias name's pinned defver under the manifest. Returns 0 and
/// writes *error if the name is malformed or absent from the manifest.
- (uint32_t)aliasDefverFor:(NSString *)name error:(NSError *_Nullable *_Nullable)error;

/// Insert an alias ({name,target,version}) directly into the in-memory cache
/// and register its defver in the manifest (test helper).
- (void)insertCachedAliasForTest:(NSDictionary *)alias;

/// Insert a cap directly into the in-memory cap cache and register its defver
/// in the manifest (test helper).
- (void)insertCachedCapForTest:(CSCap *)cap;

/// The registry-snapshot manifest as a dict ({version,previous,caps,media,
/// aliases}). Test/diagnostic surface.
- (NSDictionary *)manifestDictionary;

// MARK: Cache lifecycle

/// Clear in-memory and on-disk caches.
- (void)clearCache;

@end

/// Convenience function — validates a cap against its canonical
/// definition through the supplied registry.
void CSValidateCapCanonical(CSFabricRegistry *registry, CSCap *cap,
                            void (^completion)(NSError * _Nullable error));

NS_ASSUME_NONNULL_END