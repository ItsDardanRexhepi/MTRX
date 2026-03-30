//
//  TimeSensitivity.swift
//  MTRX — Omniversal
//
//  Time sensitivity modifier that adjusts gate thresholds based on urgency.
//

import Foundation

// MARK: - Time Sensitivity

/// Urgency level that modifies gate evaluation thresholds.
/// Higher urgency relaxes certain gates (e.g., clarity) while tightening others (e.g., risk).
enum TimeSensitivity: Int, Comparable, Sendable, Codable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2

    // MARK: - Comparable

    static func < (lhs: TimeSensitivity, rhs: TimeSensitivity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - Display Properties

    var displayName: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    var description: String {
        switch self {
        case .low:
            return "No time pressure. Full evaluation with standard thresholds."
        case .medium:
            return "Moderate urgency. Slight threshold adjustments permitted."
        case .high:
            return "High urgency. Relaxed thresholds for speed, tightened risk controls."
        }
    }

    // MARK: - Threshold Modification

    /// Returns the threshold modifier for a specific gate at this sensitivity level.
    /// Positive values raise the threshold (stricter), negative values lower it (more permissive).
    /// - Parameter gate: The gate to modify.
    /// - Returns: The modifier value to add to the gate's default threshold.
    func thresholdModifier(for gate: Gate) -> Double {
        switch self {
        case .low:
            // Standard thresholds — no modification
            return 0.0

        case .medium:
            // Slight relaxation on clarity and uncertainty; neutral on others
            switch gate {
            case .clarity:      return -0.05
            case .feasibility:  return 0.0
            case .risk:         return 0.0
            case .uncertainty:  return -0.05
            case .value:        return 0.0
            case .loopLimit:    return -0.05
            }

        case .high:
            // Significant relaxation on clarity/uncertainty, tighten risk
            switch gate {
            case .clarity:      return -0.15
            case .feasibility:  return -0.10
            case .risk:         return 0.10   // Tighter risk control under urgency
            case .uncertainty:  return -0.15
            case .value:        return -0.10
            case .loopLimit:    return -0.20
            }
        }
    }

    // MARK: - Decision Timeout

    /// Maximum time allowed for the scoring pipeline at this sensitivity level.
    var pipelineTimeout: TimeInterval {
        switch self {
        case .low:    return 60.0   // 1 minute
        case .medium: return 30.0   // 30 seconds
        case .high:   return 10.0   // 10 seconds
        }
    }

    /// Maximum deferral time before a decision must be re-evaluated.
    var maxDeferralInterval: TimeInterval {
        switch self {
        case .low:    return 86400.0  // 24 hours
        case .medium: return 3600.0   // 1 hour
        case .high:   return 300.0    // 5 minutes
        }
    }

    // MARK: - Adjusted Scoring

    /// Apply this sensitivity level to adjust a full set of gate scores.
    /// - Parameter gateScore: The original gate score to adjust.
    /// - Returns: A new set of adjusted thresholds per gate.
    func adjustedThresholds() -> [Gate: Double] {
        var thresholds: [Gate: Double] = [:]
        for gate in Gate.allCases {
            thresholds[gate] = gate.threshold(for: self)
        }
        return thresholds
    }

    /// Determines if a gate evaluation should be re-evaluated under this sensitivity.
    /// - Parameter evaluation: The gate evaluation to check.
    /// - Returns: True if the evaluation result might change under adjusted thresholds.
    func shouldReEvaluate(_ evaluation: GateEvaluation) -> Bool {
        let adjustedThreshold = evaluation.gate.threshold(for: self)
        // Re-evaluate if the adjusted threshold would flip the pass/fail result
        let wouldPass = evaluation.score >= adjustedThreshold
        return wouldPass != evaluation.passed
    }
}

// MARK: - Time Sensitivity Detection

/// Heuristics for automatically detecting time sensitivity from context.
struct TimeSensitivityDetector {

    /// Detect time sensitivity from a decision request's context.
    /// - Parameter request: The decision request to analyze.
    /// - Returns: The detected time sensitivity level.
    static func detect(from request: DecisionRequest) -> TimeSensitivity {
        // TODO: Implement real detection logic based on:
        // - Market volatility indicators
        // - User-specified urgency
        // - Time-bound events (expiring options, flash sales, etc.)
        // - Security threat level

        let keywords = request.description.lowercased()

        if keywords.contains("urgent") || keywords.contains("immediately") ||
           keywords.contains("emergency") || keywords.contains("now") {
            return .high
        }

        if keywords.contains("soon") || keywords.contains("today") ||
           keywords.contains("asap") {
            return .medium
        }

        return .low
    }
}
