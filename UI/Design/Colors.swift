// Colors.swift
// MTRX
//
// HIG-compliant semantic color system with light/dark mode adaptive colors.

import SwiftUI

// MARK: - Semantic Colors

extension Color {

    // MARK: - Brand

    /// Primary brand color — terminal cyan
    static let accentPrimary = Color("AccentPrimary", bundle: .main)

    /// Secondary brand color — complementary teal
    static let accentSecondary = Color("AccentSecondary", bundle: .main)

    /// Tertiary brand accent — warm amber
    static let accentTertiary = Color("AccentTertiary", bundle: .main)

    // MARK: - Backgrounds

    /// Primary background — system background
    static let backgroundPrimary = Color(uiColor: .systemBackground)

    /// Secondary background — grouped content
    static let backgroundSecondary = Color(uiColor: .secondarySystemBackground)

    /// Tertiary background — nested grouped content
    static let backgroundTertiary = Color(uiColor: .tertiarySystemBackground)

    /// Grouped background — for grouped table views
    static let backgroundGrouped = Color(uiColor: .systemGroupedBackground)

    /// Secondary grouped background
    static let backgroundGroupedSecondary = Color(uiColor: .secondarySystemGroupedBackground)

    // MARK: - Surfaces

    /// Card surface color
    static let surfaceCard = Color("SurfaceCard", bundle: .main)

    /// Elevated surface — for modals, popovers
    static let surfaceElevated = Color("SurfaceElevated", bundle: .main)

    /// Overlay surface — semi-transparent overlays
    static let surfaceOverlay = Color(uiColor: .systemFill)

    /// Thin material surface
    static let surfaceThin = Color(uiColor: .tertiarySystemFill)

    // MARK: - Labels / Text

    /// Primary text color
    static let labelPrimary = Color(uiColor: .label)

    /// Secondary text color
    static let labelSecondary = Color(uiColor: .secondaryLabel)

    /// Tertiary text color
    static let labelTertiary = Color(uiColor: .tertiaryLabel)

    /// Quaternary text color — least prominent
    static let labelQuaternary = Color(uiColor: .quaternaryLabel)

    /// Placeholder text color
    static let labelPlaceholder = Color(uiColor: .placeholderText)

    // MARK: - Separators

    /// Standard separator
    static let separatorStandard = Color(uiColor: .separator)

    /// Opaque separator
    static let separatorOpaque = Color(uiColor: .opaqueSeparator)

    // MARK: - Semantic Status

    /// Success state — green
    static let statusSuccess = Color.green

    /// Warning state — orange
    static let statusWarning = Color.orange

    /// Error / destructive state — red
    static let statusError = Color.red

    /// Info state — blue
    static let statusInfo = Color.blue

    // MARK: - Financial

    /// Positive price change — green
    static let priceUp = Color("PriceUp", bundle: .main)

    /// Negative price change — red
    static let priceDown = Color("PriceDown", bundle: .main)

    /// Neutral / no change
    static let priceNeutral = Color(uiColor: .secondaryLabel)

    // MARK: - DeFi Specific

    /// Healthy position — green
    static let healthGood = Color.green

    /// Moderate risk — yellow
    static let healthModerate = Color.yellow

    /// At risk position — orange
    static let healthWarning = Color.orange

    /// Critical / near liquidation — red
    static let healthCritical = Color.red

    // MARK: - Governance

    /// Vote yes — green
    static let voteFor = Color.green

    /// Vote no — red
    static let voteAgainst = Color.red

    /// Abstain — gray
    static let voteAbstain = Color.gray

    /// Quorum met — blue
    static let quorumMet = Color.blue

    // MARK: - Tab Bar

    /// Tab bar selected state — terminal cyan
    static let tabSelected = Color(red: 0.0, green: 0.675, blue: 0.694)

    /// Tab bar unselected state (#666666)
    static let tabUnselected = Color(white: 0.4)

    // MARK: - Trinity AI

    /// Trinity primary glow
    static let trinityPrimary = Color("TrinityPrimary", bundle: .main)

    /// Trinity secondary glow
    static let trinitySecondary = Color("TrinitySecondary", bundle: .main)

    /// Trinity processing indicator
    static let trinityProcessing = Color("TrinityProcessing", bundle: .main)
}

// MARK: - Fallback Color Definitions (When Asset Catalog is unavailable)

extension Color {
    static let fallbackAccentPrimary = Color(red: 0.0, green: 0.675, blue: 0.694)
    static let fallbackAccentSecondary = Color(red: 0.0, green: 0.8, blue: 0.75)
    static let fallbackAccentTertiary = Color(red: 1.0, green: 0.7, blue: 0.0)
    static let fallbackPriceUp = Color(red: 0.2, green: 0.84, blue: 0.42)
    static let fallbackPriceDown = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let fallbackTrinityPrimary = Color(red: 0.0, green: 0.675, blue: 0.694)
    static let fallbackTrinitySecondary = Color(red: 0.0, green: 0.800, blue: 0.750)
}

// MARK: - Gradient Definitions

extension LinearGradient {

    /// Primary brand gradient
    static let mtrxPrimary = LinearGradient(
        colors: [.accentPrimary, .accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Trinity AI gradient
    static let mtrxTrinity = LinearGradient(
        colors: [.trinityPrimary, .trinitySecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Success gradient
    static let mtrxSuccess = LinearGradient(
        colors: [.statusSuccess, .statusSuccess.opacity(0.7)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Card shimmer gradient for loading states
    static let mtrxShimmer = LinearGradient(
        colors: [
            Color.surfaceCard.opacity(0.4),
            Color.surfaceCard.opacity(0.8),
            Color.surfaceCard.opacity(0.4)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Material Extensions

extension ShapeStyle where Self == Material {
    static var mtrxUltraThin: Material { .ultraThinMaterial }
    static var mtrxThin: Material { .thinMaterial }
    static var mtrxRegular: Material { .regularMaterial }
    static var mtrxThick: Material { .thickMaterial }
}
