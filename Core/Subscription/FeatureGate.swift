// Core/Subscription/FeatureGate.swift
// MTRX — Feature Gate System
//
// Wraps every major action behind tier-based access control.
// Checks the user's active subscription tier (including trial status)
// and enforces usage limits.
//
// Usage:
//   if FeatureGate.shared.isEnabled(.priorityTrinity) { ... }
//   let result = FeatureGate.shared.checkLimit(.nftMints)
//   switch result {
//   case .allowed(let remaining): // proceed
//   case .limitReached(let upgrade): // show upgrade prompt
//   case .featureUnavailable(let upgrade): // show upgrade screen
//   }

import Foundation
import SwiftUI
import SwiftData
import Observation

// MARK: - Gate Result

/// Result of checking whether a feature/action is allowed.
enum GateResult {
    /// Action is allowed. `remaining` is nil if unlimited, or the count remaining.
    case allowed(remaining: Int?)

    /// Usage limit has been reached for this billing period.
    case limitReached(suggestedUpgrade: SubscriptionTier)

    /// Feature is not available at the user's current tier.
    case featureUnavailable(requiredTier: SubscriptionTier)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

// MARK: - Feature Gate

/// Central feature-gating system. Every major action checks this before executing.
@Observable
final class FeatureGate {

    static let shared = FeatureGate()

    // MARK: State

    /// Current subscription state (loaded from SwiftData on launch).
    private(set) var subscriptionState: SubscriptionState

    /// Whether the user is currently in a trial period.
    var isInTrial: Bool {
        subscriptionState.isTrialActive &&
        subscriptionState.trialDaysRemaining > 0
    }

    /// The user's effective tier (accounts for trial status).
    var currentTier: SubscriptionTier {
        subscriptionState.effectiveTier
    }

    /// Days remaining in trial.
    var trialDaysRemaining: Int {
        subscriptionState.trialDaysRemaining
    }

    /// Human-readable trial status string.
    var trialStatusText: String? {
        guard isInTrial else { return nil }
        let days = trialDaysRemaining
        if days > 1 {
            return "3 days free \u{2022} Ends in \(days) days"
        } else if days == 1 {
            return "3 days free \u{2022} Ends tomorrow"
        } else {
            return "3 days free \u{2022} Ends today"
        }
    }

    // MARK: Init

    private init() {
        self.subscriptionState = SubscriptionState()
    }

    /// Load persisted state from SwiftData on app launch.
    func loadState(from modelContext: ModelContext) {
        let descriptor = FetchDescriptor<SubscriptionState>()
        if let existing = try? modelContext.fetch(descriptor).first {
            self.subscriptionState = existing
        } else {
            let newState = SubscriptionState()
            modelContext.insert(newState)
            try? modelContext.save()
            self.subscriptionState = newState
        }
    }

    // MARK: Feature Checks

    /// Check if a boolean feature is enabled at the current tier.
    func isEnabled(_ feature: Feature) -> Bool {
        currentTier >= feature.minimumTier
    }

    /// Check if a usage-limited action is allowed, accounting for current usage.
    func checkLimit(_ feature: Feature) -> GateResult {
        let tier = currentTier

        // First check tier access
        if tier < feature.minimumTier {
            return .featureUnavailable(requiredTier: feature.minimumTier)
        }

        // Check usage limit
        guard let limit = feature.limit(for: tier) else {
            // nil = unlimited
            return .allowed(remaining: nil)
        }

        let used = subscriptionState.currentUsage(feature)
        if used >= limit {
            let upgrade: SubscriptionTier = tier == .free ? .pro : .enterprise
            return .limitReached(suggestedUpgrade: upgrade)
        }

        return .allowed(remaining: limit - used)
    }

    /// Record usage of a feature. Call this AFTER the action succeeds.
    func recordUsage(_ feature: Feature) {
        subscriptionState.incrementUsage(feature)
    }

    /// Convenience: check and record in one call. Returns true if allowed.
    func checkAndRecord(_ feature: Feature) -> GateResult {
        let result = checkLimit(feature)
        if result.isAllowed {
            recordUsage(feature)
        }
        return result
    }

    // MARK: Tier Updates

    /// Update the subscription tier (called by StoreKitManager after entitlement check).
    func updateTier(
        _ tier: SubscriptionTier,
        isTrialActive: Bool = false,
        trialEndDate: Date? = nil,
        originalTransactionId: String? = nil
    ) {
        subscriptionState.tier = tier
        subscriptionState.isTrialActive = isTrialActive
        subscriptionState.trialEndDate = trialEndDate
        subscriptionState.lastVerifiedDate = Date()
        if let txId = originalTransactionId {
            subscriptionState.originalTransactionId = txId
        }
        if isTrialActive && subscriptionState.trialStartDate == nil {
            subscriptionState.trialStartDate = Date()
        }
    }

    /// Fall back to free tier (called when trial expires or subscription lapses).
    func fallbackToFree() {
        subscriptionState.tier = .free
        subscriptionState.isTrialActive = false
    }

    // MARK: Usage Summary

    /// Get a summary of all feature usage for the current period.
    func usageSummary() -> [(feature: Feature, used: Int, limit: Int?)] {
        let tier = currentTier
        return Feature.allCases.compactMap { feature in
            guard let limit = feature.limit(for: tier) else { return nil }
            let used = subscriptionState.currentUsage(feature)
            return (feature: feature, used: used, limit: limit)
        }
    }
}
