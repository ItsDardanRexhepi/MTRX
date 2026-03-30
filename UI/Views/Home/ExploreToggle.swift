// ExploreToggle.swift
// MTRX
//
// Toggle between dashboard and explore/discover modes.

import SwiftUI

// MARK: - Explore Toggle Mode

enum ExploreMode: String, CaseIterable {
    case dashboard = "Dashboard"
    case explore = "Explore"
}

// MARK: - Explore Toggle View

struct ExploreToggle: View {
    @Binding var selectedMode: ExploreMode
    @Namespace private var toggleNamespace

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ExploreMode.allCases, id: \.self) { mode in
                toggleButton(for: mode)
            }
        }
        .padding(Spacing.xs)
        .background(Color.surfaceOverlay)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("View mode")
        .accessibilityValue(selectedMode.rawValue)
    }

    // MARK: - Toggle Button

    private func toggleButton(for mode: ExploreMode) -> some View {
        Button {
            withAnimation(Motion.springSnappy) {
                selectedMode = mode
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(mode.rawValue)
                    .font(.mtrxCaptionBold)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                Group {
                    if selectedMode == mode {
                        Capsule()
                            .fill(Color.accentPrimary)
                            .matchedGeometryEffect(id: "toggleBackground", in: toggleNamespace)
                    }
                }
            )
            .foregroundStyle(selectedMode == mode ? .white : Color.labelSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
    }
}

// MARK: - Mode Properties

extension ExploreMode {
    var icon: String {
        switch self {
        case .dashboard: return Symbols.chartBar
        case .explore: return Symbols.discover
        }
    }

    var description: String {
        switch self {
        case .dashboard: return "View your portfolio dashboard"
        case .explore: return "Discover new opportunities"
        }
    }
}

// MARK: - Explore Toggle Container

/// Container view that switches between Dashboard and Explore content
struct ExploreToggleContainer: View {
    @State private var selectedMode: ExploreMode = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            ExploreToggle(selectedMode: $selectedMode)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.vertical, Spacing.sm)

            Group {
                switch selectedMode {
                case .dashboard:
                    DashboardView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .explore:
                    DiscoverView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .animation(Motion.springDefault, value: selectedMode)
        }
    }
}

// MARK: - Preview

#Preview {
    ExploreToggleContainer()
        .environmentObject(WalletManager())
}
