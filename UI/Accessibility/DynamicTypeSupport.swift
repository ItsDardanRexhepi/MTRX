import SwiftUI

/// Dynamic Type scaling for visual impairments — minimum 44x44pt touch targets
struct DynamicTypeSupport {
    @ScaledMetric(relativeTo: .body) static var bodyPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) static var captionPadding: CGFloat = 8
    @ScaledMetric(relativeTo: .title) static var titleSpacing: CGFloat = 16
    @ScaledMetric(relativeTo: .body) static var minimumTouchTarget: CGFloat = 44
    @ScaledMetric(relativeTo: .body) static var iconSize: CGFloat = 24
}

/// Accessible button that always meets minimum touch target of 44x44pt
struct AccessibleButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(minWidth: 44, minHeight: 44)
        }
    }
}

/// View modifier ensuring minimum touch targets
struct MinimumTouchTarget: ViewModifier {
    @ScaledMetric private var minSize: CGFloat = 44

    func body(content: Content) -> some View {
        content.frame(minWidth: minSize, minHeight: minSize)
    }
}

/// Text that scales with Dynamic Type and wraps correctly
struct ScalableText: View {
    let text: String
    let style: Font.TextStyle

    var body: some View {
        Text(text)
            .font(.system(style))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func minimumTouchTarget() -> some View { modifier(MinimumTouchTarget()) }
}
