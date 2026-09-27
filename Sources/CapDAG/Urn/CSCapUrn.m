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

static NSString * _Nullable CSCapNormalizeEffectValue(NSString * _Nullable rawValue, NSError **error) {
    if (!rawValue) {
        return @"declared";
    }
    if ([rawValue isEqualToString:@"*"] || [rawValue isEqualToString:@"?"]) {
        return @"?";
    }
    if ([rawValue isEqualToString:@"declared"] ||
        [rawValue isEqualToString:@"none"] ||
        [rawValue isEqualToString:@"patch"]) {
        return rawValue;
    }
    if (rawValue.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidEffect
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty value for 'effect' tag is not allowed"}];
        }
        return nil;
    }
    if (error) {
        *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                     code:CSCapUrnErrorInvalidEffect
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Unsupported effect '%@'. Supported values are declared, none, patch, or explicit unconstrained ?effect/effect=*", rawValue]}];
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *mutableTags;
- (instancetype)initWithInSpec:(NSString *)inSpec
                       outSpec:(NSString *)outSpec
                    effectSpec:(NSString *)effectSpec
                        tagUrn:(CSTaggedUrn *)tagUrn NS_DESIGNATED_INITIALIZER;
@end

@implementation CSCapUrn

+ (CSCapUrn *)mustCreateFromInSpec:(NSString *)inSpec
                           outSpec:(NSString *)outSpec
                            effect:(NSString *)effect
                              tags:(NSDictionary<NSString *, NSString *> *)tags
                           context:(NSString *)context {
    NSError *error = nil;
    CSCapUrn *result = [self fromInSpec:inSpec outSpec:outSpec effect:effect tags:tags error:&error];
    if (!result) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"%@ produced an illegal cap declaration: %@", context, error.localizedDescription ?: @"unknown error"];
    }
    return result;
}

+ (BOOL)validateAdmissibleInSpec:(NSString *)inSpec
                         outSpec:(NSString *)outSpec
                          effect:(NSString *)effect
                            tags:(NSDictionary<NSString *, NSString *> *)tags
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

- (NSDictionary<NSString *, NSString *> *)tags {
    return [self.mutableTags copy];
}

// Note: Utility methods (needsQuoting, quoteValue) are delegated to CSTaggedUrn

#pragma mark - Media URN Validation

+ (BOOL)isValidMediaUrnOrWildcard:(NSString *)value {
    return [value isEqualToString:@"*"] || [value hasPrefix:@"media:"];
}

#pragma mark - Parsing

/// Convert CSTaggedUrnError to CSCapUrnError with appropriate error code
+ (NSError *)capUrnErrorFromTaggedUrnError:(NSError *)taggedError {
    NSString *msg = taggedError.localizedDescription ?: @"";
    NSString *msgLower = [msg lowercaseString];

    CSCapUrnError code;
    if ([msgLower containsString:@"invalid character"]) {
        code = CSCapUrnErrorInvalidCharacter;
    } else if ([msgLower containsString:@"duplicate"]) {
        code = CSCapUrnErrorDuplicateKey;
    } else if ([msgLower containsString:@"unterminated"] || [msgLower containsString:@"unclosed"]) {
        code = CSCapUrnErrorUnterminatedQuote;
    } else if ([msgLower containsString:@"expected"] && [msgLower containsString:@"after quoted"]) {
        // "expected ';' or end after quoted value" - treat as unterminated quote for compatibility
        code = CSCapUrnErrorUnterminatedQuote;
    } else if ([msgLower containsString:@"numeric"]) {
        code = CSCapUrnErrorNumericKey;
    } else if ([msgLower containsString:@"escape"]) {
        code = CSCapUrnErrorInvalidEscapeSequence;
    } else if ([msgLower containsString:@"incomplete"] || [msgLower containsString:@"missing value"]) {
        code = CSCapUrnErrorInvalidTagFormat;
    } else {
        code = CSCapUrnErrorInvalidFormat;
    }

    return [NSError errorWithDomain:CSCapUrnErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
}

/// Process a direction tag (in or out) with wildcard expansion
/// - Missing tag → "media:" (wildcard)
/// - tag=* → "media:" (wildcard)
/// - tag= (empty) → error
/// - tag=value → value (validated later)
+ (nullable NSString *)processDirectionTag:(CSTaggedUrn *)taggedUrn tagName:(NSString *)tagName error:(NSError **)error {
    NSString *value = [taggedUrn getTag:tagName];

    if (!value) {
        // Missing tag - default to media: wildcard
        return @"media:";
    }

    if ([value isEqualToString:@"*"]) {
        // Replace * with media: wildcard
        return @"media:";
    }

    if ([value length] == 0) {
        // Empty value is not allowed (in= or out= with nothing after =)
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"Empty value for '%@' tag is not allowed", tagName];
            NSInteger errorCode = [tagName isEqualToString:@"in"] ? CSCapUrnErrorInvalidInSpec : CSCapUrnErrorInvalidOutSpec;
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:errorCode
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return nil;
    }

    // Regular value - will be validated as MediaUrn later
    return value;
}

+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error {
    if (!string || string.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier cannot be empty"}];
        }
        return nil;
    }

    // Check for "cap:" prefix early to give better error messages
    if (string.length < 4 || [[string substringToIndex:4] caseInsensitiveCompare:@"cap:"] != NSOrderedSame) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingCapPrefix
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier must start with 'cap:'"}];
        }
        return nil;
    }

    // Use CSTaggedUrn for parsing
    NSError *parseError = nil;
    CSTaggedUrn *taggedUrn = [CSTaggedUrn fromString:string error:&parseError];
    if (parseError) {
        if (error) {
            *error = [self capUrnErrorFromTaggedUrnError:parseError];
        }
        return nil;
    }

    // Double-check prefix (should always be 'cap' after the early check above)
    if (![[taggedUrn.prefix lowercaseString] isEqualToString:@"cap"]) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingCapPrefix
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Expected 'cap:' prefix, got '%@:'", taggedUrn.prefix]}];
        }
        return nil;
    }

    // Process in and out tags with wildcard expansion (exactly matching Rust behavior)
    // - Missing tag → "media:" (wildcard)
    // - tag=* → "media:" (wildcard)
    // - tag= (empty) → error
    // - tag=value → value (validated later)
    NSString *inSpecValue = [self processDirectionTag:taggedUrn tagName:@"in" error:error];
    if (!inSpecValue) {
        return nil;
    }
    NSString *outSpecValue = [self processDirectionTag:taggedUrn tagName:@"out" error:error];
    if (!outSpecValue) {
        return nil;
    }
    NSString *effectValue = CSCapNormalizeEffectValue([taggedUrn getTag:@"effect"], error);
    if (!effectValue) {
        return nil;
    }

    // Validate that in and out specs are valid media URNs (or wildcard "media:")
    // After processing, "media:" is the wildcard (not "*")
    if (![inSpecValue isEqualToString:@"media:"]) {
        NSError *mediaError = nil;
        CSMediaUrn *inMediaUrn = [CSMediaUrn fromString:inSpecValue error:&mediaError];
        if (!inMediaUrn) {
            if (error) {
                NSString *errorMsg = mediaError ? mediaError.localizedDescription : @"Unknown error";
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorInvalidInSpec
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid media URN for in spec '%@': %@", inSpecValue, errorMsg]}];
            }
            return nil;
        }
    }
    if (![outSpecValue isEqualToString:@"media:"]) {
        NSError *mediaError = nil;
        CSMediaUrn *outMediaUrn = [CSMediaUrn fromString:outSpecValue error:&mediaError];
        if (!outMediaUrn) {
            if (error) {
                NSString *errorMsg = mediaError ? mediaError.localizedDescription : @"Unknown error";
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorInvalidOutSpec
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid media URN for out spec '%@': %@", outSpecValue, errorMsg]}];
            }
            return nil;
        }
    }

    // Build remaining tags (excluding in/out)
    NSMutableDictionary<NSString *, NSString *> *remainingTags = [NSMutableDictionary dictionary];
    for (NSString *key in taggedUrn.tags) {
        NSString *keyLower = [key lowercaseString];
        if (![keyLower isEqualToString:@"in"] && ![keyLower isEqualToString:@"out"] && ![keyLower isEqualToString:@"effect"]) {
            remainingTags[keyLower] = taggedUrn.tags[key];
        }
    }

    return [self fromInSpec:inSpecValue outSpec:outSpecValue effect:effectValue tags:remainingTags error:error];
}

+ (nullable instancetype)fromTags:(NSDictionary<NSString *, NSString *> *)tags error:(NSError **)error {
    if (!tags) {
        tags = @{};
    }

    // Normalize keys to lowercase; values preserved as-is
    NSMutableDictionary<NSString *, NSString *> *normalizedTags = [NSMutableDictionary dictionary];
    for (NSString *key in tags) {
        NSString *value = tags[key];
        normalizedTags[[key lowercaseString]] = value;
    }

    // Process in and out tags with wildcard expansion
    // - Missing tag → "media:" (wildcard)
    // - tag=* → "media:" (wildcard)
    // - tag= (empty) → error
    // - tag=value → value (validated later)
    NSString *inSpecValue = normalizedTags[@"in"];
    if (!inSpecValue || [inSpecValue isEqualToString:@"*"]) {
        inSpecValue = @"media:";
    } else if ([inSpecValue length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidInSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty value for 'in' tag is not allowed"}];
        }
        return nil;
    }

    NSString *outSpecValue = normalizedTags[@"out"];
    if (!outSpecValue || [outSpecValue isEqualToString:@"*"]) {
        outSpecValue = @"media:";
    } else if ([outSpecValue length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidOutSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty value for 'out' tag is not allowed"}];
        }
        return nil;
    }

    NSString *effectValue = CSCapNormalizeEffectValue(normalizedTags[@"effect"], error);
    if (!effectValue) {
        return nil;
    }

    // Validate that in and out specs are valid media URNs (or wildcard "media:")
    // After processing, "media:" is the wildcard (not "*")
    if (![inSpecValue isEqualToString:@"media:"]) {
        NSError *mediaError = nil;
        CSMediaUrn *inMediaUrn = [CSMediaUrn fromString:inSpecValue error:&mediaError];
        if (!inMediaUrn) {
            if (error) {
                NSString *errorMsg = mediaError ? mediaError.localizedDescription : @"Unknown error";
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorInvalidInSpec
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid media URN for in spec '%@': %@", inSpecValue, errorMsg]}];
            }
            return nil;
        }
    }
    if (![outSpecValue isEqualToString:@"media:"]) {
        NSError *mediaError = nil;
        CSMediaUrn *outMediaUrn = [CSMediaUrn fromString:outSpecValue error:&mediaError];
        if (!outMediaUrn) {
            if (error) {
                NSString *errorMsg = mediaError ? mediaError.localizedDescription : @"Unknown error";
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorInvalidOutSpec
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid media URN for out spec '%@': %@", outSpecValue, errorMsg]}];
            }
            return nil;
        }
    }

    // Build remaining tags (excluding in/out)
    NSMutableDictionary<NSString *, NSString *> *remainingTags = [NSMutableDictionary dictionary];
    for (NSString *key in normalizedTags) {
        if (![key isEqualToString:@"in"] && ![key isEqualToString:@"out"] && ![key isEqualToString:@"effect"]) {
            remainingTags[key] = normalizedTags[key];
        }
    }

    return [self fromInSpec:inSpecValue outSpec:outSpecValue effect:effectValue tags:remainingTags error:error];
}

+ (nullable instancetype)fromInSpec:(NSString *)inSpec
                            outSpec:(NSString *)outSpec
                             effect:(NSString *)effect
                               tags:(NSDictionary<NSString *, NSString *> *)tags
                              error:(NSError **)error {
    // Apply wildcard expansion to in/out specs (exactly matching Rust behavior)
    // - nil or "*" → "media:"
    // - Empty string → error
    // - Other value → validate as MediaUrn

    // Process in spec
    NSString *processedInSpec;
    if (!inSpec || [inSpec isEqualToString:@"*"]) {
        processedInSpec = @"media:";
    } else if ([inSpec length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidInSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty value for 'in' spec is not allowed"}];
        }
        return nil;
    } else {
        processedInSpec = inSpec;
    }

    // Process out spec
    NSString *processedOutSpec;
    if (!outSpec || [outSpec isEqualToString:@"*"]) {
        processedOutSpec = @"media:";
    } else if ([outSpec length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidOutSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty value for 'out' spec is not allowed"}];
        }
        return nil;
    } else {
        processedOutSpec = outSpec;
    }

    // Validate that in and out specs are valid media URNs (or wildcard "media:")
    if (![processedInSpec isEqualToString:@"media:"]) {
        NSError *mediaError = nil;
        CSMediaUrn *inMediaUrn = [CSMediaUrn fromString:processedInSpec error:&mediaError];
        if (!inMediaUrn) {
            if (error) {
                NSString *errorMsg = mediaError ? mediaError.localizedDescription : @"Unknown error";
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorInvalidInSpec
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid media URN for in spec '%@': %@", processedInSpec, errorMsg]}];
            }
            return nil;
        }
    }
    if (![processedOutSpec isEqualToString:@"media:"]) {
        NSError *mediaError = nil;
        CSMediaUrn *outMediaUrn = [CSMediaUrn fromString:processedOutSpec error:&mediaError];
        if (!outMediaUrn) {
            if (error) {
                NSString *errorMsg = mediaError ? mediaError.localizedDescription : @"Unknown error";
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorInvalidOutSpec
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid media URN for out spec '%@': %@", processedOutSpec, errorMsg]}];
            }
            return nil;
        }
    }

    NSString *normalizedEffect = CSCapNormalizeEffectValue(effect, error);
    if (!normalizedEffect) {
        return nil;
    }

    NSError *tagError = nil;
    CSTaggedUrn *validatedTags = [CSTaggedUrn fromPrefix:@"cap" tags:tags ?: @{} error:&tagError];
    if (!validatedTags) {
        if (error) {
            *error = [self capUrnErrorFromTaggedUrnError:tagError];
        }
        return nil;
    }

    if (![self validateAdmissibleInSpec:processedInSpec outSpec:processedOutSpec effect:normalizedEffect tags:validatedTags.tags error:error]) {
        return nil;
    }
    return [[CSCapUrn alloc] initWithInSpec:processedInSpec outSpec:processedOutSpec effectSpec:normalizedEffect tagUrn:validatedTags];
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
        _mutableTags = [tagUrn.tags mutableCopy];
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

- (nullable NSString *)getTag:(NSString *)key {
    NSString *keyLower = [key lowercaseString];
    if ([keyLower isEqualToString:@"in"]) {
        return self.inSpec;
    }
    if ([keyLower isEqualToString:@"out"]) {
        return self.outSpec;
    }
    if ([keyLower isEqualToString:@"effect"]) {
        return self.effectSpec;
    }
    return self.mutableTags[keyLower];
}

- (BOOL)hasTag:(NSString *)key withValue:(NSString *)value {
    NSString *keyLower = [key lowercaseString];
    NSString *tagValue;
    if ([keyLower isEqualToString:@"in"]) {
        tagValue = self.inSpec;
    } else if ([keyLower isEqualToString:@"out"]) {
        tagValue = self.outSpec;
    } else if ([keyLower isEqualToString:@"effect"]) {
        tagValue = self.effectSpec;
    } else {
        tagValue = self.mutableTags[keyLower];
    }
    // Case-sensitive value comparison
    return tagValue && [tagValue isEqualToString:value];
}

- (BOOL)hasMarkerTag:(NSString *)tagName {
    NSString *keyLower = [tagName lowercaseString];
    // Marker semantics live on the tag map only — direction specs (in/out)
    // are not markers.
    if ([keyLower isEqualToString:@"in"] || [keyLower isEqualToString:@"out"] || [keyLower isEqualToString:@"effect"]) {
        return NO;
    }
    NSString *tagValue = self.mutableTags[keyLower];
    return tagValue && [tagValue isEqualToString:@"*"];
}

- (CSCapUrn *)withTag:(NSString *)key value:(NSString *)value {
    NSString *keyLower = [key lowercaseString];
    if ([keyLower isEqualToString:@"in"] || [keyLower isEqualToString:@"out"] || [keyLower isEqualToString:@"effect"]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Reserved structural key '%@' must be changed via withInSpec:, withOutSpec:, or withEffect:", keyLower];
    }
    if (value.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Empty value for key '%@' is not allowed (use '*' for wildcard)", key];
    }
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    newTags[keyLower] = value;
    return [[self class] mustCreateFromInSpec:self.inSpec
                                      outSpec:self.outSpec
                                       effect:self.effectSpec
                                         tags:newTags
                                      context:@"CSCapUrn.withTag"];
}

- (CSCapUrn *)withInSpec:(NSString *)inSpec {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    return [[self class] mustCreateFromInSpec:inSpec
                                      outSpec:self.outSpec
                                       effect:self.effectSpec
                                         tags:newTags
                                      context:@"CSCapUrn.withInSpec"];
}

- (CSCapUrn *)withOutSpec:(NSString *)outSpec {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    return [[self class] mustCreateFromInSpec:self.inSpec
                                      outSpec:outSpec
                                       effect:self.effectSpec
                                         tags:newTags
                                      context:@"CSCapUrn.withOutSpec"];
}

- (CSCapUrn *)withEffect:(CSCapEffect)effect {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    return [[self class] mustCreateFromInSpec:self.inSpec
                                      outSpec:self.outSpec
                                       effect:CSCapEffectToString(effect)
                                         tags:newTags
                                      context:@"CSCapUrn.withEffect"];
}

- (CSCapUrn *)withoutTag:(NSString *)key {
    NSString *keyLower = [key lowercaseString];
    if ([keyLower isEqualToString:@"in"] || [keyLower isEqualToString:@"out"] || [keyLower isEqualToString:@"effect"]) {
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

/// Whether this cap, as a PATTERN, accepts `request` as an instance: the request's input refines
/// this cap's, this cap's output refines the request's, the effect matches (this cap's ?effect
/// matching any), and the request's cap-tags refine this cap's. Decided by the proved model
/// (CapDAG.Exec.accepts); the cap-tag axis runs opposite to dispatch's.
- (BOOL)accepts:(CSCapUrn *)request {
    if (!request) {
        return YES;
    }
    return CSCapModelRelation(capdagFormal_accepts, _formal, request->_formal, @"decide acceptance");
}

- (BOOL)conformsTo:(CSCapUrn *)pattern {
    return [pattern accepts:self];
}

#pragma mark - Dispatch predicates

/// Whether this candidate can serve `request`, decided by the proved model
/// (CapDAG.Exec.dispatch): every axis is a type. The request's input refines the candidate's,
/// the candidate's output refines the request's, the effect matches unless the request says
/// ?effect, and the candidate's cap-tags refine the request's. `media:` on a request's input is
/// a type — "may send anything" — so only a candidate that accepts anything serves it, which is
/// what makes dispatch compose.
- (BOOL)isDispatchable:(CSCapUrn *)request {
    return CSCapModelRelation(capdagFormal_dispatch, _formal, request->_formal, @"decide dispatch");
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
    BOOL inputConforms = [runtimeInput conformsTo:declaredIn error:&parseError];
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
        BOOL outputConforms = [runtimeInput conformsTo:declaredOut error:&parseError];
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
    BOOL outputConforms = [result conformsTo:declaredOut error:&parseError];
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
        BOOL conforms = [runtimeOutput conformsTo:inferred error:&compareError];
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

    // Handle direction keys specially
    if ([keyLower isEqualToString:@"in"]) {
        return [self withInSpec:@"media:"];
    }
    if ([keyLower isEqualToString:@"out"]) {
        return [self withOutSpec:@"media:"];
    }
    if ([keyLower isEqualToString:@"effect"]) {
        return [self withEffect:CSCapEffectAny];
    }

    // For regular tags, only set wildcard if tag already exists
    if (self.mutableTags[keyLower]) {
        return [self withTag:key value:@"*"];
    }
    return self;
}

- (CSCapUrn *)subset:(NSArray<NSString *> *)keys {
    // Always preserve direction specs, subset only applies to other tags
    NSMutableDictionary *newTags = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *normalizedKey = [key lowercaseString];
        // Skip in/out keys - direction is always preserved
        if ([normalizedKey isEqualToString:@"in"] || [normalizedKey isEqualToString:@"out"]) {
            continue;
        }
        NSString *value = self.mutableTags[normalizedKey];
        if (value) {
            newTags[normalizedKey] = value;
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
    for (NSString *key in other.mutableTags) {
        newTags[key] = other.mutableTags[key];
    }
    return [[self class] mustCreateFromInSpec:other.inSpec
                                      outSpec:other.outSpec
                                       effect:other.effectSpec
                                         tags:newTags
                                      context:@"CSCapUrn.merge"];
}

- (NSString *)toString {
    // `in` and `out` segments are emitted only when they refine beyond
    // the trivial wildcard `media:`. `effect=declared` is the default and
    // omitted. `effect=none` is preserved, so the categorical identity
    // canonicalizes to `cap:effect=none`, never bare `cap:`.
    NSMutableDictionary *allTags = [self.mutableTags mutableCopy];
    if (![self.inSpec isEqualToString:@"media:"]) {
        allTags[@"in"] = self.inSpec;
    }
    if (![self.outSpec isEqualToString:@"media:"]) {
        allTags[@"out"] = self.outSpec;
    }
    if (![self.effectSpec isEqualToString:@"declared"]) {
        allTags[@"effect"] = self.effectSpec;
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
                                         tags:self.tags
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
    NSDictionary<NSString *, NSString *> *tags = [coder decodeObjectOfClass:[NSMutableDictionary class] forKey:@"tags"] ?: @{};
    // Decoded as it is made: through the constructor that validates and assembles it.
    CSCapUrn *decoded = [[self class] fromInSpec:inSpec outSpec:outSpec effect:effectSpec tags:tags error:nil];
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *tags;
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

- (CSCapUrnBuilder *)tag:(NSString *)key value:(NSString *)value {
    NSString *keyLower = [key lowercaseString];
    if ([keyLower isEqualToString:@"in"] || [keyLower isEqualToString:@"out"] || [keyLower isEqualToString:@"effect"]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Reserved structural key '%@' must be set via inSpec:, outSpec:, or effect:", keyLower];
    }
    self.tags[keyLower] = value;
    return self;
}

- (CSCapUrnBuilder *)marker:(NSString *)key {
    NSString *keyLower = [key lowercaseString];
    if ([keyLower isEqualToString:@"in"] || [keyLower isEqualToString:@"out"] || [keyLower isEqualToString:@"effect"]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Reserved structural key '%@' cannot be used as a marker", keyLower];
    }
    self.tags[keyLower] = @"*";
    return self;
}

- (nullable CSCapUrn *)build:(NSError **)error {
    // Require inSpec
    if (!self.builderInSpec) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingInSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap URN requires 'in' spec - use inSpec: method"}];
        }
        return nil;
    }

    // Require outSpec
    if (!self.builderOutSpec) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingOutSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap URN requires 'out' spec - use outSpec: method"}];
        }
        return nil;
    }

    return [CSCapUrn fromInSpec:self.builderInSpec
                        outSpec:self.builderOutSpec
                         effect:CSCapEffectToString(self.builderEffect)
                           tags:self.tags
                          error:error];
}


@end
