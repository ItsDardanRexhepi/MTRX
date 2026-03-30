//
//  Outcomes.swift
//  MTRX — Omniversal
//
//  Defines the five possible outcomes: EXECUTE, PROBE, ASK, DEFER, ABORT.
//

import Foundation

// MARK: - Outcome

/// The five possible outcomes from the six-gate scoring pipeline.
/// Each outcome carries associated context explaining the decision.
enum Outcome: Sendable {

    /// Proceed with execution. All gates passed with sufficient confidence.
    case execute(context: ExecutionContext)

    /// Need more information before deciding. Specific probes are required.
    case probe(questions: [ProbeQuestion])

    /// Need explicit user input or confirmation before proceeding.
    case ask(prompt: String, options: [String])

    /// Defer the decision to a later time. Conditions not yet met.
    case defer_(reason: String, reassessAt: Date?)

    /// Abort the decision entirely. Hard rule violation or critical failure.
    case abort(reason: String, violations: [String])

    // MARK: - Determination Logic

    /// Determine the appropriate outcome based on gate scores.
    /// - Parameter gateScore: The composite gate score from the evaluation pipeline.
    /// - Returns: The recommended outcome.
    static func determine(from gateScore: GateScore) -> Outcome {
        // ABORT: Any critical failures or hard rule violations
        let criticalFailures = gateScore.evaluations.filter {
            !$0.value.passed && $0.value.failureSeverity >= .significant
        }
        if !criticalFailures.isEmpty {
            let violations = criticalFailures.map {
                "\($0.key.displayName): \($0.value.reason)"
            }
            return .abort(
                reason: "Critical gate failures detected",
                violations: violations
            )
        }

        // EXECUTE: All gates passed
        if gateScore.allGatesPassed && gateScore.compositeScore >= 0.70 {
            return .execute(context: ExecutionContext(
                confidence: gateScore.compositeScore,
                gateScore: gateScore,
                approvedAt: Date()
            ))
        }

        // ASK: Clarity gate failed — need user clarification
        if let clarityEval = gateScore.evaluations[.clarity], !clarityEval.passed {
            return .ask(
                prompt: "The request needs clarification before proceeding.",
                options: ["Provide more details", "Proceed anyway", "Cancel"]
            )
        }

        // PROBE: Uncertainty gate failed — need more data
        if let uncertaintyEval = gateScore.evaluations[.uncertainty], !uncertaintyEval.passed {
            let questions = generateProbeQuestions(from: gateScore)
            return .probe(questions: questions)
        }

        // DEFER: Value or feasibility gates are borderline
        let borderlineGates = gateScore.evaluations.filter { $0.value.isBorderline && !$0.value.passed }
        if !borderlineGates.isEmpty {
            let reassessDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            return .defer_(
                reason: "Borderline gate scores suggest waiting for better conditions",
                reassessAt: reassessDate
            )
        }

        // Default to ASK if no clear determination
        return .ask(
            prompt: "Unable to determine a clear course of action. Multiple gates require attention.",
            options: ["Review details", "Override and execute", "Cancel"]
        )
    }

    // MARK: - Probe Question Generation

    private static func generateProbeQuestions(from gateScore: GateScore) -> [ProbeQuestion] {
        var questions: [ProbeQuestion] = []

        for (gate, evaluation) in gateScore.evaluations where !evaluation.passed {
            let question = ProbeQuestion(
                id: UUID(),
                gate: gate,
                question: "What additional information is needed for \(gate.displayName)?",
                priority: evaluation.failureSeverity == .critical ? .high : .medium,
                context: evaluation.reason
            )
            questions.append(question)
        }

        return questions.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }

    // MARK: - Display Properties

    var displayName: String {
        switch self {
        case .execute:  return "EXECUTE"
        case .probe:    return "PROBE"
        case .ask:      return "ASK"
        case .defer_:   return "DEFER"
        case .abort:    return "ABORT"
        }
    }

    var isActionable: Bool {
        switch self {
        case .execute: return true
        default: return false
        }
    }
}

// MARK: - Execution Context

/// Context provided when the outcome is EXECUTE.
struct ExecutionContext: Sendable {
    let confidence: Double
    let gateScore: GateScore
    let approvedAt: Date
    let conditions: [String]

    init(confidence: Double, gateScore: GateScore, approvedAt: Date, conditions: [String] = []) {
        self.confidence = confidence
        self.gateScore = gateScore
        self.approvedAt = approvedAt
        self.conditions = conditions
    }
}

// MARK: - Probe Question

/// A specific question generated when PROBE outcome is selected.
struct ProbeQuestion: Identifiable, Sendable {
    let id: UUID
    let gate: Gate
    let question: String
    let priority: ProbePriority
    let context: String
}

/// Priority level for probe questions.
enum ProbePriority: Int, Sendable, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    static func < (lhs: ProbePriority, rhs: ProbePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
