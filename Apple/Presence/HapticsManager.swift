// HapticsManager.swift
// MTRX Apple Integration — Presence
// CoreHaptics custom patterns per transaction type

import CoreHaptics
import UIKit

// MARK: - Haptics Manager

final class HapticsManager {

    // MARK: - Shared Instance

    static let shared = HapticsManager()

    // MARK: - Properties

    private var engine: CHHapticEngine?
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    // MARK: - Initialization

    private init() {
        prepareEngine()
    }

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            engine = try CHHapticEngine()
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine?.stoppedHandler = { _ in }
            try engine?.start()
        } catch {
            engine = nil
        }
    }

    // MARK: - Transaction Haptics

    /// Plays a haptic pattern appropriate for the transaction event.
    func playTransactionHaptic(_ event: TransactionHapticEvent) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            playFallbackHaptic(event)
            return
        }

        do {
            let pattern = try hapticPattern(for: event)
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            playFallbackHaptic(event)
        }
    }

    // MARK: - Pattern Definitions

    private func hapticPattern(for event: TransactionHapticEvent) throws -> CHHapticPattern {
        switch event {
        case .transactionSent:
            return try sendPattern()
        case .transactionReceived:
            return try receivePattern()
        case .transactionConfirmed:
            return try confirmPattern()
        case .transactionFailed:
            return try failPattern()
        case .contractDeployed:
            return try deployPattern()
        case .contractExecuted:
            return try executePattern()
        case .portfolioMilestone:
            return try milestonePattern()
        case .alertUrgent:
            return try urgentAlertPattern()
        case .buttonTap:
            return try tapPattern()
        case .swipeAction:
            return try swipePattern()
        }
    }

    /// Rising haptic — money leaving the wallet.
    private func sendPattern() throws -> CHHapticPattern {
        let events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ], relativeTime: 0.08),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            ], relativeTime: 0.15, duration: 0.2)
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Descending haptic — money arriving.
    private func receivePattern() throws -> CHHapticPattern {
        let events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
            ], relativeTime: 0.1),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            ], relativeTime: 0.2, duration: 0.3)
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Double-tap confirmation pulse.
    private func confirmPattern() throws -> CHHapticPattern {
        let events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            ], relativeTime: 0.15)
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Error buzz pattern.
    private func failPattern() throws -> CHHapticPattern {
        let events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            ], relativeTime: 0.1),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
            ], relativeTime: 0.2)
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Deep rumble for contract deployment.
    private func deployPattern() throws -> CHHapticPattern {
        let events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            ], relativeTime: 0, duration: 0.4),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ], relativeTime: 0.4)
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Quick pulse for contract execution.
    private func executePattern() throws -> CHHapticPattern {
        let events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ], relativeTime: 0.12)
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Celebration burst for portfolio milestones.
    private func milestonePattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        for i in 0..<5 {
            let time = Double(i) * 0.08
            let intensity = Float(0.4 + Double(i) * 0.15)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(intensity, 1.0)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
            ], relativeTime: time))
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Urgent triple-pulse alert.
    private func urgentAlertPattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        for i in 0..<3 {
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            ], relativeTime: Double(i) * 0.2))
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Light tap for button interactions.
    private func tapPattern() throws -> CHHapticPattern {
        let events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ], relativeTime: 0)
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Smooth continuous for swipe gestures.
    private func swipePattern() throws -> CHHapticPattern {
        let events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ], relativeTime: 0, duration: 0.15)
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }

    // MARK: - Fallback Haptics

    private func playFallbackHaptic(_ event: TransactionHapticEvent) {
        switch event {
        case .transactionSent, .contractExecuted:
            impactMedium.impactOccurred()
        case .transactionReceived, .portfolioMilestone:
            notificationGenerator.notificationOccurred(.success)
        case .transactionConfirmed, .contractDeployed:
            impactHeavy.impactOccurred()
        case .transactionFailed, .alertUrgent:
            notificationGenerator.notificationOccurred(.error)
        case .buttonTap:
            impactLight.impactOccurred()
        case .swipeAction:
            selectionGenerator.selectionChanged()
        }
    }

    // MARK: - Prepare

    /// Prepares haptic generators for low-latency playback.
    func prepare() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }
}

// MARK: - Transaction Haptic Event

enum TransactionHapticEvent {
    case transactionSent
    case transactionReceived
    case transactionConfirmed
    case transactionFailed
    case contractDeployed
    case contractExecuted
    case portfolioMilestone
    case alertUrgent
    case buttonTap
    case swipeAction
}
