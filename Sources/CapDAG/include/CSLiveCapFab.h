//
//  CSLiveCapFab.h
//  CapDAG
//
//  Precomputed capability graph for path finding.
//  Mirrors Rust: src/planner/live_cap_fab.rs
//
//  Design:
//  1. Store MediaUrn/CapUrn directly (not strings) — avoids reparsing.
//  2. Exact matching for targets (isEquivalentTo:), satisfies: for traversal.
//     A node that may have several shapes (`…;fmt=json;?list;?record`) ends on
//     the bookends its shapes are, read complete (-[CSMediaUrn endsOn:]), and a
//     route reaching it reaches each of them.
//  3. Deterministic ordering: (cap_step_count, specificity desc, urn lex).
//

#import <Foundation/Foundation.h>
#import "CSCardinality.h"
#import "CSPlanBuilder.h"

@class CSCap;
@class CSMediaUrn;
@class CSCapUrn;

NS_ASSUME_NONNULL_BEGIN

// MARK: - Edge Type

/// Type of edge in the live capability graph
typedef NS_ENUM(NSInteger, CSLiveMachinePlanEdgeType) {
    /// A real capability that transforms media
    CSLiveMachinePlanEdgeTypeCap,
    /// Fan-out: splits a list into individual items
    CSLiveMachinePlanEdgeTypeForEach,
    /// Collect: scalar → list (standalone or after ForEach)
    CSLiveMachinePlanEdgeTypeCollect,
};

// MARK: - LiveMachinePlanEdge

/// An edge in the live capability graph.
/// Represents either a real capability or a cardinality transition.
@interface CSLiveMachinePlanEdge : NSObject

/// Input media type (what this edge consumes)
@property (nonatomic, strong, readonly) CSMediaUrn *fromSpec;
/// Output media type (what this edge produces)
@property (nonatomic, strong, readonly) CSMediaUrn *toSpec;
/// Type of edge
@property (nonatomic, assign, readonly) CSLiveMachinePlanEdgeType edgeType;
/// Whether the cap's main input expects a sequence
@property (nonatomic, assign, readonly) BOOL inputIsSequence;
/// Whether the output this edge reaches produces a sequence
@property (nonatomic, assign, readonly) BOOL outputIsSequence;
/// The output this edge reaches, when it is not the cap's main one: that
/// output's media URN, its identity in the definition. nil: the main output.
@property (nonatomic, strong, readonly, nullable) CSMediaUrn *outputUrn;

/// Cap URN (for Cap edges only; nil for cardinality transitions)
@property (nonatomic, strong, readonly, nullable) CSCapUrn *capUrn;
/// Cap title (for Cap edges only)
@property (nonatomic, copy, readonly, nullable) NSString *capTitle;
/// Specificity score (0 for cardinality transitions)
@property (nonatomic, assign, readonly) NSUInteger specificity;

/// Human-readable title
- (NSString *)title;

/// Whether this is a real cap edge (not a cardinality transition)
- (BOOL)isCap;

/// Create a cap edge
+ (instancetype)capEdgeFrom:(CSMediaUrn *)from
                         to:(CSMediaUrn *)to
                     capUrn:(CSCapUrn *)capUrn
                      title:(NSString *)title
                specificity:(NSUInteger)specificity
            inputIsSequence:(BOOL)inputIsSeq
           outputIsSequence:(BOOL)outputIsSeq
                  outputUrn:(nullable CSMediaUrn *)outputUrn;

/// Create a ForEach edge (list -> item)
+ (instancetype)forEachEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to;

/// Create a Collect edge (item -> list)
+ (instancetype)collectEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to;

@end

// MARK: - LiveCapFab

/// Precomputed capability graph for path finding and reachability queries.
/// Maintains a persistent graph structure updated when capabilities change.
@interface CSLiveCapFab : NSObject

/// Create a new empty graph
+ (instancetype)graph;

/// Clear the graph completely
- (void)clear;

/// Whether `urn` is a node that ends on bookends: every shape it may have is a
/// file type, so whatever a route reaching it gives can sit on disk as a file.
///
/// Strand bookends (transmute source or target) MUST end on bookends. Internal
/// URNs that appear as cap inputs/outputs but do not name a concrete file
/// format (wildcards like `media:enc=utf8`, primitives like
/// `media:integer;numeric`, role markers like `media:enc=utf8;page`) are
/// tracked as nodes for path finding but end on no bookend and never appear as
/// transmute sources/targets.
/// Mirrors Rust: LiveCapFab::is_bookend
- (BOOL)isBookend:(CSMediaUrn *)urn;

/// The bookends `node` ends on, one for each shape it may have, in structural
/// order; empty when it ends on none.
/// Mirrors Rust: LiveCapFab::ends_on
- (NSArray<CSMediaUrn *> *)endsOn:(CSMediaUrn *)node;

/// Rebuild from a list of capabilities (replaces current contents).
/// Cardinality transitions (ForEach/Collect) are synthesized during traversal.
///
/// `bookendUrns` is the live snapshot of media URNs whose stored definition
/// lists at least one file extension (-[CSFabricRegistry bookendUrns:]), in
/// any order. Each node of the graph is marked with the bookends among them it
/// ends on, once per sync; lookups during traversal are dictionary hits with
/// no registry calls.
/// Mirrors Rust: LiveCapFab::sync_from_caps
- (void)syncFromCaps:(NSArray<CSCap *> *)caps bookendUrns:(NSArray<CSMediaUrn *> *)bookendUrns;

/// Recompute which nodes end on bookends, and on which, from the supplied
/// registry snapshot (as syncFromCaps:bookendUrns: takes it). For callers that
/// build the graph with addCap: and set its bookends apart from a full sync.
/// Mirrors Rust: LiveCapFab::set_bookends
- (void)setBookends:(NSArray<CSMediaUrn *> *)bookendUrns;

/// Rebuild from cap URN strings using the registry.
/// Looks up Cap definitions from the registry; skips identity caps. Each node
/// is then marked with the bookends among `bookendUrns` it ends on, as
/// syncFromCaps:bookendUrns: does.
- (void)syncFromCapUrns:(NSArray<NSString *> *)capUrns
               registry:(id<CSFabricRegistryProtocol>)registry
            bookendUrns:(NSArray<CSMediaUrn *> *)bookendUrns
             completion:(void (^)(void))completion;

/// The graph of the whole fabric: every cap the registry's pinned manifest
/// names (-[CSFabricRegistry getManifestCaps:]), each node marked with the
/// bookends it ends on: for each shape it may have, the media definition the
/// manifest publishes for that shape, read complete, when that definition is a
/// bookend (CSStoredMediaDefIsBookend).
///
/// Nothing comes from what the cache happens to hold: the caps not cached are
/// fetched, and so is every definition a node's shape is. A cap or a
/// definition that cannot be had completes with the error naming it, never a
/// graph with a part of the fabric missing.
/// Mirrors Rust: LiveCapFab::from_fabric
+ (void)fromFabric:(CSFabricRegistry *)registry
        completion:(void (^)(CSLiveCapFab *_Nullable fab, NSError *_Nullable error))completion;

/// Add a single capability as an edge. Skips empty specs and identity caps.
- (void)addCap:(CSCap *)cap;

/// Number of unique media URN nodes
- (NSUInteger)nodeCount;

/// Number of edges (cap + cardinality transitions)
- (NSUInteger)edgeCount;

/// BFS: find all reachable targets from source, up to maxDepth.
/// isSequence indicates whether the source data is a sequence (multiple items) or scalar.
/// The targets are the bookends the reached nodes end on (endsOn:), one target
/// for each bookend: its shortest route, and the routes to every node that
/// ends on it counted together.
/// Returns targets sorted by (min_path_length, display_name).
- (NSArray<CSReachableTargetInfo *> *)getReachableTargetsFromSource:(CSMediaUrn *)source
                                                          maxDepth:(NSUInteger)maxDepth
                                                        isSequence:(BOOL)isSequence;

/// DFS: find all paths to exact target. A path ends at a node that is the
/// target (isEquivalentTo:) or ends on bookends one of which is.
/// isSequence indicates whether the source data is a sequence (multiple items) or scalar.
/// Returns paths sorted by (cap_step_count, specificity desc, urn lex).
- (NSArray<CSStrand *> *)findPathsToExactTarget:(CSMediaUrn *)source
                                                   target:(CSMediaUrn *)target
                                                 maxDepth:(NSUInteger)maxDepth
                                                 maxPaths:(NSUInteger)maxPaths
                                               isSequence:(BOOL)isSequence;

@end

NS_ASSUME_NONNULL_END
