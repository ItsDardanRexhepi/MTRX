//
//  PatternIntelligence.swift
//  MTRX — Oracle
//
//  Cross-feed correlation engine. Detects patterns and anomalies across all data feeds.
//

import Foundation

// MARK: - Data Feed

/// Represents a live data feed that Oracle monitors for pattern detection.
enum DataFeed: String, CaseIterable, Sendable {
    case marketPrice       // Real-time price data
    case onChainMetrics    // Blockchain on-chain data
    case socialSentiment   // Social media sentiment
    case healthBiometrics  // User health data from HealthKit
    case locationPatterns  // User location history
    case transactionFlow   // User transaction patterns
    case newsFlow          // News and regulatory updates
    case networkMetrics    // Blockchain network health
    case exchangeFlows     // Exchange inflow/outflow
    case whaleTracking     // Large wallet movements
}

// MARK: - Detected Pattern

/// A pattern detected by the cross-feed correlation engine.
struct DetectedPattern: Identifiable, Sendable {
    let id: UUID
    let type: PatternType
    let feeds: [DataFeed]
    let description: String
    let strength: Double         // 0.0-1.0 correlation strength
    let confidence: Double       // 0.0-1.0 statistical confidence
    let firstObserved: Date
    let lastObserved: Date
    let occurrences: Int
    let isAnomaly: Bool
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        type: PatternType,
        feeds: [DataFeed],
        description: String,
        strength: Double,
        confidence: Double,
        firstObserved: Date = Date(),
        lastObserved: Date = Date(),
        occurrences: Int = 1,
        isAnomaly: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.feeds = feeds
        self.description = description
        self.strength = strength
        self.confidence = confidence
        self.firstObserved = firstObserved
        self.lastObserved = lastObserved
        self.occurrences = occurrences
        self.isAnomaly = isAnomaly
        self.metadata = metadata
    }
}

// MARK: - Pattern Type

enum PatternType: String, Sendable, CaseIterable {
    case correlation       // Two or more feeds showing correlated behavior
    case divergence        // Expected correlation breaking
    case cycle             // Repeating cyclical pattern
    case trend             // Sustained directional movement
    case anomaly           // Statistical outlier
    case leadLag           // One feed predicting another
    case meanReversion     // Value returning to historical mean
    case regimeChange      // Fundamental change in behavior
}

// MARK: - Pattern Intelligence

/// Cross-feed correlation engine that detects patterns and anomalies
/// across all monitored data feeds.
final class PatternIntelligence {

    // MARK: - Properties

    private var knownPatterns: [DetectedPattern] = []
    private var correlationMatrix: [String: Double] = [:]
    private let minimumCorrelationStrength: Double = 0.60
    private let minimumConfidence: Double = 0.65
    private let historyWindow: TimeInterval = 86400 * 30 // 30 days

    // MARK: - Feed Data Cache

    private var feedDataCache: [DataFeed: [DataPoint]] = [:]

    struct DataPoint: Sendable {
        let timestamp: Date
        let value: Double
        let feed: DataFeed
    }

    // MARK: - Analysis

    /// Run pattern analysis across all feeds.
    /// - Returns: Oracle insights generated from detected patterns.
    func analyze() async -> [OracleInsight] {
        var insights: [OracleInsight] = []

        // 1. Update feed data
        await refreshFeedData()

        // 2. Compute cross-feed correlations
        let correlations = computeCorrelations()

        // 3. Detect new patterns
        let newPatterns = detectPatterns(from: correlations)

        // 4. Detect anomalies
        let anomalies = detectAnomalies()

        // 5. Convert patterns to insights
        for pattern in newPatterns {
            let insight = OracleInsight(
                type: pattern.isAnomaly ? .anomaly : .pattern,
                category: categorize(feeds: pattern.feeds),
                content: pattern.description,
                confidence: pattern.confidence,
                priority: prioritize(pattern),
                metadata: pattern.metadata
            )
            insights.append(insight)
        }

        // 6. Convert anomalies to insights
        for anomaly in anomalies {
            let insight = OracleInsight(
                type: .anomaly,
                category: categorize(feeds: anomaly.feeds),
                content: anomaly.description,
                confidence: anomaly.confidence,
                priority: .high,
                metadata: anomaly.metadata
            )
            insights.append(insight)
        }

        knownPatterns.append(contentsOf: newPatterns)
        return insights
    }

    /// Correlate a specific pair of feeds.
    /// - Parameters:
    ///   - feedA: First data feed.
    ///   - feedB: Second data feed.
    /// - Returns: Correlation coefficient (-1.0 to 1.0).
    func correlate(_ feedA: DataFeed, _ feedB: DataFeed) -> Double {
        guard let dataA = feedDataCache[feedA],
              let dataB = feedDataCache[feedB],
              !dataA.isEmpty, !dataB.isEmpty else {
            return 0.0
        }

        // TODO: Implement Pearson correlation with time-alignment
        // - Align timestamps between feeds
        // - Compute rolling correlation windows
        // - Apply lag detection for lead/lag relationships
        return 0.0
    }

    /// Get all known patterns for a specific feed.
    /// - Parameter feed: The data feed to query.
    /// - Returns: Patterns involving this feed.
    func patterns(for feed: DataFeed) -> [DetectedPattern] {
        knownPatterns.filter { $0.feeds.contains(feed) }
    }

    // MARK: - Private Helpers

    private func refreshFeedData() async {
        // TODO: Fetch latest data from each feed provider
        for feed in DataFeed.allCases {
            // feedDataCache[feed] = await fetchFeedData(feed)
        }
    }

    private func computeCorrelations() -> [String: Double] {
        var matrix: [String: Double] = [:]

        let feeds = DataFeed.allCases
        for i in 0..<feeds.count {
            for j in (i + 1)..<feeds.count {
                let key = "\(feeds[i].rawValue)_\(feeds[j].rawValue)"
                matrix[key] = correlate(feeds[i], feeds[j])
            }
        }

        correlationMatrix = matrix
        return matrix
    }

    private func detectPatterns(from correlations: [String: Double]) -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []

        for (key, value) in correlations {
            let feeds = key.split(separator: "_").compactMap { feedName in
                DataFeed(rawValue: String(feedName))
            }

            // Strong positive correlation
            if value >= minimumCorrelationStrength {
                patterns.append(DetectedPattern(
                    type: .correlation,
                    feeds: feeds,
                    description: "Strong positive correlation detected between \(feeds.map { $0.rawValue }.joined(separator: " and "))",
                    strength: value,
                    confidence: min(value + 0.1, 1.0)
                ))
            }

            // Divergence from expected correlation
            if let known = knownPatterns.first(where: { $0.feeds == feeds && $0.type == .correlation }) {
                if abs(value - known.strength) > 0.30 {
                    patterns.append(DetectedPattern(
                        type: .divergence,
                        feeds: feeds,
                        description: "Correlation divergence: expected \(String(format: "%.2f", known.strength)), observed \(String(format: "%.2f", value))",
                        strength: abs(value - known.strength),
                        confidence: 0.75,
                        isAnomaly: true
                    ))
                }
            }
        }

        return patterns
    }

    private func detectAnomalies() -> [DetectedPattern] {
        // TODO: Implement statistical anomaly detection
        // - Z-score analysis across all feeds
        // - Isolation forest for multivariate anomalies
        // - CUSUM for change-point detection
        return []
    }

    private func categorize(feeds: [DataFeed]) -> InsightCategory {
        if feeds.contains(.healthBiometrics) { return .behavioral }
        if feeds.contains(.marketPrice) || feeds.contains(.exchangeFlows) { return .market }
        if feeds.contains(.newsFlow) { return .regulatory }
        if feeds.contains(.onChainMetrics) || feeds.contains(.networkMetrics) { return .technical }
        return .portfolio
    }

    private func prioritize(_ pattern: DetectedPattern) -> InsightPriority {
        if pattern.isAnomaly && pattern.strength > 0.80 { return .critical }
        if pattern.strength > 0.70 { return .high }
        if pattern.strength > 0.50 { return .normal }
        return .low
    }
}
