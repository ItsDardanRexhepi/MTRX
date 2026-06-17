// SubscriptionView.swift
// MTRX -- Subscription management and tier comparison
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI
import StoreKit

// MARK: - Tier UI Extensions

private extension SubscriptionTier {

    var badgeStyle: MtrxBadge.BadgeStyle {
        switch self {
        case .free:       return .neutral
        case .pro:        return .accent
        case .enterprise: return .success
        }
    }

    var features: [(String, Bool)] {
        switch self {
        case .free:
            return [
                ("3 smart contracts", true),
                ("100 transactions/day", true),
                ("Basic Trinity AI", true),
                ("Community support", true),
                ("DeFi analytics", false),
                ("Custom gas settings", false),
            ]
        case .pro:
            return [
                ("Unlimited contracts", true),
                ("Unlimited transactions", true),
                ("Advanced Trinity AI", true),
                ("Priority support", true),
                ("DeFi analytics", true),
                ("Custom gas settings", true),
            ]
        case .enterprise:
            return [
                ("Everything in Pro", true),
                ("API access", true),
                ("White-label options", true),
                ("Dedicated support", true),
                ("Custom integrations", true),
                ("SLA guarantee", true),
            ]
        }
    }
}

// MARK: - Subscription View

struct SubscriptionView: View {
    @State private var storeKit = StoreKitManager.shared
    @State private var gate = FeatureGate.shared

    @State private var selectedTier: SubscriptionTier = .pro
    @State private var appeared = false
    @State private var showUpgraded = false
    @State private var showRestored = false
    @State private var showError = false
    @State private var restoreMessage = ""
    @State private var errorMessage = ""

    /// The effective tier comes from the verified StoreKit entitlement
    /// (via FeatureGate) — never from a local flag.
    private var currentTier: SubscriptionTier { gate.currentTier }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        currentPlanCard
                        tierCards
                        if showTrialBanner { trialBanner }
                        legalSection
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: Symbols.close)
                            .accessibilityLabel("Close")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
            .task {
                if !storeKit.isLoaded { await storeKit.loadProducts() }
                await storeKit.refreshEntitlements()
                withAnimation(Motion.springDefault.delay(0.1)) {
                    appeared = true
                }
            }
            .alert(
                currentTier == .free ? "Plan Changed" : "Welcome to \(currentTier.displayName)",
                isPresented: $showUpgraded
            ) {
                Button("Done", role: .cancel) {}
            } message: {
                Text(upgradeAlertMessage)
            }
            .alert("Restore Purchases", isPresented: $showRestored) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage)
            }
            .alert("Purchase Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Current Plan Card

    private var currentPlanCard: some View {
        MtrxCard(style: .glass) {
            VStack(spacing: Spacing.md) {
                // Badge + icon header
                HStack {
                    MtrxBadge(text: currentTier.displayName, style: currentTier.badgeStyle)
                    Spacer()
                    Image(systemName: Symbols.verified)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentPrimary)
                }

                // Plan name + subtitle
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(currentTier.displayName)
                        .font(.mtrxTitle2)
                        .foregroundStyle(Color.labelPrimary)

                    Text(planStatusText)
                        .font(.mtrxSubheadline)
                        .foregroundStyle(currentTier.isPaid ? Color.labelSecondary : Color.accentPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let usage = contractUsage {
                    MtrxDivider()
                    usageRow(used: usage.used, limit: usage.limit)
                }
            }
        }
        .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
        .mtrxFadeInFromBottom(isVisible: appeared)
    }

    /// Real contract-deployment usage for the current tier (nil limit = unlimited).
    private var contractUsage: (used: Int, limit: Int?)? {
        let used = gate.subscriptionState.currentUsage(.contractDeployments)
        let limit = Feature.contractDeployments.limit(for: currentTier)
        return (used, limit)
    }

    private func usageRow(used: Int, limit: Int?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(limit == nil
                    ? "\(used) contract deployments this month"
                    : "\(used)/\(limit!) deployments used")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)

                Spacer()

                if let limit {
                    Text("\(Int(Double(used) / Double(max(limit, 1)) * 100))%")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(used >= limit ? Color.statusWarning : Color.accentPrimary)
                } else {
                    Text("Unlimited")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.statusSuccess)
                }
            }

            if let limit {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.surfaceOverlay)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(used >= limit ? Color.statusWarning : Color.accentPrimary)
                            .frame(
                                width: geo.size.width * min(Double(used) / Double(max(limit, 1)), 1.0),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)
            }
        }
    }

    /// Honest plan-status line driven by the verified subscription.
    private var planStatusText: String {
        if gate.isInTrial {
            let days = gate.trialDaysRemaining
            return "Free trial \u{2022} \(days) day\(days == 1 ? "" : "s") left"
        }
        if currentTier.isPaid {
            if let exp = storeKit.currentSubscription?.expirationDate {
                return "Renews \(exp.formatted(.dateTime.month(.abbreviated).day().year()))"
            }
            return "Active"
        }
        return "Upgrade for premium features"
    }

    // MARK: - Tier Cards

    private var tierCards: some View {
        VStack(spacing: Spacing.md) {
            ForEach(Array(SubscriptionTier.allCases.enumerated()), id: \.element) { index, tier in
                tierCardView(for: tier)
                    .mtrxFadeInFromBottom(
                        isVisible: appeared,
                        delay: Motion.staggerDelay(for: index, baseDelay: 0.08)
                    )
            }
        }
    }

    private func tierCardView(for tier: SubscriptionTier) -> some View {
        let isCurrent = tier == currentTier

        return MtrxCard(
            style: .standard,
            accentEdge: isCurrent ? .leading : nil
        ) {
            VStack(alignment: .leading, spacing: Spacing.ms) {
                // Header: tier name + price
                HStack(alignment: .firstTextBaseline) {
                    Text(tier.displayName)
                        .font(.mtrxTitle3)
                        .foregroundStyle(Color.labelPrimary)

                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(priceText(for: tier))
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                        if tier.isPaid {
                            Text("/month")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelTertiary)
                        }
                    }
                }

                Text(tier.tagline)
                    .font(.mtrxSubheadline)
                    .foregroundStyle(Color.labelSecondary)

                MtrxDivider()

                // Feature list
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(tier.features, id: \.0) { feature, included in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: included ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(included ? Color.statusSuccess : Color.labelTertiary)

                            Text(feature)
                                .font(.mtrxCallout)
                                .foregroundStyle(included ? Color.labelPrimary : Color.labelTertiary)
                        }
                    }
                }

                tierActionButton(for: tier, isCurrent: isCurrent)
            }
        }
    }

    @ViewBuilder
    private func tierActionButton(for tier: SubscriptionTier, isCurrent: Bool) -> some View {
        if isCurrent {
            if tier.isPaid {
                Button {
                    Task { await storeKit.manageSubscription() }
                } label: {
                    Text("Manage Subscription")
                }
                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular, fullWidth: true))
            } else {
                Button {} label: {
                    Text("Current Plan")
                }
                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular, fullWidth: true))
                .disabled(true)
                .opacity(0.5)
            }
        } else if tier == .free {
            // Downgrading to Free means cancelling in the App Store.
            Button {
                Task { await storeKit.manageSubscription() }
            } label: {
                Text("Manage in App Store")
            }
            .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .regular, fullWidth: true))
        } else {
            Button {
                Task { await subscribe(to: tier) }
            } label: {
                Text(upgradeLabel(for: tier))
            }
            .buttonStyle(MtrxButtonStyle(
                variant: tier == .enterprise ? .accent : .primary,
                size: .regular,
                isLoading: storeKit.isPurchasing && selectedTier == tier,
                fullWidth: true
            ))
            .disabled(storeKit.isPurchasing || product(for: tier) == nil)
        }
    }

    // MARK: - Trial Banner

    /// Only advertise a free trial when StoreKit actually offers one to this user.
    private var showTrialBanner: Bool {
        currentTier == .free && storeKit.isTrialAvailable(for: .pro)
    }

    private var trialBanner: some View {
        MtrxCard(style: .glass) {
            VStack(spacing: Spacing.ms) {
                HStack(spacing: Spacing.ms) {
                    Image(systemName: Symbols.sparkle)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                        .mtrxGlow(color: .accentPrimary, radius: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try Pro Free for 3 Days")
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)

                        Text("No charge until the trial ends")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()
                }

                Button {
                    Task { await subscribe(to: .pro) }
                } label: {
                    Text("Start Free Trial")
                }
                .buttonStyle(MtrxButtonStyle(variant: .accent, size: .regular, fullWidth: true))
                .disabled(storeKit.isPurchasing || product(for: .pro) == nil)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.accentPrimary.opacity(0.6),
                            Color.accentSecondary.opacity(0.3),
                            Color.accentPrimary.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0.25)
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        VStack(spacing: Spacing.md) {
            Text("Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Payment will be charged to your Apple ID account. You can manage and cancel your subscriptions in your App Store account settings.")
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button {
                MtrxHaptics.impact(.light)
                Task { await restore() }
            } label: {
                Text("Restore Purchases")
            }
            .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: - Helpers

    private func product(for tier: SubscriptionTier) -> Product? {
        storeKit.product(for: tier)
    }

    /// Real, store-provided localized price (e.g. "$9.99"); placeholder while loading.
    private func priceText(for tier: SubscriptionTier) -> String {
        if tier == .free { return "Free" }
        return product(for: tier)?.displayPrice ?? "\u{2014}"
    }

    private func upgradeLabel(for tier: SubscriptionTier) -> String {
        if storeKit.isTrialAvailable(for: tier) {
            return "Start 3-Day Free Trial"
        }
        return "Upgrade \u{2014} \(priceText(for: tier))/mo"
    }

    private var upgradeAlertMessage: String {
        if currentTier == .free {
            return "You're on the Free plan. Upgrade anytime."
        }
        if gate.isInTrial {
            return "Your 3-day free trial of \(currentTier.displayName) is active. You won't be charged until it ends — cancel anytime in the App Store."
        }
        return "\(currentTier.displayName) is now active. Thanks for subscribing."
    }

    // MARK: - Actions

    /// Real StoreKit 2 purchase. The 3-day introductory offer is applied
    /// automatically when the user is eligible. No feature unlocks without a
    /// verified transaction; a user cancel is silent.
    private func subscribe(to tier: SubscriptionTier) async {
        guard tier.isPaid else { return }
        selectedTier = tier
        do {
            _ = try await storeKit.purchase(tier)
            MtrxHaptics.success()
            showUpgraded = true
        } catch StoreError.purchaseFailed(let reason) {
            // "User cancelled" / "pending" are not errors to surface loudly.
            if reason != "User cancelled" {
                errorMessage = reason
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Real restore via AppStore.sync(); reports the verified outcome.
    private func restore() async {
        do {
            try await storeKit.restorePurchases()
            restoreMessage = currentTier == .free
                ? "No active subscription was found on your Apple ID."
                : "Your \(currentTier.displayName) plan has been restored."
            showRestored = true
        } catch {
            restoreMessage = "Couldn't restore purchases: \(error.localizedDescription)"
            showRestored = true
        }
    }
}

// MARK: - Upgrade Prompt View

struct UpgradePromptView: View {
    let feature: Feature
    let gateResult: GateResult

    @State private var showSubscription = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.accentPrimary)
                .mtrxGlow(color: .accentPrimary, radius: 12)

            VStack(spacing: Spacing.sm) {
                Text(titleText)
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitleText)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button {
                showSubscription = true
            } label: {
                Text("View Plans")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular))

            Button { dismiss() } label: {
                Text("Maybe Later")
            }
            .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))

            Spacer()
        }
        .padding(Spacing.xl)
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
}

// MARK: - Preview

#Preview("Subscription") {
    SubscriptionView()
        .preferredColorScheme(.dark)
}
