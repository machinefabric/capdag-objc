//
//  CSPlanBuilder.m
//  CapDAG
//
//  The argument requirements of a strand's steps, addressed by each step's
//  token. Mirrors Rust: src/planner/plan_builder.rs (analyze_path_arguments).
//

#import "CSPlanBuilder.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSMediaUrn.h"
#import "CSPlan.h"
#import "CSCardinality.h"
#import "CSArgumentBinding.h"

NSString * const CSPlannerErrorDomain = @"CSPlannerError";

// MARK: - Supporting Structures Implementation

@implementation CSReachableTargetInfo
@end

NSErrorDomain const CSStepTokenErrorDomain = @"com.machinefabric.capdag.StepToken";

@implementation CSStepToken {
    NSString *_raw;
}

- (instancetype)initWithRaw:(NSString *)raw {
    self = [super init];
    if (self) {
        _raw = [raw copy];
    }
    return self;
}

+ (instancetype)mint {
    return [[CSStepToken alloc] initWithRaw:[[NSUUID UUID] UUIDString]];
}

+ (nullable instancetype)parse:(NSString *)raw error:(NSError **)error {
    if (raw.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSStepTokenErrorDomain
                                         code:CSStepTokenErrorCodeEmpty
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"a strand step token_id is empty; a step "
                                                    @"without a token came from no plan and "
                                                    @"cannot be addressed"}];
        }
        return nil;
    }
    return [[CSStepToken alloc] initWithRaw:raw];
}

- (NSString *)string {
    return _raw;
}

- (id)copyWithZone:(NSZone *)zone {
    // Immutable — a token has no mutable state to copy away from.
    return self;
}

- (BOOL)isEqual:(id)other {
    if (self == other) {
        return YES;
    }
    if (![other isKindOfClass:[CSStepToken class]]) {
        return NO;
    }
    return [_raw isEqualToString:((CSStepToken *)other).string];
}

- (NSUInteger)hash {
    return _raw.hash;
}

- (NSString *)description {
    return _raw;
}

@end

@implementation CSStrandStep

- (instancetype)init {
    self = [super init];
    if (self) {
        // Every step is born with an identity. There is no window in which a
        // step exists but cannot be addressed.
        _tokenId = [CSStepToken mint];
    }
    return self;
}

- (NSString *)title {
    switch (self.stepType) {
        case CSStrandStepTypeCap:
            return self.capUrn ?: @"(unknown cap)";
        case CSStrandStepTypeForEach:
            return @"ForEach (iterate over list)";
        case CSStrandStepTypeCollect:
            return @"Collect (scalar to list)";
    }
}

- (BOOL)isCap {
    return self.stepType == CSStrandStepTypeCap;
}

@end

@implementation CSStrand
@end

@implementation CSArgumentInfo
@end

@implementation CSStepArgumentRequirements
@end

@implementation CSPathArgumentRequirements
@end

// MARK: - CSMachinePlanBuilder Implementation

@interface CSMachinePlanBuilder ()
@property (nonatomic, strong) id<CSFabricRegistryProtocol> fabricRegistry;
@end

@implementation CSMachinePlanBuilder

- (instancetype)initWithFabricRegistry:(id<CSFabricRegistryProtocol>)fabricRegistry {
    self = [super init];
    if (self) {
        _fabricRegistry = fabricRegistry;
    }
    return self;
}

// MARK: - Analyze Path Arguments

- (void)analyzePathArgumentsForStrand:(CSStrand *)strand
                           completion:(void (^)(CSPathArgumentRequirements * _Nullable requirements, NSError * _Nullable error))completion {

    [self.fabricRegistry getCachedCaps:^(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error) {
        if (error) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                code:CSPlannerErrorCodeFabricRegistryError
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to get caps: %@", error.localizedDescription]}]);
            return;
        }

        NSMutableArray<CSStepArgumentRequirements *> *stepRequirements = [NSMutableArray array];
        NSMutableArray<CSArgumentInfo *> *allSlots = [NSMutableArray array];

        // Track the cap-step ordinal for first-cap detection only: whether an
        // input arg is fed from the run's input file or from the previous cap's
        // output is a question about POSITION IN THE CHAIN, not about identity.
        // Nothing addressable is derived from it.
        NSUInteger capStepIndex = 0;

        for (CSStrandStep *step in strand.steps) {
            // Only cap steps have arguments — cardinality transitions are shape
            // changes with nothing to configure.
            if (![step isCap]) {
                continue;
            }
            NSString *capUrn = step.capUrn;
            NSUInteger stepIndex = capStepIndex;

            CSCap *cap = nil;
            for (CSCap *c in caps) {
                if ([[[c capUrn] toString] isEqualToString:capUrn]) {
                    cap = c;
                    break;
                }
            }

            if (!cap) {
                completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                    code:CSPlannerErrorCodeNotFound
                                                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cap '%@' not found in registry", capUrn]}]);
                return;
            }

            NSString *inSpec = [[cap capUrn] inSpec];
            NSString *outSpec = [[cap capUrn] outSpec];

            NSMutableArray<CSArgumentInfo *> *arguments = [NSMutableArray array];
            NSMutableArray<CSArgumentInfo *> *slots = [NSMutableArray array];

            for (CSCapArg *arg in cap.args) {
                // Determine resolution
                BOOL isInputArg = [arg.mediaUrn isEqualToString:inSpec];
                BOOL isOutputArg = [arg.mediaUrn isEqualToString:outSpec];
                BOOL isFilePathType = NO;

                NSError *parseError = nil;
                CSMediaUrn *urn = [CSMediaUrn fromString:arg.mediaUrn error:&parseError];
                if (urn) {
                    isFilePathType = [urn isFilePath];
                }

                NSString *resolution;
                if (isInputArg) {
                    resolution = (stepIndex == 0) ? @"from_input_file" : @"from_previous_output";
                } else if (isOutputArg) {
                    resolution = @"from_previous_output";
                } else if (isFilePathType) {
                    resolution = (stepIndex == 0) ? @"from_input_file" : @"from_previous_output";
                } else if (arg.defaultValue) {
                    resolution = @"has_default";
                } else {
                    resolution = @"requires_user_input";
                }

                CSArgumentInfo *argInfo = [[CSArgumentInfo alloc] init];
                argInfo.name = arg.mediaUrn;
                argInfo.mediaUrn = arg.mediaUrn;
                argInfo.isRequired = arg.required;
                argInfo.defaultValue = arg.defaultValue;
                argInfo.schema = nil; // Would need MediaValidation conversion

                BOOL isIOArg = [resolution isEqualToString:@"from_input_file"] || [resolution isEqualToString:@"from_previous_output"];

                if (!isIOArg) {
                    [slots addObject:argInfo];
                    [allSlots addObject:argInfo];
                }
                [arguments addObject:argInfo];
            }

            CSStepArgumentRequirements *stepReq = [[CSStepArgumentRequirements alloc] init];
            stepReq.capUrn = capUrn;
            stepReq.tokenId = step.tokenId;
            stepReq.arguments = arguments;
            [stepRequirements addObject:stepReq];
            capStepIndex++;
        }

        CSPathArgumentRequirements *requirements = [[CSPathArgumentRequirements alloc] init];
        requirements.steps = stepRequirements;
        requirements.allSlots = allSlots;

        completion(requirements, nil);
    }];
}

@end
