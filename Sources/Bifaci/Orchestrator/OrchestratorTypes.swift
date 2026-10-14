//
//  OrchestratorTypes.swift
//  Bifaci
//
//  The graph an executor runs: the steps of a machine plan with the cap
//  definitions they run, wired by the nodes they read and produce.
//  Mirrors Rust: src/orchestrator/types.rs

import Foundation
@preconcurrency import CapDAG

// MARK: - Error Types

/// Errors that can occur turning a plan into a graph
public enum ParseOrchestrationError: Error, Equatable {
    /// Cap URN not found in registry
    case capNotFound(capUrn: String)

    /// The plan or graph is not one that can be run as asked
    case invalidGraph(String)
}

extension ParseOrchestrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .capNotFound(let capUrn):
            return "Cap URN '\(capUrn)' not found in registry"
        case .invalidGraph(let message):
            return "Invalid graph: \(message)"
        }
    }
}

// MARK: - IR Structures

/// What one input of a step is sent: one node's value as it is, or several
/// nodes' values gathered, in order, into one sequence — a single value
/// contributes one item, a sequence its items. A gather with no members is an
/// empty sequence.
public enum StepSource: Equatable, Sendable {
    case node(String)
    case gather([String])

    /// Every node this source reads, in order.
    public var nodes: [String] {
        switch self {
        case .node(let node): return [node]
        case .gather(let members): return members
        }
    }
}

/// One input stream of a step.
public struct StepInput: Equatable, Sendable {
    /// The URN the stream is delivered under: the cap's `in=` for its main
    /// input, the arg's stream URN for any other. A cartridge tells its inputs
    /// apart by this.
    public let streamUrn: String
    public let source: StepSource

    public init(streamUrn: String, source: StepSource) {
        self.streamUrn = streamUrn
        self.source = source
    }
}

/// An output of a step other than its main one that something takes.
public struct StepOutput: Equatable, Sendable {
    /// The output's media URN in the cap's definition: what its response
    /// stream names.
    public let outputMediaUrn: String
    /// The node its value is stored at.
    public let node: String

    public init(outputMediaUrn: String, node: String) {
        self.outputMediaUrn = outputMediaUrn
        self.node = node
    }
}

/// One step of a resolved graph: one invocation of a cap.
public struct ResolvedStep: Equatable {
    /// The stable per-step identity carried from the plan's Cap node: the key
    /// by which a run's live progress maps back to the graph element a client
    /// rendered.
    public let tokenId: CSStepToken
    /// The step's node: where its MAIN output is stored.
    public let node: String
    /// Cap URN string
    public let capUrn: String
    /// Resolved cap definition
    public let cap: CSCap
    /// The streams the step is sent, besides the values its args are given by
    /// the run. None for a step nothing is wired into.
    public let inputs: [StepInput]
    /// The outputs other than the main one that something takes.
    public let outputs: [StepOutput]
    /// The media URN of the main output, from the cap definition.
    public let outMedia: String
    /// What the step does when it fails.
    public let policy: CSStepPolicy

    public init(tokenId: CSStepToken, node: String, capUrn: String, cap: CSCap,
                inputs: [StepInput], outputs: [StepOutput], outMedia: String, policy: CSStepPolicy) {
        self.tokenId = tokenId
        self.node = node
        self.capUrn = capUrn
        self.cap = cap
        self.inputs = inputs
        self.outputs = outputs
        self.outMedia = outMedia
        self.policy = policy
    }

    /// Every node the step reads, in input order.
    public var sourceNodes: [String] {
        inputs.flatMap { $0.source.nodes }
    }

    /// Every node the step produces: its own, then its other taken outputs'.
    public var producedNodes: [String] {
        [node] + outputs.map { $0.node }
    }

    public static func == (lhs: ResolvedStep, rhs: ResolvedStep) -> Bool {
        return lhs.tokenId == rhs.tokenId &&
               lhs.node == rhs.node &&
               lhs.capUrn == rhs.capUrn &&
               lhs.inputs == rhs.inputs &&
               lhs.outputs == rhs.outputs &&
               lhs.outMedia == rhs.outMedia &&
               lhs.policy == rhs.policy
    }
}

/// Steps with the cap definitions they run, wired by the nodes they read and
/// produce. A node no step of the graph produces is an input of the graph:
/// its value is supplied when the graph is run.
public struct ResolvedGraph: Equatable {
    /// Map from a node name to the media URN it holds
    public var nodes: [String: String]
    /// The steps, in the order they were asked for
    public var steps: [ResolvedStep]
    /// The name of the plan the graph came from
    public var graphName: String?

    public init(nodes: [String: String] = [:], steps: [ResolvedStep] = [], graphName: String? = nil) {
        self.nodes = nodes
        self.steps = steps
        self.graphName = graphName
    }
}

// MARK: - Cap Registry Protocol

/// Protocol for Cap registry abstraction
///
/// This allows dependency injection and testing without network access
public protocol FabricRegistryProtocol: Sendable {
    /// Look up a cap by URN. A cap the registry does not have is
    /// `ParseOrchestrationError.capNotFound`.
    func lookup(_ urn: String) async throws -> CSCap
}
