//
//  CSPlanBuilder.m
//  CapDAG
//
//  The planner's path types: a strand, its steps and their tokens.
//  Mirrors Rust: src/planner/live_cap_fab.rs. What a plan's steps are given is
//  analyzed over plans, which only the reference builds.
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
