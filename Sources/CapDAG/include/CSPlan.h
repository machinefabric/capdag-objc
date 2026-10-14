//
//  CSPlan.h
//  CapDAG
//
//  Cap Execution Plan structures
//  Mirrors Rust: src/planner/plan.rs
//

#import <Foundation/Foundation.h>
#import "CSCardinality.h"

@class CSArgumentBinding;
@class CSMachineNode;
@class CSMachinePlanEdge;
@class CSStepToken;

NS_ASSUME_NONNULL_BEGIN

/// Unique identifier for a node in the execution plan
typedef NSString * CSNodeId;

// MARK: - StepPolicy

/// What a step's lasting failure does to the run.
typedef NS_ENUM(NSInteger, CSOnError) {
    /// The run fails. The default.
    CSOnErrorFail,
    /// The step's outputs are absent and the run goes on.
    CSOnErrorAbsent
};

/// What a step does when it fails (capdag/docs/09-machine-notation.md
/// §Step policy). The default policy, a step that wrote none, fails the run
/// at once.
@interface CSStepPolicy : NSObject <NSCopying>

/// The number of further attempts after a failure whose class is retryable.
@property (nonatomic, readonly) uint32_t retry;

/// What a failure that stands, after its retries, does to the run.
@property (nonatomic, readonly) CSOnError onError;

/// The policy of a step that wrote none.
+ (instancetype)defaultPolicy;

+ (instancetype)policyWithRetry:(uint32_t)retry onError:(CSOnError)onError;

/// Whether this is the policy of a step that wrote none.
- (BOOL)isDefault;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

// MARK: - EdgeType

/// The kind of an edge. An edge carries the whole value its source produced:
/// there is no reading of a part of it.
typedef NS_ENUM(NSInteger, CSEdgeType) {
    /// Into a step: its MAIN input. Into any other node: what that node is
    /// of — a map's source, an output node's step, a plan output's source.
    CSEdgeTypeDirect,
    /// Into a specific NON-main argument of the target step, identified by
    /// the URN that argument's stream is delivered under (`argUrn`).
    CSEdgeTypeArg,
    /// From a map to one of its item nodes.
    CSEdgeTypeIteration,
    /// From a gathered node into its gather.
    CSEdgeTypeCollection
};

// MARK: - MachinePlanEdge

/// An edge in the execution plan
/// Mirrors Rust: pub struct MachinePlanEdge
@interface CSMachinePlanEdge : NSObject

/// Source node
@property (nonatomic, copy) CSNodeId fromNode;

/// Target node
@property (nonatomic, copy) CSNodeId toNode;

/// Type of data flow
@property (nonatomic, assign) CSEdgeType edgeType;

/// For an Arg edge, the URN the argument's stream is delivered under; nil
/// for every other kind.
@property (nonatomic, copy, nullable) NSString *argUrn;

/// Create a direct edge
+ (instancetype)directFrom:(NSString *)from to:(NSString *)to;

/// Create an edge into the non-main argument of `to` whose stream is
/// delivered under `argUrn`.
+ (instancetype)argFrom:(NSString *)from to:(NSString *)to argUrn:(NSString *)argUrn;

/// Create an iteration edge (map -> item)
+ (instancetype)iterationFrom:(NSString *)from to:(NSString *)to;

/// Create a collection edge (gathered node -> gather)
+ (instancetype)collectionFrom:(NSString *)from to:(NSString *)to;

@end

// MARK: - ForEachSource

/// One sequence a map iterates.
@interface CSForEachSource : NSObject

/// The node that holds the sequence, as the map's own scope sees it.
@property (nonatomic, copy) CSNodeId node;

/// The Item node the body is given each item as.
@property (nonatomic, copy) CSNodeId item;

+ (instancetype)sourceWithNode:(CSNodeId)node item:(CSNodeId)item;

@end

// MARK: - MachineNode

/// The kind of a node of a plan.
typedef NS_ENUM(NSInteger, CSExecutionNodeKind) {
    /// Execute a single cap.
    CSExecutionNodeKindCap,
    /// One output of a step other than its main one, as a node of its own.
    CSExecutionNodeKindCapOutput,
    /// A map: its body runs once per item of its sources, zipped.
    CSExecutionNodeKindForEach,
    /// What one run of a map's body is given of one of the map's sources.
    CSExecutionNodeKindItem,
    /// A gather: several values delivered to one sequence arg as one
    /// sequence, in order.
    CSExecutionNodeKindCollect,
    /// Entry point for user-provided files.
    CSExecutionNodeKindInputSlot,
    /// Terminal node marking a result.
    CSExecutionNodeKindOutput
};

/// A node in the execution DAG. Only the properties of its kind mean
/// anything.
/// Mirrors Rust: pub struct MachineNode and pub enum ExecutionNodeType
@interface CSMachineNode : NSObject

/// Unique identifier for this node
@property (nonatomic, copy) CSNodeId nodeId;

/// Optional description
@property (nonatomic, copy, nullable) NSString *nodeDescription;

/// What the node is.
@property (nonatomic, readonly) CSExecutionNodeKind kind;

/// Cap, ForEach: the stable identity of the step or the map (the
/// CSStrandStep.tokenId it came from). A run's progress is reported under it.
@property (nonatomic, strong, nullable) CSStepToken *tokenId;

// Cap
@property (nonatomic, copy, nullable) NSString *capUrn;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, CSArgumentBinding *> *argBindings;
@property (nonatomic, copy, nullable) NSString *preferredCap;
/// What the step does when it fails. The default policy for a step that
/// wrote none.
@property (nonatomic, strong, nullable) CSStepPolicy *policy;

// CapOutput. A step's main output is the step's node; every other output
// something takes is one of these.
/// The step whose output this is.
@property (nonatomic, copy, nullable) CSNodeId capNode;
/// The output carries the step's input, type unchanged, rather than its own
/// URN (a router's outputs).
@property (nonatomic, assign) BOOL carriesInput;

/// CapOutput: the output's media URN in the cap's definition (its identity,
/// and what its response stream names). Collect: the element type of the
/// gathered sequence.
@property (nonatomic, copy, nullable) NSString *outputMediaUrn;

// ForEach. Run `i` of the body is given item `i` of every source; sources of
// unequal length fail the run.
/// The sequences the map zips, each with the node the body is given its item
/// as. At least one.
@property (nonatomic, copy, nullable) NSArray<CSForEachSource *> *sources;
/// Every node that runs once per item: the item nodes, the steps, the
/// outputs and gathers that belong to them, and the maps opened inside this
/// one (whose own bodies are theirs, not listed here).
@property (nonatomic, copy, nullable) NSArray<CSNodeId> *body;

// Item
/// The map this is an item of.
@property (nonatomic, copy, nullable) CSNodeId foreach;
/// The source node whose item it is.
@property (nonatomic, copy, nullable) CSNodeId source;
/// The item's media URN: the element type of the source sequence.
@property (nonatomic, copy, nullable) NSString *mediaUrn;

// Collect: the nodes gathered, in the order they are delivered. A single
// value contributes one item, a sequence its items; a member that is absent
// contributes none.
@property (nonatomic, copy, nullable) NSArray<CSNodeId> *inputNodes;

// InputSlot
@property (nonatomic, copy, nullable) NSString *slotName;
@property (nonatomic, copy, nullable) NSString *expectedMediaUrn;
@property (nonatomic, assign) CSInputCardinality cardinality;

// Output. For a CapOutput, outputName is the output's name in the cap's
// definition (a label; unique per cap).
@property (nonatomic, copy, nullable) NSString *outputName;
@property (nonatomic, copy, nullable) CSNodeId sourceNode;

/// A cap node with no bindings, under a freshly minted token.
+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn;

/// A cap node with argument bindings, under a freshly minted token.
+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings;

/// A cap node with argument bindings and routing preference, under a freshly
/// minted token.
+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings preferredCap:(nullable NSString *)preferredCap;

/// A cap node keeping a strand step's identity.
+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings tokenId:(CSStepToken *)tokenId;

/// A map, under a freshly minted token.
+ (instancetype)forEachNode:(NSString *)nodeId sources:(NSArray<CSForEachSource *> *)sources body:(NSArray<CSNodeId> *)body;

/// A map, keeping the originating step's identity.
+ (instancetype)forEachNode:(NSString *)nodeId sources:(NSArray<CSForEachSource *> *)sources body:(NSArray<CSNodeId> *)body tokenId:(CSStepToken *)tokenId;

/// The node a map's body is given one source's item as.
+ (instancetype)itemNode:(NSString *)nodeId foreach:(NSString *)foreach source:(NSString *)source mediaUrn:(NSString *)mediaUrn;

/// The node of an output of `capNode` other than its main one.
+ (instancetype)capOutputNode:(NSString *)nodeId capNode:(NSString *)capNode outputMediaUrn:(NSString *)outputMediaUrn outputName:(NSString *)outputName carriesInput:(BOOL)carriesInput;

/// A gather of `inputNodes`, in order, as one sequence of `outputMediaUrn`.
+ (instancetype)collectNode:(NSString *)nodeId inputNodes:(NSArray<CSNodeId> *)inputNodes outputMediaUrn:(NSString *)outputMediaUrn;

/// Create an input slot node
+ (instancetype)inputSlotNode:(NSString *)nodeId slotName:(NSString *)slotName mediaUrn:(NSString *)mediaUrn cardinality:(CSInputCardinality)cardinality;

/// Create an output node
+ (instancetype)outputNode:(NSString *)nodeId outputName:(NSString *)outputName sourceNode:(NSString *)sourceNode;

/// Check if this is a cap execution node
- (BOOL)isCap;

/// Check if this is a map
- (BOOL)isFanOut;

/// Check if this is a gather
- (BOOL)isFanIn;

@end

// MARK: - MachinePlan

/// The structured execution plan for a machine
/// Mirrors Rust: pub struct MachinePlan
@interface CSMachinePlan : NSObject

/// Human-readable name for this execution plan
@property (nonatomic, copy) NSString *name;

/// All nodes in the DAG (nodeId -> node)
@property (nonatomic, strong) NSMutableDictionary<CSNodeId, CSMachineNode *> *nodes;

/// Edges describing data flow
@property (nonatomic, strong) NSMutableArray<CSMachinePlanEdge *> *edges;

/// Entry point nodes (InputSlots)
@property (nonatomic, strong) NSMutableArray<CSNodeId> *entryNodes;

/// Output nodes
@property (nonatomic, strong) NSMutableArray<CSNodeId> *outputNodes;

/// Plan metadata
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id> *metadata;

/// Create an empty plan
+ (instancetype)planWithName:(NSString *)name;

/// Add a node. An input slot is registered as an entry node, an output node
/// as an output.
- (void)addNode:(CSMachineNode *)node;

/// Add an edge to the plan
- (void)addEdge:(CSMachinePlanEdge *)edge;

/// Get a node by ID
- (nullable CSMachineNode *)getNode:(NSString *)nodeId;

/// Check the plan's structure: every edge, entry and output names a node of
/// the plan, and what a node names is there and is what it is named as.
/// Nodes are checked in the order of their ids, so a plan is refused the
/// same way every time.
- (NSError * _Nullable)validate;

/// The map each node runs in: node id -> the id of the map whose body lists
/// it. A node of the machine itself has no entry.
- (NSDictionary<CSNodeId, CSNodeId> *)enclosingMaps;

/// Every node inside map `foreachId`: its body, and the bodies of the maps
/// opened inside it. Empty for a node that is no map.
- (NSSet<CSNodeId> *)mapMembers:(NSString *)foreachId;

/// Get topological ordering of nodes
- (nullable NSArray<CSMachineNode *> *)topologicalOrder:(NSError **)error;

/// Create a plan for a single cap execution
+ (instancetype)singleCapPlan:(NSString *)capUrn inputMedia:(NSString *)inputMedia outputMedia:(NSString *)outputMedia filePathArgName:(NSString *)filePathArgName;

/// Create a linear chain of caps
+ (instancetype)linearChainPlan:(NSArray<NSString *> *)capUrns inputMedia:(NSString *)inputMedia outputMedia:(NSString *)outputMedia filePathArgNames:(NSArray<NSString *> *)filePathArgNames;

/// Whether the plan contains a map.
- (BOOL)hasForeach;

@end

NS_ASSUME_NONNULL_END
