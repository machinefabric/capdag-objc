//
//  CSCapUrn.m
//  Flat Tag-Based Cap Identifier Implementation with Required Direction
//
//  Uses CSTaggedUrn for parsing to ensure consistency across implementations.
//

#import "CSCapUrn.h"
#import "CSMediaUrn.h"
@import TaggedUrn;
// Dispatch, acceptance, equivalence and specificity are decided by the program generated from
// the proved model in ../formal (see ../lungo.toml), through its C API. Its URNs are
// tagged-urn's model values, which pass to it as they are.
#import "capdagFormal.h"

NSErrorDomain const CSCapUrnErrorDomain = @"CSCapUrnErrorDomain";

static NSString *CSCapEffectToString(CSCapEffect effect) {
    switch (effect) {
        case CSCapEffectDeclared: return @"declared";
        case CSCapEffectNone: return @"none";
        case CSCapEffectPatch: return @"patch";
        case CSCapEffectAny: return @"?";
    }
    NSCAssert(NO, @"Unknown CSCapEffect value %ld", (long)effect);
    return @"";
}

static CSCapEffect CSCapEffectFromString(NSString *effectValue) {
    if ([effectValue isEqualToString:@"declared"]) return CSCapEffectDeclared;
    if ([effectValue isEqualToString:@"none"]) return CSCapEffectNone;
    if ([effectValue isEqualToString:@"patch"]) return CSCapEffectPatch;
    if ([effectValue isEqualToString:@"?"]) return CSCapEffectAny;
    NSCAssert(NO, @"CSCapUrn invariant violation: invalid effect '%@'", effectValue);
    return CSCapEffectDeclared;
}

static NSArray<NSString *> *CSCapStructuralKeys(void) {
    return @[@"in", @"out", @"effect"];
}

static NSError *CSCapError(CSCapUrnError code, NSString *message) {
    return [NSError errorWithDomain:CSCapUrnErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// A tag a parsed tag map holds, as written, for an error that names it.
static NSString *CSCapWrittenTag(NSString *key, CSTagConstraint *constraint) {
    NSError *error = nil;
    CSTaggedUrn *urn = [CSTaggedUrn fromPrefix:@"cap" tags:@{key: constraint} error:&error];
    NSCAssert(urn != nil, @"a stored tag is writable: %@", error);
    return [[urn toString] substringFromIndex:4];
}

/// The cap URN error a tagged URN's error is, by its code.
static NSError *CSCapErrorFromTaggedUrnError(NSError *taggedError) {
    if (![taggedError.domain isEqualToString:CSTaggedUrnErrorDomain]) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:@"capdag: a tagged URN failed with no tagged URN error: %@", taggedError]
                                     userInfo:nil];
    }
    CSCapUrnError code;
    switch ((CSTaggedUrnError)taggedError.code) {
        case CSTaggedUrnErrorInvalidFormat: code = CSCapUrnErrorInvalidFormat; break;
        case CSTaggedUrnErrorEmptyTag: code = CSCapUrnErrorEmptyTag; break;
        case CSTaggedUrnErrorInvalidCharacter: code = CSCapUrnErrorInvalidCharacter; break;
        case CSTaggedUrnErrorInvalidTagFormat: code = CSCapUrnErrorInvalidTagFormat; break;
        case CSTaggedUrnErrorMissingPrefix: code = CSCapUrnErrorMissingCapPrefix; break;
        case CSTaggedUrnErrorDuplicateKey: code = CSCapUrnErrorDuplicateKey; break;
        case CSTaggedUrnErrorUnterminatedQuote: code = CSCapUrnErrorUnterminatedQuote; break;
        case CSTaggedUrnErrorInvalidEscapeSequence: code = CSCapUrnErrorInvalidEscapeSequence; break;
        case CSTaggedUrnErrorEmptyPrefix: code = CSCapUrnErrorMissingCapPrefix; break;
        case CSTaggedUrnErrorPrefixMismatch: code = CSCapUrnErrorMissingCapPrefix; break;
        case CSTaggedUrnErrorWhitespaceInInput: code = CSCapUrnErrorInvalidCharacter; break;
        default:
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:@"capdag: tagged URN error code %ld has no cap URN code", (long)taggedError.code]
                                         userInfo:nil];
    }
    return CSCapError(code, taggedError.localizedDescription);
}

static CSCapUrnError CSCapDirectionCode(NSString *side) {
    return [side isEqualToString:@"in"] ? CSCapUrnErrorInvalidInSpec : CSCapUrnErrorInvalidOutSpec;
}

/// What a direction side says when its value is no media URN: a value that does not even name
/// the media prefix, in the validation rules' words, and one that names it but does not parse,
/// with the parser's reason.
static NSError *CSCapDirectionError(NSString *side, NSString *value, NSError *mediaError) {
    NSError *underlying = mediaError.userInfo[NSUnderlyingErrorKey];
    BOOL noMediaPrefix =
        ([mediaError.domain isEqualToString:CSMediaUrnErrorDomain] && mediaError.code == CSMediaUrnErrorInvalidPrefix)
        || ([underlying.domain isEqualToString:CSTaggedUrnErrorDomain]
            && (underlying.code == CSTaggedUrnErrorMissingPrefix || underlying.code == CSTaggedUrnErrorEmptyPrefix));
    if (noMediaPrefix) {
        return CSCapError(CSCapDirectionCode(side),
                          [NSString stringWithFormat:@"Invalid '%@' media URN: %@. Must start with 'media:' or be '*'", side, value]);
    }
    return CSCapError(CSCapDirectionCode(side),
                      [NSString stringWithFormat:@"Invalid '%@' media URN: %@: %@", side, value, mediaError.localizedDescription]);
}

/// A direction side's media URN, in canonical form. An empty value is refused.
static NSString * _Nullable CSCapDirectionMedia(NSString *side, NSString *value, NSError **error) {
    if (value.length == 0) {
        if (error) *error = CSCapError(CSCapDirectionCode(side), [NSString stringWithFormat:@"Empty value for '%@' tag is not allowed", side]);
        return nil;
    }
    NSError *mediaError = nil;
    CSMediaUrn *media = [CSMediaUrn fromString:value error:&mediaError];
    if (!media) {
        if (error) *error = CSCapDirectionError(side, value, mediaError);
        return nil;
    }
    return [media toString];
}

/// A direction spec given as text to a constructor or the builder: `*` is the top media
/// `media:`, as the marker is in parsing; anything else is a media URN, in canonical form.
static NSString * _Nullable CSCapDirectionSpec(NSString *side, NSString *raw, NSError **error) {
    if ([raw isEqualToString:@"*"]) {
        return @"media:";
    }
    return CSCapDirectionMedia(side, raw, error);
}

/// A direction tag as a cap's tag map holds it: missing, or the marker (`in`, `in=*`), is
/// `media:`; an exact value is that media URN in canonical form; any other form is refused.
static NSString * _Nullable CSCapProcessDirectionTag(CSTagConstraint * _Nullable tag, NSString *side, NSError **error) {
    if (!tag || tag.kind == CSTagConstraintKindPresent) {
        return @"media:";
    }
    if (tag.kind == CSTagConstraintKindExact) {
        return CSCapDirectionMedia(side, tag.value, error);
    }
    if (error) {
        *error = CSCapError(CSCapDirectionCode(side),
                            [NSString stringWithFormat:@"Invalid '%@' media URN: %@. Must start with 'media:' or be '*'", side, CSCapWrittenTag(side, tag)]);
    }
    return nil;
}

/// The effect a cap's tag map writes: none is declared; the marker or `?effect` is the
/// unconstrained `?`; an exact declared, none or patch is that effect; anything else is
/// refused, named as written.
static NSString * _Nullable CSCapNormalizeEffectValue(CSTagConstraint * _Nullable raw, NSError **error) {
    if (!raw) {
        return @"declared";
    }
    if (raw.kind == CSTagConstraintKindPresent || raw.kind == CSTagConstraintKindUnconstrained) {
        return @"?";
    }
    if (raw.kind == CSTagConstraintKindExact
        && ([raw.value isEqualToString:@"declared"] || [raw.value isEqualToString:@"none"] || [raw.value isEqualToString:@"patch"])) {
        return raw.value;
    }
    if (error) {
        *error = CSCapError(CSCapUrnErrorInvalidEffect,
                            [NSString stringWithFormat:@"Unsupported effect '%@'. Supported values are declared, none, patch, or explicit unconstrained ?effect/effect=*", CSCapWrittenTag(@"effect", raw)]);
    }
    return nil;
}

/// An effect given as text to a constructor: declared, none, patch or ?.
static NSString * _Nullable CSCapParseEffect(NSString *effect, NSError **error) {
    if ([@[@"declared", @"none", @"patch", @"?"] containsObject:effect]) {
        return effect;
    }
    if (error) {
        *error = CSCapError(CSCapUrnErrorInvalidEffect,
                            [NSString stringWithFormat:@"Unsupported effect '%@'. Supported values are declared, none, patch, or ?", effect]);
    }
    return nil;
}

#pragma mark - The model

/// A model call that fails is a broken invariant — a cap this class built that the model cannot
/// take, or a runtime that is not working — and there is no answer to give instead.
static void CSCapModelFailed(NSString *what, lungo_error *error) {
    NSString *reason = [NSString stringWithFormat:@"capdag: the model could not %@: %s", what,
                        error ? lungo_error_message(error) : "no error was reported"];
    if (error) lungo_error_free(error);
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

/// A direction's media URN as the model's value; owned. The spec was validated before a cap is
/// assembled, so one that does not parse is a broken invariant.
static lungo_value *CSCapModelMedia(NSString *spec) {
    NSError *error = nil;
    CSMediaUrn *media = [CSMediaUrn fromString:spec error:&error];
    if (!media) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:@"capdag: the validated media URN '%@' does not parse: %@", spec, error.localizedDescription]
                                     userInfo:nil];
    }
    return lungo_value_clone(media.inner.formalValue);
}

/// A stored effect as the model's value; owned.
static lungo_value *CSCapModelEffect(NSString *effectSpec) {
    switch (CSCapEffectFromString(effectSpec)) {
        case CSCapEffectDeclared: return capdagFormal_effect_declared();
        case CSCapEffectNone: return capdagFormal_effect_none();
        case CSCapEffectPatch: return capdagFormal_effect_patch();
        case CSCapEffectAny: return capdagFormal_effect_unspecified();
    }
}

/// Runs a model relation of two caps.
static BOOL CSCapModelRelation(int32_t (*relation)(const lungo_value *, const lungo_value *, lungo_value **, lungo_error **),
                               const lungo_value *a, const lungo_value *b, NSString *what) {
    lungo_value *result = NULL;
    lungo_error *error = NULL;
    if (relation(a, b, &result, &error) != LUNGO_OK) CSCapModelFailed(what, error);
    BOOL answer = lungo_value_get_bool(result);
    lungo_value_free(result);
    return answer;
}

@interface CSCapUrn () {
    // The same cap on the proved model's side: its three URNs and its effect (a
    // CapDAG.Exec.WfCap, owned). Dispatch, acceptance, equivalence and specificity are asked of
    // it. Made by the designated initializer from the same fields, which nothing changes
    // afterwards, so the two cannot describe different caps.
    lungo_value *_formal;
}
@property (nonatomic, strong) NSString *inSpec;
@property (nonatomic, strong) NSString *outSpec;
@property (nonatomic, strong) NSString *effectSpec;
@property (nonatomic, strong) NSDictionary<NSString *, CSTagConstraint *> *mutableTags;
- (instancetype)initWithInSpec:(NSString *)inSpec
                       outSpec:(NSString *)outSpec
                    effectSpec:(NSString *)effectSpec
                        tagUrn:(CSTaggedUrn *)tagUrn NS_DESIGNATED_INITIALIZER;
@end

@implementation CSCapUrn

+ (CSCapUrn *)mustCreateFromInSpec:(NSString *)inSpec
                           outSpec:(NSString *)outSpec
                            effect:(NSString *)effect
                              tags:(NSDictionary<NSString *, CSTagConstraint *> *)tags
                           context:(NSString *)context {
    NSError *error = nil;
    CSCapUrn *result = [self fromCanonicalInSpec:inSpec outSpec:outSpec effect:effect tags:tags error:&error];
    if (!result) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"%@ produced an illegal cap declaration: %@", context, error.localizedDescription ?: @"unknown error"];
    }
    return result;
}

+ (BOOL)validateAdmissibleInSpec:(NSString *)inSpec
                         outSpec:(NSString *)outSpec
                          effect:(NSString *)effect
                            tags:(NSDictionary<NSString *, CSTagConstraint *> *)tags
                           error:(NSError **)error {
    NSError *parseError = nil;
    CSMediaUrn *inMedia = [CSMediaUrn fromString:inSpec error:&parseError];
    if (!inMedia) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidInSpec
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Stored in spec '%@' failed admissibility validation: %@", inSpec, parseError.localizedDescription ?: @"unknown error"]}];
        }
        return NO;
    }

    parseError = nil;
    CSMediaUrn *outMedia = [CSMediaUrn fromString:outSpec error:&parseError];
    if (!outMedia) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidOutSpec
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Stored out spec '%@' failed admissibility validation: %@", outSpec, parseError.localizedDescription ?: @"unknown error"]}];
        }
        return NO;
    }

    CSCapEffect parsedEffect = CSCapEffectFromString(effect);
    if (inMedia.isTop && outMedia.isTop && tags.count == 0 && parsedEffect == CSCapEffectDeclared) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorIllegalDeclaration
                                     userInfo:@{NSLocalizedDescriptionKey: @"illegal bare top cap; use cap:effect=none for identity, or declare a non-vacuous input/output/effect/tag"}];
        }
        return NO;
    }

    if (parsedEffect == CSCapEffectNone) {
        parseError = nil;
        BOOL sound = [inMedia conformsTo:outMedia error:&parseError];
        if (!sound) {
            if (error) {
                NSString *message = parseError
                    ? [NSString stringWithFormat:@"failed to verify effect=none admissibility for in='%@' out='%@': %@", inSpec, outSpec, parseError.localizedDescription]
                    : [NSString stringWithFormat:@"effect=none requires declared input '%@' to conform to declared output '%@'", inSpec, outSpec];
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorIllegalDeclaration
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
        return YES;
    }

    if (parsedEffect == CSCapEffectPatch) {
        parseError = nil;
        CSTaggedUrnCoordinateDelta *delta = [outMedia deltaFrom:inMedia error:&parseError];
        if (!delta) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorIllegalDeclaration
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"effect=patch requires a computable declared media delta from '%@' to '%@': %@", inSpec, outSpec, parseError.localizedDescription ?: @"unknown error"]}];
            }
            return NO;
        }

        parseError = nil;
        CSMediaUrn *witness = [inMedia applyDelta:delta error:&parseError];
        if (!witness) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorIllegalDeclaration
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"effect=patch failed to apply declared media delta to input '%@': %@", inSpec, parseError.localizedDescription ?: @"unknown error"]}];
            }
            return NO;
        }

        parseError = nil;
        BOOL sound = [witness conformsTo:outMedia error:&parseError];
        if (!sound) {
            if (error) {
                NSString *message = parseError
                    ? [NSString stringWithFormat:@"failed to verify effect=patch admissibility for witness '%@' against declared output '%@': %@", [witness toString], outSpec, parseError.localizedDescription]
                    : [NSString stringWithFormat:@"effect=patch witness '%@' does not conform to declared output '%@'", [witness toString], outSpec];
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorIllegalDeclaration
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
    }

    return YES;
}

- (NSDictionary<NSString *, CSTagConstraint *> *)tags {
    return self.mutableTags;
}

#pragma mark - Parsing

+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error {
    NSError *parseError = nil;
    CSTaggedUrn *taggedUrn = [CSTaggedUrn fromString:string error:&parseError];
    if (!taggedUrn) {
        if (error) *error = CSCapErrorFromTaggedUrnError(parseError);
        return nil;
    }
    if (![taggedUrn.prefix isEqualToString:@"cap"]) {
        if (error) *error = CSCapError(CSCapUrnErrorMissingCapPrefix, @"Cap identifier must start with 'cap:'");
        return nil;
    }
    return [self fromTags:taggedUrn.tags error:error];
}

+ (nullable instancetype)fromTags:(NSDictionary<NSString *, CSTagConstraint *> *)tags error:(NSError **)error {
    NSMutableDictionary<NSString *, CSTagConstraint *> *rest = [NSMutableDictionary dictionary];
    CSTagConstraint *inTag = nil, *outTag = nil, *effectTag = nil;
    for (NSString *key in tags) {
        NSString *keyLower = [key lowercaseString];
        if ([keyLower isEqualToString:@"in"]) inTag = tags[key];
        else if ([keyLower isEqualToString:@"out"]) outTag = tags[key];
        else if ([keyLower isEqualToString:@"effect"]) effectTag = tags[key];
        else rest[key] = tags[key];
    }
    NSString *inSpec = CSCapProcessDirectionTag(inTag, @"in", error);
    if (!inSpec) return nil;
    NSString *outSpec = CSCapProcessDirectionTag(outTag, @"out", error);
    if (!outSpec) return nil;
    NSString *effect = CSCapNormalizeEffectValue(effectTag, error);
    if (!effect) return nil;
    return [self fromCanonicalInSpec:inSpec outSpec:outSpec effect:effect tags:rest error:error];
}

+ (nullable instancetype)fromInSpec:(NSString *)inSpec
                            outSpec:(NSString *)outSpec
                             effect:(NSString *)effect
                               tags:(NSDictionary<NSString *, CSTagConstraint *> *)tags
                              error:(NSError **)error {
    NSString *canonicalIn = CSCapDirectionSpec(@"in", inSpec, error);
    if (!canonicalIn) return nil;
    NSString *canonicalOut = CSCapDirectionSpec(@"out", outSpec, error);
    if (!canonicalOut) return nil;
    NSString *parsedEffect = CSCapParseEffect(effect, error);
    if (!parsedEffect) return nil;
    return [self fromCanonicalInSpec:canonicalIn outSpec:canonicalOut effect:parsedEffect tags:tags error:error];
}

/// A cap from parts already in canonical form: the direction specs as media URNs the parser or
/// a cap made, and a known effect. The cap-tags are checked here: a structural key is refused,
/// and every key and constraint must be one a URN can write.
+ (nullable instancetype)fromCanonicalInSpec:(NSString *)inSpec
                                     outSpec:(NSString *)outSpec
                                      effect:(NSString *)effect
                                        tags:(NSDictionary<NSString *, CSTagConstraint *> *)tags
                                       error:(NSError **)error {
    for (NSString *key in tags) {
        if ([CSCapStructuralKeys() containsObject:[key lowercaseString]]) {
            if (error) {
                *error = CSCapError(CSCapUrnErrorInvalidTagFormat,
                                    [NSString stringWithFormat:@"reserved structural key '%@' must be passed as inSpec, outSpec or effect, not as a tag", key]);
            }
            return nil;
        }
    }
    NSError *tagError = nil;
    CSTaggedUrn *validatedTags = [CSTaggedUrn fromPrefix:@"cap" tags:tags error:&tagError];
    if (!validatedTags) {
        if (error) *error = CSCapErrorFromTaggedUrnError(tagError);
        return nil;
    }
    if (![self validateAdmissibleInSpec:inSpec outSpec:outSpec effect:effect tags:validatedTags.tags error:error]) {
        return nil;
    }
    return [[CSCapUrn alloc] initWithInSpec:inSpec outSpec:outSpec effectSpec:effect tagUrn:validatedTags];
}

/// The one way a cap is made: the fields, and the model's value built from exactly them. Every
/// caller has validated and canonicalized them.
- (instancetype)initWithInSpec:(NSString *)inSpec
                       outSpec:(NSString *)outSpec
                    effectSpec:(NSString *)effectSpec
                        tagUrn:(CSTaggedUrn *)tagUrn {
    if (self = [super init]) {
        _inSpec = [inSpec copy];
        _outSpec = [outSpec copy];
        _effectSpec = [effectSpec copy];
        _mutableTags = [tagUrn.tags copy];
        _formal = capdagFormal_wf_cap_mk(CSCapModelMedia(_inSpec), CSCapModelMedia(_outSpec),
                                         lungo_value_clone(tagUrn.formalValue), CSCapModelEffect(_effectSpec));
    }
    return self;
}

- (void)dealloc {
    lungo_value_free(_formal);
}

- (NSString *)getInSpec {
    return self.inSpec;
}

- (NSString *)getOutSpec {
    return self.outSpec;
}

- (NSString *)getEffectSpec {
    return self.effectSpec;
}

- (CSCapEffect)effect {
    return CSCapEffectFromString(self.effectSpec);
}

- (CSCapKind)kind {
    NSError *err = nil;
    CSMediaUrn *inMedia = [CSMediaUrn fromString:self.inSpec error:&err];
    NSAssert(inMedia != nil, @"CSCapUrn.kind: in spec '%@' is not a valid media URN: %@",
             self.inSpec, err.localizedDescription);
    CSMediaUrn *outMedia = [CSMediaUrn fromString:self.outSpec error:&err];
    NSAssert(outMedia != nil, @"CSCapUrn.kind: out spec '%@' is not a valid media URN: %@",
             self.outSpec, err.localizedDescription);

    BOOL inVoid = [inMedia isVoid];
    BOOL outVoid = [outMedia isVoid];
    BOOL inTop = [inMedia isTop];
    BOOL outTop = [outMedia isTop];
    // self.tags is the dict of tags BEYOND in/out (those live in
    // self.inSpec / self.outSpec). Empty here means "fully generic on
    // the operation/metadata axis."
    BOOL noExtraTags = self.tags.count == 0;
    CSCapEffect effect = [self effect];

    if (inTop && outTop && noExtraTags && effect == CSCapEffectNone) {
        return CSCapKindIdentity;
    }
    if (inVoid && outVoid) {
        return CSCapKindEffect;
    }
    if (inVoid) {
        return CSCapKindSource;
    }
    if (outVoid) {
        return CSCapKindSink;
    }
    return CSCapKindTransform;
}

NSString *CSCapKindToString(CSCapKind kind) {
    switch (kind) {
        case CSCapKindIdentity: return @"identity";
        case CSCapKindSource: return @"source";
        case CSCapKindSink: return @"sink";
        case CSCapKindEffect: return @"effect";
        case CSCapKindTransform: return @"transform";
    }
    NSCAssert(NO, @"CSCapKindToString: unknown CSCapKind value %ld", (long)kind);
    return @"";
}

- (nullable CSTagConstraint *)getTag:(NSString *)key {
    return self.mutableTags[[key lowercaseString]];
}

- (nullable NSString *)exactValue:(NSString *)key {
    CSTagConstraint *constraint = [self getTag:key];
    return constraint.kind == CSTagConstraintKindExact ? constraint.value : nil;
}

- (BOOL)hasTag:(NSString *)key withValue:(NSString *)value {
    // Case-sensitive value comparison
    return [[self exactValue:key] isEqualToString:value];
}

- (BOOL)hasMarkerTag:(NSString *)tagName {
    return [self getTag:tagName].kind == CSTagConstraintKindPresent;
}

- (nullable CSCapUrn *)withTag:(NSString *)key constraint:(CSTagConstraint *)constraint error:(NSError **)error {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    newTags[[key lowercaseString]] = constraint;
    return [[self class] fromCanonicalInSpec:self.inSpec outSpec:self.outSpec effect:self.effectSpec tags:newTags error:error];
}

- (CSCapUrn *)withInSpec:(NSString *)inSpec {
    NSError *error = nil;
    NSString *canonicalIn = CSCapDirectionSpec(@"in", inSpec, &error);
    if (!canonicalIn) {
        [NSException raise:NSInvalidArgumentException format:@"CSCapUrn.withInSpec: %@", error.localizedDescription];
    }
    return [[self class] mustCreateFromInSpec:canonicalIn
                                      outSpec:self.outSpec
                                       effect:self.effectSpec
                                         tags:self.mutableTags
                                      context:@"CSCapUrn.withInSpec"];
}

- (CSCapUrn *)withOutSpec:(NSString *)outSpec {
    NSError *error = nil;
    NSString *canonicalOut = CSCapDirectionSpec(@"out", outSpec, &error);
    if (!canonicalOut) {
        [NSException raise:NSInvalidArgumentException format:@"CSCapUrn.withOutSpec: %@", error.localizedDescription];
    }
    return [[self class] mustCreateFromInSpec:self.inSpec
                                      outSpec:canonicalOut
                                       effect:self.effectSpec
                                         tags:self.mutableTags
                                      context:@"CSCapUrn.withOutSpec"];
}

- (CSCapUrn *)withEffect:(CSCapEffect)effect {
    return [[self class] mustCreateFromInSpec:self.inSpec
                                      outSpec:self.outSpec
                                       effect:CSCapEffectToString(effect)
                                         tags:self.mutableTags
                                      context:@"CSCapUrn.withEffect"];
}

- (CSCapUrn *)withoutTag:(NSString *)key {
    NSString *keyLower = [key lowercaseString];
    if ([CSCapStructuralKeys() containsObject:keyLower]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Reserved structural key '%@' cannot be removed via withoutTag:", keyLower];
    }
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    [newTags removeObjectForKey:keyLower];
    return [[self class] mustCreateFromInSpec:self.inSpec
                                      outSpec:self.outSpec
                                       effect:self.effectSpec
                                         tags:newTags
                                      context:@"CSCapUrn.withoutTag"];
}

/// Whether `cap` fits this cap read as a PATTERN over caps — what a search asks: `cap`'s input
/// is within this pattern's, its output covers the pattern's, its effect is the pattern's (a
/// pattern's ?effect fits any), and its cap-tags — complete: a cap has the tags it has — satisfy
/// the pattern's. A side the pattern leaves open is not asked about. Decided by the proved
/// model (CapDAG.Exec.accepts, which is CapDAG.fits).
- (BOOL)accepts:(CSCapUrn *)cap {
    if (!cap) {
        return YES;
    }
    return CSCapModelRelation(capdagFormal_accepts, _formal, cap->_formal, @"decide acceptance");
}

- (BOOL)conformsTo:(CSCapUrn *)pattern {
    return [pattern accepts:self];
}

- (const lungo_value *)formalValue {
    return _formal;
}

#pragma mark - Dispatch predicates

/// Whether this candidate SERVES `request`, decided by the proved model (CapDAG.Exec.dispatch,
/// which is CapDAG.serves). The candidate takes at least what the request sends, gives at
/// least what it needs, has the effect asked for unless the request says ?effect, and has the
/// cap-tags asked for, its own tags being complete. An input the request leaves open is not
/// established — "some input", not "any input" — and every candidate passes that side.
- (BOOL)isDispatchable:(CSCapUrn *)request {
    return CSCapModelRelation(capdagFormal_dispatch, _formal, request->_formal, @"decide dispatch");
}

/// This candidate's key in the proved ranking for `request` (CapDAG.Exec.rankingKey); owned.
- (lungo_value *)rankingKeyFor:(CSCapUrn *)request {
    lungo_value *key = NULL;
    lungo_error *error = NULL;
    if (capdagFormal_ranking_key(_formal, request->_formal, &key, &error) != LUNGO_OK) {
        CSCapModelFailed(@"rank a cap", error);
    }
    return key;
}

/// A part of a ranking key, which the model gives as a natural number.
static uint64_t CSCapRankingKeyPart(const lungo_value *part) {
    uint64_t value = 0;
    if (!lungo_value_get_nat(part, &value)) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"capdag: a ranking key does not fit"
                                     userInfo:nil];
    }
    return value;
}

/// Orders two ranking keys as the model does: by their first part, then by their second.
static NSComparisonResult CSCapCompareRankingKeys(const lungo_value *a, const lungo_value *b) {
    uint64_t a1 = CSCapRankingKeyPart(lungo_value_first(a)), b1 = CSCapRankingKeyPart(lungo_value_first(b));
    if (a1 != b1) return a1 < b1 ? NSOrderedAscending : NSOrderedDescending;
    uint64_t a2 = CSCapRankingKeyPart(lungo_value_second(a)), b2 = CSCapRankingKeyPart(lungo_value_second(b));
    if (a2 != b2) return a2 < b2 ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame;
}

- (NSComparisonResult)compareRankWith:(CSCapUrn *)other forRequest:(CSCapUrn *)request {
    lungo_value *mine = [self rankingKeyFor:request];
    lungo_value *theirs = [other rankingKeyFor:request];
    NSComparisonResult order = CSCapCompareRankingKeys(mine, theirs);
    lungo_value_free(mine);
    lungo_value_free(theirs);
    return order;
}

+ (NSUInteger)selectFromCandidates:(NSArray<CSCapUrn *> *)candidates forRequest:(CSCapUrn *)request {
    lungo_value **items = calloc(MAX(candidates.count, (NSUInteger)1), sizeof(lungo_value *));
    for (NSUInteger i = 0; i < candidates.count; i++) {
        items[i] = lungo_value_clone(candidates[i]->_formal);
    }
    lungo_value *list = lungo_value_list(items, (size_t)candidates.count);
    free(items);
    lungo_value *result = NULL;
    lungo_error *error = NULL;
    if (capdagFormal_select(list, request->_formal, &result, &error) != LUNGO_OK) {
        lungo_value_free(list);
        CSCapModelFailed(@"select a cap", error);
    }
    lungo_value_free(list);
    const lungo_value *chosen = lungo_value_get_option(result);
    if (!chosen) {
        lungo_value_free(result);
        return NSNotFound;
    }
    // The model returns the cap it chose; it is the first candidate that serves the request
    // with the chosen cap's key, since the model keeps the first of equal keys.
    lungo_value *key = NULL;
    if (capdagFormal_ranking_key(chosen, request->_formal, &key, &error) != LUNGO_OK) {
        lungo_value_free(result);
        CSCapModelFailed(@"rank a cap", error);
    }
    lungo_value_free(result);
    NSUInteger position = NSNotFound;
    for (NSUInteger i = 0; i < candidates.count && position == NSNotFound; i++) {
        CSCapUrn *candidate = candidates[i];
        if (![candidate isDispatchable:request]) continue;
        lungo_value *candidateKey = [candidate rankingKeyFor:request];
        if (CSCapCompareRankingKeys(candidateKey, key) == NSOrderedSame) position = i;
        lungo_value_free(candidateKey);
    }
    lungo_value_free(key);
    if (position == NSNotFound) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:@"capdag: the model chose a cap to serve %@ that is none of the candidates", [request toString]]
                                     userInfo:nil];
    }
    return position;
}

/// Whether this candidate COULD serve `request`: not guaranteed, not excluded.
- (BOOL)mayDispatch:(CSCapUrn *)request {
    return CSCapModelRelation(capdagFormal_may_dispatch, _formal, request->_formal, @"decide possible dispatch");
}

/// Whether what this cap gives, `next` takes: the edge of a route.
- (BOOL)flowsInto:(CSCapUrn *)next {
    return CSCapModelRelation(capdagFormal_flows, _formal, next->_formal, @"decide a flow");
}

/// Whether what this cap gives COULD be something `next` takes.
- (BOOL)mayFlowInto:(CSCapUrn *)next {
    return CSCapModelRelation(capdagFormal_may_flow, _formal, next->_formal, @"decide a possible flow");
}

- (nullable CSMediaUrn *)inferRuntimeOutputMedia:(CSMediaUrn *)runtimeInput error:(NSError **)error {
    NSError *parseError = nil;
    CSMediaUrn *declaredIn = [CSMediaUrn fromString:self.inSpec error:&parseError];
    if (!declaredIn) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidEffectApplication
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid declared input media '%@': %@", self.inSpec, parseError.localizedDescription ?: @"unknown error"]}];
        }
        return nil;
    }
    parseError = nil;
    CSMediaUrn *declaredOut = [CSMediaUrn fromString:self.outSpec error:&parseError];
    if (!declaredOut) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidEffectApplication
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid declared output media '%@': %@", self.outSpec, parseError.localizedDescription ?: @"unknown error"]}];
        }
        return nil;
    }

    parseError = nil;
    // A runtime media URN is the media of a value that exists, so it is read complete: it
    // SATISFIES the declared type, or does not.
    BOOL inputConforms = [runtimeInput satisfies:declaredIn error:&parseError];
    if (!inputConforms) {
        if (error) {
            NSString *message = parseError
                ? [NSString stringWithFormat:@"Failed to compare runtime input '%@' against declared input '%@': %@", [runtimeInput toString], [declaredIn toString], parseError.localizedDescription]
                : [NSString stringWithFormat:@"Runtime input '%@' does not conform to declared input '%@'", [runtimeInput toString], [declaredIn toString]];
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidEffectApplication
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    CSCapEffect effect = [self effect];
    if (effect == CSCapEffectAny) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidEffectApplication
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot infer runtime output media from unconstrained effect '?'. Requests may use ?effect; candidates may not."}];
        }
        return nil;
    }

    if (effect == CSCapEffectNone) {
        parseError = nil;
        BOOL outputConforms = [runtimeInput satisfies:declaredOut error:&parseError];
        if (!outputConforms) {
            if (error) {
                NSString *message = parseError
                    ? [NSString stringWithFormat:@"Failed to validate runtime output '%@' against declared output '%@': %@", [runtimeInput toString], [declaredOut toString], parseError.localizedDescription]
                    : [NSString stringWithFormat:@"Inferred runtime output '%@' does not conform to declared output '%@'", [runtimeInput toString], [declaredOut toString]];
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorInvalidEffectApplication
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return nil;
        }
        return runtimeInput;
    }

    if (effect == CSCapEffectDeclared) {
        return declaredOut;
    }

    CSTaggedUrnCoordinateDelta *delta = [declaredOut deltaFrom:declaredIn error:&parseError];
    if (!delta) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidEffectApplication
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to compute output-input media delta for patch effect: %@", parseError.localizedDescription ?: @"unknown error"]}];
        }
        return nil;
    }
    CSMediaUrn *result = [runtimeInput applyDelta:delta error:&parseError];
    if (!result) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidEffectApplication
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to apply patch effect delta to runtime media '%@': %@", [runtimeInput toString], parseError.localizedDescription ?: @"unknown error"]}];
        }
        return nil;
    }

    parseError = nil;
    BOOL outputConforms = [result satisfies:declaredOut error:&parseError];
    if (!outputConforms) {
        if (error) {
            NSString *message = parseError
                ? [NSString stringWithFormat:@"Failed to validate runtime output '%@' against declared output '%@': %@", [result toString], [declaredOut toString], parseError.localizedDescription]
                : [NSString stringWithFormat:@"Inferred runtime output '%@' does not conform to declared output '%@'", [result toString], [declaredOut toString]];
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidEffectApplication
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }
    return result;
}

- (BOOL)isConformantRuntimeOutput:(CSMediaUrn *)runtimeInput
                    runtimeOutput:(CSMediaUrn *)runtimeOutput
                            error:(NSError **)error {
    // THE effect-audit predicate: every check of "did the cap emit what its
    // effect promised" must go through it — never a hand-rolled combination
    // of inferRuntimeOutputMedia with equality or conformance checks, so the
    // contract has exactly one definition.
    //
    // effect=none / effect=patch compute an EXACT runtime output type, so
    // the emission must be tag-equivalent to the inference (a more specific
    // emission is still a lie). effect=declared promises only the declared
    // out=, so the emission must conform to it — more specific is legal,
    // more generic fails.
    //
    // Returns NO with *error set when the inference itself is impossible
    // (nonconforming runtime input, unconstrained ?effect, inconsistent URN
    // state) — an upstream contract break, not an emission mismatch.
    // Returns NO with no error for a clean nonconformant emission.
    NSError *inferError = nil;
    CSMediaUrn *inferred = [self inferRuntimeOutputMedia:runtimeInput error:&inferError];
    if (!inferred) {
        if (error) {
            *error = inferError
                ?: [NSError errorWithDomain:CSCapUrnErrorDomain
                                       code:CSCapUrnErrorInvalidEffectApplication
                                   userInfo:@{NSLocalizedDescriptionKey: @"Runtime output inference failed without a diagnostic"}];
        }
        return NO;
    }

    CSCapEffect effect = [self effect];
    if (effect == CSCapEffectNone || effect == CSCapEffectPatch) {
        return [runtimeOutput isEquivalentTo:inferred];
    }
    if (effect == CSCapEffectDeclared) {
        NSError *compareError = nil;
        BOOL conforms = [runtimeOutput satisfies:inferred error:&compareError];
        if (!conforms && compareError) {
            if (error) {
                *error = compareError;
            }
            return NO;
        }
        return conforms;
    }
    // CSCapEffectAny is unreachable — inferRuntimeOutputMedia already
    // rejected it above — but the audit must never silently pass an
    // unhandled effect.
    if (error) {
        *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                     code:CSCapUrnErrorInvalidEffectApplication
                                 userInfo:@{NSLocalizedDescriptionKey: @"Cannot audit an emission against an unconstrained effect request"}];
    }
    return NO;
}

- (BOOL)isComparable:(CSCapUrn *)other {
    return CSCapModelRelation(capdagFormal_comparable, _formal, other->_formal, @"decide comparability");
}

- (BOOL)isEquivalent:(CSCapUrn *)other {
    return CSCapModelRelation(capdagFormal_equivalent, _formal, other->_formal, @"decide equivalence");
}

/// A cap's stored `in=` or `out=` as a media URN. The cap was parsed, so its
/// sides are media URNs; one that is not is a broken invariant.
static CSMediaUrn *CSCapSideMedia(NSString *spec) {
    NSError *error = nil;
    CSMediaUrn *media = [CSMediaUrn fromString:spec error:&error];
    if (media == nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"CSCapUrn invariant: '%@' parses as a media URN: %@",
                           spec, error.localizedDescription];
    }
    return media;
}

/// A cap's cap-tags as the tagged URN they make. The cap was made from them,
/// so a map that is no tagged URN is a broken invariant.
static CSTaggedUrn *CSCapTagUrn(NSDictionary<NSString *, CSTagConstraint *> *tags) {
    NSError *error = nil;
    CSTaggedUrn *urn = [CSTaggedUrn fromPrefix:@"cap" tags:tags error:&error];
    if (urn == nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"CSCapUrn invariant: its cap-tags make a tagged URN: %@", error.localizedDescription];
    }
    return urn;
}

- (NSComparisonResult)compareStructurally:(CSCapUrn *)other {
    NSComparisonResult byIn = [CSCapSideMedia(self.inSpec) compareStructurally:CSCapSideMedia(other.inSpec)];
    if (byIn != NSOrderedSame) return byIn;
    NSComparisonResult byOut = [CSCapSideMedia(self.outSpec) compareStructurally:CSCapSideMedia(other.outSpec)];
    if (byOut != NSOrderedSame) return byOut;
    CSCapEffect effectA = [self effect];
    CSCapEffect effectB = [other effect];
    if (effectA != effectB) {
        return effectA < effectB ? NSOrderedAscending : NSOrderedDescending;
    }
    return [CSCapTagUrn(self.mutableTags) compare:CSCapTagUrn(other.mutableTags)];
}

- (NSUInteger)specificity {
    // Weighted sum of the per-tag truth-table score across the structural
    // axes: out, in, and the cap-local y-axis tags. Effect dispatch is exact
    // when constrained, but effect does not currently participate in
    // specificity scoring. Per-tag
    // ladder:
    //   "?"            -> 0   (no constraint)
    //   starts "?="    -> 1   (absent or not v)
    //   "*"            -> 2   (must-have-any)
    //   starts "!="    -> 3   (present and not v)
    //   exact value    -> 4   (exact match)
    //   "!"            -> 5   (must-not-have)
    //
    // Axis weighting:
    //   spec_C(c) = WEIGHT_OUT * spec_U(c.out)
    //             + WEIGHT_IN  * spec_U(c.in)
    //             +              spec_U(c.y)
    //
    // Lexicographic priority (out, in, y) reflects the routing
    // intent: producing different things is the largest semantic
    // difference between two caps; consuming different things is
    // next; descriptive y-axis metadata is last.

    //
    // Computed by the proved model (CapDAG.Exec.specificity).
    lungo_value *result = NULL;
    lungo_error *error = NULL;
    if (capdagFormal_specificity(_formal, &result, &error) != LUNGO_OK) CSCapModelFailed(@"score a cap", error);
    uint64_t score = 0;
    BOOL fits = lungo_value_get_nat(result, &score);
    lungo_value_free(result);
    if (!fits) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:@"capdag: the specificity of %@ does not fit", [self toString]]
                                     userInfo:nil];
    }
    return (NSUInteger)score;
}

- (BOOL)isMoreSpecificThan:(CSCapUrn *)other {
    if (!other) {
        return YES;
    }

    return self.specificity > other.specificity;
}

- (CSCapUrn *)withWildcardTag:(NSString *)key {
    NSString *keyLower = [key lowercaseString];
    NSString *inSpec = self.inSpec, *outSpec = self.outSpec, *effect = self.effectSpec;
    NSMutableDictionary *tags = [self.mutableTags mutableCopy];
    if ([keyLower isEqualToString:@"in"]) {
        inSpec = @"media:";
    } else if ([keyLower isEqualToString:@"out"]) {
        outSpec = @"media:";
    } else if ([keyLower isEqualToString:@"effect"]) {
        effect = @"?";
    } else if (tags[keyLower]) {
        tags[keyLower] = [CSTagConstraint present];
    }
    return [[self class] mustCreateFromInSpec:inSpec outSpec:outSpec effect:effect tags:tags context:@"CSCapUrn.withWildcardTag"];
}

- (CSCapUrn *)subset:(NSArray<NSString *> *)keys {
    // Direction and effect are always kept; the subset is of the cap-tags.
    NSMutableDictionary *newTags = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *normalizedKey = [key lowercaseString];
        CSTagConstraint *constraint = self.mutableTags[normalizedKey];
        if (constraint) {
            newTags[normalizedKey] = constraint;
        }
    }
    return [[self class] mustCreateFromInSpec:self.inSpec
                                      outSpec:self.outSpec
                                       effect:self.effectSpec
                                         tags:newTags
                                      context:@"CSCapUrn.subset"];
}

- (CSCapUrn *)merge:(CSCapUrn *)other {
    // Direction comes from other (other takes precedence)
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    [newTags addEntriesFromDictionary:other.mutableTags];
    return [[self class] mustCreateFromInSpec:other.inSpec
                                      outSpec:other.outSpec
                                       effect:other.effectSpec
                                         tags:newTags
                                      context:@"CSCapUrn.merge"];
}

- (NSString *)toString {
    // `in` and `out` are written only when they refine beyond the top media `media:`.
    // `effect=declared` is the default and omitted; the unconstrained effect is `?effect`.
    // `effect=none` is kept, so the categorical identity is `cap:effect=none`, never bare `cap:`.
    NSMutableDictionary<NSString *, CSTagConstraint *> *allTags = [self.mutableTags mutableCopy];
    if (![self.inSpec isEqualToString:@"media:"]) {
        allTags[@"in"] = [CSTagConstraint exact:self.inSpec];
    }
    if (![self.outSpec isEqualToString:@"media:"]) {
        allTags[@"out"] = [CSTagConstraint exact:self.outSpec];
    }
    if ([self.effectSpec isEqualToString:@"?"]) {
        allTags[@"effect"] = [CSTagConstraint unconstrained];
    } else if (![self.effectSpec isEqualToString:@"declared"]) {
        allTags[@"effect"] = [CSTagConstraint exact:self.effectSpec];
    }

    NSError *error = nil;
    CSTaggedUrn *taggedUrn = [CSTaggedUrn fromPrefix:@"cap" tags:allTags error:&error];
    NSAssert(taggedUrn != nil, @"CSTaggedUrn serialization failed: %@", error.localizedDescription);
    return [taggedUrn toString];
}

- (NSString *)description {
    return [self toString];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[CSCapUrn class]]) {
        return NO;
    }

    CSCapUrn *other = (CSCapUrn *)object;
    // Compare direction specs first
    if (![self.inSpec isEqualToString:other.inSpec]) {
        return NO;
    }
    if (![self.outSpec isEqualToString:other.outSpec]) {
        return NO;
    }
    if (![self.effectSpec isEqualToString:other.effectSpec]) {
        return NO;
    }
    // Then compare tags
    return [self.mutableTags isEqualToDictionary:other.mutableTags];
}

- (NSUInteger)hash {
    // Include direction specs in hash
    return self.inSpec.hash ^ self.outSpec.hash ^ self.effectSpec.hash ^ self.mutableTags.hash;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] mustCreateFromInSpec:self.inSpec
                                      outSpec:self.outSpec
                                       effect:self.effectSpec
                                         tags:self.mutableTags
                                      context:@"CSCapUrn.copy"];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.inSpec forKey:@"inSpec"];
    [coder encodeObject:self.outSpec forKey:@"outSpec"];
    [coder encodeObject:self.effectSpec forKey:@"effectSpec"];
    [coder encodeObject:self.mutableTags forKey:@"tags"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSString *inSpec = [coder decodeObjectOfClass:[NSString class] forKey:@"inSpec"];
    NSString *outSpec = [coder decodeObjectOfClass:[NSString class] forKey:@"outSpec"];
    NSString *effectSpec = [coder decodeObjectOfClass:[NSString class] forKey:@"effectSpec"] ?: @"declared";
    NSDictionary<NSString *, CSTagConstraint *> *tags =
        [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSDictionary class], [NSString class], [CSTagConstraint class], nil]
                              forKey:@"tags"] ?: @{};
    // Decoded as it is made: through the constructor that validates and assembles it.
    CSCapUrn *decoded = [[self class] fromCanonicalInSpec:inSpec outSpec:outSpec effect:effectSpec tags:tags error:nil];
    if (!decoded) {
        return nil;
    }
    return [self initWithInSpec:decoded.inSpec outSpec:decoded.outSpec effectSpec:decoded.effectSpec
                         tagUrn:[CSTaggedUrn fromPrefix:@"cap" tags:decoded.tags error:nil]];
}

@end

#pragma mark - CSCapUrnBuilder

@interface CSCapUrnBuilder ()
@property (nonatomic, strong) NSString *builderInSpec;
@property (nonatomic, strong) NSString *builderOutSpec;
@property (nonatomic, assign) CSCapEffect builderEffect;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSTagConstraint *> *tags;
@end

@implementation CSCapUrnBuilder

+ (instancetype)builder {
    return [[CSCapUrnBuilder alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        _tags = [NSMutableDictionary dictionary];
        _builderInSpec = nil;
        _builderOutSpec = nil;
        _builderEffect = CSCapEffectDeclared;
    }
    return self;
}

- (CSCapUrnBuilder *)inSpec:(NSString *)spec {
    self.builderInSpec = spec;
    return self;
}

- (CSCapUrnBuilder *)outSpec:(NSString *)spec {
    self.builderOutSpec = spec;
    return self;
}

- (CSCapUrnBuilder *)effect:(CSCapEffect)effect {
    self.builderEffect = effect;
    return self;
}

- (CSCapUrnBuilder *)tag:(NSString *)key constraint:(CSTagConstraint *)constraint {
    NSString *keyLower = [key lowercaseString];
    if ([CSCapStructuralKeys() containsObject:keyLower]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSCapUrnBuilder cannot set reserved structural key '%@'; use inSpec:/outSpec:/effect:", keyLower];
    }
    self.tags[keyLower] = constraint;
    return self;
}

- (CSCapUrnBuilder *)tag:(NSString *)key value:(NSString *)value {
    return [self tag:key constraint:[CSTagConstraint exact:value]];
}

- (CSCapUrnBuilder *)marker:(NSString *)key {
    return [self tag:key constraint:[CSTagConstraint present]];
}

- (nullable CSCapUrn *)build:(NSError **)error {
    if (!self.builderInSpec) {
        if (error) *error = CSCapError(CSCapUrnErrorMissingInSpec, @"Cap URN requires 'in' tag");
        return nil;
    }
    if (!self.builderOutSpec) {
        if (error) *error = CSCapError(CSCapUrnErrorMissingOutSpec, @"Cap URN requires 'out' tag");
        return nil;
    }
    return [CSCapUrn fromInSpec:self.builderInSpec
                        outSpec:self.builderOutSpec
                         effect:CSCapEffectToString(self.builderEffect)
                           tags:self.tags
                          error:error];
}


@end
