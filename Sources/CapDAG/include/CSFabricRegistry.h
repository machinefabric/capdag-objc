//
//  CSFabricRegistry.h
//  CapDAG
//
//  Unified Fabric Registry — replaces what used to be a separate
//  cap registry and media-URN registry. Holds cap definitions and
//  media specs together with a single HTTP client and one disk
//  cache root (`caps/` and `media/` subdirectories).
//

#import <Foundation/Foundation.h>

@class CSCap, CSCapUrn;

NS_ASSUME_NONNULL_BEGIN

/**
 * CSFabricRegistryConfig holds configuration for the unified registry.
 */
@interface CSFabricRegistryConfig : NSObject

/** Base URL for the registry API (e.g., "https://fabric.capdag.com") */
@property (nonatomic, copy) NSString *registryBaseURL;

/** Base URL for schema profiles (defaults to {registryBaseURL}/schema) */
@property (nonatomic, copy) NSString *schemaBaseURL;

/// Defaults from environment variables CAPDAG_REGISTRY_URL and
/// CAPDAG_SCHEMA_BASE_URL, falling back to https://fabric.capdag.com.
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
 * media-spec cache: extensions become known as their owning specs
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

// MARK: Media-spec surface

/// Get a media spec from the in-memory cache or fetch it.
- (void)getMediaSpec:(NSString *)urn
          completion:(void (^)(NSDictionary * _Nullable spec, NSError * _Nullable error))completion;

/// Synchronous in-memory probe for a cached media spec. Returns nil
/// when not cached; never touches the network.
- (nullable NSDictionary *)getCachedMediaSpec:(NSString *)urn;

/// Insert a media spec directly into the in-memory cache.
/// Updates the extension index as a side effect. Used for tests and
/// for hydrating from local sources (e.g. cartridge manifests).
- (void)addMediaSpec:(NSDictionary *)spec;

/// All media URNs registered for the given extension. Returns an
/// empty array when the extension hasn't been seen yet (specs
/// hydrate on demand through getMediaSpec / getCapWithUrn — there is
/// no compiled-in fallback). The leading dot is stripped if present;
/// matching is case-insensitive.
- (NSArray<NSString *> *)mediaUrnsForExtension:(NSString *)extension;

/// Convenience: the first registered URN for the extension, or nil.
- (nullable NSString *)primaryMediaUrnForExtension:(NSString *)extension;

/// YES if the extension index currently has any URNs for the extension.
- (BOOL)hasExtension:(NSString *)extension;

/// All extensions currently in the index.
- (NSArray<NSString *> *)allExtensions;

// MARK: Cache lifecycle

/// Clear in-memory and on-disk caches.
- (void)clearCache;

@end

/// Convenience function — validates a cap against its canonical
/// definition through the supplied registry.
void CSValidateCapCanonical(CSFabricRegistry *registry, CSCap *cap,
                            void (^completion)(NSError * _Nullable error));

NS_ASSUME_NONNULL_END