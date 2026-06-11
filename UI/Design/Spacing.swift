// Spacing.swift
// MTRX
//
// HIG-compliant spacing system with consistent spatial values.

import SwiftUI

// MARK: - Spacing Scale

enum Spacing {

    // MARK: - Base Scale (Apple HIG Compliant)

    /// 4pt — Extra small spacing for tight groupings
    static let xs: CGFloat = 8

    /// 8pt — Small spacing for related elements
    static let sm: CGFloat = 12

    /// 12pt — Medium-small for compact layouts
    static let ms: CGFloat = 12

    /// 16pt — Medium spacing, standard padding
    static let md: CGFloat = 16

    /// 20pt — Medium-large for section spacing
    static let ml: CGFloat = 20

    /// 24pt — Large spacing for section gaps
    static let lg: CGFloat = 24

    /// 32pt — Extra large for major sections
    static let xl: CGFloat = 32

    /// 48pt — Double extra large for page-level spacing
    static let xxl: CGFloat = 48

    /// 64pt — Triple extra large for hero sections
    static let xxxl: CGFloat = 64

    // MARK: - Semantic Spacing

    /// Standard content padding (16pt)
    static let contentPadding: CGFloat = md

    /// Standard card padding (16pt)
    static let cardPadding: CGFloat = md

    /// List row vertical padding (12pt)
    static let listRowVertical: CGFloat = ms

    /// List row horizontal padding (16pt)
    static let listRowHorizontal: CGFloat = md

    /// Section header bottom spacing (8pt)
    static let sectionHeaderBottom: CGFloat = sm

    /// Section footer top spacing (8pt)
    static let sectionFooterTop: CGFloat = sm

    /// Inter-section spacing (24pt)
    static let sectionGap: CGFloat = lg

    /// Tab bar safe area bottom
    static let tabBarSafeArea: CGFloat = 49

    // MARK: - Component Specific

    /// Button horizontal padding (20pt)
    static let buttonHorizontal: CGFloat = ml

    /// Button vertical padding (12pt)
    static let buttonVertical: CGFloat = ms

    /// Icon-to-text gap (8pt)
    static let iconTextGap: CGFloat = sm

    /// Text field internal padding (12pt)
    static let textFieldPadding: CGFloat = ms

    /// Chip/tag padding horizontal (12pt)
    static let chipHorizontal: CGFloat = ms

    /// Chip/tag padding vertical (6pt)
    static let chipVertical: CGFloat = 6

    /// Avatar-to-content gap (12pt)
    static let avatarContentGap: CGFloat = ms

    /// Navigation bar item spacing (16pt)
    static let navBarItemSpacing: CGFloat = md

    // MARK: - Corner Radius

    enum CornerRadius {
        /// 4pt — Small chips, tags
        static let xs: CGFloat = 8

        /// 8pt — Buttons, text fields
        static let sm: CGFloat = 12

        /// 12pt — Cards, sheets
        static let md: CGFloat = 18

        /// 16pt — Large cards, modals
        static let lg: CGFloat = 24

        /// 20pt — Bottom sheets
        static let xl: CGFloat = 28

        /// 24pt — Full-screen modals
        static let xxl: CGFloat = 32

        /// Capsule — Pill shapes
        static let capsule: CGFloat = .infinity
    }

    // MARK: - Size

    enum Size {
        /// Small icon size (20pt)
        static let iconSmall: CGFloat = 20

        /// Medium icon size (24pt)
        static let iconMedium: CGFloat = 24

        /// Large icon size (28pt)
        static let iconLarge: CGFloat = 28

        /// Small avatar (32pt)
        static let avatarSmall: CGFloat = 32

        /// Medium avatar (40pt)
        static let avatarMedium: CGFloat = 40

        /// Large avatar (56pt)
        static let avatarLarge: CGFloat = 56

        /// Extra large avatar (80pt)
        static let avatarXLarge: CGFloat = 80

        /// Minimum touch target (44pt per Apple HIG)
        static let minTouchTarget: CGFloat = 44

        /// Standard button height (50pt)
        static let buttonHeight: CGFloat = 50

        /// Compact button height (36pt)
        static let buttonHeightCompact: CGFloat = 36

        /// Standard text field height (44pt)
        static let textFieldHeight: CGFloat = 44
    }
}

// MARK: - Spacing View Modifiers

extension View {
    /// Apply standard content padding
    func mtrxContentPadding() -> some View {
        padding(Spacing.contentPadding)
    }

    /// Apply standard card padding
    func mtrxCardPadding() -> some View {
        padding(Spacing.cardPadding)
    }

    /// Apply standard card styling with background and corner radius
    func mtrxCardStyle() -> some View {
        self
            .padding(Spacing.cardPadding)
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }

    /// Apply minimum touch target size per Apple HIG
    func mtrxMinTouchTarget() -> some View {
        frame(minWidth: Spacing.Size.minTouchTarget, minHeight: Spacing.Size.minTouchTarget)
    }
}
