// UI/Views/Account/SubscriptionView.swift
// MTRX — Subscription & Trial Management Screen
//
// Shows the user's current tier, trial status, and upgrade options.
// Displayed when:
//   - User navigates to Account > Subscription
//   - User hits a usage limit (via UpgradePromptView)
//   - User taps "Upgrade" anywhere in the app

import SwiftUI
import StoreKit

// MARK: - Subscription View

struct SubscriptionView: View {
    @State private var storeKit = StoreKitManager.shared
    @State private var featureGate = FeatureGate.shared
    @State private var trialManager = TrialManager.shared
    @State private var selectedTier: SubscriptionTier = .pro
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isPurchasing = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Current status banner
                    currentStatusBanner

                    // Trial banner (if active)
                    if trialManager.isInTrial {
                        trialBanner
                    }

                    // Tier cards
                    tierCards

                    // Usage summary (if subscribed)
                    if featureGate.currentTier != .free || trialManager.isInTrial {
                        usageSummarySection
                    }

                    // Manage / Restore
                    managementButtons

                    // Legal
                    legalText
                }
                .padding()
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if !storeKit.isLoaded {
                    try? await storeKit.loadProducts()
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Current Status Banner

    private var currentStatusBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: tierIcon(for: featureGate.currentTier))
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(featureGate.currentTier.displayName)
                    .font(.title2.bold())
            }

            Text(featureGate.currentTier.tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let trialStatus = trialManager.status.displayText as String?,
               trialManager.isInTrial {
                Text(trialStatus)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Trial Banner

    private var trialBanner: some View {
        HStack {
            Image(systemName: "clock.badge.checkmark")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Free Trial Active")
                    .font(.subheadline.bold())
                if let countdown = trialManager.countdownText {
                    Text(countdown)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let badge = trialManager.badgeText {
                Text(badge)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Tier Cards

    private var tierCards: some View {
        VStack(spacing: 12) {
            tierCard(for: .pro)
            tierCard(for: .enterprise)
        }
    }

    private func tierCard(for tier: SubscriptionTier) -> some View {
        let isCurrentTier = featureGate.currentTier == tier
        let features = trialManager.featuresList(for: tier)

        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.headline)
                    Text(tier.priceDisplay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isCurrentTier {
                    Text("Current")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: Capsule())
                }
            }

            // Features
            ForEach(features, id: \.self) { feature in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(feature)
                        .font(.caption)
                }
            }

            // CTA Button
            if !isCurrentTier {
                Button {
                    Task { await purchaseTier(tier) }
                } label: {
                    HStack {
                        if isPurchasing && selectedTier == tier {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(trialManager.upgradePromptText(for: tier))
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing)

                Text(trialManager.upgradeSubtitleText(for: tier))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isCurrentTier ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: isCurrentTier ? 2 : 1
                )
        )
    }

    // MARK: - Usage Summary

    private var usageSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage This Month")
                .font(.headline)

            let usage = featureGate.usageSummary()
            ForEach(usage.prefix(8), id: \.feature) { item in
                HStack {
                    Text(item.feature.rawValue
                        .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
                        .capitalized
                        .trimmingCharacters(in: .whitespaces))
                        .font(.caption)
                    Spacer()
                    if let limit = item.limit {
                        Text("\(item.used) / \(limit)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(
                                item.used >= limit ? .red : .secondary
                            )
                    } else {
                        Text("\(item.used) / \u{221E}")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Management Buttons

    private var managementButtons: some View {
        VStack(spacing: 8) {
            if featureGate.currentTier.isPaid || trialManager.isInTrial {
                Button("Manage Subscription") {
                    Task { await storeKit.manageSubscription() }
                }
                .font(.subheadline)
            }

            Button("Restore Purchases") {
                Task {
                    do {
                        try await storeKit.restorePurchases()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Legal

    private var legalText: some View {
        Text("Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. All tiers include automatic on-chain platform fees (Platform Access Contribution, NFT 10%, DAO treasury fees) that route to NeoSafe.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    // MARK: - Actions

    private func purchaseTier(_ tier: SubscriptionTier) async {
        selectedTier = tier
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            _ = try await storeKit.purchase(tier)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func tierIcon(for tier: SubscriptionTier) -> String {
        switch tier {
        case .free:       return "person.circle"
        case .pro:        return "star.circle.fill"
        case .enterprise: return "building.2.circle.fill"
        }
    }
}

// MARK: - Upgrade Prompt View (shown when limit is hit)

/// Modal shown when a user hits a usage limit or tries to access a tier-locked feature.
struct UpgradePromptView: View {
    let feature: Feature
    let gateResult: GateResult

    @State private var trialManager = TrialManager.shared
    @State private var showSubscription = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text(titleText)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showSubscription = true
            } label: {
                Text(ctaText)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            Button("Maybe Later") { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .sheet(isPresented: $showSubscription) {
            SubscriptionView()
        }
    }

    private var titleText: String {
        switch gateResult {
        case .limitReached:
            return "You've reached your monthly limit"
        case .featureUnavailable(let tier):
            return "Upgrade to \(tier.displayName)"
        default:
            return "Upgrade"
        }
    }

    private var subtitleText: String {
        switch gateResult {
        case .limitReached(let tier):
            return "Upgrade to \(tier.displayName) for higher limits."
        case .featureUnavailable(let tier):
            return "This feature requires \(tier.displayName)."
        default:
            return ""
        }
    }

    private var ctaText: String {
        let suggestedTier: SubscriptionTier
        switch gateResult {
        case .limitReached(let tier): suggestedTier = tier
        case .featureUnavailable(let tier): suggestedTier = tier
        default: suggestedTier = .pro
        }
        return trialManager.upgradePromptText(for: suggestedTier)
    }
}

#Preview {
    SubscriptionView()
}
