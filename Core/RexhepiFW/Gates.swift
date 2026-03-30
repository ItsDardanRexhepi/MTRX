//
//  Gates.swift
//  MTRX — RexhepiFW
//
//  Defines the six evaluation gates: Clarity, Feasibility, Risk, Uncertainty, Value, and Loop Limit.
//

import Foundation

// MARK: - Gate Enum

/// The six gates through which every decision must pass.
/// Each gate evaluates a distinct dimension of decision quality.
enum Gate: Int, CaseIterable, Sendable, Codable, Comparable {
    case clarity = 0
    case feasibility = 1
    case risk = 2
    case uncertainty = 3
    case value = 4
    case loopLimit = 5

    // MARK: - Display Properties

    var displayName: String {
        switch self {
        case .clarity:      return "Clarity"
        case .feasibility:  return "Feasibility"
        case .risk:         return "Risk"
        case .uncertainty:  return "Uncertainty"
        case .value:        return "Value"
        case .loopLimit:    return "Loop Limit"
        }
    }

    var description: String {
        switch self {
        case .clarity:
            return "How well-defined and unambiguous is the decision request?"
        case .feasibility:
            return "Can this decision realistically be executed given current constraints?"
        case .risk:
            return "What is the potential downside, and is it within acceptable bounds?"
        case .uncertainty:
            return "How much unknown information exists, and can we proceed despite it?"
        case .value:
            return "Does the expected outcome justify the cost and effort?"
        case .loopLimit:
            return "Are we revisiting a decision that has already been evaluated too many times?"
        }
    }

    // MARK: - Default Thresholds

    /// Default threshold score (0.0-1.0) required to pass this gate.
    var defaultThreshold: Double {
        switch self {
        case .clarity:      return 0.70
        case .feasibility:  return 0.65
        case .risk:         return 0.60
        case .uncertainty:  return 0.55
        case .value:        return 0.60
        case .loopLimit:    return 0.80
        }
    }

    /// Returns the adjusted threshold based on time sensitivity.
    /// Higher urgency lowers certain thresholds to allow faster decisions.
    /// - Parameter sensitivity: The current time sensitivity level.
    /// - Returns: Adjusted threshold value.
    func threshold(for sensitivity: TimeSensitivity) -> Double {
        let modifier = sensitivity.thresholdModifier(for: self)
        return max(0.1, min(1.0, defaultThreshold + modifier))
    }

    // MARK: - Gate Weight

    /// Weight of this gate in composite scoring.
    var weight: Double {
        switch self {
        case .clarity:      return 0.20
        case .feasibility:  return 0.20
        case .risk:         return 0.20
        case .uncertainty:  return 0.15
        case .value:        return 0.15
        case .loopLimit:    return 0.10
        }
    }

    // MARK: - Comparable

    static func < (lhs: Gate, rhs: Gate) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Gate Evaluation

/// Result of evaluating a single gate for a decision request.
struct GateEvaluation: Sendable, Codable {
    let gate: Gate
    let score: Double
    let threshold: Double
    let passed: Bool
    let reason: String
    let timestamp: Date

    /// How far above or below the threshold this evaluation landed.
    var margin: Double {
        score - threshold
    }

    /// True if the score is within 10% of the threshold (borderline).
    var isBorderline: Bool {
        abs(margin) < 0.10
    }

    /// Severity of failure (only meaningful when `passed` is false).
    var failureSeverity: FailureSeverity {
        guard !passed else { return .none }
        let deficit = threshold - score
        switch deficit {
        case ..<0.10: return .minor
        case ..<0.25: return .moderate
        case ..<0.40: return .significant
        default:      return .critical
        }
    }
}

// MARK: - Failure Severity

/// Indicates how severely a gate evaluation failed.
enum FailureSeverity: Int, Sendable, Codable, Comparable {
    case none = 0
    case minor = 1
    case moderate = 2
    case significant = 3
    case critical = 4

    var displayName: String {
        switch self {
        case .none:        return "None"
        case .minor:       return "Minor"
        case .moderate:    return "Moderate"
        case .significant: return "Significant"
        case .critical:    return "Critical"
        }
    }

    static func < (lhs: FailureSeverity, rhs: FailureSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Gate Configuration

/// Configurable parameters for a gate, allowing runtime adjustment.
struct GateConfiguration: Sendable, Codable {
    let gate: Gate
    var threshold: Double
    var weight: Double
    var isEnabled: Bool

    init(gate: Gate, threshold: Double? = nil, weight: Double? = nil, isEnabled: Bool = true) {
        self.gate = gate
        self.threshold = threshold ?? gate.defaultThreshold
        self.weight = weight ?? gate.weight
        self.isEnabled = isEnabled
    }

    /// Validates that configuration values are within acceptable ranges.
    func validate() -> [String] {
        var errors: [String] = []
        if threshold < 0.0 || threshold > 1.0 {
            errors.append("\(gate.displayName) threshold must be between 0.0 and 1.0")
        }
        if weight < 0.0 || weight > 1.0 {
            errors.append("\(gate.displayName) weight must be between 0.0 and 1.0")
        }
        return errors
    }
}

// MARK: - Gate Pipeline Configuration

/// Configuration for the entire gate evaluation pipeline.
struct GatePipelineConfiguration: Sendable {
    var gateConfigurations: [Gate: GateConfiguration]
    var requireAllGatesPass: Bool
    var minimumGatesPassed: Int
    var timeoutSeconds: TimeInterval

    init(
        requireAllGatesPass: Bool = true,
        minimumGatesPassed: Int = 4,
        timeoutSeconds: TimeInterval = 30.0
    ) {
        self.requireAllGatesPass = requireAllGatesPass
        self.minimumGatesPassed = minimumGatesPassed
        self.timeoutSeconds = timeoutSeconds

        var configs: [Gate: GateConfiguration] = [:]
        for gate in Gate.allCases {
            configs[gate] = GateConfiguration(gate: gate)
        }
        self.gateConfigurations = configs
    }

    /// Total weight across all enabled gates (should sum to ~1.0).
    var totalWeight: Double {
        gateConfigurations.values
            .filter { $0.isEnabled }
            .reduce(0.0) { $0 + $1.weight }
    }

    /// Validates the entire pipeline configuration.
    func validate() -> [String] {
        var errors: [String] = []
        for config in gateConfigurations.values {
            errors.append(contentsOf: config.validate())
        }
        let weightSum = totalWeight
        if abs(weightSum - 1.0) > 0.01 {
            errors.append("Total gate weights should sum to 1.0, got \(weightSum)")
        }
        return errors
    }
}
