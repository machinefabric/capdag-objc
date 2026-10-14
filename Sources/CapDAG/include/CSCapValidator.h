//
//  CSCapValidator.h
//  Cap schema validation for cartridge interactions
//
//  This provides strict validation of inputs and outputs against
//  advertised cap schemas from cartridges.
//

#import <Foundation/Foundation.h>
#import "CSCap.h"

NS_ASSUME_NONNULL_BEGIN

/// Error domain for validation errors
FOUNDATION_EXPORT NSErrorDomain const CSValidationErrorDomain;

/// Validation error types
typedef NS_ENUM(NSInteger, CSValidationErrorType) {
    CSValidationErrorTypeUnknownCap,
    CSValidationErrorTypeMissingRequiredArgument,
    CSValidationErrorTypeUnknownArgument,
    CSValidationErrorTypeInvalidArgumentType,
    CSValidationErrorTypeMediaValidationFailed,
    CSValidationErrorTypeMediaDefValidationFailed,
    CSValidationErrorTypeInvalidOutputType,
    CSValidationErrorTypeOutputValidationFailed,
    CSValidationErrorTypeOutputMediaDefValidationFailed,
    CSValidationErrorTypeInvalidCapSchema,
    CSValidationErrorTypeTooManyArguments,
    CSValidationErrorTypeJSONParseError,
    CSValidationErrorTypeSchemaValidationFailed,
};

/// Validation error information
@interface CSValidationError : NSError

@property (nonatomic, readonly) CSValidationErrorType validationType;
@property (nonatomic, readonly, copy) NSString *capUrn;
@property (nonatomic, readonly, copy, nullable) NSString *argumentName;
@property (nonatomic, readonly, copy, nullable) NSString *validationRule;
@property (nonatomic, readonly, strong, nullable) id actualValue;
@property (nonatomic, readonly, copy, nullable) NSString *actualType;
@property (nonatomic, readonly, copy, nullable) NSString *expectedType;

+ (instancetype)unknownCapError:(NSString *)capUrn;
+ (instancetype)missingRequiredArgumentError:(NSString *)capUrn argumentName:(NSString *)argumentName;
+ (instancetype)unknownArgumentError:(NSString *)capUrn argumentName:(NSString *)argumentName;
+ (instancetype)invalidArgumentTypeError:(NSString *)capUrn
                            argumentName:(NSString *)argumentName
                            expectedType:(NSString *)expectedType
                              actualType:(NSString *)actualType
                             actualValue:(id)actualValue;
+ (instancetype)mediaValidationFailedError:(NSString *)capUrn
                                 argumentName:(NSString *)argumentName
                               validationRule:(NSString *)validationRule
                                  actualValue:(id)actualValue;
+ (instancetype)mediaDefValidationFailedError:(NSString *)capUrn
                                  argumentName:(NSString *)argumentName
                                      mediaUrn:(NSString *)mediaUrn
                                validationRule:(NSString *)validationRule
                                   actualValue:(id)actualValue;
+ (instancetype)invalidOutputTypeError:(NSString *)capUrn
                          expectedType:(NSString *)expectedType
                            actualType:(NSString *)actualType
                           actualValue:(id)actualValue;
+ (instancetype)outputValidationFailedError:(NSString *)capUrn
                             validationRule:(NSString *)validationRule
                                actualValue:(id)actualValue;
+ (instancetype)outputMediaDefValidationFailedError:(NSString *)capUrn
                                            mediaUrn:(NSString *)mediaUrn
                                      validationRule:(NSString *)validationRule
                                         actualValue:(id)actualValue;
+ (instancetype)invalidCapSchemaError:(NSString *)capUrn issue:(NSString *)issue;
+ (instancetype)tooManyArgumentsError:(NSString *)capUrn 
                          maxExpected:(NSInteger)maxExpected 
                          actualCount:(NSInteger)actualCount;
+ (instancetype)jsonParseError:(NSString *)capUrn error:(NSString *)error;
+ (instancetype)schemaValidationFailedError:(NSString *)capUrn
                               argumentName:(nullable NSString *)argumentName
                           underlyingError:(NSError *)underlyingError;

@end

@class CSFabricRegistry;

/// Input argument validator
@interface CSInputValidator : NSObject

/// Validate positional arguments against cap input schema, resolving
/// referenced media URNs through the unified `CSFabricRegistry`.
+ (BOOL)validateArguments:(NSArray * _Nonnull)arguments
                      cap:(CSCap * _Nonnull)cap
                 registry:(CSFabricRegistry * _Nonnull)registry
                    error:(NSError * _Nullable * _Nullable)error;

/// Validate named arguments against cap input schema, resolving through
/// the unified `CSFabricRegistry`.
+ (BOOL)validateNamedArguments:(NSArray * _Nonnull)namedArguments
                           cap:(CSCap * _Nonnull)cap
                      registry:(CSFabricRegistry * _Nonnull)registry
                         error:(NSError * _Nullable * _Nullable)error;

@end

/// Output validator
@interface CSOutputValidator : NSObject

/// Validate output against cap output schema, resolving through the
/// unified `CSFabricRegistry`.
+ (BOOL)validateOutput:(id _Nonnull)output
                   cap:(CSCap * _Nonnull)cap
              registry:(CSFabricRegistry * _Nonnull)registry
                 error:(NSError * _Nullable * _Nullable)error;

@end

/// Cap schema validator
/**
 * Whether a text is a well-formed name for an argument or an output: it
 * starts with a letter or an underscore, continues with letters, digits,
 * underscores and hyphens, and is not one of the words notation reads as
 * constants (true, false, null).
 */
FOUNDATION_EXPORT BOOL CSIsValidDefinitionName(NSString * _Nullable name);

/**
 * The definition rules a cap is held to wherever it crosses from one program
 * to another, under the numbers every capdag implementation raises them
 * under: a number names one rule.
 */
@interface CSCapValidator : NSObject

/**
 * The rules on a cap's arguments: RULE1 no duplicate media URNs, RULE2
 * sources not empty, RULE3 at most one stdin source, RULE4 no source type
 * twice, RULE5 no position twice, RULE6 positions sequential, RULE7 not
 * both position and cli_flag, RULE9 no cli_flag twice, RULE10 no reserved
 * cli_flag, RULE14 only the main input streams, RULE15 the stdin argument's
 * URN is in=, RULE17 names well-formed and unique, RULE18 accepts never beside
 * a stdin source.
 */
+ (BOOL)validateCapArgs:(CSCap * _Nonnull)cap error:(NSError * _Nullable * _Nullable)error;

/**
 * The rules on a cap's outputs: RULE19 names well-formed and unique, RULE20
 * no duplicate media URNs, RULE21 exactly one main output, the cap's out=
 * (none when out= is media:void), RULE22 only a non-main output of a cap
 * that takes an input carries it.
 */
+ (BOOL)validateCapOutputs:(CSCap * _Nonnull)cap error:(NSError * _Nullable * _Nullable)error;

/** Every definition rule: the arguments', then the outputs'. */
+ (BOOL)validateCapDefinition:(CSCap * _Nonnull)cap error:(NSError * _Nullable * _Nullable)error;

@end

/// Main validation coordinator that orchestrates input and output validation
@interface CSSchemaValidator : NSObject

/// Register a cap schema for validation
- (void)registerCap:(CSCap * _Nonnull)cap;

/// Get a cap by ID
- (nullable CSCap *)getCap:(NSString * _Nonnull)capUrn;

/// Validate arguments against a cap's input schema, resolving
/// referenced media URNs through the unified `CSFabricRegistry`.
- (BOOL)validateInputs:(NSArray * _Nonnull)arguments
                capUrn:(NSString * _Nonnull)capUrn
              registry:(CSFabricRegistry * _Nonnull)registry
                 error:(NSError * _Nullable * _Nullable)error;

/// Validate output against a cap's output schema, resolving through
/// the unified `CSFabricRegistry`.
- (BOOL)validateOutput:(id _Nonnull)output
                capUrn:(NSString * _Nonnull)capUrn
              registry:(CSFabricRegistry * _Nonnull)registry
                 error:(NSError * _Nullable * _Nullable)error;

/// Validate binary output against a cap's output schema, resolving
/// through the unified `CSFabricRegistry`.
- (BOOL)validateBinaryOutput:(NSData * _Nonnull)outputData
                      capUrn:(NSString * _Nonnull)capUrn
                    registry:(CSFabricRegistry * _Nonnull)registry
                       error:(NSError * _Nullable * _Nullable)error;

/// Validate a cap definition itself
- (BOOL)validateCapSchema:(CSCap * _Nonnull)cap
                    error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END