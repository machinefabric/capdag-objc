//
//  CSPlanTests.m
//  CapDAGTests
//
//  The plan model: its nodes and edges, the maps a node runs in, and the
//  plans it refuses. Mirrors Rust plan.rs tests.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSPlanTests : XCTestCase
@end

// input_slot → cap_0 → foreach_0 (item foreach_0_item_0) → body_cap_0 →
// body_cap_1 → cap_post → output. The body is the item and the two body caps.
static CSMachinePlan *buildForeachPlan(void) {
    CSMachinePlan *plan = [CSMachinePlan planWithName:@"ForEach test plan"];
    [plan addNode:[CSMachineNode inputSlotNode:@"input_slot" slotName:@"input" mediaUrn:@"media:document;ext=pdf" cardinality:CSInputCardinalitySingle]];
    [plan addNode:[CSMachineNode capNode:@"cap_0" capUrn:@"cap:in=\"media:document;ext=pdf\";out=\"media:pdf-page;list\""]];
    [plan addNode:[CSMachineNode forEachNode:@"foreach_0"
                                     sources:@[[CSForEachSource sourceWithNode:@"cap_0" item:@"foreach_0_item_0"]]
                                        body:@[@"foreach_0_item_0", @"body_cap_0", @"body_cap_1"]]];
    [plan addNode:[CSMachineNode itemNode:@"foreach_0_item_0" foreach:@"foreach_0" source:@"cap_0" mediaUrn:@"media:pdf-page"]];
    [plan addNode:[CSMachineNode capNode:@"body_cap_0" capUrn:@"cap:in=media:pdf-page;out=\"media:enc=utf-8;text\""]];
    [plan addNode:[CSMachineNode capNode:@"body_cap_1" capUrn:@"cap:in=\"media:enc=utf-8;text\";out=\"media:decision;fmt=json;record\""]];
    [plan addNode:[CSMachineNode capNode:@"cap_post" capUrn:@"cap:in=\"media:decision;fmt=json;record\";out=\"media:fmt=json\""]];
    [plan addNode:[CSMachineNode outputNode:@"output" outputName:@"result" sourceNode:@"cap_post"]];

    [plan addEdge:[CSMachinePlanEdge directFrom:@"input_slot" to:@"cap_0"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"cap_0" to:@"foreach_0"]];
    [plan addEdge:[CSMachinePlanEdge iterationFrom:@"foreach_0" to:@"foreach_0_item_0"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"foreach_0_item_0" to:@"body_cap_0"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"body_cap_0" to:@"body_cap_1"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"body_cap_1" to:@"cap_post"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"cap_post" to:@"output"]];
    return plan;
}

@implementation CSPlanTests

// TEST728: Tests MachineNode helper methods for identifying node types (cap, fan-out, fan-in) Verifies is_cap(), is_fan_out(), is_fan_in(), and cap_urn() correctly classify node types
- (void)test728_capNodeHelpers {
    CSMachineNode *capNode = [CSMachineNode capNode:@"test" capUrn:@"cap:test"];
    XCTAssertTrue([capNode isCap]);
    XCTAssertFalse([capNode isFanOut]);
    XCTAssertFalse([capNode isFanIn]);
    XCTAssertEqualObjects(capNode.capUrn, @"cap:test");

    CSMachineNode *foreachNode = [CSMachineNode forEachNode:@"foreach"
                                                    sources:@[[CSForEachSource sourceWithNode:@"input" item:@"item"]]
                                                       body:@[@"item", @"body"]];
    XCTAssertFalse([foreachNode isCap]);
    XCTAssertTrue([foreachNode isFanOut]);
    XCTAssertFalse([foreachNode isFanIn]);
    XCTAssertNil(foreachNode.capUrn);

    CSMachineNode *collectNode = [CSMachineNode collectNode:@"collect" inputNodes:@[@"a"] outputMediaUrn:@"media:"];
    XCTAssertFalse([collectNode isCap]);
    XCTAssertFalse([collectNode isFanOut]);
    XCTAssertTrue([collectNode isFanIn]);
}

// TEST729: Tests creation and classification of different edge types (Direct, Iteration, Collection, Arg) Verifies that edge constructors produce correct EdgeType variants
- (void)test729_edgeTypes {
    CSMachinePlanEdge *direct = [CSMachinePlanEdge directFrom:@"a" to:@"b"];
    XCTAssertEqual(direct.edgeType, CSEdgeTypeDirect);
    XCTAssertEqual([CSMachinePlanEdge iterationFrom:@"foreach" to:@"body"].edgeType, CSEdgeTypeIteration);
    XCTAssertEqual([CSMachinePlanEdge collectionFrom:@"body" to:@"collect"].edgeType, CSEdgeTypeCollection);

    CSMachinePlanEdge *arg = [CSMachinePlanEdge argFrom:@"a" to:@"b" argUrn:@"media:data"];
    XCTAssertEqual(arg.edgeType, CSEdgeTypeArg);
    XCTAssertEqualObjects(arg.argUrn, @"media:data");
    XCTAssertNil(direct.argUrn, @"only an arg edge names an argument");
}

// TEST6635: A map and its body sort in the order a run meets them: the
// sequence, the map, the item the body is given, then the body's step. The
// iteration edge from a map to its item is a dependency like any other.
- (void)test6635_aMapPrecedesItsItemAndItsBody {
    CSMachinePlan *plan = [CSMachinePlan planWithName:@"edge_kind_test"];
    [plan addNode:[CSMachineNode inputSlotNode:@"input" slotName:@"input" mediaUrn:@"media:document;ext=pdf" cardinality:CSInputCardinalitySingle]];
    [plan addNode:[CSMachineNode capNode:@"cap_0" capUrn:@"cap:in=media:pdf;disbind;out=media:pdf-page"]];
    [plan addNode:[CSMachineNode forEachNode:@"foreach_0"
                                     sources:@[[CSForEachSource sourceWithNode:@"cap_0" item:@"page"]]
                                        body:@[@"page", @"body_cap"]]];
    [plan addNode:[CSMachineNode itemNode:@"page" foreach:@"foreach_0" source:@"cap_0" mediaUrn:@"media:pdf-page"]];
    [plan addNode:[CSMachineNode capNode:@"body_cap" capUrn:@"cap:in=media:pdf-page;process;out=media:text"]];
    [plan addNode:[CSMachineNode outputNode:@"output" outputName:@"result" sourceNode:@"body_cap"]];

    [plan addEdge:[CSMachinePlanEdge directFrom:@"input" to:@"cap_0"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"cap_0" to:@"foreach_0"]];
    [plan addEdge:[CSMachinePlanEdge iterationFrom:@"foreach_0" to:@"page"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"page" to:@"body_cap"]];
    [plan addEdge:[CSMachinePlanEdge directFrom:@"body_cap" to:@"output"]];
    XCTAssertNil([plan validate]);

    NSError *error = nil;
    NSArray<CSMachineNode *> *order = [plan topologicalOrder:&error];
    XCTAssertNotNil(order, @"a plan with a map is sortable: %@", error);
    NSUInteger (^pos)(NSString *) = ^NSUInteger(NSString *nodeId) {
        return [order indexOfObjectPassingTest:^BOOL(CSMachineNode *node, NSUInteger idx, BOOL *stop) {
            return [node.nodeId isEqualToString:nodeId];
        }];
    };
    XCTAssertLessThan(pos(@"cap_0"), pos(@"foreach_0"), @"the sequence precedes the map over it");
    XCTAssertLessThan(pos(@"foreach_0"), pos(@"page"), @"the map precedes its item");
    XCTAssertLessThan(pos(@"page"), pos(@"body_cap"), @"the item precedes the step it is given to");
}

// TEST936: has_foreach detects a map, and a gather alone is not one.
- (void)test936_hasForeach {
    CSMachinePlan *foreachPlan = buildForeachPlan();
    XCTAssertNil([foreachPlan validate], @"the fixture is a valid plan");
    XCTAssertTrue([foreachPlan hasForeach]);

    CSMachinePlan *linearPlan = [CSMachinePlan linearChainPlan:@[@"cap:a"]
                                                    inputMedia:@"media:document;ext=pdf"
                                                   outputMedia:@"media:ext=png;image"
                                              filePathArgNames:@[@"input_a"]];
    XCTAssertFalse([linearPlan hasForeach]);

    CSMachinePlan *gatherPlan = [CSMachinePlan planWithName:@"gather_only"];
    [gatherPlan addNode:[CSMachineNode inputSlotNode:@"input" slotName:@"input" mediaUrn:@"media:enc=utf-8" cardinality:CSInputCardinalitySingle]];
    [gatherPlan addNode:[CSMachineNode capNode:@"cap_0" capUrn:@"cap:in=\"media:enc=utf-8\";summarize;out=media:summary"]];
    [gatherPlan addNode:[CSMachineNode collectNode:@"collect_0" inputNodes:@[@"cap_0"] outputMediaUrn:@"media:summary"]];
    [gatherPlan addNode:[CSMachineNode outputNode:@"output" outputName:@"result" sourceNode:@"collect_0"]];
    XCTAssertNil([gatherPlan validate]);
    XCTAssertFalse([gatherPlan hasForeach]);
}

// TEST12753: a plan says which map each node runs in — the map whose body
// lists it — and which nodes are inside a map at any depth.
- (void)test12753_aPlanSaysWhichMapANodeRunsIn {
    CSMachinePlan *plan = buildForeachPlan();
    NSDictionary<NSString *, NSString *> *enclosing = [plan enclosingMaps];
    XCTAssertEqualObjects(enclosing[@"body_cap_0"], @"foreach_0");
    XCTAssertEqualObjects(enclosing[@"body_cap_1"], @"foreach_0");
    XCTAssertEqualObjects(enclosing[@"foreach_0_item_0"], @"foreach_0");
    for (NSString *outside in @[@"input_slot", @"cap_0", @"foreach_0", @"cap_post", @"output"]) {
        XCTAssertNil(enclosing[outside], @"%@ is the machine's own", outside);
    }

    // A map opened inside the body: its nodes are inside the outer map, and
    // the outer body lists the inner map, not the inner body.
    [plan addNode:[CSMachineNode forEachNode:@"foreach_1"
                                     sources:@[[CSForEachSource sourceWithNode:@"body_cap_0" item:@"foreach_1_item_0"]]
                                        body:@[@"foreach_1_item_0", @"inner_cap"]]];
    [plan addNode:[CSMachineNode itemNode:@"foreach_1_item_0" foreach:@"foreach_1" source:@"body_cap_0" mediaUrn:@"media:enc=utf-8;text"]];
    [plan addNode:[CSMachineNode capNode:@"inner_cap" capUrn:@"cap:in=\"media:enc=utf-8;text\";out=media:word"]];
    CSMachineNode *outer = [plan getNode:@"foreach_0"];
    outer.body = [outer.body arrayByAddingObject:@"foreach_1"];
    XCTAssertNil([plan validate]);
    enclosing = [plan enclosingMaps];
    XCTAssertEqualObjects(enclosing[@"inner_cap"], @"foreach_1");
    XCTAssertEqualObjects(enclosing[@"foreach_1"], @"foreach_0");
    NSSet<NSString *> *inside = [plan mapMembers:@"foreach_0"];
    for (NSString *nodeId in @[@"body_cap_0", @"body_cap_1", @"foreach_0_item_0", @"foreach_1", @"foreach_1_item_0", @"inner_cap"]) {
        XCTAssertTrue([inside containsObject:nodeId], @"%@ is inside the outer map", nodeId);
    }
    XCTAssertFalse([inside containsObject:@"cap_post"]);
    XCTAssertFalse([inside containsObject:@"foreach_0"]);
    XCTAssertEqual([plan mapMembers:@"foreach_1"].count, 2u);
    XCTAssertEqual([plan mapMembers:@"cap_0"].count, 0u, @"a step is no map");
}

- (void)assertRefused:(void (^)(CSMachinePlan *plan))change saying:(NSString *)expect {
    CSMachinePlan *plan = buildForeachPlan();
    change(plan);
    NSError *error = [plan validate];
    XCTAssertNotNil(error, @"%@", expect);
    XCTAssertTrue([error.localizedDescription containsString:expect], @"'%@' does not say '%@'", error.localizedDescription, expect);
}

// TEST12754: a plan whose nodes name what is not there, or name it as what
// it is not, is refused: a map that iterates nothing, an item its map does
// not list, a node in two bodies, an output node of something that is not
// a step, a gather of a missing node.
- (void)test12754_aPlanThatNamesWhatIsNotThereIsRefused {
    CSMachineNode *(^theMap)(CSMachinePlan *) = ^CSMachineNode *(CSMachinePlan *plan) { return [plan getNode:@"foreach_0"]; };
    [self assertRefused:^(CSMachinePlan *plan) { theMap(plan).sources = @[]; } saying:@"map 'foreach_0' iterates nothing"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode forEachNode:@"lonely" sources:@[] body:@[]]];
    } saying:@"map 'lonely' iterates nothing"];
    [self assertRefused:^(CSMachinePlan *plan) { theMap(plan).sources[0].item = @"body_cap_0"; } saying:@"which is not that"];
    [self assertRefused:^(CSMachinePlan *plan) { theMap(plan).sources[0].node = @"nowhere"; }
                 saying:@"node 'foreach_0' names source 'nowhere', which is not in the plan"];
    [self assertRefused:^(CSMachinePlan *plan) { theMap(plan).sources[0].item = @"nowhere"; }
                 saying:@"node 'foreach_0' names item 'nowhere', which is not in the plan"];
    // The item it lists is an item — of another source, or of another map.
    [self assertRefused:^(CSMachinePlan *plan) { theMap(plan).sources[0].node = @"input_slot"; }
                 saying:@"map 'foreach_0' lists 'foreach_0_item_0' as its item of 'input_slot', which is not that"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode forEachNode:@"second"
                                         sources:@[[CSForEachSource sourceWithNode:@"cap_0" item:@"foreach_0_item_0"]]
                                            body:@[@"foreach_0_item_0"]]];
    } saying:@"map 'second' lists 'foreach_0_item_0' as its item of 'cap_0', which is not that"];
    [self assertRefused:^(CSMachinePlan *plan) { theMap(plan).body = @[@"body_cap_0", @"body_cap_1"]; }
                 saying:@"does not list its item 'foreach_0_item_0' in its body"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode forEachNode:@"second"
                                         sources:@[[CSForEachSource sourceWithNode:@"cap_0" item:@"second_item"]]
                                            body:@[@"second_item", @"body_cap_1"]]];
        [plan addNode:[CSMachineNode itemNode:@"second_item" foreach:@"second" source:@"cap_0" mediaUrn:@"media:pdf-page"]];
    } saying:@"node 'body_cap_1' is in the body of two maps"];
    [self assertRefused:^(CSMachinePlan *plan) { theMap(plan).body = [theMap(plan).body arrayByAddingObject:@"foreach_0"]; }
                 saying:@"map 'foreach_0' lists itself in its body"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode capOutputNode:@"o" capNode:@"input_slot" outputMediaUrn:@"media:x" outputName:@"x" carriesInput:NO]];
    } saying:@"names 'input_slot' as its step, which is not a step"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode capOutputNode:@"o" capNode:@"nowhere" outputMediaUrn:@"media:x" outputName:@"x" carriesInput:NO]];
    } saying:@"node 'o' names step 'nowhere', which is not in the plan"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode collectNode:@"g" inputNodes:@[@"nowhere"] outputMediaUrn:@"media:"]];
    } saying:@"node 'g' names gathered node 'nowhere', which is not in the plan"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode outputNode:@"o2" outputName:@"result" sourceNode:@"nowhere"]];
    } saying:@"node 'o2' names source 'nowhere', which is not in the plan"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode itemNode:@"stray" foreach:@"foreach_0" source:@"cap_0" mediaUrn:@"media:pdf-page"]];
    } saying:@"item node 'stray' names map 'foreach_0'"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode itemNode:@"stray" foreach:@"cap_0" source:@"input_slot" mediaUrn:@"media:pdf-page"]];
    } saying:@"item node 'stray' names map 'cap_0'"];
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode itemNode:@"stray" foreach:@"nowhere" source:@"cap_0" mediaUrn:@"media:pdf-page"]];
    } saying:@"node 'stray' names map 'nowhere', which is not in the plan"];
    // An item its map lists for another source: nodes are checked in the
    // order of their ids, so it is the item — which comes first — that is
    // named.
    [self assertRefused:^(CSMachinePlan *plan) {
        [plan addNode:[CSMachineNode forEachNode:@"second"
                                         sources:@[[CSForEachSource sourceWithNode:@"cap_0" item:@"an_item"]]
                                            body:@[@"an_item"]]];
        [plan addNode:[CSMachineNode itemNode:@"an_item" foreach:@"second" source:@"input_slot" mediaUrn:@"media:pdf-page"]];
    } saying:@"item node 'an_item' names map 'second' and source 'input_slot', and that map does not list it so"];
    [self assertRefused:^(CSMachinePlan *plan) { theMap(plan).body = [theMap(plan).body arrayByAddingObject:@"nowhere"]; }
                 saying:@"node 'foreach_0' names body node 'nowhere', which is not in the plan"];

    // A step's other output, of a step: accepted.
    CSMachinePlan *plan = buildForeachPlan();
    [plan addNode:[CSMachineNode capOutputNode:@"o" capNode:@"cap_0" outputMediaUrn:@"media:x" outputName:@"x" carriesInput:NO]];
    XCTAssertNil([plan validate]);
}

@end
