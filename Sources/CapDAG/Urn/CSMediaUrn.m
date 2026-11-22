//
//  CSMediaUrn.m
//  CapDAG
//
//  Media URN - a TaggedUrn with required "media:" prefix
//  Exactly mirrors Rust MediaUrn struct (src/urn/media_urn.rs)
//

#import "CSMediaUrn.h"
#import "CSTaggedUrn.h"

NSErrorDomain const CSMediaUrnErrorDomain = @"CSMediaUrnErrorDomain";

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

NSComparisonResult CSCompareTagMaps(NSDictionary<NSString *, NSString *> *a,
                                    NSDictionary<NSString *, NSString *> *b) {
    NSComparator byCodePoint = ^NSComparisonResult(NSString *x, NSString *y) {
        return CSCompareCodePoints(x, y);
    };
    NSArray<NSString *> *keysA = [a.allKeys sortedArrayUsingComparator:byCodePoint];
    NSArray<NSString *> *keysB = [b.allKeys sortedArrayUsingComparator:byCodePoint];
    NSUInteger common = MIN(keysA.count, keysB.count);
    for (NSUInteger i = 0; i < common; i++) {
        NSComparisonResult byKey = CSCompareCodePoints(keysA[i], keysB[i]);
        if (byKey != NSOrderedSame) return byKey;
        NSComparisonResult byValue = CSCompareCodePoints(a[keysA[i]], b[keysB[i]]);
        if (byValue != NSOrderedSame) return byValue;
    }
    if (keysA.count != keysB.count) {
        return keysA.count < keysB.count ? NSOrderedAscending : NSOrderedDescending;
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
    if ([urn.tags[@"void"] isEqualToString:@"*"] && urn.tags.count > 1) {
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
                                     userInfo:@{NSLocalizedDescriptionKey: parseError.localizedDescription ?: @"Failed to parse as TaggedUrn"}];
        }
        return nil;
    }

    // Validate prefix (matching Rust: check prefix == "media")
    return [self fromTaggedUrn:urn error:error];
}

- (nullable NSString *)getTag:(NSString *)key {
    return [self.inner getTag:key];
}

- (NSDictionary<NSString *, NSString *> *)tags {
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
    NSComparisonResult byPrefix = CSCompareCodePoints(self.inner.prefix, other.inner.prefix);
    if (byPrefix != NSOrderedSame) return byPrefix;
    return CSCompareTagMaps(self.tags, other.tags);
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

- (CSMediaUrn *)withTag:(NSString *)key value:(NSString *)value {
    CSTaggedUrn *modified = [self.inner withTag:key value:value];
    NSError *error;
    CSMediaUrn *result = [CSMediaUrn fromTaggedUrn:modified error:&error];
    NSAssert(result != nil, @"CSMediaUrn withTag:value: failed — inner withTag produced invalid MediaUrn: %@", error);
    return result;
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

/// Check if a marker tag (tag with wildcard/no value) is present.
/// A marker tag is stored as key="*" in the tagged URN.
- (BOOL)hasMarkerTag:(NSString *)tagName {
    NSString *value = [self getTag:tagName];
    return value != nil && [value isEqualToString:@"*"];
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
    return [[self getTag:@"fmt"] isEqualToString:@"json"];
}

- (BOOL)isYaml {
    return [[self getTag:@"fmt"] isEqualToString:@"yaml"];
}

- (BOOL)isCsv {
    return [[self getTag:@"fmt"] isEqualToString:@"csv"];
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

@end
