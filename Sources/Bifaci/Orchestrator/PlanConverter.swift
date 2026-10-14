//
//  PlanConverter.swift
//  Bifaci
//
//  Steps of a MachinePlan as a ResolvedGraph.
//  Mirrors Rust: src/orchestrator/plan_converter.rs
//
//  The plan is node-centric: steps, the values they read and produce, the
//  maps they run in. An executor runs a ResolvedGraph: steps with their cap
//  definitions, each saying which nodes its input streams are sent from and
//  which nodes its outputs are stored at. This file is the bridge.
//
//  A graph holds only steps. What else a plan has is read through them:
//
//  - an edge into a step is one of its inputs — the cap's `in=` stream for a
//    Direct edge, the named arg's stream for an Arg edge;
//  - a Collect wired into a step is that input's gather: its members, in
//    order;
//  - a CapOutput of a step is an output of it that something takes.
//
//  Maps are not in a graph at all: a map's body runs once per item, and the
//  steps of one scope are asked for at a time (`stepsToResolvedGraph`). A
//  node a graph's steps read and none of them produces is an input of the
//  graph, whatever it is in the plan — an input slot, an item, a step of
//  another scope.

import Foundation
@preconcurrency import CapDAG

/// Names an edge kind in a refusal.
private func edgeKindLabel(_ kind: CSEdgeType) -> String {
    switch kind {
    case .direct: return "Direct"
    case .arg: return "Arg"
    case .iteration: return "Iteration"
    case .collection: return "Collection"
    @unknown default: return "EdgeType(\(kind.rawValue))"
    }
}

/// Names a node kind in a refusal.
private func nodeKindLabel(_ kind: CSExecutionNodeKind) -> String {
    switch kind {
    case .cap: return "Cap"
    case .capOutput: return "CapOutput"
    case .forEach: return "ForEach"
    case .item: return "Item"
    case .collect: return "Collect"
    case .inputSlot: return "InputSlot"
    case .output: return "Output"
    @unknown default: return "ExecutionNodeKind(\(kind.rawValue))"
    }
}

private func sortedNodeIds(_ plan: CSMachinePlan) -> [String] {
    plan.nodes.allKeys.compactMap { $0 as? String }.sorted()
}

private func node(_ plan: CSMachinePlan, _ id: String) -> CSMachineNode? {
    plan.nodes[id as NSString] as? CSMachineNode
}

/// The steps `stepIds` of `plan` (ids of its Cap nodes) as a graph.
///
/// Fails when an id is not a step of the plan, when a step's cap is not in
/// the registry, or when the plan wires a step in a way no invocation can be
/// given: two sources on one stream, or a map wired straight into a step.
public func stepsToResolvedGraph(
    _ plan: CSMachinePlan,
    stepIds: [String],
    registry: any FabricRegistryProtocol
) async throws -> ResolvedGraph {
    var nodes: [String: String] = [:]
    var steps: [ResolvedStep] = []

    // A step's other taken outputs: the CapOutput nodes that name it.
    var outputsOf: [String: [StepOutput]] = [:]
    for id in sortedNodeIds(plan) {
        guard let output = node(plan, id), output.kind == .capOutput,
              let capNode = output.capNode, let media = output.outputMediaUrn else { continue }
        outputsOf[capNode, default: []].append(StepOutput(outputMediaUrn: media, node: id))
    }

    for stepId in stepIds {
        guard let step = node(plan, stepId) else {
            throw ParseOrchestrationError.invalidGraph("'\(stepId)' is not a node of plan '\(plan.name)'")
        }
        guard step.kind == .cap, let capUrn = step.capUrn, let tokenId = step.tokenId, let policy = step.policy else {
            throw ParseOrchestrationError.invalidGraph("'\(stepId)' is not a step of plan '\(plan.name)'")
        }
        let cap = try await registry.lookup(capUrn)

        // The streams the step is sent, in the order the plan wires them.
        var inputs: [StepInput] = []
        var taken: [CSMediaUrn] = []
        for case let edge as CSMachinePlanEdge in plan.edges where edge.toNode == stepId {
            let streamUrn: String
            switch edge.edgeType {
            case .direct:
                streamUrn = cap.capUrn.getInSpec()
            case .arg:
                guard let argUrn = edge.argUrn else {
                    throw ParseOrchestrationError.invalidGraph(
                        "step '\(stepId)' has an Arg edge from '\(edge.fromNode)' that names no argument")
                }
                streamUrn = argUrn
            default:
                throw ParseOrchestrationError.invalidGraph(
                    "step '\(stepId)' has an incoming \(edgeKindLabel(edge.edgeType)) edge from '\(edge.fromNode)' — a step is wired by its main input and its args only")
            }
            guard let from = node(plan, edge.fromNode) else {
                throw ParseOrchestrationError.invalidGraph(
                    "step '\(stepId)' is wired from '\(edge.fromNode)', which is not in the plan")
            }
            let source: StepSource
            switch from.kind {
            case .collect:
                source = .gather(from.inputNodes ?? [])
            case .forEach, .output:
                throw ParseOrchestrationError.invalidGraph(
                    "step '\(stepId)' is wired from '\(edge.fromNode)', which holds no value")
            default:
                source = .node(edge.fromNode)
            }
            let stream: CSMediaUrn
            do {
                stream = try CSMediaUrn.fromString(streamUrn)
            } catch {
                throw ParseOrchestrationError.invalidGraph(
                    "step '\(stepId)': input stream URN '\(streamUrn)' is not a media URN: \(error.localizedDescription)")
            }
            if taken.contains(where: { $0.isEquivalent(to: stream) }) {
                throw ParseOrchestrationError.invalidGraph(
                    "step '\(stepId)' is wired twice on input stream '\(streamUrn)' — one stream has one source; several values into one arg are a gather")
            }
            taken.append(stream)
            inputs.append(StepInput(streamUrn: streamUrn, source: source))
        }

        let outMedia = cap.capUrn.getOutSpec()
        nodes[stepId] = outMedia
        let outputs = outputsOf[stepId] ?? []
        for output in outputs {
            nodes[output.node] = output.outputMediaUrn
        }
        steps.append(ResolvedStep(tokenId: tokenId, node: stepId, capUrn: capUrn, cap: cap,
                                  inputs: inputs, outputs: outputs, outMedia: outMedia, policy: policy))
    }

    // The nodes the graph is given: what its steps read and none produces.
    for step in steps {
        for source in step.sourceNodes where nodes[source] == nil {
            guard let from = node(plan, source) else {
                throw ParseOrchestrationError.invalidGraph("a step reads '\(source)', which is not in the plan")
            }
            switch from.kind {
            case .inputSlot:
                nodes[source] = from.expectedMediaUrn
            case .item:
                nodes[source] = from.mediaUrn
            case .capOutput:
                nodes[source] = from.outputMediaUrn
            case .cap:
                guard let capUrn = from.capUrn else {
                    throw ParseOrchestrationError.invalidGraph("a step reads '\(source)', a step with no cap")
                }
                nodes[source] = try await registry.lookup(capUrn).capUrn.getOutSpec()
            default:
                throw ParseOrchestrationError.invalidGraph(
                    "a step reads '\(source)', which holds no value (\(nodeKindLabel(from.kind)))")
            }
        }
    }

    return ResolvedGraph(nodes: nodes, steps: steps, graphName: plan.name)
}

/// Every step of a plan that has no map, as one graph.
///
/// A plan with a map is not one graph: its body runs once per item. Asking
/// for it here is refused, naming the map.
public func planToResolvedGraph(
    _ plan: CSMachinePlan,
    registry: any FabricRegistryProtocol
) async throws -> ResolvedGraph {
    var stepIds: [String] = []
    for id in sortedNodeIds(plan) {
        guard let planNode = node(plan, id) else { continue }
        switch planNode.kind {
        case .cap:
            stepIds.append(id)
        case .forEach:
            throw ParseOrchestrationError.invalidGraph(
                "plan '\(plan.name)' has a map ('\(id)'): its body runs once per item and is not one graph — run its scopes one at a time")
        default:
            break
        }
    }
    return try await stepsToResolvedGraph(plan, stepIds: stepIds, registry: registry)
}
