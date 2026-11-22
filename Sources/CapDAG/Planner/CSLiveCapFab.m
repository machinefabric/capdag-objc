//
//  CSLiveCapFab.m
//  CapDAG
//
//  Precomputed capability graph for path finding.
//  Mirrors Rust: src/planner/live_cap_fab.rs (1466 lines)
//

#import "CSLiveCapFab.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSMediaUrn.h"
#import "CSStandardCaps.h"
#import "CSCardinality.h"

// =============================================================================
// CSLiveMachinePlanEdge
// =============================================================================

@interface CSLiveMachinePlanEdge ()
@property (nonatomic, strong, readwrite) CSMediaUrn *fromSpec;
@property (nonatomic, strong, readwrite) CSMediaUrn *toSpec;
@property (nonatomic, assign, readwrite) CSLiveMachinePlanEdgeType edgeType;
@property (nonatomic, assign, readwrite) BOOL inputIsSequence;
@property (nonatomic, assign, readwrite) BOOL outputIsSequence;
@property (nonatomic, strong, readwrite, nullable) CSMediaUrn *outputUrn;
@property (nonatomic, strong, readwrite, nullable) CSCapUrn *capUrn;
@property (nonatomic, copy, readwrite, nullable) NSString *capTitle;
@property (nonatomic, assign, readwrite) NSUInteger specificity;
@end

@implementation CSLiveMachinePlanEdge

+ (instancetype)capEdgeFrom:(CSMediaUrn *)from
                         to:(CSMediaUrn *)to
                     capUrn:(CSCapUrn *)capUrn
                      title:(NSString *)title
                specificity:(NSUInteger)specificity
           inputIsSequence:(BOOL)inputIsSeq
          outputIsSequence:(BOOL)outputIsSeq
                 outputUrn:(nullable CSMediaUrn *)outputUrn {
    CSLiveMachinePlanEdge *edge = [[CSLiveMachinePlanEdge alloc] init];
    edge.fromSpec = from;
    edge.toSpec = to;
    edge.edgeType = CSLiveMachinePlanEdgeTypeCap;
    edge.capUrn = capUrn;
    edge.capTitle = title;
    edge.specificity = specificity;
    edge.inputIsSequence = inputIsSeq;
    edge.outputIsSequence = outputIsSeq;
    edge.outputUrn = outputUrn;
    return edge;
}

+ (instancetype)forEachEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to {
    CSLiveMachinePlanEdge *edge = [[CSLiveMachinePlanEdge alloc] init];
    edge.fromSpec = from;
    edge.toSpec = to;
    edge.edgeType = CSLiveMachinePlanEdgeTypeForEach;
    edge.inputIsSequence = YES;
    edge.outputIsSequence = NO;
    edge.specificity = 0;
    return edge;
}

+ (instancetype)collectEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to {
    CSLiveMachinePlanEdge *edge = [[CSLiveMachinePlanEdge alloc] init];
    edge.fromSpec = from;
    edge.toSpec = to;
    edge.edgeType = CSLiveMachinePlanEdgeTypeCollect;
    edge.inputIsSequence = NO;
    edge.outputIsSequence = YES;
    edge.specificity = 0;
    return edge;
}

- (NSString *)title {
    switch (self.edgeType) {
        case CSLiveMachinePlanEdgeTypeCap:
            return self.capTitle ?: @"(unknown cap)";
        case CSLiveMachinePlanEdgeTypeForEach:
            return @"ForEach (iterate over list)";
        case CSLiveMachinePlanEdgeTypeCollect:
            return @"Collect (scalar to list)";
    }
}

- (BOOL)isCap {
    return self.edgeType == CSLiveMachinePlanEdgeTypeCap;
}

@end

// =============================================================================
// CSLiveCapFab
// =============================================================================

@interface CSLiveCapFab ()
/// All edges in the graph
@property (nonatomic, strong) NSMutableArray<CSLiveMachinePlanEdge *> *edges;
/// Index: from_spec canonical -> edge indices
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *outgoing;
/// Index: to_spec canonical -> edge indices
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *incoming;
/// All unique media URN canonical strings
@property (nonatomic, strong) NSMutableSet<NSString *> *nodes;
/// Cap URN canonical -> edge indices (for removal)
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *capToEdges;
/// Cached identity URN for skip checks
@property (nonatomic, strong, nullable) CSCapUrn *identityUrn;
- (BOOL)canFollowForEach:(CSLiveMachinePlanEdge *)edge;
@end

@implementation CSLiveCapFab

+ (instancetype)graph {
    CSLiveCapFab *graph = [[CSLiveCapFab alloc] init];
    graph.edges = [NSMutableArray array];
    graph.outgoing = [NSMutableDictionary dictionary];
    graph.incoming = [NSMutableDictionary dictionary];
    graph.nodes = [NSMutableSet set];
    graph.capToEdges = [NSMutableDictionary dictionary];
    // Parse identity URN once
    NSError *error = nil;
    graph.identityUrn = [CSCapUrn fromString:CSCapIdentity error:&error];
    return graph;
}

- (void)clear {
    [self.edges removeAllObjects];
    [self.outgoing removeAllObjects];
    [self.incoming removeAllObjects];
    [self.nodes removeAllObjects];
    [self.capToEdges removeAllObjects];
}

// MARK: - Sync

- (void)syncFromCaps:(NSArray<CSCap *> *)caps {
    [self clear];
    for (CSCap *cap in caps) {
        [self addCap:cap];
    }
    // Cardinality transitions (ForEach/Collect) are synthesized dynamically in getOutgoingEdges:isSequence:
}

- (void)syncFromCapUrns:(NSArray<NSString *> *)capUrns
               registry:(id<CSFabricRegistryProtocol>)registry
             completion:(void (^)(void))completion {
    [self clear];

    [registry getCachedCaps:^(NSArray<CSCap *> * _Nullable allCaps, NSError * _Nullable error) {
        if (error || !allCaps) {
            completion();
            return;
        }

        for (NSString *capUrnStr in capUrns) {
            NSError *parseError = nil;
            CSCapUrn *capUrn = [CSCapUrn fromString:capUrnStr error:&parseError];
            if (!capUrn) continue;

            // Skip identity caps
            if (self.identityUrn && [capUrn isEquivalent:self.identityUrn]) {
                continue;
            }

            // Find matching Cap in registry using isDispatchable
            CSCap *matchingCap = nil;
            for (CSCap *registryCap in allCaps) {
                // Skip identity caps in registry
                if (self.identityUrn && [registryCap.capUrn isEquivalent:self.identityUrn]) {
                    continue;
                }
                if ([capUrn isDispatchable:registryCap.capUrn]) {
                    matchingCap = registryCap;
                    break;
                }
            }

            if (matchingCap) {
                [self addCap:matchingCap];
            }
        }

        // Cardinality transitions (ForEach/Collect) are synthesized dynamically in getOutgoingEdges:isSequence:
        completion();
    }];
}

// MARK: - Add Cap

- (void)addCap:(CSCap *)cap {
    NSString *inSpecStr = [cap.capUrn getInSpec];
    NSString *outSpecStr = [cap.capUrn getOutSpec];

    // Skip caps with empty specs
    if (inSpecStr.length == 0 || outSpecStr.length == 0) {
        return;
    }

    // Skip identity caps
    if (self.identityUrn && [cap.capUrn isEquivalent:self.identityUrn]) {
        return;
    }

    // Parse media URNs
    NSError *error = nil;
    CSMediaUrn *fromSpec = [CSMediaUrn fromString:inSpecStr error:&error];
    if (!fromSpec) return;

    error = nil;
    CSMediaUrn *toSpec = [CSMediaUrn fromString:outSpecStr error:&error];
    if (!toSpec) return;

    // Cardinality follows the declared main input, never argument order.
    BOOL inputIsSeq = [cap primaryInputIsSequence];
    CSCapOutput *main = [cap mainOutput];
    BOOL outputIsSeq = main ? main.isSequence : NO;
    [self pushEdgeOfCap:cap from:fromSpec to:toSpec inputIsSequence:inputIsSeq outputIsSequence:outputIsSeq outputUrn:nil];

    // Every other output the cap declares is reachable too: an edge from the
    // cap's input to that output's own type. An output that carries the input
    // unchanged (a router's) has no type of its own to reach.
    for (CSCapOutput *output in [cap getOutputs]) {
        if (output.carries != nil) continue;
        if (main != nil && [main.mediaUrn isEqualToString:output.mediaUrn]) continue;
        NSError *outputError = nil;
        CSMediaUrn *outputUrn = [CSMediaUrn fromString:output.mediaUrn error:&outputError];
        if (outputUrn == nil) {
            [NSException raise:NSInternalInconsistencyException
                        format:@"cap registry invariant: output media_urn '%@' of '%@' is a valid media URN: %@",
                               output.mediaUrn, cap.capUrn, outputError.localizedDescription];
        }
        [self pushEdgeOfCap:cap from:fromSpec to:outputUrn inputIsSequence:inputIsSeq outputIsSequence:output.isSequence outputUrn:outputUrn];
    }
}

/// Store one edge of `cap`, from its input to one of its outputs.
- (void)pushEdgeOfCap:(CSCap *)cap
                 from:(CSMediaUrn *)fromSpec
                   to:(CSMediaUrn *)toSpec
      inputIsSequence:(BOOL)inputIsSeq
     outputIsSequence:(BOOL)outputIsSeq
            outputUrn:(nullable CSMediaUrn *)outputUrn {
    NSString *fromCanonical = [fromSpec toString];
    NSString *toCanonical = [toSpec toString];
    NSString *capCanonical = [cap.capUrn toString];

    NSUInteger edgeIdx = self.edges.count;
    CSLiveMachinePlanEdge *edge = [CSLiveMachinePlanEdge capEdgeFrom:fromSpec
                                                  to:toSpec
                                              capUrn:cap.capUrn
                                               title:cap.title
                                         specificity:(NSUInteger)[cap.capUrn specificity]
                                    inputIsSequence:inputIsSeq
                                   outputIsSequence:outputIsSeq
                                          outputUrn:outputUrn];
    [self.edges addObject:edge];

    // Update indices
    if (!self.outgoing[fromCanonical]) {
        self.outgoing[fromCanonical] = [NSMutableArray array];
    }
    [self.outgoing[fromCanonical] addObject:@(edgeIdx)];

    if (!self.incoming[toCanonical]) {
        self.incoming[toCanonical] = [NSMutableArray array];
    }
    [self.incoming[toCanonical] addObject:@(edgeIdx)];

    [self.nodes addObject:fromCanonical];
    [self.nodes addObject:toCanonical];

    if (!self.capToEdges[capCanonical]) {
        self.capToEdges[capCanonical] = [NSMutableArray array];
    }
    [self.capToEdges[capCanonical] addObject:@(edgeIdx)];
}

// MARK: - Stats

- (NSUInteger)nodeCount {
    return self.nodes.count;
}

- (NSUInteger)edgeCount {
    return self.edges.count;
}

// MARK: - Outgoing Edges (satisfies matching)

/// Get all outgoing edges from source, with cardinality transitions synthesized dynamically.
/// A source is what a step gave or a file's detected type, a complete thing: what it does
/// not mention it does not have, so cap edges are matched on satisfies. ForEach/Collect are
/// synthesized based on isSequence.
/// Returns array of dictionaries with @"edge" (CSLiveMachinePlanEdge) and @"isSequence" (NSNumber BOOL).
- (NSArray<NSDictionary *> *)getOutgoingEdges:(CSMediaUrn *)source isSequence:(BOOL)isSequence {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];

    for (CSLiveMachinePlanEdge *edge in self.edges) {
        NSAssert(edge.edgeType == CSLiveMachinePlanEdgeTypeCap,
                 @"Non-cap edge found in graph storage: %@", edge);
        if (![source satisfies:edge.fromSpec]) continue;

        // Cardinality compatibility:
        // sequence data → scalar cap: needs ForEach first, skip direct match
        // scalar data → sequence cap: single item wraps into 1-item sequence, OK
        if (isSequence && !edge.inputIsSequence) continue;

        BOOL outIsSeq = edge.outputIsSequence;
        [result addObject:@{@"edge": edge, @"isSequence": @(outIsSeq)}];
    }

    // Synthesize ForEach when data is a sequence
    if (isSequence) {
        // Check if any scalar cap could consume items after ForEach
        BOOL hasScalarConsumers = NO;
        for (CSLiveMachinePlanEdge *edge in self.edges) {
            if (!edge.inputIsSequence && [source satisfies:edge.fromSpec]) {
                hasScalarConsumers = YES;
                break;
            }
        }
        if (hasScalarConsumers) {
            CSLiveMachinePlanEdge *foreachEdge = [CSLiveMachinePlanEdge forEachEdgeFrom:source to:source];
            [result addObject:@{@"edge": foreachEdge, @"isSequence": @NO}];
        }
    }

    return result;
}

// MARK: - Cardinality Transitions
// insertCardinalityTransitions removed — ForEach/Collect are synthesized dynamically
// in getOutgoingEdges:isSequence: based on the current is_sequence state.

// insertCollectEdgesForExistingLists removed — Collect edges are synthesized dynamically.

// MARK: - Reachable Targets (BFS)

- (NSArray<CSReachableTargetInfo *> *)getReachableTargetsFromSource:(CSMediaUrn *)source
                                                          maxDepth:(NSUInteger)maxDepth
                                                        isSequence:(BOOL)isSequence {
    NSMutableDictionary<NSString *, CSReachableTargetInfo *> *results = [NSMutableDictionary dictionary];
    // Visited also tracks a synthesized ForEach awaiting its body cap.
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    // Queue entries: [CSMediaUrn, depth, isSequence, pendingForEach]
    NSMutableArray<NSArray *> *queue = [NSMutableArray array];

    NSString *sourceKey = [NSString stringWithFormat:@"%@|%d|0", [source toString], isSequence];
    [queue addObject:@[source, @0, @(isSequence), @NO]];
    [visited addObject:sourceKey];

    while (queue.count > 0) {
        NSArray *item = queue.firstObject;
        [queue removeObjectAtIndex:0];

        CSMediaUrn *current = item[0];
        NSUInteger depth = [item[1] unsignedIntegerValue];
        BOOL currentIsSequence = [item[2] boolValue];
        BOOL pendingForEach = [item[3] boolValue];

        if (depth >= maxDepth) continue;

        NSArray<NSDictionary *> *outEdges = [self getOutgoingEdges:current isSequence:currentIsSequence];
        for (NSDictionary *edgeDict in outEdges) {
            CSLiveMachinePlanEdge *edge = edgeDict[@"edge"];
            if (pendingForEach && ![self canFollowForEach:edge]) {
                continue;
            }
            BOOL nextIsSequence = [edgeDict[@"isSequence"] boolValue];
            NSUInteger newDepth = depth + 1;
            NSString *outputCanonical = [edge.toSpec toString];

            BOOL nextPendingForEach = edge.edgeType == CSLiveMachinePlanEdgeTypeForEach;
            if (!nextPendingForEach) {
                // A ForEach boundary is not a result; only complete cap
                // transitions contribute reachable targets.
                CSReachableTargetInfo *info = results[outputCanonical];
                if (!info) {
                    info = [[CSReachableTargetInfo alloc] init];
                    info.mediaUrn = outputCanonical;
                    info.displayName = outputCanonical;
                    info.minDepth = newDepth;
                    info.pathCount = 0;
                    results[outputCanonical] = info;
                }
                info.pathCount += 1;
            }

            NSString *nextKey = [NSString stringWithFormat:@"%@|%d|%d", outputCanonical, nextIsSequence, nextPendingForEach];
            if (![visited containsObject:nextKey]) {
                [visited addObject:nextKey];
                [queue addObject:@[edge.toSpec, @(newDepth), @(nextIsSequence), @(nextPendingForEach)]];
            }
        }
    }

    // Sort by (minDepth, displayName)
    NSArray<CSReachableTargetInfo *> *sorted = [[results allValues] sortedArrayUsingComparator:
        ^NSComparisonResult(CSReachableTargetInfo *a, CSReachableTargetInfo *b) {
            if (a.minDepth != b.minDepth) {
                return a.minDepth < b.minDepth ? NSOrderedAscending : NSOrderedDescending;
            }
            return [a.displayName compare:b.displayName];
        }];

    return sorted;
}

// MARK: - Path Finding (DFS with exact target matching)

/// The key of a state of the path search: the media reached, whether it is a sequence, and
/// whether the step that reached it was a ForEach (whose scalar cap must come next).
static NSString *CSSearchStateKey(CSMediaUrn *media, BOOL isSequence, BOOL pendingForEach) {
    return [NSString stringWithFormat:@"%@|%d|%d", [media toString], isSequence, pendingForEach];
}

/// How few steps each search state reachable from the source is from the target, by state key,
/// for the states the target is reachable from within maxDepth of the source; nil when no step
/// reaches the target at all. The states are found forward from the source over the edges
/// getOutgoingEdges:isSequence: gives, and the distances backward over those same steps from the
/// states that are the target. A state missing from the result cannot reach the target; one at
/// distance d cannot reach it in fewer than d steps.
- (nullable NSDictionary<NSString *, NSNumber *> *)distancesToExactTarget:(CSMediaUrn *)target
                                                               fromSource:(CSMediaUrn *)source
                                                                 maxDepth:(NSUInteger)maxDepth
                                                               isSequence:(BOOL)isSequence {
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *stepsInto = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *targetStates = [NSMutableSet set];
    NSString *startKey = CSSearchStateKey(source, isSequence, NO);
    NSMutableSet<NSString *> *seen = [NSMutableSet setWithObject:startKey];
    // Queue entries: [CSMediaUrn, depth, isSequence, pendingForEach]
    NSMutableArray<NSArray *> *queue = [NSMutableArray arrayWithObject:@[source, @0, @(isSequence), @NO]];

    while (queue.count > 0) {
        NSArray *item = queue.firstObject;
        [queue removeObjectAtIndex:0];
        CSMediaUrn *current = item[0];
        NSUInteger depth = [item[1] unsignedIntegerValue];
        BOOL currentIsSequence = [item[2] boolValue];
        BOOL pendingForEach = [item[3] boolValue];
        if (depth >= maxDepth) continue;

        NSString *fromKey = CSSearchStateKey(current, currentIsSequence, pendingForEach);
        for (NSDictionary *edgeDict in [self getOutgoingEdges:current isSequence:currentIsSequence]) {
            CSLiveMachinePlanEdge *edge = edgeDict[@"edge"];
            if (pendingForEach && ![self canFollowForEach:edge]) continue;
            BOOL nextIsSequence = [edgeDict[@"isSequence"] boolValue];
            BOOL nextPendingForEach = edge.edgeType == CSLiveMachinePlanEdgeTypeForEach;
            NSString *nextKey = CSSearchStateKey(edge.toSpec, nextIsSequence, nextPendingForEach);
            NSMutableArray<NSString *> *into = stepsInto[nextKey];
            if (!into) {
                into = [NSMutableArray array];
                stepsInto[nextKey] = into;
            }
            [into addObject:fromKey];
            // The target: its media, reached by a step, not waiting on a ForEach's cap.
            if (!nextPendingForEach && [edge.toSpec isEquivalentTo:target]) {
                [targetStates addObject:nextKey];
            }
            if (![seen containsObject:nextKey]) {
                [seen addObject:nextKey];
                [queue addObject:@[edge.toSpec, @(depth + 1), @(nextIsSequence), @(nextPendingForEach)]];
            }
        }
    }

    if (targetStates.count == 0) return nil;
    NSMutableDictionary<NSString *, NSNumber *> *distances = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *backward = [NSMutableArray array];
    for (NSString *key in targetStates) {
        distances[key] = @0;
        [backward addObject:key];
    }
    while (backward.count > 0) {
        NSString *key = backward.firstObject;
        [backward removeObjectAtIndex:0];
        NSNumber *distance = @([distances[key] unsignedIntegerValue] + 1);
        for (NSString *before in stepsInto[key]) {
            if (distances[before] == nil) {
                distances[before] = distance;
                [backward addObject:before];
            }
        }
    }
    return distances;
}

- (NSArray<CSStrand *> *)findPathsToExactTarget:(CSMediaUrn *)source
                                                   target:(CSMediaUrn *)target
                                                 maxDepth:(NSUInteger)maxDepth
                                                 maxPaths:(NSUInteger)maxPaths
                                               isSequence:(BOOL)isSequence {
    // If source already satisfies target, return empty
    if ([source isEquivalentTo:target]) {
        return @[];
    }

    // The search steps only into states the target is within reach of.
    NSDictionary<NSString *, NSNumber *> *distances = [self distancesToExactTarget:target
                                                                         fromSource:source
                                                                           maxDepth:maxDepth
                                                                         isSequence:isSequence];
    if (distances == nil) {
        return @[];
    }

    NSMutableArray<CSStrand *> *allPaths = [NSMutableArray array];
    NSMutableArray<CSStrandStep *> *currentPath = [NSMutableArray array];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];

    [self dfsFindPaths:source
                target:target
               current:source
             distances:distances
           currentPath:currentPath
               visited:visited
              allPaths:allPaths
              maxDepth:maxDepth
              maxPaths:maxPaths
            isSequence:isSequence];

    // Sort paths deterministically
    [allPaths sortUsingComparator:^NSComparisonResult(CSStrand *a, CSStrand *b) {
        return [CSLiveCapFab comparePaths:a with:b];
    }];

    return allPaths;
}

- (void)dfsFindPaths:(CSMediaUrn *)source
              target:(CSMediaUrn *)target
             current:(CSMediaUrn *)current
           distances:(NSDictionary<NSString *, NSNumber *> *)distances
         currentPath:(NSMutableArray<CSStrandStep *> *)currentPath
             visited:(NSMutableSet<NSString *> *)visited
            allPaths:(NSMutableArray<CSStrand *> *)allPaths
            maxDepth:(NSUInteger)maxDepth
            maxPaths:(NSUInteger)maxPaths
          isSequence:(BOOL)isSequence {

    if (allPaths.count >= maxPaths) return;

    BOOL pendingForEach = currentPath.count > 0 &&
        currentPath.lastObject.stepType == CSStrandStepTypeForEach;

    // A ForEach boundary is incomplete until its scalar body cap follows it.
    if ([current isEquivalentTo:target] && !pendingForEach) {
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        NSInteger capStepCount = 0;
        for (CSStrandStep *step in currentPath) {
            [titles addObject:[step title]];
            if ([step isCap]) capStepCount++;
        }

        CSStrand *path = [[CSStrand alloc] init];
        path.sourceMediaUrn = [source toString];
        path.targetMediaUrn = [target toString];
        path.steps = [currentPath copy];
        path.totalSteps = (NSInteger)currentPath.count;
        path.capStepCount = capStepCount;
        path.pathDescription = [titles componentsJoinedByString:@" → "];
        [allPaths addObject:path];
        return;
    }

    if (currentPath.count >= maxDepth) return;

    // Track (urn, isSequence) pairs to avoid infinite ForEach/Collect loops
    NSString *currentKey = [NSString stringWithFormat:@"%@|%d", [current toString], isSequence];
    [visited addObject:currentKey];

    // The steps a route through the next state has left to reach the target.
    NSUInteger stepsLeft = maxDepth - currentPath.count - 1;

    // Explore outgoing edges
    NSArray<NSDictionary *> *outEdges = [self getOutgoingEdges:current isSequence:isSequence];
    for (NSDictionary *edgeDict in outEdges) {
        CSLiveMachinePlanEdge *edge = edgeDict[@"edge"];
        if (pendingForEach && ![self canFollowForEach:edge]) {
            continue;
        }
        BOOL nextIsSequence = [edgeDict[@"isSequence"] boolValue];
        // A state the target is not within the steps left of ends nowhere: it is not entered.
        NSNumber *distance = distances[CSSearchStateKey(edge.toSpec, nextIsSequence,
                                                        edge.edgeType == CSLiveMachinePlanEdgeTypeForEach)];
        if (distance == nil || distance.unsignedIntegerValue > stepsLeft) {
            continue;
        }
        NSString *nextKey = [NSString stringWithFormat:@"%@|%d", [edge.toSpec toString], nextIsSequence];

        if (![visited containsObject:nextKey]) {
            // Convert edge type to step info
            CSStrandStep *step = [[CSStrandStep alloc] init];
            step.fromSpec = [edge.fromSpec toString];
            step.toSpec = [edge.toSpec toString];

            switch (edge.edgeType) {
                case CSLiveMachinePlanEdgeTypeCap:
                    step.stepType = CSStrandStepTypeCap;
                    step.capUrn = [edge.capUrn toString];
                    step.specificity = edge.specificity;
                    step.inputIsSequence = edge.inputIsSequence;
                    step.outputIsSequence = edge.outputIsSequence;
                    step.outputUrn = [edge.outputUrn toString];
                    break;
                case CSLiveMachinePlanEdgeTypeForEach:
                    step.stepType = CSStrandStepTypeForEach;
                    step.mediaUrn = [edge.toSpec toString];
                    break;
                case CSLiveMachinePlanEdgeTypeCollect:
                    step.stepType = CSStrandStepTypeCollect;
                    step.mediaUrn = [edge.fromSpec toString];
                    break;
            }

            [currentPath addObject:step];

            [self dfsFindPaths:source
                        target:target
                       current:edge.toSpec
                     distances:distances
                   currentPath:currentPath
                       visited:visited
                      allPaths:allPaths
                      maxDepth:maxDepth
                      maxPaths:maxPaths
                    isSequence:nextIsSequence];

            [currentPath removeLastObject];
        }
    }

    // Remove from visited for backtracking (enables multiple paths through same node)
    [visited removeObject:currentKey];
}

- (BOOL)canFollowForEach:(CSLiveMachinePlanEdge *)edge {
    return edge.edgeType == CSLiveMachinePlanEdgeTypeCap && !edge.inputIsSequence;
}

// MARK: - Path Comparison (Deterministic Ordering)

/// Sort by: cap_step_count asc, total specificity desc, then the steps compared
/// structurally in turn, the shorter path first when one is a prefix of the
/// other. No URN is compared as text.
/// Mirrors Rust: LiveCapFab::compare_paths
+ (NSComparisonResult)comparePaths:(CSStrand *)a with:(CSStrand *)b {
    // 1. Fewer cap steps first
    if (a.capStepCount != b.capStepCount) {
        return a.capStepCount < b.capStepCount ? NSOrderedAscending : NSOrderedDescending;
    }

    // 2. Higher total specificity first
    NSUInteger specA = 0, specB = 0;
    for (CSStrandStep *step in a.steps) {
        specA += step.specificity;
    }
    for (CSStrandStep *step in b.steps) {
        specB += step.specificity;
    }
    if (specA != specB) {
        return specA > specB ? NSOrderedAscending : NSOrderedDescending;
    }

    // 3. Step by step, structurally
    NSUInteger minCount = MIN(a.steps.count, b.steps.count);
    for (NSUInteger i = 0; i < minCount; i++) {
        NSComparisonResult cmp = [self compareStep:a.steps[i] with:b.steps[i]];
        if (cmp != NSOrderedSame) return cmp;
    }

    // Shorter path first if all steps match so far
    if (a.steps.count != b.steps.count) {
        return a.steps.count < b.steps.count ? NSOrderedAscending : NSOrderedDescending;
    }

    return NSOrderedSame;
}

/// A step's place in the structural step order: a cap, then a ForEach, then a Collect.
+ (NSInteger)stepRank:(CSStrandStepType)stepType {
    switch (stepType) {
        case CSStrandStepTypeCap:
            return 0;
        case CSStrandStepTypeForEach:
            return 1;
        case CSStrandStepTypeCollect:
            return 2;
    }
    [NSException raise:NSInternalInconsistencyException
                format:@"strand step invariant: no step type %ld", (long)stepType];
    return -1;
}

/// A media URN a planned step carries. The planner wrote it from a parsed URN,
/// so one that does not parse is a broken invariant.
+ (CSMediaUrn *)stepMedia:(nullable NSString *)text {
    NSError *error = nil;
    CSMediaUrn *media = text != nil ? [CSMediaUrn fromString:text error:&error] : nil;
    if (media == nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"strand step invariant: '%@' parses as a media URN: %@",
                           text, error.localizedDescription];
    }
    return media;
}

/// A cap URN a planned cap step carries; one that does not parse is a broken invariant.
+ (CSCapUrn *)stepCap:(nullable NSString *)text {
    NSError *error = nil;
    CSCapUrn *cap = text != nil ? [CSCapUrn fromString:text error:&error] : nil;
    if (cap == nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"strand step invariant: '%@' parses as a cap URN: %@",
                           text, error.localizedDescription];
    }
    return cap;
}

/// Structural comparison of two strand steps: by rank; caps by their cap URNs'
/// structural order and then the output they take (the main output, nil,
/// before a named one); ForEach and Collect by their media URN; then each
/// step's fromSpec and toSpec as media URNs.
/// Mirrors Rust: LiveCapFab::compare_steps
+ (NSComparisonResult)compareStep:(CSStrandStep *)a with:(CSStrandStep *)b {
    NSInteger rankA = [self stepRank:a.stepType];
    NSInteger rankB = [self stepRank:b.stepType];
    if (rankA != rankB) {
        return rankA < rankB ? NSOrderedAscending : NSOrderedDescending;
    }

    if (a.stepType == CSStrandStepTypeCap) {
        NSComparisonResult byCap = [[self stepCap:a.capUrn] compareStructurally:[self stepCap:b.capUrn]];
        if (byCap != NSOrderedSame) return byCap;
        if (a.outputUrn == nil || b.outputUrn == nil) {
            if (a.outputUrn != nil || b.outputUrn != nil) {
                return a.outputUrn == nil ? NSOrderedAscending : NSOrderedDescending;
            }
        } else {
            NSComparisonResult byOutput =
                [[self stepMedia:a.outputUrn] compareStructurally:[self stepMedia:b.outputUrn]];
            if (byOutput != NSOrderedSame) return byOutput;
        }
    } else {
        NSComparisonResult byMedia =
            [[self stepMedia:a.mediaUrn] compareStructurally:[self stepMedia:b.mediaUrn]];
        if (byMedia != NSOrderedSame) return byMedia;
    }

    NSComparisonResult byFrom = [[self stepMedia:a.fromSpec] compareStructurally:[self stepMedia:b.fromSpec]];
    if (byFrom != NSOrderedSame) return byFrom;
    return [[self stepMedia:a.toSpec] compareStructurally:[self stepMedia:b.toSpec]];
}

@end
