//
//  CSPlanBuilder.h
//  CapDAG
//
//  Cap Plan Builder
//  Mirrors Rust: src/planner/plan_builder.rs
//

#import <Foundation/Foundation.h>
#import "CSCardinality.h"
#import "CSFabricRegistry.h"

@class CSCap;
@class CSMachinePlan;
@class CSCapInputFile;
@class CSCardinalityChainAnalysis;

NS_ASSUME_NONNULL_BEGIN

// MARK: - Error Domain

extern NSString * const CSPlannerErrorDomain;

typedef NS_ENUM(NSInteger, CSPlannerErrorCode) {
    CSPlannerErrorCodeInvalidInput = 1,
    CSPlannerErrorCodeNotFound,
    CSPlannerErrorCodeInternal,
    CSPlannerErrorCodeFabricRegistryError
};

// MARK: - Registry Protocol

/// Protocol for the unified fabric registry. The merged registry
/// holds both cap definitions and media defs in one cache; the
/// plan builder consumes both surfaces here.

// MARK: - Step Type Enum

/// Type of step in a capability chain path
/// Mirrors Rust: StrandStepType
typedef NS_ENUM(NSInteger, CSStrandStepType) {
    /// A real capability step
    CSStrandStepTypeCap,
    /// Fan-out: iterate over list items
    CSStrandStepTypeForEach,
    /// Collect: scalar → list (standalone or after ForEach)
    CSStrandStepTypeCollect,
};

// MARK: - Supporting Structures

/// Information about a reachable target with metadata
@interface CSReachableTargetInfo : NSObject
@property (nonatomic, copy) NSString *mediaUrn;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) NSUInteger minDepth;
@property (nonatomic, assign) NSUInteger maxDepth;
@property (nonatomic, assign) NSInteger pathCount;
@end

/// Domain for `CSStepToken` failures.
extern NSErrorDomain const CSStepTokenErrorDomain;

/// The only way a `CSStepToken` can fail to exist.
typedef NS_ERROR_ENUM(CSStepTokenErrorDomain, CSStepTokenErrorCode) {
    /// The id was empty. A step without a token came from no plan and cannot be
    /// addressed.
    CSStepTokenErrorCodeEmpty = 1,
};

/// The stable identity of one step of a resolved strand — the ONLY address by
/// which a step, or an argument value destined for it, is ever named.
///
/// The raw text is private so that an unidentified step is not a state the
/// program can be in: there is exactly one way to make a token (`+mint`) and
/// exactly one way to recover one that was already minted (`+parse:error:`,
/// which refuses an empty id). Decoding goes through `+parse:error:`, so a
/// persisted strand carrying `""` fails to load rather than loading into a
/// strand whose steps cannot be addressed.
///
/// Nothing derives a token. Not from a position — a strand is a DAG, and
/// parallel branches merging downstream have no ordinal, so two identical caps
/// on separate branches differ only by token. Not from notation — a plan holds
/// strictly more than the notation it was planned from, and reducing one back to
/// the other discards exactly the identities this type exists to carry. A token
/// comes from the plan that minted it or it does not exist.
///
/// Mirrors Rust: pub struct StepToken(String)
@interface CSStepToken : NSObject <NSCopying>

/// Mint a fresh identity. This is how every step in production is born.
+ (instancetype)mint;

/// Recover an already-minted token — from decoding, from a protocol message,
/// from a persisted run. An empty id is not a token: it names no step, so a
/// value bound to it could never be delivered.
+ (nullable instancetype)parse:(NSString *)raw error:(NSError **)error;

/// The token's text, for protocol encoding and diagnostics.
@property (nonatomic, copy, readonly) NSString *string;

/// Unavailable: a token is minted or parsed, never default-constructed.
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

/// Information about a step in a machine
/// Mirrors Rust: StrandStep
@interface CSStrandStep : NSObject
/// Stable per-step identity, minted once when the step is created (the very
/// source of a resolved strand). It is the single key that ties this element of
/// the realized graph to every live update the run emits for it — so a repeated
/// cap URN in one strand is never ambiguous. Alias-free and
/// notation-independent; it travels verbatim through serialization, the run's
/// persisted resolved strand, the render payload, and every progress message.
@property (nonatomic, copy) CSStepToken *tokenId;
/// Cap URN string (for Cap steps; nil for cardinality transitions)
@property (nonatomic, copy, nullable) NSString *capUrn;
@property (nonatomic, copy, nullable) NSString *preferredCap;
@property (nonatomic, strong, nullable) NSDictionary *metadata;
/// Step type (Cap, ForEach, Collect)
@property (nonatomic, assign) CSStrandStepType stepType;
/// Input media def for this step
@property (nonatomic, copy, nullable) NSString *fromSpec;
/// Output media def for this step
@property (nonatomic, copy, nullable) NSString *toSpec;
/// For ForEach/Collect: the media URN (same for both from and to — shape transition, not type)
@property (nonatomic, copy, nullable) NSString *mediaUrn;
/// Specificity score (0 for cardinality transitions)
@property (nonatomic, assign) NSUInteger specificity;
/// Whether the cap's main input expects a sequence (Cap steps; NO for cardinality transitions).
/// Mirrors Rust: StrandStepType::Cap { input_is_sequence }
@property (nonatomic, assign) BOOL inputIsSequence;
/// Whether the cap's output produces a sequence (Cap steps; NO for cardinality transitions).
/// Mirrors Rust: StrandStepType::Cap { output_is_sequence }
@property (nonatomic, assign) BOOL outputIsSequence;
/// Human-readable title for this step
- (NSString *)title;
/// Whether this is a real cap step
- (BOOL)isCap;
@end

/// Information about a machine path
/// Mirrors Rust: Strand
@interface CSStrand : NSObject
@property (nonatomic, copy) NSString *sourceMediaUrn;
@property (nonatomic, copy) NSString *targetMediaUrn;
@property (nonatomic, strong) NSArray<CSStrandStep *> *steps;
/// Total steps including cardinality transitions
@property (nonatomic, assign) NSInteger totalSteps;
/// Only real cap steps (for sorting)
@property (nonatomic, assign) NSInteger capStepCount;
/// Human-readable "A -> B -> C" description
@property (nonatomic, copy, nullable) NSString *pathDescription;
@end

/// Information about an argument
@interface CSArgumentInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *mediaUrn;
@property (nonatomic, assign) BOOL isRequired;
@property (nonatomic, strong, nullable) id defaultValue;
@property (nonatomic, strong, nullable) NSDictionary *schema;
@end

/// Argument requirements for a step
@interface CSStepArgumentRequirements : NSObject
@property (nonatomic, copy) NSString *capUrn;
/// The planner-minted `CSStrandStep.tokenId` of the step these requirements
/// describe — the ONLY address an argument value is ever bound to. A caller
/// renders a form from this and binds the values it collects straight back under
/// this token: no lookup, no strand to consult, and therefore no way for a value
/// to end up addressed to a different plan's step.
@property (nonatomic, copy) CSStepToken *tokenId;
@property (nonatomic, strong) NSArray<CSArgumentInfo *> *arguments;
@end

/// Argument requirements for a path
@interface CSPathArgumentRequirements : NSObject
@property (nonatomic, strong) NSArray<CSStepArgumentRequirements *> *steps;
@property (nonatomic, strong) NSArray<CSArgumentInfo *> *allSlots;
@end

// MARK: - MachinePlanBuilder

/// Builder for creating cap execution plans
@interface CSMachinePlanBuilder : NSObject

/// Create a new plan builder backed by the unified `CSFabricRegistry`.
- (instancetype)initWithFabricRegistry:(id<CSFabricRegistryProtocol>)fabricRegistry;

/// Set the filter for available cap URNs
- (instancetype)withAvailableCaps:(NSSet<NSString *> *)availableCaps;

/// Find a path through the capfab from source to target media type
- (void)findPathFromSource:(NSString *)sourceMedia
                  toTarget:(NSString *)targetMedia
                completion:(void (^)(NSArray<NSString *> * _Nullable capUrns, NSError * _Nullable error))completion;

/// Build an execution plan for transforming from source to target media type
- (void)buildPlanFromSource:(NSString *)sourceMedia
                   toTarget:(NSString *)targetMedia
                 inputFiles:(NSArray<CSCapInputFile *> *)inputFiles
                 completion:(void (^)(CSMachinePlan * _Nullable plan, NSError * _Nullable error))completion;

/// Analyze what transformations would be needed for a path
- (void)analyzePathCardinalityFromSource:(NSString *)sourceMedia
                                toTarget:(NSString *)targetMedia
                              completion:(void (^)(CSCardinalityChainAnalysis * _Nullable analysis, NSError * _Nullable error))completion;

/// Build a plan from a pre-defined path
- (void)buildPlanFromPath:(CSStrand *)path
                     name:(NSString *)name
        inputCardinality:(CSInputCardinality)cardinality
              completion:(void (^)(CSMachinePlan * _Nullable plan, NSError * _Nullable error))completion;

/// Get all possible target media defs from a given source
- (void)getReachableTargetsFromSource:(NSString *)sourceMedia
                           completion:(void (^)(NSArray<NSString *> * _Nullable targets, NSError * _Nullable error))completion;

/// Get all reachable targets with additional metadata
- (void)getReachableTargetsWithMetadataFromSource:(NSString *)sourceMedia
                                         maxDepth:(NSUInteger)maxDepth
                                       completion:(void (^)(NSArray<CSReachableTargetInfo *> * _Nullable targets, NSError * _Nullable error))completion;

/// Find all paths (up to max depth) from source to target
- (void)findAllPathsFromSource:(NSString *)sourceMedia
                      toTarget:(NSString *)targetMedia
                      maxDepth:(NSUInteger)maxDepth
                    completion:(void (^)(NSArray<NSArray<NSString *> *> * _Nullable paths, NSError * _Nullable error))completion;

/// Analyze argument requirements for a path
/// Analyze argument requirements for a strand.
///
/// Takes the resolved `CSStrand` — not a list of cap URNs — because the
/// requirements it produces are addressed by each step's `tokenId`, and only a
/// plan carries those. Mirrors Rust: `MachinePlanBuilder::analyze_path_arguments`.
- (void)analyzePathArgumentsForStrand:(CSStrand *)strand
                           completion:(void (^)(CSPathArgumentRequirements * _Nullable requirements, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
