// FeatureFlags.swift
// MTRX
//
// Central switches for what ships in a given build.
//
// `mvpMode` hides regulated financial features so the app is App Store
// submittable while licensing and licensed-partner integrations are
// arranged. App Review guideline 3.1.5(b) requires securities / ICO /
// futures-style features and crypto exchange/transmission to come from
// licensed financial institutions — so until those partnerships exist,
// these surfaces are hidden behind this flag. Flip `mvpMode` to false to
// turn them all back on at once.

import SwiftUI

enum FeatureFlags {

    /// App Store MVP mode. When true, regulated financial features are hidden
    /// from the UI and their screens render a neutral placeholder.
    ///
    /// DEBUG builds (Xcode run / device dev builds) unlock everything so the
    /// full set of feature screens shows its honest DEMO data and can be worked
    /// on. RELEASE builds (Archive → TestFlight → App Store) keep the gate on,
    /// so the shipped, review-facing build stays compliant with guideline
    /// 3.1.5(b) — no code change needed at ship time. Flip `releaseMVPMode` to
    /// change the shipped behaviour.
    static var mvpMode: Bool {
        #if DEBUG
        return false
        #else
        return releaseMVPMode
        #endif
    }

    /// The gate value used by RELEASE (shipped) builds. Kept true until the
    /// licensed-partner integrations exist.
    static let releaseMVPMode = true

    /// Regulated financial features are shown only outside MVP mode.
    static var regulatedFeaturesEnabled: Bool { !mvpMode }

    // MARK: - Discover categories

    /// Discover categories that surface regulated financial products
    /// (lending/borrow/yield, staking, RWA/securities, markets/perps,
    /// payments, cross-chain transfer). Hidden in MVP mode.
    static let regulatedCategories: Set<DiscoverCategory> = [
        .defi, .defiAdvanced, .nftFinance, .staking,
        .realWorld, .markets, .payments, .bridging
    ]

    static func isVisible(_ category: DiscoverCategory) -> Bool {
        regulatedFeaturesEnabled || !regulatedCategories.contains(category)
    }

    // MARK: - DeFi destinations

    static let regulatedDeFiDestinations: Set<DeFiSubDestination> = [
        .lending, .liquidity, .yield, .realWorld
    ]

    static func isVisible(_ destination: DeFiSubDestination) -> Bool {
        regulatedFeaturesEnabled || !regulatedDeFiDestinations.contains(destination)
    }
}

// MARK: - Regulated screen guard

/// Shown in place of a regulated feature while it's gated for MVP. Neutral
/// on purpose — no implication the feature is live.
struct MVPUnavailableView: View {
    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .primary)
            VStack(spacing: Spacing.md) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.labelTertiary)
                Text("Coming Soon")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                Text("This feature is being prepared for a future update.")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding(Spacing.xl)
        }
    }
}

extension View {
    /// In App Store MVP mode, replace a regulated feature's UI with a
    /// neutral placeholder so it is never reachable, regardless of which
    /// entry point opened it. A no-op once `mvpMode` is off.
    @ViewBuilder
    func mvpGated() -> some View {
        if FeatureFlags.mvpMode {
            MVPUnavailableView()
        } else {
            self
        }
    }
}
