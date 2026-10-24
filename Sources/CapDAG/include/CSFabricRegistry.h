//
//  CSFabricRegistry.h
//  CapDAG
//
//  Unified Fabric Registry — replaces what used to be a separate
//  cap registry and media-URN registry. Holds cap definitions, media
//  defs, aliases and dims together with a single HTTP client and one
//  disk cache root (`caps/`, `media/`, `aliases/` and `dims/`
//  subdirectories).
//

#import <Foundation/Foundation.h>

@class CSCap, CSCapUrn, CSStoredDim, CSCharter;

NS_ASSUME_NONNULL_BEGIN

/// The domain of every error this registry reports.
extern NSErrorDomain const CSFabricRegistryErrorDomain;

/// The codes of the registry's dim errors (domain
/// `CSFabricRegistryErrorDomain`). The reference's error kind is named with
/// each.
typedef NS_ERROR_ENUM(CSFabricRegistryErrorDomain, CSFabricRegistryDimErrorCode) {
    /// ValidationError: a string that is no dim name was asked for.
    CSFabricRegistryErrorInvalidDimName = 1050,
    /// NotFound: the registry is pinned at v0, where there are no dims.
    CSFabricRegistryErrorDimAtV0 = 1051,
    /// NotFound: the pinned manifest does not list the dim. Decided before
    /// any fetch.
    CSFabricRegistryErrorDimNotInManifest = 1052,
    /// ParseError: a dim body the registry served is not the dim asked for
    /// (unparseable, an unknown field, another name, another version).
    CSFabricRegistryErrorDimParse = 1053,
    /// ValidationError: a dim body does not hold (`-[CSStoredDim validate:]`).
    CSFabricRegistryErrorDimInvalid = 1054,
    /// ValidationError: a definition names a value its dim does not declare.
    CSFabricRegistryErrorDimValueUndeclared = 1055,
    /// ValidationError: a definition's `dims` names a dim twice, or a non-dim.
    CSFabricRegistryErrorDimRefsInvalid = 1056,
    /// NotFound: a dim a definition names could not be fetched.
    CSFabricRegistryErrorDimUnavailable = 1057,
    /// NotFound: the registry has no object at the dim's address.
    CSFabricRegistryErrorDimHTTPNotFound = 1058,
    /// The manifest is not one this library reads (for one, it has no `dims`
    /// map).
    CSFabricRegistryErrorManifestInvalid = 1059,
};

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
 * CSFabricRegistryConfig: what a fabric registry client is asked to use.
 *
 * The ANCHOR names the registry and is all a client is told; where its
 * manifest and definitions are, and the folder its cache lives in, come from
 * the registry's charter. Sources, in priority order: +configWithAnchor:, then
 * CDG_FABRIC_REGISTRY_URL, then MachineFabric's production fabric.
 */
@interface CSFabricRegistryConfig : NSObject

/** The anchor of the fabric registry (e.g. "https://fabric.capdag.com"). */
@property (nonatomic, copy) NSString *anchor;

/// The anchor from CDG_FABRIC_REGISTRY_URL, falling back to
/// https://fabric.capdag.com.
+ (instancetype)defaultConfig;

/// The fabric registry chartered at `anchor`.
+ (instancetype)configWithAnchor:(NSString *)anchor;

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
 * A cap or media def is likewise cached only once every dim it names
 * (`dims`) is cached, at the version the manifest pins, with the value it
 * names — so a reader holding a cached definition can always read the
 * documentation of the dims it was built from (`getCachedDim:`).
 *
 * Extension lookups (mediaUrnsForExtension:) consult the in-memory
 * media-def cache: extensions become known as their owning specs
 * land — there is no compiled-in fallback table.
 */
/// What the planner needs of a fabric registry.
///
/// Declared beside the registry rather than beside its consumer so that the one
/// real implementer is compiled against it: a protocol whose only implementer
/// does not conform is not a contract, it is a crash waiting for the first
/// caller. `CSFabricRegistry` below conforms.
@protocol CSFabricRegistryProtocol <NSObject>
- (void)getCachedCaps:(void (^)(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error))completion;
- (void)getMediaDef:(NSString *)urn completion:(void (^)(NSDictionary * _Nullable spec, NSError * _Nullable error))completion;
@end

@interface CSFabricRegistry : NSObject <CSFabricRegistryProtocol>

/** The current registry configuration */
@property (nonatomic, readonly) CSFabricRegistryConfig *config;

/// The charter of the registry this client reads: its slug names the cache
/// folder, and its locations are where every object is fetched from.
@property (nonatomic, readonly) CSCharter *charter;

/// Initialize with default configuration.
- (instancetype)init;

/// Initialize with the supplied configuration. The registry's charter is
/// resolved first — the one stored in the cache when one is stored for this
/// anchor, else fetched from the anchor and stored — and everything after it
/// is read from the charter. Blocks on the network when the charter or the
/// pinned manifest is not cached, and raises when neither disk nor network
/// supplies them.
- (instancetype)initWithConfig:(CSFabricRegistryConfig *)config;

/// Initialize against the fabric registry chartered at `anchor`.
- (instancetype)initWithAnchor:(NSString *)anchor;

/// Test constructor: empty registry pinned at manifest v1 so test helpers flow
/// caps/media/aliases into the manifest at their declared version. Its charter
/// is +publisherLayoutCharterForAnchor:slug: of the default anchor, and it
/// never touches the network.
- (instancetype)initForTest;

/// The directory every registry's cache folder lives under:
/// `<NSCachesDirectory>/capdag`. A registry's own folder is its charter's
/// slug, so two registries never share one, whatever their URLs look like — a
/// cache populated from one fabric can never satisfy lookups against another,
/// which serves DIFFERENT bytes for the same URN and version.
+ (NSString *)capdagCacheRoot;

/// The charter of a fabric published at `anchor` the way the publisher lays a
/// fabric out (`fabric/src/fabric.js`), named `slug`. For a registry that is
/// never fetched: the test constructors, and tests of where things are.
+ (CSCharter *)publisherLayoutCharterForAnchor:(NSString *)anchor slug:(NSString *)slug;

/// The charter of the fabric registry at `anchor`: the one stored under
/// `cacheRoot` for it, else fetched from the anchor and stored in the folder
/// its slug names. A fabric's contents carry no signature, so no content
/// environment is expected of its charter. Mirrors Rust `resolve_charter`
/// (which also verifies the signature; see CSCharter.h).
+ (nullable CSCharter *)resolveCharterForAnchor:(NSString *)anchor
                                      cacheRoot:(NSString *)cacheRoot
                                        session:(NSURLSession *)session
                                          error:(NSError *_Nullable *_Nullable)error;

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

/// The cached caps, delivered to a completion block — the `CSFabricRegistryProtocol`
/// form. The cache is already in memory, so this completes synchronously on the
/// calling thread; the block exists because the protocol's other member genuinely
/// needs one.
- (void)getCachedCaps:(void (^)(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error))completion;

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

/// Resolve a cap URN to its pinned defver under the manifest. Returns YES and
/// writes *outDefver on success; returns NO and writes *error when the URN is
/// malformed or not part of the pinned snapshot (a hard NotFound — never a
/// silent flat-path fallback). Mirrors Rust cap_defver_for.
- (BOOL)capDefverFor:(NSString *)urn
              defver:(uint32_t *)outDefver
               error:(NSError *_Nullable *_Nullable)error;

/// Resolve a media URN to its pinned defver under the manifest. Same contract as
/// capDefverFor:defver:error:. The bare `media:` wildcard resolves to 0. Mirrors
/// Rust media_defver_for.
- (BOOL)mediaDefverFor:(NSString *)urn
                defver:(uint32_t *)outDefver
                 error:(NSError *_Nullable *_Nullable)error;

/// Insert an alias ({name,target,version}) directly into the in-memory cache
/// and register its defver in the manifest (test helper).
- (void)insertCachedAliasForTest:(NSDictionary *)alias;

// MARK: Dim surface

/// A dim's definition — its title, documentation and values, each value with
/// its own — by name, at the version the pinned manifest names: from the
/// cache, else fetched from the registry (`dims/<sha256-of-name>/<defver>.json`)
/// and cached. A string that is no dim name is refused
/// (`CSFabricRegistryErrorInvalidDimName`); a name the manifest does not list is
/// `CSFabricRegistryErrorDimNotInManifest`, decided before any fetch.
- (void)getDim:(NSString *)name
    completion:(void (^)(CSStoredDim *_Nullable dim, NSError *_Nullable error))completion;

/// Synchronous, in-memory-only dim lookup. Every dim a cached cap or media def
/// names is cached with it, so a reader holding a definition from this registry
/// finds its dims here.
- (nullable CSStoredDim *)getCachedDim:(NSString *)name;

/// Look up a dim name's pinned defver under the manifest without fetching the
/// body. Returns 0 and writes *error at v0 or when the manifest does not list
/// the name.
- (uint32_t)dimDefverFor:(NSString *)name error:(NSError *_Nullable *_Nullable)error;

/// Insert a dim directly into the in-memory cache and register its defver in
/// the manifest, bypassing the network (test helper; mirrors
/// insertCachedAliasForTest:).
- (void)insertCachedDimForTest:(CSStoredDim *)dim;

/// Insert a cap directly into the in-memory cap cache and register its defver
/// in the manifest (test helper).
- (void)insertCachedCapForTest:(CSCap *)cap;

/// The registry-snapshot manifest as a dict ({version,previous,caps,media,
/// aliases,dims}). Test/diagnostic surface.
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