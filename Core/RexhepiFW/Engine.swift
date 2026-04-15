//
//  Engine.swift
//  MTRX — RexhepiFW
//
//  Six-gate scoring system for decision evaluation.
//

import Foundation

// MARK: - Scoring Engine Protocol

/// Protocol defining the interface for a six-gate scoring engine.
/// Each decision passes through all six gates to produce a composite evaluation.
protocol ScoringEngine {
    /// Evaluate a decision request through all six gates.
    /// - Parameter request: The decision request to evaluate.
    /// - Returns: A `GateScore` representing the composite result of all six gates.
    func evaluate(_ request: DecisionRequest) async throws -> GateScore

    /// Evaluate a single gate for a given request.
    /// - Parameters:
    ///   - gate: The specific gate to evaluate.
    ///   - request: The decision request context.
    /// - Returns: A `GateEvaluation` with the result.
    func evaluateGate(_ gate: Gate, for request: DecisionRequest) async throws -> GateEvaluation
}

// MARK: - Decision Request

/// Represents a decision that needs to be evaluated through the scoring pipeline.
struct DecisionRequest: Identifiable, Sendable {
    let id: UUID
    let description: String
    let context: [String: Any]
    let timestamp: Date
    let timeSensitivity: TimeSensitivity
    let source: String

    init(
        id: UUID = UUID(),
        description: String,
        context: [String: Any] = [:],
        timestamp: Date = Date(),
        timeSensitivity: TimeSensitivity = .medium,
        source: String = "user"
    ) {
        self.id = id
        self.description = description
        self.context = context
        self.timestamp = timestamp
        self.timeSensitivity = timeSensitivity
        self.source = source
    }
}

// MARK: - Gate Score

/// Composite score from all six gates, representing the full evaluation of a decision.
struct GateScore: Sendable {
    let clarityScore: Double
    let feasibilityScore: Double
    let riskScore: Double
    let uncertaintyScore: Double
    let valueScore: Double
    let loopLimitScore: Double

    let evaluations: [Gate: GateEvaluation]
    let timestamp: Date
    let overallPass: Bool

    /// Composite weighted score across all gates (0.0 - 1.0).
    var compositeScore: Double {
        let weights: [Double] = [0.20, 0.20, 0.20, 0.15, 0.15, 0.10]
        let scores = [clarityScore, feasibilityScore, riskScore, uncertaintyScore, valueScore, loopLimitScore]
        return zip(weights, scores).reduce(0.0) { $0 + $1.0 * $1.1 }
    }

    /// Returns the gates that failed evaluation.
    var failedGates: [Gate] {
        evaluations.filter { !$0.value.passed }.map { $0.key }
    }

    /// Returns true if all gates passed.
    var allGatesPassed: Bool {
        evaluations.values.allSatisfy { $0.passed }
    }
}

// MARK: - Rexhepi Engine

/// Primary implementation of the six-gate scoring engine.
/// Named after the Rexhepi framework for structured decision evaluation.
final class RexhepiEngine: ScoringEngine {

    // MARK: - Properties

    private let gateEvaluators: [Gate: GateEvaluator]
    private var timeSensitivityModifier: TimeSensitivity = .medium
    private let hardRules: HardRules

    // MARK: - Initialization

    init(hardRules: HardRules = HardRules()) {
        self.hardRules = hardRules

        // TODO: Initialize gate evaluators with production configurations
        var evaluators: [Gate: GateEvaluator] = [:]
        for gate in Gate.allCases {
            evaluators[gate] = GateEvaluator(gate: gate)
        }
        self.gateEvaluators = evaluators
    }

    // MARK: - ScoringEngine Conformance

    func evaluate(_ request: DecisionRequest) async throws -> GateScore {
        timeSensitivityModifier = request.timeSensitivity

        // Evaluate all six gates
        var evaluations: [Gate: GateEvaluation] = [:]
        for gate in Gate.allCases {
            let evaluation = try await evaluateGate(gate, for: request)
            evaluations[gate] = evaluation
        }

        // Check hard rules before finalizing
        let violations = hardRules.validate(request: request, evaluations: evaluations)
        let overallPass = violations.isEmpty && evaluations.values.allSatisfy { $0.passed }

        let gateScore = GateScore(
            clarityScore: evaluations[.clarity]?.score ?? 0.0,
            feasibilityScore: evaluations[.feasibility]?.score ?? 0.0,
            riskScore: evaluations[.risk]?.score ?? 0.0,
            uncertaintyScore: evaluations[.uncertainty]?.score ?? 0.0,
            valueScore: evaluations[.value]?.score ?? 0.0,
            loopLimitScore: evaluations[.loopLimit]?.score ?? 0.0,
            evaluations: evaluations,
            timestamp: Date(),
            overallPass: overallPass
        )

        return gateScore
    }

    func evaluateGate(_ gate: Gate, for request: DecisionRequest) async throws -> GateEvaluation {
        guard var evaluator = gateEvaluators[gate] else {
            throw EngineError.missingEvaluator(gate)
        }

        let adjustedThreshold = gate.threshold(for: timeSensitivityModifier)
        let rawScore = try await evaluator.evaluate(request: request)
        let passed = rawScore >= adjustedThreshold

        return GateEvaluation(
            gate: gate,
            score: rawScore,
            threshold: adjustedThreshold,
            passed: passed,
            reason: evaluator.lastReason,
            timestamp: Date()
        )
    }

    // MARK: - Pipeline Orchestration

    /// Runs the full scoring pipeline and determines the outcome.
    /// - Parameter request: The decision request to process.
    /// - Returns: The recommended outcome based on gate scores.
    func runPipeline(_ request: DecisionRequest) async throws -> Outcome {
        let gateScore = try await evaluate(request)
        return Outcome.determine(from: gateScore)
    }
}

// MARK: - Gate Evaluator (Internal)

/// Internal evaluator for a single gate.
struct GateEvaluator {
    let gate: Gate
    private(set) var lastReason: String = ""

    /// Evaluate the gate for a given request.
    /// - Parameter request: The decision request context.
    /// - Returns: A score between 0.0 and 1.0.
    mutating func evaluate(request: DecisionRequest) async throws -> Double {
        // TODO: Implement gate-specific evaluation logic
        // Each gate should have its own scoring algorithm based on request context
        switch gate {
        case .clarity:
            return evaluateClarity(request)
        case .feasibility:
            return evaluateFeasibility(request)
        case .risk:
            return evaluateRisk(request)
        case .uncertainty:
            return evaluateUncertainty(request)
        case .value:
            return evaluateValue(request)
        case .loopLimit:
            return evaluateLoopLimit(request)
        }
    }

    // MARK: - Gate-Specific Evaluations

    private mutating func evaluateClarity(_ request: DecisionRequest) -> Double {
        // TODO: Implement clarity scoring — how well-defined is the request?
        lastReason = "Clarity evaluation placeholder"
        return 0.5
    }

    private mutating func evaluateFeasibility(_ request: DecisionRequest) -> Double {
        // TODO: Implement feasibility scoring — can this realistically be done?
        lastReason = "Feasibility evaluation placeholder"
        return 0.5
    }

    private mutating func evaluateRisk(_ request: DecisionRequest) -> Double {
        // TODO: Implement risk scoring — what could go wrong?
        lastReason = "Risk evaluation placeholder"
        return 0.5
    }

    private mutating func evaluateUncertainty(_ request: DecisionRequest) -> Double {
        // TODO: Implement uncertainty scoring — what don't we know?
        lastReason = "Uncertainty evaluation placeholder"
        return 0.5
    }

    private mutating func evaluateValue(_ request: DecisionRequest) -> Double {
        // TODO: Implement value scoring — is this worth doing?
        lastReason = "Value evaluation placeholder"
        return 0.5
    }

    private mutating func evaluateLoopLimit(_ request: DecisionRequest) -> Double {
        // TODO: Implement loop limit scoring — are we going in circles?
        lastReason = "Loop limit evaluation placeholder"
        return 0.5
    }
}

// MARK: - Engine Errors

enum EngineError: Error, LocalizedError {
    case missingEvaluator(Gate)
    case evaluationFailed(Gate, String)
    case pipelineTimeout
    case hardRuleViolation(String)

    var errorDescription: String? {
        switch self {
        case .missingEvaluator(let gate):
            return "Missing evaluator for gate: \(gate)"
        case .evaluationFailed(let gate, let reason):
            return "Evaluation failed for gate \(gate): \(reason)"
        case .pipelineTimeout:
            return "Scoring pipeline timed out"
        case .hardRuleViolation(let rule):
            return "Hard rule violated: \(rule)"
        }
    }
}
