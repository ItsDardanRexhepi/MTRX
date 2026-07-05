// MtrxComponents.swift
// MTRX
//
// Production-grade reusable UI component library.
// Every view in the app builds on these primitives.

import SwiftUI

// MARK: - Gradient Background

struct MtrxGradientBackground: View {
    var style: GradientStyle = .primary

    enum GradientStyle {
        case primary, subtle, dark, trinityGlow
    }

    var body: some View {
        // The app rides a single pure-black field everywhere, no exception.
        // Per-screen accents (the Home ambient glow, the Social top wash)
        // ride on their own layers on top of this.
        Color.black.ignoresSafeArea()
    }
}

// MARK: - Liquid Glass

extension View {
    /// The app's measured take on Liquid Glass: real system glass on
    /// iOS 26 — refraction, depth, the live sheen — with a graceful
    /// material fallback elsewhere. One call, any shape.
    @ViewBuilder
    func mtrxLiquidGlass<S: Shape>(in shape: S) -> some View {
        Group {
            // `glassEffect` is an iOS 26 (Liquid Glass) API absent from the CI
            // SDK (Xcode 15.4 / iOS 17); a runtime #available check does not make
            // the symbol exist at compile time, so the real-glass branch is only
            // compiled when the SDK declares it. Older SDKs use the material
            // fallback (the same one iOS < 26 gets at runtime).
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                // Clip first: glassEffect draws glass within the shape but
                // leaves the view's own backgrounds rectangular — unclipped
                // tint layers would ghost past the rounded corners.
                self
                    .clipShape(shape)
                    .glassEffect(.regular, in: shape)
            } else {
                self
                    .background(.ultraThinMaterial)
                    .clipShape(shape)
            }
            #else
            self
                .background(.ultraThinMaterial)
                .clipShape(shape)
            #endif
        }
        // A light-reactive rim on every glass surface, app-wide: the top-left
        // edge catches light brightest, a quieter glint along the bottom-
        // right — subtle, but there.
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: [.white.opacity(0.30), .white.opacity(0.04), .white.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        )
    }

    func mtrxLiquidGlass(cornerRadius: CGFloat = Spacing.CornerRadius.lg) -> some View {
        mtrxLiquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Glass Circle Button

/// A single clean cyan liquid-glass circle with an icon — the circle IS
/// the whole button, no second ring around it. Used for the Discover
/// menu, the Build filter, and other circular toolbar actions.
struct MtrxGlassCircleButton: View {
    let icon: String
    var tint: Color = .accentPrimary
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: {
            MtrxHaptics.impact(.light)
            action()
        }) {
            ZStack {
                // A light frosted bubble with a faint brand-cyan wash, so the dark
                // icon always reads as clean, properly-aligned "black lines" — a clear
                // menu / filter button (the build-186 reference look).
                Circle().fill(.regularMaterial)
                Circle().fill(tint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.80))
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            // A fully-enclosing rim so the circle reads as a clean, complete disc,
            // lifted off the surface by a soft drop shadow.
            .overlay(
                Circle().stroke(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.4
                )
            )
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Card

struct MtrxCard<Content: View>: View {
    var style: CardStyle = .standard
    var accentEdge: Edge? = nil
    @ViewBuilder let content: () -> Content

    enum CardStyle {
        case standard, elevated, glass, outlined
    }

    var body: some View {
        Group {
            if style == .standard || style == .glass {
                // Liquid glass body with a breath of signature tint.
                content()
                    .padding(Spacing.cardPadding)
                    .background(
                        LinearGradient(
                            colors: [Color.trinityPrimary.opacity(0.055), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.lg)
            } else {
                content()
                    .padding(Spacing.cardPadding)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
            }
        }
        .overlay(accentOverlay)
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch style {
        case .standard, .glass:
            Color.clear
        case .elevated:
            ZStack {
                Color.surfaceElevated.opacity(0.65)
                Color.clear.background(.thinMaterial)
            }
        case .outlined:
            Color.clear
        }
    }

    @ViewBuilder
    private var accentOverlay: some View {
        if let edge = accentEdge {
            // The accent lives in the border itself — a stroke that glows
            // from the accented edge and fades across the card. No bars
            // floating against the rounded corners.
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.accentPrimary.opacity(0.55), Color.accentPrimary.opacity(0.08)],
                        startPoint: gradientStart(for: edge),
                        endPoint: gradientEnd(for: edge)
                    ),
                    lineWidth: 1
                )
        } else if style == .outlined {
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                .stroke(Color.separatorStandard, lineWidth: 0.5)
        } else {
            // Lit hairline — light falls from above, so the top edge
            // catches it and the bottom edge falls quietly away.
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.16), .white.opacity(0.015)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func gradientStart(for edge: Edge) -> UnitPoint {
        switch edge {
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private func gradientEnd(for edge: Edge) -> UnitPoint {
        switch edge {
        case .leading: return .trailing
        case .trailing: return .leading
        case .top: return .bottom
        case .bottom: return .top
        }
    }

    // Deep, diffuse, unhurried — shadows that suggest weight without
    // ever looking attached to the card.
    private var shadowColor: Color {
        style == .elevated ? Color.black.opacity(0.32) : Color.black.opacity(0.24)
    }
    private var shadowRadius: CGFloat { style == .elevated ? 20 : 15 }
    private var shadowY: CGFloat { style == .elevated ? 9 : 7 }
}

// MARK: - Button Styles

struct MtrxButtonStyle: ButtonStyle {
    var variant: Variant = .primary
    var size: Size = .regular
    var isLoading: Bool = false
    var fullWidth: Bool = false

    enum Variant { case primary, secondary, destructive, ghost, accent }
    enum Size { case compact, regular, large }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.iconTextGap) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(foregroundColor)
                    .scaleEffect(0.8)
            }
            configuration.label
        }
        .font(fontSize)
        .fontWeight(.semibold)
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .frame(height: height)
        .padding(.horizontal, horizontalPadding)
        .background(background(isPressed: configuration.isPressed))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(border)
        .opacity(configuration.isPressed ? 0.85 : 1)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return .white
        case .secondary: return .accentPrimary
        case .destructive: return .white
        case .ghost: return .accentPrimary
        case .accent: return .black
        }
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch variant {
        case .primary:
            Color.accentPrimary.opacity(isPressed ? 0.85 : 1)
        case .secondary:
            Color.accentPrimary.opacity(isPressed ? 0.15 : 0.1)
        case .destructive:
            Color.statusError.opacity(isPressed ? 0.85 : 1)
        case .ghost:
            Color.clear
        case .accent:
            Color.tabSelected.opacity(isPressed ? 0.85 : 1)
        }
    }

    @ViewBuilder
    private var border: some View {
        if variant == .secondary {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.accentPrimary.opacity(0.3), lineWidth: 1)
        }
    }

    private var height: CGFloat {
        switch size {
        case .compact: return Spacing.Size.buttonHeightCompact
        case .regular: return Spacing.Size.buttonHeight
        case .large: return 56
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .compact: return Spacing.md
        case .regular: return Spacing.buttonHorizontal
        case .large: return Spacing.xl
        }
    }

    private var fontSize: Font {
        switch size {
        case .compact: return .mtrxCaptionBold
        case .regular: return .mtrxCalloutBold
        case .large: return .mtrxBodyBold
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .compact: return Spacing.CornerRadius.sm
        case .regular: return Spacing.CornerRadius.md
        case .large: return Spacing.CornerRadius.lg
        }
    }
}

// MARK: - Text Field

struct MtrxTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.labelTertiary)
                    .frame(width: 20)
            }

            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.mtrxBody)
            } else {
                TextField(placeholder, text: $text)
                    .font(.mtrxBody)
                    .keyboardType(keyboardType)
            }

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.labelTertiary)
                        .accessibilityLabel("Clear text")
                }
            }
        }
        .padding(.horizontal, Spacing.textFieldPadding)
        .frame(height: Spacing.Size.textFieldHeight)
        .background(Color.surfaceOverlay)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

// MARK: - Search Bar

struct MtrxSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: Symbols.search)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.labelTertiary)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .font(.mtrxBody)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.labelTertiary)
                        .accessibilityLabel("Clear search")
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 42)
        .background(Color.surfaceOverlay)
        // Softer, rounder field — the Discover search reads friendlier.
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Badge

struct MtrxBadge: View {
    let text: String
    var style: BadgeStyle = .info

    enum BadgeStyle {
        case success, warning, error, info, neutral, accent
        var color: Color {
            switch self {
            case .success: return .statusSuccess
            case .warning: return .statusWarning
            case .error: return .statusError
            case .info: return .statusInfo
            case .neutral: return .labelTertiary
            case .accent: return .accentPrimary
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.mtrxCaptionBold)
            .foregroundStyle(style.color)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(style.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Chip / Filter

struct MtrxChip: View {
    let label: String
    var icon: String? = nil
    var isSelected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(label)
                    .font(.mtrxCaptionBold)
            }
            .foregroundStyle(isSelected ? Color.accentPrimary : Color.labelSecondary)
            .padding(.horizontal, Spacing.chipHorizontal)
            .padding(.vertical, Spacing.chipVertical)
            .background {
                if isSelected {
                    Capsule().fill(Color.accentPrimary.opacity(0.16))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay(
                Capsule().stroke(
                    isSelected ? Color.accentPrimary.opacity(0.45) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
            )
            .shadow(color: isSelected ? Color.accentPrimary.opacity(0.25) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header

struct MtrxSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(colors: [.trinityPrimary, .trinityPrimary.opacity(0.2)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 3, height: 16)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.mtrxTitle3)
                        .foregroundStyle(Color.labelPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            Spacer()
            if let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.accentPrimary)
                }
            }
        }
    }
}

// MARK: - List Row

struct MtrxListRow<Leading: View, Trailing: View>: View {
    var icon: String? = nil
    var iconColor: Color = .accentPrimary
    let title: String
    var subtitle: String? = nil
    var showChevron: Bool = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String? = nil,
        iconColor: Color = .accentPrimary,
        title: String,
        subtitle: String? = nil,
        showChevron: Bool = true,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showChevron = showChevron
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Spacing.ms) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
            }
            leading()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            Spacer()
            trailing()

            if showChevron {
                Image(systemName: Symbols.forward)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .padding(.vertical, Spacing.listRowVertical)
        .padding(.horizontal, Spacing.listRowHorizontal)
        .contentShape(Rectangle())
    }
}

// MARK: - Token / Avatar

struct MtrxAvatar: View {
    var symbol: String? = nil
    var text: String? = nil
    var color: Color = .accentPrimary
    var size: CGFloat = Spacing.Size.avatarMedium

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(color)
            } else if let text {
                Text(String(text.prefix(2)).uppercased())
                    .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Stat Card

struct MtrxStatCard: View {
    let title: String
    let value: String
    var change: String? = nil
    var isPositive: Bool = true
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(title)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                Spacer()
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentPrimary)
                }
            }

            Text(value)
                .font(.mtrxMonoMedium)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let change {
                HStack(spacing: 3) {
                    Image(systemName: isPositive ? Symbols.trendUp : Symbols.trendDown)
                        .font(.system(size: 10, weight: .bold))
                    Text(change)
                        .font(.mtrxCaptionBold)
                }
                .foregroundStyle(isPositive ? Color.priceUp : Color.priceDown)
            }
        }
        .padding(Spacing.ms)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Progress Ring

struct MtrxProgressRing: View {
    let progress: Double
    var size: CGFloat = 60
    var lineWidth: CGFloat = 6
    var color: Color = .accentPrimary
    var showLabel: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.springDefault, value: progress)

            if showLabel {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.labelPrimary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Empty State

struct MtrxEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.labelTertiary)
                .padding(.bottom, Spacing.sm)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                Text(message)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .accessibilityElement(children: .combine)

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular))
                .padding(.top, Spacing.sm)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Loading / Skeleton

struct MtrxSkeletonRow: View {
    var body: some View {
        HStack(spacing: Spacing.ms) {
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.xs)
                .fill(Color.surfaceOverlay)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.surfaceOverlay)
                    .frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.surfaceOverlay)
                    .frame(width: 80, height: 12)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.surfaceOverlay)
                .frame(width: 60, height: 14)
        }
        .padding(.vertical, Spacing.ms)
        .padding(.horizontal, Spacing.md)
        .mtrxShimmer(isActive: true)
    }
}

struct MtrxLoadingView: View {
    var rows: Int = 6

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                MtrxSkeletonRow()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

// MARK: - Error View

struct MtrxErrorView: View {
    let message: String
    var retryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.statusError.opacity(0.7))
                .accessibilityHidden(true)

            VStack(spacing: Spacing.sm) {
                Text("Something went wrong")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                Text(message)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)

            if let retryAction {
                Button("Try Again", action: retryAction)
                    .buttonStyle(MtrxButtonStyle(variant: .secondary))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Toast

struct MtrxToast: View {
    let message: String
    var icon: String = "checkmark.circle.fill"
    var style: MtrxBadge.BadgeStyle = .success

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(style.color)

            Text(message)
                .font(.mtrxCallout)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.ms)
        .background(.ultraThickMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
    }
}

// MARK: - Sheet Header

struct MtrxSheetHeader: View {
    let title: String
    var subtitle: String? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.labelTertiary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.sm)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.mtrxTitle3)
                        .foregroundStyle(Color.labelPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                Spacer()
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: Symbols.close)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.labelSecondary)
                            .frame(width: 30, height: 30)
                            .background(Color.surfaceOverlay)
                            .clipShape(Circle())
                            .accessibilityLabel("Dismiss")
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.bottom, Spacing.sm)
    }
}

// MARK: - Themed Divider

struct MtrxDivider: View {
    var color: Color = .separatorStandard
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 0.5)
    }
}

// MARK: - Animated Number

struct MtrxAnimatedValue: View {
    let value: Double
    var prefix: String = "$"
    var decimals: Int = 2
    var font: Font = .mtrxMonoLarge
    var color: Color = .labelPrimary

    @State private var displayValue: Double = 0

    var body: some View {
        Text(formattedValue)
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: displayValue))
            .onAppear {
                withAnimation(Motion.springDefault) {
                    displayValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(Motion.springDefault) {
                    displayValue = newValue
                }
            }
    }

    private var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        let formatted = formatter.string(from: NSNumber(value: displayValue)) ?? "0.00"
        return "\(prefix)\(formatted)"
    }
}

// MARK: - Glow Effect Modifier

extension View {
    func mtrxGlow(color: Color = .accentPrimary, radius: CGFloat = 8) -> some View {
        self
            .shadow(color: color.opacity(0.4), radius: radius / 2)
            .shadow(color: color.opacity(0.2), radius: radius)
    }

    func mtrxAccentBorder(cornerRadius: CGFloat = Spacing.CornerRadius.md) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.accentPrimary.opacity(0.5), Color.accentPrimary.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Haptic Feedback

enum MtrxHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Demo data badge (Phase 2: honest demo↔live flip)

/// A small "Demo data" pill for screens running on bundled DEMO data — i.e.
/// when `PendingCredentials.isBackendConfigured == false`. It marks demo content
/// so it is never passed off as real, and disappears automatically once the
/// backend gateway is configured and the view flips to live service data.
struct DemoBadge: View {
    var label: String = "Demo data"
    // The demo-data badge is intentionally NOT shown anywhere — DEBUG or
    // RELEASE — per the owner's request. The demo-vs-live `isDemo` logic and
    // every `.demoBadge(_:)` / `DemoBadge()` call site are unchanged; only the
    // visible pill is suppressed by rendering nothing here. To bring it back
    // (e.g. for a dev pass), restore the orange-pill body below.
    var body: some View {
        #if false
        HStack(spacing: 4) {
            Image(systemName: "testtube.2")
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.orange.opacity(0.15)))
        .accessibilityLabel("\(label) — not live")
        #else
        EmptyView()
        #endif
    }
}

extension View {
    /// Presents an honest "not available in this build" alert. Use it on a demo
    /// action button so the action tells the truth instead of faking a success
    /// (never a fake 'Success'). Demo DATA on the screen is unaffected — only
    /// the consequential action is gated honestly.
    func honestActionAlert(_ presented: Binding<Bool>, message: String) -> some View {
        alert("Not available", isPresented: presented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    /// Overlays a demo badge (top-trailing) when `isDemo` is true.
    @ViewBuilder
    func demoBadge(_ isDemo: Bool, label: String = "Demo data") -> some View {
        if isDemo {
            overlay(alignment: .topTrailing) { DemoBadge(label: label).padding(8) }
        } else {
            self
        }
    }
}
