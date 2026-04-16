// Typography.swift
// MTRX
//
// SF Pro + SF Mono semantic type scale for consistent typography across the app.

import SwiftUI

// MARK: - Typography Scale

extension Font {

    // MARK: - Display

    /// Extra large display text for hero sections — SF Pro Rounded, 40pt
    static let mtrxDisplayLarge: Font = .system(size: 40, weight: .bold, design: .rounded)

    /// Display text for section heroes — SF Pro Rounded, 34pt
    static let mtrxDisplay: Font = .system(size: 34, weight: .bold, design: .rounded)

    /// Small display for compact hero areas — SF Pro Rounded, 28pt
    static let mtrxDisplaySmall: Font = .system(size: 28, weight: .semibold, design: .rounded)

    // MARK: - Large Title

    /// Large title matching iOS navigation bar — SF Pro, 34pt
    static let mtrxLargeTitle: Font = .system(.largeTitle, design: .default, weight: .bold)

    // MARK: - Title

    /// Primary title — SF Pro, 28pt
    static let mtrxTitle1: Font = .system(.title, design: .default, weight: .bold)

    /// Secondary title — SF Pro, 22pt
    static let mtrxTitle2: Font = .system(.title2, design: .default, weight: .semibold)

    /// Tertiary title — SF Pro, 20pt
    static let mtrxTitle3: Font = .system(.title3, design: .default, weight: .semibold)

    // MARK: - Headline

    /// Headline for list rows and cards — SF Pro, 17pt semibold
    static let mtrxHeadline: Font = .system(.headline, design: .default, weight: .semibold)

    /// Subheadline for secondary information — SF Pro, 15pt
    static let mtrxSubheadline: Font = .system(.subheadline, design: .default, weight: .regular)

    // MARK: - Body

    /// Primary body text — SF Pro, 17pt
    static let mtrxBody: Font = .system(.body, design: .default, weight: .regular)

    /// Emphasized body text — SF Pro, 17pt semibold
    static let mtrxBodyBold: Font = .system(.body, design: .default, weight: .semibold)

    // MARK: - Callout

    /// Callout text for supplementary information — SF Pro, 16pt
    static let mtrxCallout: Font = .system(.callout, design: .default, weight: .regular)

    /// Emphasized callout — SF Pro, 16pt semibold
    static let mtrxCalloutBold: Font = .system(.callout, design: .default, weight: .semibold)

    // MARK: - Footnote

    /// Footnote for timestamps and metadata — SF Pro, 13pt
    static let mtrxFootnote: Font = .system(.footnote, design: .default, weight: .regular)

    /// Emphasized footnote — SF Pro, 13pt semibold
    static let mtrxFootnoteBold: Font = .system(.footnote, design: .default, weight: .semibold)

    // MARK: - Caption

    /// Primary caption — SF Pro, 12pt
    static let mtrxCaption: Font = .system(.caption, design: .default, weight: .regular)
    static let mtrxCaption1: Font = .system(.caption, design: .default, weight: .regular)

    /// Secondary caption — SF Pro, 11pt
    static let mtrxCaption2: Font = .system(.caption2, design: .default, weight: .regular)

    /// Emphasized caption — SF Pro, 12pt semibold
    static let mtrxCaptionBold: Font = .system(.caption, design: .default, weight: .semibold)

    // MARK: - Monospace (SF Mono)

    /// Large monospace for portfolio values — SF Mono, 34pt
    static let mtrxMonoLarge: Font = .system(size: 34, weight: .bold, design: .monospaced)

    /// Medium monospace for token amounts — SF Mono, 22pt
    static let mtrxMonoMedium: Font = .system(size: 22, weight: .semibold, design: .monospaced)

    /// Standard monospace for addresses and hashes — SF Mono, 15pt
    static let mtrxMono: Font = .system(size: 15, weight: .regular, design: .monospaced)

    /// Small monospace for inline code — SF Mono, 13pt
    static let mtrxMonoSmall: Font = .system(size: 13, weight: .regular, design: .monospaced)

    /// Tiny monospace for transaction IDs — SF Mono, 11pt
    static let mtrxMonoTiny: Font = .system(size: 11, weight: .regular, design: .monospaced)

    // MARK: - Tabular Numbers

    /// Body with tabular number spacing for aligned values
    static let mtrxBodyTabular: Font = .system(.body, design: .default, weight: .regular).monospacedDigit()

    /// Headline with tabular numbers for financial data
    static let mtrxHeadlineTabular: Font = .system(.headline, design: .default, weight: .semibold).monospacedDigit()
}

// MARK: - Text Style Modifiers

struct MTRXTextStyle: ViewModifier {
    let font: Font
    let color: Color
    let lineSpacing: CGFloat

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
    }
}

extension View {
    func mtrxTextStyle(_ font: Font, color: Color = .primary, lineSpacing: CGFloat = 2) -> some View {
        modifier(MTRXTextStyle(font: font, color: color, lineSpacing: lineSpacing))
    }
}
