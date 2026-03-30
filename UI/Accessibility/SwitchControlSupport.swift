import SwiftUI

/// Switch Control navigation support for motor impairments
/// Ensures proper focus management and custom accessibility actions throughout the app
struct SwitchControlSupport {
    /// Define scan groups for Switch Control navigation on main tabs
    static func mainTabAccessibilityElements() -> [String] {
        ["Home tab", "Build tab", "Discover tab", "Social tab", "Account tab"]
    }
}

/// View modifier for adding Switch Control-friendly actions to financial views
struct SwitchControlActions: ViewModifier {
    let primaryAction: (() -> Void)?
    let primaryLabel: String
    let secondaryAction: (() -> Void)?
    let secondaryLabel: String?

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: primaryLabel) { primaryAction?() }
            .accessibilityAction(named: secondaryLabel ?? "") { secondaryAction?() }
    }
}

/// Focus management for Switch Control scanning order
struct FocusableSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading) {
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Quick action accessibility for common operations
struct QuickActions: View {
    let actions: [(label: String, icon: String, action: () -> Void)]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(actions.indices, id: \.self) { i in
                Button(action: actions[i].action) {
                    VStack(spacing: 4) {
                        Image(systemName: actions[i].icon).font(.title3)
                        Text(actions[i].label).font(.caption2)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(actions[i].label)
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}

extension View {
    func switchControlActions(primary: String, primaryAction: @escaping () -> Void,
                              secondary: String? = nil, secondaryAction: (() -> Void)? = nil) -> some View {
        modifier(SwitchControlActions(primaryAction: primaryAction, primaryLabel: primary,
                                       secondaryAction: secondaryAction, secondaryLabel: secondary))
    }
}
