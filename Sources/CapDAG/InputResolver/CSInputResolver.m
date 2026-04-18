//
//  CSInputResolver.m
//  CapDAG
//
//  InputResolver — Unified input resolution with pluggable media adapters
//
//  Mirrors Rust: capdag/src/input_resolver/
//

#import "CSInputResolver.h"
#import "CSMediaAdapters.h"
#import "CSMediaUrn.h"
#import "CSMediaUrnRegistry.h"
#import <glob.h>

NSErrorDomain const CSInputResolverErrorDomain = @"CSInputResolverErrorDomain";

#pragma mark - CSResolvedFile Implementation

@implementation CSResolvedFile

+ (instancetype)fileWithPath:(NSString *)path
                    mediaUrn:(NSString *)mediaUrn
                   sizeBytes:(uint64_t)sizeBytes
            contentStructure:(CSContentStructure)structure {
    CSResolvedFile *file = [[CSResolvedFile alloc] init];
    if (file) {
        file->_path = [path copy];
        file->_mediaUrn = [mediaUrn copy];
        file->_sizeBytes = sizeBytes;
        file->_contentStructure = structure;
    }
    return file;
}

- (BOOL)isList {
    return _contentStructure == CSContentStructureListOpaque ||
           _contentStructure == CSContentStructureListRecord;
}

- (BOOL)isRecord {
    return _contentStructure == CSContentStructureScalarRecord ||
           _contentStructure == CSContentStructureListRecord;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CSResolvedFile: %@ (%@) %llu bytes>",
            _path, _mediaUrn, _sizeBytes];
}

@end

#pragma mark - CSResolvedInputSet Implementation

@implementation CSResolvedInputSet

+ (instancetype)setWithFiles:(NSArray<CSResolvedFile *> *)files
                  isSequence:(BOOL)isSequence
                 commonMedia:(nullable NSString *)commonMedia {
    CSResolvedInputSet *set = [[CSResolvedInputSet alloc] init];
    if (set) {
        set->_files = [files copy];
        set->_isSequence = isSequence;
        set->_commonMedia = [commonMedia copy];
    }
    return set;
}

- (BOOL)isHomogeneous {
    return _commonMedia != nil;
}

- (uint64_t)totalSize {
    uint64_t total = 0;
    for (CSResolvedFile *file in _files) {
        total += file.sizeBytes;
    }
    return total;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CSResolvedInputSet: %lu files, isSequence=%@, common=%@>",
            (unsigned long)_files.count,
            _isSequence ? @"YES" : @"NO",
            _commonMedia ?: @"(none)"];
}

@end

#pragma mark - OS File Filter

/// Files that are always excluded (exact name match)
static NSSet<NSString *> *_excludedFiles = nil;

/// Directory names that are always excluded
static NSSet<NSString *> *_excludedDirs = nil;

/// File extensions that indicate temp files
static NSSet<NSString *> *_excludedExtensions = nil;

static void _initExclusionSets(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _excludedFiles = [NSSet setWithArray:@[
            // macOS
            @".DS_Store",
            @".localized",
            @".com.apple.timemachine.donotpresent",
            // Windows
            @"Thumbs.db",
            @"ehthumbs.db",
            @"ehthumbs_vista.db",
            @"desktop.ini",
            // Generic
            @".directory"
        ]];

        _excludedDirs = [NSSet setWithArray:@[
            // macOS system
            @".Spotlight-V100",
            @".Trashes",
            @".fseventsd",
            @".TemporaryItems",
            @"__MACOSX",
            // Version control
            @".git",
            @".svn",
            @".hg",
            @".bzr",
            @"_darcs",
            // IDE/Editor
            @".idea",
            @".vscode",
            @".vs",
            // Build directories
            @"node_modules",
            @"__pycache__",
            @".pytest_cache",
            @".mypy_cache",
            @"target",
            @"build",
            @"dist",
            @".build"
        ]];

        _excludedExtensions = [NSSet setWithArray:@[
            @"tmp",
            @"temp",
            @"swp",
            @"swo",
            @"bak"
        ]];
    });
}

BOOL CSInputResolverShouldExcludeFile(NSString *path) {
    _initExclusionSets();

    NSString *filename = [path lastPathComponent];

    // Exact name match
    if ([_excludedFiles containsObject:filename]) {
        return YES;
    }

    // macOS resource forks (._*)
    if ([filename hasPrefix:@"._"]) {
        return YES;
    }

    // Office lock files (~$*)
    if ([filename hasPrefix:@"~$"]) {
        return YES;
    }

    // Emacs/vim backup files (*~)
    if ([filename hasSuffix:@"~"]) {
        return YES;
    }

    // macOS custom folder icon (Icon\r)
    if ([filename isEqualToString:@"Icon\r"] || [filename isEqualToString:@"Icon"]) {
        // Check if it's the special icon file
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        if (attrs && [attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            // The Icon file has a special carriage return in the name
            if ([filename length] == 5 && [filename characterAtIndex:4] == '\r') {
                return YES;
            }
        }
    }

    // Temp file extensions
    NSString *ext = [[path pathExtension] lowercaseString];
    if ([_excludedExtensions containsObject:ext]) {
        return YES;
    }

    return NO;
}

BOOL CSInputResolverShouldExcludeDirectory(NSString *path) {
    _initExclusionSets();

    NSString *dirname = [path lastPathComponent];

    // Exact name match
    if ([_excludedDirs containsObject:dirname]) {
        return YES;
    }

    // Hidden directories (except known ones we might want to include)
    if ([dirname hasPrefix:@"."] && dirname.length > 1) {
        // Check against known exclusions
        if ([_excludedDirs containsObject:dirname]) {
            return YES;
        }
        // Don't automatically exclude all hidden dirs - some might be valid input
    }

    return NO;
}

#pragma mark - Path Utilities

BOOL CSInputResolverIsGlobPattern(NSString *path) {
    // Check for glob metacharacters: *, ?, [
    NSCharacterSet *globChars = [NSCharacterSet characterSetWithCharactersInString:@"*?["];
    return [path rangeOfCharacterFromSet:globChars].location != NSNotFound;
}

NSArray<NSString *> * _Nullable CSInputResolverExpandGlob(NSString *pattern, NSError **error) {
    glob_t globResult;
    int flags = GLOB_TILDE | GLOB_BRACE | GLOB_NOCHECK;

    const char *patternCStr = [pattern fileSystemRepresentation];
    int result = glob(patternCStr, flags, NULL, &globResult);

    if (result != 0 && result != GLOB_NOMATCH) {
        globfree(&globResult);
        if (error) {
            *error = [NSError errorWithDomain:CSInputResolverErrorDomain
                                         code:CSInputResolverErrorInvalidGlob
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid glob pattern: %@", pattern]
            }];
        }
        return nil;
    }

    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    for (size_t i = 0; i < globResult.gl_pathc; i++) {
        NSString *path = [fm stringWithFileSystemRepresentation:globResult.gl_pathv[i]
                                                         length:strlen(globResult.gl_pathv[i])];

        // Only include files, not directories
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && !isDir) {
            if (!CSInputResolverShouldExcludeFile(path)) {
                [paths addObject:path];
            }
        }
    }

    globfree(&globResult);
    return paths;
}

// CSMediaAdapterRegistry implementation has been moved to CSMediaAdapters.m.
// The registry now tracks cartridge-provided adapters via cap group registration.

// The following placeholder keeps the file structure intact while the old
// implementation block has been removed — see CSMediaAdapters.m

// OLD CSMediaAdapterRegistry implementation removed — see CSMediaAdapters.m
// The following is the remainder of the file starting at Path Resolution.
// Extension-based detection helper (sync, for preliminary UI queries)
static NSString * _Nullable _detectMediaUrnByExtension(NSString *path, CSContentStructure *structure) {
    NSString *ext = [[path pathExtension] lowercaseString];
    if (ext.length == 0) {
        if (structure) *structure = CSContentStructureScalarOpaque;
        return @"media:";
    }

    CSMediaUrnRegistry *registry = [CSMediaUrnRegistry shared];
    NSString *primaryUrn = [registry primaryMediaUrnForExtension:ext];
    if (!primaryUrn) {
        if (structure) *structure = CSContentStructureScalarOpaque;
        return @"media:";
    }

    // Derive structure from URN marker tags
    if (structure) {
        NSError *parseError = nil;
        CSMediaUrn *urn = [CSMediaUrn fromString:primaryUrn error:&parseError];
        if (urn) {
            BOOL hasList = [urn isList];
            BOOL hasRecord = [urn isRecord];
            if (hasList && hasRecord) {
                *structure = CSContentStructureListRecord;
            } else if (hasList) {
                *structure = CSContentStructureListOpaque;
            } else if (hasRecord) {
                *structure = CSContentStructureScalarRecord;
            } else {
                *structure = CSContentStructureScalarOpaque;
            }
        } else {
            *structure = CSContentStructureScalarOpaque;
        }
    }

    return primaryUrn;
}

#pragma mark - Path Resolution

/// Maximum depth for directory recursion
static const NSUInteger kMaxRecursionDepth = 64;

/// Maximum number of files to resolve
static const NSUInteger kMaxFiles = 100000;

static NSArray<NSString *> * _Nullable _enumerateDirectory(NSString *dirPath,
                                                            NSMutableSet<NSString *> *visited,
                                                            NSUInteger depth,
                                                            NSError **error) {
    if (depth > kMaxRecursionDepth) {
        if (error) {
            *error = [NSError errorWithDomain:CSInputResolverErrorDomain
                                         code:CSInputResolverErrorSymlinkCycle
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Maximum directory recursion depth exceeded"
            }];
        }
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];

    // Resolve symlinks and check for cycles
    NSString *resolvedPath = [[dirPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
    if ([visited containsObject:resolvedPath]) {
        // Cycle detected, skip silently
        return @[];
    }
    [visited addObject:resolvedPath];

    NSError *enumError = nil;
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:dirPath error:&enumError];
    if (enumError) {
        if (error) {
            *error = [NSError errorWithDomain:CSInputResolverErrorDomain
                                         code:CSInputResolverErrorPermissionDenied
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cannot read directory: %@", dirPath],
                NSUnderlyingErrorKey: enumError
            }];
        }
        return nil;
    }

    NSMutableArray<NSString *> *files = [NSMutableArray array];

    for (NSString *name in contents) {
        NSString *fullPath = [dirPath stringByAppendingPathComponent:name];

        BOOL isDir = NO;
        if (![fm fileExistsAtPath:fullPath isDirectory:&isDir]) {
            continue;
        }

        if (isDir) {
            // Check if directory should be excluded
            if (CSInputResolverShouldExcludeDirectory(fullPath)) {
                continue;
            }

            // Recurse
            NSArray<NSString *> *subFiles = _enumerateDirectory(fullPath, visited, depth + 1, error);
            if (!subFiles) {
                return nil;
            }
            [files addObjectsFromArray:subFiles];
        } else {
            // Check if file should be excluded
            if (CSInputResolverShouldExcludeFile(fullPath)) {
                continue;
            }

            [files addObject:fullPath];
        }

        if (files.count > kMaxFiles) {
            if (error) {
                *error = [NSError errorWithDomain:CSInputResolverErrorDomain
                                             code:CSInputResolverErrorIOError
                                         userInfo:@{
                    NSLocalizedDescriptionKey: @"Too many files in input"
                }];
            }
            return nil;
        }
    }

    return files;
}

static NSArray<NSString *> * _Nullable _resolvePaths(NSArray<NSString *> *paths, NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableSet<NSString *> *uniquePaths = [NSMutableSet set];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *visitedDirs = [NSMutableSet set];

    for (NSString *path in paths) {
        // Expand home directory
        NSString *expandedPath = [path stringByExpandingTildeInPath];

        // Check if glob pattern
        if (CSInputResolverIsGlobPattern(expandedPath)) {
            NSArray<NSString *> *expanded = CSInputResolverExpandGlob(expandedPath, error);
            if (!expanded) {
                return nil;
            }
            for (NSString *p in expanded) {
                NSString *canonical = [[p stringByResolvingSymlinksInPath] stringByStandardizingPath];
                if (![uniquePaths containsObject:canonical]) {
                    [uniquePaths addObject:canonical];
                    [result addObject:canonical];
                }
            }
            continue;
        }

        // Check if path exists
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:expandedPath isDirectory:&isDir]) {
            if (error) {
                *error = [NSError errorWithDomain:CSInputResolverErrorDomain
                                             code:CSInputResolverErrorNotFound
                                         userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path not found: %@", expandedPath]
                }];
            }
            return nil;
        }

        if (isDir) {
            // Enumerate directory recursively
            NSArray<NSString *> *dirFiles = _enumerateDirectory(expandedPath, visitedDirs, 0, error);
            if (!dirFiles) {
                return nil;
            }
            for (NSString *p in dirFiles) {
                NSString *canonical = [[p stringByResolvingSymlinksInPath] stringByStandardizingPath];
                if (![uniquePaths containsObject:canonical]) {
                    [uniquePaths addObject:canonical];
                    [result addObject:canonical];
                }
            }
        } else {
            // Single file
            if (CSInputResolverShouldExcludeFile(expandedPath)) {
                continue;
            }
            NSString *canonical = [[expandedPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
            if (![uniquePaths containsObject:canonical]) {
                [uniquePaths addObject:canonical];
                [result addObject:canonical];
            }
        }
    }

    return result;
}

#pragma mark - Main Resolution Functions

/// Size limit for content inspection (64KB)
static const NSUInteger kInspectionBufferSize = 65536;

CSResolvedInputSet * _Nullable CSInputResolverResolvePath(NSString *path, NSError **error) {
    return CSInputResolverResolvePaths(@[path], error);
}

CSResolvedInputSet * _Nullable CSInputResolverResolvePaths(NSArray<NSString *> *paths, NSError **error) {
    // Check for empty input
    if (paths.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSInputResolverErrorDomain
                                         code:CSInputResolverErrorEmptyInput
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"No input paths provided"
            }];
        }
        return nil;
    }

    // Resolve all paths to files
    NSArray<NSString *> *filePaths = _resolvePaths(paths, error);
    if (!filePaths) {
        return nil;
    }

    // Check if we got any files
    if (filePaths.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSInputResolverErrorDomain
                                         code:CSInputResolverErrorNoFilesResolved
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"No files found in input paths"
            }];
        }
        return nil;
    }

    // Detect media type for each file (extension-based, preliminary)
    NSMutableArray<CSResolvedFile *> *resolvedFiles = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSMutableSet<NSString *> *fileMediaUrns = [NSMutableSet set];

    for (NSString *filePath in filePaths) {
        // Get file size
        NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:nil];
        uint64_t fileSize = [attrs[NSFileSize] unsignedLongLongValue];

        // Detect media type by extension (preliminary, no content inspection)
        CSContentStructure structure = CSContentStructureScalarOpaque;
        NSString *mediaUrn = _detectMediaUrnByExtension(filePath, &structure);
        if (!mediaUrn) {
            return nil;
        }

        // Track media URN for homogeneity check (proper URN equivalence, not string splitting)
        [fileMediaUrns addObject:mediaUrn];

        CSResolvedFile *resolved = [CSResolvedFile fileWithPath:filePath
                                                       mediaUrn:mediaUrn
                                                      sizeBytes:fileSize
                                               contentStructure:structure];
        [resolvedFiles addObject:resolved];
    }

    // is_sequence is determined solely by file count.
    // Content structure (list/record) describes what's inside a file, not cardinality.
    BOOL isSequence = resolvedFiles.count > 1;

    // Determine common media type via proper URN equivalence.
    // If all files resolve to equivalent URNs, they share a common media type.
    NSString *commonMedia = nil;
    if (fileMediaUrns.count == 1) {
        commonMedia = [fileMediaUrns anyObject];
    } else if (fileMediaUrns.count > 1) {
        // Check all URNs for equivalence using CSMediaUrn
        NSArray<NSString *> *allUrns = [fileMediaUrns allObjects];
        CSMediaUrn *first = [CSMediaUrn fromString:allUrns[0] error:nil];
        BOOL allEquivalent = (first != nil);
        for (NSUInteger i = 1; i < allUrns.count && allEquivalent; i++) {
            CSMediaUrn *other = [CSMediaUrn fromString:allUrns[i] error:nil];
            if (!other || ![first isEquivalentTo:other]) {
                allEquivalent = NO;
            }
        }
        if (allEquivalent) {
            commonMedia = allUrns[0];
        }
    }

    return [CSResolvedInputSet setWithFiles:resolvedFiles
                                 isSequence:isSequence
                                commonMedia:commonMedia];
}

NSString * _Nullable CSInputResolverDetectFile(NSString *path, CSContentStructure *structure, NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Check file exists
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) {
        if (error) {
            *error = [NSError errorWithDomain:CSInputResolverErrorDomain
                                         code:CSInputResolverErrorNotFound
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File not found: %@", path]
            }];
        }
        return nil;
    }

    if (isDir) {
        if (error) {
            *error = [NSError errorWithDomain:CSInputResolverErrorDomain
                                         code:CSInputResolverErrorNotAFile
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path is a directory: %@", path]
            }];
        }
        return nil;
    }

    // Read content for inspection
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    // Detect media type by extension (preliminary, no content inspection)
    return _detectMediaUrnByExtension(path, structure);
}
