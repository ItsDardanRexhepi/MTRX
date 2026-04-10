// Core/Subscription/TrialManager.swift
// MTRX — 3-Day Free Trial Manager
//
// Tracks trial status, provides countdown display, and handles
// the transition from trial to paid/free tier.
//
// Both Pro ($4.99/mo) and Enterprise ($19.99/mo) offer a 3-day free trial.
// During the trial, users get full access to their chosen tier's features.
// After the trial ends, they auto-convert to paid subscribers unless they cancel,
// in which case they fall back to the Free tier.

import Foundation
import Observation

// MARK: - Trial Status

/// Current state of the user's trial.
enum TrialStatus: Equatable {
    /// User has never started a trial.
    case neverStarted

    /// User is currently in an active trial.
    case active(daysRemaining: Int, tier: SubscriptionTier)

    /// Trial has expired and converted to a paid subscription.
    case convertedToPaid(tier: SubscriptionTier)

    /// Trial expired and user did not continue (now on Free tier).
    case expired

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .neverStarted:
            return "Start your free trial"
        case .active(let days, let tier):
            if days > 1 {
                return "3 days free \u{2022} \(tier.displayName) trial ends in \(days) days"
            } else if days == 1 {
                return "3 days free \u{2022} \(tier.displayName) trial ends tomorrow"
            } else {
                return "3 days free \u{2022} \(tier.displayName) trial ends today"
            }
        case .convertedToPaid(let tier):
            return "\(tier.displayName) subscriber"
        case .expired:
            return "Trial ended"
        }
    }
}

// MARK: - Trial Manager

/// Manages 3-day free trial state and provides UI-friendly properties.
@Observable
final class TrialManager {

    static let shared = TrialManager()

    // MARK: State

    /// Current trial status computed from FeatureGate and StoreKit state.
    var status: TrialStatus {
        let gate = FeatureGate.shared
        let store = StoreKitManager.shared

        // Currently in trial
        if gate.isInTrial {
            return .active(
                daysRemaining: gate.trialDaysRemaining,
                tier: gate.currentTier
            )
        }

        // Has an active paid subscription (trial converted)
        if let sub = store.currentSubscription, sub.isActive, !sub.isInTrialPeriod {
            return .convertedToPaid(tier: sub.tier)
        }

        // Has used trial before but no active sub
        if store.hasUsedTrial {
            return .expired
        }

        // Never started a trial
        return .neverStarted
    }

    /// Whether the user is currently in an active trial.
    var isInTrial: Bool { status.isActive }

    /// The tier being trialed (nil if not in trial).
    var trialTier: SubscriptionTier? {
        if case .active(_, let tier) = status { return tier }
        return nil
    }

    /// Days remaining in the trial (0 if not in trial).
    var daysRemaining: Int {
        if case .active(let days, _) = status { return days }
        return 0
    }

    /// Whether the user can start a new trial (never used one before).
    var canStartTrial: Bool {
        if case .neverStarted = status { return true }
        return false
    }

    /// Human-readable trial countdown for display in the UI.
    var countdownText: String? {
        guard isInTrial else { return nil }
        let days = daysRemaining
        if days > 1 {
            return "\(days) days left"
        } else if days == 1 {
            return "1 day left"
        } else {
            return "Last day"
        }
    }

    /// Short badge text for navigation bars.
    var badgeText: String? {
        guard isInTrial else { return nil }
        return "TRIAL"
    }

    // MARK: Actions

    /// Start a trial by purchasing the subscription (StoreKit handles the trial offer).
    /// The 3-day free trial is configured as an introductory offer in App Store Connect.
    @MainActor
    func startTrial(for tier: SubscriptionTier) async throws {
        guard tier.hasTrialOffer else {
            throw TrialError.noTrialAvailable
        }

        guard canStartTrial else {
            throw TrialError.trialAlreadyUsed
        }

        // The purchase flow through StoreKit 2 automatically applies
        // the introductory offer (3-day free trial) if the user is eligible.
        _ = try await StoreKitManager.shared.purchase(tier)
    }

    // MARK: Display Helpers

    /// Call-to-action text for upgrade prompts.
    func upgradePromptText(for tier: SubscriptionTier) -> String {
        if canStartTrial {
            return "Start 3-day free trial"
        } else {
            return "Upgrade to \(tier.displayName)"
        }
    }

    /// Subtitle text explaining what happens after the trial.
    func upgradeSubtitleText(for tier: SubscriptionTier) -> String {
        if canStartTrial {
            return "Try \(tier.displayName) free for 3 days. Cancel anytime. Then \(tier.priceDisplay)."
        } else {
            return "\(tier.priceDisplay). Cancel anytime."
        }
    }

    /// Features list for upgrade prompts, based on tier.
    func featuresList(for tier: SubscriptionTier) -> [String] {
        switch tier {
        case .free:
            return []
        case .pro:
            return [
                "Remove most usage limits",
                "Priority Trinity responses",
                "Extended conversation memory",
                "Advanced dashboard with exports",
                "Custom agent skills & saved workflows",
                "Early access to new components",
            ]
        case .enterprise:
            return [
                "Everything in Pro, plus:",
                "Unlimited usage across all components",
                "Team & multi-user accounts",
                "White-label custom branding",
                "Advanced governance tools",
                "Enterprise analytics & audit logs",
                "Direct API access",
                "Priority support",
                "Custom component development",
            ]
        }
    }

    private init() {}
}

// MARK: - Trial Errors

enum TrialError: LocalizedError {
    case noTrialAvailable
    case trialAlreadyUsed

    var errorDescription: String? {
        switch self {
        case .noTrialAvailable:
            return "This tier does not offer a free trial."
        case .trialAlreadyUsed:
            return "You've already used your free trial."
        }
    }
}
