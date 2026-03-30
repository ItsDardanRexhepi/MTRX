//
//  ThreatDetection.swift
//  MTRX — Oracle
//
//  Pre-incident pattern recognition. Security threat detection, anomalous transactions,
//  and smart contract vulnerability scanning.
//

import Foundation

// MARK: - Threat

/// A detected or potential security threat.
struct Threat: Identifiable, Sendable {
    let id: UUID
    let type: ThreatType
    let severity: ThreatSeverity
    let title: String
    let description: String
    let detectedAt: Date
    let affectedAssets: [String]
    let indicators: [ThreatIndicator]
    let recommendedActions: [String]
    let confidence: Double
    let isConfirmed: Bool

    init(
        id: UUID = UUID(),
        type: ThreatType,
        severity: ThreatSeverity,
        title: String,
        description: String,
        affectedAssets: [String] = [],
        indicators: [ThreatIndicator] = [],
        recommendedActions: [String] = [],
        confidence: Double,
        isConfirmed: Bool = false
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.title = title
        self.description = description
        self.detectedAt = Date()
        self.affectedAssets = affectedAssets
        self.indicators = indicators
        self.recommendedActions = recommendedActions
        self.confidence = confidence
        self.isConfirmed = isConfirmed
    }
}

// MARK: - Threat Type

enum ThreatType: String, Sendable, CaseIterable {
    case anomalousTransaction   // Unusual transaction pattern
    case smartContractVuln      // Smart contract vulnerability
    case phishingAttempt        // Phishing or social engineering
    case rugPull                // Potential rug pull indicators
    case flashLoanAttack        // Flash loan attack pattern
    case oracleManipulation     // Price oracle manipulation
    case walletCompromise       // Wallet key compromise indicators
    case exchangeRisk           // Exchange solvency concerns
    case bridgeExploit          // Cross-chain bridge vulnerability
    case governanceAttack       // Protocol governance manipulation
    case dusting                // Dusting attack on wallet
    case addressPoisoning       // Address poisoning attack
}

// MARK: - Threat Severity

enum ThreatSeverity: Int, Sendable, Comparable, CaseIterable {
    case informational = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    var displayName: String {
        switch self {
        case .informational: return "Informational"
        case .low:           return "Low"
        case .medium:        return "Medium"
        case .high:          return "High"
        case .critical:      return "Critical"
        }
    }

    static func < (lhs: ThreatSeverity, rhs: ThreatSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Threat Indicator

/// A specific indicator that contributed to threat detection.
struct ThreatIndicator: Sendable {
    let name: String
    let value: String
    let expectedRange: String
    let weight: Double
    let source: String
}

// MARK: - Threat Detection

/// Pre-incident pattern recognition engine.
/// Scans for security threats, anomalous transactions, and smart contract vulnerabilities.
final class ThreatDetection {

    // MARK: - Properties

    private var activeThreats: [Threat] = []
    private var threatHistory: [Threat] = []
    private var monitoredContracts: Set<String> = []
    private var monitoredWallets: Set<String> = []
    private var transactionBaseline: TransactionBaseline?
    private let maxActiveThreats: Int = 50

    // MARK: - Transaction Baseline

    /// Statistical baseline for normal transaction patterns.
    struct TransactionBaseline: Sendable {
        let averageTransactionSize: Double
        let standardDeviation: Double
        let averageDailyTransactions: Int
        let typicalTimesOfDay: [Int]  // Hours (0-23)
        let knownCounterparties: Set<String>
        let lastUpdated: Date
    }

    // MARK: - Scanning

    /// Run a full threat scan across all monitored assets and patterns.
    /// - Returns: Oracle insights generated from detected threats.
    func scan() async -> [OracleInsight] {
        var insights: [OracleInsight] = []

        // 1. Scan for anomalous transactions
        let transactionThreats = await scanTransactions()
        activeThreats.append(contentsOf: transactionThreats)

        // 2. Scan monitored smart contracts
        let contractThreats = await scanSmartContracts()
        activeThreats.append(contentsOf: contractThreats)

        // 3. Check for known attack patterns
        let attackPatterns = await detectAttackPatterns()
        activeThreats.append(contentsOf: attackPatterns)

        // 4. Check exchange health
        let exchangeThreats = await monitorExchangeHealth()
        activeThreats.append(contentsOf: exchangeThreats)

        // Convert threats to insights
        let allThreats = transactionThreats + contractThreats + attackPatterns + exchangeThreats
        for threat in allThreats {
            insights.append(OracleInsight(
                type: .threat,
                category: .security,
                content: "\(threat.title): \(threat.description)",
                confidence: threat.confidence,
                priority: mapThreatPriority(threat.severity),
                metadata: [
                    "threat_type": threat.type.rawValue,
                    "threat_severity": threat.severity.displayName,
                    "affected_assets": threat.affectedAssets.joined(separator: ",")
                ]
            ))
        }

        // Prune resolved threats
        pruneThreats()

        return insights
    }

    // MARK: - Transaction Monitoring

    /// Scan recent transactions for anomalous patterns.
    private func scanTransactions() async -> [Threat] {
        var threats: [Threat] = []

        // TODO: Implement transaction anomaly detection
        // - Compare against baseline transaction patterns
        // - Flag unusually large transactions
        // - Detect transactions at unusual times
        // - Check for unknown counterparties
        // - Monitor for rapid sequential transactions (draining)

        guard let baseline = transactionBaseline else { return threats }

        // TODO: Fetch recent transactions and compare against baseline
        // Example detection logic:
        // if transaction.amount > baseline.averageTransactionSize + 3 * baseline.standardDeviation {
        //     threats.append(...)
        // }

        return threats
    }

    // MARK: - Smart Contract Scanning

    /// Scan monitored smart contracts for vulnerabilities.
    private func scanSmartContracts() async -> [Threat] {
        var threats: [Threat] = []

        for contractAddress in monitoredContracts {
            // TODO: Implement smart contract vulnerability scanning
            // - Check for known vulnerability signatures
            // - Monitor for unusual state changes
            // - Detect proxy upgrade events
            // - Check admin key usage patterns
            // - Monitor TVL changes (sudden outflows)
            // - Check for reentrancy patterns
        }

        return threats
    }

    // MARK: - Attack Pattern Detection

    /// Detect known attack patterns across all monitored data.
    private func detectAttackPatterns() async -> [Threat] {
        var threats: [Threat] = []

        // TODO: Implement pattern matching for known attack vectors
        // - Flash loan attack signatures
        // - Price oracle manipulation patterns
        // - Governance attack voting patterns
        // - Address poisoning detection
        // - Dust attack detection

        return threats
    }

    // MARK: - Exchange Health Monitoring

    /// Monitor exchange health indicators.
    private func monitorExchangeHealth() async -> [Threat] {
        var threats: [Threat] = []

        // TODO: Monitor exchange health signals
        // - Proof of reserves changes
        // - Withdrawal delay reports
        // - Large outflow patterns
        // - Social media sentiment about exchange

        return threats
    }

    // MARK: - Configuration

    /// Add a smart contract address to monitor.
    /// - Parameter address: The contract address.
    func monitorContract(_ address: String) {
        monitoredContracts.insert(address)
    }

    /// Add a wallet address to monitor.
    /// - Parameter address: The wallet address.
    func monitorWallet(_ address: String) {
        monitoredWallets.insert(address)
    }

    /// Update the transaction baseline with new data.
    /// - Parameter baseline: The updated baseline.
    func updateBaseline(_ baseline: TransactionBaseline) {
        transactionBaseline = baseline
    }

    // MARK: - Queries

    /// Get all active threats above a given severity.
    func threats(minimumSeverity: ThreatSeverity = .low) -> [Threat] {
        activeThreats.filter { $0.severity >= minimumSeverity }
            .sorted { $0.severity > $1.severity }
    }

    /// Get threats for a specific asset.
    func threats(for asset: String) -> [Threat] {
        activeThreats.filter { $0.affectedAssets.contains(asset) }
    }

    // MARK: - Private Helpers

    private func mapThreatPriority(_ severity: ThreatSeverity) -> InsightPriority {
        switch severity {
        case .informational: return .low
        case .low:           return .low
        case .medium:        return .normal
        case .high:          return .high
        case .critical:      return .critical
        }
    }

    private func pruneThreats() {
        // Move old threats to history
        let cutoff = Date().addingTimeInterval(-86400 * 7) // 7 days
        let oldThreats = activeThreats.filter { $0.detectedAt < cutoff }
        threatHistory.append(contentsOf: oldThreats)
        activeThreats.removeAll { $0.detectedAt < cutoff }

        // Cap active threats
        if activeThreats.count > maxActiveThreats {
            let overflow = activeThreats.sorted { $0.severity < $1.severity }
            let toRemove = overflow.prefix(activeThreats.count - maxActiveThreats)
            threatHistory.append(contentsOf: toRemove)
            activeThreats = Array(activeThreats.suffix(maxActiveThreats))
        }
    }
}
