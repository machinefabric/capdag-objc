//
//  CSPlan.m
//  CapDAG
//
//  Cap Execution Plan structures
//  Mirrors Rust: src/planner/plan.rs
//

#import "CSPlan.h"
#import "CSArgumentBinding.h"
#import "CSCardinality.h"
#import "CSPlanBuilder.h"

static NSError *CSPlanError(NSString *message) {
    return [NSError errorWithDomain:@"CSPlannerError"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

// MARK: - StepPolicy

@implementation CSStepPolicy

- (instancetype)initWithRetry:(uint32_t)retry onError:(CSOnError)onError {
    self = [super init];
    if (self) {
        _retry = retry;
        _onError = onError;
    }
    return self;
}

+ (instancetype)defaultPolicy {
    return [[self alloc] initWithRetry:0 onError:CSOnErrorFail];
}

+ (instancetype)policyWithRetry:(uint32_t)retry onError:(CSOnError)onError {
    return [[self alloc] initWithRetry:retry onError:onError];
}

- (BOOL)isDefault {
    return self.retry == 0 && self.onError == CSOnErrorFail;
}

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:[CSStepPolicy class]]) return NO;
    CSStepPolicy *policy = other;
    return policy.retry == self.retry && policy.onError == self.onError;
}

- (NSUInteger)hash {
    return (NSUInteger)self.retry * 2 + (NSUInteger)self.onError;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

// MARK: - MachinePlanEdge

@implementation CSMachinePlanEdge

+ (instancetype)edgeFrom:(NSString *)from to:(NSString *)to type:(CSEdgeType)type {
    CSMachinePlanEdge *edge = [[CSMachinePlanEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = type;
    return edge;
}

+ (instancetype)directFrom:(NSString *)from to:(NSString *)to {
    return [self edgeFrom:from to:to type:CSEdgeTypeDirect];
}

+ (instancetype)argFrom:(NSString *)from to:(NSString *)to argUrn:(NSString *)argUrn {
    CSMachinePlanEdge *edge = [self edgeFrom:from to:to type:CSEdgeTypeArg];
    edge.argUrn = argUrn;
    return edge;
}

+ (instancetype)iterationFrom:(NSString *)from to:(NSString *)to {
    return [self edgeFrom:from to:to type:CSEdgeTypeIteration];
}

+ (instancetype)collectionFrom:(NSString *)from to:(NSString *)to {
    return [self edgeFrom:from to:to type:CSEdgeTypeCollection];
}

@end

// MARK: - ForEachSource

@implementation CSForEachSource

+ (instancetype)sourceWithNode:(CSNodeId)node item:(CSNodeId)item {
    CSForEachSource *source = [[CSForEachSource alloc] init];
    source.node = node;
    source.item = item;
    return source;
}

@end

// MARK: - MachineNode

@interface CSMachineNode ()
@property (nonatomic, readwrite) CSExecutionNodeKind kind;
@end

@implementation CSMachineNode

+ (instancetype)nodeWithId:(NSString *)nodeId kind:(CSExecutionNodeKind)kind {
    CSMachineNode *node = [[CSMachineNode alloc] init];
    node.nodeId = nodeId;
    node.kind = kind;
    return node;
}

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn {
    return [self capNode:nodeId capUrn:capUrn bindings:@{} tokenId:[CSStepToken mint]];
}

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings {
    return [self capNode:nodeId capUrn:capUrn bindings:bindings tokenId:[CSStepToken mint]];
}

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings preferredCap:(nullable NSString *)preferredCap {
    CSMachineNode *node = [self capNode:nodeId capUrn:capUrn bindings:bindings tokenId:[CSStepToken mint]];
    node.preferredCap = preferredCap;
    return node;
}

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings tokenId:(CSStepToken *)tokenId {
    CSMachineNode *node = [self nodeWithId:nodeId kind:CSExecutionNodeKindCap];
    node.capUrn = capUrn;
    node.argBindings = bindings;
    node.tokenId = tokenId;
    node.policy = [CSStepPolicy defaultPolicy];
    return node;
}

+ (instancetype)forEachNode:(NSString *)nodeId sources:(NSArray<CSForEachSource *> *)sources body:(NSArray<CSNodeId> *)body {
    return [self forEachNode:nodeId sources:sources body:body tokenId:[CSStepToken mint]];
}

+ (instancetype)forEachNode:(NSString *)nodeId sources:(NSArray<CSForEachSource *> *)sources body:(NSArray<CSNodeId> *)body tokenId:(CSStepToken *)tokenId {
    CSMachineNode *node = [self nodeWithId:nodeId kind:CSExecutionNodeKindForEach];
    node.sources = sources;
    node.body = body;
    node.tokenId = tokenId;
    node.nodeDescription = @"Map: run the body once per item";
    return node;
}

+ (instancetype)itemNode:(NSString *)nodeId foreach:(NSString *)foreach source:(NSString *)source mediaUrn:(NSString *)mediaUrn {
    CSMachineNode *node = [self nodeWithId:nodeId kind:CSExecutionNodeKindItem];
    node.foreach = foreach;
    node.source = source;
    node.mediaUrn = mediaUrn;
    node.nodeDescription = [NSString stringWithFormat:@"Item of %@", source];
    return node;
}

+ (instancetype)capOutputNode:(NSString *)nodeId capNode:(NSString *)capNode outputMediaUrn:(NSString *)outputMediaUrn outputName:(NSString *)outputName carriesInput:(BOOL)carriesInput {
    CSMachineNode *node = [self nodeWithId:nodeId kind:CSExecutionNodeKindCapOutput];
    node.capNode = capNode;
    node.outputMediaUrn = outputMediaUrn;
    node.outputName = outputName;
    node.carriesInput = carriesInput;
    node.nodeDescription = [NSString stringWithFormat:@"Output: %@", outputName];
    return node;
}

+ (instancetype)collectNode:(NSString *)nodeId inputNodes:(NSArray<CSNodeId> *)inputNodes outputMediaUrn:(NSString *)outputMediaUrn {
    CSMachineNode *node = [self nodeWithId:nodeId kind:CSExecutionNodeKindCollect];
    node.inputNodes = inputNodes;
    node.outputMediaUrn = outputMediaUrn;
    node.nodeDescription = @"Gather: several values into one sequence";
    return node;
}

+ (instancetype)inputSlotNode:(NSString *)nodeId slotName:(NSString *)slotName mediaUrn:(NSString *)mediaUrn cardinality:(CSInputCardinality)cardinality {
    CSMachineNode *node = [self nodeWithId:nodeId kind:CSExecutionNodeKindInputSlot];
    node.slotName = slotName;
    node.expectedMediaUrn = mediaUrn;
    node.cardinality = cardinality;
    node.nodeDescription = [NSString stringWithFormat:@"Input: %@", slotName];
    return node;
}

+ (instancetype)outputNode:(NSString *)nodeId outputName:(NSString *)outputName sourceNode:(NSString *)sourceNode {
    CSMachineNode *node = [self nodeWithId:nodeId kind:CSExecutionNodeKindOutput];
    node.outputName = outputName;
    node.sourceNode = sourceNode;
    node.nodeDescription = [NSString stringWithFormat:@"Output: %@", outputName];
    return node;
}

- (BOOL)isCap {
    return self.kind == CSExecutionNodeKindCap;
}

- (BOOL)isFanOut {
    return self.kind == CSExecutionNodeKindForEach;
}

- (BOOL)isFanIn {
    return self.kind == CSExecutionNodeKindCollect;
}

@end

// MARK: - MachinePlan

@implementation CSMachinePlan

+ (instancetype)planWithName:(NSString *)name {
    CSMachinePlan *plan = [[CSMachinePlan alloc] init];
    plan.name = name;
    plan.nodes = [NSMutableDictionary dictionary];
    plan.edges = [NSMutableArray array];
    plan.entryNodes = [NSMutableArray array];
    plan.outputNodes = [NSMutableArray array];
    return plan;
}

- (void)addNode:(CSMachineNode *)node {
    switch (node.kind) {
        case CSExecutionNodeKindInputSlot:
            [self.entryNodes addObject:node.nodeId];
            break;
        case CSExecutionNodeKindOutput:
            [self.outputNodes addObject:node.nodeId];
            break;
        default:
            break;
    }
    self.nodes[node.nodeId] = node;
}

- (void)addEdge:(CSMachinePlanEdge *)edge {
    [self.edges addObject:edge];
}

- (nullable CSMachineNode *)getNode:(NSString *)nodeId {
    return self.nodes[nodeId];
}

- (nullable NSError *)node:(NSString *)owner names:(NSString *)what known:(nullable NSString *)nodeId {
    if (nodeId != nil && self.nodes[nodeId] != nil) return nil;
    return CSPlanError([NSString stringWithFormat:@"node '%@' names %@ '%@', which is not in the plan", owner, what, nodeId ?: @""]);
}

- (NSError * _Nullable)validate {
    for (CSMachinePlanEdge *edge in self.edges) {
        if (!self.nodes[edge.fromNode]) {
            return CSPlanError([NSString stringWithFormat:@"Edge from_node '%@' not found in plan", edge.fromNode]);
        }
        if (!self.nodes[edge.toNode]) {
            return CSPlanError([NSString stringWithFormat:@"Edge to_node '%@' not found in plan", edge.toNode]);
        }
    }
    for (NSString *entry in self.entryNodes) {
        if (!self.nodes[entry]) {
            return CSPlanError([NSString stringWithFormat:@"Entry node '%@' not found in plan", entry]);
        }
    }
    for (NSString *output in self.outputNodes) {
        if (!self.nodes[output]) {
            return CSPlanError([NSString stringWithFormat:@"Output node '%@' not found in plan", output]);
        }
    }

    NSMutableDictionary<NSString *, NSString *> *inBody = [NSMutableDictionary dictionary];
    NSArray<NSString *> *ids = [self.nodes.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *nodeId in ids) {
        CSMachineNode *node = self.nodes[nodeId];
        NSError *error = nil;
        switch (node.kind) {
            case CSExecutionNodeKindCap:
            case CSExecutionNodeKindInputSlot:
                break;
            case CSExecutionNodeKindOutput:
                if ((error = [self node:nodeId names:@"source" known:node.sourceNode])) return error;
                break;
            case CSExecutionNodeKindCollect:
                for (NSString *input in node.inputNodes) {
                    if ((error = [self node:nodeId names:@"gathered node" known:input])) return error;
                }
                break;
            case CSExecutionNodeKindCapOutput:
                if ((error = [self node:nodeId names:@"step" known:node.capNode])) return error;
                if (![self.nodes[node.capNode] isCap]) {
                    return CSPlanError([NSString stringWithFormat:@"output node '%@' names '%@' as its step, which is not a step", nodeId, node.capNode]);
                }
                break;
            case CSExecutionNodeKindItem: {
                if ((error = [self node:nodeId names:@"map" known:node.foreach])) return error;
                CSMachineNode *of = self.nodes[node.foreach];
                BOOL listed = NO;
                if (of.kind == CSExecutionNodeKindForEach) {
                    for (CSForEachSource *source in of.sources) {
                        if ([source.item isEqualToString:nodeId] && [source.node isEqualToString:node.source]) listed = YES;
                    }
                }
                if (!listed) {
                    return CSPlanError([NSString stringWithFormat:@"item node '%@' names map '%@' and source '%@', and that map does not list it so", nodeId, node.foreach, node.source]);
                }
                break;
            }
            case CSExecutionNodeKindForEach: {
                if (node.sources.count == 0) {
                    return CSPlanError([NSString stringWithFormat:@"map '%@' iterates nothing", nodeId]);
                }
                for (CSForEachSource *source in node.sources) {
                    if ((error = [self node:nodeId names:@"source" known:source.node])) return error;
                    if ((error = [self node:nodeId names:@"item" known:source.item])) return error;
                    CSMachineNode *item = self.nodes[source.item];
                    if (item.kind != CSExecutionNodeKindItem || ![item.foreach isEqualToString:nodeId] || ![item.source isEqualToString:source.node]) {
                        return CSPlanError([NSString stringWithFormat:@"map '%@' lists '%@' as its item of '%@', which is not that", nodeId, source.item, source.node]);
                    }
                    if (![node.body containsObject:source.item]) {
                        return CSPlanError([NSString stringWithFormat:@"map '%@' does not list its item '%@' in its body", nodeId, source.item]);
                    }
                }
                for (NSString *member in node.body) {
                    if ((error = [self node:nodeId names:@"body node" known:member])) return error;
                    if ([member isEqualToString:nodeId]) {
                        return CSPlanError([NSString stringWithFormat:@"map '%@' lists itself in its body", nodeId]);
                    }
                    NSString *other = inBody[member];
                    if (other != nil) {
                        return CSPlanError([NSString stringWithFormat:@"node '%@' is in the body of two maps ('%@' and '%@')", member, other, nodeId]);
                    }
                    inBody[member] = nodeId;
                }
                break;
            }
        }
    }
    return nil;
}

- (NSDictionary<CSNodeId, CSNodeId> *)enclosingMaps {
    NSMutableDictionary<CSNodeId, CSNodeId> *enclosing = [NSMutableDictionary dictionary];
    for (NSString *nodeId in self.nodes) {
        CSMachineNode *node = self.nodes[nodeId];
        if (node.kind != CSExecutionNodeKindForEach) continue;
        for (NSString *member in node.body) {
            enclosing[member] = nodeId;
        }
    }
    return enclosing;
}

- (NSSet<CSNodeId> *)mapMembers:(NSString *)foreachId {
    NSMutableSet<CSNodeId> *members = [NSMutableSet set];
    NSMutableArray<NSString *> *pending = [NSMutableArray arrayWithObject:foreachId];
    while (pending.count > 0) {
        NSString *nodeId = pending.lastObject;
        [pending removeLastObject];
        CSMachineNode *node = self.nodes[nodeId];
        if (node.kind != CSExecutionNodeKindForEach || node == nil) continue;
        for (NSString *member in node.body) {
            if (![members containsObject:member]) {
                [members addObject:member];
                [pending addObject:member];
            }
        }
    }
    return members;
}

- (nullable NSArray<CSMachineNode *> *)topologicalOrder:(NSError **)error {
    NSMutableDictionary<NSString *, NSNumber *> *inDegree = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *adj = [NSMutableDictionary dictionary];

    for (NSString *nodeId in self.nodes) {
        inDegree[nodeId] = @0;
        adj[nodeId] = [NSMutableArray array];
    }

    for (CSMachinePlanEdge *edge in self.edges) {
        if (inDegree[edge.toNode] != nil) {
            inDegree[edge.toNode] = @([inDegree[edge.toNode] integerValue] + 1);
        }
        [adj[edge.fromNode] addObject:edge.toNode];
    }

    NSMutableArray<NSString *> *queue = [NSMutableArray array];
    for (NSString *nodeId in inDegree) {
        if ([inDegree[nodeId] integerValue] == 0) {
            [queue addObject:nodeId];
        }
    }

    NSMutableArray<CSMachineNode *> *result = [NSMutableArray array];
    while (queue.count > 0) {
        NSString *nodeId = queue.firstObject;
        [queue removeObjectAtIndex:0];

        CSMachineNode *node = self.nodes[nodeId];
        if (node) {
            [result addObject:node];
        }

        for (NSString *neighbor in adj[nodeId]) {
            NSInteger degree = [inDegree[neighbor] integerValue] - 1;
            inDegree[neighbor] = @(degree);
            if (degree == 0) {
                [queue addObject:neighbor];
            }
        }
    }

    if (result.count != self.nodes.count) {
        if (error) {
            *error = CSPlanError(@"Cycle detected in execution plan");
        }
        return nil;
    }
    return result;
}

+ (instancetype)singleCapPlan:(NSString *)capUrn inputMedia:(NSString *)inputMedia outputMedia:(NSString *)outputMedia filePathArgName:(NSString *)filePathArgName {
    CSMachinePlan *plan = [self planWithName:[NSString stringWithFormat:@"Single cap: %@", capUrn]];

    NSString *inputId = @"input_slot";
    [plan addNode:[CSMachineNode inputSlotNode:inputId
                                      slotName:@"input"
                                      mediaUrn:inputMedia
                                   cardinality:CSInputCardinalitySingle]];

    NSString *capId = @"cap_0";
    NSDictionary *bindings = @{filePathArgName: [CSArgumentBinding inputFilePath]};
    [plan addNode:[CSMachineNode capNode:capId capUrn:capUrn bindings:bindings]];
    [plan addEdge:[CSMachinePlanEdge directFrom:inputId to:capId]];

    NSString *outputId = @"output";
    [plan addNode:[CSMachineNode outputNode:outputId outputName:@"result" sourceNode:capId]];
    [plan addEdge:[CSMachinePlanEdge directFrom:capId to:outputId]];

    return plan;
}

+ (instancetype)linearChainPlan:(NSArray<NSString *> *)capUrns inputMedia:(NSString *)inputMedia outputMedia:(NSString *)outputMedia filePathArgNames:(NSArray<NSString *> *)filePathArgNames {
    CSMachinePlan *plan = [self planWithName:@"Linear machine"];

    if (capUrns.count == 0) {
        return plan;
    }

    NSString *inputId = @"input_slot";
    [plan addNode:[CSMachineNode inputSlotNode:inputId
                                      slotName:@"input"
                                      mediaUrn:inputMedia
                                   cardinality:CSInputCardinalitySingle]];

    NSString *prevId = inputId;
    for (NSUInteger i = 0; i < capUrns.count; i++) {
        NSString *capId = [NSString stringWithFormat:@"cap_%lu", (unsigned long)i];
        NSDictionary *bindings = @{};
        if (i < filePathArgNames.count) {
            bindings = @{filePathArgNames[i]: [CSArgumentBinding inputFilePath]};
        }
        [plan addNode:[CSMachineNode capNode:capId capUrn:capUrns[i] bindings:bindings]];
        [plan addEdge:[CSMachinePlanEdge directFrom:prevId to:capId]];
        prevId = capId;
    }

    NSString *outputId = @"output";
    [plan addNode:[CSMachineNode outputNode:outputId outputName:@"result" sourceNode:prevId]];
    [plan addEdge:[CSMachinePlanEdge directFrom:prevId to:outputId]];

    return plan;
}

- (BOOL)hasForeach {
    for (NSString *nodeId in self.nodes) {
        if ([self.nodes[nodeId] isFanOut]) {
            return YES;
        }
    }
    return NO;
}

@end

