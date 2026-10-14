//
//  CSCapValidator.m
//  Cap schema validation for cartridge interactions
//
//  NOTE: Type validation now uses mediaDef -> spec ID resolution.
//  The old CSArgumentType and CSOutputType enums have been removed.
//

#import "CSCapValidator.h"
#import "CSSchemaValidator.h"
#import "CSMediaDef.h"
#import "CSMediaUrn.h"
#import "CSFabricRegistry.h"

// Error domain
NSErrorDomain const CSValidationErrorDomain = @"CSValidationErrorDomain";

// Error user info keys
NSString * const CSValidationErrorCapUrnKey = @"CSValidationErrorCapUrnKey";
NSString * const CSValidationErrorArgumentNameKey = @"CSValidationErrorArgumentNameKey";
NSString * const CSValidationErrorValidationRuleKey = @"CSValidationErrorValidationRuleKey";
NSString * const CSValidationErrorActualValueKey = @"CSValidationErrorActualValueKey";
NSString * const CSValidationErrorActualTypeKey = @"CSValidationErrorActualTypeKey";
NSString * const CSValidationErrorExpectedTypeKey = @"CSValidationErrorExpectedTypeKey";

@implementation CSValidationError

@synthesize validationType = _validationType;
@synthesize capUrn = _capUrn;
@synthesize argumentName = _argumentName;
@synthesize validationRule = _validationRule;
@synthesize actualValue = _actualValue;
@synthesize actualType = _actualType;
@synthesize expectedType = _expectedType;

- (instancetype)initWithType:(CSValidationErrorType)type
                capUrn:(NSString *)capUrn
                 description:(NSString *)description
                    userInfo:(NSDictionary *)userInfo {
    self = [super initWithDomain:CSValidationErrorDomain code:type userInfo:userInfo];
    if (self) {
        _validationType = type;
        _capUrn = [capUrn copy];
        _argumentName = [userInfo[CSValidationErrorArgumentNameKey] copy];
        _validationRule = [userInfo[CSValidationErrorValidationRuleKey] copy];
        _actualValue = userInfo[CSValidationErrorActualValueKey];
        _actualType = [userInfo[CSValidationErrorActualTypeKey] copy];
        _expectedType = [userInfo[CSValidationErrorExpectedTypeKey] copy];
    }
    return self;
}

+ (instancetype)unknownCapError:(NSString *)capUrn {
    NSString *description = [NSString stringWithFormat:@"Unknown cap '%@' - cap not registered or advertised", capUrn];
    return [[self alloc] initWithType:CSValidationErrorTypeUnknownCap
                         capUrn:capUrn
                          description:description
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)missingRequiredArgumentError:(NSString *)capUrn argumentName:(NSString *)argumentName {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' requires argument '%@' but it was not provided", capUrn, argumentName];
    return [[self alloc] initWithType:CSValidationErrorTypeMissingRequiredArgument
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName
                             }];
}

+ (instancetype)unknownArgumentError:(NSString *)capUrn argumentName:(NSString *)argumentName {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' has no argument named '%@'", capUrn, argumentName];
    return [[self alloc] initWithType:CSValidationErrorTypeUnknownArgument
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName
                             }];
}

+ (instancetype)invalidArgumentTypeError:(NSString *)capUrn
                            argumentName:(NSString *)argumentName
                            expectedType:(NSString *)expectedType
                              actualType:(NSString *)actualType
                             actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' argument '%@' expects type '%@' but received '%@' with value: %@",
                            capUrn, argumentName, expectedType, actualType, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidArgumentType
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName,
                                 CSValidationErrorExpectedTypeKey: expectedType,
                                 CSValidationErrorActualTypeKey: actualType,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)mediaValidationFailedError:(NSString *)capUrn
                                 argumentName:(NSString *)argumentName
                               validationRule:(NSString *)validationRule
                                  actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' argument '%@' failed validation rule '%@' with value: %@",
                            capUrn, argumentName, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeMediaValidationFailed
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName,
                                 CSValidationErrorValidationRuleKey: validationRule,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)mediaDefValidationFailedError:(NSString *)capUrn
                                  argumentName:(NSString *)argumentName
                                      mediaUrn:(NSString *)mediaUrn
                                validationRule:(NSString *)validationRule
                                   actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' argument '%@' failed media def '%@' validation rule '%@' with value: %@",
                            capUrn, argumentName, mediaUrn, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeMediaDefValidationFailed
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName,
                                 CSValidationErrorValidationRuleKey: validationRule,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)invalidOutputTypeError:(NSString *)capUrn
                          expectedType:(NSString *)expectedType
                            actualType:(NSString *)actualType
                           actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' output expects type '%@' but received '%@' with value: %@",
                            capUrn, expectedType, actualType, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidOutputType
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorExpectedTypeKey: expectedType,
                                 CSValidationErrorActualTypeKey: actualType,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)outputValidationFailedError:(NSString *)capUrn
                             validationRule:(NSString *)validationRule
                                actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' output failed validation rule '%@' with value: %@",
                            capUrn, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeOutputValidationFailed
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorValidationRuleKey: validationRule,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)outputMediaDefValidationFailedError:(NSString *)capUrn
                                            mediaUrn:(NSString *)mediaUrn
                                      validationRule:(NSString *)validationRule
                                         actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' output failed media def '%@' validation rule '%@' with value: %@",
                            capUrn, mediaUrn, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeOutputMediaDefValidationFailed
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorValidationRuleKey: validationRule,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)invalidCapSchemaError:(NSString *)capUrn issue:(NSString *)issue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' has invalid schema: %@", capUrn, issue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidCapSchema
                         capUrn:capUrn
                          description:description
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)tooManyArgumentsError:(NSString *)capUrn
                          maxExpected:(NSInteger)maxExpected
                          actualCount:(NSInteger)actualCount {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' expects at most %ld arguments but received %ld",
                            capUrn, (long)maxExpected, (long)actualCount];
    return [[self alloc] initWithType:CSValidationErrorTypeTooManyArguments
                         capUrn:capUrn
                          description:description
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)jsonParseError:(NSString *)capUrn error:(NSString *)error {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' JSON parsing failed: %@", capUrn, error];
    return [[self alloc] initWithType:CSValidationErrorTypeJSONParseError
                         capUrn:capUrn
                          description:description
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)schemaValidationFailedError:(NSString *)capUrn
                               argumentName:(nullable NSString *)argumentName
                           underlyingError:(NSError *)underlyingError {
    NSString *context = argumentName ? [NSString stringWithFormat:@"argument '%@'", argumentName] : @"output";
    NSString *description = [NSString stringWithFormat:@"Cap '%@' %@ failed schema validation: %@",
                            capUrn, context, underlyingError.localizedDescription];

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:description
                                                                       forKey:NSLocalizedDescriptionKey];
    if (argumentName) {
        userInfo[CSValidationErrorArgumentNameKey] = argumentName;
    }
    userInfo[NSUnderlyingErrorKey] = underlyingError;

    return [[self alloc] initWithType:CSValidationErrorTypeSchemaValidationFailed
                         capUrn:capUrn
                          description:description
                             userInfo:userInfo];
}

@end

// Internal helper functions
@interface CSInputValidator ()
+ (NSString *)getJsonTypeName:(id)value;
+ (NSNumber *)getNumericValue:(id)value;
+ (BOOL)validateSingleArgument:(CSCapArg *)argDef
                         value:(id)value
                           cap:(CSCap *)cap
                      registry:(CSFabricRegistry *)registry
                         error:(NSError **)error;
+ (BOOL)validateArgumentType:(CSCapArg *)argDef
                       value:(id)value
                         cap:(CSCap *)cap
                    registry:(CSFabricRegistry *)registry
                       error:(NSError **)error;
+ (BOOL)validateMediaDefRules:(CSCapArg *)argDef
                     mediaDef:(CSMediaDef *)mediaDef
                         value:(id)value
                           cap:(CSCap *)cap
                         error:(NSError **)error;
@end

@implementation CSInputValidator

+ (BOOL)validateArguments:(NSArray *)arguments
               cap:(CSCap *)cap
          registry:(CSFabricRegistry *)registry
             error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    NSArray<CSCapArg *> *requiredArgs = [cap getRequiredArgs];
    NSArray<CSCapArg *> *optionalArgs = [cap getOptionalArgs];

    // Check if too many arguments provided
    NSInteger maxArgs = requiredArgs.count + optionalArgs.count;
    if (arguments.count > maxArgs) {
        if (error) {
            *error = [CSValidationError tooManyArgumentsError:capUrn
                                                  maxExpected:maxArgs
                                                  actualCount:arguments.count];
        }
        return NO;
    }

    // Validate required arguments
    for (NSInteger index = 0; index < requiredArgs.count; index++) {
        if (index >= arguments.count) {
            if (error) {
                CSCapArg *reqArg = requiredArgs[index];
                *error = [CSValidationError missingRequiredArgumentError:capUrn
                                                            argumentName:reqArg.mediaUrn];
            }
            return NO;
        }

        CSCapArg *reqArg = requiredArgs[index];
        if (![self validateSingleArgument:reqArg
                                    value:arguments[index]
                                      cap:cap
                                 registry:registry
                                    error:error]) {
            return NO;
        }
    }

    // Validate optional arguments if provided
    NSInteger requiredCount = requiredArgs.count;
    for (NSInteger index = 0; index < optionalArgs.count; index++) {
        NSInteger argIndex = requiredCount + index;
        if (argIndex < arguments.count) {
            CSCapArg *optArg = optionalArgs[index];
            if (![self validateSingleArgument:optArg
                                    value:arguments[argIndex]
                                      cap:cap
                                 registry:registry
                                    error:error]) {
                return NO;
            }
        }
    }

    return YES;
}

+ (BOOL)validateNamedArguments:(NSArray *)namedArguments
                           cap:(CSCap *)cap
                      registry:(CSFabricRegistry *)registry
                         error:(NSError **)error {
    // For now, delegate to regular validation
    return [self validateArguments:namedArguments cap:cap registry:registry error:error];
}

+ (BOOL)validateSingleArgument:(CSCapArg *)argDef
                         value:(id)value
                           cap:(CSCap *)cap
                      registry:(CSFabricRegistry *)registry
                         error:(NSError **)error {
    // Resolve mediaDef first - needed for type validation and media def validation
    CSMediaDef *mediaDef = nil;
    if (argDef.mediaUrn) {
        NSError *resolveError = nil;
        mediaDef = CSResolveMediaUrn(argDef.mediaUrn, registry, &resolveError);
        if (!mediaDef) {
            // FAIL HARD on unresolvable spec ID
            if (error) {
                NSString *capUrn = [cap urnString];
                *error = [CSValidationError invalidCapSchemaError:capUrn
                                                            issue:[NSString stringWithFormat:@"Cannot resolve spec ID '%@' for argument '%@': %@",
                                                                   argDef.mediaUrn, argDef.mediaUrn, resolveError.localizedDescription]];
            }
            return NO;
        }
    }

    // Type validation
    if (![self validateArgumentType:argDef value:value cap:cap registry:registry error:error]) {
        return NO;
    }

    // Media def validation rules (inherent to the semantic type)
    if (mediaDef && mediaDef.validation) {
        if (![self validateMediaDefRules:argDef mediaDef:mediaDef value:value cap:cap error:error]) {
            return NO;
        }
    }

    // Schema validation
    if (mediaDef && mediaDef.schema) {
        CSJSONSchemaValidator *schemaValidator = [CSJSONSchemaValidator validator];
        NSError *schemaError = nil;

        if (![schemaValidator validateArgument:argDef withValue:value registry:registry error:&schemaError]) {
            if (error) {
                NSString *capUrn = [cap urnString];
                *error = [CSValidationError schemaValidationFailedError:capUrn
                                                           argumentName:argDef.mediaUrn
                                                        underlyingError:schemaError];
            }
            return NO;
        }
    }

    return YES;
}

+ (BOOL)validateArgumentType:(CSCapArg *)argDef
                       value:(id)value
                         cap:(CSCap *)cap
                    registry:(CSFabricRegistry *)registry
                       error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    NSString *actualType = [self getJsonTypeName:value];

    // If no mediaDef, skip type validation
    if (!argDef.mediaUrn) {
        return YES;
    }

    // Resolve mediaDef to determine expected type
    NSError *resolveError = nil;
    CSMediaDef *mediaDef = CSResolveMediaUrn(argDef.mediaUrn, registry, &resolveError);
    if (!mediaDef) {
        // FAIL HARD on unresolvable spec ID
        if (error) {
            *error = [CSValidationError invalidCapSchemaError:capUrn
                                                        issue:[NSString stringWithFormat:@"Cannot resolve spec ID '%@' for argument '%@': %@",
                                                               argDef.mediaUrn, argDef.mediaUrn, resolveError.localizedDescription]];
        }
        return NO;
    }

    // Determine expected type from profile
    NSString *profile = mediaDef.profile;
    BOOL typeMatches = YES;
    NSString *expectedType = argDef.mediaUrn;

    if (profile) {
        if ([profile containsString:@"/schema/str"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSString class]];
            expectedType = @"string";
        } else if ([profile containsString:@"/schema/int"] && ![profile containsString:@"-array"]) {
            if ([value isKindOfClass:[NSNumber class]]) {
                NSNumber *num = (NSNumber *)value;
                typeMatches = !CFNumberIsFloatType((__bridge CFNumberRef)num) &&
                              CFGetTypeID((__bridge CFTypeRef)num) != CFBooleanGetTypeID();
            } else {
                typeMatches = NO;
            }
            expectedType = @"integer";
        } else if ([profile containsString:@"/schema/num"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSNumber class]];
            expectedType = @"number";
        } else if ([profile containsString:@"/schema/bool"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSNumber class]] &&
                          CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
            expectedType = @"boolean";
        } else if ([profile containsString:@"/schema/obj"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSDictionary class]];
            expectedType = @"object";
        } else if ([profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSArray class]];
            expectedType = @"array";
        }
    }

    // Check for binary based on media type (no enc= ⇒ not text-representable)
    if (!CSMediaUrnHasEncoding(mediaDef.mediaUrn)) {
        typeMatches = [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSData class]];
        expectedType = @"binary";
    }

    if (!typeMatches) {
        if (error) {
            *error = [CSValidationError invalidArgumentTypeError:capUrn
                                                    argumentName:argDef.mediaUrn
                                                    expectedType:expectedType
                                                      actualType:actualType
                                                     actualValue:value];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)validateMediaDefRules:(CSCapArg *)argDef
                     mediaDef:(CSMediaDef *)mediaDef
                         value:(id)value
                           cap:(CSCap *)cap
                         error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    CSMediaValidation *validation = mediaDef.validation;
    NSString *mediaUrn = mediaDef.mediaUrn ?: argDef.mediaUrn;

    if (!validation) {
        return YES;
    }

    // Numeric validation
    if (validation.min) {
        NSNumber *numValue = [self getNumericValue:value];
        if (numValue && [numValue doubleValue] < [validation.min doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum value %@", validation.min];
                *error = [CSValidationError mediaDefValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
                                                            validationRule:rule
                                                               actualValue:value];
            }
            return NO;
        }
    }

    if (validation.max) {
        NSNumber *numValue = [self getNumericValue:value];
        if (numValue && [numValue doubleValue] > [validation.max doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"maximum value %@", validation.max];
                *error = [CSValidationError mediaDefValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
                                                            validationRule:rule
                                                               actualValue:value];
            }
            return NO;
        }
    }

    // String length validation
    if (validation.minLength && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (stringValue.length < [validation.minLength integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum length %@", validation.minLength];
                *error = [CSValidationError mediaDefValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
                                                            validationRule:rule
                                                               actualValue:value];
            }
            return NO;
        }
    }

    if (validation.maxLength && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (stringValue.length > [validation.maxLength integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"maximum length %@", validation.maxLength];
                *error = [CSValidationError mediaDefValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
                                                            validationRule:rule
                                                               actualValue:value];
            }
            return NO;
        }
    }

    // Pattern validation
    if (validation.pattern && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        NSError *regexError = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:validation.pattern
                                                                               options:0
                                                                                 error:&regexError];
        if (regex) {
            NSRange range = NSMakeRange(0, stringValue.length);
            NSTextCheckingResult *match = [regex firstMatchInString:stringValue options:0 range:range];
            if (!match) {
                if (error) {
                    NSString *rule = [NSString stringWithFormat:@"pattern '%@'", validation.pattern];
                    *error = [CSValidationError mediaDefValidationFailedError:capUrn
                                                                  argumentName:argDef.mediaUrn
                                                                      mediaUrn:mediaUrn
                                                                validationRule:rule
                                                                   actualValue:value];
                }
                return NO;
            }
        }
    }

    // Allowed values validation
    if (validation.allowedValues.count > 0 && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (![validation.allowedValues containsObject:stringValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"allowed values: %@", validation.allowedValues];
                *error = [CSValidationError mediaDefValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
                                                            validationRule:rule
                                                               actualValue:value];
            }
            return NO;
        }
    }

    return YES;
}

+ (NSString *)getJsonTypeName:(id)value {
    if ([value isKindOfClass:[NSNull class]]) {
        return @"null";
    } else if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)value;
        if (CFGetTypeID((__bridge CFTypeRef)num) == CFBooleanGetTypeID()) {
            return @"boolean";
        } else if (!CFNumberIsFloatType((__bridge CFNumberRef)num)) {
            return @"integer";
        } else {
            return @"number";
        }
    } else if ([value isKindOfClass:[NSString class]]) {
        return @"string";
    } else if ([value isKindOfClass:[NSArray class]]) {
        return @"array";
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        return @"object";
    } else {
        return NSStringFromClass([value class]);
    }
}

+ (NSNumber *)getNumericValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        return (NSNumber *)value;
    }
    return nil;
}

@end

@interface CSOutputValidator ()
+ (BOOL)validateOutputType:(CSCapOutput *)outputDef
                     value:(id)value
                       cap:(CSCap *)cap
                  registry:(CSFabricRegistry *)registry
                     error:(NSError **)error;
+ (BOOL)validateOutputMediaDefRules:(CSCapOutput *)outputDef
                           mediaDef:(CSMediaDef *)mediaDef
                               value:(id)value
                                 cap:(CSCap *)cap
                               error:(NSError **)error;
@end

@implementation CSOutputValidator

+ (BOOL)validateOutput:(id)output
                   cap:(CSCap *)cap
              registry:(CSFabricRegistry *)registry
                 error:(NSError **)error {
    NSString *capUrn = [cap urnString];

    CSCapOutput *outputDef = [cap mainOutput];
    if (!outputDef) {
        // No main output (out=media:void): there is nothing to hold it to
        return YES;
    }

    // Resolve mediaDef first - needed for type validation and media def validation
    CSMediaDef *mediaDef = nil;
    if (outputDef.mediaUrn) {
        NSError *resolveError = nil;
        mediaDef = CSResolveMediaUrn(outputDef.mediaUrn, registry, &resolveError);
        if (!mediaDef) {
            // FAIL HARD on unresolvable spec ID
            if (error) {
                *error = [CSValidationError invalidCapSchemaError:capUrn
                                                            issue:[NSString stringWithFormat:@"Cannot resolve spec ID '%@' for output: %@",
                                                                   outputDef.mediaUrn, resolveError.localizedDescription]];
            }
            return NO;
        }
    }

    // Type validation
    if (![self validateOutputType:outputDef value:output cap:cap registry:registry error:error]) {
        return NO;
    }

    // Media def validation rules (inherent to the semantic type)
    if (mediaDef && mediaDef.validation) {
        if (![self validateOutputMediaDefRules:outputDef mediaDef:mediaDef value:output cap:cap error:error]) {
            return NO;
        }
    }

    // Schema validation
    if (mediaDef && mediaDef.schema) {
        CSJSONSchemaValidator *schemaValidator = [CSJSONSchemaValidator validator];
        NSError *schemaError = nil;

        if (![schemaValidator validateOutput:outputDef withValue:output registry:registry error:&schemaError]) {
            if (error) {
                *error = [CSValidationError schemaValidationFailedError:capUrn
                                                           argumentName:nil
                                                        underlyingError:schemaError];
            }
            return NO;
        }
    }

    return YES;
}

+ (BOOL)validateOutputType:(CSCapOutput *)outputDef
                     value:(id)value
                       cap:(CSCap *)cap
                  registry:(CSFabricRegistry *)registry
                     error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    NSString *actualType = [CSInputValidator getJsonTypeName:value];

    // If no mediaDef, skip type validation
    if (!outputDef.mediaUrn) {
        return YES;
    }

    // Resolve mediaDef to determine expected type
    NSError *resolveError = nil;
    CSMediaDef *mediaDef = CSResolveMediaUrn(outputDef.mediaUrn, registry, &resolveError);
    if (!mediaDef) {
        // FAIL HARD on unresolvable spec ID
        if (error) {
            *error = [CSValidationError invalidCapSchemaError:capUrn
                                                        issue:[NSString stringWithFormat:@"Cannot resolve spec ID '%@' for output: %@",
                                                               outputDef.mediaUrn, resolveError.localizedDescription]];
        }
        return NO;
    }

    // Determine expected type from profile
    NSString *profile = mediaDef.profile;
    BOOL typeMatches = YES;
    NSString *expectedType = outputDef.mediaUrn;

    if (profile) {
        if ([profile containsString:@"/schema/str"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSString class]];
            expectedType = @"string";
        } else if ([profile containsString:@"/schema/int"] && ![profile containsString:@"-array"]) {
            if ([value isKindOfClass:[NSNumber class]]) {
                NSNumber *num = (NSNumber *)value;
                typeMatches = !CFNumberIsFloatType((__bridge CFNumberRef)num) &&
                              CFGetTypeID((__bridge CFTypeRef)num) != CFBooleanGetTypeID();
            } else {
                typeMatches = NO;
            }
            expectedType = @"integer";
        } else if ([profile containsString:@"/schema/num"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSNumber class]];
            expectedType = @"number";
        } else if ([profile containsString:@"/schema/bool"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSNumber class]] &&
                          CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
            expectedType = @"boolean";
        } else if ([profile containsString:@"/schema/obj"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSDictionary class]];
            expectedType = @"object";
        } else if ([profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSArray class]];
            expectedType = @"array";
        }
    }

    // Check for binary based on media type (no enc= ⇒ not text-representable)
    if (!CSMediaUrnHasEncoding(mediaDef.mediaUrn)) {
        typeMatches = [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSData class]];
        expectedType = @"binary";
    }

    if (!typeMatches) {
        if (error) {
            *error = [CSValidationError invalidOutputTypeError:capUrn
                                                  expectedType:expectedType
                                                    actualType:actualType
                                                   actualValue:value];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)validateOutputMediaDefRules:(CSCapOutput *)outputDef
                           mediaDef:(CSMediaDef *)mediaDef
                               value:(id)value
                                 cap:(CSCap *)cap
                               error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    CSMediaValidation *validation = mediaDef.validation;
    NSString *mediaUrn = mediaDef.mediaUrn ?: outputDef.mediaUrn;

    if (!validation) {
        return YES;
    }

    // Numeric validation
    if (validation.min) {
        NSNumber *numValue = [CSInputValidator getNumericValue:value];
        if (numValue && [numValue doubleValue] < [validation.min doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum value %@", validation.min];
                *error = [CSValidationError outputMediaDefValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
                                                                  validationRule:rule
                                                                     actualValue:value];
            }
            return NO;
        }
    }

    if (validation.max) {
        NSNumber *numValue = [CSInputValidator getNumericValue:value];
        if (numValue && [numValue doubleValue] > [validation.max doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"maximum value %@", validation.max];
                *error = [CSValidationError outputMediaDefValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
                                                                  validationRule:rule
                                                                     actualValue:value];
            }
            return NO;
        }
    }

    // String length validation
    if (validation.minLength && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (stringValue.length < [validation.minLength integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum length %@", validation.minLength];
                *error = [CSValidationError outputMediaDefValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
                                                                  validationRule:rule
                                                                     actualValue:value];
            }
            return NO;
        }
    }

    if (validation.maxLength && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (stringValue.length > [validation.maxLength integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"maximum length %@", validation.maxLength];
                *error = [CSValidationError outputMediaDefValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
                                                                  validationRule:rule
                                                                     actualValue:value];
            }
            return NO;
        }
    }

    // Pattern validation
    if (validation.pattern && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        NSError *regexError = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:validation.pattern
                                                                               options:0
                                                                                 error:&regexError];
        if (regex) {
            NSRange range = NSMakeRange(0, stringValue.length);
            NSTextCheckingResult *match = [regex firstMatchInString:stringValue options:0 range:range];
            if (!match) {
                if (error) {
                    NSString *rule = [NSString stringWithFormat:@"pattern '%@'", validation.pattern];
                    *error = [CSValidationError outputMediaDefValidationFailedError:capUrn
                                                                            mediaUrn:mediaUrn
                                                                      validationRule:rule
                                                                         actualValue:value];
                }
                return NO;
            }
        }
    }

    // Allowed values validation
    if (validation.allowedValues.count > 0 && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (![validation.allowedValues containsObject:stringValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"allowed values: %@", validation.allowedValues];
                *error = [CSValidationError outputMediaDefValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
                                                                  validationRule:rule
                                                                     actualValue:value];
            }
            return NO;
        }
    }

    return YES;
}

@end

BOOL CSIsValidDefinitionName(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return NO;
    if ([name isEqualToString:@"true"] || [name isEqualToString:@"false"] || [name isEqualToString:@"null"]) return NO;
    static NSRegularExpression *shape;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shape = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z_][A-Za-z0-9_-]*$" options:0 error:nil];
    });
    return [shape numberOfMatchesInString:name options:0 range:NSMakeRange(0, name.length)] == 1;
}

/// The cli_flags a definition may not take: the ones every cartridge's own
/// command line already means something by.
static NSArray<NSString *> *CSReservedCliFlags(void) {
    return @[@"manifest", @"--help", @"--version", @"-v", @"-h"];
}

static NSString *CSSourceTypeName(CSArgSource *source) {
    switch (source.type) {
        case CSArgSourceTypeStdin: return @"stdin";
        case CSArgSourceTypePosition: return @"position";
        case CSArgSourceTypeCliFlag: return @"cli_flag";
    }
    return @"unknown";
}

@implementation CSCapValidator

+ (BOOL)refuse:(CSCap *)cap issue:(NSString *)issue error:(NSError **)error {
    if (error) *error = [CSValidationError invalidCapSchemaError:[cap urnString] issue:issue];
    return NO;
}

+ (BOOL)validateCapArgs:(CSCap *)cap error:(NSError **)error {
    NSArray<CSCapArg *> *args = cap.args;

    // RULE1: No duplicate media_urns
    NSMutableSet<NSString *> *mediaUrns = [NSMutableSet set];
    for (CSCapArg *arg in args) {
        if ([mediaUrns containsObject:arg.mediaUrn]) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE1: Duplicate media_urn '%@'", arg.mediaUrn] error:error];
        }
        [mediaUrns addObject:arg.mediaUrn];
    }

    // RULE2: sources must not be empty
    for (CSCapArg *arg in args) {
        if (arg.sources.count == 0) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE2: Argument '%@' has empty sources", arg.mediaUrn] error:error];
        }
    }

    NSMutableArray<NSString *> *stdinUrns = [NSMutableArray array];
    NSMutableArray<NSArray *> *positions = [NSMutableArray array];
    NSMutableArray<NSArray *> *cliFlags = [NSMutableArray array];
    for (CSCapArg *arg in args) {
        NSMutableSet<NSString *> *sourceTypes = [NSMutableSet set];
        BOOL hasPosition = NO;
        BOOL hasCliFlag = NO;
        for (CSArgSource *source in arg.sources) {
            NSString *type = CSSourceTypeName(source);
            // RULE4: No arg may specify the same source type more than once
            if ([sourceTypes containsObject:type]) {
                return [self refuse:cap issue:[NSString stringWithFormat:@"RULE4: Argument '%@' has duplicate source type '%@'", arg.mediaUrn, type] error:error];
            }
            [sourceTypes addObject:type];
            if ([source isStdin]) [stdinUrns addObject:source.stdinMediaUrn];
            if ([source isPosition]) {
                hasPosition = YES;
                [positions addObject:@[@(source.position), arg.mediaUrn]];
            }
            if ([source isCliFlag]) {
                hasCliFlag = YES;
                [cliFlags addObject:@[source.cliFlag, arg.mediaUrn]];
                // RULE10: Reserved cli_flags
                if ([CSReservedCliFlags() containsObject:source.cliFlag]) {
                    return [self refuse:cap issue:[NSString stringWithFormat:@"RULE10: Argument '%@' uses reserved cli_flag '%@'", arg.mediaUrn, source.cliFlag] error:error];
                }
            }
        }
        // RULE7: No arg may have both position and cli_flag
        if (hasPosition && hasCliFlag) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE7: Argument '%@' has both position and cli_flag sources", arg.mediaUrn] error:error];
        }
    }

    // RULE3: At most one arg declares a stdin source. `stdin` is a command
    // line's one piped input, and the arg that declares it is the main input.
    NSMutableArray<NSString *> *stdinArgs = [NSMutableArray array];
    for (CSCapArg *arg in args) {
        if ([arg hasStdinSource]) [stdinArgs addObject:arg.mediaUrn];
    }
    if (stdinArgs.count > 1) {
        return [self refuse:cap issue:[NSString stringWithFormat:@"RULE3: Arguments '%@' and '%@' both declare a stdin source; a cap has one main input", stdinArgs[0], stdinArgs[1]] error:error];
    }

    // RULE17: names
    NSMutableArray<CSCapArg *> *named = [NSMutableArray array];
    for (CSCapArg *arg in args) {
        if (arg.name.length == 0) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE17: Argument '%@' has no name", arg.mediaUrn] error:error];
        }
        if (!CSIsValidDefinitionName(arg.name)) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE17: Argument name '%@' is not a valid name", arg.name] error:error];
        }
        for (CSCapArg *seen in named) {
            if ([seen.name isEqualToString:arg.name]) {
                return [self refuse:cap issue:[NSString stringWithFormat:@"RULE17: Arguments '%@' and '%@' share the name '%@'", seen.mediaUrn, arg.mediaUrn, arg.name] error:error];
            }
        }
        [named addObject:arg];
    }

    // RULE18: an arg says what it accepts in one place.
    for (CSCapArg *arg in args) {
        if (arg.accepts != nil && [arg hasStdinSource]) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE18: Argument '%@' declares both a stdin source and accepts", arg.mediaUrn] error:error];
        }
    }

    // RULE15: The main input matches in=. With in=media:void no arg declares
    // a stdin source; otherwise one does, equivalent to in= — compared as
    // tagged URNs, never as strings.
    NSError *inError = nil;
    CSMediaUrn *inMedia = [CSMediaUrn fromString:[cap.capUrn getInSpec] error:&inError];
    if (inMedia == nil) {
        return [self refuse:cap issue:[NSString stringWithFormat:@"RULE15: Failed to parse in= spec: %@", inError.localizedDescription] error:error];
    }
    CSMediaUrn *voidMedia = [CSMediaUrn fromString:CSMediaVoid error:nil];
    BOOL inIsVoid = [inMedia isEquivalentTo:voidMedia];
    if (inIsVoid && stdinUrns.count > 0) {
        return [self refuse:cap issue:[NSString stringWithFormat:@"RULE15: in= is 'media:void' but %lu arg(s) declare a stdin source", (unsigned long)stdinUrns.count] error:error];
    }
    if (!inIsVoid) {
        BOOL found = NO;
        for (NSString *stdinUrn in stdinUrns) {
            CSMediaUrn *parsed = [CSMediaUrn fromString:stdinUrn error:nil];
            if (parsed != nil && [parsed isEquivalentTo:inMedia]) found = YES;
        }
        if (!found) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE15: in= is '%@' but no arg declares a stdin source equivalent to it", [cap.capUrn getInSpec]] error:error];
        }
    }

    // RULE14: Only the main input may stream. `streaming` declares that an
    // argument is consumed without a length promise — a feed. Side arguments
    // are values the runtime demuxes whole; a feed there has no meaning and
    // would let an unbounded stream reach a collector that must refuse it.
    for (CSCapArg *arg in args) {
        if (arg.streaming && ![arg isMainInputForInSpec:inMedia]) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE14: Argument '%@' declares streaming=true but is not the main input (no stdin source equivalent to in='%@') — only the main input may be consumed without a length promise", arg.mediaUrn, [cap.capUrn getInSpec]] error:error];
        }
    }

    // RULE5: No two args may have the same position
    NSMutableSet<NSNumber *> *positionSet = [NSMutableSet set];
    for (NSArray *held in positions) {
        if ([positionSet containsObject:held[0]]) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE5: Duplicate position %@ in argument '%@'", held[0], held[1]] error:error];
        }
        [positionSet addObject:held[0]];
    }

    // RULE6: Positions must be sequential (0-based, no gaps when aggregated)
    NSArray<NSArray *> *sortedPositions = [positions sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        return [a[0] compare:b[0]];
    }];
    for (NSUInteger i = 0; i < sortedPositions.count; i++) {
        if ([sortedPositions[i][0] integerValue] != (NSInteger)i) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE6: Position gap - expected %lu but found %@", (unsigned long)i, sortedPositions[i][0]] error:error];
        }
    }

    // RULE9: No two args may have the same cli_flag
    NSMutableSet<NSString *> *flagSet = [NSMutableSet set];
    for (NSArray *held in cliFlags) {
        if ([flagSet containsObject:held[0]]) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE9: Duplicate cli_flag '%@' in argument '%@'", held[0], held[1]] error:error];
        }
        [flagSet addObject:held[0]];
    }
    return YES;
}

+ (BOOL)validateCapOutputs:(CSCap *)cap error:(NSError **)error {
    NSArray<CSCapOutput *> *outputs = cap.outputs;
    NSError *parseError = nil;
    CSMediaUrn *outMedia = [CSMediaUrn fromString:[cap.capUrn getOutSpec] error:&parseError];
    if (outMedia == nil) {
        return [self refuse:cap issue:[NSString stringWithFormat:@"RULE21: Failed to parse out= spec: %@", parseError.localizedDescription] error:error];
    }
    CSMediaUrn *inMedia = [CSMediaUrn fromString:[cap.capUrn getInSpec] error:&parseError];
    if (inMedia == nil) {
        return [self refuse:cap issue:[NSString stringWithFormat:@"RULE22: Failed to parse in= spec: %@", parseError.localizedDescription] error:error];
    }
    CSMediaUrn *voidMedia = [CSMediaUrn fromString:CSMediaVoid error:nil];
    BOOL outIsVoid = [outMedia isEquivalentTo:voidMedia];
    BOOL inIsVoid = [inMedia isEquivalentTo:voidMedia];

    // RULE19: names
    NSMutableArray<CSCapOutput *> *named = [NSMutableArray array];
    for (CSCapOutput *output in outputs) {
        if (output.name.length == 0) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE19: Output '%@' has no name", output.mediaUrn] error:error];
        }
        if (!CSIsValidDefinitionName(output.name)) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE19: Output name '%@' is not a valid name", output.name] error:error];
        }
        for (CSCapOutput *seen in named) {
            if ([seen.name isEqualToString:output.name]) {
                return [self refuse:cap issue:[NSString stringWithFormat:@"RULE19: Outputs '%@' and '%@' share the name '%@'", seen.mediaUrn, output.mediaUrn, output.name] error:error];
            }
        }
        [named addObject:output];
    }

    // RULE20: identities, compared as media URNs (tag order is not identity)
    NSMutableArray<CSMediaUrn *> *identities = [NSMutableArray array];
    for (CSCapOutput *output in outputs) {
        CSMediaUrn *identity = [CSMediaUrn fromString:output.mediaUrn error:&parseError];
        if (identity == nil) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE20: Output media_urn '%@' is not a media URN: %@", output.mediaUrn, parseError.localizedDescription] error:error];
        }
        for (CSMediaUrn *seen in identities) {
            if ([seen isEquivalentTo:identity]) {
                return [self refuse:cap issue:[NSString stringWithFormat:@"RULE20: Duplicate output media_urn '%@'", output.mediaUrn] error:error];
            }
        }
        [identities addObject:identity];
    }

    // RULE21: the main output
    if (outIsVoid) {
        if (outputs.count > 0) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE21: out= is 'media:void' but %lu output(s) are declared", (unsigned long)outputs.count] error:error];
        }
        return YES;
    }
    NSMutableArray<NSNumber *> *main = [NSMutableArray array];
    for (NSUInteger i = 0; i < identities.count; i++) {
        if ([identities[i] isEquivalentTo:outMedia]) [main addObject:@(i)];
    }
    if (main.count != 1) {
        return [self refuse:cap issue:[NSString stringWithFormat:@"RULE21: out= is '%@' but %lu outputs are equivalent to it; exactly one must be", [cap.capUrn getOutSpec], (unsigned long)main.count] error:error];
    }

    // RULE22: what an output carries
    for (NSUInteger i = 0; i < outputs.count; i++) {
        CSCapOutput *output = outputs[i];
        if (output.carries == nil) continue;
        if (i == [main[0] unsignedIntegerValue]) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE22: The main output '%@' declares carries", output.mediaUrn] error:error];
        }
        if (inIsVoid) {
            return [self refuse:cap issue:[NSString stringWithFormat:@"RULE22: Output '%@' carries the input but the cap takes none", output.mediaUrn] error:error];
        }
    }
    return YES;
}

+ (BOOL)validateCapDefinition:(CSCap *)cap error:(NSError **)error {
    return [self validateCapArgs:cap error:error] && [self validateCapOutputs:cap error:error];
}

@end

@implementation CSSchemaValidator {
    NSMutableDictionary<NSString *, CSCap *> *_caps;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _caps = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)registerCap:(CSCap *)cap {
    NSString *capUrn = [cap urnString];
    _caps[capUrn] = cap;
}

- (nullable CSCap *)getCap:(NSString *)capUrn {
    return _caps[capUrn];
}

- (BOOL)validateInputs:(NSArray *)arguments
                capUrn:(NSString *)capUrn
              registry:(CSFabricRegistry *)registry
                 error:(NSError **)error {
    CSCap *cap = [self getCap:capUrn];
    if (!cap) {
        if (error) {
            *error = [CSValidationError unknownCapError:capUrn];
        }
        return NO;
    }

    return [CSInputValidator validateArguments:arguments cap:cap registry:registry error:error];
}

- (BOOL)validateOutput:(id)output
                capUrn:(NSString *)capUrn
              registry:(CSFabricRegistry *)registry
                 error:(NSError **)error {
    CSCap *cap = [self getCap:capUrn];
    if (!cap) {
        if (error) {
            *error = [CSValidationError unknownCapError:capUrn];
        }
        return NO;
    }

    return [CSOutputValidator validateOutput:output cap:cap registry:registry error:error];
}

- (BOOL)validateBinaryOutput:(NSData *)outputData
                      capUrn:(NSString *)capUrn
                    registry:(CSFabricRegistry *)registry
                       error:(NSError **)error {
    CSCap *cap = [self getCap:capUrn];
    if (!cap) {
        if (error) {
            *error = [CSValidationError unknownCapError:capUrn];
        }
        return NO;
    }

    // For binary outputs, we primarily validate existence and basic constraints
    CSCapOutput *output = [cap mainOutput];
    if (!output) {
        // No main output (out=media:void): there is nothing to hold it to
        return YES;
    }

    // Resolve mediaDef to check if it's binary - fail hard if resolution fails
    if (output.mediaUrn) {
        NSError *resolveError = nil;
        CSMediaDef *mediaDef = CSResolveMediaUrn(output.mediaUrn, registry, &resolveError);

        if (!mediaDef) {
            // FAIL HARD on unresolvable spec ID
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Cannot resolve output spec ID '%@' for cap '%@': %@",
                                   output.mediaUrn, capUrn, resolveError.localizedDescription];
                *error = [NSError errorWithDomain:@"CSCapValidator"
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }

        if (CSMediaUrnHasEncoding(mediaDef.mediaUrn)) {
            if (error) {
                *error = [CSValidationError invalidOutputTypeError:capUrn
                                                      expectedType:output.mediaUrn
                                                        actualType:@"binary"
                                                       actualValue:outputData];
            }
            return NO;
        }

        // Validate binary data size constraints using media def validation if defined
        CSMediaValidation *validation = mediaDef.validation;
        if (validation && validation.min) {
            if (outputData.length < [validation.min integerValue]) {
                if (error) {
                    NSString *rule = [NSString stringWithFormat:@"minimum size %@ bytes", validation.min];
                    *error = [CSValidationError outputMediaDefValidationFailedError:capUrn
                                                                            mediaUrn:mediaDef.mediaUrn
                                                                      validationRule:rule
                                                                         actualValue:@(outputData.length)];
                }
                return NO;
            }
        }

        if (validation && validation.max) {
            if (outputData.length > [validation.max integerValue]) {
                if (error) {
                    NSString *rule = [NSString stringWithFormat:@"maximum size %@ bytes", validation.max];
                    *error = [CSValidationError outputMediaDefValidationFailedError:capUrn
                                                                            mediaUrn:mediaDef.mediaUrn
                                                                      validationRule:rule
                                                                         actualValue:@(outputData.length)];
                }
                return NO;
            }
        }
    }

    return YES;
}

- (BOOL)validateCapSchema:(CSCap *)cap
                           error:(NSError **)error {
    return [CSCapValidator validateCapDefinition:cap error:error];
}

@end

// XV5 (no-inline-media-def-redefinition) was removed when inline
// `cap.media_defs` arrays were dropped from the cap definition. The
// situation it guarded against — a cap embedding a media def that
// conflicts with the registry — is now structurally impossible.
