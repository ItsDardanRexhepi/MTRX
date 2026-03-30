// LiveActivityView.swift
// MTRX Apple Integration — Presence
// Live activity UI for transactions on Dynamic Island and Lock Screen

import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget

struct MTRXLiveActivityWidget: Widget {
    let kind: String = "MTRXTransactionActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MTRXTransactionAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(state: context.state, attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(state: context.state)
                }
            } compactLeading: {
                CompactLeadingView(state: context.state)
            } compactTrailing: {
                CompactTrailingView(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<MTRXTransactionAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay {
                    if context.state.status == .confirming {
                        Circle()
                            .stroke(statusColor.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.transactionType.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("\(context.state.amount) \(context.state.symbol)")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                if context.state.status == .confirming {
                    Text("\(context.state.confirmations)/\(context.state.requiredConfirmations)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress ring
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(statusColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 32, height: 32)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var progress: Double {
        guard context.state.requiredConfirmations > 0 else { return context.state.status == .confirmed ? 1.0 : 0.0 }
        return Double(context.state.confirmations) / Double(context.state.requiredConfirmations)
    }

    private var statusColor: Color {
        switch context.state.status {
        case .pending: return .orange
        case .confirming: return .blue
        case .confirmed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    private var statusLabel: String {
        switch context.state.status {
        case .pending: return "Pending"
        case .confirming: return "Confirming"
        case .confirmed: return "Confirmed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Dynamic Island Components

struct CompactLeadingView: View {
    let state: MTRXTransactionAttributes.ContentState

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .foregroundStyle(state.status == .confirmed ? .green : .blue)
    }
}

struct CompactTrailingView: View {
    let state: MTRXTransactionAttributes.ContentState

    var body: some View {
        Text("\(state.confirmations)/\(state.requiredConfirmations)")
            .font(.caption2)
            .fontWeight(.medium)
            .monospacedDigit()
    }
}

struct MinimalView: View {
    let state: MTRXTransactionAttributes.ContentState

    var body: some View {
        Image(systemName: state.status == .confirmed ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
            .foregroundStyle(state.status == .confirmed ? .green : .blue)
    }
}

struct ExpandedLeadingView: View {
    let state: MTRXTransactionAttributes.ContentState
    let attributes: MTRXTransactionAttributes

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attributes.transactionType.capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(attributes.chainName)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct ExpandedTrailingView: View {
    let state: MTRXTransactionAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(state.amount)")
                .font(.headline)
                .fontWeight(.bold)
            Text(state.symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ExpandedCenterView: View {
    let state: MTRXTransactionAttributes.ContentState

    var body: some View {
        if let counterparty = state.counterparty {
            Text("To: \(counterparty)")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct ExpandedBottomView: View {
    let state: MTRXTransactionAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(state.status == .confirmed ? .green : .blue)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)

            HStack {
                Text("\(state.confirmations) of \(state.requiredConfirmations) confirmations")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if let eta = state.estimatedCompletion {
                    Text(eta, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var progress: Double {
        guard state.requiredConfirmations > 0 else { return state.status == .confirmed ? 1.0 : 0.0 }
        return Double(state.confirmations) / Double(state.requiredConfirmations)
    }
}
