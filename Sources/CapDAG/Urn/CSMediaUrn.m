//
//  CSMediaUrn.m
//  CapDAG
//
//  Media URN - a TaggedUrn with required "media:" prefix
//  Exactly mirrors Rust MediaUrn struct (src/urn/media_urn.rs)
//

#import "CSMediaUrn.h"
#import "CSTaggedUrn.h"
// A media type's shapes and the bookends it ends on are decided by the program generated from
// the proved model in ../formal (see ../lungo.toml), through its C API. Its URNs are
// tagged-urn's model values, which pass to it as they are.
#import "capdagFormal.h"
#include <stdlib.h>

NSErrorDomain const CSMediaUrnErrorDomain = @"CSMediaUrnErrorDomain";

/// A model call that fails is a broken invariant — a media URN this class holds that the model
/// cannot take, or a runtime that is not working — and there is no answer to give instead.
static void CSMediaUrnModelFailed(NSString *what, lungo_error *error) {
    NSString *reason = [NSString stringWithFormat:@"capdag: the model could not %@: %s", what,
                        error ? lungo_error_message(error) : "no error was reported"];
    if (error) lungo_error_free(error);
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

NSComparisonResult CSCompareCodePoints(NSString *a, NSString *b) {
    // UTF-8 byte order is Unicode code point order.
    NSData *bytesA = [a dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bytesB = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (bytesA == nil || bytesB == nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"a URN component is not valid Unicode: '%@' or '%@'", a, b];
    }
    NSUInteger common = MIN(bytesA.length, bytesB.length);
    int cmp = common > 0 ? memcmp(bytesA.bytes, bytesB.bytes, common) : 0;
    if (cmp != 0) {
        return cmp < 0 ? NSOrderedAscending : NSOrderedDescending;
    }
    if (bytesA.length != bytesB.length) {
        return bytesA.length < bytesB.length ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

@implementation CSMediaUrn

+ (NSString *)PREFIX {
    return @"media";
}

+ (nullable instancetype)fromTaggedUrn:(CSTaggedUrn *)urn error:(NSError **)error {
    if (!urn) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaUrnErrorDomain
                                         code:CSMediaUrnErrorParse
                                     userInfo:@{NSLocalizedDescriptionKey: @"TaggedUrn cannot be nil"}];
        }
        return nil;
    }

    // Validate prefix is "media" (case-insensitive, matching Rust behavior)
    if (![[urn.prefix lowercaseString] isEqualToString:@"media"]) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaUrnErrorDomain
                                         code:CSMediaUrnErrorInvalidPrefix
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Expected 'media' prefix, got '%@'", urn.prefix]}];
        }
        return nil;
    }

    // Enforce media:void atomicity. The unit type has no lattice
    // underneath it; refinements like media:void;text or
    // media:void;reason=warmup are conceptually wrong. Reasons or
    // labels belong on cap-tags or args. Only the void marker is atomic:
    // media:!void;… and media:?void;… do not say void.
    if ([urn hasMarkerTag:@"void"] && urn.tags.count > 1) {
        NSMutableArray<NSString *> *extras = [NSMutableArray array];
        for (NSString *key in urn.tags) {
            if (![key isEqualToString:@"void"]) {
                [extras addObject:key];
            }
        }
        [extras sortUsingSelector:@selector(compare:)];
        if (error) {
            NSString *msg = [NSString stringWithFormat:
                @"media:void is atomic and cannot be refined; got extra tag(s): %@. "
                @"Move why/how this void is used into cap-tags or args, not the media URN.",
                [extras componentsJoinedByString:@", "]];
            *error = [NSError errorWithDomain:CSMediaUrnErrorDomain
                                         code:CSMediaUrnErrorVoidNotAtomic
                                     userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        return nil;
    }

    CSMediaUrn *mediaUrn = [[CSMediaUrn alloc] init];
    mediaUrn->_inner = urn;
    return mediaUrn;
}

+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error {
    // Parse as TaggedUrn first (matching Rust: TaggedUrn::from_str then try_into)
    NSError *parseError = nil;
    CSTaggedUrn *urn = [CSTaggedUrn fromString:string error:&parseError];
    if (!urn) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaUrnErrorDomain
                                         code:CSMediaUrnErrorParse
                                     userInfo:@{NSLocalizedDescriptionKey: parseError.localizedDescription,
                                                NSUnderlyingErrorKey: parseError}];
        }
        return nil;
    }

    // Validate prefix (matching Rust: check prefix == "media")
    return [self fromTaggedUrn:urn error:error];
}

- (nullable CSTagConstraint *)getTag:(NSString *)key {
    return [self.inner getTag:key];
}

- (nullable NSString *)exactValue:(NSString *)key {
    return [self.inner getTag:key].exactValue;
}

- (NSDictionary<NSString *, CSTagConstraint *> *)tags {
    return self.inner.tags;
}

- (NSString *)toString {
    return [self.inner toString];
}

- (NSString *)description {
    return [self toString];
}

/// A comparison's answer. The tagged-URN comparisons fail only on a prefix
/// mismatch, which two media URNs never have, so a failure is a programming
/// error and raises, naming the comparison.
static BOOL CSMediaUrnDecided(BOOL result, NSError *error, NSString *comparison) {
    if (error) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"MediaUrn %@: every MediaUrn has the media prefix: %@", comparison, error.localizedDescription];
    }
    return result;
}

- (BOOL)conformsTo:(CSMediaUrn *)pattern {
    NSError *error = nil;
    BOOL result = [self.inner conformsTo:pattern.inner error:&error];
    return CSMediaUrnDecided(result, error, @"conformsTo");
}

- (BOOL)accepts:(CSMediaUrn *)instance {
    NSError *error = nil;
    BOOL result = [self.inner accepts:instance.inner error:&error];
    return CSMediaUrnDecided(result, error, @"accepts");
}

- (BOOL)meets:(CSMediaUrn *)other {
    NSError *error = nil;
    BOOL result = [self.inner meets:other.inner error:&error];
    return CSMediaUrnDecided(result, error, @"meets");
}

- (BOOL)satisfies:(CSMediaUrn *)pattern {
    NSError *error = nil;
    BOOL result = [self.inner satisfies:pattern.inner error:&error];
    return CSMediaUrnDecided(result, error, @"satisfies");
}

- (BOOL)maySatisfy:(CSMediaUrn *)pattern {
    NSError *error = nil;
    BOOL result = [self.inner maySatisfy:pattern.inner error:&error];
    return CSMediaUrnDecided(result, error, @"maySatisfy");
}

- (BOOL)isEquivalentTo:(CSMediaUrn *)other {
    return [self accepts:other] && [other accepts:self];
}

- (BOOL)isComparableTo:(CSMediaUrn *)other {
    // Comparable: either side accepts the other (same specialization chain).
    // Mirrors Rust MediaUrn::is_comparable.
    return [self accepts:other] || [other accepts:self];
}

- (NSComparisonResult)compareStructurally:(CSMediaUrn *)other {
    return [self.inner compare:other.inner];
}

- (nullable CSTaggedUrnCoordinateDelta *)deltaFrom:(CSMediaUrn *)base error:(NSError **)error {
    return [self.inner deltaFrom:base.inner error:error];
}

- (nullable CSMediaUrn *)applyDelta:(CSTaggedUrnCoordinateDelta *)delta error:(NSError **)error {
    CSTaggedUrn *applied = [self.inner applyDelta:delta error:error];
    if (!applied) {
        return nil;
    }
    return [CSMediaUrn fromTaggedUrn:applied error:error];
}

// MARK: - Builders

- (nullable CSMediaUrn *)withTag:(NSString *)key constraint:(CSTagConstraint *)constraint error:(NSError **)error {
    CSTaggedUrn *modified = [self.inner withTag:key constraint:constraint error:error];
    if (!modified) {
        return nil;
    }
    return [CSMediaUrn fromTaggedUrn:modified error:error];
}

- (CSMediaUrn *)withoutTag:(NSString *)key {
    CSTaggedUrn *modified = [self.inner withoutTag:key];
    NSError *error;
    CSMediaUrn *result = [CSMediaUrn fromTaggedUrn:modified error:&error];
    NSAssert(result != nil, @"CSMediaUrn withoutTag: failed — inner withoutTag produced invalid MediaUrn: %@", error);
    return result;
}

- (CSMediaUrn *)referenceBase {
    CSTaggedUrn *base = self.inner;
    for (NSString *key in self.inner.tags) {
        if ([self.inner admitsAbsence:key]) {
            base = [base withoutTag:key];
        }
    }
    NSError *error;
    CSMediaUrn *result = [CSMediaUrn fromTaggedUrn:base error:&error];
    NSAssert(result != nil, @"CSMediaUrn referenceBase failed — dropping tags produced an invalid MediaUrn: %@", error);
    return result;
}

// MARK: - Helper: Check for marker tag presence

/// Whether a marker tag (present, written as just the key) is present.
- (BOOL)hasMarkerTag:(NSString *)tagName {
    return [self.inner hasMarkerTag:tagName];
}

// MARK: - Predicates

// MARK: - Cardinality (list marker)

- (BOOL)isList {
    return [self hasMarkerTag:@"list"];
}

- (BOOL)isScalar {
    return ![self hasMarkerTag:@"list"];
}

// MARK: - Structure (record marker)

- (BOOL)isRecord {
    return [self hasMarkerTag:@"record"];
}

- (BOOL)isOpaque {
    return ![self hasMarkerTag:@"record"];
}

- (BOOL)isJson {
    return [[self exactValue:@"fmt"] isEqualToString:@"json"];
}

- (BOOL)isYaml {
    return [[self exactValue:@"fmt"] isEqualToString:@"yaml"];
}

- (BOOL)isCsv {
    return [[self exactValue:@"fmt"] isEqualToString:@"csv"];
}

- (BOOL)isVoid {
    return [self hasMarkerTag:@"void"];
}

- (BOOL)isTop {
    return self.inner.tags.count == 0;
}

- (BOOL)isImage {
    return [self hasMarkerTag:@"image"];
}

- (BOOL)isAudio {
    return [self hasMarkerTag:@"audio"];
}

- (BOOL)isVideo {
    return [self hasMarkerTag:@"video"];
}

- (BOOL)isNumeric {
    return [self hasMarkerTag:@"numeric"];
}

- (BOOL)isBool {
    return [self hasMarkerTag:@"bool"];
}

- (BOOL)isFilePath {
    // Single file-path media URN; cardinality (single file vs many) is
    // carried on the wire via is_sequence, not via URN tags.
    return [self hasMarkerTag:@"file-path"];
}

// MARK: - Specificity

- (NSInteger)specificity {
    // The graded per-tag score (?x=0 … !x=5), not the tag count: a count
    // ranked `media:x` level with `media:!x` and disagreed with the cap
    // score, which grades its in and out axes this way.
    return (NSInteger)[self.inner specificity];
}

// MARK: - List type queries (semantic, not shape)
// withList and withoutList have been removed — the list tag is a semantic type
// indicator (the data IS a list), not a shape indicator. Shape is tracked via
// is_sequence on the wire protocol, not by manipulating URNs.

+ (CSMediaUrn *)lub:(NSArray<CSMediaUrn *> *)urns {
    NSMutableArray<CSTaggedUrn *> *tagged = [NSMutableArray arrayWithCapacity:urns.count];
    for (CSMediaUrn *urn in urns) [tagged addObject:urn.inner];
    NSError *err = nil;
    CSTaggedUrn *bound = [CSTaggedUrn leastUpperBoundWithPrefix:@"media" urns:tagged error:&err];
    NSAssert(bound != nil, @"Every CSMediaUrn has the media prefix: %@", err);
    CSMediaUrn *result = [CSMediaUrn fromTaggedUrn:bound error:&err];
    NSAssert(result != nil, @"The bound of media URNs is a media URN: %@", err);
    return result;
}

// MARK: - Shapes and bookends

/// The media URNs a list of the model's URN values stands for: values the model gave back for
/// media URNs it was handed, so each is a media URN; one that is not is a broken invariant.
static NSArray<CSMediaUrn *> *CSMediaUrnsOfModel(const lungo_value *list) {
    size_t count = lungo_value_count(list);
    NSMutableArray<CSMediaUrn *> *urns = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) {
        NSError *error = nil;
        CSTaggedUrn *tagged = [CSTaggedUrn fromFormal:lungo_value_item(list, i) error:&error];
        CSMediaUrn *media = tagged ? [CSMediaUrn fromTaggedUrn:tagged error:&error] : nil;
        if (!media) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:@"capdag: the model gave back no media URN for media URNs: %@", error.localizedDescription]
                                         userInfo:nil];
        }
        [urns addObject:media];
    }
    return urns;
}

- (NSArray<CSMediaUrn *> *)splits {
    lungo_value *result = NULL;
    lungo_error *error = NULL;
    if (capdagFormal_splits(self.inner.formalValue, &result, &error) != LUNGO_OK) {
        CSMediaUrnModelFailed(@"split a media type into its shapes", error);
    }
    NSArray<CSMediaUrn *> *parts = CSMediaUrnsOfModel(result);
    lungo_value_free(result);
    return parts;
}

- (nullable NSArray<CSMediaUrn *> *)endsOn:(NSArray<CSMediaUrn *> *)bookends {
    // The list takes ownership of each item.
    lungo_value **items = calloc(MAX(bookends.count, (NSUInteger)1), sizeof(lungo_value *));
    for (NSUInteger i = 0; i < bookends.count; i++) {
        items[i] = lungo_value_clone(bookends[i].inner.formalValue);
    }
    lungo_value *list = lungo_value_list(items, (size_t)bookends.count);
    free(items);
    lungo_value *result = NULL;
    lungo_error *error = NULL;
    int32_t status = capdagFormal_ends_on(list, self.inner.formalValue, &result, &error);
    lungo_value_free(list);
    if (status != LUNGO_OK) {
        CSMediaUrnModelFailed(@"say which bookends a media type ends on", error);
    }
    const lungo_value *ends = lungo_value_get_option(result);
    NSArray<CSMediaUrn *> *answer = ends ? CSMediaUrnsOfModel(ends) : nil;
    lungo_value_free(result);
    return answer;
}

@end
