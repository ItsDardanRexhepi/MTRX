//
//  DardanAdvisory.swift
//  MTRX — Oracle
//
//  Owner-only private strategic briefings. Intelligence summaries, strategic recommendations,
//  and portfolio optimization suggestions.
//

import Foundation

// MARK: - Advisory Briefing

/// A private strategic briefing for the owner.
struct AdvisoryBriefing: Identifiable, Sendable {
    let id: UUID
    let type: BriefingType
    let title: String
    let executiveSummary: String
    let sections: [BriefingSection]
    let recommendations: [StrategicRecommendation]
    let riskSummary: RiskSummary
    let generatedAt: Date
    let validUntil: Date
    let confidence: Double

    init(
        id: UUID = UUID(),
        type: BriefingType,
        title: String,
        executiveSummary: String,
        sections: [BriefingSection] = [],
        recommendations: [StrategicRecommendation] = [],
        riskSummary: RiskSummary,
        validUntil: Date? = nil,
        confidence: Double = 0.75
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.executiveSummary = executiveSummary
        self.sections = sections
        self.recommendations = recommendations
        self.riskSummary = riskSummary
        self.generatedAt = Date()
        self.validUntil = validUntil ?? Calendar.current.date(byAdding: .hour, value: 24, to: Date())!
        self.confidence = confidence
    }
}

// MARK: - Briefing Type

enum BriefingType: String, Sendable, CaseIterable {
    case daily           // Daily strategic overview
    case weekly          // Weekly in-depth analysis
    case eventDriven     // Triggered by significant events
    case portfolioReview // Portfolio optimization review
    case threatBriefing  // Security threat summary
    case opportunity     // Time-sensitive opportunity briefing
}

// MARK: - Briefing Section

struct BriefingSection: Identifiable, Sendable {
    let id: UUID
    let title: String
    let content: String
    let priority: Int
    let dataPoints: [String: String]

    init(id: UUID = UUID(), title: String, content: String, priority: Int = 0, dataPoints: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.content = content
        self.priority = priority
        self.dataPoints = dataPoints
    }
}

// MARK: - Strategic Recommendation

struct StrategicRecommendation: Identifiable, Sendable {
    let id: UUID
    let action: String
    let rationale: String
    let urgency: RecommendationUrgency
    let expectedImpact: String
    let riskLevel: String
    let timeframe: String
    let confidence: Double

    init(
        id: UUID = UUID(),
        action: String,
        rationale: String,
        urgency: RecommendationUrgency = .standard,
        expectedImpact: String,
        riskLevel: String,
        timeframe: String,
        confidence: Double
    ) {
        self.id = id
        self.action = action
        self.rationale = rationale
        self.urgency = urgency
        self.expectedImpact = expectedImpact
        self.riskLevel = riskLevel
        self.timeframe = timeframe
        self.confidence = confidence
    }
}

enum RecommendationUrgency: String, Sendable, Comparable {
    case informational
    case standard
    case timeSensitive
    case immediate

    static func < (lhs: RecommendationUrgency, rhs: RecommendationUrgency) -> Bool {
        let order: [RecommendationUrgency] = [.informational, .standard, .timeSensitive, .immediate]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

// MARK: - Risk Summary

struct RiskSummary: Sendable {
    let overallRiskLevel: Double // 0.0-1.0
    let topRisks: [String]
    let mitigationStatus: String
    let portfolioAtRiskPercent: Double
}

// MARK: - Dardan Advisory

/// Owner-only intelligence briefing system.
/// Generates private strategic briefings, recommendations, and portfolio optimization suggestions.
/// This layer is exclusive to the system owner and never surfaces to other users.
final class DardanAdvisory {

    // MARK: - Properties

    private var briefingHistory: [AdvisoryBriefing] = []
    private var latestBriefing: AdvisoryBriefing?
    private var pendingInsights: [OracleInsight] = []
    private let voice: OracleVoice

    /// Minimum number of new insights to trigger a briefing.
    private let briefingThreshold: Int = 5

    /// Minimum time between briefings (seconds).
    private let minimumBriefingInterval: TimeInterval = 3600 // 1 hour

    // MARK: - Initialization

    init(voice: OracleVoice = OracleVoice()) {
        self.voice = voice
    }

    // MARK: - Briefing Evaluation

    /// Evaluate whether a new briefing should be generated based on accumulated insights.
    /// - Parameter insights: The latest batch of Oracle insights.
    func evaluateForBriefing(insights: [OracleInsight]) async {
        pendingInsights.append(contentsOf: insights)

        // Check if briefing conditions are met
        guard shouldGenerateBriefing() else { return }

        let briefing = await generateBriefing(from: pendingInsights)
        latestBriefing = briefing
        briefingHistory.append(briefing)
        pendingInsights.removeAll()
    }

    /// Force generation of a briefing regardless of conditions.
    /// - Returns: The generated briefing.
    func forceGenerateBriefing() async -> AdvisoryBriefing {
        let briefing = await generateBriefing(from: pendingInsights)
        latestBriefing = briefing
        briefingHistory.append(briefing)
        pendingInsights.removeAll()
        return briefing
    }

    // MARK: - Briefing Generation

    /// Generate a comprehensive strategic briefing.
    /// - Parameter insights: The insights to base the briefing on.
    /// - Returns: A complete advisory briefing.
    private func generateBriefing(from insights: [OracleInsight]) async -> AdvisoryBriefing {
        // Categorize insights
        let threats = insights.filter { $0.type == .threat }
        let opportunities = insights.filter { $0.type == .opportunity }
        let predictions = insights.filter { $0.type == .prediction }
        let patterns = insights.filter { $0.type == .pattern }

        // Build briefing sections
        var sections: [BriefingSection] = []

        if !threats.isEmpty {
            sections.append(BriefingSection(
                title: "Threat Assessment",
                content: summarizeInsights(threats),
                priority: 0,
                dataPoints: ["threat_count": "\(threats.count)"]
            ))
        }

        if !opportunities.isEmpty {
            sections.append(BriefingSection(
                title: "Opportunity Analysis",
                content: summarizeInsights(opportunities),
                priority: 1,
                dataPoints: ["opportunity_count": "\(opportunities.count)"]
            ))
        }

        if !predictions.isEmpty {
            sections.append(BriefingSection(
                title: "Market Outlook",
                content: summarizeInsights(predictions),
                priority: 2,
                dataPoints: ["prediction_count": "\(predictions.count)"]
            ))
        }

        if !patterns.isEmpty {
            sections.append(BriefingSection(
                title: "Pattern Intelligence",
                content: summarizeInsights(patterns),
                priority: 3,
                dataPoints: ["pattern_count": "\(patterns.count)"]
            ))
        }

        // Generate recommendations
        let recommendations = generateRecommendations(from: insights)

        // Compute risk summary
        let riskSummary = computeRiskSummary(threats: threats)

        // Determine briefing type
        let type: BriefingType
        if threats.contains(where: { $0.priority >= .critical }) {
            type = .threatBriefing
        } else if opportunities.contains(where: { $0.priority >= .high }) {
            type = .opportunity
        } else {
            type = .eventDriven
        }

        return AdvisoryBriefing(
            type: type,
            title: buildBriefingTitle(type: type),
            executiveSummary: buildExecutiveSummary(
                threats: threats.count,
                opportunities: opportunities.count,
                predictions: predictions.count,
                patterns: patterns.count
            ),
            sections: sections,
            recommendations: recommendations,
            riskSummary: riskSummary,
            confidence: computeAverageConfidence(insights)
        )
    }

    // MARK: - Portfolio Optimization

    /// Generate portfolio optimization suggestions.
    /// - Returns: Recommendations for portfolio adjustments.
    func portfolioOptimizationSuggestions() async -> [StrategicRecommendation] {
        // TODO: Implement portfolio optimization
        // - Analyze current allocation vs optimal allocation
        // - Consider risk-adjusted returns
        // - Factor in correlation data
        // - Suggest rebalancing opportunities
        // - Tax-loss harvesting opportunities
        return []
    }

    // MARK: - Briefing Delivery

    /// Deliver the latest briefing via Oracle voice.
    func deliverBriefingVoice() async {
        guard let briefing = latestBriefing else { return }
        let voiceScript = buildVoiceScript(from: briefing)
        await voice.speakBriefing(voiceScript)
    }

    // MARK: - Queries

    /// Get the latest briefing.
    func getLatestBriefing() -> AdvisoryBriefing? {
        latestBriefing
    }

    /// Get briefing history.
    /// - Parameter limit: Maximum number of briefings to return.
    func getBriefingHistory(limit: Int = 10) -> [AdvisoryBriefing] {
        Array(briefingHistory.suffix(limit).reversed())
    }

    // MARK: - Private Helpers

    private func shouldGenerateBriefing() -> Bool {
        // Check minimum insight threshold
        guard pendingInsights.count >= briefingThreshold else { return false }

        // Check minimum time interval
        if let lastBriefing = briefingHistory.last {
            let elapsed = Date().timeIntervalSince(lastBriefing.generatedAt)
            guard elapsed >= minimumBriefingInterval else { return false }
        }

        // Always generate if critical threats exist
        if pendingInsights.contains(where: { $0.type == .threat && $0.priority >= .critical }) {
            return true
        }

        return true
    }

    private func summarizeInsights(_ insights: [OracleInsight]) -> String {
        // TODO: Generate natural language summary from insights
        insights.map { $0.content }.joined(separator: " ")
    }

    private func generateRecommendations(from insights: [OracleInsight]) -> [StrategicRecommendation] {
        // TODO: Generate actionable recommendations from insights
        var recommendations: [StrategicRecommendation] = []

        let threats = insights.filter { $0.type == .threat && $0.priority >= .high }
        for threat in threats {
            recommendations.append(StrategicRecommendation(
                action: "Review and mitigate: \(threat.content)",
                rationale: "High-priority threat detected requiring attention.",
                urgency: .timeSensitive,
                expectedImpact: "Risk reduction",
                riskLevel: "High",
                timeframe: "Immediate",
                confidence: threat.confidence
            ))
        }

        return recommendations
    }

    private func computeRiskSummary(threats: [OracleInsight]) -> RiskSummary {
        let riskLevel = threats.isEmpty ? 0.2 :
            min(1.0, Double(threats.count) * 0.15 + 0.3)

        return RiskSummary(
            overallRiskLevel: riskLevel,
            topRisks: threats.prefix(3).map { $0.content },
            mitigationStatus: threats.isEmpty ? "No active threats" : "Requires review",
            portfolioAtRiskPercent: riskLevel * 20.0 // Simplified estimate
        )
    }

    private func buildBriefingTitle(type: BriefingType) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let timestamp = formatter.string(from: Date())

        switch type {
        case .daily:            return "Daily Strategic Briefing — \(timestamp)"
        case .weekly:           return "Weekly Intelligence Report — \(timestamp)"
        case .eventDriven:      return "Strategic Update — \(timestamp)"
        case .portfolioReview:  return "Portfolio Optimization Review — \(timestamp)"
        case .threatBriefing:   return "THREAT BRIEFING — \(timestamp)"
        case .opportunity:      return "Opportunity Alert — \(timestamp)"
        }
    }

    private func buildExecutiveSummary(threats: Int, opportunities: Int, predictions: Int, patterns: Int) -> String {
        var parts: [String] = []
        if threats > 0 { parts.append("\(threats) active threat\(threats == 1 ? "" : "s")") }
        if opportunities > 0 { parts.append("\(opportunities) opportunity\(opportunities == 1 ? "" : " opportunities") identified") }
        if predictions > 0 { parts.append("\(predictions) predictive model\(predictions == 1 ? "" : "s") updated") }
        if patterns > 0 { parts.append("\(patterns) pattern\(patterns == 1 ? "" : "s") detected") }
        return parts.joined(separator: ". ") + "."
    }

    private func computeAverageConfidence(_ insights: [OracleInsight]) -> Double {
        guard !insights.isEmpty else { return 0.0 }
        return insights.reduce(0.0) { $0 + $1.confidence } / Double(insights.count)
    }

    private func buildVoiceScript(from briefing: AdvisoryBriefing) -> String {
        var script = "Strategic briefing. \(briefing.executiveSummary) "

        for section in briefing.sections.sorted(by: { $0.priority < $1.priority }) {
            script += "\(section.title). \(section.content) "
        }

        if !briefing.recommendations.isEmpty {
            script += "Recommendations. "
            for rec in briefing.recommendations.prefix(3) {
                script += "\(rec.action). "
            }
        }

        return script
    }
}
