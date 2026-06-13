// MeshOutboxComponents.swift (formerly NetworkTopologyIndicator)
// MTRX
//
// The on-screen transport indicator was removed app-wide. What remains
// is the Mesh Outbox card — the transient "Queued in Outbox" view used
// by the Build dashboard when an action is initialized off-grid.

import SwiftUI

// MARK: - Mesh Outbox Card

/// The transient "Queued in Outbox" card with a non-blocking marquee and
/// live packet accounting. Used in the Build dashboard and Transport sheet.
struct MeshOutboxCard: View {
    let entry: MeshOutbox.Entry
    @State private var marquee = false

    private var label: String {
        switch entry.intent.kind {
        case .payment: return "Payment"
        case .message: return "Message"
        case .contract: return "Contract deployment"
        case .identity: return "Identity update"
        case .insurance: return "Insurance action"
        }
    }

    var body: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: icon)
                        .foregroundStyle(stateColor)
                    Text(label).font(.mtrxCaptionBold).foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Text(stateText).font(.mtrxCaption2).foregroundStyle(stateColor)
                }

                // Non-blocking marquee track.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.surfaceOverlay).frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(colors: [Color.trinityPrimary.opacity(0.2), Color.trinityPrimary, Color.trinityPrimary.opacity(0.2)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * 0.4, height: 4)
                            .offset(x: marquee ? geo.size.width * 0.6 : -geo.size.width * 0.05)
                            .opacity(entry.state == .broadcasting ? 1 : 0)
                        Capsule()
                            .fill(Color.statusSuccess)
                            .frame(width: geo.size.width * CGFloat(entry.totalPackets > 0 ? Double(entry.sentPackets) / Double(entry.totalPackets) : 0), height: 4)
                            .opacity(entry.state == .delivered ? 1 : 0.0)
                    }
                }
                .frame(height: 4)

                Text("Broadcasting via local transport (Packet \(min(entry.sentPackets + (entry.state == .broadcasting ? 1 : 0), entry.totalPackets)) of \(entry.totalPackets) verified)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { marquee = true }
        }
    }

    private var icon: String {
        switch entry.state {
        case .queued: return "tray.full"
        case .broadcasting: return "dot.radiowaves.left.and.right"
        case .delivered: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    private var stateColor: Color {
        switch entry.state {
        case .queued: return .labelSecondary
        case .broadcasting: return .trinityPrimary
        case .delivered: return .statusSuccess
        case .failed: return .statusError
        }
    }
    private var stateText: String {
        switch entry.state {
        case .queued: return "Queued"
        case .broadcasting: return "Broadcasting"
        case .delivered: return "Delivered"
        case .failed: return "Retry"
        }
    }
}
