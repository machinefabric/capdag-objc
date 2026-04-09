//
//  CSLiveCapGraph.m
//  CapDAG
//
//  Precomputed capability graph for path finding.
//  Mirrors Rust: src/planner/live_cap_graph.rs (1466 lines)
//

#import "CSLiveCapGraph.h"
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
          outputIsSequence:(BOOL)outputIsSeq {
    CSLiveMachinePlanEdge *edge = [[CSLiveMachinePlanEdge alloc] init];
    edge.fromSpec = from;
    edge.toSpec = to;
    edge.edgeType = CSLiveMachinePlanEdgeTypeCap;
    edge.capUrn = capUrn;
    edge.capTitle = title;
    edge.specificity = specificity;
    edge.inputIsSequence = inputIsSeq;
    edge.outputIsSequence = outputIsSeq;
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
// CSLiveCapGraph
// =============================================================================

@interface CSLiveCapGraph ()
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
@end

@implementation CSLiveCapGraph

+ (instancetype)graph {
    CSLiveCapGraph *graph = [[CSLiveCapGraph alloc] init];
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
               registry:(id<CSCapRegistryProtocol>)registry
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

    NSString *fromCanonical = [fromSpec toString];
    NSString *toCanonical = [toSpec toString];
    NSString *capCanonical = [cap.capUrn toString];

    // Determine input/output is_sequence from cap arg/output definitions
    // Main input arg: the one with a stdin source
    BOOL inputIsSeq = NO;
    for (CSCapArg *arg in cap.args) {
        for (CSArgSource *source in arg.sources) {
            if (source.stdinMediaUrn != nil) {
                inputIsSeq = arg.isSequence;
                break;
            }
        }
        if (inputIsSeq) break;
    }
    BOOL outputIsSeq = cap.output ? cap.output.isSequence : NO;

    // Create edge
    NSUInteger edgeIdx = self.edges.count;
    CSLiveMachinePlanEdge *edge = [CSLiveMachinePlanEdge capEdgeFrom:fromSpec
                                                  to:toSpec
                                              capUrn:cap.capUrn
                                               title:cap.title
                                         specificity:(NSUInteger)[cap.capUrn specificity]
                                    inputIsSequence:inputIsSeq
                                   outputIsSequence:outputIsSeq];
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

// MARK: - Outgoing Edges (conformsTo matching)

/// Get all outgoing edges from source, with cardinality transitions synthesized dynamically.
/// Cap edges are matched purely on conformsTo. ForEach/Collect are synthesized based on isSequence.
/// Returns array of dictionaries with @"edge" (CSLiveMachinePlanEdge) and @"isSequence" (NSNumber BOOL).
- (NSArray<NSDictionary *> *)getOutgoingEdges:(CSMediaUrn *)source isSequence:(BOOL)isSequence {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];

    for (CSLiveMachinePlanEdge *edge in self.edges) {
        NSAssert(edge.edgeType == CSLiveMachinePlanEdgeTypeCap,
                 @"Non-cap edge found in graph storage: %@", edge);
        if (![source conformsTo:edge.fromSpec]) continue;

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
            if (!edge.inputIsSequence && [source conformsTo:edge.fromSpec]) {
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
    // Visited tracks (urn, isSequence) pairs to avoid infinite loops through ForEach/Collect
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    // Queue entries: [CSMediaUrn, NSNumber(depth), NSNumber(isSequence)]
    NSMutableArray<NSArray *> *queue = [NSMutableArray array];

    NSString *sourceKey = [NSString stringWithFormat:@"%@|%d", [source toString], isSequence];
    [queue addObject:@[source, @0, @(isSequence)]];
    [visited addObject:sourceKey];

    while (queue.count > 0) {
        NSArray *item = queue.firstObject;
        [queue removeObjectAtIndex:0];

        CSMediaUrn *current = item[0];
        NSUInteger depth = [item[1] unsignedIntegerValue];
        BOOL currentIsSequence = [item[2] boolValue];

        if (depth >= maxDepth) continue;

        NSArray<NSDictionary *> *outEdges = [self getOutgoingEdges:current isSequence:currentIsSequence];
        for (NSDictionary *edgeDict in outEdges) {
            CSLiveMachinePlanEdge *edge = edgeDict[@"edge"];
            BOOL nextIsSequence = [edgeDict[@"isSequence"] boolValue];
            NSUInteger newDepth = depth + 1;
            NSString *outputCanonical = [edge.toSpec toString];

            // Record this target
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

            // Continue BFS if not visited (track isSequence state)
            NSString *nextKey = [NSString stringWithFormat:@"%@|%d", outputCanonical, nextIsSequence];
            if (![visited containsObject:nextKey]) {
                [visited addObject:nextKey];
                [queue addObject:@[edge.toSpec, @(newDepth), @(nextIsSequence)]];
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

- (NSArray<CSStrand *> *)findPathsToExactTarget:(CSMediaUrn *)source
                                                   target:(CSMediaUrn *)target
                                                 maxDepth:(NSUInteger)maxDepth
                                                 maxPaths:(NSUInteger)maxPaths
                                               isSequence:(BOOL)isSequence {
    // If source already satisfies target, return empty
    if ([source isEquivalentTo:target]) {
        return @[];
    }

    NSMutableArray<CSStrand *> *allPaths = [NSMutableArray array];
    NSMutableArray<CSStrandStep *> *currentPath = [NSMutableArray array];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];

    [self dfsFindPaths:source
                target:target
               current:source
           currentPath:currentPath
               visited:visited
              allPaths:allPaths
              maxDepth:maxDepth
              maxPaths:maxPaths
            isSequence:isSequence];

    // Sort paths deterministically
    [allPaths sortUsingComparator:^NSComparisonResult(CSStrand *a, CSStrand *b) {
        return [CSLiveCapGraph comparePaths:a with:b];
    }];

    return allPaths;
}

- (void)dfsFindPaths:(CSMediaUrn *)source
              target:(CSMediaUrn *)target
             current:(CSMediaUrn *)current
         currentPath:(NSMutableArray<CSStrandStep *> *)currentPath
             visited:(NSMutableSet<NSString *> *)visited
            allPaths:(NSMutableArray<CSStrand *> *)allPaths
            maxDepth:(NSUInteger)maxDepth
            maxPaths:(NSUInteger)maxPaths
          isSequence:(BOOL)isSequence {

    if (allPaths.count >= maxPaths) return;

    // Check if we reached the EXACT target using isEquivalentTo:
    if ([current isEquivalentTo:target]) {
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        NSInteger capStepCount = 0;
        for (CSStrandStep *step in currentPath) {
            [titles addObject:[step title]];
            if ([step isCap]) capStepCount++;
        }

        CSStrand *path = [[CSStrand alloc] init];
        path.sourceSpec = [source toString];
        path.targetSpec = [target toString];
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

    // Explore outgoing edges
    NSArray<NSDictionary *> *outEdges = [self getOutgoingEdges:current isSequence:isSequence];
    for (NSDictionary *edgeDict in outEdges) {
        CSLiveMachinePlanEdge *edge = edgeDict[@"edge"];
        BOOL nextIsSequence = [edgeDict[@"isSequence"] boolValue];
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

// MARK: - Path Comparison (Deterministic Ordering)

/// Sort by: cap_step_count asc, total specificity desc, step keys lex
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

    // 3. Lexicographic by step keys
    NSUInteger minCount = MIN(a.steps.count, b.steps.count);
    for (NSUInteger i = 0; i < minCount; i++) {
        NSString *keyA = [self stepKey:a.steps[i]];
        NSString *keyB = [self stepKey:b.steps[i]];
        NSComparisonResult cmp = [keyA compare:keyB];
        if (cmp != NSOrderedSame) return cmp;
    }

    // Shorter path first if all keys match so far
    if (a.steps.count != b.steps.count) {
        return a.steps.count < b.steps.count ? NSOrderedAscending : NSOrderedDescending;
    }

    return NSOrderedSame;
}

+ (NSString *)stepKey:(CSStrandStep *)step {
    switch (step.stepType) {
        case CSStrandStepTypeCap:
            return step.capUrn ?: @"";
        case CSStrandStepTypeForEach:
            return @"foreach";
        case CSStrandStepTypeCollect:
            return @"collect";
    }
}

@end
