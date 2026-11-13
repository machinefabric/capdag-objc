//
//  CSInputResolver.h
//  CapDAG
//
//  InputResolver — resolving a run's inputs (files, directories and globs) to
//  the files they name and what each of them is.
//
//  What a file is comes from the one detection every host runs
//  (CSDetectFileMedia, CSFileMediaDetection.h); this module adds the path
//  resolution around it and the shape of the result.
//
//  Mirrors Rust: capdag/src/input_resolver/
//

#import <Foundation/Foundation.h>
#import "CSCardinality.h"
#import "CSFileMediaDetection.h"

@class CSFabricRegistry;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Error Domain

FOUNDATION_EXPORT NSErrorDomain const CSInputResolverErrorDomain;

typedef NS_ERROR_ENUM(CSInputResolverErrorDomain, CSInputResolverError) {
    /// Path does not exist
    CSInputResolverErrorNotFound = 1,
    /// Path is not a file (e.g., socket, device)
    CSInputResolverErrorNotAFile = 2,
    /// Permission denied accessing path
    CSInputResolverErrorPermissionDenied = 3,
    /// Invalid glob pattern
    CSInputResolverErrorInvalidGlob = 4,
    /// IO error during resolution
    CSInputResolverErrorIOError = 5,
    /// Content inspection failed
    CSInputResolverErrorInspectionFailed = 6,
    /// Empty input (no paths provided)
    CSInputResolverErrorEmptyInput = 7,
    /// All paths resolved to zero files
    CSInputResolverErrorNoFilesResolved = 8,
    /// Symlink cycle detected
    CSInputResolverErrorSymlinkCycle = 9,
    /// The file has no extension to tell its type from
    CSInputResolverErrorNoExtension = 10,
    /// The fabric declares no file media type for the file's extension
    /// (the extension is under CSInputResolverExtensionKey)
    CSInputResolverErrorUnknownExtension = 11,
    /// The fabric's file media types could not be loaded (the registry's
    /// error is under NSUnderlyingErrorKey)
    CSInputResolverErrorFabricUnavailable = 12
};

/// userInfo key of a CSInputResolverErrorDomain error about one file: its path
/// (NSString).
FOUNDATION_EXPORT NSString * const CSInputResolverPathKey;

/// userInfo key of a CSInputResolverErrorUnknownExtension error: the file's
/// extension, lowercased (NSString).
FOUNDATION_EXPORT NSString * const CSInputResolverExtensionKey;

#pragma mark - Content Structure

/// Content structure classification
/// Mirrors Rust: ContentStructure enum
typedef NS_ENUM(NSInteger, CSContentStructure) {
    /// Single value, no internal structure (e.g., PDF, PNG, single JSON primitive)
    CSContentStructureScalarOpaque = 0,
    /// Single value with key-value structure (e.g., JSON object, TOML)
    CSContentStructureScalarRecord = 1,
    /// Multiple values, no internal structure per item (e.g., array of primitives)
    CSContentStructureListOpaque = 2,
    /// Multiple values, each with key-value structure (e.g., CSV with headers, NDJSON of objects)
    CSContentStructureListRecord = 3
};

// CSInputCardinality is defined in CSCardinality.h

#pragma mark - Resolved File

/// A single resolved file with detected media type
/// Mirrors Rust: ResolvedFile struct
@interface CSResolvedFile : NSObject

/// Absolute path to the file
@property (nonatomic, copy, readonly) NSString *path;

/// Detected media URN with list/record markers (e.g., "media:enc=utf8;fmt=json;record")
@property (nonatomic, copy, readonly) NSString *mediaUrn;

/// File size in bytes
@property (nonatomic, readonly) uint64_t sizeBytes;

/// Detected content structure
@property (nonatomic, readonly) CSContentStructure contentStructure;

/// Create a resolved file
+ (instancetype)fileWithPath:(NSString *)path
                    mediaUrn:(NSString *)mediaUrn
                   sizeBytes:(uint64_t)sizeBytes
            contentStructure:(CSContentStructure)structure;

/// Check if this file has list content
- (BOOL)isList;

/// Check if this file has record structure
- (BOOL)isRecord;

@end

#pragma mark - Resolved Input Set

/// The result of resolving input paths
/// Mirrors Rust: ResolvedInputSet struct
@interface CSResolvedInputSet : NSObject

/// All resolved files
@property (nonatomic, copy, readonly) NSArray<CSResolvedFile *> *files;

/// Whether the input is a sequence (multiple files).
/// Determined solely by file count — content structure is irrelevant.
@property (nonatomic, readonly) BOOL isSequence;

/// Common media type if all files share the same base type, nil otherwise
@property (nonatomic, copy, readonly, nullable) NSString *commonMedia;

/// Create a resolved input set
+ (instancetype)setWithFiles:(NSArray<CSResolvedFile *> *)files
                  isSequence:(BOOL)isSequence
                 commonMedia:(nullable NSString *)commonMedia;

/// Check if all files share the same media type
- (BOOL)isHomogeneous;

/// Get total size of all files
- (uint64_t)totalSize;

@end

#pragma mark - Media Adapter Registry

/// Registry of cartridge-provided content inspection adapters.
///
/// Tracks which cartridges have registered adapter URNs for content inspection,
/// detects ambiguity at registration time (rejecting entire cap groups), and
/// names the cartridges to consult for a file's candidates (it is a host's
/// CSAdapterSource).
@interface CSMediaAdapterRegistry : NSObject <CSAdapterSource>

/// Create a new empty registry with the given media URN registry.
/// No adapters are registered by default — cartridges register them
/// via registerCapGroup:adapterUrns:cartridgeId:error:.
- (instancetype)initWithFabricRegistry:(CSFabricRegistry *)mediaUrnRegistry;

/// Register a cap group's adapter URNs.
/// Checks each new adapter URN against ALL existing registered URNs.
/// If any pair has a conforms_to relationship in either direction,
/// the entire group is rejected.
/// Exact re-registration is IDEMPOTENT: an adapter URN equivalent to one
/// this same (cartridgeId, groupName) already registered is neither a
/// conflict nor a second row — a cartridge attached through more than one
/// hosting route (e.g. app-bundled and system-installed) is still one
/// adapter provider, not an ambiguity with itself. The skip is logged.
/// @return YES on success, NO on conflict (error describes the conflict)
- (BOOL)registerCapGroup:(NSString *)groupName
             adapterUrns:(NSArray<NSString *> *)adapterUrns
             cartridgeId:(NSString *)cartridgeId
                   error:(NSError **)error;

/// The number of registered adapter rows (tests/diagnostics).
@property (nonatomic, readonly) NSUInteger registeredAdapterCount;

/// The registered adapters some of these candidates conform to, one per
/// cartridge, in registration order.
- (NSArray<CSCartridgeAdapter *> *)adaptersForCandidates:(NSArray<CSMediaUrn *> *)candidates;

/// The adapters of the file media types the fabric declares for an extension
/// (-[CSFabricRegistry fileMediaForExtension:completion:]), one per cartridge.
/// The completion gets the registry's error when the file types cannot be
/// loaded, or a definition has no valid URN.
- (void)findAdaptersForExtension:(NSString *)extension
                      completion:(void (^)(NSArray<CSCartridgeAdapter *> *_Nullable adapters,
                                           NSError *_Nullable error))completion;

/// Whether any registered adapter covers a file media type the fabric declares
/// for the extension. Errors as findAdaptersForExtension:completion:'s.
- (void)hasAdapterForExtension:(NSString *)extension
                    completion:(void (^)(BOOL hasAdapter, NSError *_Nullable error))completion;

@end

#pragma mark - OS File Filter

/// Check if a file should be excluded from input resolution
/// @param path File path to check
/// @return YES if the file is an OS artifact that should be excluded
BOOL CSInputResolverShouldExcludeFile(NSString *path);

/// Check if a directory should be excluded from recursive enumeration
/// @param path Directory path to check
/// @return YES if the directory should not be traversed
BOOL CSInputResolverShouldExcludeDirectory(NSString *path);

#pragma mark - Input Resolution Functions

/// How a host detects its inputs: its fabric and the cartridges it can ask.
/// Mirrors Rust: Detection
@interface CSDetection : NSObject

@property (nonatomic, strong, readonly) CSFabricRegistry *registry;
@property (nonatomic, strong, readonly) id<CSAdapterSource> adapters;
@property (nonatomic, strong, readonly) id<CSCartridgeAdapterInvoker> invoker;

+ (instancetype)detectionWithRegistry:(CSFabricRegistry *)registry
                             adapters:(id<CSAdapterSource>)adapters
                              invoker:(id<CSCartridgeAdapterInvoker>)invoker;

@end

/// What one file is, as a run's input: the media a host that cannot ask takes
/// (CSPrimaryMedia of CSDetectFileMedia's answer), with the content structure
/// its list and record markers say. Mirrors Rust: resolve_file
void CSInputResolverResolveFile(NSString *path,
                                CSDetection *detection,
                                void (^completion)(CSResolvedFile *_Nullable file, NSError *_Nullable error));

/// Resolve one input path (a file, a directory or a glob) to the files it
/// names and what each is. Mirrors Rust: resolve_input
void CSInputResolverResolvePath(NSString *path,
                                CSDetection *detection,
                                void (^completion)(CSResolvedInputSet *_Nullable set, NSError *_Nullable error));

/// Resolve input paths (a file, a directory or a glob each) to the files they
/// name and what each is, in order. The first file whose type cannot be told
/// fails the whole set with its error. Mirrors Rust: resolve_paths
void CSInputResolverResolvePaths(NSArray<NSString *> *paths,
                                 CSDetection *detection,
                                 void (^completion)(CSResolvedInputSet *_Nullable set, NSError *_Nullable error));

#pragma mark - Path Utilities

/// Check if a path contains glob metacharacters
/// @param path Path to check
/// @return YES if path contains *, ?, or [
BOOL CSInputResolverIsGlobPattern(NSString *path);

/// Expand a glob pattern to matching file paths
/// @param pattern Glob pattern
/// @param error Output: error if expansion fails
/// @return Array of matching paths, or nil on error
NSArray<NSString *> * _Nullable CSInputResolverExpandGlob(NSString *pattern, NSError **error);

NS_ASSUME_NONNULL_END
