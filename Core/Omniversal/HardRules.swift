//
//  HardRules.swift
//  MTRX — Omniversal
//
//  Non-negotiable rules that override gate scores. Violations cause immediate ABORT.
//

import Foundation

// MARK: - Hard Rule

/// A non-negotiable rule that must be satisfied regardless of gate scores.
struct HardRule: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let severity: HardRuleSeverity
    let validate: @Sendable (DecisionRequest, [Gate: GateEvaluation]) -> HardRuleViolation?

    init(
        id: String,
        name: String,
        description: String,
        severity: HardRuleSeverity = .critical,
        validate: @escaping @Sendable (DecisionRequest, [Gate: GateEvaluation]) -> HardRuleViolation?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.severity = severity
        self.validate = validate
    }
}

// MARK: - Hard Rule Severity

enum HardRuleSeverity: Int, Sendable, Codable, Comparable {
    case warning = 0
    case blocking = 1
    case critical = 2

    static func < (lhs: HardRuleSeverity, rhs: HardRuleSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Hard Rule Violation

/// Represents a violation of a hard rule.
struct HardRuleViolation: Sendable {
    let ruleId: String
    let ruleName: String
    let severity: HardRuleSeverity
    let message: String
    let timestamp: Date

    init(ruleId: String, ruleName: String, severity: HardRuleSeverity, message: String) {
        self.ruleId = ruleId
        self.ruleName = ruleName
        self.severity = severity
        self.message = message
        self.timestamp = Date()
    }
}

// MARK: - Hard Rules Container

/// Contains all non-negotiable rules that must be enforced on every decision.
struct HardRules: Sendable {

    // MARK: - Properties

    private let rules: [HardRule]

    // MARK: - Initialization

    init(additionalRules: [HardRule] = []) {
        var allRules = HardRules.defaultRules
        allRules.append(contentsOf: additionalRules)
        self.rules = allRules
    }

    // MARK: - Validation

    /// Validate a decision request against all hard rules.
    /// - Parameters:
    ///   - request: The decision request.
    ///   - evaluations: The gate evaluations for the request.
    /// - Returns: An array of violations. Empty array means all rules passed.
    func validate(
        request: DecisionRequest,
        evaluations: [Gate: GateEvaluation]
    ) -> [HardRuleViolation] {
        var violations: [HardRuleViolation] = []
        for rule in rules {
            if let violation = rule.validate(request, evaluations) {
                violations.append(violation)
            }
        }
        return violations
    }

    /// Returns true if any critical rule was violated.
    func hasCriticalViolation(
        request: DecisionRequest,
        evaluations: [Gate: GateEvaluation]
    ) -> Bool {
        validate(request: request, evaluations: evaluations)
            .contains { $0.severity == .critical }
    }

    // MARK: - Default Rules

    private static var defaultRules: [HardRule] {
        [
            noPublishWithoutApproval,
            rollbackRequired,
            noHighRiskWithoutConfirmation,
            maxLoopLimitEnforced,
            dataIntegrityRequired,
            complianceCheckRequired,
        ]
    }

    // MARK: - Rule: No Publish Without Approval

    /// No action that publishes, deploys, or makes changes visible externally
    /// without explicit user approval.
    private static var noPublishWithoutApproval: HardRule {
        HardRule(
            id: "no_publish_without_approval",
            name: "No Publish Without Approval",
            description: "Prevents publishing or deploying without explicit user approval.",
            severity: .critical
        ) { request, _ in
            let publishKeywords = ["publish", "deploy", "release", "broadcast", "send"]
            let isPublishAction = publishKeywords.contains { request.description.lowercased().contains($0) }
            let hasApproval = request.context["user_approved"] as? Bool ?? false

            if isPublishAction && !hasApproval {
                return HardRuleViolation(
                    ruleId: "no_publish_without_approval",
                    ruleName: "No Publish Without Approval",
                    severity: .critical,
                    message: "Publishing actions require explicit user approval."
                )
            }
            return nil
        }
    }

    // MARK: - Rule: Rollback Required

    /// Every action that modifies state must have a rollback mechanism.
    private static var rollbackRequired: HardRule {
        HardRule(
            id: "rollback_required",
            name: "Rollback Required",
            description: "State-modifying actions must have a rollback mechanism available.",
            severity: .critical
        ) { request, _ in
            let modifyKeywords = ["modify", "update", "delete", "create", "swap", "transfer"]
            let isModifyAction = modifyKeywords.contains { request.description.lowercased().contains($0) }
            let hasRollback = request.context["rollback_available"] as? Bool ?? false

            if isModifyAction && !hasRollback {
                return HardRuleViolation(
                    ruleId: "rollback_required",
                    ruleName: "Rollback Required",
                    severity: .critical,
                    message: "State-modifying actions require a rollback mechanism."
                )
            }
            return nil
        }
    }

    // MARK: - Rule: No High-Risk Without Confirmation

    /// Decisions flagged as high-risk by the risk gate must have user confirmation.
    private static var noHighRiskWithoutConfirmation: HardRule {
        HardRule(
            id: "no_high_risk_without_confirmation",
            name: "No High-Risk Without Confirmation",
            description: "High-risk decisions require explicit user confirmation.",
            severity: .critical
        ) { request, evaluations in
            guard let riskEval = evaluations[.risk] else { return nil }

            if riskEval.score < 0.40 {
                let hasConfirmation = request.context["user_confirmed"] as? Bool ?? false
                if !hasConfirmation {
                    return HardRuleViolation(
                        ruleId: "no_high_risk_without_confirmation",
                        ruleName: "No High-Risk Without Confirmation",
                        severity: .critical,
                        message: "High-risk decision (risk score: \(riskEval.score)) requires user confirmation."
                    )
                }
            }
            return nil
        }
    }

    // MARK: - Rule: Max Loop Limit Enforced

    /// Prevents infinite decision loops by enforcing the loop limit gate.
    private static var maxLoopLimitEnforced: HardRule {
        HardRule(
            id: "max_loop_limit_enforced",
            name: "Max Loop Limit Enforced",
            description: "Prevents re-evaluating the same decision too many times.",
            severity: .blocking
        ) { _, evaluations in
            guard let loopEval = evaluations[.loopLimit] else { return nil }

            if loopEval.score < 0.20 {
                return HardRuleViolation(
                    ruleId: "max_loop_limit_enforced",
                    ruleName: "Max Loop Limit Enforced",
                    severity: .blocking,
                    message: "Decision has been re-evaluated too many times. Manual intervention required."
                )
            }
            return nil
        }
    }

    // MARK: - Rule: Data Integrity Required

    /// All data-dependent decisions must have verified, non-stale data.
    private static var dataIntegrityRequired: HardRule {
        HardRule(
            id: "data_integrity_required",
            name: "Data Integrity Required",
            description: "Decisions must be based on verified, current data.",
            severity: .blocking
        ) { request, _ in
            // TODO: Implement data freshness checks
            // Check that data sources are within acceptable staleness thresholds
            if let dataAge = request.context["data_age_seconds"] as? TimeInterval, dataAge > 300 {
                return HardRuleViolation(
                    ruleId: "data_integrity_required",
                    ruleName: "Data Integrity Required",
                    severity: .blocking,
                    message: "Decision data is stale (age: \(Int(dataAge))s). Refresh required."
                )
            }
            return nil
        }
    }

    // MARK: - Rule: Compliance Check Required

    /// Regulatory compliance must be verified for financial actions.
    private static var complianceCheckRequired: HardRule {
        HardRule(
            id: "compliance_check_required",
            name: "Compliance Check Required",
            description: "Financial actions must pass compliance verification.",
            severity: .critical
        ) { request, _ in
            let financialKeywords = ["trade", "swap", "invest", "transfer", "withdraw"]
            let isFinancialAction = financialKeywords.contains { request.description.lowercased().contains($0) }
            let compliancePassed = request.context["compliance_verified"] as? Bool ?? false

            if isFinancialAction && !compliancePassed {
                return HardRuleViolation(
                    ruleId: "compliance_check_required",
                    ruleName: "Compliance Check Required",
                    severity: .critical,
                    message: "Financial actions require compliance verification."
                )
            }
            return nil
        }
    }
}
