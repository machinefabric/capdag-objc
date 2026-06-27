//
//  CSPlanDecompositionTests.m
//  CapDAGTests
//
//  Tests for plan decomposition (standalone Collect, extract prefix/body/suffix).
//  Mirrors Rust plan.rs tests TEST934-TEST764.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSPlanDecompositionTests : XCTestCase
@end

// Helper: build plan with ForEach closed by Collect
// Topology: input_slot → cap_0 → foreach_0 --iteration--> body_cap_0 → body_cap_1 --collection--> collect_0 → cap_post → output
static CSMachinePlan *buildForeachPlanWithCollect(void) {
    CSMachinePlan *plan = [CSMachinePlan planWithName:@"ForEach test plan"];

    [plan addNode:[CSMachineNode inputSlotNode:@"input_slot" slotName:@"input" mediaUrn:@"media:ext=pdf" cardinality:CSInputCardinalitySingle]];
    [plan addNode:[CSMachineNode capNode:@"cap_0" capUrn:@"cap:in=\"media:ext=pdf\";out=media:pdf-page;list"]];
    [plan addNode:[CSMachineNode forEachNode:@"foreach_0" inputNode:@"cap_0" bodyEntry:@"body_cap_0" bodyExit:@"body_cap_1"]];
    [plan addNode:[CSMachineNode capNode:@"body_cap_0" capUrn:@"cap:in=media:pdf-page;out=\"media:enc=utf-8;text\""]];
    [plan addNode:[CSMachineNode capNode:@"body_cap_1" capUrn:@"cap:in=\"media:enc=utf-8;text\";out=\"media:decision;fmt=json;record\""]];
    [plan addNode:[CSMachineNode collectNode:@"collect_0" inputNodes:@[@"body_cap_1"]]];
    [plan addNode:[CSMachineNode capNode:@"cap_post" capUrn:@"cap:in=\"media:decision;fmt=json;record\";out=\"media:fmt=json\""]];
    [plan addNode:[CSMachineNode outputNode:@"output" outputName:@"result" sourceNode:@"cap_post"]];

    [plan addEdge:[CSMachinePlanEdge directFrom:@"input_slot" to:@"cap_0"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"cap_0" to:@"foreach_0"]];
    [plan addEdge:[CSMachinePlanEdge iterationFrom:@"foreach_0" to:@"body_cap_0"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"body_cap_0" to:@"body_cap_1"]];
    [plan addEdge:[CSMachinePlanEdge collectionFrom:@"body_cap_1" to:@"collect_0"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"collect_0" to:@"cap_post"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"cap_post" to:@"output"]];

    return plan;
}

// Helper: build plan with unclosed ForEach (no Collect)
// Topology: input_slot → cap_0 → foreach_0 --iteration--> body_cap_0 → output
static CSMachinePlan *buildForeachPlanUnclosed(void) {
    CSMachinePlan *plan = [CSMachinePlan planWithName:@"Unclosed ForEach test plan"];

    [plan addNode:[CSMachineNode inputSlotNode:@"input_slot" slotName:@"input" mediaUrn:@"media:ext=pdf" cardinality:CSInputCardinalitySingle]];
    [plan addNode:[CSMachineNode capNode:@"cap_0" capUrn:@"cap:in=\"media:ext=pdf\";out=media:pdf-page;list"]];
    [plan addNode:[CSMachineNode forEachNode:@"foreach_0" inputNode:@"cap_0" bodyEntry:@"body_cap_0" bodyExit:@"body_cap_0"]];
    [plan addNode:[CSMachineNode capNode:@"body_cap_0" capUrn:@"cap:in=media:pdf-page;out=\"media:decision;fmt=json;record\""]];
    [plan addNode:[CSMachineNode outputNode:@"output" outputName:@"result" sourceNode:@"body_cap_0"]];

    [plan addEdge:[CSMachinePlanEdge directFrom:@"input_slot" to:@"cap_0"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"cap_0" to:@"foreach_0"]];
    [plan addEdge:[CSMachinePlanEdge iterationFrom:@"foreach_0" to:@"body_cap_0"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"body_cap_0" to:@"output"]];

    return plan;
}

@implementation CSPlanDecompositionTests

// MARK: - Standalone Collect Node Tests

- (void)test6490_StandaloneCollectNode {
    // Standalone Collect: has outputMediaUrn set, single input node
    CSMachineNode *node = [CSMachineNode collectNode:@"collect_0" inputNodes:@[@"cap_0"]];
    node.outputMediaUrn = @"media:list;text";

    XCTAssertEqualObjects(node.nodeId, @"collect_0");
    XCTAssertNotNil(node.outputMediaUrn);
    XCTAssertTrue([node isFanIn]);
    XCTAssertFalse([node isCap]);
    XCTAssertFalse([node isFanOut]);
}

// TEST6523: Cap and for each are not standalone collect
- (void)test6523_CapAndForEachAreNotStandaloneCollect {
    CSMachineNode *cap = [CSMachineNode capNode:@"cap_0" capUrn:@"cap:test"];
    XCTAssertFalse([cap isFanIn]);

    CSMachineNode *forEach = [CSMachineNode forEachNode:@"fe" inputNode:@"in" bodyEntry:@"b1" bodyExit:@"b2"];
    XCTAssertFalse([forEach isFanIn]);
}

// MARK: - TEST6677: findFirstForeach detects ForEach
- (void)test6677_findFirstForeach {
    CSMachinePlan *plan = buildForeachPlanWithCollect();
    NSString *foreachId = [plan findFirstForeach];
    XCTAssertEqualObjects(foreachId, @"foreach_0");
}

// TEST935: findFirstForeach returns nil for linear plans
- (void)test935_findFirstForeachLinear {
    CSMachinePlan *plan = [CSMachinePlan linearChainPlan:@[@"cap:a", @"cap:b"]
                                                       inputMedia:@"media:ext=pdf"
                                                      outputMedia:@"media:ext=png;image"
                                                  filePathArgNames:@[@"input_a", @"input_b"]];
    XCTAssertNil([plan findFirstForeach]);
}

// TEST6678: hasForeach
- (void)test6678_hasForeach {
    CSMachinePlan *foreachPlan = buildForeachPlanWithCollect();
    XCTAssertTrue([foreachPlan hasForeach]);

    CSMachinePlan *linearPlan = [CSMachinePlan linearChainPlan:@[@"cap:a"]
                                                             inputMedia:@"media:ext=pdf"
                                                            outputMedia:@"media:ext=png;image"
                                                        filePathArgNames:@[@"input_a"]];
    XCTAssertFalse([linearPlan hasForeach]);
}

// TEST937: extractPrefixTo extracts input_slot → cap_0 as standalone plan
- (void)test937_extractPrefixTo {
    CSMachinePlan *plan = buildForeachPlanWithCollect();

    NSError *error = nil;
    CSMachinePlan *prefix = [plan extractPrefixTo:@"cap_0" error:&error];
    XCTAssertNotNil(prefix, @"extractPrefixTo should succeed: %@", error);

    // Should have: input_slot, cap_0, synthetic output
    XCTAssertEqual(prefix.nodes.count, 3u);
    XCTAssertNotNil([prefix getNode:@"input_slot"]);
    XCTAssertNotNil([prefix getNode:@"cap_0"]);
    XCTAssertNotNil([prefix getNode:@"cap_0_prefix_output"]);
    XCTAssertEqual(prefix.entryNodes.count, 1u);
    XCTAssertEqual(prefix.outputNodes.count, 1u);
    XCTAssertNil([prefix validate]);

    // Topological order works (no cycles)
    NSArray *order = [prefix topologicalOrder:&error];
    XCTAssertNotNil(order);
    XCTAssertEqual(order.count, 3u);
}

// TEST754: extractPrefixTo with nonexistent node returns error
- (void)test754_extractPrefixNonexistent {
    CSMachinePlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSMachinePlan *result = [plan extractPrefixTo:@"nonexistent" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

// TEST755: extractForeachBody extracts body with synthetic I/O
- (void)test755_extractForeachBody {
    CSMachinePlan *plan = buildForeachPlanWithCollect();

    NSError *error = nil;
    CSMachinePlan *body = [plan extractForeachBody:@"foreach_0" itemMediaUrn:@"media:pdf-page" error:&error];
    XCTAssertNotNil(body, @"extractForeachBody should succeed: %@", error);

    // Should have: synthetic input, body_cap_0, body_cap_1, synthetic output
    XCTAssertEqual(body.nodes.count, 4u);
    XCTAssertNotNil([body getNode:@"foreach_0_body_input"]);
    XCTAssertNotNil([body getNode:@"body_cap_0"]);
    XCTAssertNotNil([body getNode:@"body_cap_1"]);
    XCTAssertNotNil([body getNode:@"foreach_0_body_output"]);
    XCTAssertEqual(body.entryNodes.count, 1u);
    XCTAssertEqual(body.outputNodes.count, 1u);
    XCTAssertNil([body validate]);

    // Should NOT contain ForEach or Collect
    XCTAssertFalse([body hasForeach]);

    // Verify synthetic InputSlot has item media URN
    CSMachineNode *inputNode = [body getNode:@"foreach_0_body_input"];
    XCTAssertEqualObjects(inputNode.expectedMediaUrn, @"media:pdf-page");
    XCTAssertEqual(inputNode.cardinality, CSInputCardinalitySingle);

    // Topological order
    NSArray *order = [body topologicalOrder:&error];
    XCTAssertNotNil(order);
    XCTAssertEqual(order.count, 4u);
}

// TEST756: extractForeachBody for unclosed ForEach (single body cap)
- (void)test756_extractForeachBodyUnclosed {
    CSMachinePlan *plan = buildForeachPlanUnclosed();

    NSError *error = nil;
    CSMachinePlan *body = [plan extractForeachBody:@"foreach_0" itemMediaUrn:@"media:pdf-page" error:&error];
    XCTAssertNotNil(body, @"should succeed: %@", error);

    // Should have: synthetic input, body_cap_0, synthetic output
    XCTAssertEqual(body.nodes.count, 3u);
    XCTAssertNotNil([body getNode:@"foreach_0_body_input"]);
    XCTAssertNotNil([body getNode:@"body_cap_0"]);
    XCTAssertNotNil([body getNode:@"foreach_0_body_output"]);
    XCTAssertNil([body validate]);
    XCTAssertFalse([body hasForeach]);
}

// TEST757: extractForeachBody fails for non-ForEach node
- (void)test757_extractForeachBodyWrongType {
    CSMachinePlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSMachinePlan *result = [plan extractForeachBody:@"cap_0" itemMediaUrn:@"media:pdf-page" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"not a ForEach"],
                  @"Error should mention 'not a ForEach': %@", error.localizedDescription);
}

// TEST758: extractSuffixFrom extracts collect → cap_post → output
- (void)test758_extractSuffixFrom {
    CSMachinePlan *plan = buildForeachPlanWithCollect();

    NSError *error = nil;
    CSMachinePlan *suffix = [plan extractSuffixFrom:@"collect_0" sourceMediaUrn:@"media:decision;fmt=json;record" error:&error];
    XCTAssertNotNil(suffix, @"should succeed: %@", error);

    // Should have: synthetic input, cap_post, output
    XCTAssertEqual(suffix.nodes.count, 3u);
    XCTAssertNotNil([suffix getNode:@"collect_0_suffix_input"]);
    XCTAssertNotNil([suffix getNode:@"cap_post"]);
    XCTAssertNotNil([suffix getNode:@"output"]);
    XCTAssertEqual(suffix.entryNodes.count, 1u);
    XCTAssertEqual(suffix.outputNodes.count, 1u);
    XCTAssertNil([suffix validate]);

    // Should not contain ForEach/Collect
    XCTAssertFalse([suffix hasForeach]);
}

// TEST759: extractSuffixFrom fails for nonexistent node
- (void)test759_extractSuffixNonexistent {
    CSMachinePlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSMachinePlan *result = [plan extractSuffixFrom:@"nonexistent" sourceMediaUrn:@"media:whatever" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

// TEST6641: Full decomposition covers all cap nodes
- (void)test6641_decompositionCoversAllCaps {
    CSMachinePlan *plan = buildForeachPlanWithCollect();

    // Get all original cap node IDs
    NSMutableSet *originalCaps = [NSMutableSet set];
    for (NSString *nodeId in plan.nodes) {
        CSMachineNode *node = plan.nodes[nodeId];
        if ([node isCap]) {
            [originalCaps addObject:nodeId];
        }
    }
    XCTAssertEqual(originalCaps.count, 4u); // cap_0, body_cap_0, body_cap_1, cap_post

    NSError *error = nil;
    CSMachinePlan *prefix = [plan extractPrefixTo:@"cap_0" error:&error];
    CSMachinePlan *body = [plan extractForeachBody:@"foreach_0" itemMediaUrn:@"media:pdf-page" error:&error];
    CSMachinePlan *suffix = [plan extractSuffixFrom:@"collect_0" sourceMediaUrn:@"media:decision;fmt=json;record" error:&error];

    XCTAssertNotNil(prefix);
    XCTAssertNotNil(body);
    XCTAssertNotNil(suffix);

    // Collect cap nodes from each sub-plan
    NSMutableSet *allCaps = [NSMutableSet set];
    for (NSString *nodeId in prefix.nodes) {
        if ([prefix.nodes[nodeId] isCap]) [allCaps addObject:nodeId];
    }
    for (NSString *nodeId in body.nodes) {
        if ([body.nodes[nodeId] isCap]) [allCaps addObject:nodeId];
    }
    for (NSString *nodeId in suffix.nodes) {
        if ([suffix.nodes[nodeId] isCap]) [allCaps addObject:nodeId];
    }

    XCTAssertEqualObjects(allCaps, originalCaps,
                          @"Decomposition should cover all cap nodes");
}

// TEST6642: Prefix is valid DAG
- (void)test6642_prefixIsDag {
    CSMachinePlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSMachinePlan *prefix = [plan extractPrefixTo:@"cap_0" error:&error];
    XCTAssertNotNil(prefix);
    XCTAssertNotNil([prefix topologicalOrder:&error]);
}

// TEST6643: Body is valid DAG
- (void)test6643_bodyIsDag {
    CSMachinePlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSMachinePlan *body = [plan extractForeachBody:@"foreach_0" itemMediaUrn:@"media:pdf-page" error:&error];
    XCTAssertNotNil(body);
    XCTAssertNotNil([body topologicalOrder:&error]);
}

// TEST6644: Suffix is valid DAG
- (void)test6644_suffixIsDag {
    CSMachinePlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSMachinePlan *suffix = [plan extractSuffixFrom:@"collect_0" sourceMediaUrn:@"media:decision;fmt=json;record" error:&error];
    XCTAssertNotNil(suffix);
    XCTAssertNotNil([suffix topologicalOrder:&error]);
}

// TEST764: extractPrefixTo with InputSlot as target (trivial prefix)
- (void)test764_prefixToInputSlot {
    CSMachinePlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSMachinePlan *prefix = [plan extractPrefixTo:@"input_slot" error:&error];
    XCTAssertNotNil(prefix, @"should succeed: %@", error);

    // Should have: input_slot + synthetic output
    XCTAssertEqual(prefix.nodes.count, 2u);
    XCTAssertNil([prefix validate]);
}

@end
