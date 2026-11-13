//
//  CSFabricRegistry.m
//  CapDAG
//
//  Unified registry implementation. Replaces the previous split between
//  a cap-only registry and a media-only registry. Holds:
//
//    - cachedCaps: in-memory map of normalised cap URN → CSCap.
//    - cachedSpecs: in-memory map of normalised media URN → spec dict.
//    - fileMediaIndex: lowercase extension → the file media definitions
//      (those whose URN carries the `ext=` tag) of the whole pinned manifest
//      that list it, loaded the first time a file's type is asked.
//    - cachedAliases / cachedDims: name → stored alias / dim, versioned-only.
//
//  Atomic cap fetch: getCapWithUrn: refuses to cache a cap until every
//  media URN it references has also been successfully fetched. The bare
//  `media:` wildcard is excluded from the recursive fetch.
//
//  A cap or media def is likewise cached only once every dim it names
//  (`dims`) is cached, at the version the manifest pins, with the value it
//  names (ensureDimsCached:owner:completion:).
//

#import "CSFabricRegistry.h"
#import "CSCharter.h"
#import "CSCapValidator.h"
#import "CSFabricManifestVersion.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSMediaUrn.h"
#import "CSDim.h"
#import <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

NSErrorDomain const CSFabricRegistryErrorDomain = @"CSFabricRegistryError";
NSString * const CSFabricFetchWhatKey = @"CSFabricFetchWhat";
NSString * const CSFabricFetchURLKey = @"CSFabricFetchURL";
NSString * const CSFabricFetchManifestVersionKey = @"CSFabricFetchManifestVersion";
NSString * const CSFabricFetchCauseKey = @"CSFabricFetchCause";
NSString * const CSFabricFetchStatusKey = @"CSFabricFetchStatus";

static NSError *CSRegistryError(NSInteger code, NSString *message, NSError *_Nullable underlying) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:CSFabricRegistryErrorDomain code:code userInfo:info];
}

/// What one fetch from the registry came to, when it brought back no body:
/// nil for a success; NotFound for 404 or 410, the registry's answer that it
/// does not hold the object; and FetchFailed, carrying what was fetched, the
/// URL, the manifest version and the cause, for any other status and for a
/// fetch that got no answer. A refused fetch is never reported as missing.
static NSError *_Nullable CSFetchOutcome(NSString *what, NSString *urlString, uint32_t manifestVersion,
                                         NSURLResponse *_Nullable response, NSError *_Nullable transportError) {
    NSMutableDictionary *info = [@{
        CSFabricFetchWhatKey: what,
        CSFabricFetchURLKey: urlString,
        CSFabricFetchManifestVersionKey: @(manifestVersion),
    } mutableCopy];
    if (transportError) {
        BOOL timedOut = [transportError.domain isEqualToString:NSURLErrorDomain] && transportError.code == NSURLErrorTimedOut;
        info[CSFabricFetchCauseKey] = timedOut ? @"timed_out" : @"transport";
        info[NSUnderlyingErrorKey] = transportError;
        info[NSLocalizedDescriptionKey] = timedOut
            ? [NSString stringWithFormat:@"the registry did not answer the fetch of %@ for fabric manifest v%u: the request to %@ timed out",
                  what, manifestVersion, urlString]
            : [NSString stringWithFormat:@"the fetch of %@ for fabric manifest v%u from %@ failed: %@",
                  what, manifestVersion, urlString, transportError.localizedDescription];
        return [NSError errorWithDomain:CSFabricRegistryErrorDomain code:CSFabricRegistryErrorFetchFailed userInfo:info];
    }
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (status >= 200 && status < 300) return nil;
    if (status == 404 || status == 410) {
        return CSRegistryError(CSFabricRegistryErrorNotFound, [NSString stringWithFormat:
            @"the registry has no %@ for fabric manifest v%u (HTTP %ld from %@)", what, manifestVersion, (long)status, urlString], nil);
    }
    info[CSFabricFetchCauseKey] = @"status";
    info[CSFabricFetchStatusKey] = @(status);
    info[NSLocalizedDescriptionKey] = [NSString stringWithFormat:
        @"the registry refused the fetch of %@ for fabric manifest v%u: HTTP %ld %@ from %@",
        what, manifestVersion, (long)status, [NSHTTPURLResponse localizedStringForStatusCode:status], urlString];
    return [NSError errorWithDomain:CSFabricRegistryErrorDomain code:CSFabricRegistryErrorFetchFailed userInfo:info];
}

// The anchor of MachineFabric's production fabric, used when nothing names
// another. Only the anchor: where its objects are is read from its charter.
static NSString * const DEFAULT_FABRIC_ANCHOR = @"https://fabric.capdag.com";
// How long a defver-0 entry is kept, in whole hours: cache entries carry it,
// and `cached_at`, as integers, as every capdag library writes them.
static const uint64_t CACHE_DURATION_HOURS = 24;
static const NSTimeInterval HTTP_TIMEOUT_SECONDS = 10.0;

// MARK: - CSFabricRegistryConfig

@implementation CSFabricRegistryConfig

+ (instancetype)defaultConfig {
    NSString *anchor = [[NSProcessInfo processInfo] environment][@"CDG_FABRIC_REGISTRY_URL"];
    return [self configWithAnchor:anchor.length > 0 ? anchor : DEFAULT_FABRIC_ANCHOR];
}

+ (instancetype)configWithAnchor:(NSString *)anchor {
    CSFabricRegistryConfig *config = [[CSFabricRegistryConfig alloc] init];
    config.anchor = anchor;
    return config;
}

@end

// MARK: - Alias primitives (free functions)

BOOL CSTokenIsURN(NSString *token) {
    return [token rangeOfString:@":"].location != NSNotFound;
}

BOOL CSIsAliasToken(NSString *token) {
    return !CSTokenIsURN(token);
}

NSString *_Nullable CSNormalizeAliasName(NSString *name, NSError *_Nullable *_Nullable error) {
    NSError *(^mk)(NSString *) = ^NSError *(NSString *msg) {
        return [NSError errorWithDomain:@"CSFabricRegistryError"
                                   code:1020
                               userInfo:@{NSLocalizedDescriptionKey: msg}];
    };
    if (name.length == 0) {
        if (error) *error = mk(@"alias name is empty");
        return nil;
    }
    if ([name rangeOfString:@":"].location != NSNotFound) {
        if (error) *error = mk([NSString stringWithFormat:
            @"alias name '%@' contains ':' — aliases must never look like a tagged URN", name]);
        return nil;
    }
    if ([name rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
        if (error) *error = mk([NSString stringWithFormat:@"alias name '%@' contains whitespace", name]);
        return nil;
    }
    NSString *lowered = [name lowercaseString];
    static NSCharacterSet *allowed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"abcdefghijklmnopqrstuvwxyz0123456789._-"];
    });
    NSCharacterSet *disallowed = [allowed invertedSet];
    if ([lowered rangeOfCharacterFromSet:disallowed].location != NSNotFound) {
        if (error) *error = mk([NSString stringWithFormat:
            @"alias name '%@' contains invalid characters; allowed: lowercase letters, digits, '.', '_', '-'", name]);
        return nil;
    }
    return lowered;
}

BOOL CSClassifyAliasTarget(NSString *target, CSAliasTargetKind *_Nullable outKind) {
    NSError *e = nil;
    if ([CSCapUrn fromString:target error:&e]) {
        if (outKind) *outKind = CSAliasTargetKindCap;
        return YES;
    }
    e = nil;
    if ([CSMediaUrn fromString:target error:&e]) {
        if (outKind) *outKind = CSAliasTargetKindMedia;
        return YES;
    }
    return NO;
}

// MARK: - The disk cache
//
// Where a fabric registry's definitions are kept on disk, and how an entry is
// written and read there. Mirrors the reference's `fabric::cache` module.
//
// The cache is shared: every capdag process on a machine that reads the same
// fabric reads and writes the same folder, and they run at once. Two rules
// follow.
//
// - One folder per fabric manifest version. A registry pinned at manifest N
//   keeps everything under `<registry folder>/v<N>/`:
//
//     <caches>/capdag/<charter slug>/          the registry's folder; its charter
//       v<N>/manifest.json                     manifest N, as the registry served it
//       v<N>/file_types.json                   which of manifest N's media are file types, worked
//                                              out once from manifest.json (and its hash)
//       v<N>/caps/<sha256 of URN>/<defver>.json
//       v<N>/media/<sha256 of URN>/<defver>.json
//       v<N>/aliases/<sha256 of name>/<defver>.json
//       v<N>/dims/<sha256 of name>/<defver>.json
//
//   capdag releases built against different manifests can be installed side
//   by side; each reads and writes only its own `v<N>`.
//
// - An entry is replaced whole. It is written to a temporary file in the
//   folder it belongs in (`.<entry>.<pid>-<n>.tmp`) and renamed over the entry
//   with rename(2), which replaces the name in one step, so a reader sees the
//   old entry or the new one, never part of one. A temporary file a killed
//   writer left behind is never read, and clearing the cache removes it.
//
// An entry that is there and cannot be read, or does not parse, or is not the
// definition its path names, is corrupt: an error naming the file, never
// treated as missing, and never deleted.
//
// Before this layout, every manifest version shared the registry's folder
// (`<charter slug>/{caps,media,aliases,dims,manifests}`). This library neither
// reads nor writes those folders; clearing the cache removes them.

/// The name of the exception a registry's construction raises when its disk
/// cache cannot be used: a corrupt entry or manifest, or a folder or file that
/// cannot be made. Its reason is the error's message, and its userInfo holds
/// the NSError under NSUnderlyingErrorKey.
static NSString * const CSFabricRegistryCacheErrorException = @"CSFabricRegistryCacheError";

/// The folders a manifest version's definitions live in, one per kind.
static NSArray<NSString *> *CSFabricCacheKindFolders(void) {
    return @[@"caps", @"media", @"aliases", @"dims"];
}

/// The file a manifest version's manifest is kept in, in its folder.
static NSString * const CSFabricCacheManifestFile = @"manifest.json";

/// The file the file types a manifest version's manifest names are kept in,
/// in its folder: which of its media definitions carry the `ext=` tag, with
/// the hash of the manifest file they were worked out from.
static NSString * const CSFabricCacheFileTypesFile = @"file_types.json";

/// How many file media definitions are fetched at once when the file media
/// index loads on a cold cache.
static const NSUInteger CSFileMediaFetchesAtOnce = 16;

/// The folders the shared layout before this one kept in a registry's folder.
/// Nothing reads them; clearing the cache removes them.
static NSArray<NSString *> *CSFabricCacheLegacyFolders(void) {
    return @[@"caps", @"media", @"aliases", @"dims", @"manifests"];
}

/// The sha256 of `data`, in lowercase hex.
static NSString *CSSha256HexOfData(NSData *data) {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [out appendFormat:@"%02x", digest[i]];
    }
    return out;
}

/// The hash a definition is filed under, in the cache as in the registry.
static NSString *CSSha256Hex(NSString *s) {
    return CSSha256HexOfData([s dataUsingEncoding:NSUTF8StringEncoding]);
}

static NSError *CSCacheError(NSString *message, NSError *_Nullable underlying) {
    return CSRegistryError(CSFabricRegistryErrorCache, message, underlying);
}

/// The error for a cache entry that is there and is not what its path says.
/// `what` names the kind of entry: cap, media def, alias, dim or manifest.
static NSError *CSCacheCorrupt(NSString *path, NSString *what, NSString *detail) {
    return CSCacheError([NSString stringWithFormat:
        @"the cached %@ %@ is corrupt: %@; remove the file, or run `capdag cache clear`", what, path, detail], nil);
}

/// Whether `error`, or any error under it, is the POSIX error `code`.
static BOOL CSErrorChainHasPOSIXCode(NSError *_Nullable error, int code) {
    for (NSError *e = error; e != nil; e = e.userInfo[NSUnderlyingErrorKey]) {
        if ([e.domain isEqualToString:NSPOSIXErrorDomain] && e.code == code) return YES;
    }
    return NO;
}

/// Whether `error` says the file or folder is not there.
static BOOL CSIsNoSuchFile(NSError *_Nullable error) {
    for (NSError *e = error; e != nil; e = e.userInfo[NSUnderlyingErrorKey]) {
        if ([e.domain isEqualToString:NSCocoaErrorDomain]
            && (e.code == NSFileNoSuchFileError || e.code == NSFileReadNoSuchFileError)) {
            return YES;
        }
    }
    return CSErrorChainHasPOSIXCode(error, ENOENT);
}

/// Whether there is a folder at `path` (NO when there is nothing, or a file).
static BOOL CSIsFolder(NSString *path) {
    BOOL isFolder = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isFolder] && isFolder;
}

/// Make the folder `path` and its parents. A folder a peer made at the same
/// moment is the folder wanted: what counts is that it is there afterwards.
/// The error says what could not be made, and why.
static BOOL CSMakeFolder(NSString *path, NSError *_Nullable *_Nullable error) {
    NSError *makeError = nil;
    if ([[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES
                                                   attributes:nil error:&makeError]
        || CSIsFolder(path)) {
        return YES;
    }
    if (error) *error = makeError;
    return NO;
}

/// Tells apart the temporary files one process writes at once.
static _Atomic uint64_t CSFabricCacheTemporaryFiles = 0;

/// Put `bytes` at `path` whole: written to a temporary file beside it, then
/// renamed over it with rename(2). A reader opening `path` meanwhile reads
/// what was there before, or `bytes`, never part of them. The folder is made
/// when missing. On failure the temporary file is removed and the error names
/// the path.
///
/// rename(2) rather than -[NSData writeToFile:atomically:]: the temporary file
/// must be in the entry's own folder, under a name that says whose it is, so
/// that the replacement is one rename on one volume and a temporary file a
/// killed writer leaves is recognisable; Foundation chooses neither the folder
/// nor the name of its own.
static BOOL CSWriteCacheFileAtomically(NSString *path, NSData *bytes, NSError *_Nullable *_Nullable error) {
    NSString *folder = [path stringByDeletingLastPathComponent];
    NSString *name = [path lastPathComponent];
    if (folder.length == 0 || name.length == 0 || [name isEqualToString:@"/"]) {
        if (error) *error = CSCacheError([NSString stringWithFormat:@"the cache file %@ has no folder", path], nil);
        return NO;
    }
    NSError *folderError = nil;
    if (!CSMakeFolder(folder, &folderError)) {
        if (error) *error = CSCacheError([NSString stringWithFormat:@"failed to create the cache folder %@: %@",
                                          folder, folderError.localizedDescription], folderError);
        return NO;
    }
    NSString *temporary = [folder stringByAppendingPathComponent:
        [NSString stringWithFormat:@".%@.%d-%llu.tmp", name, (int)getpid(),
         (unsigned long long)atomic_fetch_add(&CSFabricCacheTemporaryFiles, 1)]];
    NSError *writeError = nil;
    if (![bytes writeToFile:temporary options:0 error:&writeError]) {
        unlink(temporary.fileSystemRepresentation);
        if (error) *error = CSCacheError([NSString stringWithFormat:@"failed to write the cache file %@: %@",
                                          temporary, writeError.localizedDescription], writeError);
        return NO;
    }
    if (rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        int code = errno;
        unlink(temporary.fileSystemRepresentation);
        NSError *posix = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
        if (error) *error = CSCacheError([NSString stringWithFormat:@"failed to put the cache file %@ in place: %s",
                                          path, strerror(code)], posix);
        return NO;
    }
    return YES;
}

/// The cache file at `path`, as a JSON object. Answers YES with *outObject nil
/// when there is none, YES with the object when it parses as one, and NO with
/// an error naming the file when it is there and cannot be read or is not a
/// JSON object. `what` names the kind of entry in the error.
static BOOL CSReadCacheFile(NSString *path, NSString *what,
                            NSDictionary *_Nullable *_Nonnull outObject,
                            NSError *_Nullable *_Nullable error) {
    *outObject = nil;
    NSError *readError = nil;
    NSData *bytes = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    if (!bytes) {
        if (CSIsNoSuchFile(readError)) return YES;
        if (error) *error = CSCacheError([NSString stringWithFormat:@"the cached %@ %@ cannot be read: %@",
                                          what, path, readError.localizedDescription], readError);
        return NO;
    }
    NSError *parseError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:&parseError];
    if (!json) {
        if (error) *error = CSCacheCorrupt(path, what, parseError.localizedDescription ?: @"it is not JSON");
        return NO;
    }
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) *error = CSCacheCorrupt(path, what, @"it is not a JSON object");
        return NO;
    }
    *outObject = json;
    return YES;
}

/// The body of the cache entry `entry` (`{"<bodyKey>": {...}, "cached_at": <s>,
/// "ttl_hours": <h>}`), or nil with `*detail` saying what is wrong with it.
static NSDictionary *_Nullable CSCacheEntryBody(NSDictionary *entry, NSString *bodyKey, NSString *_Nullable *_Nonnull detail) {
    for (NSString *field in @[@"cached_at", @"ttl_hours"]) {
        if (![entry[field] isKindOfClass:[NSNumber class]]) {
            *detail = [NSString stringWithFormat:@"its '%@' is %@", field, entry[field] ? @"not a number" : @"missing"];
            return nil;
        }
    }
    id body = entry[bodyKey];
    if (![body isKindOfClass:[NSDictionary class]]) {
        *detail = [NSString stringWithFormat:@"its '%@' is %@", bodyKey, body ? @"not an object" : @"missing"];
        return nil;
    }
    return body;
}

/// Whether a cache entry is older than its time to live. Only a defver-0
/// definition (the flat, mutable regime) is held to it.
static BOOL CSCacheEntryIsExpired(NSDictionary *entry) {
    double cachedAt = [entry[@"cached_at"] doubleValue];
    double ttlHours = [entry[@"ttl_hours"] doubleValue];
    return [[NSDate date] timeIntervalSince1970] > cachedAt + ttlHours * 3600.0;
}

/// Remove one file or folder of the shared cache, which a peer may be removing
/// or refilling at the same moment. Already gone is the outcome either way;
/// "not empty" or "busy" means a peer refilled it, and the entries now there
/// are exactly what a refresh was for. Anything else is an error naming it.
static BOOL CSRemoveShared(NSString *path, NSError *_Nullable *_Nullable error) {
    NSError *removeError = nil;
    if ([[NSFileManager defaultManager] removeItemAtPath:path error:&removeError]) return YES;
    if (CSIsNoSuchFile(removeError)
        || CSErrorChainHasPOSIXCode(removeError, ENOTEMPTY)
        || CSErrorChainHasPOSIXCode(removeError, EBUSY)) {
        return YES;
    }
    if (error) *error = CSCacheError([NSString stringWithFormat:@"Failed to remove %@: %@",
                                      path, removeError.localizedDescription], removeError);
    return NO;
}

/// Remove everything in `folder`, which peers are clearing and filling at the
/// same time (CSRemoveShared).
static BOOL CSRemoveContents(NSString *folder, NSError *_Nullable *_Nullable error) {
    NSError *listError = nil;
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:&listError];
    if (!names) {
        // A peer removed it between the create and the read. It is empty by
        // any reading, which is what was wanted.
        if (CSIsNoSuchFile(listError)) return YES;
        if (error) *error = CSCacheError([NSString stringWithFormat:@"Failed to read cache directory %@: %@",
                                          folder, listError.localizedDescription], listError);
        return NO;
    }
    for (NSString *name in names) {
        if (!CSRemoveShared([folder stringByAppendingPathComponent:name], error)) return NO;
    }
    return YES;
}

/// What makes `manifest` not one this library reads, or nil when it is: the
/// `dims` map (dim name -> defver) is required, and `caps`, `media` and
/// `aliases`, when present, map names to defvers.
static NSError *_Nullable CSManifestRefusal(NSDictionary *manifest) {
    id dims = manifest[@"dims"];
    if (![dims isKindOfClass:[NSDictionary class]]) {
        return CSRegistryError(CSFabricRegistryErrorManifestInvalid, [NSString stringWithFormat:
            @"manifest v%@ %@ 'dims' map (dim name -> defver); every manifest names the dims of its snapshot",
            manifest[@"version"], dims ? @"has a malformed" : @"has no"], nil);
    }
    for (NSString *field in @[@"caps", @"media", @"aliases", @"dims"]) {
        id map = manifest[field];
        if (map == nil) continue;
        if (![map isKindOfClass:[NSDictionary class]]) {
            return CSRegistryError(CSFabricRegistryErrorManifestInvalid, [NSString stringWithFormat:
                @"manifest v%@ '%@' is not a map of names to defvers", manifest[@"version"], field], nil);
        }
        for (id name in (NSDictionary *)map) {
            id defver = ((NSDictionary *)map)[name];
            if (![name isKindOfClass:[NSString class]] || ![defver isKindOfClass:[NSNumber class]]) {
                return CSRegistryError(CSFabricRegistryErrorManifestInvalid, [NSString stringWithFormat:
                    @"manifest v%@ '%@' entry '%@' is not %@ mapped to a defver", manifest[@"version"], field, name,
                    [field isEqualToString:@"dims"] ? @"a dim name" : @"a name"], nil);
            }
        }
    }
    return nil;
}

// MARK: - The file types of a manifest

/// The media definitions of a manifest (`media`: URN → defver, of manifest
/// `manifestVersion`) that are file types: those whose URN carries the `ext=`
/// file-type tag, each as `@[URN, defver]`, in URN order. A manifest entry
/// that is no media URN is a FileTypes error naming the manifest version and
/// the entry. Mirrors Rust `derive_file_types`.
static NSArray<NSArray *> *_Nullable CSDeriveFileTypes(NSDictionary<NSString *, NSNumber *> *media,
                                                       uint32_t manifestVersion,
                                                       NSError *_Nullable *_Nullable error) {
    NSMutableArray<NSArray *> *fileTypes = [NSMutableArray array];
    for (NSString *urn in media) {
        NSError *parseError = nil;
        CSMediaUrn *parsed = [CSMediaUrn fromString:urn error:&parseError];
        if (!parsed) {
            if (error) *error = CSRegistryError(CSFabricRegistryErrorFileTypes, [NSString stringWithFormat:
                @"manifest v%u names '%@' as a media definition, and it is no media URN: %@",
                manifestVersion, urn, parseError.localizedDescription ?: @"it does not parse"], parseError);
            return nil;
        }
        if ([parsed getTag:@"ext"] != nil) {
            [fileTypes addObject:@[urn, @([media[urn] unsignedIntValue])]];
        }
    }
    [fileTypes sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        NSComparisonResult byUrn = [(NSString *)a[0] compare:b[0] options:NSLiteralSearch];
        return byUrn != NSOrderedSame ? byUrn : [(NSNumber *)a[1] compare:b[1]];
    }];
    return fileTypes;
}

/// The file types kept at `path` (`{"manifest_sha256": <hex>, "file_types":
/// [[<URN>, <defver>], ...]}`, as every capdag library keeps them) and the
/// hash of the manifest file they were worked out from. Answers YES with both
/// nil when nothing is kept there, YES with both when the file holds them, and
/// NO with an error naming the file when it is there and cannot be read or is
/// not that. Mirrors Rust `read_entry::<KeptFileTypes>`.
static BOOL CSReadKeptFileTypes(NSString *path,
                                NSString *_Nullable *_Nonnull outManifestSha256,
                                NSArray<NSArray *> *_Nullable *_Nonnull outFileTypes,
                                NSError *_Nullable *_Nullable error) {
    *outManifestSha256 = nil;
    *outFileTypes = nil;
    NSDictionary *kept = nil;
    if (!CSReadCacheFile(path, @"file types", &kept, error)) return NO;
    if (!kept) return YES;
    id sha = kept[@"manifest_sha256"];
    if (![sha isKindOfClass:[NSString class]]) {
        if (error) *error = CSCacheCorrupt(path, @"file types", [NSString stringWithFormat:
            @"its 'manifest_sha256' is %@", sha ? @"not a string" : @"missing"]);
        return NO;
    }
    id list = kept[@"file_types"];
    if (![list isKindOfClass:[NSArray class]]) {
        if (error) *error = CSCacheCorrupt(path, @"file types", [NSString stringWithFormat:
            @"its 'file_types' is %@", list ? @"not a list" : @"missing"]);
        return NO;
    }
    NSMutableArray<NSArray *> *fileTypes = [NSMutableArray arrayWithCapacity:[(NSArray *)list count]];
    for (id entry in (NSArray *)list) {
        if (![entry isKindOfClass:[NSArray class]] || [(NSArray *)entry count] != 2
            || ![((NSArray *)entry)[0] isKindOfClass:[NSString class]]
            || ![((NSArray *)entry)[1] isKindOfClass:[NSNumber class]]) {
            if (error) *error = CSCacheCorrupt(path, @"file types",
                @"an entry of its 'file_types' is not a [media URN, defver] pair");
            return NO;
        }
        [fileTypes addObject:@[((NSArray *)entry)[0], @([((NSArray *)entry)[1] unsignedIntValue])]];
    }
    *outManifestSha256 = sha;
    *outFileTypes = fileTypes;
    return YES;
}

/// One load of the file media index: the file media definitions still to
/// fetch, and what the fetches came to. Guarded by itself.
@interface CSFileMediaLoad : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *queue;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *definitions;
@property (nonatomic, strong) NSMutableArray<NSString *> *failures;
/// Fetches started or still to start that have not completed.
@property (nonatomic) NSUInteger outstanding;
@end

@implementation CSFileMediaLoad
@end

/// What a load of the file media index hands each caller waiting on it: the
/// index, or the error that stopped it.
typedef void (^CSFileMediaIndexCompletion)(NSDictionary<NSString *, NSArray<NSDictionary *> *> *_Nullable index,
                                           NSError *_Nullable error);

// MARK: - CSFabricRegistry

@interface CSFabricRegistry ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy, readwrite) NSString *cacheDirectory;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSCap *> *cachedCaps;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *cachedSpecs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *cachedAliases;
// Dim name → stored dim, filtered to the pinned manifest's defvers.
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSStoredDim *> *cachedDims;
// Lower-case extension → the file media definitions of the whole manifest
// that list it, in URN order; nil until a file's type is first asked
// (fileMediaForExtension:completion:). Guarded by cacheLock.
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSArray<NSDictionary *> *> *fileMediaIndex;
// The callers waiting on the file media index while it loads; nil when no
// load runs, so the index loads once. Guarded by cacheLock.
@property (nonatomic, strong, nullable) NSMutableArray<CSFileMediaIndexCompletion> *fileMediaWaiters;
// The cached manifest file the manifest maps were read from: the file types it
// names are kept beside it. nil for a manifest made in memory, and once a test
// helper has changed the manifest's media. Guarded by cacheLock.
@property (nonatomic, copy, nullable) NSString *manifestFile;
@property (nonatomic, strong) NSLock *cacheLock;
// What the last failed fetch of each media def came to, by normalized URN,
// until a fetch of it succeeds: the synchronous lookup says this rather than
// "not fetched yet" when the registry already answered.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSError *> *mediaFetchFailures;
@property (nonatomic, strong, readwrite) CSFabricRegistryConfig *config;
@property (nonatomic, strong, readwrite) CSCharter *charter;
// The charter's `manifest` and `definition` templates. Its shape check
// guarantees each uses exactly the placeholders filled here, so filling one
// cannot fail, and nothing composes a fabric URL any other way.
@property (nonatomic, copy) NSString *manifestTemplate;
@property (nonatomic, copy) NSString *definitionTemplate;
// Manifest pin. >= 1 ⇒ manifest-driven; the test constructors may pin 0, where
// no manifest is consulted and there are no aliases or dims.
// The four maps are name/urn → defver, mirroring the Rust Manifest.
@property (nonatomic) uint32_t manifestVersion;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestCaps;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestMedia;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestAliases;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *manifestDims;
@end

@implementation CSFabricRegistry

+ (NSString *)capdagCacheRoot {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [[paths firstObject] stringByAppendingPathComponent:@"capdag"];
}

+ (CSCharter *)publisherLayoutCharterForAnchor:(NSString *)anchor slug:(NSString *)slug {
    NSError *error = nil;
    CSCharter *charter = [CSCharter charterWithDictionary:@{
        @"format": CSCharterFormat,
        @"anchor": anchor,
        @"kind": CSRegistryKindName(CSRegistryKindFabric),
        @"slug": slug,
        @"environment": @"prod",
        @"locations": @{
            @"manifest": [anchor stringByAppendingString:@"/manifest/{manifest_version}.json"],
            @"latest": [anchor stringByAppendingString:@"/manifest/latest.json"],
            @"definition": [anchor stringByAppendingString:@"/{kind}/{urn_hash}/{version}.json"],
        },
        @"issued_at": @0,
        @"not_after": [NSNull null],
    } error:&error];
    if (!charter) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"the publisher-layout charter has a charter's fields: %@", error.localizedDescription];
    }
    return charter;
}

+ (nullable CSCharter *)resolveCharterForAnchor:(NSString *)anchor
                                      cacheRoot:(NSString *)cacheRoot
                                        session:(NSURLSession *)session
                                          error:(NSError **)error {
    CSCharter *stored = [CSCharter storedUnder:cacheRoot forAnchor:anchor kind:CSRegistryKindFabric folder:nil];
    if (stored) return stored;
    CSFetchedCharter *fetched = [CSFetchedCharter fetchFromAnchor:anchor kind:CSRegistryKindFabric session:session error:error];
    if (!fetched) return nil;
    NSString *folder = [cacheRoot stringByAppendingPathComponent:fetched.charter.slug];
    NSError *storeError = nil;
    if (![fetched storeInFolder:folder error:&storeError]) {
        if (error) *error = CSCacheError([NSString stringWithFormat:@"Failed to store the charter of %@ in %@: %@",
                                            anchor, folder, storeError.localizedDescription], storeError);
        return nil;
    }
    return fetched.charter;
}

+ (NSURLSession *)registrySession {
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = HTTP_TIMEOUT_SECONDS;
    sessionConfig.timeoutIntervalForResource = HTTP_TIMEOUT_SECONDS;
    return [NSURLSession sessionWithConfiguration:sessionConfig];
}

- (instancetype)init {
    return [self initWithConfig:[CSFabricRegistryConfig defaultConfig]];
}

- (instancetype)initWithAnchor:(NSString *)anchor {
    return [self initWithConfig:[CSFabricRegistryConfig configWithAnchor:anchor]];
}

- (instancetype)initWithConfig:(CSFabricRegistryConfig *)config {
    // The production path: resolve the registry's charter, then pin at the
    // baked manifest version and bootstrap the manifest from disk/network.
    // Mirrors Rust with_config (which delegates to
    // with_config_and_manifest_version at the baked version).
    NSError *error = nil;
    CSCharter *charter = [[self class] resolveCharterForAnchor:config.anchor
                                                     cacheRoot:[[self class] capdagCacheRoot]
                                                       session:[[self class] registrySession]
                                                         error:&error];
    if (!charter) {
        [NSException raise:@"CSFabricRegistryCharterUnavailable"
                    format:@"the fabric registry %@ has no charter this client can use: %@",
                           config.anchor, error.localizedDescription];
    }
    return [self initWithCharter:charter
                          config:config
                 manifestVersion:CSBakedFabricManifestVersion
            bootstrapFromNetwork:YES];
}

// Designated initializer, over a charter already resolved. Everything is read
// from it: the registry's folder is its slug (the cache, that folder's
// `v<manifestVersion>`), and the manifest and definitions are where its
// locations say. `bootstrapFromNetwork == YES` mirrors Rust's
// `with_config_and_manifest_version`: it loads the pinned manifest from the
// local cache, else blocks on a network fetch, and fails hard if neither can
// supply it. `bootstrapFromNetwork == NO` mirrors Rust's `new_for_test_*`: an
// EMPTY manifest pinned at the requested version, no network, so test helpers
// populate the manifest maps as they insert caps/media/aliases.
- (instancetype)initWithCharter:(CSCharter *)charter
                         config:(CSFabricRegistryConfig *)config
                manifestVersion:(uint32_t)manifestVersion
           bootstrapFromNetwork:(BOOL)bootstrapFromNetwork {
    self = [super init];
    if (self) {
        _config = config;
        _charter = charter;
        if (charter.kind != CSRegistryKindFabric) {
            [NSException raise:@"CSFabricRegistryCharterUnavailable"
                        format:@"%@ is chartered as a %@ registry, not a fabric",
                               charter.anchor, CSRegistryKindName(charter.kind)];
        }
        for (NSString *name in @[@"manifest", @"definition"]) {
            if (charter.locations[name] == nil) {
                [NSException raise:@"CSFabricRegistryCharterUnavailable"
                            format:@"the fabric charter of %@ declares no '%@' location", charter.anchor, name];
            }
        }
        _manifestTemplate = [charter.locations[@"manifest"] copy];
        _definitionTemplate = [charter.locations[@"definition"] copy];
        _session = [[self class] registrySession];

        // The registry's folder is the charter's slug. Prod and staging serve
        // different bytes for the same URN/version; two registries have two
        // charters and two slugs, so a prod-populated cache can never satisfy a
        // staging lookup. Its cache is the folder of the manifest version it
        // is pinned at, `<slug>/v<N>`, so registries built for two manifests
        // never read each other's definitions.
        _cacheDirectory = [[[self class] cacheFolderOfRegistryFolder:
                               [[[self class] capdagCacheRoot] stringByAppendingPathComponent:charter.slug]
                                                     manifestVersion:manifestVersion] copy];
        for (NSString *kind in CSFabricCacheKindFolders()) {
            NSString *folder = [_cacheDirectory stringByAppendingPathComponent:kind];
            NSError *folderError = nil;
            if (!CSMakeFolder(folder, &folderError)) {
                [[self class] raiseCacheError:CSCacheError([NSString stringWithFormat:
                    @"Failed to create cache directory %@: %@", folder, folderError.localizedDescription], folderError)];
            }
        }

        _cachedCaps = [[NSMutableDictionary alloc] init];
        _cachedSpecs = [[NSMutableDictionary alloc] init];
        _mediaFetchFailures = [[NSMutableDictionary alloc] init];
        _cachedAliases = [[NSMutableDictionary alloc] init];
        _cachedDims = [[NSMutableDictionary alloc] init];
        _cacheLock = [[NSLock alloc] init];
        // A bootstrapped manifest is the file it was read from, or the file
        // it was written to when it was fetched.
        _manifestFile = bootstrapFromNetwork
            ? [_cacheDirectory stringByAppendingPathComponent:CSFabricCacheManifestFile]
            : nil;

        // Manifest pin. The production path passes CSBakedFabricManifestVersion
        // (CSFabricManifestVersion.m, regenerated by scripts/lib/config.sh from
        // fabric/manifest-version.txt) — the ObjC analogue of Rust's
        // compile-time FABRIC_MANIFEST_VERSION. We do NOT read
        // MFR_FABRIC_MANIFEST_VERSION from the process environment and do NOT
        // fall back to v0: a process that happened to lack the env var (e.g. the
        // app's UI process) silently degraded to legacy flat-path lookups that
        // 404 every versioned cap/media def. A baked value < 1 is a hard failure
        // here, mirroring build.rs's refusal to build below v1.
        if (CSBakedFabricManifestVersion < 1) {
            [NSException raise:@"CSFabricRegistryManifestVersionInvalid"
                        format:@"CSBakedFabricManifestVersion is %u; it must be >= 1. v0 is the implicit pre-versioning state and is never a valid target (see capdag/build.rs and scripts/lib/config.sh).",
                               CSBakedFabricManifestVersion];
        }
        _manifestVersion = manifestVersion;
        _manifestCaps = [[NSMutableDictionary alloc] init];
        _manifestMedia = [[NSMutableDictionary alloc] init];
        _manifestAliases = [[NSMutableDictionary alloc] init];
        _manifestDims = [[NSMutableDictionary alloc] init];

        // Bootstrap the manifest BEFORE hydrating the on-disk caches, mirroring
        // Rust with_config_and_manifest_version: the manifest's per-URN defvers
        // are what the cache loaders are filtered against and what every fetch
        // resolves a path from. At v >= 1 this BLOCKS on a network round-trip to
        // fetch `manifest/<N>.json` if no local cache copy exists (exactly the
        // reference's behaviour), and FAILS HARD if neither disk nor network can
        // produce it — there is no v0 fallback. The faithful mirror of Rust's
        // async constructor that `.await`s load_or_fetch_manifest before
        // returning Self. The test path (bootstrapFromNetwork == NO) leaves the
        // manifest maps empty — mirroring Rust's Manifest::empty(version).
        if (bootstrapFromNetwork) {
            [self bootstrapManifest];
        }

        // Hydrate the in-memory caches from the disk cache: each definition the
        // manifest pins, from the one file its key and pinned defver name. A
        // corrupt entry fails the construction, naming its file. Mirrors
        // load_pinned_entries in Rust's constructor.
        NSError *loadError = nil;
        NSDictionary *pinned = [[self class] loadPinnedEntriesFromCacheFolder:_cacheDirectory
                                                                     manifest:[self manifestDictionary]
                                                                        error:&loadError];
        if (!pinned) {
            [[self class] raiseCacheError:loadError];
        }
        [_cachedCaps addEntriesFromDictionary:pinned[@"caps"]];
        [_cachedSpecs addEntriesFromDictionary:pinned[@"media"]];
        [_cachedAliases addEntriesFromDictionary:pinned[@"aliases"]];
        [_cachedDims addEntriesFromDictionary:pinned[@"dims"]];
        // Filter the loaded caches to the pinned manifest's defvers (v >= 1),
        // then keep a cap or media def only when every dim it names survived.
        // Loading already reads only pinned entries. Mirrors retain_pinned in
        // Rust's constructor.
        [self filterCachesToManifest];
    }
    return self;
}

/// Test constructor: an empty registry pinned at manifest v1, so test helpers
/// (insertCachedCapForTest:/insertCachedAliasForTest:/addMediaDef:) flow into
/// the manifest at their declared version — mirrors Rust new_for_test, which
/// builds Manifest::empty(1) and never touches the network.
- (instancetype)initForTest {
    CSFabricRegistryConfig *config = [CSFabricRegistryConfig defaultConfig];
    return [self initWithCharter:[[self class] publisherLayoutCharterForAnchor:config.anchor slug:@"test-fabric"]
                          config:config
                 manifestVersion:1
            bootstrapFromNetwork:NO];
}

// MARK: - URN normalization helpers

// URN normalisation no longer falls back to the raw input on a parse failure.
// A malformed URN returns nil and (when an error-out is supplied) populates an
// NSError. Callers MUST decide: propagate the error (resolution paths with an
// error/completion channel), log+nil (nullable cache lookups), or log+skip
// (void mutator/loader loops). A non-canonical/garbage string must NEVER reach
// a cache or manifest key. Mirrors Rust normalize_cap_urn/normalize_media_urn.

- (nullable NSString *)normalizeCapUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error {
    NSError *parseError = nil;
    CSCapUrn *parsed = [CSCapUrn fromString:urn error:&parseError];
    if (!parsed) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1030
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"malformed cap URN '%@': %@", urn, parseError.localizedDescription ?: @"parse failed"]}];
        }
        return nil;
    }
    return [parsed toString];
}

- (nullable NSString *)normalizeMediaUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error {
    NSError *parseError = nil;
    CSMediaUrn *parsed = [CSMediaUrn fromString:urn error:&parseError];
    if (!parsed) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1031
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"malformed media URN '%@': %@", urn, parseError.localizedDescription ?: @"parse failed"]}];
        }
        return nil;
    }
    return [parsed toString];
}

- (NSString *)sha256HexForString:(NSString *)s {
    return CSSha256Hex(s);
}

// MARK: - Manifest bootstrap

// Load the pinned manifest BEFORE any cache hydrate or fetch. Tries the cached
// manifest (`v<N>/manifest.json`) first, then BLOCKS on a network GET. If
// neither produces a parseable manifest at the pinned version this raises —
// there is no v0 fallback (the caller pinned v >= 1 by baking it in). A cached
// manifest that is corrupt or another version's raises naming its file
// (CSFabricRegistryCacheError), and is never silently fetched again. Exact
// behavioural mirror of Rust load_or_fetch_manifest + the constructor that
// .awaits it.
- (void)bootstrapManifest {
    NSString *cacheFile = [self.cacheDirectory stringByAppendingPathComponent:CSFabricCacheManifestFile];
    NSDictionary *cached = nil;
    NSError *cacheError = nil;
    if (![[self class] readCachedManifestInFolder:self.cacheDirectory
                                          version:self.manifestVersion
                                         manifest:&cached
                                            error:&cacheError]) {
        [[self class] raiseCacheError:cacheError];
    }
    if (cached) {
        NSError *ingestErr = nil;
        if (![self ingestManifestDictionary:cached error:&ingestErr]) {
            [[self class] raiseCacheError:CSCacheCorrupt(cacheFile, @"manifest", ingestErr.localizedDescription)];
        }
        return;
    }

    NSData *body = nil;
    NSString *urlString = [self.manifestTemplate
        stringByReplacingOccurrencesOfString:@"{manifest_version}"
                                  withString:[NSString stringWithFormat:@"%u", self.manifestVersion]];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Manifest v%u URL is malformed: %@", self.manifestVersion, urlString];
    }

    // Synchronous fetch: the reference constructor blocks on the manifest round
    // trip before the registry is usable, so the ObjC init blocks the same way.
    __block NSData *fetched = nil;
    __block NSURLResponse *response = nil;
    __block NSError *netError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        fetched = data;
        response = resp;
        netError = error;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    NSError *outcome = CSFetchOutcome([NSString stringWithFormat:@"manifest v%u", self.manifestVersion],
                                      urlString, self.manifestVersion, response, netError);
    if (outcome) {
        // The fetch's own account — a refusal with its status, or the
        // registry's 404 — is what the exception says and carries.
        @throw [NSException exceptionWithName:@"CSFabricRegistryManifestUnavailable"
                                       reason:outcome.localizedDescription
                                     userInfo:@{NSUnderlyingErrorKey: outcome}];
    }
    body = fetched;

    NSError *parseErr = nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseErr];
    if (![manifest isKindOfClass:[NSDictionary class]]) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Failed to parse manifest v%u: %@",
                           self.manifestVersion, parseErr.localizedDescription ?: @"not a JSON object"];
    }
    uint32_t fetchedVersion = (uint32_t)[manifest[@"version"] unsignedIntValue];
    if (fetchedVersion != self.manifestVersion) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Manifest fetched as v%u reports version %u",
                           self.manifestVersion, fetchedVersion];
    }

    NSError *ingestErr = nil;
    if (![self ingestManifestDictionary:manifest error:&ingestErr]) {
        [NSException raise:@"CSFabricRegistryManifestUnavailable"
                    format:@"Manifest v%u at %@ is refused: %@",
                           self.manifestVersion, urlString, ingestErr.localizedDescription];
    }
    NSError *writeError = nil;
    if (!CSWriteCacheFileAtomically(cacheFile, body, &writeError)) {
        [[self class] raiseCacheError:writeError];
    }
}

// Replace the in-memory manifest maps with the snapshot's `caps`/`media`/
// `aliases`/`dims` URN→defver mappings. The published manifest is the single
// source of truth for which URNs belong to the snapshot and at which defver each
// resolves. `dims` is required, and each map names definitions with defvers: a
// manifest that breaks either is not one this library reads, and is refused
// (NO + *error) without touching the maps (CSManifestRefusal).
- (BOOL)ingestManifestDictionary:(NSDictionary *)manifest error:(NSError *_Nullable *_Nullable)error {
    NSError *refusal = CSManifestRefusal(manifest);
    if (refusal) {
        if (error) *error = refusal;
        return NO;
    }
    NSDictionary *caps = manifest[@"caps"];
    NSDictionary *media = manifest[@"media"];
    NSDictionary *aliases = manifest[@"aliases"];
    NSDictionary *dims = manifest[@"dims"];
    [self.cacheLock lock];
    [self.manifestCaps removeAllObjects];
    [self.manifestMedia removeAllObjects];
    [self.manifestAliases removeAllObjects];
    [self.manifestDims removeAllObjects];
    [self.manifestDims addEntriesFromDictionary:dims];
    if ([caps isKindOfClass:[NSDictionary class]]) {
        [self.manifestCaps addEntriesFromDictionary:caps];
    }
    if ([media isKindOfClass:[NSDictionary class]]) {
        [self.manifestMedia addEntriesFromDictionary:media];
    }
    if ([aliases isKindOfClass:[NSDictionary class]]) {
        [self.manifestAliases addEntriesFromDictionary:aliases];
    }
    [self.cacheLock unlock];
    return YES;
}

// After hydrating the on-disk caches, drop any entry whose version does NOT
// match the defver the manifest pins its URN at — a stale-snapshot or v0-flat
// blob must never satisfy a v >= 1 lookup. At v0 the manifest is empty and the
// alias and dim caches are cleared (aliases and dims are versioned-regime
// concepts). Then keep a cap or media def only when every dim it names
// survived with the value it names: one whose dims did not is dropped here and
// fetched again, with its dims, when it is next asked for — so a cached
// definition always has its dims cached. Mirrors Rust retain_pinned.
- (void)filterCachesToManifest {
    [self.cacheLock lock];
    if (self.manifestVersion >= 1) {
        NSArray<NSString *> *capKeys = [self.cachedCaps allKeys];
        for (NSString *urn in capKeys) {
            CSCap *cap = self.cachedCaps[urn];
            uint32_t pinned = (uint32_t)[self.manifestCaps[urn] unsignedIntValue];
            if (pinned != cap.version) {
                [self.cachedCaps removeObjectForKey:urn];
            }
        }
        NSArray<NSString *> *specKeys = [self.cachedSpecs allKeys];
        for (NSString *urn in specKeys) {
            NSDictionary *spec = self.cachedSpecs[urn];
            uint32_t specVersion = (uint32_t)[spec[@"version"] unsignedIntValue];
            uint32_t pinned = (uint32_t)[self.manifestMedia[urn] unsignedIntValue];
            if (pinned != specVersion) {
                [self.cachedSpecs removeObjectForKey:urn];
            }
        }
        NSArray<NSString *> *aliasKeys = [self.cachedAliases allKeys];
        for (NSString *name in aliasKeys) {
            NSDictionary *alias = self.cachedAliases[name];
            uint32_t aliasVersion = (uint32_t)[alias[@"version"] unsignedIntValue];
            uint32_t pinned = (uint32_t)[self.manifestAliases[name] unsignedIntValue];
            if (pinned != aliasVersion) {
                [self.cachedAliases removeObjectForKey:name];
            }
        }
        for (NSString *name in [self.cachedDims allKeys]) {
            uint32_t pinned = (uint32_t)[self.manifestDims[name] unsignedIntValue];
            if (pinned != self.cachedDims[name].version) {
                [self.cachedDims removeObjectForKey:name];
            }
        }
    } else {
        // v0: aliases and dims never exist on the flat path.
        [self.cachedAliases removeAllObjects];
        [self.cachedDims removeAllObjects];
    }
    for (NSString *urn in [self.cachedCaps allKeys]) {
        if (![self dimRefs:self.cachedCaps[urn].dims resolveIn:self.cachedDims]) {
            [self.cachedCaps removeObjectForKey:urn];
        }
    }
    for (NSString *urn in [self.cachedSpecs allKeys]) {
        NSArray<CSDimRef *> *refs = [CSDimRef refsFromField:self.cachedSpecs[urn][@"dims"]
                                                       owner:[NSString stringWithFormat:@"media def '%@'", urn]
                                                       error:nil];
        if (!refs || ![self dimRefs:refs resolveIn:self.cachedDims]) {
            [self.cachedSpecs removeObjectForKey:urn];
        }
    }
    [self.cacheLock unlock];
}

// Whether every dim `refs` names is in `cached` with the value it names.
// Mirrors Rust dims_resolve_in.
- (BOOL)dimRefs:(NSArray<CSDimRef *> *)refs resolveIn:(NSDictionary<NSString *, CSStoredDim *> *)cached {
    for (CSDimRef *ref in refs) {
        CSStoredDim *dim = cached[ref.dim];
        if (!dim || ![dim valueNamed:ref.value]) return NO;
    }
    return YES;
}

// MARK: - Defver resolution (manifest pin)

// Resolve a normalized cap URN to its defver under the pinned manifest. At v0 →
// 0 (flat path). At v >= 1 the URN MUST be in the manifest's caps map; absence
// is a hard NotFound (no fallback to flat paths, which would 404 against a
// versioned registry and mix snapshot versions). Mirrors Rust cap_defver.
- (BOOL)capDefver:(uint32_t *)outDefver
    forNormalized:(NSString *)normalizedUrn
            error:(NSError *_Nullable *_Nullable)error {
    if (self.manifestVersion == 0) {
        *outDefver = 0;
        return YES;
    }
    [self.cacheLock lock];
    NSNumber *defver = self.manifestCaps[normalizedUrn];
    uint32_t mv = self.manifestVersion;
    [self.cacheLock unlock];
    if (!defver) {
        if (error) *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1040
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"cap '%@' is not part of manifest v%u", normalizedUrn, mv]}];
        return NO;
    }
    *outDefver = (uint32_t)[defver unsignedIntValue];
    return YES;
}

// Resolve a normalized media URN to its defver. Same rules as capDefver. The
// bare `media:` wildcard is a sentinel with no published spec, so it resolves
// to 0 (the fetch path special-cases it and never reaches a request for it).
// Mirrors Rust media_defver.
- (BOOL)mediaDefver:(uint32_t *)outDefver
      forNormalized:(NSString *)normalizedUrn
              error:(NSError *_Nullable *_Nullable)error {
    if (self.manifestVersion == 0) {
        *outDefver = 0;
        return YES;
    }
    if ([normalizedUrn isEqualToString:@"media:"]) {
        *outDefver = 0;
        return YES;
    }
    [self.cacheLock lock];
    NSNumber *defver = self.manifestMedia[normalizedUrn];
    uint32_t mv = self.manifestVersion;
    [self.cacheLock unlock];
    if (!defver) {
        if (error) *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1041
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"media def '%@' is not part of manifest v%u", normalizedUrn, mv]}];
        return NO;
    }
    *outDefver = (uint32_t)[defver unsignedIntValue];
    return YES;
}

// Public defver-resolution surface (normalize-then-resolve), mirroring Rust
// cap_defver_for / media_defver_for. A malformed URN is a hard error; a URN
// outside the snapshot is a hard NotFound.
- (BOOL)capDefverFor:(NSString *)urn
              defver:(uint32_t *)outDefver
               error:(NSError *_Nullable *_Nullable)error {
    NSString *normalized = [self normalizeCapUrn:urn error:error];
    if (!normalized) return NO;
    return [self capDefver:outDefver forNormalized:normalized error:error];
}

- (BOOL)mediaDefverFor:(NSString *)urn
                defver:(uint32_t *)outDefver
                 error:(NSError *_Nullable *_Nullable)error {
    NSString *normalized = [self normalizeMediaUrn:urn error:error];
    if (!normalized) return NO;
    return [self mediaDefver:outDefver forNormalized:normalized error:error];
}

// MARK: - Object-path construction

// The registry URL of one definition at the given defver, from the charter's
// `definition` location: `kind` is caps, media, aliases or dims. Exact mirror
// of the URL half of Rust cap_url_and_cache_path/media_url_and_cache_path.
- (NSString *)objectURLForKind:(NSString *)kind digest:(NSString *)digest defver:(uint32_t)defver {
    NSString *url = [self.definitionTemplate stringByReplacingOccurrencesOfString:@"{kind}" withString:kind];
    url = [url stringByReplacingOccurrencesOfString:@"{urn_hash}" withString:digest];
    return [url stringByReplacingOccurrencesOfString:@"{version}"
                                          withString:[NSString stringWithFormat:@"%u", defver]];
}

// MARK: - Public cap surface

- (void)getCapWithUrn:(NSString *)urn
           completion:(void (^)(CSCap *_Nullable cap, NSError *_Nullable error))completion {
    // An alias (a colon-free token) is resolved first; because this is the
    // typed cap boundary, an alias whose target is not a cap URN is a hard
    // error.
    if (CSIsAliasToken(urn)) {
        [self resolveAliasTyped:urn expected:CSAliasTargetKindCap completion:^(NSString *target, NSError *error) {
            if (error) { completion(nil, error); return; }
            [self getCapWithUrn:target completion:completion];
        }];
        return;
    }

    NSError *normError = nil;
    NSString *normalized = [self normalizeCapUrn:urn error:&normError];
    if (!normalized) {
        completion(nil, normError);
        return;
    }

    [self.cacheLock lock];
    CSCap *cached = self.cachedCaps[normalized];
    [self.cacheLock unlock];

    if (cached) {
        completion(cached, nil);
        return;
    }

    [self fetchCapAtomic:urn completion:completion];
}

- (void)getCapsWithUrns:(NSArray<NSString *> *)urns
             completion:(void (^)(NSArray<CSCap *> *_Nullable caps, NSError *_Nullable error))completion {
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<CSCap *> *caps = [NSMutableArray array];
    __block NSError *firstError = nil;

    for (NSString *urn in urns) {
        dispatch_group_enter(group);
        [self getCapWithUrn:urn completion:^(CSCap *cap, NSError *error) {
            if (error && !firstError) {
                firstError = error;
            } else if (cap) {
                @synchronized (caps) {
                    [caps addObject:cap];
                }
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (firstError) {
            completion(nil, firstError);
        } else {
            completion([caps copy], nil);
        }
    });
}

- (void)validateCap:(CSCap *)cap completion:(void (^)(NSError *error))completion {
    NSString *urn = [cap.capUrn toString];
    [self getCapWithUrn:urn completion:^(CSCap *canonicalCap, NSError *error) {
        if (error) { completion(error); return; }

        // A cartridge responds to a SUBSET of the fabric cap's aliases (never
        // an alias the fabric does not define).
        NSSet<NSString *> *canonicalAliasSet = [NSSet setWithArray:canonicalCap.aliases];
        for (NSString *a in cap.aliases) {
            if (![canonicalAliasSet containsObject:a]) {
                completion([NSError errorWithDomain:@"CSFabricRegistryError"
                                               code:1003
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                          [NSString stringWithFormat:@"Alias mismatch: '%@' not among the fabric cap's aliases %@",
                                                           a, canonicalCap.aliases]}]);
                return;
            }
        }
        if (cap.isAbstract != canonicalCap.isAbstract) {
            completion([NSError errorWithDomain:@"CSFabricRegistryError"
                                           code:1003
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                      [NSString stringWithFormat:@"Abstract-flag mismatch. Local: %d, Canonical: %d",
                                                       cap.isAbstract, canonicalCap.isAbstract]}]);
            return;
        }

        NSString *capStdin = [cap getStdinMediaUrn];
        NSString *canonStdin = [canonicalCap getStdinMediaUrn];
        BOOL stdinMatches = (capStdin == nil && canonStdin == nil) ||
                            (capStdin != nil && canonStdin != nil && [capStdin isEqualToString:canonStdin]);
        if (!stdinMatches) {
            completion([NSError errorWithDomain:@"CSFabricRegistryError"
                                           code:1004
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                      [NSString stringWithFormat:@"stdin mismatch. Local: %@, Canonical: %@",
                                                       capStdin ?: @"(none)", canonStdin ?: @"(none)"]}]);
            return;
        }

        completion(nil);
    }];
}

- (NSArray<CSCap *> *)getCachedCaps {
    [self.cacheLock lock];
    NSArray<CSCap *> *caps = [self.cachedCaps allValues];
    [self.cacheLock unlock];
    return caps;
}

- (void)getCachedCaps:(void (^)(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error))completion {
    completion([self getCachedCaps], nil);
}

- (BOOL)capExists:(NSString *)urn {
    NSError *normError = nil;
    NSString *normalized = [self normalizeCapUrn:urn error:&normError];
    if (!normalized) {
        NSLog(@"[CSFabricRegistry] capExists: malformed cap URN treated as not-present: %@", normError.localizedDescription);
        return NO;
    }
    [self.cacheLock lock];
    BOOL exists = (self.cachedCaps[normalized] != nil);
    [self.cacheLock unlock];
    return exists;
}

// MARK: - Public media-def surface

- (void)getMediaDef:(NSString *)urn
          completion:(void (^)(NSDictionary * _Nullable spec, NSError * _Nullable error))completion {
    // An alias (a colon-free token) is resolved first; because this is the
    // typed media boundary, an alias whose target is not a media URN is a
    // hard error.
    if (CSIsAliasToken(urn)) {
        [self resolveAliasTyped:urn expected:CSAliasTargetKindMedia completion:^(NSString *target, NSError *error) {
            if (error) { completion(nil, error); return; }
            [self getMediaDef:target completion:completion];
        }];
        return;
    }

    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:urn error:&normError];
    if (!normalized) {
        completion(nil, normError);
        return;
    }

    [self.cacheLock lock];
    NSDictionary *cached = self.cachedSpecs[normalized];
    [self.cacheLock unlock];

    if (cached) {
        completion(cached, nil);
        return;
    }

    [self fetchMediaDefAtomic:urn completion:completion];
}

- (NSDictionary *)getCachedMediaDef:(NSString *)urn error:(NSError **)error {
    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:urn error:&normError];
    if (!normalized) {
        if (error) *error = normError;
        return nil;
    }
    [self.cacheLock lock];
    NSDictionary *spec = self.cachedSpecs[normalized];
    NSError *lastFailure = self.mediaFetchFailures[normalized];
    [self.cacheLock unlock];
    if (spec) return spec;
    NSError *defverError = nil;
    uint32_t defver = 0;
    if (![self mediaDefver:&defver forNormalized:normalized error:&defverError]) {
        if (error) *error = defverError;
        return nil;
    }
    if (error) {
        *error = lastFailure ?: CSRegistryError(CSFabricRegistryErrorPending, [NSString stringWithFormat:
            @"media def '%@' (defver %u) is named by manifest v%u and has not been fetched",
            normalized, defver, self.manifestVersion], nil);
    }
    return nil;
}

// Seed a media def directly (test/local hydrate, e.g. from a cartridge
// manifest). Unlike the fetch path this REGISTERS the def in the manifest map at
// its declared version (stamping a version-0 spec to the pinned manifest
// version), so subsequent lookups resolve its defver without a network round
// trip. Mirrors Rust insert_cached_media_def_for_test.
- (void)addMediaDef:(NSDictionary *)spec {
    NSString *rawUrn = spec[@"urn"];
    if (![rawUrn isKindOfClass:[NSString class]] || rawUrn.length == 0) {
        return;
    }
    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:rawUrn error:&normError];
    if (!normalized) {
        NSLog(@"[CSFabricRegistry] addMediaDef: skipping spec with malformed media URN '%@': %@",
              rawUrn, normError.localizedDescription);
        return;
    }
    uint32_t specVersion = 0;
    NSNumber *v = spec[@"version"];
    if ([v isKindOfClass:[NSNumber class]]) {
        specVersion = (uint32_t)[v unsignedIntValue];
    }
    if (specVersion == 0 && self.manifestVersion >= 1) {
        specVersion = self.manifestVersion;
        NSMutableDictionary *stamped = [spec mutableCopy];
        stamped[@"version"] = @(specVersion);
        spec = [stamped copy];
    }
    [self insertMediaDefInMemory:spec];
    [self.cacheLock lock];
    if (self.manifestVersion >= 1) {
        self.manifestMedia[normalized] = @(specVersion);
    }
    // The manifest is no longer the file it was read from.
    self.manifestFile = nil;
    [self.cacheLock unlock];
}

- (void)listMediaInManifestForTest:(NSString *)urn defver:(uint32_t)defver {
    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:urn error:&normError];
    if (!normalized) {
        [NSException raise:NSInvalidArgumentException
                    format:@"listMediaInManifestForTest: '%@' is no media URN: %@", urn, normError.localizedDescription];
    }
    [self.cacheLock lock];
    self.manifestMedia[normalized] = @(defver);
    // The manifest is no longer the file it was read from.
    self.manifestFile = nil;
    [self.cacheLock unlock];
}

// MARK: - File media types

- (void)fileMediaForExtension:(NSString *)extension
                   completion:(void (^)(NSArray<NSDictionary *> *_Nullable definitions, NSError *_Nullable error))completion {
    NSString *key = [extension lowercaseString];
    [self loadFileMediaIndex:^(NSDictionary<NSString *, NSArray<NSDictionary *> *> *index, NSError *error) {
        if (!index) {
            completion(nil, error);
            return;
        }
        completion(index[key] ?: @[], nil);
    }];
}

// The file media index, loaded when first asked: which of the manifest's media
// definitions are file types (fileTypesInCacheFolder:...), each from the cache
// or fetched, CSFileMediaFetchesAtOnce at a time. A caller arriving while it
// loads waits for that load. A load that fails keeps nothing, so the next
// caller loads again. Mirrors Rust `file_media_index`.
- (void)loadFileMediaIndex:(CSFileMediaIndexCompletion)completion {
    [self.cacheLock lock];
    NSDictionary<NSString *, NSArray<NSDictionary *> *> *loaded = self.fileMediaIndex;
    if (loaded) {
        [self.cacheLock unlock];
        completion(loaded, nil);
        return;
    }
    if (self.fileMediaWaiters) {
        [self.fileMediaWaiters addObject:[completion copy]];
        [self.cacheLock unlock];
        return;
    }
    self.fileMediaWaiters = [NSMutableArray arrayWithObject:[completion copy]];
    NSDictionary<NSString *, NSNumber *> *media = [self.manifestMedia copy];
    NSString *manifestFile = self.manifestFile;
    NSDictionary<NSString *, NSDictionary *> *cached = [self.cachedSpecs copy];
    [self.cacheLock unlock];

    NSError *error = nil;
    NSArray<NSArray *> *fileTypes = [[self class] fileTypesInCacheFolder:self.cacheDirectory
                                                            manifestFile:manifestFile
                                                         manifestVersion:self.manifestVersion
                                                                   media:media
                                                                   error:&error];
    if (!fileTypes) {
        [self finishFileMediaLoad:nil error:error];
        return;
    }
    CSFileMediaLoad *load = [[CSFileMediaLoad alloc] init];
    load.queue = [NSMutableArray array];
    load.definitions = [NSMutableArray array];
    load.failures = [NSMutableArray array];
    for (NSArray *fileType in fileTypes) {
        NSDictionary *definition = cached[fileType[0]];
        if (definition) {
            [load.definitions addObject:definition];
        } else {
            [load.queue addObject:fileType[0]];
        }
    }
    load.outstanding = load.queue.count;
    if (load.outstanding == 0) {
        [self completeFileMediaLoad:load];
        return;
    }
    NSUInteger atOnce = MIN(load.queue.count, CSFileMediaFetchesAtOnce);
    for (NSUInteger i = 0; i < atOnce; i++) {
        [self fetchNextFileMedia:load];
    }
}

// Fetch the next file media definition the load still lacks; when the fetch
// completes, the next is started, so no more than CSFileMediaFetchesAtOnce run
// at once. The last to complete finishes the load.
- (void)fetchNextFileMedia:(CSFileMediaLoad *)load {
    NSString *urn = nil;
    @synchronized (load) {
        if (load.queue.count == 0) return;
        urn = load.queue.firstObject;
        [load.queue removeObjectAtIndex:0];
    }
    [self fetchMediaDefAtomic:urn completion:^(NSDictionary *spec, NSError *error) {
        BOOL finished = NO;
        @synchronized (load) {
            if (spec) {
                [load.definitions addObject:spec];
            } else {
                [load.failures addObject:[NSString stringWithFormat:@"%@: %@",
                    urn, error.localizedDescription ?: @"the fetch reported no error"]];
            }
            load.outstanding -= 1;
            finished = (load.outstanding == 0);
        }
        if (finished) {
            [self completeFileMediaLoad:load];
        } else {
            [self fetchNextFileMedia:load];
        }
    }];
}

// Index what the load gathered by extension, or fail naming every file media
// definition that could not be had.
- (void)completeFileMediaLoad:(CSFileMediaLoad *)load {
    NSComparator literal = ^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSLiteralSearch];
    };
    if (load.failures.count > 0) {
        NSArray<NSString *> *failures = [load.failures sortedArrayUsingComparator:literal];
        [self finishFileMediaLoad:nil error:CSRegistryError(CSFabricRegistryErrorFileTypes, [NSString stringWithFormat:
            @"%lu of the %lu file media types of manifest v%u could not be loaded, so no file's type can be told "
            @"from its extension: %@",
            (unsigned long)failures.count, (unsigned long)(failures.count + load.definitions.count),
            self.manifestVersion, [failures componentsJoinedByString:@"; "]], nil)];
        return;
    }
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *index = [NSMutableDictionary dictionary];
    for (NSDictionary *definition in load.definitions) {
        id extensions = definition[@"extensions"];
        if (extensions == nil) continue;
        BOOL listOfStrings = [extensions isKindOfClass:[NSArray class]];
        for (id extension in (listOfStrings ? (NSArray *)extensions : @[])) {
            if (![extension isKindOfClass:[NSString class]]) listOfStrings = NO;
        }
        if (!listOfStrings) {
            [self finishFileMediaLoad:nil error:CSRegistryError(CSFabricRegistryErrorFileTypes, [NSString stringWithFormat:
                @"the file media definition '%@' of manifest v%u has an 'extensions' that is not a list of strings",
                definition[@"urn"], self.manifestVersion], nil)];
            return;
        }
        for (NSString *extension in (NSArray<NSString *> *)extensions) {
            NSString *key = [extension lowercaseString];
            NSMutableArray<NSDictionary *> *named = index[key];
            if (!named) {
                named = [NSMutableArray array];
                index[key] = named;
            }
            [named addObject:definition];
        }
    }
    NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *sorted = [NSMutableDictionary dictionaryWithCapacity:index.count];
    for (NSString *key in index) {
        NSArray<NSDictionary *> *byUrn = [index[key] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return literal(a[@"urn"], b[@"urn"]);
        }];
        NSMutableArray<NSDictionary *> *unique = [NSMutableArray arrayWithCapacity:byUrn.count];
        for (NSDictionary *definition in byUrn) {
            if (![[unique.lastObject objectForKey:@"urn"] isEqualToString:definition[@"urn"]]) {
                [unique addObject:definition];
            }
        }
        sorted[key] = unique;
    }
    [self finishFileMediaLoad:sorted error:nil];
}

// Keep the index a load made, and answer every caller that waited on it.
- (void)finishFileMediaLoad:(nullable NSDictionary<NSString *, NSArray<NSDictionary *> *> *)index
                      error:(nullable NSError *)error {
    [self.cacheLock lock];
    if (index) {
        self.fileMediaIndex = index;
    }
    NSArray<CSFileMediaIndexCompletion> *waiters = self.fileMediaWaiters;
    self.fileMediaWaiters = nil;
    [self.cacheLock unlock];
    for (CSFileMediaIndexCompletion waiter in waiters) {
        waiter(index, error);
    }
}

// The file types of the manifest whose media map is `media`, in the cache
// folder `folder` of its version. `manifestFile` is the cached manifest file
// the map was read from, nil for a manifest made in memory.
//
// Working them out parses every media URN the manifest names (tens of
// thousands), which every file a host detects would otherwise pay for. So they
// are kept beside the manifest file (CSFabricCacheFileTypesFile), with the
// sha256 of its bytes, and read back while that file is unchanged; a manifest
// fetched again has other bytes and its file types are worked out afresh. Kept
// file types that cannot be read are an error naming their file. A manifest
// with no file keeps nothing. Mirrors Rust `file_types_of`.
+ (nullable NSArray<NSArray *> *)fileTypesInCacheFolder:(NSString *)folder
                                           manifestFile:(nullable NSString *)manifestFile
                                        manifestVersion:(uint32_t)manifestVersion
                                                  media:(NSDictionary<NSString *, NSNumber *> *)media
                                                  error:(NSError *_Nullable *_Nullable)error {
    if (!manifestFile) {
        return CSDeriveFileTypes(media, manifestVersion, error);
    }
    NSError *readError = nil;
    NSData *bytes = [NSData dataWithContentsOfFile:manifestFile options:0 error:&readError];
    if (!bytes) {
        if (error) *error = CSCacheError([NSString stringWithFormat:@"the cached manifest %@ cannot be read: %@",
                                          manifestFile, readError.localizedDescription], readError);
        return nil;
    }
    NSString *manifestSha256 = CSSha256HexOfData(bytes);
    NSString *keptFile = [folder stringByAppendingPathComponent:CSFabricCacheFileTypesFile];
    NSString *keptSha256 = nil;
    NSArray<NSArray *> *kept = nil;
    if (!CSReadKeptFileTypes(keptFile, &keptSha256, &kept, error)) return nil;
    if (kept && [keptSha256 isEqualToString:manifestSha256]) {
        return kept;
    }
    NSArray<NSArray *> *fileTypes = CSDeriveFileTypes(media, manifestVersion, error);
    if (!fileTypes) return nil;
    if (![self storeCacheEntry:@{@"manifest_sha256": manifestSha256, @"file_types": fileTypes}
                        atPath:keptFile
                          what:@"file types"
                         error:error]) {
        return nil;
    }
    return fileTypes;
}

// MARK: - Cache lifecycle

// Invalidate every cache of this registry's manifest version: the in-memory
// definition maps and its whole folder on disk, INCLUDING the cached manifest,
// and the folders of the layout before per-version folders. The in-memory
// manifest maps stay (the registry stays pinned and usable; every definition is
// fetched again lazily at the same defvers), and a registry constructed after
// this fetches the manifest afresh. Mirrors Rust clear_cache.
- (BOOL)clearCache:(NSError *_Nullable *_Nullable)error {
    [self.cacheLock lock];
    [self.cachedCaps removeAllObjects];
    [self.cachedSpecs removeAllObjects];
    [self.cachedAliases removeAllObjects];
    [self.cachedDims removeAllObjects];
    self.fileMediaIndex = nil;
    [self.cacheLock unlock];
    return [[self class] clearCacheFolder:self.cacheDirectory error:error];
}

// MARK: - Atomic cap fetch

/// Walk every media URN a cap definition references (in_spec, out_spec,
/// each arg.media_urn, each stdin source, output.media_urn). Skip the
/// bare `media:` wildcard. Order is deterministic and de-duplicated.
- (NSArray<NSString *> *)collectReferencedMediaUrnsForCap:(CSCap *)cap {
    NSMutableArray<NSString *> *seen = [NSMutableArray array];
    void (^push)(NSString *) = ^(NSString *urn) {
        if (urn.length == 0) return;
        NSError *err = nil;
        CSMediaUrn *parsed = [CSMediaUrn fromString:urn error:&err];
        if (!parsed) return;
        if ([parsed isTop]) return; // bare media: wildcard
        NSString *normalized = [parsed toString];
        if (![seen containsObject:normalized]) {
            [seen addObject:normalized];
        }
    };

    push([cap.capUrn inSpec]);
    push([cap.capUrn outSpec]);
    for (CSCapArg *arg in cap.args) {
        push(arg.mediaUrn);
        // What the arg accepts: its stdin source's URN, or its `accepts`.
        push([arg acceptedUrn]);
    }
    for (CSCapOutput *output in cap.outputs) {
        push(output.mediaUrn);
    }
    return seen;
}

- (void)fetchCapAtomic:(NSString *)urn
            completion:(void (^)(CSCap *_Nullable cap, NSError *_Nullable error))completion {
    [self fetchCapFromRegistry:urn completion:^(CSCap *cap, NSError *error) {
        if (!cap) {
            completion(nil, error);
            return;
        }

        NSArray<NSString *> *referenced = [self collectReferencedMediaUrnsForCap:cap];
        [self ensureMediaDefsCached:referenced
                          forCapUrn:urn
                         completion:^(NSError *mediaError) {
            if (mediaError) {
                // Atomic: every referenced media URN must land before
                // the cap is cached. Failure leaves the cap out of both
                // in-memory and on-disk caches.
                completion(nil, mediaError);
                return;
            }
            NSError *normError = nil;
            NSString *normalized = [self normalizeCapUrn:[cap.capUrn toString] error:&normError];
            if (!normalized) {
                completion(nil, normError);
                return;
            }
            // Every dim the cap names, at its pinned version, with the value
            // named.
            [self ensureDimsCached:cap.dims
                             owner:[NSString stringWithFormat:@"cap '%@'", normalized]
                        completion:^(NSError *dimError) {
                if (dimError) {
                    completion(nil, dimError);
                    return;
                }
                // All referenced media defs and dims in cache. Write the cap.
                NSError *saveError = nil;
                if (![self saveCapToCache:cap error:&saveError]) {
                    completion(nil, saveError);
                    return;
                }
                [self.cacheLock lock];
                self.cachedCaps[normalized] = cap;
                [self.cacheLock unlock];
                completion(cap, nil);
            }];
        }];
    }];
}

// Atomic media-def fetch: the media def is cached only once every dim it names
// is cached (ensureDimsCached:owner:completion:). A `dims` entry this capdag
// cannot hold refuses the body. Mirrors Rust fetch_one_media_def.
- (void)fetchMediaDefAtomic:(NSString *)urn
                 completion:(void (^)(NSDictionary *_Nullable spec, NSError *_Nullable error))outerCompletion {
    // Keep what the fetch came to, for the synchronous lookup.
    NSString *key = [self normalizeMediaUrn:urn error:nil] ?: urn;
    void (^completion)(NSDictionary *, NSError *) = ^(NSDictionary *spec, NSError *error) {
        [self.cacheLock lock];
        if (spec) {
            [self.mediaFetchFailures removeObjectForKey:key];
        } else if (error) {
            self.mediaFetchFailures[key] = error;
        }
        [self.cacheLock unlock];
        outerCompletion(spec, error);
    };
    [self fetchMediaDefFromRegistry:urn completion:^(NSDictionary *spec, NSError *error) {
        if (!spec) {
            completion(nil, error);
            return;
        }
        NSString *owner = [NSString stringWithFormat:@"media def '%@'", [self normalizeMediaUrn:urn error:nil] ?: urn];
        NSError *dimsError = nil;
        NSArray<CSDimRef *> *dims = [CSDimRef refsFromField:spec[@"dims"] owner:owner error:&dimsError];
        if (!dims) {
            completion(nil, CSRegistryError(1001, [NSString stringWithFormat:
                @"Failed to parse registry response for %@: %@", owner, dimsError.localizedDescription], dimsError));
            return;
        }
        [self ensureDimsCached:dims owner:owner completion:^(NSError *dimError) {
            if (dimError) {
                completion(nil, dimError);
                return;
            }
            NSError *saveError = nil;
            if (![self saveMediaDefToCache:spec error:&saveError]) {
                completion(nil, saveError);
                return;
            }
            [self insertMediaDefInMemory:spec];
            completion(spec, nil);
        }];
    }];
}

- (void)ensureMediaDefsCached:(NSArray<NSString *> *)urns
                     forCapUrn:(NSString *)capUrn
                    completion:(void (^)(NSError * _Nullable error))completion {
    if (urns.count == 0) {
        completion(nil);
        return;
    }
    __block NSUInteger remaining = urns.count;
    __block NSError *firstError = nil;
    __block NSString *firstFailingUrn = nil;
    NSObject *guard = [[NSObject alloc] init];

    for (NSString *mediaUrn in urns) {
        [self.cacheLock lock];
        BOOL alreadyCached = (self.cachedSpecs[mediaUrn] != nil);
        [self.cacheLock unlock];

        if (alreadyCached) {
            @synchronized (guard) {
                if (--remaining == 0) {
                    completion(firstError);
                }
            }
            continue;
        }

        [self fetchMediaDefAtomic:mediaUrn completion:^(NSDictionary *spec, NSError *error) {
            @synchronized (guard) {
                if (error && !firstError) {
                    firstError = error;
                    firstFailingUrn = mediaUrn;
                }
                if (--remaining == 0) {
                    if (firstError) {
                        NSString *msg = [NSString stringWithFormat:
                            @"Cap '%@' fetch aborted: referenced media URN '%@' could not be resolved: %@",
                            capUrn, firstFailingUrn, firstError.localizedDescription];
                        completion([NSError errorWithDomain:@"CSFabricRegistryError"
                                                       code:1010
                                                   userInfo:@{NSLocalizedDescriptionKey: msg,
                                                              NSUnderlyingErrorKey: firstError}]);
                    } else {
                        completion(nil);
                    }
                }
            }
        }];
    }
}

// Insert a fetched/cached media spec into the in-memory cache — and ONLY
// there. The manifest map is NOT written here: the manifest is
// authoritative (loaded from R2 / seeded by the test helper) and the path this
// spec was fetched from was already derived from it. Mirrors the cache-only
// insert at the tail of Rust fetch_one_media_def. The test/local seeding path
// (addMediaDef:) is the one that registers the manifest defver.
- (void)insertMediaDefInMemory:(NSDictionary *)spec {
    NSString *rawUrn = spec[@"urn"];
    if (![rawUrn isKindOfClass:[NSString class]] || rawUrn.length == 0) {
        return;
    }
    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:rawUrn error:&normError];
    if (!normalized) {
        NSLog(@"[CSFabricRegistry] insertMediaDefInMemory: skipping spec with malformed media URN '%@': %@",
              rawUrn, normError.localizedDescription);
        return;
    }
    [self.cacheLock lock];
    self.cachedSpecs[normalized] = spec;
    [self.cacheLock unlock];
}

// MARK: - Disk cache I/O

+ (void)raiseCacheError:(NSError *)error {
    @throw [NSException exceptionWithName:CSFabricRegistryCacheErrorException
                                   reason:error.localizedDescription
                                 userInfo:@{NSUnderlyingErrorKey: error}];
}

+ (NSString *)cacheFolderOfRegistryFolder:(NSString *)registryFolder manifestVersion:(uint32_t)manifestVersion {
    return [registryFolder stringByAppendingPathComponent:[NSString stringWithFormat:@"v%u", manifestVersion]];
}

+ (NSString *)cacheEntryPathInFolder:(NSString *)folder
                                kind:(NSString *)kind
                                 key:(NSString *)key
                              defver:(uint32_t)defver {
    return [[[folder stringByAppendingPathComponent:kind] stringByAppendingPathComponent:CSSha256Hex(key)]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%u.json", defver]];
}

+ (BOOL)storeCacheEntry:(NSDictionary *)entry
                 atPath:(NSString *)path
                   what:(NSString *)what
                  error:(NSError *_Nullable *_Nullable)error {
    if (![NSJSONSerialization isValidJSONObject:entry]) {
        if (error) *error = CSCacheError([NSString stringWithFormat:
            @"failed to serialize the %@ cache entry: it is not a JSON object", what], nil);
        return NO;
    }
    NSError *serializeError = nil;
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:entry options:NSJSONWritingPrettyPrinted error:&serializeError];
    if (!bytes) {
        if (error) *error = CSCacheError([NSString stringWithFormat:@"failed to serialize the %@ cache entry: %@",
                                          what, serializeError.localizedDescription], serializeError);
        return NO;
    }
    return CSWriteCacheFileAtomically(path, bytes, error);
}

+ (BOOL)readCachedManifestInFolder:(NSString *)folder
                           version:(uint32_t)version
                          manifest:(NSDictionary *_Nullable *_Nonnull)outManifest
                             error:(NSError *_Nullable *_Nullable)error {
    *outManifest = nil;
    NSString *path = [folder stringByAppendingPathComponent:CSFabricCacheManifestFile];
    NSDictionary *manifest = nil;
    if (!CSReadCacheFile(path, @"manifest", &manifest, error)) return NO;
    if (!manifest) return YES;
    id cachedVersion = manifest[@"version"];
    if (![cachedVersion isKindOfClass:[NSNumber class]]) {
        if (error) *error = CSCacheCorrupt(path, @"manifest",
            [NSString stringWithFormat:@"its 'version' is %@", cachedVersion ? @"not a number" : @"missing"]);
        return NO;
    }
    NSError *refusal = CSManifestRefusal(manifest);
    if (refusal) {
        if (error) *error = CSCacheCorrupt(path, @"manifest", refusal.localizedDescription);
        return NO;
    }
    if ([cachedVersion unsignedIntValue] != version) {
        if (error) *error = CSCacheCorrupt(path, @"manifest", [NSString stringWithFormat:
            @"it is manifest %u, in the folder of manifest %u", [cachedVersion unsignedIntValue], version]);
        return NO;
    }
    *outManifest = manifest;
    return YES;
}

// Read, from the cache folder `folder` of manifest `manifest`, every definition
// the manifest pins that is cached: each from the one file its key and pinned
// defver name, so nothing at another defver, and nothing another manifest
// version cached, is ever read. Mirrors Rust load_pinned_entries.
//
// An entry that is not there is not cached. One that is there and cannot be
// read, does not parse, or is not the definition and defver its path names is
// corrupt, and an error naming the file; the file is left where it is. Two
// rules drop an entry and leave it to be fetched anew, naming its file in the
// log:
// - a defver-0 cap or media def older than its time to live (defver 0 is the
//   flat, mutable regime);
// - a cap or dim that breaks the definition rules was written by a capdag with
//   other rules; its file is removed.
+ (nullable NSDictionary *)loadPinnedEntriesFromCacheFolder:(NSString *)folder
                                                   manifest:(NSDictionary *)manifest
                                                      error:(NSError *_Nullable *_Nullable)error {
    NSMutableDictionary<NSString *, CSCap *> *caps = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *media = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *aliases = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, CSStoredDim *> *dims = [NSMutableDictionary dictionary];
    NSString *(^holds)(NSString *, uint32_t, NSString *, uint32_t) =
        ^NSString *(NSString *found, uint32_t foundVersion, NSString *key, uint32_t defver) {
            return [NSString stringWithFormat:@"it holds '%@' at defver %u, where '%@' at defver %u belongs",
                    found, foundVersion, key, defver];
        };

    NSDictionary<NSString *, NSNumber *> *pinnedCaps = manifest[@"caps"];
    for (NSString *urn in pinnedCaps) {
        uint32_t defver = [pinnedCaps[urn] unsignedIntValue];
        NSString *path = [self cacheEntryPathInFolder:folder kind:@"caps" key:urn defver:defver];
        NSDictionary *entry = nil;
        if (!CSReadCacheFile(path, @"cap", &entry, error)) return nil;
        if (!entry) continue;
        NSString *detail = nil;
        NSDictionary *body = CSCacheEntryBody(entry, @"definition", &detail);
        if (!body) {
            if (error) *error = CSCacheCorrupt(path, @"cap", detail);
            return nil;
        }
        NSError *parseError = nil;
        CSCap *cap = [CSCap capWithDictionary:body error:&parseError];
        if (!cap) {
            if (error) *error = CSCacheCorrupt(path, @"cap", parseError.localizedDescription ?: @"it is not a cap definition");
            return nil;
        }
        NSError *urnError = nil;
        NSString *cachedUrn = [[CSCapUrn fromString:[cap.capUrn toString] error:&urnError] toString];
        if (!cachedUrn) {
            if (error) *error = CSCacheCorrupt(path, @"cap", urnError.localizedDescription ?: @"its URN does not parse");
            return nil;
        }
        if (![cachedUrn isEqualToString:urn] || cap.version != defver) {
            if (error) *error = CSCacheCorrupt(path, @"cap", holds(cachedUrn, cap.version, urn, defver));
            return nil;
        }
        if (defver == 0 && CSCacheEntryIsExpired(entry)) {
            NSLog(@"[CSFabricRegistry] the cached cap %@ is past its time to live", path);
            continue;
        }
        NSError *ruleError = nil;
        if (![CSCapValidator validateCapDefinition:cap error:&ruleError]) {
            NSLog(@"[CSFabricRegistry] dropping the cached cap %@: %@", path, ruleError.localizedDescription);
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            continue;
        }
        caps[cachedUrn] = cap;
    }

    NSDictionary<NSString *, NSNumber *> *pinnedMedia = manifest[@"media"];
    for (NSString *urn in pinnedMedia) {
        uint32_t defver = [pinnedMedia[urn] unsignedIntValue];
        NSString *path = [self cacheEntryPathInFolder:folder kind:@"media" key:urn defver:defver];
        NSDictionary *entry = nil;
        if (!CSReadCacheFile(path, @"media def", &entry, error)) return nil;
        if (!entry) continue;
        NSString *detail = nil;
        NSDictionary *spec = CSCacheEntryBody(entry, @"spec", &detail);
        if (!spec) {
            if (error) *error = CSCacheCorrupt(path, @"media def", detail);
            return nil;
        }
        id specUrn = spec[@"urn"];
        id specVersion = spec[@"version"];
        if (![specUrn isKindOfClass:[NSString class]]) {
            if (error) *error = CSCacheCorrupt(path, @"media def", @"its spec has no 'urn' string");
            return nil;
        }
        if (specVersion != nil && ![specVersion isKindOfClass:[NSNumber class]]) {
            if (error) *error = CSCacheCorrupt(path, @"media def", @"its spec's 'version' is not a number");
            return nil;
        }
        NSError *urnError = nil;
        NSString *cachedUrn = [[CSMediaUrn fromString:specUrn error:&urnError] toString];
        if (!cachedUrn) {
            if (error) *error = CSCacheCorrupt(path, @"media def", urnError.localizedDescription ?: @"its URN does not parse");
            return nil;
        }
        uint32_t cachedVersion = [specVersion unsignedIntValue];
        if (![cachedUrn isEqualToString:urn] || cachedVersion != defver) {
            if (error) *error = CSCacheCorrupt(path, @"media def", holds(cachedUrn, cachedVersion, urn, defver));
            return nil;
        }
        if (defver == 0 && CSCacheEntryIsExpired(entry)) {
            NSLog(@"[CSFabricRegistry] the cached media def %@ is past its time to live", path);
            continue;
        }
        media[cachedUrn] = spec;
    }

    NSDictionary<NSString *, NSNumber *> *pinnedAliases = manifest[@"aliases"];
    for (NSString *name in pinnedAliases) {
        uint32_t defver = [pinnedAliases[name] unsignedIntValue];
        NSString *path = [self cacheEntryPathInFolder:folder kind:@"aliases" key:name defver:defver];
        NSDictionary *entry = nil;
        if (!CSReadCacheFile(path, @"alias", &entry, error)) return nil;
        if (!entry) continue;
        NSString *detail = nil;
        NSDictionary *alias = CSCacheEntryBody(entry, @"alias", &detail);
        if (!alias) {
            if (error) *error = CSCacheCorrupt(path, @"alias", detail);
            return nil;
        }
        id aliasName = alias[@"name"];
        id target = alias[@"target"];
        id version = alias[@"version"];
        if (![aliasName isKindOfClass:[NSString class]] || ![target isKindOfClass:[NSString class]]
            || ![version isKindOfClass:[NSNumber class]]) {
            if (error) *error = CSCacheCorrupt(path, @"alias", @"it is not an alias (a 'name', a 'target' and a 'version')");
            return nil;
        }
        // The checks the reference holds a fetched alias to
        // (validate_fetched_alias), each a corrupt entry here.
        if (![aliasName isEqualToString:name]) {
            if (error) *error = CSCacheCorrupt(path, @"alias", [NSString stringWithFormat:
                @"alias object name '%@' does not match requested name '%@'", aliasName, name]);
            return nil;
        }
        if ([version unsignedIntValue] != defver) {
            if (error) *error = CSCacheCorrupt(path, @"alias", [NSString stringWithFormat:
                @"alias '%@' object reports version %u but manifest pins defver %u", aliasName, [version unsignedIntValue], defver]);
            return nil;
        }
        if (!CSClassifyAliasTarget(target, NULL)) {
            if (error) *error = CSCacheCorrupt(path, @"alias", [NSString stringWithFormat:
                @"alias '%@' target '%@' is neither a cap nor a media URN", aliasName, target]);
            return nil;
        }
        aliases[aliasName] = alias;
    }

    NSDictionary<NSString *, NSNumber *> *pinnedDims = manifest[@"dims"];
    for (NSString *name in pinnedDims) {
        uint32_t defver = [pinnedDims[name] unsignedIntValue];
        NSString *path = [self cacheEntryPathInFolder:folder kind:@"dims" key:name defver:defver];
        NSDictionary *entry = nil;
        if (!CSReadCacheFile(path, @"dim", &entry, error)) return nil;
        if (!entry) continue;
        NSString *detail = nil;
        NSDictionary *body = CSCacheEntryBody(entry, @"dim", &detail);
        if (!body) {
            if (error) *error = CSCacheCorrupt(path, @"dim", detail);
            return nil;
        }
        NSError *parseError = nil;
        CSStoredDim *dim = [CSStoredDim dimWithDictionary:body error:&parseError];
        if (!dim) {
            if (error) *error = CSCacheCorrupt(path, @"dim", parseError.localizedDescription ?: @"it is not a dim");
            return nil;
        }
        if (![dim.name isEqualToString:name] || dim.version != defver) {
            if (error) *error = CSCacheCorrupt(path, @"dim", holds(dim.name, dim.version, name, defver));
            return nil;
        }
        NSError *validateError = nil;
        if (![dim validate:&validateError]) {
            NSLog(@"[CSFabricRegistry] dropping the cached dim %@: %@", path, validateError.localizedDescription);
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            continue;
        }
        dims[dim.name] = dim;
    }

    return @{@"caps": caps, @"media": media, @"aliases": aliases, @"dims": dims};
}

// Empty the cache folder of one manifest version, `folder`, and remove the
// folders the layout before per-version folders kept beside it. Mirrors Rust
// clear_cache_folder.
//
// The cache is SHARED, and the processes that clear it run at the same time.
// Removing the tree and putting it back is not safe between peers — one
// process deleting an ancestor while another is creating into it fails the
// second with "No such file or directory" on a path it had just made. So a
// kind's folder is never removed, only its contents, and every step tolerates
// a peer having done the same thing first (CSRemoveShared). The manifest, and
// any temporary file a killed writer left, are removed from the version's
// folder; other versions' folders and the stored charter are left as they are.
+ (BOOL)clearCacheFolder:(NSString *)folder error:(NSError *_Nullable *_Nullable)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *kind in CSFabricCacheKindFolders()) {
        NSString *kindFolder = [folder stringByAppendingPathComponent:kind];
        NSError *createError = nil;
        if (!CSMakeFolder(kindFolder, &createError)) {
            if (error) *error = CSCacheError([NSString stringWithFormat:@"Failed to create cache directory %@: %@",
                                              kindFolder, createError.localizedDescription], createError);
            return NO;
        }
        if (!CSRemoveContents(kindFolder, error)) return NO;
    }
    // What is left at the top of the version's folder: the manifest, and
    // temporary files. The kinds' folders themselves stay.
    NSError *listError = nil;
    NSArray<NSString *> *top = [fm contentsOfDirectoryAtPath:folder error:&listError];
    if (!top) {
        if (CSIsNoSuchFile(listError)) return YES;
        if (error) *error = CSCacheError([NSString stringWithFormat:@"Failed to read cache directory %@: %@",
                                          folder, listError.localizedDescription], listError);
        return NO;
    }
    for (NSString *name in top) {
        NSString *path = [folder stringByAppendingPathComponent:name];
        if (!CSIsFolder(path) && !CSRemoveShared(path, error)) return NO;
    }
    NSString *registryFolder = [folder stringByDeletingLastPathComponent];
    for (NSString *legacy in CSFabricCacheLegacyFolders()) {
        NSString *path = [registryFolder stringByAppendingPathComponent:legacy];
        if (CSIsFolder(path) && !CSRemoveShared(path, error)) return NO;
    }
    return YES;
}

- (nullable NSString *)capCacheFilePathForUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error {
    NSString *normalized = [self normalizeCapUrn:urn error:error];
    if (!normalized) return nil;
    uint32_t defver = 0;
    if (![self capDefver:&defver forNormalized:normalized error:error]) return nil;
    return [[self class] cacheEntryPathInFolder:self.cacheDirectory kind:@"caps" key:normalized defver:defver];
}

- (nullable NSString *)mediaCacheFilePathForUrn:(NSString *)urn error:(NSError *_Nullable *_Nullable)error {
    NSString *normalized = [self normalizeMediaUrn:urn error:error];
    if (!normalized) return nil;
    uint32_t defver = 0;
    if (![self mediaDefver:&defver forNormalized:normalized error:error]) return nil;
    return [[self class] cacheEntryPathInFolder:self.cacheDirectory kind:@"media" key:normalized defver:defver];
}

// Write a fetched cap's cache entry, whole (storeCacheEntry:). A cap that
// cannot be written is not cached at all: the fetch fails with the error.
- (BOOL)saveCapToCache:(CSCap *)cap error:(NSError *_Nullable *_Nullable)error {
    NSString *cacheFile = [self capCacheFilePathForUrn:[cap.capUrn toString] error:error];
    if (!cacheFile) return NO;
    NSDictionary *entry = @{
        @"definition": [cap toDictionary],
        @"cached_at": @((uint64_t)[[NSDate date] timeIntervalSince1970]),
        @"ttl_hours": @(CACHE_DURATION_HOURS),
    };
    return [[self class] storeCacheEntry:entry atPath:cacheFile what:@"cap" error:error];
}

// Write a fetched media def's cache entry, whole (storeCacheEntry:).
- (BOOL)saveMediaDefToCache:(NSDictionary *)spec error:(NSError *_Nullable *_Nullable)error {
    id rawUrn = spec[@"urn"];
    if (![rawUrn isKindOfClass:[NSString class]]) {
        if (error) *error = CSRegistryError(1001, @"a media def without a 'urn' string cannot be cached", nil);
        return NO;
    }
    NSString *cacheFile = [self mediaCacheFilePathForUrn:rawUrn error:error];
    if (!cacheFile) return NO;
    NSDictionary *entry = @{
        @"spec": spec,
        @"cached_at": @((uint64_t)[[NSDate date] timeIntervalSince1970]),
        @"ttl_hours": @(CACHE_DURATION_HOURS),
    };
    return [[self class] storeCacheEntry:entry atPath:cacheFile what:@"media def" error:error];
}

// MARK: - HTTP fetch

- (void)fetchCapFromRegistry:(NSString *)urn
                  completion:(void (^)(CSCap *cap, NSError *error))completion {
    NSError *normError = nil;
    NSString *normalized = [self normalizeCapUrn:urn error:&normError];
    if (!normalized) {
        completion(nil, normError);
        return;
    }
    // Resolve the defver from the pinned manifest. A URN that is not part of the
    // snapshot is a hard NotFound here — we do NOT fetch a flat v0 path as a
    // fallback (that path 404s against a versioned registry and would mix
    // snapshots). Mirrors Rust get_cap → cap_defver.
    NSError *defverError = nil;
    uint32_t defver = 0;
    if (![self capDefver:&defver forNormalized:normalized error:&defverError]) {
        completion(nil, defverError);
        return;
    }
    NSString *digest = [self sha256HexForString:normalized];
    NSString *urlString = [self objectURLForKind:@"caps" digest:digest defver:defver];
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *outcome = CSFetchOutcome([NSString stringWithFormat:@"cap '%@' (defver %u)", normalized, defver],
                                          urlString, self.manifestVersion, response, error);
        if (outcome) { completion(nil, outcome); return; }
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:1001
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to parse registry response for cap '%@'", urn]}]);
            return;
        }
        CSCap *cap = [CSCap capWithDictionary:json error:&parseError];
        if (!cap) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:1001
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to parse registry response for cap '%@': %@", urn, parseError.localizedDescription]}]);
            return;
        }
        // A definition is held to the definition rules by the side that
        // receives it as well as the side that sends it, before anything
        // caches it.
        NSError *ruleError = nil;
        if (![CSCapValidator validateCapDefinition:cap error:&ruleError]) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:1006
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"the registry's definition of cap '%@' breaks a definition rule: %@", urn, ruleError.localizedDescription]}]);
            return;
        }
        completion(cap, nil);
    }];
    [task resume];
}

- (void)fetchMediaDefFromRegistry:(NSString *)urn
                        completion:(void (^)(NSDictionary *spec, NSError *error))completion {
    NSError *normError = nil;
    NSString *normalized = [self normalizeMediaUrn:urn error:&normError];
    if (!normalized) {
        completion(nil, normError);
        return;
    }
    // Manifest-driven defver; a URN outside the snapshot is a hard NotFound, not
    // a silent v0-flat fetch. Mirrors Rust get_media_def → media_defver.
    NSError *defverError = nil;
    uint32_t defver = 0;
    if (![self mediaDefver:&defver forNormalized:normalized error:&defverError]) {
        completion(nil, defverError);
        return;
    }
    NSString *digest = [self sha256HexForString:normalized];
    NSString *urlString = [self objectURLForKind:@"media" digest:digest defver:defver];
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *outcome = CSFetchOutcome([NSString stringWithFormat:@"media def '%@' (defver %u)", normalized, defver],
                                          urlString, self.manifestVersion, response, error);
        if (outcome) { completion(nil, outcome); return; }
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError"
                                                code:1001
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to parse registry response for media def '%@'", urn]}]);
            return;
        }
        completion(json, nil);
    }];
    [task resume];
}

// MARK: - Alias surface

- (uint32_t)aliasDefverFor:(NSString *)name error:(NSError *_Nullable *_Nullable)error {
    NSError *nerr = nil;
    NSString *normalized = CSNormalizeAliasName(name, &nerr);
    if (!normalized) {
        if (error) *error = nerr;
        return 0;
    }
    [self.cacheLock lock];
    uint32_t mv = self.manifestVersion;
    NSNumber *defver = self.manifestAliases[normalized];
    [self.cacheLock unlock];
    if (mv == 0) {
        if (error) *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1021
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"alias '%@' cannot resolve: registry is pinned at v0 (aliases are a versioned-regime concept)", normalized]}];
        return 0;
    }
    if (!defver) {
        if (error) *error = [NSError errorWithDomain:@"CSFabricRegistryError" code:1022
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"alias '%@' is not part of manifest v%u", normalized, mv]}];
        return 0;
    }
    return (uint32_t)[defver unsignedIntValue];
}

- (void)getAlias:(NSString *)name
      completion:(void (^)(NSDictionary *_Nullable alias, NSError *_Nullable error))completion {
    NSError *nerr = nil;
    NSString *normalized = CSNormalizeAliasName(name, &nerr);
    if (!normalized) {
        completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError" code:1020
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"invalid alias name: %@",
                nerr.localizedDescription]}]);
        return;
    }
    [self.cacheLock lock];
    NSDictionary *cached = self.cachedAliases[normalized];
    [self.cacheLock unlock];
    if (cached) {
        completion(cached, nil);
        return;
    }
    // Not cached: confirm manifest membership so an unknown alias is a hard
    // not-found rather than a silent miss. (The objc media registry does not
    // fetch aliases over the network; they are seeded or loaded from disk.)
    NSError *defErr = nil;
    [self aliasDefverFor:normalized error:&defErr];
    if (defErr) {
        completion(nil, defErr);
        return;
    }
    completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError" code:1023
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
            @"alias '%@' is in manifest v%u but not present in cache", normalized, self.manifestVersion]}]);
}

- (void)resolveAlias:(NSString *)name
          completion:(void (^)(NSString *_Nullable target, NSError *_Nullable error))completion {
    [self getAlias:name completion:^(NSDictionary *alias, NSError *error) {
        if (error) { completion(nil, error); return; }
        completion(alias[@"target"], nil);
    }];
}

- (void)resolveAliasTyped:(NSString *)name
                 expected:(NSInteger)expected
               completion:(void (^)(NSString *_Nullable target, NSError *_Nullable error))completion {
    [self getAlias:name completion:^(NSDictionary *alias, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *target = alias[@"target"];
        CSAliasTargetKind actual;
        if (!CSClassifyAliasTarget(target, &actual)) {
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError" code:1024
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"alias '%@' target '%@' is neither a cap nor a media URN", alias[@"name"], target]}]);
            return;
        }
        if (expected >= 0 && actual != (CSAliasTargetKind)expected) {
            NSString *actualStr = (actual == CSAliasTargetKindCap) ? @"cap" : @"media";
            NSString *expStr = ((CSAliasTargetKind)expected == CSAliasTargetKindCap) ? @"cap" : @"media";
            completion(nil, [NSError errorWithDomain:@"CSFabricRegistryError" code:1025
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"alias '%@' resolves to a %@ URN ('%@') but a %@ was required here",
                    alias[@"name"], actualStr, target, expStr]}]);
            return;
        }
        completion(target, nil);
    }];
}

- (NSString *)resolveAliasCached:(NSString *)name {
    NSError *nerr = nil;
    NSString *normalized = CSNormalizeAliasName(name, &nerr);
    if (!normalized) return nil;
    [self.cacheLock lock];
    NSDictionary *alias = self.cachedAliases[normalized];
    [self.cacheLock unlock];
    return alias ? alias[@"target"] : nil;
}

- (void)insertCachedAliasForTest:(NSDictionary *)alias {
    NSString *name = alias[@"name"];
    NSNumber *version = alias[@"version"];
    if (![name isKindOfClass:[NSString class]]) return;
    [self.cacheLock lock];
    self.cachedAliases[name] = alias;
    if (self.manifestVersion >= 1 && [version isKindOfClass:[NSNumber class]]) {
        self.manifestAliases[name] = version;
    }
    [self.cacheLock unlock];
}

// MARK: - Dim surface

// Resolve a dim name to its defver under the pinned manifest. Dims exist only in
// the versioned regime: at v0 any dim lookup is a hard NotFound. At v >= 1 the
// name must be in the manifest's `dims` map. Mirrors Rust dim_defver.
- (uint32_t)dimDefverFor:(NSString *)name error:(NSError *_Nullable *_Nullable)error {
    [self.cacheLock lock];
    uint32_t mv = self.manifestVersion;
    NSNumber *defver = self.manifestDims[name];
    [self.cacheLock unlock];
    if (mv == 0) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimAtV0, [NSString stringWithFormat:
            @"dim '%@' cannot resolve: registry is pinned at v0 (dims are a versioned-regime concept)", name], nil);
        return 0;
    }
    if (!defver) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimNotInManifest, [NSString stringWithFormat:
            @"dim '%@' is not part of manifest v%u", name, mv], nil);
        return 0;
    }
    return (uint32_t)[defver unsignedIntValue];
}

- (void)getDim:(NSString *)name
    completion:(void (^)(CSStoredDim *_Nullable dim, NSError *_Nullable error))completion {
    if (!CSIsDimName(name)) {
        completion(nil, CSRegistryError(CSFabricRegistryErrorInvalidDimName,
            [NSString stringWithFormat:@"'%@' is not a dim name", name], nil));
        return;
    }
    CSStoredDim *cached = [self getCachedDim:name];
    if (cached) {
        completion(cached, nil);
        return;
    }
    NSError *defverError = nil;
    uint32_t defver = [self dimDefverFor:name error:&defverError];
    if (defverError) {
        completion(nil, defverError);
        return;
    }
    [self fetchDimFromRegistry:name defver:defver completion:completion];
}

- (nullable CSStoredDim *)getCachedDim:(NSString *)name {
    [self.cacheLock lock];
    CSStoredDim *dim = self.cachedDims[name];
    [self.cacheLock unlock];
    return dim;
}

- (void)insertCachedDimForTest:(CSStoredDim *)dim {
    [self.cacheLock lock];
    self.cachedDims[dim.name] = dim;
    if (self.manifestVersion >= 1) {
        self.manifestDims[dim.name] = @(dim.version);
    }
    [self.cacheLock unlock];
}

// The registry URL of a dim at a defver: `<base>/dims/<sha256-of-name>/<defver>.json`.
// Dims are versioned-only. Mirrors the URL half of Rust dim_url_and_cache_path.
- (NSString *)dimURLForName:(NSString *)name defver:(uint32_t)defver {
    return [self objectURLForKind:@"dims" digest:[self sha256HexForString:name] defver:defver];
}

// The cache file of a dim at a defver: `<cache>/dims/<sha256-of-name>/<defver>.json`,
// in the folder of the pinned manifest version. Mirrors the cache-path half of
// Rust dim_url_and_cache_path.
- (NSString *)dimCacheFileForName:(NSString *)name defver:(uint32_t)defver {
    return [[self class] cacheEntryPathInFolder:self.cacheDirectory kind:@"dims" key:name defver:defver];
}

// A dim body as a registry served it, for the dim `name` at `defver`: parsed
// (unknown fields refused), named and versioned as requested, and holding
// (-[CSStoredDim validate:]). Mirrors Rust checked_dim.
- (nullable CSStoredDim *)checkedDimFromData:(NSData *)data
                                        name:(NSString *)name
                                      defver:(uint32_t)defver
                                       error:(NSError *_Nullable *_Nullable)error {
    NSError *parseError = nil;
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError] : nil;
    CSStoredDim *dim = [json isKindOfClass:[NSDictionary class]] ? [CSStoredDim dimWithDictionary:json error:&parseError] : nil;
    if (!dim) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimParse, [NSString stringWithFormat:
            @"Failed to parse dim '%@': %@", name, parseError.localizedDescription ?: @"not a JSON object"], parseError);
        return nil;
    }
    if (![dim.name isEqualToString:name]) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimParse, [NSString stringWithFormat:
            @"dim object name '%@' does not match requested name '%@'", dim.name, name], nil);
        return nil;
    }
    if (dim.version != defver) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimParse, [NSString stringWithFormat:
            @"dim '%@' object reports version %u but manifest pins defver %u", dim.name, dim.version, defver], nil);
        return nil;
    }
    NSError *validateError = nil;
    if (![dim validate:&validateError]) {
        if (error) *error = CSRegistryError(CSFabricRegistryErrorDimInvalid, validateError.localizedDescription, validateError);
        return nil;
    }
    return dim;
}

// Fetch a single dim body at its pinned defver, check it, and cache it in memory
// and on disk. A registry that serves another object is a hard error, never
// silently accepted. Mirrors Rust fetch_one_dim.
- (void)fetchDimFromRegistry:(NSString *)name
                      defver:(uint32_t)defver
                  completion:(void (^)(CSStoredDim *_Nullable dim, NSError *_Nullable error))completion {
    if (defver < 1) {
        completion(nil, CSRegistryError(CSFabricRegistryErrorDimNotInManifest, [NSString stringWithFormat:
            @"dim '%@' has non-positive defver %u; dims are versioned-only", name, defver], nil));
        return;
    }
    NSString *urlString = [self dimURLForName:name defver:defver];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *netError) {
        NSError *outcome = CSFetchOutcome([NSString stringWithFormat:@"dim '%@' (defver %u)", name, defver],
                                          urlString, self.manifestVersion, response, netError);
        if (outcome) { completion(nil, outcome); return; }
        NSError *checkError = nil;
        CSStoredDim *dim = [self checkedDimFromData:data name:name defver:defver error:&checkError];
        if (!dim) {
            completion(nil, checkError);
            return;
        }
        NSDictionary *entry = @{
            @"dim": [dim toDictionary],
            @"cached_at": @((uint64_t)[[NSDate date] timeIntervalSince1970]),
            @"ttl_hours": @(CACHE_DURATION_HOURS),
        };
        NSError *writeError = nil;
        if (![[self class] storeCacheEntry:entry
                                    atPath:[self dimCacheFileForName:name defver:defver]
                                      what:@"dim"
                                     error:&writeError]) {
            completion(nil, writeError);
            return;
        }
        [self.cacheLock lock];
        self.cachedDims[dim.name] = dim;
        [self.cacheLock unlock];
        completion(dim, nil);
    }];
    [task resume];
}

// Make sure every dim a definition names is cached, fetching the ones that are
// not at the defver the manifest pins, and that each names a value the dim
// declares. `owner` names the definition in errors. Nothing about the
// definition itself is cached here: its fetcher caches it only once this
// succeeds. A dim the manifest does not list is refused before any fetch.
// Mirrors Rust ensure_dims_cached.
- (void)ensureDimsCached:(NSArray<CSDimRef *> *)refs
                   owner:(NSString *)owner
              completion:(void (^)(NSError *_Nullable error))completion {
    NSError *refsError = nil;
    if (!CSCheckDimRefs(refs, &refsError)) {
        completion(CSRegistryError(CSFabricRegistryErrorDimRefsInvalid, [NSString stringWithFormat:
            @"%@ dims: %@", owner, refsError.localizedDescription], refsError));
        return;
    }
    [self ensureDimsCached:refs fromIndex:0 owner:owner completion:completion];
}

- (void)ensureDimsCached:(NSArray<CSDimRef *> *)refs
               fromIndex:(NSUInteger)index
                   owner:(NSString *)owner
              completion:(void (^)(NSError *_Nullable error))completion {
    if (index == refs.count) {
        completion(nil);
        return;
    }
    CSDimRef *ref = refs[index];
    void (^holdValue)(CSStoredDim *) = ^(CSStoredDim *dim) {
        if (![dim valueNamed:ref.value]) {
            completion(CSRegistryError(CSFabricRegistryErrorDimValueUndeclared, [NSString stringWithFormat:
                @"%@ names value '%@' of dim '%@', which the dim does not declare", owner, ref.value, ref.dim], nil));
            return;
        }
        [self ensureDimsCached:refs fromIndex:index + 1 owner:owner completion:completion];
    };
    [self.cacheLock lock];
    CSStoredDim *cached = self.cachedDims[ref.dim];
    NSNumber *defver = self.manifestDims[ref.dim];
    uint32_t mv = self.manifestVersion;
    [self.cacheLock unlock];
    if (cached) {
        holdValue(cached);
        return;
    }
    if (mv == 0) {
        completion(CSRegistryError(CSFabricRegistryErrorDimAtV0, [NSString stringWithFormat:
            @"%@ names dim '%@', but the registry is pinned at v0 (dims are a versioned-regime concept)", owner, ref.dim], nil));
        return;
    }
    if (!defver) {
        completion(CSRegistryError(CSFabricRegistryErrorDimNotInManifest, [NSString stringWithFormat:
            @"%@ names dim '%@', which is not in manifest v%u", owner, ref.dim, mv], nil));
        return;
    }
    [self fetchDimFromRegistry:ref.dim defver:(uint32_t)[defver unsignedIntValue]
                    completion:^(CSStoredDim *dim, NSError *error) {
        if (!dim) {
            // The dim's own failure, as it is: a refused fetch stays a refused
            // fetch, and only the registry's 404 is NotFound.
            completion(error);
            return;
        }
        holdValue(dim);
    }];
}

- (void)insertCachedCapForTest:(CSCap *)cap {
    if (cap.version == 0 && self.manifestVersion >= 1) {
        cap.version = self.manifestVersion;
    }
    NSError *normError = nil;
    NSString *normalized = [self normalizeCapUrn:[cap.capUrn toString] error:&normError];
    if (!normalized) {
        NSLog(@"[CSFabricRegistry] insertCachedCapForTest: skipping cap with malformed URN: %@", normError.localizedDescription);
        return;
    }
    [self.cacheLock lock];
    self.cachedCaps[normalized] = cap;
    if (self.manifestVersion >= 1) {
        self.manifestCaps[normalized] = @(cap.version);
    }
    [self.cacheLock unlock];
}

- (NSDictionary *)manifestDictionary {
    [self.cacheLock lock];
    NSDictionary *dict = @{
        @"version": @(self.manifestVersion),
        @"previous": @(self.manifestVersion > 0 ? self.manifestVersion - 1 : 0),
        @"caps": [self.manifestCaps copy],
        @"media": [self.manifestMedia copy],
        @"aliases": [self.manifestAliases copy],
        @"dims": [self.manifestDims copy],
    };
    [self.cacheLock unlock];
    return dict;
}

@end

// MARK: - Validation Functions

void CSValidateCapCanonical(CSFabricRegistry *registry, CSCap *cap, void (^completion)(NSError *error)) {
    [registry validateCap:cap completion:completion];
}
