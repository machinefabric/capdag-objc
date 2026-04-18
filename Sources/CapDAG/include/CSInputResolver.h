//
//  CSInputResolver.h
//  CapDAG
//
//  InputResolver — Unified input resolution with pluggable media adapters
//
//  This module resolves mixed file/directory/glob inputs into a flat list of files
//  with detected media types, cardinality, and structure markers.
//
//  Mirrors Rust: capdag/src/input_resolver/
//

#import <Foundation/Foundation.h>
#import "CSCardinality.h"

@class CSMediaUrnRegistry;

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
    CSInputResolverErrorSymlinkCycle = 9
};

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

/// Detected media URN with list/record markers (e.g., "media:json;record;textable")
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
/// detects ambiguity at registration time (rejecting entire cap groups),
/// and maps file extensions to the cartridges that can inspect them.
@interface CSMediaAdapterRegistry : NSObject

/// Create a new empty registry with the given media URN registry.
/// No adapters are registered by default — cartridges register them
/// via registerCapGroup:adapterUrns:cartridgeId:error:.
- (instancetype)initWithMediaUrnRegistry:(CSMediaUrnRegistry *)mediaUrnRegistry;

/// Register a cap group's adapter URNs.
/// Checks each new adapter URN against ALL existing registered URNs.
/// If any pair has a conforms_to relationship in either direction,
/// the entire group is rejected.
/// @return YES on success, NO on conflict (error describes the conflict)
- (BOOL)registerCapGroup:(NSString *)groupName
             adapterUrns:(NSArray<NSString *> *)adapterUrns
             cartridgeId:(NSString *)cartridgeId
                   error:(NSError **)error;

/// Find adapters that can handle candidate URNs for a given file extension.
/// Returns array of cartridge IDs that have registered adapters matching.
- (NSArray<NSString *> *)cartridgeIdsForExtension:(NSString *)extension;

/// Quick check: does any registered adapter handle this extension?
- (BOOL)hasAdapterForExtension:(NSString *)extension;

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

/// Resolve a single input path to files
/// @param path Path to file, directory, or glob pattern
/// @param error Output: error if resolution fails
/// @return Resolved input set, or nil on error
CSResolvedInputSet * _Nullable CSInputResolverResolvePath(NSString *path, NSError **error);

/// Resolve multiple input paths to files
/// @param paths Array of paths (files, directories, or glob patterns)
/// @param error Output: error if resolution fails
/// @return Resolved input set, or nil on error
CSResolvedInputSet * _Nullable CSInputResolverResolvePaths(NSArray<NSString *> *paths, NSError **error);

/// Detect media type for a single file
/// @param path File path
/// @param structure Output: detected content structure
/// @param error Output: error if detection fails
/// @return Media URN string, or nil on error
NSString * _Nullable CSInputResolverDetectFile(NSString *path, CSContentStructure *structure, NSError **error);

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
