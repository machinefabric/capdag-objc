//
//  CSInputResolver.m
//  CapDAG
//
//  InputResolver — resolving a run's inputs (files, directories and globs) to
//  the files they name and what each of them is (CSDetectFileMedia).
//
//  Mirrors Rust: capdag/src/input_resolver/
//

#import "CSInputResolver.h"
#import "CSMediaUrn.h"
#import "CSFabricRegistry.h"
#import <glob.h>

NSErrorDomain const CSInputResolverErrorDomain = @"CSInputResolverErrorDomain";
NSString * const CSInputResolverPathKey = @"CSInputResolverPath";
NSString * const CSInputResolverExtensionKey = @"CSInputResolverExtension";

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

/// The content structure a media URN's list and record markers say.
/// Mirrors Rust: structure_from_marker_tags
static CSContentStructure CSStructureFromMarkerTags(CSMediaUrn *urn) {
    BOOL hasList = [urn isList];
    BOOL hasRecord = [urn isRecord];
    if (hasList && hasRecord) return CSContentStructureListRecord;
    if (hasList) return CSContentStructureListOpaque;
    if (hasRecord) return CSContentStructureScalarRecord;
    return CSContentStructureScalarOpaque;
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

@implementation CSDetection

+ (instancetype)detectionWithRegistry:(CSFabricRegistry *)registry
                             adapters:(id<CSAdapterSource>)adapters
                              invoker:(id<CSCartridgeAdapterInvoker>)invoker {
    CSDetection *detection = [[CSDetection alloc] init];
    detection->_registry = registry;
    detection->_adapters = adapters;
    detection->_invoker = invoker;
    return detection;
}

@end

void CSInputResolverResolveFile(NSString *path,
                                CSDetection *detection,
                                void (^completion)(CSResolvedFile *_Nullable file, NSError *_Nullable error)) {
    CSDetectFileMedia(path, detection.registry, detection.adapters, detection.invoker,
                      ^(CSFileMedia *found, NSError *error) {
        if (!found) {
            completion(nil, error);
            return;
        }
        NSString *mediaUrn = [found primary];
        NSError *parseError = nil;
        CSMediaUrn *urn = [CSMediaUrn fromString:mediaUrn error:&parseError];
        if (!urn) {
            completion(nil, [NSError errorWithDomain:CSInputResolverErrorDomain
                                                code:CSInputResolverErrorInspectionFailed
                                            userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Content inspection failed for %@: '%@' is no media URN: %@",
                                            path, mediaUrn, parseError.localizedDescription],
                CSInputResolverPathKey: path,
            }]);
            return;
        }
        completion([CSResolvedFile fileWithPath:found.path
                                       mediaUrn:mediaUrn
                                      sizeBytes:found.sizeBytes
                               contentStructure:CSStructureFromMarkerTags(urn)], nil);
    });
}

void CSInputResolverResolvePath(NSString *path,
                                CSDetection *detection,
                                void (^completion)(CSResolvedInputSet *_Nullable set, NSError *_Nullable error)) {
    CSInputResolverResolvePaths(@[path], detection, completion);
}

/// The input set of resolved files: a sequence when there is more than one,
/// and their common media when every file's media is equivalent.
static CSResolvedInputSet *CSInputSetOfFiles(NSArray<CSResolvedFile *> *files) {
    // is_sequence is determined solely by file count. Content structure
    // (list/record) describes what's inside a file, not cardinality.
    BOOL isSequence = files.count > 1;
    NSString *commonMedia = files.firstObject.mediaUrn;
    CSMediaUrn *first = commonMedia ? [CSMediaUrn fromString:commonMedia error:nil] : nil;
    for (CSResolvedFile *file in files) {
        CSMediaUrn *other = [CSMediaUrn fromString:file.mediaUrn error:nil];
        if (!first || !other || ![first isEquivalentTo:other]) {
            commonMedia = nil;
            break;
        }
    }
    return [CSResolvedInputSet setWithFiles:files isSequence:isSequence commonMedia:commonMedia];
}

/// Resolve the files from `index` on, one after another, then hand over the
/// set.
static void CSResolveFilesFrom(NSArray<NSString *> *filePaths, NSUInteger index, CSDetection *detection,
                               NSMutableArray<CSResolvedFile *> *resolved,
                               void (^completion)(CSResolvedInputSet *_Nullable set, NSError *_Nullable error)) {
    if (index == filePaths.count) {
        completion(CSInputSetOfFiles(resolved), nil);
        return;
    }
    CSInputResolverResolveFile(filePaths[index], detection, ^(CSResolvedFile *file, NSError *error) {
        if (!file) {
            completion(nil, error);
            return;
        }
        [resolved addObject:file];
        CSResolveFilesFrom(filePaths, index + 1, detection, resolved, completion);
    });
}

void CSInputResolverResolvePaths(NSArray<NSString *> *paths,
                                 CSDetection *detection,
                                 void (^completion)(CSResolvedInputSet *_Nullable set, NSError *_Nullable error)) {
    if (paths.count == 0) {
        completion(nil, [NSError errorWithDomain:CSInputResolverErrorDomain
                                            code:CSInputResolverErrorEmptyInput
                                        userInfo:@{NSLocalizedDescriptionKey: @"No input paths provided"}]);
        return;
    }
    NSError *error = nil;
    NSArray<NSString *> *filePaths = _resolvePaths(paths, &error);
    if (!filePaths) {
        completion(nil, error);
        return;
    }
    if (filePaths.count == 0) {
        completion(nil, [NSError errorWithDomain:CSInputResolverErrorDomain
                                            code:CSInputResolverErrorNoFilesResolved
                                        userInfo:@{NSLocalizedDescriptionKey: @"No files found in input paths"}]);
        return;
    }
    CSResolveFilesFrom(filePaths, 0, detection, [NSMutableArray arrayWithCapacity:filePaths.count], completion);
}
