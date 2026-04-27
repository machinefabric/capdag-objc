//
//  CSCapManifest.h
//  CapDAG
//
//  Unified cap-based manifest for components (providers and cartridges)
//

#import <Foundation/Foundation.h>

@class CSCap;

NS_ASSUME_NONNULL_BEGIN

// MARK: - Cap Group

/**
 * A cap group bundles caps and adapter URNs as an atomic registration unit.
 *
 * If any adapter in the group creates ambiguity with an already-registered adapter,
 * the entire group is rejected — none of its caps or adapters get registered.
 */
@interface CSCapGroup : NSObject

/// Group name (for diagnostics and error messages)
@property (nonatomic, strong) NSString *name;

/// Caps in this group
@property (nonatomic, strong) NSArray<CSCap *> *caps;

/// Media URNs this group's adapter handles.
/// Matched via conforms_to during registration — not patterns,
/// declared URNs checked for overlap with existing registrations.
@property (nonatomic, strong) NSArray<NSString *> *adapterUrns;

- (instancetype)initWithName:(NSString *)name
                        caps:(NSArray<CSCap *> *)caps
                 adapterUrns:(NSArray<NSString *> *)adapterUrns;

+ (nullable instancetype)groupWithDictionary:(NSDictionary *)dictionary
                                       error:(NSError * _Nullable * _Nullable)error;

@end

// MARK: - Unified Cap Manifest

@interface CSCapManifest : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *version;
/// Distribution channel the cartridge was built for ("release" or
/// "nightly"). `(registryURL, channel, name, version)` is the
/// cartridge's full identity — each (registry, channel) is an
/// independent namespace. The Rust SDK reads `MFR_CARTRIDGE_CHANNEL`
/// at compile time; Swift cartridges set it via the same
/// compile-time mechanism. Required.
@property (nonatomic, strong) NSString *channel;
/// Verbatim URL of the registry the cartridge was built for, or
/// `nil` for dev builds (`MFR_REGISTRY_URL` unset). Compared
/// byte-wise; never normalized. Required-but-nullable on the wire:
/// missing key surfaces as a parse error so old-schema payloads
/// never silently pass; explicit null means dev install.
@property (nonatomic, strong, nullable) NSString *registryURL;
@property (nonatomic, strong) NSString *manifestDescription;
/// Cap groups — bundles of caps + adapter URNs. All caps must be in a cap group.
@property (nonatomic, strong) NSArray<CSCapGroup *> *capGroups;
@property (nonatomic, strong, nullable) NSString *author;
@property (nonatomic, strong, nullable) NSString *pageUrl;

- (instancetype)initWithName:(NSString *)name
                     version:(NSString *)version
                     channel:(NSString *)channel
                 registryURL:(nullable NSString *)registryURL
          manifestDescription:(NSString *)manifestDescription
               capGroups:(NSArray<CSCapGroup *> *)capGroups;

+ (instancetype)manifestWithName:(NSString *)name
                         version:(NSString *)version
                         channel:(NSString *)channel
                     registryURL:(nullable NSString *)registryURL
                     description:(NSString *)description
                       capGroups:(NSArray<CSCapGroup *> *)capGroups;

+ (nullable instancetype)manifestWithDictionary:(NSDictionary * _Nonnull)dictionary
                                          error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(init(dictionary:));

- (CSCapManifest *)withAuthor:(NSString *)author;
- (CSCapManifest *)withPageUrl:(NSString *)pageUrl;

/**
 * Validate that CAP_IDENTITY is declared in this manifest.
 * Fails if missing — identity is mandatory in every capset.
 *
 * Swift automatically converts this to a throwing method.
 *
 * @param error If validation fails, contains the error description
 * @return YES if manifest contains CAP_IDENTITY, NO otherwise
 */
- (BOOL)validate:(NSError **)error;

/**
 * Ensure CAP_IDENTITY is present in this manifest. Adds it if missing.
 * This method is idempotent — if identity is already present, returns self unchanged.
 *
 * @return A new manifest with CAP_IDENTITY guaranteed to be present
 */
- (CSCapManifest *)ensureIdentity;

/**
 * Returns all caps from both the top-level caps list and all capGroups.
 */
- (NSArray<CSCap *> *)allCaps;

@end

NS_ASSUME_NONNULL_END