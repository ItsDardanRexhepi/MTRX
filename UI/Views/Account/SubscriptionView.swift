// SubscriptionView.swift
// MTRX -- Subscription management and tier comparison
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - Tier UI Extensions

private extension SubscriptionTier {

    var price: String {
        switch self {
        case .free:       return "$0"
        case .pro:        return "$4.99"
        case .enterprise: return "$19.99"
        }
    }

    var priceSuffix: String { "/month" }

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
    @State private var selectedTier: SubscriptionTier = .pro
    @State private var isPurchasing = false
    @State private var appeared = false
    @State private var showTrialStarted = false
    @State private var showRestored = false

    private let currentTier: SubscriptionTier = .free
    private let contractsUsed: Int = 3
    private let contractsLimit: Int = 3

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        currentPlanCard
                        tierCards
                        trialBanner
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
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.labelSecondary)
                            .frame(width: 30, height: 30)
                            .background(Color.surfaceOverlay)
                            .clipShape(Circle())
                    }
                }
            }
            .onAppear {
                withAnimation(Motion.springDefault.delay(0.1)) {
                    appeared = true
                }
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

                    Text(currentTier.isPaid
                        ? "Renews \((Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()).formatted(.dateTime.month(.abbreviated).day().year()))"
                        : "Upgrade for premium features")
                        .font(.mtrxSubheadline)
                        .foregroundStyle(currentTier.isPaid ? Color.labelSecondary : Color.accentPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MtrxDivider()

                // Usage row with progress bar
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("\(contractsUsed)/\(contractsLimit) contracts used")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        Spacer()

                        Text("\(Int(Double(contractsUsed) / Double(contractsLimit) * 100))%")
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(contractsUsed >= contractsLimit ? Color.statusWarning : Color.accentPrimary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.surfaceOverlay)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(contractsUsed >= contractsLimit ? Color.statusWarning : Color.accentPrimary)
                                .frame(
                                    width: geo.size.width * min(Double(contractsUsed) / Double(contractsLimit), 1.0),
                                    height: 8
                                )
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
        .mtrxFadeInFromBottom(isVisible: appeared)
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
                        Text(tier.price)
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                        Text(tier.priceSuffix)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
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

                // Action button
                if isCurrent {
                    Button {} label: {
                        Text("Current Plan")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular, fullWidth: true))
                    .disabled(true)
                    .opacity(0.5)
                } else if tier == .enterprise {
                    Button {
                        selectedTier = tier
                        handleSubscribeTap()
                    } label: {
                        Text("Upgrade")
                    }
                    .buttonStyle(MtrxButtonStyle(
                        variant: .accent,
                        size: .regular,
                        isLoading: isPurchasing && selectedTier == tier,
                        fullWidth: true
                    ))
                    .disabled(isPurchasing)
                } else {
                    Button {
                        selectedTier = tier
                        handleSubscribeTap()
                    } label: {
                        Text("Subscribe")
                    }
                    .buttonStyle(MtrxButtonStyle(
                        variant: .primary,
                        size: .regular,
                        isLoading: isPurchasing && selectedTier == tier,
                        fullWidth: true
                    ))
                    .disabled(isPurchasing)
                }
            }
        }
    }

    // MARK: - Trial Banner

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

                        Text("No charge until trial ends")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()
                }

                Button {
                    MtrxHaptics.success()
                    showTrialStarted = true
                } label: {
                    Text("Start Free Trial")
                }
                .buttonStyle(MtrxButtonStyle(variant: .accent, size: .regular, fullWidth: true))
                .alert("Pro Trial Active", isPresented: $showTrialStarted) {
                    Button("Let's go", role: .cancel) {}
                } message: {
                    Text("You have 3 days of MTRX Pro, free. Unlimited deployments, advanced analytics, and priority agent responses are unlocked.")
                }
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
                showRestored = true
            } label: {
                Text("Restore Purchases")
            }
            .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))
            .alert("Purchases Restored", isPresented: $showRestored) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your purchase history is synced — your plan is up to date.")
            }
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: - Actions

    private func handleSubscribeTap() {
        isPurchasing = true
        MtrxHaptics.success()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(Motion.springDefault) {
                isPurchasing = false
            }
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
