// NetworkTopologyIndicator.swift
// MTRX
//
// The global transport-state badge for the top-right of primary views.
// Driven live by NetworkPathMonitor:
//   • Unconstrained → a solid teal status ring
//   • Mesh          → concentric waves (local BLE outbox carrying traffic)
//   • Constrained   → an orbital graphic (hyper-compression over a
//                     restricted carrier / satellite link)
// Tapping it opens the Transport sheet with detail + the mesh outbox.

import SwiftUI

struct NetworkTopologyIndicator: View {
    @ObservedObject private var monitor = NetworkPathMonitor.shared
    @ObservedObject private var outbox = MeshOutbox.shared
    @State private var pulse = false
    @State private var showSheet = false

    private var accent: Color {
        switch monitor.state {
        case .unconstrained: return .trinityPrimary
        case .mesh: return Color(red: 0.62, green: 0.40, blue: 0.96)
        case .constrained: return Color(red: 0.98, green: 0.65, blue: 0.15)
        }
    }

    var body: some View {
        Button {
            MtrxHaptics.impact(.light)
            showSheet = true
        } label: {
            ZStack {
                switch monitor.state {
                case .unconstrained: solidRing
                case .mesh: meshWaves
                case .constrained: satelliteOrbit
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
        .sheet(isPresented: $showSheet) {
            TransportSheet()
        }
    }

    // Unconstrained — premium solid teal ring.
    private var solidRing: some View {
        Circle()
            .stroke(accent, lineWidth: 2.5)
            .frame(width: 18, height: 18)
            .overlay(Circle().fill(accent.opacity(pulse ? 0.9 : 0.5)).frame(width: 6, height: 6))
            .shadow(color: accent.opacity(0.6), radius: pulse ? 5 : 2)
    }

    // Mesh — concentric outgoing waves.
    private var meshWaves: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(accent.opacity(0.7 - Double(i) * 0.22), lineWidth: 1.5)
                    .frame(width: pulse ? CGFloat(10 + i * 9) : CGFloat(6 + i * 6),
                           height: pulse ? CGFloat(10 + i * 9) : CGFloat(6 + i * 6))
            }
            Circle().fill(accent).frame(width: 6, height: 6)
            // Tiny pending-count badge.
            if outbox.pendingCount > 0 {
                Text("\(outbox.pendingCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 11, y: -11)
            }
        }
    }

    // Constrained — an orbiting node around a core (satellite link).
    private var satelliteOrbit: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.35), lineWidth: 1).frame(width: 22, height: 22)
            Circle().fill(accent).frame(width: 7, height: 7)
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .offset(x: 11)
                .rotationEffect(.degrees(pulse ? 360 : 0))
                .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: pulse)
        }
    }
}

// MARK: - Transport Sheet

struct TransportSheet: View {
    @ObservedObject private var monitor = NetworkPathMonitor.shared
    @ObservedObject private var outbox = MeshOutbox.shared
    @ObservedObject private var watchdog = HeartbeatWatchdog.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    stateCard
                    if !outbox.entries.isEmpty { outboxSection }
                    watchdogCard
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Transport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
        }
    }

    private var stateCard: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    NetworkTopologyIndicator()
                    Text(monitor.state.title)
                        .font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
                    Spacer()
                }
                Text(stateDetail)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
    }

    private var stateDetail: String {
        switch monitor.state {
        case .unconstrained: return "Standard Wi-Fi or high-speed cellular. Full app behavior, no restrictions."
        case .mesh: return "No internet path. Actions are queued in the local mesh outbox and carried over local transport until they reach a peer."
        case .constrained: return "Ultra-constrained / satellite link detected. Payloads are hyper-compressed and non-essential transfers are paused to conserve the path and battery."
        }
    }

    private var outboxSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Mesh Outbox").font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
            ForEach(outbox.entries) { entry in
                MeshOutboxCard(entry: entry)
            }
        }
    }

    private var watchdogCard: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(watchdog.hasLapsed ? Color.statusError : Color.trinityPrimary)
                    Text("Heartbeat Watchdog").font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Text(watchdog.countdownText)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(watchdog.hasLapsed ? Color.statusError : Color.labelSecondary)
                }
                ProgressView(value: watchdog.progress)
                    .tint(watchdog.hasLapsed ? Color.statusError : Color.trinityPrimary)
                Text(watchdog.hasLapsed
                     ? "Window lapsed — sensitive actions now require fresh Face ID."
                     : "Local 72-hour canary. Check in to reset the window.")
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
                Button {
                    watchdog.pushHeartbeat()
                } label: {
                    Text("Check in").font(.mtrxCaptionBold)
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.trinityPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

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
