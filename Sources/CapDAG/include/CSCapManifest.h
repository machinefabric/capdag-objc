//
//  CSCapManifest.h
//  CapDAG
//
//  Unified cap-based manifest for components (candidates and cartridges)
//

#import <Foundation/Foundation.h>
#import "CSCap.h"

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

/** The group as the dictionary +groupWithDictionary:error: reads. */
- (NSDictionary *)toDictionary;

@end

// MARK: - Unified Cap Manifest

/// The error domain of a manifest another program advertised that was not taken.
FOUNDATION_EXPORT NSErrorDomain const CSManifestLoadErrorDomain;

typedef NS_ENUM(NSInteger, CSManifestLoadErrorCode) {
    /// The bytes are not a manifest.
    CSManifestLoadUnparseable = 1,
    /// The manifest parsed, and a cap definition in it breaks a definition rule.
    CSManifestLoadInvalidDefinition = 2,
};

@interface CSCapManifest : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *version;
/// Distribution channel the cartridge was built for.
/// `(registryURL, channel, name, version)` is the cartridge's full
/// identity — each (registry, channel) is an independent namespace.
/// The Rust SDK reads `MFR_CARTRIDGE_CHANNEL` at compile time; Swift
/// cartridges set it via the same compile-time mechanism. Required;
/// a missing or unrecognized value is a hard parse error.
@property (nonatomic, assign) CSCartridgeChannel channel;
/// Verbatim URL of the registry the cartridge was built for, or
/// `nil` for dev builds (`MFR_CARTRIDGE_REGISTRY_URL` unset). Compared
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
                     channel:(CSCartridgeChannel)channel
                 registryURL:(nullable NSString *)registryURL
          manifestDescription:(NSString *)manifestDescription
               capGroups:(NSArray<CSCapGroup *> *)capGroups;

+ (instancetype)manifestWithName:(NSString *)name
                         version:(NSString *)version
                         channel:(CSCartridgeChannel)channel
                     registryURL:(nullable NSString *)registryURL
                     description:(NSString *)description
                       capGroups:(NSArray<CSCapGroup *> *)capGroups;

+ (nullable instancetype)manifestWithDictionary:(NSDictionary * _Nonnull)dictionary
                                          error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(init(dictionary:));

- (CSCapManifest *)withAuthor:(NSString *)author;
- (CSCapManifest *)withPageUrl:(NSString *)pageUrl;

/**
 * Validate this manifest: it declares CAP_IDENTITY — identity is mandatory
 * in every capset — and every definition in it, in any group, passes the
 * definition rules. Identity alone being present is not enough.
 *
 * Swift automatically converts this to a throwing method.
 *
 * @param error If validation fails, contains the error description
 * @return YES if the manifest is valid
 */
- (BOOL)validate:(NSError **)error;

/** The manifest as the dictionary -manifestWithDictionary:error: reads. */
- (NSDictionary *)toDictionary;

/** Hold every definition in the manifest, in any group, to the definition rules. */
- (BOOL)validateDefinitions:(NSError **)error;

/**
 * Take a manifest another program advertised: parse it and hold every
 * definition in it to the definition rules, in one step. The two refusals
 * are told apart by the error's code: CSManifestLoadUnparseable for bytes
 * that are no manifest, CSManifestLoadInvalidDefinition for a manifest with
 * a definition that breaks a rule.
 */
+ (nullable instancetype)manifestFromAdvertisedData:(NSData * _Nonnull)data error:(NSError * _Nullable * _Nullable)error;

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