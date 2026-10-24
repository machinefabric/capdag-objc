//
//  CSCharter.h
//  CapDAG
//
//  Registry charters: what makes a URL a MachineFabric registry. Mirrors Rust
//  `bifaci/charter.rs`.
//
//  A registry — of cartridges, of fabric definitions, or of app releases — is
//  named by its ANCHOR, which may be any URL. The one convention anywhere is
//  that `<anchor>/charter.json` and `<anchor>/charter.json.sig` exist.
//  Everything else is read from the charter, never derived from the shape of a
//  URL: the registry's slug (its folder on disk), its kind, the environment
//  its contents are signed under, the locations of its manifests, and for a
//  cartridge registry the fabric its caps resolve against.
//
//  What this does and does not do: it reads a charter and holds it to its
//  shape, to the folder it is stored in and to the anchor its cartridges
//  record. It does NOT verify the signature: this mirror carries no chain
//  verification (`release_cert.rs` and `charter.rs` in the Rust library are
//  the only implementation of it, checked against the MachineFabric roots
//  every Rust build bakes; a client verifies a charter with the same chain
//  code it verifies a manifest with), and a mirror that stubbed one would be
//  worse than a mirror that has none.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The domain of every charter error.
extern NSErrorDomain const CSCharterErrorDomain;

typedef NS_ERROR_ENUM(CSCharterErrorDomain, CSCharterErrorCode) {
    /// The bytes are not a charter document, or it breaks its shape.
    CSCharterErrorMalformed = 1,
    /// A charter that reads, and is not the one asked for: another anchor,
    /// another kind, or stored in a folder not named for its slug.
    CSCharterErrorRefused = 2,
    /// A stored charter could not be read from disk.
    CSCharterErrorUnreadable = 3,
    /// Nothing is at `<anchor>/charter.json`: the URL is not a MachineFabric
    /// registry.
    CSCharterErrorUnchartered = 4,
    /// The anchor answered with an HTTP error other than 404.
    CSCharterErrorHTTP = 5,
    /// The anchor could not be reached.
    CSCharterErrorUnreachable = 6,
};

/// The format discriminator inside every charter body.
extern NSString * const CSCharterFormat;
/// The format discriminator of a charter's signature envelope — distinct from
/// the manifest envelope's, so a prod-signed manifest can never be presented
/// as a charter.
extern NSString * const CSCharterSigFormat;
/// The charter's file name under its anchor and in a registry's folder.
extern NSString * const CSCharterFile;
/// The charter signature's file name.
extern NSString * const CSCharterSigFile;
/// The reserved folder name of cartridges built with no registry. No charter
/// may claim it.
extern NSString * const CSCharterDevSlug;

/// One of the three kinds of registry.
typedef NS_ENUM(NSInteger, CSRegistryKind) {
    CSRegistryKindCartridges,
    CSRegistryKindFabric,
    CSRegistryKindReleases,
};

/// The wire name of a registry kind: "cartridges", "fabric" or "releases".
FOUNDATION_EXPORT NSString *CSRegistryKindName(CSRegistryKind kind);

/// A charter body, as signed.
@interface CSCharter : NSObject

@property (nonatomic, readonly, copy) NSString *format;
/// The URL this registry is named by — the registry_url every cartridge from
/// it records.
@property (nonatomic, readonly, copy) NSString *anchor;
@property (nonatomic, readonly) CSRegistryKind kind;
/// The registry's name on disk. Never "dev".
@property (nonatomic, readonly, copy) NSString *slug;
/// The label this registry's CONTENTS are signed under.
@property (nonatomic, readonly, copy) NSString *environment;
/// The lab experiment this registry belongs to, if any.
@property (nonatomic, readonly, copy, nullable) NSString *experiment;
/// Templates, by name.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *locations;
/// For a cartridge registry, the anchor of the fabric registry its caps
/// resolve against.
@property (nonatomic, readonly, copy, nullable) NSString *fabric;
@property (nonatomic, readonly) uint64_t issuedAt;
/// When the charter is void; nil: valid while the key that signed it is
/// trusted.
@property (nonatomic, readonly, nullable) NSNumber *notAfter;

/// A charter's fields, each of the type a charter has; no field a charter
/// does not have. The shape rules are -validate:'s.
+ (nullable instancetype)charterWithDictionary:(NSDictionary *)dictionary
                                         error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(init(dictionary:));

/// A charter's bytes, read: the format first, then the fields, then the shape.
+ (nullable instancetype)charterWithData:(NSData *)data error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(init(data:));

/// The charter as its JSON object.
- (NSDictionary *)dictionaryRepresentation;

/// Hold the charter to the shape every charter must have, whoever signed it.
- (BOOL)validate:(NSError *_Nullable *_Nullable)error;

/// One location with its placeholders filled. Every placeholder the template
/// uses must be given, and nothing else may be.
- (nullable NSString *)locationNamed:(NSString *)name
                              values:(NSDictionary<NSString *, NSString *> *)values
                               error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(location(named:values:));

/// Whether `s` can be a registry slug: `[a-z0-9][a-z0-9.-]{0,62}`, and not
/// the reserved "dev".
+ (BOOL)isSlug:(NSString *)s;

/// Whether `s` can be a lab experiment id: `[a-z0-9][a-z0-9-]{0,39}`.
+ (BOOL)isExperimentID:(NSString *)s;

/// The charter stored in a registry's folder, held to its shape and its kind,
/// and the folder to its slug. The signature beside it is the Rust host's to
/// verify (see the file comment).
+ (nullable instancetype)storedInFolder:(NSString *)folder
                                   kind:(CSRegistryKind)kind
                                  error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(stored(inFolder:kind:));

/// Among the registry folders under `root`, the charter stored for `anchor`,
/// of `kind`; nil when none is. A folder whose charter does not read is
/// passed over. `outFolder` receives the folder it is stored in.
+ (nullable instancetype)storedUnder:(NSString *)root
                           forAnchor:(NSString *)anchor
                                kind:(CSRegistryKind)kind
                              folder:(NSString *_Nullable *_Nullable)outFolder
    NS_SWIFT_NAME(stored(under:anchor:kind:folder:));

@end

/// A charter as its anchor serves it: the exact bytes of the body and of its
/// signature, and the body read.
@interface CSFetchedCharter : NSObject

@property (nonatomic, readonly) CSCharter *charter;
@property (nonatomic, readonly, copy) NSData *body;
@property (nonatomic, readonly, copy) NSData *signature;

- (instancetype)initWithCharter:(CSCharter *)charter body:(NSData *)body signature:(NSData *)signature;
- (instancetype)init NS_UNAVAILABLE;

/// Fetch `<anchor>/charter.json` and its signature, read the body and hold it
/// to the anchor and kind asked. Blocks the calling thread until both answer.
///
/// The two are fetched with one cache-bust token, because the signature holds
/// only over a coherent pair and a CDN may cache them from different issues.
+ (nullable instancetype)fetchFromAnchor:(NSString *)anchor
                                    kind:(CSRegistryKind)kind
                                 session:(NSURLSession *)session
                                   error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(fetch(anchor:kind:session:));

/// Write the charter and its signature, byte for byte, into `folder` — which
/// must be named for the charter's slug, as +storedInFolder:kind:error:
/// requires of every folder it reads.
- (BOOL)storeInFolder:(NSString *)folder error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(store(inFolder:));

@end

NS_ASSUME_NONNULL_END
