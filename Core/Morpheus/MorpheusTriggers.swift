//
//  MorpheusTriggers.swift
//  MTRX — Morpheus
//
//  Conditions that surface Morpheus. Defines trigger types and their evaluation logic.
//

import Foundation

// MARK: - Morpheus Trigger

/// Conditions that can trigger a Morpheus pivotal moment alert.
enum MorpheusTrigger: String, CaseIterable, Sendable {
    case suddenPriceDrop         // Asset price drops beyond threshold
    case suddenPriceSpike        // Asset price spikes beyond threshold
    case liquidationApproaching  // Leveraged position nearing liquidation
    case whaleTransaction        // Large wallet transaction detected
    case protocolExploit         // Smart contract exploit detected
    case regulatoryAnnouncement  // Regulatory body announcement
    case correlationAnomaly      // Cross-asset correlation breaks pattern
    case volumeAnomaly           // Unusual trading volume detected
    case sentimentShift          // Market sentiment sudden reversal
    case portfolioThreshold      // Portfolio value hits predefined milestone
    case securityThreat          // Account or wallet security threat
    case taxDeadline             // Tax-relevant deadline approaching
    case stablecoinDepeg         // Stablecoin losing peg
    case networkCongestion       // Blockchain network congestion spike
    case yieldOpportunity        // High-yield opportunity detected

    // MARK: - Display Properties

    var displayName: String {
        switch self {
        case .suddenPriceDrop:        return "Sudden Price Drop"
        case .suddenPriceSpike:       return "Sudden Price Spike"
        case .liquidationApproaching: return "Liquidation Warning"
        case .whaleTransaction:       return "Whale Movement"
        case .protocolExploit:        return "Protocol Exploit"
        case .regulatoryAnnouncement: return "Regulatory Alert"
        case .correlationAnomaly:     return "Correlation Anomaly"
        case .volumeAnomaly:          return "Volume Anomaly"
        case .sentimentShift:         return "Sentiment Shift"
        case .portfolioThreshold:     return "Portfolio Milestone"
        case .securityThreat:         return "Security Threat"
        case .taxDeadline:            return "Tax Deadline"
        case .stablecoinDepeg:        return "Stablecoin Depeg"
        case .networkCongestion:      return "Network Congestion"
        case .yieldOpportunity:       return "Yield Opportunity"
        }
    }

    var description: String {
        switch self {
        case .suddenPriceDrop:
            return "A held asset has experienced a rapid, significant price decline."
        case .suddenPriceSpike:
            return "A held asset has experienced a rapid, significant price increase."
        case .liquidationApproaching:
            return "A leveraged position is approaching its liquidation threshold."
        case .whaleTransaction:
            return "A large wallet has made a significant transaction affecting a held asset."
        case .protocolExploit:
            return "A potential exploit or vulnerability has been detected in a protocol with holdings."
        case .regulatoryAnnouncement:
            return "A regulatory body has made an announcement affecting held assets."
        case .correlationAnomaly:
            return "A historical correlation between tracked assets has broken."
        case .volumeAnomaly:
            return "Unusual trading volume detected for a held asset."
        case .sentimentShift:
            return "Market sentiment has shifted abruptly for a tracked sector."
        case .portfolioThreshold:
            return "Portfolio total value has crossed a significant threshold."
        case .securityThreat:
            return "A security threat has been detected on a connected account or wallet."
        case .taxDeadline:
            return "A tax-relevant deadline is approaching that requires attention."
        case .stablecoinDepeg:
            return "A stablecoin in the portfolio is losing its peg."
        case .networkCongestion:
            return "Blockchain network congestion is unusually high, affecting transaction costs."
        case .yieldOpportunity:
            return "A time-limited high-yield opportunity has been identified."
        }
    }

    /// The type of pivotal moment this trigger produces.
    var momentType: PivotalMomentType {
        switch self {
        case .suddenPriceDrop, .suddenPriceSpike:
            return .marketCrash
        case .liquidationApproaching:
            return .liquidationRisk
        case .whaleTransaction:
            return .whaleMovement
        case .protocolExploit:
            return .smartContractRisk
        case .regulatoryAnnouncement:
            return .regulatoryChange
        case .correlationAnomaly:
            return .correlationBreak
        case .volumeAnomaly, .sentimentShift:
            return .opportunityWindow
        case .portfolioThreshold:
            return .portfolioMilestone
        case .securityThreat:
            return .securityBreach
        case .taxDeadline:
            return .taxEvent
        case .stablecoinDepeg:
            return .marketCrash
        case .networkCongestion:
            return .opportunityWindow
        case .yieldOpportunity:
            return .opportunityWindow
        }
    }

    /// Default severity for this trigger type.
    var defaultSeverity: MomentSeverity {
        switch self {
        case .protocolExploit, .securityThreat, .liquidationApproaching, .stablecoinDepeg:
            return .critical
        case .suddenPriceDrop, .whaleTransaction, .regulatoryAnnouncement:
            return .urgent
        case .suddenPriceSpike, .correlationAnomaly, .volumeAnomaly, .taxDeadline:
            return .important
        case .sentimentShift, .portfolioThreshold, .networkCongestion, .yieldOpportunity:
            return .advisory
        }
    }

    /// Build the default trigger condition for this trigger type.
    var condition: TriggerCondition? {
        switch self {
        case .suddenPriceDrop:
            return TriggerCondition(
                name: displayName,
                threshold: -0.10, // 10% drop
                comparisonType: .lessThan,
                timeWindow: 3600, // 1 hour
                evaluator: { context in
                    // TODO: Check portfolio for assets with >10% drop in last hour
                    guard let portfolio = context.portfolioState else { return false }
                    return portfolio.dailyChangePercent < -10.0
                }
            )
        case .liquidationApproaching:
            return TriggerCondition(
                name: displayName,
                threshold: 0.15, // 15% margin remaining
                comparisonType: .lessThan,
                timeWindow: nil,
                evaluator: { context in
                    // TODO: Check leveraged positions against liquidation thresholds
                    return false
                }
            )
        default:
            // TODO: Implement conditions for all trigger types
            return TriggerCondition(
                name: displayName,
                threshold: 0.0,
                comparisonType: .greaterThan,
                timeWindow: nil,
                evaluator: { _ in false }
            )
        }
    }
}

// MARK: - Trigger Condition

/// Defines the evaluation parameters for a Morpheus trigger.
struct TriggerCondition: @unchecked Sendable {
    let name: String
    let threshold: Double
    let comparisonType: ComparisonType
    let timeWindow: TimeInterval? // seconds
    let evaluator: (UserContext) -> Bool

    enum ComparisonType: String, Sendable {
        case greaterThan
        case lessThan
        case equals
        case deviatesBy // Deviation from mean
    }

    /// Evaluate this condition against the current context.
    /// - Parameter context: The user's current context.
    /// - Returns: True if the trigger condition is met.
    func evaluate(context: UserContext) -> Bool {
        return evaluator(context)
    }
}

// MARK: - Trigger Group

/// Groups related triggers for batch evaluation.
struct TriggerGroup: Sendable {
    let name: String
    let triggers: [MorpheusTrigger]
    let evaluationPriority: Int

    static let marketTriggers = TriggerGroup(
        name: "Market",
        triggers: [.suddenPriceDrop, .suddenPriceSpike, .volumeAnomaly, .correlationAnomaly, .sentimentShift],
        evaluationPriority: 0
    )

    static let securityTriggers = TriggerGroup(
        name: "Security",
        triggers: [.protocolExploit, .securityThreat, .stablecoinDepeg],
        evaluationPriority: 0
    )

    static let positionTriggers = TriggerGroup(
        name: "Position",
        triggers: [.liquidationApproaching, .whaleTransaction, .portfolioThreshold],
        evaluationPriority: 1
    )

    static let complianceTriggers = TriggerGroup(
        name: "Compliance",
        triggers: [.regulatoryAnnouncement, .taxDeadline],
        evaluationPriority: 2
    )

    static let opportunityTriggers = TriggerGroup(
        name: "Opportunity",
        triggers: [.yieldOpportunity, .networkCongestion],
        evaluationPriority: 3
    )
}
