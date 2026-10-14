//
//  OrchestratorTests.swift
//  Bifaci
//
//  The steps of a machine plan as the graph an executor runs.
//
//  Tests use // TEST###: comments matching the Rust implementation for cross-tracking.

import XCTest
@testable import Bifaci
import CapDAG
import Foundation

private let extractCap = #"cap:in="media:document;ext=pdf";extract;out="media:enc=utf-8;ext=txt""#
private let summarizeCap = #"cap:in="media:enc=utf-8;ext=txt";summarize;out="media:enc=utf-8;summary""#
private let concatCap = #"cap:in="media:enc=utf-8";concat;out="media:enc=utf-8;joined""#
private let splitCap = #"cap:in="media:enc=utf-8;ext=txt";split;out="media:enc=utf-8;head""#
private let nowCap = #"cap:in="media:void";now;out="media:stamp""#
private let contextUrn = "media:context;enc=utf-8"
private let restUrn = "media:enc=utf-8;rest"

/// The smallest definition of `capUrn`: its input on stdin unless it is void,
/// and the output its URN states.
private func testCap(_ capUrn: String) throws -> CSCap {
    let urn = try CSCapUrn.fromString(capUrn)
    let cap = CSCap(urn: urn, title: "t", aliases: ["t"])
    let input = urn.getInSpec()
    if input != "media:void" {
        cap.addArg(CSCapArg(mediaUrn: input, name: "input", required: true,
                            sources: [CSArgSource.stdinSource(withMediaUrn: input)]))
    }
    cap.addOutput(CSCapOutput(mediaUrn: urn.getOutSpec(), name: "output", outputDescription: "out"))
    return cap
}

/// The caps of the tests' plans, looked up as the registry's cache is: by
/// the cap URN, compared as a URN.
final class PlanCapRegistry: FabricRegistryProtocol, @unchecked Sendable {
    private let caps: [CSCap]

    init() throws {
        let summarize = try testCap(summarizeCap)
        summarize.addArg(CSCapArg(mediaUrn: contextUrn, name: "context", required: false,
                                  sources: [CSArgSource.cliFlagSource("--context")]))
        let concat = try CSCap(urn: CSCapUrn.fromString(concatCap), title: "t", aliases: ["t"])
        concat.addArg(CSCapArg(mediaUrn: "media:enc=utf-8", name: "input", required: true,
                               sources: [CSArgSource.stdinSource(withMediaUrn: "media:enc=utf-8")]).asSequence(true))
        concat.addOutput(CSCapOutput(mediaUrn: "media:enc=utf-8;joined", name: "output", outputDescription: "out"))
        let split = try testCap(splitCap)
        split.addOutput(CSCapOutput(mediaUrn: restUrn, name: "rest", outputDescription: "the rest"))
        caps = [try testCap(extractCap), summarize, concat, split, try testCap(nowCap)]
    }

    func lookup(_ urn: String) async throws -> CSCap {
        let wanted = try CSCapUrn.fromString(urn)
        guard let cap = caps.first(where: { $0.capUrn.isEquivalent(wanted) }) else {
            throw ParseOrchestrationError.capNotFound(capUrn: urn)
        }
        return cap
    }
}

/// doc → extract → summarize (context ← now) → out; extract also feeds split,
/// whose `rest` output is taken; concat gathers summarize and rest.
private func testPlan() -> CSMachinePlan {
    let plan = CSMachinePlan(name: "convert")
    plan.addNode(CSMachineNode.inputSlotNode("doc", slotName: "input", mediaUrn: "media:document;ext=pdf", cardinality: .single))
    plan.addNode(CSMachineNode.capNode("extract", capUrn: extractCap))
    plan.addNode(CSMachineNode.capNode("summarize", capUrn: summarizeCap))
    plan.addNode(CSMachineNode.capNode("now", capUrn: nowCap))
    plan.addNode(CSMachineNode.capNode("split", capUrn: splitCap))
    plan.addNode(CSMachineNode.capOutputNode("split.rest", capNode: "split", outputMediaUrn: restUrn, outputName: "rest", carriesInput: false))
    plan.addNode(CSMachineNode.collect("both", inputNodes: ["summarize", "split.rest"], outputMediaUrn: "media:enc=utf-8"))
    plan.addNode(CSMachineNode.capNode("concat", capUrn: concatCap))
    plan.addNode(CSMachineNode.outputNode("out", outputName: "result", sourceNode: "concat"))
    plan.addEdge(CSMachinePlanEdge.direct(from: "doc", to: "extract"))
    plan.addEdge(CSMachinePlanEdge.direct(from: "extract", to: "summarize"))
    plan.addEdge(CSMachinePlanEdge.arg(from: "now", to: "summarize", argUrn: contextUrn))
    plan.addEdge(CSMachinePlanEdge.direct(from: "extract", to: "split"))
    plan.addEdge(CSMachinePlanEdge.direct(from: "split", to: "split.rest"))
    plan.addEdge(CSMachinePlanEdge.collection(from: "summarize", to: "both"))
    plan.addEdge(CSMachinePlanEdge.collection(from: "split.rest", to: "both"))
    plan.addEdge(CSMachinePlanEdge.direct(from: "both", to: "concat"))
    plan.addEdge(CSMachinePlanEdge.direct(from: "concat", to: "out"))
    precondition(plan.validate() == nil, "the fixture is a valid plan")
    return plan
}

private func stepOf(_ graph: ResolvedGraph, _ node: String, file: StaticString = #filePath, line: UInt = #line) throws -> ResolvedStep {
    guard let step = graph.steps.first(where: { $0.node == node }) else {
        XCTFail("no step '\(node)'", file: file, line: line)
        throw ParseOrchestrationError.invalidGraph("no step '\(node)'")
    }
    return step
}

/// The message of the invalid-graph refusal `body` throws.
private func invalidGraphMessage(_ body: () async throws -> ResolvedGraph, file: StaticString = #filePath, line: UInt = #line) async -> String {
    do {
        _ = try await body()
        XCTFail("expected a refusal", file: file, line: line)
    } catch ParseOrchestrationError.invalidGraph(let message) {
        return message
    } catch {
        XCTFail("expected an invalid graph, got \(error)", file: file, line: line)
    }
    return ""
}

final class OrchestratorTests: XCTestCase {

    // TEST1161: every step of a plan becomes one step of the graph, keyed by
    // its node; its main input is the stream its cap's `in=` names and a named
    // arg the stream the edge names; a step nothing is wired into has no
    // inputs; a gather is one input with its members in order; an output of a
    // step that something takes is listed with the node it is stored at.
    func test1161_aPlanConvertsToStepsWithTheirInputsAndOutputs() async throws {
        let registry = try PlanCapRegistry()
        let graph = try await planToResolvedGraph(testPlan(), registry: registry)
        XCTAssertEqual(graph.steps.count, 5)
        XCTAssertEqual(graph.graphName, "convert")

        let extract = try stepOf(graph, "extract")
        XCTAssertEqual(extract.inputs, [StepInput(streamUrn: "media:document;ext=pdf", source: .node("doc"))])
        XCTAssertEqual(extract.outputs, [])
        XCTAssertEqual(extract.outMedia, "media:enc=utf-8;ext=txt")

        XCTAssertEqual(try stepOf(graph, "summarize").inputs, [
            StepInput(streamUrn: "media:enc=utf-8;ext=txt", source: .node("extract")),
            StepInput(streamUrn: contextUrn, source: .node("now")),
        ])

        XCTAssertEqual(try stepOf(graph, "now").inputs, [], "a source is sent no stream")

        let split = try stepOf(graph, "split")
        XCTAssertEqual(split.outputs, [StepOutput(outputMediaUrn: restUrn, node: "split.rest")])
        XCTAssertEqual(split.producedNodes, ["split", "split.rest"])

        let concat = try stepOf(graph, "concat")
        XCTAssertEqual(concat.inputs, [StepInput(streamUrn: "media:enc=utf-8", source: .gather(["summarize", "split.rest"]))])
        XCTAssertEqual(concat.sourceNodes, ["summarize", "split.rest"])

        // Every node a step reads or produces has its media; the plan's input
        // is there as what the graph is given.
        XCTAssertEqual(graph.nodes["doc"], "media:document;ext=pdf")
        XCTAssertEqual(graph.nodes["split.rest"], restUrn)
        XCTAssertEqual(graph.nodes["concat"], "media:enc=utf-8;joined")
        XCTAssertNil(graph.nodes["both"], "a gather is an input, not a node of the graph")
        XCTAssertNil(graph.nodes["out"])

        // A step alone: what it produces has its media whether or not a step
        // of the graph reads it, and what it reads is what the graph is given.
        let alone = try await stepsToResolvedGraph(testPlan(), stepIds: ["split"], registry: registry)
        XCTAssertEqual(alone.nodes, [
            "split": "media:enc=utf-8;head",
            "split.rest": restUrn,
            "extract": "media:enc=utf-8;ext=txt",
        ])

        // And a step that reads a step's other output from outside the graph
        // is given it under that output's own type.
        let gathering = try await stepsToResolvedGraph(testPlan(), stepIds: ["concat"], registry: registry)
        XCTAssertEqual(gathering.nodes, [
            "concat": "media:enc=utf-8;joined",
            "summarize": "media:enc=utf-8;summary",
            "split.rest": restUrn,
        ])
    }

    // TEST770: a plan with a map is not one graph, and the refusal names the
    // map; the steps of one scope of it are, with what they read from outside
    // (an item, a step of the enclosing scope) as the graph's inputs.
    func test770_aPlanWithAMapIsRunScopeByScope() async throws {
        let plan = CSMachinePlan(name: "mapped")
        plan.addNode(CSMachineNode.inputSlotNode("docs", slotName: "input", mediaUrn: "media:document;ext=pdf", cardinality: .sequence))
        plan.addNode(CSMachineNode.capNode("now", capUrn: nowCap))
        plan.addNode(CSMachineNode.forEachNode("each", sources: [CSForEachSource(node: "docs", item: "doc")], body: ["doc", "extract", "summarize"]))
        plan.addNode(CSMachineNode.itemNode("doc", foreach: "each", source: "docs", mediaUrn: "media:document;ext=pdf"))
        plan.addNode(CSMachineNode.capNode("extract", capUrn: extractCap))
        plan.addNode(CSMachineNode.capNode("summarize", capUrn: summarizeCap))
        plan.addEdge(CSMachinePlanEdge.direct(from: "docs", to: "each"))
        plan.addEdge(CSMachinePlanEdge.iteration(from: "each", to: "doc"))
        plan.addEdge(CSMachinePlanEdge.direct(from: "doc", to: "extract"))
        plan.addEdge(CSMachinePlanEdge.direct(from: "extract", to: "summarize"))
        plan.addEdge(CSMachinePlanEdge.arg(from: "now", to: "summarize", argUrn: contextUrn))
        XCTAssertNil(plan.validate())

        let registry = try PlanCapRegistry()
        let whole = await invalidGraphMessage { try await planToResolvedGraph(plan, registry: registry) }
        XCTAssertTrue(whole.contains("has a map ('each')"), whole)

        let body = try await stepsToResolvedGraph(plan, stepIds: ["extract", "summarize"], registry: registry)
        XCTAssertEqual(body.steps.count, 2)
        XCTAssertEqual(try stepOf(body, "extract").inputs.first?.source, .node("doc"))
        XCTAssertEqual(body.nodes["doc"], "media:document;ext=pdf", "the item is what the body is given")
        XCTAssertEqual(body.nodes["now"], "media:stamp", "a step of the enclosing scope is given whole")

        // Not a step, and not in the plan.
        let notStep = await invalidGraphMessage { try await stepsToResolvedGraph(plan, stepIds: ["each"], registry: registry) }
        XCTAssertEqual(notStep, "'each' is not a step of plan 'mapped'")
        let notNode = await invalidGraphMessage { try await stepsToResolvedGraph(plan, stepIds: ["nowhere"], registry: registry) }
        XCTAssertEqual(notNode, "'nowhere' is not a node of plan 'mapped'")
    }

    // TEST771: a plan that wires a step in a way no invocation can be given is
    // refused by what is wrong: two sources on one input stream (two main
    // inputs; the same arg named by two edges, however its URN is spelled), a
    // map wired straight into a step, a cap the registry does not have.
    func test771_aStepNoInvocationCanBeGivenIsRefused() async throws {
        let registry = try PlanCapRegistry()
        func refused(_ change: (CSMachinePlan) -> Void, _ expect: String, line: UInt = #line) async {
            let plan = testPlan()
            change(plan)
            let message = await invalidGraphMessage({ try await planToResolvedGraph(plan, registry: registry) }, line: line)
            XCTAssertTrue(message.contains(expect), "\(message) does not say \(expect)", line: line)
        }
        await refused({ $0.addEdge(CSMachinePlanEdge.direct(from: "now", to: "summarize")) },
                      "step 'summarize' is wired twice on input stream 'media:enc=utf-8;ext=txt'")
        // The same arg, its tags in another order.
        await refused({ $0.addEdge(CSMachinePlanEdge.arg(from: "doc", to: "summarize", argUrn: "media:enc=utf-8;context")) },
                      "step 'summarize' is wired twice on input stream")
        await refused({ $0.addEdge(CSMachinePlanEdge.iteration(from: "now", to: "summarize")) },
                      "step 'summarize' has an incoming Iteration edge from 'now'")
        await refused({ $0.addEdge(CSMachinePlanEdge.collection(from: "now", to: "summarize")) },
                      "step 'summarize' has an incoming Collection edge from 'now'")
        await refused({ $0.addEdge(CSMachinePlanEdge.arg(from: "out", to: "extract", argUrn: contextUrn)) },
                      "step 'extract' is wired from 'out', which holds no value")
        await refused({ $0.addEdge(CSMachinePlanEdge.arg(from: "doc", to: "extract", argUrn: "not a urn")) },
                      "step 'extract': input stream URN 'not a urn' is not a media URN")

        let unknown = testPlan()
        unknown.addNode(CSMachineNode.capNode("mystery", capUrn: #"cap:in="media:x";mystery;out="media:y""#))
        do {
            _ = try await planToResolvedGraph(unknown, registry: registry)
            XCTFail("a cap the registry does not have is refused")
        } catch ParseOrchestrationError.capNotFound(let capUrn) {
            XCTAssertTrue(capUrn.contains("mystery"), capUrn)
        }
    }

    // TEST953: a step's policy and its token go with it into the graph.
    func test953_aStepKeepsItsTokenAndPolicy() async throws {
        let plan = testPlan()
        let policy = CSStepPolicy(retry: 2, onError: .absent)
        let extract = try XCTUnwrap(plan.getNode("extract"))
        extract.policy = policy
        let token = try XCTUnwrap(extract.tokenId)

        let graph = try await planToResolvedGraph(plan, registry: try PlanCapRegistry())
        XCTAssertEqual(try stepOf(graph, "extract").policy, policy)
        XCTAssertEqual(try stepOf(graph, "extract").tokenId, token)
        XCTAssertTrue(try stepOf(graph, "summarize").policy.isDefault())
        XCTAssertNotEqual(try stepOf(graph, "summarize").tokenId, token, "each step has its own")
    }
}
