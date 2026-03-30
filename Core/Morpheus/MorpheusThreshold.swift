//
//  MorpheusThreshold.swift
//  MTRX — Morpheus
//
//  Defines what qualifies as genuinely pivotal. Prevents alert fatigue with strict thresholds.
//

import Foundation

// MARK: - Morpheus Threshold

/// Strict thresholds that determine what qualifies as a genuinely pivotal moment.
/// Designed to prevent alert fatigue by filtering out noise and only surfacing
/// events that truly require the user's attention.
struct MorpheusThreshold: Sendable {

    // MARK: - Configuration

    /// Minimum confidence score (0.0-1.0) for a moment to qualify.
    let minimumConfidence: Double

    /// Minimum severity level to surface to the user.
    let minimumSeverity: MomentSeverity

    /// Maximum number of active moments allowed simultaneously.
    /// Prevents alert overload.
    let maxActiveMoments: Int

    /// Cooldown period between alerts of the same type (seconds).
    let sameTriggerCooldown: TimeInterval

    /// Global cooldown between any non-critical alerts (seconds).
    let globalAlertCooldown: TimeInterval

    /// Minimum portfolio impact percentage for financial alerts.
    let minimumPortfolioImpact: Double

    /// Whether to allow advisory-level alerts.
    let allowAdvisoryAlerts: Bool

    // MARK: - Alert History Tracking

    private var lastAlertTimestamps: [PivotalMomentType: Date]
    private var lastGlobalAlertTimestamp: Date?

    // MARK: - Initialization

    init(
        minimumConfidence: Double = 0.70,
        minimumSeverity: MomentSeverity = .important,
        maxActiveMoments: Int = 5,
        sameTriggerCooldown: TimeInterval = 1800,     // 30 minutes
        globalAlertCooldown: TimeInterval = 300,       // 5 minutes
        minimumPortfolioImpact: Double = 2.0,          // 2% of portfolio
        allowAdvisoryAlerts: Bool = false
    ) {
        self.minimumConfidence = minimumConfidence
        self.minimumSeverity = minimumSeverity
        self.maxActiveMoments = maxActiveMoments
        self.sameTriggerCooldown = sameTriggerCooldown
        self.globalAlertCooldown = globalAlertCooldown
        self.minimumPortfolioImpact = minimumPortfolioImpact
        self.allowAdvisoryAlerts = allowAdvisoryAlerts
        self.lastAlertTimestamps = [:]
        self.lastGlobalAlertTimestamp = nil
    }

    // MARK: - Qualification Check

    /// Determine if a moment qualifies as genuinely pivotal.
    /// - Parameter moment: The candidate pivotal moment.
    /// - Returns: True if the moment passes all threshold checks.
    func qualifiesAsPivotal(_ moment: PivotalMoment) -> Bool {
        // Critical moments always pass (safety override)
        if moment.severity == .critical {
            return true
        }

        // Check minimum confidence
        guard moment.confidence >= minimumConfidence else {
            return false
        }

        // Check minimum severity
        guard moment.severity >= minimumSeverity else {
            return false
        }

        // Check advisory filter
        if moment.severity == .advisory && !allowAdvisoryAlerts {
            return false
        }

        // Check same-trigger cooldown
        if let lastTime = lastAlertTimestamps[moment.type] {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < sameTriggerCooldown {
                return false
            }
        }

        // Check global cooldown (non-critical only)
        if let lastGlobal = lastGlobalAlertTimestamp {
            let elapsed = Date().timeIntervalSince(lastGlobal)
            if elapsed < globalAlertCooldown {
                return false
            }
        }

        return true
    }

    /// Record that an alert was surfaced, updating cooldown timestamps.
    /// - Parameter moment: The moment that was surfaced.
    mutating func recordAlert(_ moment: PivotalMoment) {
        lastAlertTimestamps[moment.type] = Date()
        lastGlobalAlertTimestamp = Date()
    }

    /// Reset all cooldown timestamps.
    mutating func resetCooldowns() {
        lastAlertTimestamps.removeAll()
        lastGlobalAlertTimestamp = nil
    }

    // MARK: - Threshold Profiles

    /// Conservative thresholds — fewer, higher-quality alerts.
    static let conservative = MorpheusThreshold(
        minimumConfidence: 0.85,
        minimumSeverity: .urgent,
        maxActiveMoments: 3,
        sameTriggerCooldown: 3600,       // 1 hour
        globalAlertCooldown: 600,         // 10 minutes
        minimumPortfolioImpact: 5.0,      // 5%
        allowAdvisoryAlerts: false
    )

    /// Balanced thresholds — good signal-to-noise ratio.
    static let balanced = MorpheusThreshold(
        minimumConfidence: 0.70,
        minimumSeverity: .important,
        maxActiveMoments: 5,
        sameTriggerCooldown: 1800,       // 30 minutes
        globalAlertCooldown: 300,         // 5 minutes
        minimumPortfolioImpact: 2.0,      // 2%
        allowAdvisoryAlerts: false
    )

    /// Aggressive thresholds — more alerts, wider coverage.
    static let aggressive = MorpheusThreshold(
        minimumConfidence: 0.55,
        minimumSeverity: .advisory,
        maxActiveMoments: 10,
        sameTriggerCooldown: 600,        // 10 minutes
        globalAlertCooldown: 120,         // 2 minutes
        minimumPortfolioImpact: 1.0,      // 1%
        allowAdvisoryAlerts: true
    )

    // MARK: - Dynamic Threshold Adjustment

    /// Adjust thresholds based on market conditions.
    /// During high volatility, lower thresholds to catch more events.
    /// During calm periods, raise thresholds to reduce noise.
    /// - Parameter volatilityIndex: Current market volatility (0.0-1.0).
    /// - Returns: Adjusted threshold configuration.
    static func adjusted(for volatilityIndex: Double) -> MorpheusThreshold {
        if volatilityIndex > 0.75 {
            // High volatility — more permissive
            return MorpheusThreshold(
                minimumConfidence: 0.60,
                minimumSeverity: .important,
                maxActiveMoments: 8,
                sameTriggerCooldown: 900,
                globalAlertCooldown: 180,
                minimumPortfolioImpact: 1.5,
                allowAdvisoryAlerts: true
            )
        } else if volatilityIndex < 0.25 {
            // Low volatility — more conservative
            return .conservative
        } else {
            return .balanced
        }
    }
}

// MARK: - Threshold Validation

extension MorpheusThreshold {

    /// Validate that threshold configuration is internally consistent.
    func validate() -> [String] {
        var errors: [String] = []

        if minimumConfidence < 0.0 || minimumConfidence > 1.0 {
            errors.append("minimumConfidence must be between 0.0 and 1.0")
        }
        if maxActiveMoments < 1 {
            errors.append("maxActiveMoments must be at least 1")
        }
        if sameTriggerCooldown < 0 {
            errors.append("sameTriggerCooldown cannot be negative")
        }
        if globalAlertCooldown < 0 {
            errors.append("globalAlertCooldown cannot be negative")
        }
        if minimumPortfolioImpact < 0 {
            errors.append("minimumPortfolioImpact cannot be negative")
        }
        if globalAlertCooldown > sameTriggerCooldown {
            errors.append("globalAlertCooldown should not exceed sameTriggerCooldown")
        }

        return errors
    }
}
