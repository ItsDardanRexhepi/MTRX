//
//  CoordinationIntelligence.swift
//  MTRX — Oracle
//
//  Coordinates between all intelligence layers (Trinity, Morpheus, Oracle).
//  Prevents conflicting advice and manages resource allocation.
//

import Foundation

// MARK: - Intelligence Layer

/// The intelligence layers in the MTRX system.
enum IntelligenceLayer: String, Sendable, CaseIterable {
    case trinity     // User-facing conversational layer
    case morpheus    // Pivotal moment detection layer
    case oracle      // Background intelligence layer
}

// MARK: - Coordination Decision

/// A decision made by the coordination engine about how to handle an insight.
struct CoordinationDecision: Sendable {
    let insight: OracleInsight
    let targetLayer: IntelligenceLayer
    let action: CoordinationAction
    let reason: String
    let timestamp: Date

    init(insight: OracleInsight, targetLayer: IntelligenceLayer, action: CoordinationAction, reason: String) {
        self.insight = insight
        self.targetLayer = targetLayer
        self.action = action
        self.reason = reason
        self.timestamp = Date()
    }
}

// MARK: - Coordination Action

enum CoordinationAction: String, Sendable {
    case deliver        // Send insight to the target layer
    case suppress       // Suppress conflicting or redundant insight
    case merge          // Merge with an existing insight
    case defer_         // Hold for later delivery
    case escalate       // Escalate priority
}

// MARK: - Resource Allocation

/// Tracks computational resource allocation across layers.
struct ResourceAllocation: Sendable {
    let layer: IntelligenceLayer
    var cpuBudgetPercent: Double
    var memoryBudgetMB: Double
    var networkBandwidthPercent: Double
    var isThrottled: Bool

    static let defaultAllocations: [IntelligenceLayer: ResourceAllocation] = [
        .trinity: ResourceAllocation(layer: .trinity, cpuBudgetPercent: 40, memoryBudgetMB: 256, networkBandwidthPercent: 30, isThrottled: false),
        .morpheus: ResourceAllocation(layer: .morpheus, cpuBudgetPercent: 25, memoryBudgetMB: 128, networkBandwidthPercent: 25, isThrottled: false),
        .oracle: ResourceAllocation(layer: .oracle, cpuBudgetPercent: 35, memoryBudgetMB: 512, networkBandwidthPercent: 45, isThrottled: false),
    ]
}

// MARK: - Coordination Intelligence

/// Coordinates between all intelligence layers to prevent conflicting advice,
/// manage resource allocation, and ensure coherent system behavior.
final class CoordinationIntelligence {

    // MARK: - Properties

    private var recentDecisions: [CoordinationDecision] = []
    private var activeInsightsByLayer: [IntelligenceLayer: [OracleInsight]] = [:]
    private var resourceAllocations: [IntelligenceLayer: ResourceAllocation]
    private let conflictResolutionQueue = DispatchQueue(label: "com.mtrx.coordination", qos: .userInitiated)
    private let maxRecentDecisions: Int = 500

    // MARK: - Initialization

    init() {
        self.resourceAllocations = ResourceAllocation.defaultAllocations
        for layer in IntelligenceLayer.allCases {
            activeInsightsByLayer[layer] = []
        }
    }

    // MARK: - Insight Coordination

    /// Coordinate a set of insights, resolving conflicts and routing to appropriate layers.
    /// - Parameter insights: The raw insights from Oracle's analysis cycle.
    /// - Returns: Coordinated insights ready for distribution.
    func coordinate(_ insights: [OracleInsight]) async -> [OracleInsight] {
        var coordinated: [OracleInsight] = []

        for insight in insights {
            let decision = routeInsight(insight)
            recentDecisions.append(decision)

            switch decision.action {
            case .deliver:
                coordinated.append(insight)
                activeInsightsByLayer[decision.targetLayer, default: []].append(insight)

            case .suppress:
                // Insight suppressed — log but don't deliver
                break

            case .merge:
                // Merge with existing insight
                if let merged = mergeWithExisting(insight, layer: decision.targetLayer) {
                    coordinated.append(merged)
                }

            case .defer_:
                // Queue for later delivery
                // TODO: Implement deferred delivery queue
                break

            case .escalate:
                // Escalate priority and deliver
                var escalated = insight
                // Create a new insight with higher priority (InsightPriority is not mutable)
                let escalatedInsight = OracleInsight(
                    type: insight.type,
                    category: insight.category,
                    content: insight.content,
                    confidence: insight.confidence,
                    priority: .critical,
                    metadata: insight.metadata,
                    sourceAnalysis: insight.sourceAnalysis
                )
                coordinated.append(escalatedInsight)
            }
        }

        // Check for cross-layer conflicts
        resolveConflicts()

        // Prune old decisions
        if recentDecisions.count > maxRecentDecisions {
            recentDecisions.removeFirst(recentDecisions.count - maxRecentDecisions)
        }

        return coordinated
    }

    // MARK: - Conflict Resolution

    /// Detect and resolve conflicts between insights across layers.
    private func resolveConflicts() {
        // TODO: Implement conflict detection logic
        // - Check if Trinity and Morpheus have contradictory recommendations
        // - Ensure Oracle insights don't cause Trinity to give conflicting advice
        // - Resolve timing conflicts (e.g., "buy now" vs "wait for dip")

        let trinityInsights = activeInsightsByLayer[.trinity] ?? []
        let morpheusInsights = activeInsightsByLayer[.morpheus] ?? []

        // Check for directional conflicts
        for trinityInsight in trinityInsights {
            for morpheusInsight in morpheusInsights {
                if areConflicting(trinityInsight, morpheusInsight) {
                    // Resolve in favor of higher confidence
                    // TODO: Implement more sophisticated conflict resolution
                    if trinityInsight.confidence < morpheusInsight.confidence {
                        activeInsightsByLayer[.trinity]?.removeAll { $0.id == trinityInsight.id }
                    } else {
                        activeInsightsByLayer[.morpheus]?.removeAll { $0.id == morpheusInsight.id }
                    }
                }
            }
        }
    }

    /// Check if two insights are conflicting.
    private func areConflicting(_ a: OracleInsight, _ b: OracleInsight) -> Bool {
        // TODO: Implement semantic conflict detection
        // For now, simple heuristic: same category with opposing types
        guard a.category == b.category else { return false }

        // Threat vs opportunity on same topic = conflict
        if (a.type == .threat && b.type == .opportunity) ||
           (a.type == .opportunity && b.type == .threat) {
            return true
        }

        return false
    }

    // MARK: - Insight Routing

    /// Determine which layer should receive an insight and what action to take.
    private func routeInsight(_ insight: OracleInsight) -> CoordinationDecision {
        // Threat insights go to Morpheus
        if insight.type == .threat {
            return CoordinationDecision(
                insight: insight,
                targetLayer: .morpheus,
                action: .deliver,
                reason: "Threat insights are routed to Morpheus for alert evaluation."
            )
        }

        // High-priority predictions go to both Trinity and Morpheus
        if insight.type == .prediction && insight.priority >= .high {
            return CoordinationDecision(
                insight: insight,
                targetLayer: .morpheus,
                action: .escalate,
                reason: "High-priority predictions escalated to Morpheus."
            )
        }

        // Recommendations go to Trinity for conversation
        if insight.type == .recommendation {
            return CoordinationDecision(
                insight: insight,
                targetLayer: .trinity,
                action: .deliver,
                reason: "Recommendations are surfaced through Trinity conversation."
            )
        }

        // Check for redundancy
        if isRedundant(insight) {
            return CoordinationDecision(
                insight: insight,
                targetLayer: .oracle,
                action: .suppress,
                reason: "Insight is redundant with existing active insight."
            )
        }

        // Default: deliver to Trinity
        return CoordinationDecision(
            insight: insight,
            targetLayer: .trinity,
            action: .deliver,
            reason: "Default routing to Trinity for contextual use."
        )
    }

    /// Check if an insight is redundant with existing active insights.
    private func isRedundant(_ insight: OracleInsight) -> Bool {
        for layerInsights in activeInsightsByLayer.values {
            for existing in layerInsights {
                if existing.type == insight.type &&
                   existing.category == insight.category &&
                   abs(existing.confidence - insight.confidence) < 0.1 {
                    // Same type and category with similar confidence — likely redundant
                    return true
                }
            }
        }
        return false
    }

    /// Merge an insight with an existing one in the target layer.
    private func mergeWithExisting(_ insight: OracleInsight, layer: IntelligenceLayer) -> OracleInsight? {
        // TODO: Implement insight merging logic
        // - Combine evidence from both insights
        // - Update confidence based on corroboration
        // - Merge metadata
        return insight
    }

    // MARK: - Resource Management

    /// Get current resource allocation for a layer.
    func allocation(for layer: IntelligenceLayer) -> ResourceAllocation? {
        resourceAllocations[layer]
    }

    /// Adjust resource allocation based on system load.
    /// - Parameter layer: The layer to adjust.
    /// - Parameter throttled: Whether to throttle the layer.
    func setThrottled(_ throttled: Bool, for layer: IntelligenceLayer) {
        resourceAllocations[layer]?.isThrottled = throttled
    }

    /// Rebalance resources based on current system demands.
    func rebalanceResources() {
        // TODO: Implement dynamic resource rebalancing
        // - Monitor CPU/memory usage per layer
        // - Adjust allocations based on priority and demand
        // - Ensure critical paths (Morpheus alerts) always have resources
    }
}
