//
//  Morpheus.swift
//  MTRX — Morpheus
//
//  Pivotal moment detection layer. Monitors for critical moments in the user's financial life.
//

import Foundation
import Combine

// MARK: - Pivotal Moment

/// Represents a detected pivotal moment in the user's financial life.
struct PivotalMoment: Identifiable, Sendable {
    let id: UUID
    let type: PivotalMomentType
    let severity: MomentSeverity
    let title: String
    let description: String
    let detectedAt: Date
    let expiresAt: Date?
    let requiredAction: String?
    let confidence: Double
    let triggerData: [String: String]

    init(
        id: UUID = UUID(),
        type: PivotalMomentType,
        severity: MomentSeverity,
        title: String,
        description: String,
        detectedAt: Date = Date(),
        expiresAt: Date? = nil,
        requiredAction: String? = nil,
        confidence: Double,
        triggerData: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.title = title
        self.description = description
        self.detectedAt = detectedAt
        self.expiresAt = expiresAt
        self.requiredAction = requiredAction
        self.confidence = confidence
        self.triggerData = triggerData
    }
}

// MARK: - Pivotal Moment Type

enum PivotalMomentType: String, Sendable, CaseIterable {
    case marketCrash          // Sudden, severe market downturn
    case liquidationRisk      // Position approaching liquidation
    case whaleMovement        // Large wallet movements affecting holdings
    case regulatoryChange     // Regulatory event impacting portfolio
    case smartContractRisk    // Vulnerability detected in held protocol
    case opportunityWindow    // Time-limited high-value opportunity
    case portfolioMilestone   // Significant portfolio threshold reached
    case securityBreach       // Security threat detected
    case taxEvent             // Tax-relevant event requiring attention
    case correlationBreak     // Historical correlation pattern broken
}

// MARK: - Moment Severity

enum MomentSeverity: Int, Sendable, Comparable, CaseIterable {
    case advisory = 0      // Worth knowing, no action needed
    case important = 1     // Should be reviewed soon
    case urgent = 2        // Requires prompt attention
    case critical = 3      // Immediate action required

    var displayName: String {
        switch self {
        case .advisory:  return "Advisory"
        case .important: return "Important"
        case .urgent:    return "Urgent"
        case .critical:  return "Critical"
        }
    }

    static func < (lhs: MomentSeverity, rhs: MomentSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Morpheus

/// Pivotal moment detection engine. Monitors all data feeds for moments
/// that require the user's attention, filtering out noise to only surface
/// genuinely pivotal events.
final class Morpheus {

    // MARK: - Properties

    private let threshold: MorpheusThreshold
    private let triggers: [MorpheusTrigger]
    private let voice: MorpheusVoice
    private var activeMoments: [PivotalMoment] = []
    private var momentHistory: [PivotalMoment] = []
    private let evaluationQueue = DispatchQueue(label: "com.mtrx.morpheus.evaluation", qos: .userInitiated)

    /// Publisher for newly detected pivotal moments.
    private let momentSubject = PassthroughSubject<PivotalMoment, Never>()
    var momentPublisher: AnyPublisher<PivotalMoment, Never> {
        momentSubject.eraseToAnyPublisher()
    }

    // MARK: - Configuration

    private var isMonitoring: Bool = false
    private var evaluationInterval: TimeInterval = 30.0 // seconds
    private var monitoringTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        threshold: MorpheusThreshold = MorpheusThreshold(),
        voice: MorpheusVoice = MorpheusVoice()
    ) {
        self.threshold = threshold
        self.voice = voice
        self.triggers = MorpheusTrigger.allCases.map { $0 }
    }

    // MARK: - Monitoring

    /// Start continuous monitoring for pivotal moments.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runEvaluationCycle()
                try? await Task.sleep(nanoseconds: UInt64(self?.evaluationInterval ?? 30) * 1_000_000_000)
            }
        }
    }

    /// Stop monitoring.
    func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // MARK: - Evaluation

    /// Run a single evaluation cycle across all triggers.
    func evaluate() async -> [PivotalMoment] {
        return await runEvaluationCycle()
    }

    /// Detect if a pivotal moment exists in the given context.
    /// - Parameter context: The current user context.
    /// - Returns: Detected pivotal moment, or nil if none.
    func detectPivotalMoment(in context: UserContext) async -> PivotalMoment? {
        // Evaluate all trigger conditions against current context
        for trigger in triggers {
            if let condition = trigger.condition,
               condition.evaluate(context: context) {

                let severity = assessSeverity(trigger: trigger, context: context)
                let moment = buildMoment(trigger: trigger, severity: severity, context: context)

                // Apply threshold filter — only surface genuinely pivotal moments
                if threshold.qualifiesAsPivotal(moment) {
                    activeMoments.append(moment)
                    momentHistory.append(moment)
                    momentSubject.send(moment)
                    return moment
                }
            }
        }

        return nil
    }

    // MARK: - Active Moment Management

    /// Get all currently active pivotal moments.
    var currentMoments: [PivotalMoment] {
        // Remove expired moments
        let now = Date()
        activeMoments.removeAll { moment in
            if let expiry = moment.expiresAt, expiry < now {
                return true
            }
            return false
        }
        return activeMoments
    }

    /// Acknowledge and dismiss a pivotal moment.
    /// - Parameter momentId: The ID of the moment to dismiss.
    func dismiss(momentId: UUID) {
        activeMoments.removeAll { $0.id == momentId }
    }

    // MARK: - Voice Alert

    /// Deliver a pivotal moment alert via Morpheus voice.
    /// - Parameter moment: The moment to announce.
    func announceAlert(for moment: PivotalMoment) async {
        let message = buildAlertMessage(for: moment)
        await voice.speak(message)
    }

    // MARK: - Private Helpers

    @discardableResult
    private func runEvaluationCycle() async -> [PivotalMoment] {
        // TODO: Fetch current context from Oracle/Trinity
        // For now, use a placeholder context evaluation
        var detected: [PivotalMoment] = []

        // TODO: Evaluate each trigger against live data feeds
        // - Market data feed
        // - Blockchain monitoring feed
        // - Portfolio state changes
        // - Security alert feed
        // - Regulatory news feed

        return detected
    }

    private func assessSeverity(trigger: MorpheusTrigger, context: UserContext) -> MomentSeverity {
        // TODO: Implement severity assessment based on:
        // - Magnitude of the event
        // - Potential financial impact
        // - Time sensitivity
        // - User's exposure level
        return .important
    }

    private func buildMoment(trigger: MorpheusTrigger, severity: MomentSeverity, context: UserContext) -> PivotalMoment {
        PivotalMoment(
            type: trigger.momentType,
            severity: severity,
            title: trigger.displayName,
            description: trigger.description,
            confidence: 0.75,
            triggerData: [:]
        )
    }

    private func buildAlertMessage(for moment: PivotalMoment) -> String {
        switch moment.severity {
        case .critical:
            return "Critical alert. \(moment.title). \(moment.description). Immediate action is recommended."
        case .urgent:
            return "Urgent. \(moment.title). \(moment.description)."
        case .important:
            return "\(moment.title). \(moment.description)."
        case .advisory:
            return "For your awareness: \(moment.title)."
        }
    }
}
