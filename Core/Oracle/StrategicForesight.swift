//
//  StrategicForesight.swift
//  MTRX — Oracle
//
//  Three-steps-ahead predictive modeling. Scenario planning and market condition forecasting.
//

import Foundation

// MARK: - Scenario

/// A potential future scenario modeled by the foresight engine.
struct Scenario: Identifiable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let probability: Double
    let timeHorizon: TimeHorizon
    let impact: ScenarioImpact
    let assumptions: [String]
    let indicators: [LeadingIndicator]
    let recommendedActions: [String]
    let generatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        probability: Double,
        timeHorizon: TimeHorizon,
        impact: ScenarioImpact,
        assumptions: [String] = [],
        indicators: [LeadingIndicator] = [],
        recommendedActions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.probability = probability
        self.timeHorizon = timeHorizon
        self.impact = impact
        self.assumptions = assumptions
        self.indicators = indicators
        self.recommendedActions = recommendedActions
        self.generatedAt = Date()
    }
}

// MARK: - Time Horizon

enum TimeHorizon: String, Sendable, Comparable, CaseIterable {
    case immediate = "immediate"  // 0-24 hours
    case shortTerm = "short"      // 1-7 days
    case mediumTerm = "medium"    // 1-4 weeks
    case longTerm = "long"        // 1-3 months

    var displayName: String {
        switch self {
        case .immediate:  return "Next 24 Hours"
        case .shortTerm:  return "Next Week"
        case .mediumTerm: return "Next Month"
        case .longTerm:   return "Next Quarter"
        }
    }

    static func < (lhs: TimeHorizon, rhs: TimeHorizon) -> Bool {
        let order: [TimeHorizon] = [.immediate, .shortTerm, .mediumTerm, .longTerm]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

// MARK: - Scenario Impact

struct ScenarioImpact: Sendable {
    let portfolioEffect: Double      // Expected % change to portfolio
    let affectedAssets: [String]
    let riskLevel: RiskLevel
    let description: String

    enum RiskLevel: String, Sendable {
        case minimal
        case moderate
        case significant
        case severe
    }
}

// MARK: - Leading Indicator

/// A metric that tends to precede and predict a scenario outcome.
struct LeadingIndicator: Sendable {
    let name: String
    let currentValue: Double
    let thresholdValue: Double
    let direction: IndicatorDirection
    let leadTime: TimeInterval // How far ahead this indicator predicts (seconds)

    enum IndicatorDirection: String, Sendable {
        case bullish
        case bearish
        case neutral
    }

    /// Whether the indicator is currently signaling.
    var isTriggered: Bool {
        switch direction {
        case .bullish:  return currentValue > thresholdValue
        case .bearish:  return currentValue < thresholdValue
        case .neutral:  return abs(currentValue - thresholdValue) < 0.05
        }
    }
}

// MARK: - Strategic Foresight

/// Predictive modeling engine that generates future scenarios.
/// Models market conditions, plans for multiple outcomes, and stays
/// three steps ahead of current conditions.
final class StrategicForesight {

    // MARK: - Properties

    private var activeScenarios: [Scenario] = []
    private var scenarioHistory: [Scenario] = []
    private var indicatorRegistry: [String: LeadingIndicator] = [:]
    private let maxActiveScenarios: Int = 20
    private let scenarioRefreshInterval: TimeInterval = 3600 // 1 hour

    // MARK: - Scenario Generation

    /// Generate scenarios based on current conditions and models.
    /// - Returns: Oracle insights from scenario analysis.
    func generateScenarios() async -> [OracleInsight] {
        var insights: [OracleInsight] = []

        // Generate scenarios for each time horizon
        for horizon in TimeHorizon.allCases {
            let scenarios = await buildScenarios(for: horizon)
            activeScenarios.append(contentsOf: scenarios)

            // Convert high-probability or high-impact scenarios to insights
            for scenario in scenarios where scenario.probability > 0.40 || scenario.impact.riskLevel == .severe {
                insights.append(OracleInsight(
                    type: .prediction,
                    category: .market,
                    content: "[\(horizon.displayName)] \(scenario.name): \(scenario.description)",
                    confidence: scenario.probability,
                    priority: scenario.impact.riskLevel == .severe ? .high : .normal,
                    metadata: [
                        "scenario_id": scenario.id.uuidString,
                        "time_horizon": horizon.rawValue,
                        "portfolio_effect": String(format: "%.2f%%", scenario.impact.portfolioEffect)
                    ]
                ))
            }
        }

        // Prune old scenarios
        pruneScenarios()

        return insights
    }

    /// Get the three most likely scenarios for the next time step.
    /// This is the "three steps ahead" core feature.
    /// - Returns: Top three scenarios sorted by probability.
    func threeStepsAhead() -> [Scenario] {
        Array(activeScenarios
            .sorted { $0.probability > $1.probability }
            .prefix(3))
    }

    /// Get scenarios for a specific time horizon.
    /// - Parameter horizon: The time horizon to query.
    /// - Returns: Active scenarios for the given horizon.
    func scenarios(for horizon: TimeHorizon) -> [Scenario] {
        activeScenarios.filter { $0.timeHorizon == horizon }
            .sorted { $0.probability > $1.probability }
    }

    // MARK: - Indicator Management

    /// Register a leading indicator for monitoring.
    /// - Parameter indicator: The indicator to register.
    func registerIndicator(_ indicator: LeadingIndicator) {
        indicatorRegistry[indicator.name] = indicator
    }

    /// Update a leading indicator's current value.
    /// - Parameters:
    ///   - name: The indicator name.
    ///   - value: The new value.
    func updateIndicator(name: String, value: Double) {
        guard var indicator = indicatorRegistry[name] else { return }
        indicator = LeadingIndicator(
            name: indicator.name,
            currentValue: value,
            thresholdValue: indicator.thresholdValue,
            direction: indicator.direction,
            leadTime: indicator.leadTime
        )
        indicatorRegistry[name] = indicator
    }

    /// Get all currently triggered indicators.
    /// - Returns: Indicators that are currently signaling.
    func triggeredIndicators() -> [LeadingIndicator] {
        indicatorRegistry.values.filter { $0.isTriggered }
    }

    // MARK: - Private Helpers

    private func buildScenarios(for horizon: TimeHorizon) async -> [Scenario] {
        // TODO: Implement scenario generation
        // - Analyze current market conditions
        // - Apply Monte Carlo simulation
        // - Consider leading indicators
        // - Factor in probability models from ProbabilityArchitecture
        // - Generate base case, bull case, bear case, and tail risk scenarios

        let baseCase = Scenario(
            name: "Base Case",
            description: "Current trends continue with moderate volatility.",
            probability: 0.55,
            timeHorizon: horizon,
            impact: ScenarioImpact(
                portfolioEffect: 0.5,
                affectedAssets: [],
                riskLevel: .minimal,
                description: "Minimal portfolio impact expected."
            ),
            assumptions: ["Current market regime persists", "No major regulatory changes"],
            recommendedActions: ["Maintain current positions"]
        )

        let bullCase = Scenario(
            name: "Bull Case",
            description: "Favorable conditions drive significant upside.",
            probability: 0.25,
            timeHorizon: horizon,
            impact: ScenarioImpact(
                portfolioEffect: 8.0,
                affectedAssets: [],
                riskLevel: .minimal,
                description: "Positive portfolio impact expected."
            ),
            assumptions: ["Positive macro catalysts", "Increasing adoption"],
            recommendedActions: ["Consider increasing exposure"]
        )

        let bearCase = Scenario(
            name: "Bear Case",
            description: "Adverse conditions lead to significant downside.",
            probability: 0.15,
            timeHorizon: horizon,
            impact: ScenarioImpact(
                portfolioEffect: -12.0,
                affectedAssets: [],
                riskLevel: .significant,
                description: "Material portfolio drawdown possible."
            ),
            assumptions: ["Negative macro event", "Liquidity contraction"],
            recommendedActions: ["Review stop-loss levels", "Consider hedging"]
        )

        let tailRisk = Scenario(
            name: "Tail Risk",
            description: "Black swan event causes severe market disruption.",
            probability: 0.05,
            timeHorizon: horizon,
            impact: ScenarioImpact(
                portfolioEffect: -35.0,
                affectedAssets: [],
                riskLevel: .severe,
                description: "Severe portfolio impact. Emergency protocols may be needed."
            ),
            assumptions: ["Major systemic event", "Cascading failures"],
            recommendedActions: ["Ensure emergency liquidity", "Verify rollback mechanisms"]
        )

        return [baseCase, bullCase, bearCase, tailRisk]
    }

    private func pruneScenarios() {
        // Remove expired scenarios
        let now = Date()
        activeScenarios.removeAll { scenario in
            let expiryMap: [TimeHorizon: TimeInterval] = [
                .immediate: 86400,
                .shortTerm: 604800,
                .mediumTerm: 2592000,
                .longTerm: 7776000
            ]
            let expiry = expiryMap[scenario.timeHorizon] ?? 86400
            return now.timeIntervalSince(scenario.generatedAt) > expiry
        }

        // Cap total active scenarios
        if activeScenarios.count > maxActiveScenarios {
            activeScenarios = Array(activeScenarios
                .sorted { $0.probability > $1.probability }
                .prefix(maxActiveScenarios))
        }

        scenarioHistory.append(contentsOf: activeScenarios)
    }
}
