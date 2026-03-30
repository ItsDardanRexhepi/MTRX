// ContextAssembler.swift
// MTRX Apple Integration — Awareness
// Aggregates all awareness signals into a unified Trinity context

import Foundation

// MARK: - Context Assembler

final class ContextAssembler {

    // MARK: - Shared Instance

    static let shared = ContextAssembler()

    // MARK: - Unified Context

    struct TrinityContext {
        let health: HealthKitManager.HealthSnapshot?
        let location: LocationManager.LocationContext?
        let weather: WeatherManager.WeatherContext?
        let motion: SensorFusion.BehavioralContext?
        let focus: FocusConfiguration?
        let derivedInsights: [ContextInsight]
        let contextScore: Double // 0.0 to 1.0 — how much context is available
        let timestamp: Date
    }

    struct ContextInsight {
        let category: InsightCategory
        let title: String
        let description: String
        let relevanceScore: Double
        let actionable: Bool
        let suggestedAction: String?
    }

    enum InsightCategory: String {
        case healthRisk
        case locationOpportunity
        case weatherInsurance
        case behavioralPattern
        case focusModeAdjustment
        case transactionTiming
        case riskWarning
    }

    // MARK: - Properties

    private var lastContext: TrinityContext?
    private var contextUpdateInterval: TimeInterval = 30 // seconds
    private var lastUpdateTime: Date?

    // MARK: - Assemble Context

    /// Assembles a complete context from all awareness sources.
    func assembleContext() async -> TrinityContext {
        // Check cache
        if let lastUpdate = lastUpdateTime,
           Date().timeIntervalSince(lastUpdate) < contextUpdateInterval,
           let cached = lastContext {
            return cached
        }

        // Gather all signals in parallel
        async let health = fetchHealth()
        async let location = fetchLocation()
        async let weather = fetchWeather()
        async let motion = fetchMotion()
        let focus = fetchFocus()

        let healthData = await health
        let locationData = await location
        let weatherData = await weather
        let motionData = await motion

        // Derive insights from combined signals
        let insights = deriveInsights(
            health: healthData,
            location: locationData,
            weather: weatherData,
            motion: motionData,
            focus: focus
        )

        // Calculate context completeness score
        let score = calculateContextScore(
            health: healthData,
            location: locationData,
            weather: weatherData,
            motion: motionData,
            focus: focus
        )

        let context = TrinityContext(
            health: healthData,
            location: locationData,
            weather: weatherData,
            motion: motionData,
            focus: focus,
            derivedInsights: insights,
            contextScore: score,
            timestamp: Date()
        )

        lastContext = context
        lastUpdateTime = Date()

        return context
    }

    // MARK: - Data Fetching

    private func fetchHealth() async -> HealthKitManager.HealthSnapshot? {
        return try? await HealthKitManager.shared.currentSnapshot()
    }

    private func fetchLocation() async -> LocationManager.LocationContext? {
        return await LocationManager.shared.currentContext()
    }

    private func fetchWeather() async -> WeatherManager.WeatherContext? {
        guard let location = LocationManager.shared.currentLocation else { return nil }
        return try? await WeatherManager.shared.fetchContext(for: location)
    }

    private func fetchMotion() async -> SensorFusion.BehavioralContext? {
        return await SensorFusion.shared.currentContext()
    }

    private func fetchFocus() -> FocusConfiguration? {
        return FocusFilterStore.shared.currentConfiguration
    }

    // MARK: - Insight Derivation

    private func deriveInsights(
        health: HealthKitManager.HealthSnapshot?,
        location: LocationManager.LocationContext?,
        weather: WeatherManager.WeatherContext?,
        motion: SensorFusion.BehavioralContext?,
        focus: FocusConfiguration?
    ) -> [ContextInsight] {
        var insights: [ContextInsight] = []

        // Health-based insights
        if let health = health {
            if health.stressLevel == .high || health.stressLevel == .veryHigh {
                insights.append(ContextInsight(
                    category: .healthRisk,
                    title: "Elevated Stress Detected",
                    description: "Your stress indicators are elevated. Consider deferring major financial decisions.",
                    relevanceScore: 0.9,
                    actionable: true,
                    suggestedAction: "Defer non-urgent transactions"
                ))
            }

            if let sleep = health.sleepAnalysis, sleep.totalSleepHours < 5 {
                insights.append(ContextInsight(
                    category: .healthRisk,
                    title: "Sleep Deficit",
                    description: "Poor sleep quality may impair decision-making.",
                    relevanceScore: 0.7,
                    actionable: true,
                    suggestedAction: "Add confirmation step for large transactions"
                ))
            }
        }

        // Weather-insurance insights
        if let weather = weather {
            for trigger in weather.insuranceTriggers {
                insights.append(ContextInsight(
                    category: .weatherInsurance,
                    title: "Insurance Trigger: \(trigger.type.rawValue)",
                    description: trigger.description,
                    relevanceScore: trigger.severity,
                    actionable: true,
                    suggestedAction: "Review affected insurance products: \(trigger.affectedProducts.joined(separator: ", "))"
                ))
            }
        }

        // Location-based insights
        if let location = location {
            switch location.locationType {
            case .exchange:
                insights.append(ContextInsight(
                    category: .locationOpportunity,
                    title: "Near Exchange Location",
                    description: "You are near a known exchange office.",
                    relevanceScore: 0.5,
                    actionable: false,
                    suggestedAction: nil
                ))
            case .travel:
                insights.append(ContextInsight(
                    category: .locationOpportunity,
                    title: "Travel Detected",
                    description: "Adjusting transaction geography warnings.",
                    relevanceScore: 0.6,
                    actionable: true,
                    suggestedAction: "Enable travel mode for fraud prevention"
                ))
            default:
                break
            }
        }

        // Motion-based insights
        if let motion = motion {
            if motion.activity == .driving {
                insights.append(ContextInsight(
                    category: .behavioralPattern,
                    title: "Driving Detected",
                    description: "Trinity will use voice-only mode and suppress visual alerts.",
                    relevanceScore: 0.8,
                    actionable: true,
                    suggestedAction: "Switch to voice-only mode"
                ))
            }

            if motion.movement.isShaking {
                insights.append(ContextInsight(
                    category: .riskWarning,
                    title: "Unstable Movement",
                    description: "Device instability detected. Confirming actions may be difficult.",
                    relevanceScore: 0.4,
                    actionable: false,
                    suggestedAction: nil
                ))
            }
        }

        // Focus mode insights
        if let focus = focus, focus.quietMode {
            insights.append(ContextInsight(
                category: .focusModeAdjustment,
                title: "Focus Mode Active",
                description: "Non-critical notifications are suppressed.",
                relevanceScore: 0.6,
                actionable: false,
                suggestedAction: nil
            ))
        }

        // Sort by relevance
        return insights.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    // MARK: - Context Score

    private func calculateContextScore(
        health: HealthKitManager.HealthSnapshot?,
        location: LocationManager.LocationContext?,
        weather: WeatherManager.WeatherContext?,
        motion: SensorFusion.BehavioralContext?,
        focus: FocusConfiguration?
    ) -> Double {
        var score = 0.0
        var total = 5.0

        if health != nil { score += 1.0 }
        if location != nil { score += 1.0 }
        if weather != nil { score += 1.0 }
        if motion != nil { score += 1.0 }
        if focus != nil { score += 1.0 }

        return score / total
    }

    // MARK: - Context Serialization

    /// Serializes the context into a dictionary for Trinity's prompt engine.
    func serializeForPrompt(_ context: TrinityContext) -> [String: Any] {
        var dict: [String: Any] = [
            "context_score": context.contextScore,
            "timestamp": ISO8601DateFormatter().string(from: context.timestamp)
        ]

        if let health = context.health {
            dict["health"] = [
                "stress_level": health.stressLevel.rawValue,
                "heart_rate": health.heartRate as Any,
                "hrv": health.heartRateVariability as Any
            ]
        }

        if let location = context.location {
            dict["location"] = [
                "type": location.locationType.rawValue,
                "is_significant": location.isSignificantLocation
            ]
        }

        if let weather = context.weather {
            dict["weather"] = [
                "risk_level": weather.riskLevel.rawValue,
                "triggers_count": weather.insuranceTriggers.count
            ]
        }

        if let motion = context.motion {
            dict["motion"] = [
                "activity": motion.activity.rawValue,
                "is_stationary": motion.isStationary
            ]
        }

        dict["insights"] = context.derivedInsights.map { [
            "category": $0.category.rawValue,
            "title": $0.title,
            "relevance": $0.relevanceScore,
            "actionable": $0.actionable
        ] }

        return dict
    }
}
