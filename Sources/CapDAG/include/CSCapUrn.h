//
//  CSCapUrn.h
//  Flat Tag-Based Cap Identifier System with Required Direction
//
//  This provides a flat, tag-based cap URN system with structural direction (in→out),
//  pattern matching, and graded specificity comparison.
//
//  Structural coordinates:
//  - inSpec: input media URN (defaults to "media:")
//  - outSpec: output media URN (defaults to "media:")
//  - effect: runtime media relation ("declared" by default)
//
//  Special pattern values (from tagged-urn):
//    K=v  - Must have key K with exact value v
//    K=*  - Must have key K with any value (presence required)
//    K=!  - Must NOT have key K (absence required)
//    K=?  - No constraint on key K
//    (missing) - Same as K=? - no constraint
//
//  Uses CSTaggedUrn for parsing to ensure consistency across implementations.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CSTaggedUrn;
@class CSMediaUrn;

/// Functional category of a cap, derived from all four structural axes
/// (`in`, `out`, `effect`, and the remaining tags). The classification is
/// **logical** — the dispatch protocol does not branch on `CSCapKind`.
/// Exposed so tools, UIs, planners, and tests can reason about a
/// cap's role without re-deriving the rules.
///
/// `media:void` is the **unit type** (no meaningful value).
/// `media:` is the **top type** (universal wildcard). With those
/// anchors the five kinds fall out:
///
///   Identity   in=media:, out=media:, effect=none, no other tags →  A → A
///   Source     in=media:void, out!=void              →  () → B
///   Sink       in!=void, out=media:void              →  A → ()
///   Effect     in=media:void, out=media:void         →  () → ()
///   Transform  anything else
///
/// Identity is the explicit `effect=none` cap on every axis: input wide
/// open, output wide open, no operation/metadata tags, and no runtime
/// media/type change.
typedef NS_ENUM(NSInteger, CSCapKind) {
    CSCapKindIdentity,
    CSCapKindSource,
    CSCapKindSink,
    CSCapKindEffect,
    CSCapKindTransform,
};

typedef NS_ENUM(NSInteger, CSCapEffect) {
    CSCapEffectDeclared,
    CSCapEffectNone,
    CSCapEffectPatch,
    CSCapEffectAny,
};

/// Stable wire/log/UI label for a CSCapKind value (snake_case to
/// match other capdag enum serializations on the wire).
FOUNDATION_EXPORT NSString *CSCapKindToString(CSCapKind kind);

/// Per-axis weights for cap-URN specificity. Two orders of magnitude
/// separate each axis to keep them in distinct digit slots while
/// folding into a single comparable integer.
///   spec_C(c) = WeightOut*spec_U(out) + WeightIn*spec_U(in) + spec_U(y)
static const NSUInteger CSCapUrnWeightOut = 10000;
static const NSUInteger CSCapUrnWeightIn  = 100;

/**
 * A cap URN with direction (in→out), effect, and optional tags
 *
 * Direction and effect are integral to a cap's identity.
 * Omitted `in` and `out` default to `media:`.
 * Omitted `effect` defaults to `declared`.
 *
 * The 'in' and 'out' values must be either:
 * - A valid media URN starting with "media:" (e.g., "media:string")
 * - A wildcard "*" for pattern matching
 *
 * Examples:
 * - cap:in="media:void";generate;out="media:binary";target=thumbnail
 * - cap:in="media:binary";extract;out="media:object";target=metadata
 * - cap:in="media:string";embed;out="media:number-array"
 */
@interface CSCapUrn : NSObject <NSCopying, NSSecureCoding>

/// A cap is made by parsing or by the constructors below, which validate it; there is no empty one.
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The input media URN (required) - e.g., "media:void", "media:string", or "*"
@property (nonatomic, readonly) NSString *inSpec;

/// The output media URN (required) - e.g., "media:object", "media:binary", or "*"
@property (nonatomic, readonly) NSString *outSpec;

/// The effect coordinate. Omitted `effect` defaults to `declared`.
@property (nonatomic, readonly) NSString *effectSpec;

/// Other tags that define this cap (excludes in/out)
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *tags;

/**
 * Create a cap URN from a string
 * Format: cap:in="<media-urn>";out="<media-urn>";key1=value1;...
 * `in` and `out` may be omitted; they default to `media:`.
 * `effect` may be omitted; it defaults to `declared`.
 *
 * Uses CSTaggedUrn for parsing to ensure consistency with tagged-urn library.
 *
 * @param string The cap URN string (e.g., "cap:in=\"media:void\";generate;out=\"media:object\"")
 * @param error Error if the string format is invalid or in/out missing/invalid
 * @return A new CSCapUrn instance or nil if invalid
 */
+ (nullable instancetype)fromString:(NSString * _Nonnull)string error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a cap URN from tags
 * Extracts `in`, `out`, and `effect` from tags, defaulting omitted
 * structural coordinates to `media:`, `media:`, and `declared`.
 *
 * @param tags Dictionary containing all tags including 'in' and 'out'
 * @param error Error if tags are invalid or in/out missing
 * @return A new CSCapUrn instance or nil if invalid
 */
+ (nullable instancetype)fromTags:(NSDictionary<NSString *, NSString *> * _Nonnull)tags error:(NSError * _Nullable * _Nullable)error;

/**
 * Get the input spec ID
 * @return The input spec ID
 */
- (NSString *)getInSpec;

/**
 * Get the output spec ID
 * @return The output spec ID
 */
- (NSString *)getOutSpec;

/**
 * Get the effect coordinate string.
 * @return The canonical effect coordinate (`declared`, `none`, `patch`, or `?`)
 */
- (NSString *)getEffectSpec;

/**
 * Get the parsed effect coordinate.
 * @return The parsed effect enum
 */
- (CSCapEffect)effect;

/**
 * Functional category of this cap, derived from all four structural axes:
 * `in`, `out`, `effect`, and the rest of the tags. See CSCapKind doc for the
 * full taxonomy. Identity requires top/top, explicit `effect=none`, and no
 * extra tags.
 *
 * Aborts (NSAssert) if either side is not a valid media URN — that
 * only happens on internally inconsistent state since CSCapUrn
 * construction validates both sides.
 */
- (CSCapKind)kind;

/**
 * Get the value of a specific tag
 * Key is normalized to lowercase for lookup
 * Returns inSpec for "in" key, outSpec for "out" key, effectSpec for "effect" key
 *
 * @param key The tag key
 * @return The tag value or nil if not found
 */
- (nullable NSString *)getTag:(NSString * _Nonnull)key;

/**
 * Check if this cap has a specific tag with a specific value
 * Key is normalized to lowercase; value comparison is case-sensitive
 * Checks inSpec for "in" key, outSpec for "out" key
 *
 * @param key The tag key
 * @param value The tag value to check
 * @return YES if the tag exists with the specified value
 */
- (BOOL)hasTag:(NSString * _Nonnull)key withValue:(NSString * _Nonnull)value;

/**
 * Check whether a marker tag (a tag whose value is "*") is present at the
 * given key. Equivalent to `[self hasTag:tagName withValue:@"*"]` but
 * expresses authorial intent: this tag is present as a marker (a
 * wildcard-valued tag that serializes as just the key), not as a
 * key=value pair. Example: `cap:constrained;...` has marker tag
 * "constrained".
 *
 * @param tagName The marker key
 * @return YES if the tag exists with value "*"
 */
- (BOOL)hasMarkerTag:(NSString * _Nonnull)tagName;

/**
 * Infer the runtime output media for this cap from a concrete runtime input.
 *
 * `effect=declared` returns the declared output media.
 * `effect=none` returns the runtime input unchanged.
 * `effect=patch` applies the declared `(out - in)` coordinate delta to the
 * runtime input.
 *
 * @param runtimeInput The concrete runtime input media URN
 * @param error Error if the effect declaration is invalid or cannot be applied
 * @return The inferred runtime output media or nil on error
 */
- (nullable CSMediaUrn *)inferRuntimeOutputMedia:(CSMediaUrn * _Nonnull)runtimeInput error:(NSError * _Nullable * _Nullable)error;

/**
 * THE effect-audit predicate: does an actually-emitted runtime output satisfy
 * this cap's declared effect contract for the given runtime input? Every
 * check of "did the cap emit what its effect promised" must go through this
 * — never a hand-rolled combination of inferRuntimeOutputMedia with equality
 * or conformance checks.
 *
 * effect=none / effect=patch require the emission to be tag-equivalent to
 * the inferred output (the effect fully determines the type — a more
 * specific emission is still a violation). effect=declared requires the
 * emission to conform to the declared out= (more specific is legal, more
 * generic is a violation).
 *
 * @param runtimeInput The concrete runtime input media URN
 * @param runtimeOutput The media URN the cap actually emitted
 * @param error Set when the inference itself is impossible (nonconforming
 *        runtime input, unconstrained ?effect, inconsistent URN state) — an
 *        upstream contract break, not an emission mismatch. A clean
 *        nonconformant emission returns NO with no error.
 * @return YES iff the emission satisfies the effect contract
 */
- (BOOL)isConformantRuntimeOutput:(CSMediaUrn * _Nonnull)runtimeInput
                    runtimeOutput:(CSMediaUrn * _Nonnull)runtimeOutput
                            error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a new cap URN with an added or updated non-structural tag.
 * Reserved structural keys (`in`, `out`, `effect`) are illegal here and raise
 * `NSInvalidArgumentException`. Use withInSpec:, withOutSpec:, or withEffect:
 * to change structural coordinates.
 *
 * @param key The tag key
 * @param value The tag value
 * @return A new CSCapUrn instance with the tag added/updated
 */
- (CSCapUrn * _Nonnull)withTag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Create a new cap URN with a changed input spec
 * @param inSpec The new input spec ID
 * @return A new CSCapUrn instance with the changed inSpec
 */
- (CSCapUrn * _Nonnull)withInSpec:(NSString * _Nonnull)inSpec;

/**
 * Create a new cap URN with a changed output spec
 * @param outSpec The new output spec ID
 * @return A new CSCapUrn instance with the changed outSpec
 */
- (CSCapUrn * _Nonnull)withOutSpec:(NSString * _Nonnull)outSpec;

/**
 * Create a new cap URN with a non-structural tag removed.
 * Reserved structural keys (`in`, `out`, `effect`) are illegal here and raise
 * `NSInvalidArgumentException`. Structural coordinates cannot be removed.
 *
 * @param key The tag key to remove
 * @return A new CSCapUrn instance with the tag removed
 */
- (CSCapUrn * _Nonnull)withoutTag:(NSString * _Nonnull)key;

/**
 * Whether `cap` fits this cap read as a PATTERN over caps — what a search asks:
 * `cap`'s input is within this pattern's, its output covers the pattern's, its
 * effect is the pattern's (a pattern's `?effect` fits any), and its cap-tags —
 * complete: a cap has the tags it has — satisfy the pattern's.
 *
 * A side the pattern leaves open is not asked about. `cap:candle` fits every cap
 * tagged `candle`, whatever it takes and gives: its open output is "not
 * established", not the type "anything".
 *
 * Decided by the proved model (CapDAG.Exec.accepts, which is CapDAG.fits). For a
 * question no cap URN can spell — "what gives this, whatever it takes" — ask a
 * CSCapQuery.
 *
 * @param cap The cap to test against this pattern
 * @return YES if the cap fits
 */
- (BOOL)accepts:(CSCapUrn * _Nonnull)cap;

/**
 * Whether this cap fits `pattern`: [pattern accepts:self].
 *
 * @param pattern The pattern cap to check against
 * @return YES if this cap fits the pattern
 */
- (BOOL)conformsTo:(CSCapUrn * _Nonnull)pattern;

/**
 * Whether this candidate SERVES `request` — the predicate routing and dispatch
 * act on.
 *
 * The candidate takes at least what the request sends, gives at least what the
 * request needs, has the effect asked for unless the request says `?effect`,
 * and has the cap-tags asked for — its own tags being complete, so a request
 * for `!x` is served by a candidate that does not mention `x`, and a candidate
 * may carry tags the request does not ask about.
 *
 * An input the request leaves open is not established: the caller has not said
 * what it will send, and every candidate passes that side. That is "some
 * input", not "any input" — `media:` on a CANDIDATE's input does mean it takes
 * anything.
 *
 * This is a guarantee. What only could serve does not; see mayDispatch: and
 * -[CSCapQuery grade:]. Decided by the proved model (CapDAG.Exec.dispatch,
 * which is CapDAG.serves). Not symmetric.
 *
 * @param request The request cap
 * @return YES if this candidate serves the request
 */
- (BOOL)isDispatchable:(CSCapUrn * _Nonnull)request;

/**
 * Whether this candidate COULD serve `request`: not guaranteed, not excluded.
 * For exploring what the fabric might do — never for routing a call, which must
 * be served.
 */
- (BOOL)mayDispatch:(CSCapUrn * _Nonnull)request;

/** Whether what this cap gives, `next` takes: the edge of a route. */
- (BOOL)flowsInto:(CSCapUrn * _Nonnull)next;

/**
 * Whether what this cap gives COULD be something `next` takes: an edge a search
 * may explore and a run has to check.
 */
- (BOOL)mayFlowInto:(CSCapUrn * _Nonnull)next;

/**
 * This cap on the proved model's side (a CapDAG.Exec.WfCap on lungo's runtime),
 * owned by this cap and alive as long as it is.
 */
@property (nonatomic, readonly) const struct lungo_value *formalValue NS_RETURNS_INNER_POINTER;

/**
 * Whether the two caps are on one chain: one stands in for the other on every
 * side. Both are read as descriptions — nothing is unknown.
 *
 * @param other The other cap to compare with
 * @return YES if the two caps are comparable
 */
- (BOOL)isComparable:(CSCapUrn * _Nonnull)other;

/**
 * Whether the two are the SAME cap: equivalent on every side, the effects
 * agreeing. What resolving a name to its cap asks. Nothing is read as unknown:
 * a cap that promises no particular output is not the same cap as one that
 * promises pages, though as a pattern it fits it.
 *
 * @param other The other cap to compare with
 * @return YES if the two caps are equivalent
 */
- (BOOL)isEquivalent:(CSCapUrn * _Nonnull)other;

/**
 * Get the specificity score for cap matching using graded scoring:
 *   K=v (exact value): 3 points (most specific)
 *   K=* (must-have-any): 2 points
 *   K=! (must-not-have): 1 point
 *   K=? (unspecified) or missing: 0 points (least specific)
 *
 * Includes direction specs (in/out) in the score.
 *
 * @return The total specificity score
 */
- (NSUInteger)specificity;

/**
 * Check if this cap is more specific than another
 * @param other The other cap to compare specificity with
 * @return YES if this cap is more specific
 */
- (BOOL)isMoreSpecificThan:(CSCapUrn * _Nonnull)other;

/**
 * Create a new cap with a specific tag set to wildcard
 * For "in" key, uses withInSpec:@"*"
 * For "out" key, uses withOutSpec:@"*"
 * For "effect" key, uses withEffect:CSCapEffectAny
 *
 * @param key The tag key to set to wildcard
 * @return A new CSCapUrn instance with the tag set to wildcard
 */
- (CSCapUrn * _Nonnull)withWildcardTag:(NSString * _Nonnull)key;

/**
 * Create a new cap URN with a changed effect coordinate.
 * @param effect The new effect coordinate
 * @return A new CSCapUrn instance with the changed effect
 */
- (CSCapUrn * _Nonnull)withEffect:(CSCapEffect)effect;

/**
 * Create a new cap with only specified tags
 * @param keys Array of tag keys to include
 * @return A new CSCapUrn instance with only the specified tags
 */
- (CSCapUrn * _Nonnull)subset:(NSArray<NSString *> * _Nonnull)keys;

/**
 * Merge with another cap (other takes precedence for conflicts)
 * @param other The cap to merge with
 * @return A new CSCapUrn instance with merged tags
 */
- (CSCapUrn * _Nonnull)merge:(CSCapUrn * _Nonnull)other;

/**
 * Get the canonical string representation of this cap
 * @return The cap URN as a string
 */
- (NSString *)toString;


@end

/// Error domain for cap URN errors
FOUNDATION_EXPORT NSErrorDomain const CSCapUrnErrorDomain;

/// Error codes for cap URN operations
typedef NS_ERROR_ENUM(CSCapUrnErrorDomain, CSCapUrnError) {
    CSCapUrnErrorInvalidFormat = 1,
    CSCapUrnErrorEmptyTag = 2,
    CSCapUrnErrorInvalidCharacter = 3,
    CSCapUrnErrorInvalidTagFormat = 4,
    CSCapUrnErrorMissingCapPrefix = 5,
    CSCapUrnErrorDuplicateKey = 6,
    CSCapUrnErrorNumericKey = 7,
    CSCapUrnErrorUnterminatedQuote = 8,
    CSCapUrnErrorInvalidEscapeSequence = 9,
    CSCapUrnErrorMissingInSpec = 10,
    CSCapUrnErrorMissingOutSpec = 11,
    CSCapUrnErrorInvalidInSpec = 12,
    CSCapUrnErrorInvalidOutSpec = 13,
    CSCapUrnErrorInvalidEffect = 14,
    CSCapUrnErrorInvalidEffectApplication = 15,
    CSCapUrnErrorIllegalDeclaration = 16
};

/**
 * Builder for creating cap URNs fluently.
 * Both inSpec and outSpec MUST be set before build() succeeds.
 * Effect defaults to `declared`.
 */
@interface CSCapUrnBuilder : NSObject

/**
 * Create a new builder
 * @return A new CSCapUrnBuilder instance
 */
+ (instancetype)builder;

/**
 * Set the input media URN (required)
 * @param spec The input media URN (e.g., "media:void") or "*" for wildcard
 * @return This builder instance for chaining
 */
- (CSCapUrnBuilder * _Nonnull)inSpec:(NSString * _Nonnull)spec;

/**
 * Set the output media URN (required)
 * @param spec The output media URN (e.g., "media:object") or "*" for wildcard
 * @return This builder instance for chaining
 */
- (CSCapUrnBuilder * _Nonnull)outSpec:(NSString * _Nonnull)spec;

/**
 * Set the effect coordinate.
 * @param effect The effect coordinate
 * @return This builder instance for chaining
 */
- (CSCapUrnBuilder * _Nonnull)effect:(CSCapEffect)effect;

/**
 * Add or update a non-structural tag.
 * Reserved structural keys (`in`, `out`, `effect`) are illegal here and raise
 * `NSInvalidArgumentException`. Use inSpec:, outSpec:, or effect: instead.
 *
 * @param key The tag key
 * @param value The tag value
 * @return This builder instance for chaining
 */
- (CSCapUrnBuilder * _Nonnull)tag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Add a marker tag (a wildcard-valued tag that serializes as just the key).
 * Equivalent to `[self tag:key value:@"*"]` but expresses authorial intent:
 * this tag is present as a marker, not a key=value pair. Structural
 * coordinates (`in`, `out`, `effect`) are illegal as marker keys and raise
 * `NSInvalidArgumentException`.
 * @param key The marker key
 * @return This builder instance for chaining
 */
- (CSCapUrnBuilder * _Nonnull)marker:(NSString * _Nonnull)key;

/**
 * Build the final CapUrn
 * Fails if inSpec or outSpec not set.
 *
 * @param error Error if build fails
 * @return A new CSCapUrn instance or nil if error
 */
- (nullable CSCapUrn *)build:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
