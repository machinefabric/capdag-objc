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
@property (nonatomic, strong) NSString *manifestDescription;
/// Cap groups — bundles of caps + adapter URNs. All caps must be in a cap group.
@property (nonatomic, strong) NSArray<CSCapGroup *> *capGroups;
@property (nonatomic, strong, nullable) NSString *author;
@property (nonatomic, strong, nullable) NSString *pageUrl;

- (instancetype)initWithName:(NSString *)name
                     version:(NSString *)version
          manifestDescription:(NSString *)manifestDescription
               capGroups:(NSArray<CSCapGroup *> *)capGroups;

+ (instancetype)manifestWithName:(NSString *)name
                         version:(NSString *)version
                     description:(NSString *)description
                       capGroups:(NSArray<CSCapGroup *> *)capGroups;

+ (instancetype)manifestWithDictionary:(NSDictionary * _Nonnull)dictionary 
                                 error:(NSError * _Nullable * _Nullable)error 
    NS_SWIFT_NAME(init(dictionary:error:));

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