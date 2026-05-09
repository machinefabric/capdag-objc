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
    CSValidationErrorTypeMediaSpecValidationFailed,
    CSValidationErrorTypeInvalidOutputType,
    CSValidationErrorTypeOutputValidationFailed,
    CSValidationErrorTypeOutputMediaSpecValidationFailed,
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
+ (instancetype)mediaSpecValidationFailedError:(NSString *)capUrn
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
+ (instancetype)outputMediaSpecValidationFailedError:(NSString *)capUrn
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
@interface CSCapValidator : NSObject

/// Validate a cap definition itself
+ (BOOL)validateCap:(CSCap * _Nonnull)cap
              error:(NSError * _Nullable * _Nullable)error;

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