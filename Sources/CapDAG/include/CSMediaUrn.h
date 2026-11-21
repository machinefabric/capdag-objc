//
//  CSMediaUrn.h
//  CapDAG
//
//  Media URN - a TaggedUrn with required "media:" prefix
//  Exactly mirrors Rust MediaUrn struct (src/urn/media_urn.rs)
//

#import <Foundation/Foundation.h>

@class CSTaggedUrn;
@class CSTagConstraint;
@class CSTaggedUrnCoordinateDelta;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const CSMediaUrnErrorDomain;

typedef NS_ERROR_ENUM(CSMediaUrnErrorDomain, CSMediaUrnError) {
    CSMediaUrnErrorInvalidPrefix = 1,
    CSMediaUrnErrorParse = 2,
    /// `media:void` was combined with one or more other tags. The
    /// unit type is atomic — there is no lattice underneath it.
    /// Reasons for "why void was used" belong on the cap URN's
    /// non-directional tags or in the cap's args.
    CSMediaUrnErrorVoidNotAtomic = 3
};

/// Two strings in Unicode code point order, as Rust orders `String`s (not
/// `-compare:`, which orders UTF-16 code units).
FOUNDATION_EXPORT NSComparisonResult CSCompareCodePoints(NSString *a, NSString *b);

/// Media URN - a TaggedUrn with required "media:" prefix
/// Mirrors Rust: pub struct MediaUrn(TaggedUrn)
@interface CSMediaUrn : NSObject

/// The required prefix for all media URNs
@property (class, nonatomic, readonly) NSString *PREFIX;

/// The underlying TaggedUrn
@property (nonatomic, strong, readonly) CSTaggedUrn *inner;

/// Create a MediaUrn from a TaggedUrn
/// Returns nil if the TaggedUrn doesn't have the "media" prefix
/// Mirrors Rust: impl TryFrom<TaggedUrn> for MediaUrn
+ (nullable instancetype)fromTaggedUrn:(CSTaggedUrn *)urn error:(NSError **)error;

/// Create a MediaUrn from a string representation
/// The string must be a valid tagged URN with the "media" prefix
/// Mirrors Rust: impl FromStr for MediaUrn
+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error;

/// The constraint this media URN writes for `key`, or nil when it does not mention it.
/// Mirrors Rust: pub fn get_tag(&self, key: &str) -> Option<&Constraint>
- (nullable CSTagConstraint *)getTag:(NSString *)key;

/// The exact value this media URN writes for `key` (`key=value`); nil when it does not
/// mention the key or constrains it in another form.
/// Mirrors Rust: pub fn exact_value(&self, key: &str) -> Option<&str>
- (nullable NSString *)exactValue:(NSString *)key;

/// Whether `tagName` is present as a marker (written as just the key).
- (BOOL)hasMarkerTag:(NSString *)tagName;

/// Every tag, each as the constraint it writes
- (NSDictionary<NSString *, CSTagConstraint *> *)tags;

/// Convert to canonical string representation
/// Mirrors Rust: impl Display for MediaUrn
- (NSString *)toString;

// Every comparison below answers YES or NO. The comparisons of tagged URNs
// fail only on a prefix mismatch, which two media URNs never have, so such a
// failure is a programming error and raises NSInternalInconsistencyException.

/// Check if this instance conforms to (can be handled by) the given pattern.
/// Equivalent to `pattern.accepts(self)`.
/// Mirrors Rust: pub fn conforms_to(&self, pattern: &MediaUrn) -> bool
- (BOOL)conformsTo:(CSMediaUrn *)pattern;

/// Check if this pattern accepts the given instance.
/// Equivalent to `instance.conformsTo(self)`.
/// Mirrors Rust: pub fn accepts(&self, instance: &MediaUrn) -> bool
- (BOOL)accepts:(CSMediaUrn *)instance;

/// Whether this media type and `other` COULD describe the same value: not a guarantee
/// (conformsTo), and not excluded. `media:ext` meets `media:document;ext=pdf`; `media:document;ext=pdf` does
/// not meet `media:ext=png`.
- (BOOL)meets:(CSMediaUrn *)other;

/// Whether a VALUE whose media this is satisfies the type `pattern`.
///
/// conformsTo compares two types, and a type that does not mention a key says nothing about
/// it. A value that exists is complete: the tags it does not have, it does not have. Use this
/// where the receiver is the media of actual data — a stream that arrived, an output that was
/// produced.
- (BOOL)satisfies:(CSMediaUrn *)pattern;

/// Whether a value whose media this is COULD satisfy `pattern`.
- (BOOL)maySatisfy:(CSMediaUrn *)pattern;

/// Check if two media URNs have the exact same tag set (order-independent).
/// Equivalent to `self.accepts(other) && other.accepts(self)`.
/// Mirrors Rust: pub fn is_equivalent(&self, other: &MediaUrn) -> bool
- (BOOL)isEquivalentTo:(CSMediaUrn *)other;

/// Check if two media URNs are comparable (on the same specialization chain).
/// Equivalent to `self.accepts(other) || other.accepts(self)`.
/// Mirrors Rust: pub fn is_comparable(&self, other: &MediaUrn) -> bool
- (BOOL)isComparableTo:(CSMediaUrn *)other;

/// Structural total order of two media URNs: the tagged URN's order by parts
/// (CSTaggedUrn -compare:): the prefix, then each tag in key order by its key,
/// its constraint's form and its value, a URN whose tags run out first coming
/// first. This is the reference's order, not the order of the canonical text,
/// which differs wherever one key is the beginning of another (`a` and `a-x`).
/// Mirrors Rust: impl Ord for MediaUrn
- (NSComparisonResult)compareStructurally:(CSMediaUrn *)other;

/// Compute the directional coordinate delta from `base` to `self`.
- (nullable CSTaggedUrnCoordinateDelta *)deltaFrom:(CSMediaUrn *)base error:(NSError **)error;

/// Apply a coordinate delta to this media URN.
- (nullable CSMediaUrn *)applyDelta:(CSTaggedUrnCoordinateDelta *)delta error:(NSError **)error;

// MARK: - Builders (mirror Rust MediaUrn builders)

/// A new MediaUrn with an added or replaced tag. The key must be an identifier; the
/// constraint one a URN can write.
/// Mirrors Rust: pub fn with_tag(&self, key: &str, constraint: Constraint) -> Result<MediaUrn>
- (nullable CSMediaUrn *)withTag:(NSString * _Nonnull)key
                      constraint:(CSTagConstraint * _Nonnull)constraint
                           error:(NSError * _Nullable * _Nullable)error;

/// Create a new MediaUrn without a specific tag.
/// Delegates to inner CSTaggedUrn withoutTag: and wraps result.
/// Mirrors Rust: pub fn without_tag(&self, key: &str) -> Self
- (CSMediaUrn * _Nonnull)withoutTag:(NSString * _Nonnull)key;

// withList and withoutList removed — list tag is semantic, not shape.
// Shape (scalar vs sequence) is tracked via is_sequence, not URN manipulation.

/// The most specific media type every one of `urns` conforms to: their common
/// denominator, as a gather's element type or the meeting point where branches of
/// different media converge.
///
/// Made by tagged-urn's proved model (`leastUpperBoundWithPrefix:urns:error:`): key by
/// key, the bound allows every state some input allows, and where no single form says
/// exactly that, it is the least bound that excludes only values the inputs name.
/// `[media:document;ext=pdf, media:ext=png;image]` gives `media:ext`; no inputs give `media:`.
+ (CSMediaUrn * _Nonnull)lub:(NSArray<CSMediaUrn *> * _Nonnull)urns;

// MARK: - Predicates (mirror Rust MediaUrn predicates)

// MARK: - Cardinality (list marker)

/// Returns true if this media is a list (has `list` marker tag).
/// Returns false if scalar (no `list` marker = default).
/// Mirrors Rust: pub fn is_list(&self) -> bool
- (BOOL)isList;

/// Returns true if this media is a scalar (no `list` marker).
/// Scalar is the default cardinality.
/// Mirrors Rust: pub fn is_scalar(&self) -> bool
- (BOOL)isScalar;

// MARK: - Structure (record marker)

/// Returns true if this media is a record (has `record` marker tag).
/// A record has internal key-value structure (e.g., JSON object).
/// Mirrors Rust: pub fn is_record(&self) -> bool
- (BOOL)isRecord;

/// Returns true if this media is opaque (no `record` marker).
/// Opaque is the default structure - no internal fields recognized.
/// Mirrors Rust: pub fn is_opaque(&self) -> bool
- (BOOL)isOpaque;

/// Check if this value's content format is JSON (carries `fmt=json`).
/// Mirrors Rust: pub fn is_json(&self) -> bool
- (BOOL)isJson;

/// Check if this value's content format is YAML (carries `fmt=yaml`).
/// Mirrors Rust: pub fn is_yaml(&self) -> bool
- (BOOL)isYaml;

/// Check if this value's content format is CSV (carries `fmt=csv`).
/// Mirrors Rust: pub fn is_csv(&self) -> bool
- (BOOL)isCsv;

/// Check if this represents void (void marker tag present) — the
/// **unit type** in the type-theoretic reading. media:void is the
/// nullary value; NOT "invalid" or "absent".
/// Mirrors Rust: pub fn is_void(&self) -> bool
- (BOOL)isVoid;

/// True if this is the **top** media URN — the universal wildcard
/// `media:` with no tags. Order-theoretically, every other media URN
/// conformsTo this one. Distinct from isVoid: top means "any data
/// type accepted here," void means "no data flows here."
/// Mirrors Rust: pub fn is_top(&self) -> bool
- (BOOL)isTop;

/// Check if this represents image data (image marker tag present).
/// Mirrors Rust: pub fn is_image(&self) -> bool
- (BOOL)isImage;

/// Check if this represents audio data (audio marker tag present).
/// Mirrors Rust: pub fn is_audio(&self) -> bool
- (BOOL)isAudio;

/// Check if this represents video data (video marker tag present).
/// Mirrors Rust: pub fn is_video(&self) -> bool
- (BOOL)isVideo;

/// Check if this represents numeric data (numeric marker tag present).
/// Mirrors Rust: pub fn is_numeric(&self) -> bool
- (BOOL)isNumeric;

/// Check if this represents boolean data (bool marker tag present).
/// Mirrors Rust: pub fn is_bool(&self) -> bool
- (BOOL)isBool;

/// Check if this URN specializes `media:file-path`. There is a single
/// file-path media URN; cardinality (single file vs many) is carried on the
/// wire via is_sequence, not via URN tags.
/// Mirrors Rust: pub fn is_file_path(&self) -> bool
- (BOOL)isFilePath;

// MARK: - Specificity

/// Get the specificity score: the sum of each tag's graded score
/// (?x=0, x?=v=1, x=2, x!=v=3, x=v=4, !x=5), as CSTaggedUrn scores it.
/// Higher specificity means more specific matching.
/// Mirrors Rust: pub fn specificity(&self) -> usize
- (NSInteger)specificity;

@end

NS_ASSUME_NONNULL_END
