//
//  CSFileMediaDetection.m
//  CapDAG
//
//  What a file is: the one detection every host runs. The rule is the proved
//  model's (CapDAG.Detect: stands, mostSpecific, primary), called through the
//  C API of the program generated from it; this file does the I/O the model is
//  handed. See CSFileMediaDetection.h.
//
//  Mirrors Rust: capdag/src/input_resolver/detection.rs
//

#import "CSFileMediaDetection.h"
#import "CSInputResolver.h"
#import "CSFabricRegistry.h"
#import "CSMediaUrn.h"
@import TaggedUrn;
// Which candidates stand, which are kept and which one a host that cannot ask
// takes are decided by the program generated from the proved model in
// ../formal (see ../lungo.toml), through its C API. Its URNs are tagged-urn's
// model values, which pass to it as they are.
#import "capdagFormal.h"
#include <errno.h>
#include <stdlib.h>

const NSUInteger CSMaxContentInspectionBytes = 100 * 1024;

#pragma mark - Cartridges

@implementation CSCartridgeAdapter

+ (instancetype)adapterWithCartridgeId:(NSString *)cartridgeId adapterUrn:(CSMediaUrn *)adapterUrn {
    CSCartridgeAdapter *adapter = [[CSCartridgeAdapter alloc] init];
    adapter->_cartridgeId = [cartridgeId copy];
    adapter->_adapterUrn = adapterUrn;
    return adapter;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CSCartridgeAdapter: %@ for %@>", _cartridgeId, [_adapterUrn toString]];
}

@end

@implementation CSNoAdapters

- (NSArray<CSCartridgeAdapter *> *)adaptersForCandidates:(NSArray<CSMediaUrn *> *)candidates {
    return @[];
}

@end

@implementation CSNoInvoker

- (void)invokeAdapterSelectionForCartridge:(NSString *)cartridgeId
                                  filePath:(NSString *)filePath
                                completion:(void (^)(NSArray<NSString *> *_Nullable, NSError *_Nullable))completion {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:
                                       @"a host with no adapters was asked to consult cartridge '%@'", cartridgeId]
                                 userInfo:nil];
}

@end

#pragma mark - What a file is

@implementation CSFileMedia

+ (instancetype)fileMediaWithPath:(NSString *)path
                        sizeBytes:(uint64_t)sizeBytes
                        extension:(NSString *)extension
                       candidates:(NSArray<NSString *> *)candidates
                            media:(NSArray<NSString *> *)media {
    CSFileMedia *found = [[CSFileMedia alloc] init];
    found->_path = [path copy];
    found->_sizeBytes = sizeBytes;
    found->_extension = [extension copy];
    found->_candidates = [candidates copy];
    found->_media = [media copy];
    return found;
}

- (NSString *)primary {
    NSError *error = nil;
    NSString *primary = CSPrimaryMedia(_media, &error);
    if (!primary) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:
                                           @"a CSFileMedia holds at least one media, each a media URN it parsed; %@ does not: %@",
                                           _media, error.localizedDescription ?: @"it is empty"]
                                     userInfo:nil];
    }
    return primary;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CSFileMedia: %@ (.%@) is %@ of %@>", _path, _extension, _media, _candidates];
}

@end

/// One file media type a file's extension names, with the validation rules
/// its definition declares (nil when it declares none). Mirrors Rust:
/// FileMediaCandidate
@interface CSFileMediaCandidate : NSObject
@property (nonatomic, strong) CSMediaUrn *urn;
@property (nonatomic, copy, nullable) NSDictionary *validation;
@end

@implementation CSFileMediaCandidate
@end

#pragma mark - Errors

static NSError *CSDetectionError(CSInputResolverError code, NSString *path, NSString *message,
                                 NSDictionary *_Nullable extra) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
        NSLocalizedDescriptionKey: message,
        CSInputResolverPathKey: path,
    }];
    if (extra) [info addEntriesFromDictionary:extra];
    return [NSError errorWithDomain:CSInputResolverErrorDomain code:code userInfo:info];
}

static NSError *CSInspectionFailed(NSString *path, NSString *reason) {
    return CSDetectionError(CSInputResolverErrorInspectionFailed, path,
                            [NSString stringWithFormat:@"Content inspection failed for %@: %@", path, reason], nil);
}

#pragma mark - The model

/// A model call that fails is a broken invariant — a value this file built that
/// the model cannot take, or a runtime that is not working — and there is no
/// answer to give instead.
static void CSDetectModelFailed(NSString *what, lungo_error *error) {
    NSString *reason = [NSString stringWithFormat:@"capdag: the model could not %@: %s", what,
                        error ? lungo_error_message(error) : "no error was reported"];
    if (error) lungo_error_free(error);
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

/// A list of the model's values, taking ownership of each of `items`.
static lungo_value *CSDetectModelList(lungo_value **items, NSUInteger count) {
    return lungo_value_list(items, (size_t)count);
}

/// The URNs as the model's list of URNs; owned.
static lungo_value *CSDetectModelUrns(NSArray<CSMediaUrn *> *urns) {
    lungo_value **items = calloc(MAX(urns.count, (NSUInteger)1), sizeof(lungo_value *));
    for (NSUInteger i = 0; i < urns.count; i++) {
        items[i] = lungo_value_clone(urns[i].inner.formalValue);
    }
    lungo_value *list = CSDetectModelList(items, urns.count);
    free(items);
    return list;
}

#pragma mark - Validation rules

/// The rule `key` of a definition's validation, nil when it declares none.
static id _Nullable CSRule(NSDictionary *rules, NSString *key) {
    id value = rules[key];
    return [value isKindOfClass:[NSNull class]] ? nil : value;
}

/// Does the definition declare any rule?
static BOOL CSDeclaresRules(NSDictionary *_Nullable rules) {
    if (!rules) return NO;
    for (NSString *key in @[@"pattern", @"min_length", @"max_length", @"allowed_values", @"min", @"max"]) {
        if (CSRule(rules, key) != nil) return YES;
    }
    return NO;
}

/// A rule of the wrong kind is a defect of the definition, and an error naming
/// it and the rule.
static NSString *CSRuleOfWrongKind(CSMediaUrn *urn, NSString *key, NSString *kind) {
    return [NSString stringWithFormat:@"the media definition '%@' declares a validation '%@' that is not %@",
            [urn toString], key, kind];
}

/// The trimmed text read as a number, or nil when it is none.
static NSNumber *_Nullable CSNumberOfText(NSString *_Nullable text) {
    if (!text) return nil;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    scanner.charactersToBeSkipped = nil;
    double value = 0;
    if (![scanner scanDouble:&value] || !scanner.isAtEnd) return nil;
    return @(value);
}

/// Whether every rule the definition declares is of its kind: a string
/// pattern, numeric lengths and bounds, a list of string allowed values. NO
/// with *failure naming the definition and the rule.
static BOOL CSRulesAreOfTheirKinds(CSMediaUrn *urn, NSDictionary *rules, NSString **failure) {
    NSDictionary<NSString *, NSString *> *numbers = @{@"min_length": @"a number", @"max_length": @"a number",
                                                      @"min": @"a number", @"max": @"a number"};
    for (NSString *key in numbers) {
        id rule = CSRule(rules, key);
        if (rule && ![rule isKindOfClass:[NSNumber class]]) {
            *failure = CSRuleOfWrongKind(urn, key, numbers[key]);
            return NO;
        }
    }
    id pattern = CSRule(rules, @"pattern");
    if (pattern && ![pattern isKindOfClass:[NSString class]]) {
        *failure = CSRuleOfWrongKind(urn, @"pattern", @"a string");
        return NO;
    }
    id allowed = CSRule(rules, @"allowed_values");
    if (allowed) {
        BOOL strings = [allowed isKindOfClass:[NSArray class]];
        for (id value in (strings ? (NSArray *)allowed : @[])) {
            if (![value isKindOfClass:[NSString class]]) strings = NO;
        }
        if (!strings) {
            *failure = CSRuleOfWrongKind(urn, @"allowed_values", @"a list of strings");
            return NO;
        }
    }
    return YES;
}

/// What the rules say of the content: YES with *outMet when they could be
/// read, NO with *failure naming the definition when one is not a rule (an
/// invalid pattern, or a rule of the wrong kind). Mirrors Rust `meets`.
static BOOL CSMeets(NSData *content, CSMediaUrn *urn, NSDictionary *rules, BOOL *outMet, NSString **failure) {
    *outMet = NO;
    if (!CSRulesAreOfTheirKinds(urn, rules, failure)) return NO;
    NSString *text = [[NSString alloc] initWithData:content encoding:NSUTF8StringEncoding];

    NSString *pattern = CSRule(rules, @"pattern");
    if (pattern) {
        NSError *regexError = nil;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&regexError];
        if (!re) {
            *failure = [NSString stringWithFormat:@"the media definition '%@' declares an invalid validation pattern '%@': %@",
                        [urn toString], pattern, regexError.localizedDescription ?: @"it does not compile"];
            return NO;
        }
        if (!text || [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] == nil) {
            return YES;
        }
    }
    NSNumber *minLength = CSRule(rules, @"min_length");
    if (minLength && content.length < minLength.unsignedIntegerValue) return YES;
    NSNumber *maxLength = CSRule(rules, @"max_length");
    if (maxLength && content.length > maxLength.unsignedIntegerValue) return YES;
    NSArray<NSString *> *allowed = CSRule(rules, @"allowed_values");
    if (allowed) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed || ![allowed containsObject:trimmed]) return YES;
    }
    NSNumber *min = CSRule(rules, @"min");
    NSNumber *max = CSRule(rules, @"max");
    if (min || max) {
        NSNumber *value = CSNumberOfText(text);
        if (!value) return YES;
        if (min && value.doubleValue < min.doubleValue) return YES;
        if (max && value.doubleValue > max.doubleValue) return YES;
    }
    *outMet = YES;
    return YES;
}

/// What a candidate's rules say of the content, as the model takes it (owned),
/// or NULL with *failure naming the definition.
static lungo_value *_Nullable CSRulesVerdict(NSData *content, CSFileMediaCandidate *candidate, NSString **failure) {
    if (!CSDeclaresRules(candidate.validation)) return capdagFormal_rules_unruled();
    BOOL met = NO;
    if (!CSMeets(content, candidate.urn, candidate.validation, &met, failure)) return NULL;
    return met ? capdagFormal_rules_met() : capdagFormal_rules_unmet();
}

#pragma mark - The decision

/// The candidates that stand (the model's `stands`), in the candidates'
/// order, given the consulted adapters' URNs and what their cartridges
/// claimed; nil with *failure when a definition's rules cannot be read.
static NSArray<CSMediaUrn *> *_Nullable CSSurvivingCandidates(NSData *content,
                                                              NSArray<CSFileMediaCandidate *> *candidates,
                                                              NSArray<CSMediaUrn *> *owners,
                                                              NSArray<CSMediaUrn *> *claims,
                                                              NSString **failure) {
    NSUInteger n = candidates.count;
    lungo_value **modelled = calloc(MAX(n, (NSUInteger)1), sizeof(lungo_value *));
    for (NSUInteger i = 0; i < n; i++) {
        lungo_value *rules = CSRulesVerdict(content, candidates[i], failure);
        if (!rules) {
            for (NSUInteger j = 0; j < i; j++) lungo_value_free(modelled[j]);
            free(modelled);
            return nil;
        }
        modelled[i] = capdagFormal_candidate_mk(lungo_value_clone(candidates[i].urn.inner.formalValue), rules);
    }
    lungo_value **cloned = calloc(MAX(n, (NSUInteger)1), sizeof(lungo_value *));
    for (NSUInteger i = 0; i < n; i++) cloned[i] = lungo_value_clone(modelled[i]);
    lungo_value *all = CSDetectModelList(cloned, n);
    free(cloned);
    lungo_value *ownerList = CSDetectModelUrns(owners);
    lungo_value *claimList = CSDetectModelUrns(claims);

    NSMutableArray<CSMediaUrn *> *standing = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++) {
        lungo_value *result = NULL;
        lungo_error *error = NULL;
        if (capdagFormal_stands(all, ownerList, claimList, modelled[i], &result, &error) != LUNGO_OK) {
            CSDetectModelFailed(@"decide whether a candidate stands", error);
        }
        if (lungo_value_get_bool(result)) [standing addObject:candidates[i].urn];
        lungo_value_free(result);
    }
    for (NSUInteger i = 0; i < n; i++) lungo_value_free(modelled[i]);
    free(modelled);
    lungo_value_free(all);
    lungo_value_free(ownerList);
    lungo_value_free(claimList);
    return standing;
}

/// Of what stands, the most specific member of each line of refinement (the
/// model's `mostSpecific`), in order, written as capdag writes media URNs.
/// This library has no value adapters to refine what stands first.
static NSArray<NSString *> *CSSettle(NSArray<CSMediaUrn *> *survivors) {
    NSMutableArray<CSMediaUrn *> *distinct = [NSMutableArray arrayWithCapacity:survivors.count];
    for (CSMediaUrn *urn in survivors) {
        BOOL seen = NO;
        for (CSMediaUrn *kept in distinct) {
            if ([kept isEquivalentTo:urn]) {
                seen = YES;
                break;
            }
        }
        if (!seen) [distinct addObject:urn];
    }
    lungo_value *all = CSDetectModelUrns(distinct);
    NSMutableArray<NSString *> *media = [NSMutableArray arrayWithCapacity:distinct.count];
    for (CSMediaUrn *urn in distinct) {
        lungo_value *result = NULL;
        lungo_error *error = NULL;
        if (capdagFormal_most_specific(all, urn.inner.formalValue, &result, &error) != LUNGO_OK) {
            CSDetectModelFailed(@"decide the most specific media", error);
        }
        if (lungo_value_get_bool(result)) [media addObject:[urn toString]];
        lungo_value_free(result);
    }
    lungo_value_free(all);
    return media;
}

NSString *_Nullable CSPrimaryMedia(NSArray<NSString *> *media, NSError *_Nullable *_Nullable error) {
    NSMutableArray<CSMediaUrn *> *urns = [NSMutableArray arrayWithCapacity:media.count];
    for (NSString *m in media) {
        NSError *parseError = nil;
        CSMediaUrn *urn = [CSMediaUrn fromString:m error:&parseError];
        if (!urn) {
            if (error) *error = [NSError errorWithDomain:CSMediaUrnErrorDomain
                                                    code:CSMediaUrnErrorParse
                                                userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"'%@' is no media URN: %@",
                                            m, parseError.localizedDescription ?: @"it does not parse"],
            }];
            return nil;
        }
        [urns addObject:urn];
    }
    lungo_value *all = CSDetectModelUrns(urns);
    lungo_value *result = NULL;
    lungo_error *modelError = NULL;
    if (capdagFormal_primary(all, &result, &modelError) != LUNGO_OK) {
        lungo_value_free(all);
        CSDetectModelFailed(@"pick the primary media", modelError);
    }
    lungo_value_free(all);
    const lungo_value *position = lungo_value_get_option(result);
    NSString *primary = nil;
    if (position) {
        uint64_t index = 0;
        if (!lungo_value_get_nat(position, &index) || index >= (uint64_t)media.count) {
            lungo_value_free(result);
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:@"capdag: the model's primary media is no position of the list it was given"
                                         userInfo:nil];
        }
        primary = media[(NSUInteger)index];
    }
    lungo_value_free(result);
    return primary;
}

#pragma mark - The I/O

/// A file's extension, lowercased; empty when it has none (a name with no dot,
/// or whose only dot leads it).
static NSString *CSLowercaseExtension(NSString *path) {
    NSString *name = [path lastPathComponent];
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound || dot.location == 0) return @"";
    return [[name substringFromIndex:dot.location + 1] lowercaseString];
}

/// The file media types a file with this extension can be, with their
/// validation rules: the fabric's answer, loaded when first asked.
static void CSCandidatesFor(NSString *path, NSString *extension, CSFabricRegistry *registry,
                            void (^completion)(NSArray<CSFileMediaCandidate *> *_Nullable candidates,
                                               NSError *_Nullable error)) {
    if (extension.length == 0) {
        completion(nil, CSDetectionError(CSInputResolverErrorNoExtension, path,
            [NSString stringWithFormat:@"%@ has no extension to tell its type from", path], nil));
        return;
    }
    [registry fileMediaForExtension:extension completion:^(NSArray<NSDictionary *> *definitions, NSError *error) {
        if (!definitions) {
            completion(nil, CSDetectionError(CSInputResolverErrorFabricUnavailable, path,
                [NSString stringWithFormat:@"the type of %@ cannot be told: %@", path, error.localizedDescription],
                error ? @{NSUnderlyingErrorKey: error} : nil));
            return;
        }
        if (definitions.count == 0) {
            completion(nil, CSDetectionError(CSInputResolverErrorUnknownExtension, path,
                [NSString stringWithFormat:@"the fabric declares no file type for the extension .%@ of %@", extension, path],
                @{CSInputResolverExtensionKey: extension}));
            return;
        }
        NSMutableArray<CSFileMediaCandidate *> *candidates = [NSMutableArray arrayWithCapacity:definitions.count];
        for (NSDictionary *definition in definitions) {
            id urnString = definition[@"urn"];
            NSError *parseError = nil;
            CSMediaUrn *urn = [urnString isKindOfClass:[NSString class]]
                ? [CSMediaUrn fromString:urnString error:&parseError]
                : nil;
            if (!urn) {
                completion(nil, CSInspectionFailed(path, [NSString stringWithFormat:
                    @"the fabric's media definition '%@' has no valid URN: %@",
                    urnString, parseError.localizedDescription ?: @"it is not a string"]));
                return;
            }
            id validation = definition[@"validation"];
            if ([validation isKindOfClass:[NSNull class]]) validation = nil;
            if (validation && ![validation isKindOfClass:[NSDictionary class]]) {
                completion(nil, CSInspectionFailed(path, [NSString stringWithFormat:
                    @"the media definition '%@' has a 'validation' that is not an object", [urn toString]]));
                return;
            }
            CSFileMediaCandidate *candidate = [[CSFileMediaCandidate alloc] init];
            candidate.urn = urn;
            candidate.validation = validation;
            [candidates addObject:candidate];
        }
        completion(candidates, nil);
    }];
}

/// Whether `error`, or an error under it, is the Cocoa file error or POSIX
/// error given.
static BOOL CSFileErrorIs(NSError *error, NSArray<NSNumber *> *cocoaCodes, int posixCode) {
    for (NSError *e = error; e != nil; e = e.userInfo[NSUnderlyingErrorKey]) {
        if ([e.domain isEqualToString:NSCocoaErrorDomain] && [cocoaCodes containsObject:@(e.code)]) return YES;
        if ([e.domain isEqualToString:NSPOSIXErrorDomain] && e.code == posixCode) return YES;
    }
    return NO;
}

static NSError *CSReadError(NSString *path, NSError *error) {
    if (CSFileErrorIs(error, @[@(NSFileNoSuchFileError), @(NSFileReadNoSuchFileError)], ENOENT)) {
        return CSDetectionError(CSInputResolverErrorNotFound, path,
            [NSString stringWithFormat:@"Path not found: %@", path], @{NSUnderlyingErrorKey: error});
    }
    if (CSFileErrorIs(error, @[@(NSFileReadNoPermissionError)], EACCES)) {
        return CSDetectionError(CSInputResolverErrorPermissionDenied, path,
            [NSString stringWithFormat:@"Permission denied: %@", path], @{NSUnderlyingErrorKey: error});
    }
    return CSDetectionError(CSInputResolverErrorIOError, path,
        [NSString stringWithFormat:@"IO error at %@: %@", path, error.localizedDescription], @{NSUnderlyingErrorKey: error});
}

/// The file's size, and the first CSMaxContentInspectionBytes of its content.
static BOOL CSReadPrefix(NSString *path, uint64_t *outSize, NSData *_Nullable *_Nonnull outContent,
                         NSError *_Nullable *_Nullable error) {
    *outContent = nil;
    NSError *ioError = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&ioError];
    if (!attributes) {
        if (error) *error = CSReadError(path, ioError);
        return NO;
    }
    *outSize = [attributes[NSFileSize] unsignedLongLongValue];
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:path] error:&ioError];
    if (!handle) {
        if (error) *error = CSReadError(path, ioError);
        return NO;
    }
    NSData *content = [handle readDataUpToLength:CSMaxContentInspectionBytes error:&ioError];
    [handle closeAndReturnError:nil];
    if (!content) {
        if (error) *error = CSReadError(path, ioError);
        return NO;
    }
    *outContent = content;
    return YES;
}

/// Ask every cartridge whose adapter covers a candidate, from `index` on, what
/// the file is, one after another. Every covering adapter's URN is an owner;
/// a cartridge is asked once. A cartridge that declines, or fails, claims
/// nothing; its domain stays covered, so its candidates fall.
static void CSConsultFrom(NSArray<CSCartridgeAdapter *> *pairs, NSUInteger index, NSString *path,
                          id<CSCartridgeAdapterInvoker> invoker, NSMutableSet<NSString *> *asked,
                          NSMutableArray<CSMediaUrn *> *owners, NSMutableArray<CSMediaUrn *> *claims,
                          void (^done)(void)) {
    while (index < pairs.count) {
        CSCartridgeAdapter *pair = pairs[index];
        [owners addObject:pair.adapterUrn];
        if ([asked containsObject:pair.cartridgeId]) {
            index += 1;
            continue;
        }
        [asked addObject:pair.cartridgeId];
        NSUInteger next = index + 1;
        [invoker invokeAdapterSelectionForCartridge:pair.cartridgeId
                                           filePath:path
                                         completion:^(NSArray<NSString *> *answer, NSError *error) {
            if (error) {
                NSLog(@"[CSFileMediaDetection] cartridge '%@' (adapter %@) failed to inspect %@: %@",
                      pair.cartridgeId, [pair.adapterUrn toString], path, error.localizedDescription);
            } else {
                for (NSString *claim in answer) {
                    NSError *parseError = nil;
                    CSMediaUrn *urn = [CSMediaUrn fromString:claim error:&parseError];
                    if (urn) {
                        [claims addObject:urn];
                    } else {
                        NSLog(@"[CSFileMediaDetection] cartridge '%@' claimed %@ as '%@', which is no media URN: %@",
                              pair.cartridgeId, path, claim, parseError.localizedDescription);
                    }
                }
            }
            CSConsultFrom(pairs, next, path, invoker, asked, owners, claims, done);
        }];
        return;
    }
    done();
}

void CSDetectFileMedia(NSString *path,
                       CSFabricRegistry *registry,
                       id<CSAdapterSource> adapters,
                       id<CSCartridgeAdapterInvoker> invoker,
                       void (^completion)(CSFileMedia *_Nullable found, NSError *_Nullable error)) {
    NSString *extension = CSLowercaseExtension(path);
    CSCandidatesFor(path, extension, registry, ^(NSArray<CSFileMediaCandidate *> *candidates, NSError *error) {
        if (!candidates) {
            completion(nil, error);
            return;
        }
        uint64_t sizeBytes = 0;
        NSData *content = nil;
        NSError *readError = nil;
        if (!CSReadPrefix(path, &sizeBytes, &content, &readError)) {
            completion(nil, readError);
            return;
        }
        NSMutableArray<CSMediaUrn *> *urns = [NSMutableArray arrayWithCapacity:candidates.count];
        NSMutableArray<NSString *> *candidateStrings = [NSMutableArray arrayWithCapacity:candidates.count];
        for (CSFileMediaCandidate *candidate in candidates) {
            [urns addObject:candidate.urn];
            [candidateStrings addObject:[candidate.urn toString]];
        }
        NSArray<CSCartridgeAdapter *> *pairs = [adapters adaptersForCandidates:urns];
        NSMutableArray<CSMediaUrn *> *owners = [NSMutableArray array];
        NSMutableArray<CSMediaUrn *> *claims = [NSMutableArray array];
        CSConsultFrom(pairs, 0, path, invoker, [NSMutableSet set], owners, claims, ^{
            NSString *failure = nil;
            NSArray<CSMediaUrn *> *survivors = CSSurvivingCandidates(content, candidates, owners, claims, &failure);
            if (!survivors) {
                completion(nil, CSInspectionFailed(path, failure));
                return;
            }
            if (survivors.count == 0) {
                completion(nil, CSInspectionFailed(path, [NSString stringWithFormat:
                    @"its content is none of the %lu media types the fabric declares for .%@",
                    (unsigned long)candidates.count, extension]));
                return;
            }
            completion([CSFileMedia fileMediaWithPath:path
                                            sizeBytes:sizeBytes
                                            extension:extension
                                           candidates:candidateStrings
                                                media:CSSettle(survivors)], nil);
        });
    });
}

void CSExtensionMedia(NSString *extension,
                      CSFabricRegistry *registry,
                      void (^completion)(NSArray<NSString *> *_Nullable media, NSError *_Nullable error)) {
    NSString *lowered = [extension lowercaseString];
    NSString *path = [NSString stringWithFormat:@"*.%@", extension];
    CSCandidatesFor(path, lowered, registry, ^(NSArray<CSFileMediaCandidate *> *candidates, NSError *error) {
        if (!candidates) {
            completion(nil, error);
            return;
        }
        NSMutableArray<CSFileMediaCandidate *> *unread = [NSMutableArray arrayWithCapacity:candidates.count];
        for (CSFileMediaCandidate *candidate in candidates) {
            CSFileMediaCandidate *bare = [[CSFileMediaCandidate alloc] init];
            bare.urn = candidate.urn;
            [unread addObject:bare];
        }
        NSString *failure = nil;
        NSArray<CSMediaUrn *> *bases = CSSurvivingCandidates([NSData data], unread, @[], @[], &failure);
        if (!bases) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:
                                               @"candidates with no rules are decided without reading a pattern: %@", failure]
                                         userInfo:nil];
        }
        NSMutableArray<NSString *> *media = [NSMutableArray arrayWithCapacity:bases.count];
        for (CSMediaUrn *urn in bases) [media addObject:[urn toString]];
        completion(media, nil);
    });
}
