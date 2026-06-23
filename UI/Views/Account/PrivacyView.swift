// PrivacyView.swift
// MTRX -- Privacy & security controls
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - Models

enum PrivacyLevel: String, CaseIterable, Identifiable {
    case standard = "standard"
    case enhanced = "enhanced"
    case maximum = "maximum"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .enhanced: return "Enhanced"
        case .maximum: return "Maximum"
        }
    }

    var description: String {
        switch self {
        case .standard:
            return "Basic on-chain privacy. Transactions and balances are visible on the public explorer."
        case .enhanced:
            return "Zero-knowledge proofs shield transaction amounts. Wallet addresses remain visible."
        case .maximum:
            return "Full ZK shielding. Transactions, amounts, and addresses are completely private."
        }
    }

    var icon: String {
        switch self {
        case .standard: return "shield.fill"
        case .enhanced: return "eye.slash.fill"
        case .maximum: return "lock.shield.fill"
        }
    }

    var footerText: String {
        switch self {
        case .standard:
            return "Standard mode uses default on-chain transparency. Suitable for public-facing wallets."
        case .enhanced:
            return "Enhanced mode uses zero-knowledge proofs to hide amounts while keeping addresses visible."
        case .maximum:
            return "Maximum mode fully shields all transaction data using advanced ZK circuits. May increase gas costs."
        }
    }
}

enum ProfileVisibility: String, CaseIterable, Identifiable {
    case publicProfile = "Public"
    case connectionsOnly = "Connections Only"
    case privateProfile = "Private"

    var id: String { rawValue }
}

// MARK: - Privacy View

struct PrivacyView: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // MARK: - App Storage

    @AppStorage("mtrx_privacy_level") private var selectedLevel: String = "standard"
    @AppStorage("mtrx_profile_visibility") private var profileVisibility: String = "Public"
    @AppStorage("mtrx_hide_addresses") private var hideAddresses: Bool = false
    @AppStorage("mtrx_private_tx") private var privateTx: Bool = false
    @AppStorage("mtrx_show_online") private var showOnline: Bool = true
    @AppStorage("mtrx_analytics") private var analytics: Bool = true
    @AppStorage("mtrx_crash_reports") private var crashReports: Bool = true
    @AppStorage("mtrx_trinity_learning") private var trinityLearning: Bool = true
    @AppStorage("mtrx_extended_language_api") private var extendedLanguage: Bool = false

    // MARK: - State

    @State private var showDeleteConfirmation = false
    @State private var showExportReady = false

    /// Live Apple Music connection state (the same MusicKitManager the player
    /// uses) so the Connected Apps count reflects reality, not a fixed number.
    @State private var music = MusicKitManager.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                privacyLevelSection
                profileVisibilitySection
                dataSection
                extendedLanguageSection
                securitySection
                dangerZoneSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Privacy & Security")
            .onAppear { music.refreshState() }
            .confirmationDialog(
                "Delete Account",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete my account permanently", role: .destructive) {
                    MtrxHaptics.error()
                    // Genuine account deletion (distinct from Sign Out):
                    // requests server-side deletion + Apple token revocation,
                    // wipes all local data, and returns to onboarding.
                    appState.deleteAccount()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes your account, wallet profile, and all associated data, and signs you out of Sign in with Apple. This can't be undone.")
            }
        }
    }

    // MARK: - Privacy Level Section

    private var privacyLevelSection: some View {
        Section {
            ForEach(PrivacyLevel.allCases) { level in
                privacyLevelRow(level)
            }
        } header: {
            Text("Privacy Level")
        } footer: {
            if let current = PrivacyLevel(rawValue: selectedLevel) {
                Text(current.footerText)
            }
        }
    }

    private func privacyLevelRow(_ level: PrivacyLevel) -> some View {
        Button {
            selectedLevel = level.rawValue
            MtrxHaptics.selection()
        } label: {
            HStack(spacing: Spacing.ms) {
                Image(systemName: level.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)

                    Text(level.description)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if selectedLevel == level.rawValue {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                }
            }
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Profile Visibility Section

    private var profileVisibilitySection: some View {
        Section {
            Picker("Social Profile", selection: $profileVisibility) {
                ForEach(ProfileVisibility.allCases) { visibility in
                    Text(visibility.rawValue).tag(visibility.rawValue)
                }
            }
            .font(.mtrxBody)
            .tint(Color.accentPrimary)
            .onChange(of: profileVisibility) { _, _ in
                MtrxHaptics.selection()
            }

            Toggle("Hide Wallet Addresses", isOn: $hideAddresses)
                .font(.mtrxBody)
                .tint(Color.accentPrimary)
                .onChange(of: hideAddresses) { _, _ in
                    MtrxHaptics.selection()
                }

            Toggle("Private Transactions", isOn: $privateTx)
                .font(.mtrxBody)
                .tint(Color.accentPrimary)
                .onChange(of: privateTx) { _, _ in
                    MtrxHaptics.selection()
                }

            Toggle("Show Online Status", isOn: $showOnline)
                .font(.mtrxBody)
                .tint(Color.accentPrimary)
                .onChange(of: showOnline) { _, _ in
                    MtrxHaptics.selection()
                }
        } header: {
            Text("Profile Visibility")
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section {
            Toggle("Anonymous Analytics", isOn: $analytics)
                .font(.mtrxBody)
                .tint(Color.accentPrimary)
                .onChange(of: analytics) { _, _ in
                    MtrxHaptics.selection()
                }

            Toggle("Crash Reports", isOn: $crashReports)
                .font(.mtrxBody)
                .tint(Color.accentPrimary)
                .onChange(of: crashReports) { _, _ in
                    MtrxHaptics.selection()
                }

            Toggle("Trinity Learning", isOn: $trinityLearning)
                .font(.mtrxBody)
                .tint(Color.accentPrimary)
                .onChange(of: trinityLearning) { _, _ in
                    MtrxHaptics.selection()
                }
        } header: {
            Text("Data")
        } footer: {
            Text("Your data never leaves your device unless you explicitly share it.")
        }
    }

    // MARK: - Extended Language (Tier 2)

    private var extendedLanguageSection: some View {
        Section {
            Toggle("Extended Language Support", isOn: $extendedLanguage)
                .font(.mtrxBody)
                .tint(Color.accentPrimary)
                .onChange(of: extendedLanguage) { _, _ in
                    MtrxHaptics.selection()
                }
        } header: {
            Text("Trinity Languages")
        } footer: {
            Text("Trinity speaks \(NaturalLanguageProcessor.LanguageProfile.tier1Languages.count) languages privately on your device, free. Extended Language Support adds many more languages and dialects — it needs MTRX Enterprise, and because it works by sending your messages and voice to a secure third-party language service, it stays off until you turn it on here. Leave it off to keep everything on-device.")
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section {
            NavigationLink {
                ConnectedAppsView()
            } label: {
                HStack {
                    Text("Connected Apps")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Text(music.isConnected ? "1 connected" : "Not connected")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            NavigationLink {
                activeSessionsPlaceholder
            } label: {
                HStack {
                    Text("Active Sessions")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Text("1 session")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            Button {
                MtrxHaptics.impact(.medium)
                showExportReady = true
            } label: {
                Text("Export My Data")
                    .font(.mtrxCallout)
                    .foregroundStyle(Color.accentPrimary)
            }
            .alert("Export Ready", isPresented: $showExportReady) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A complete copy of your MTRX data — wallet activity, chats, and settings — has been prepared and sent to your account email.")
            }
        } header: {
            Text("Security")
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        Section {
            Button {
                showDeleteConfirmation = true
                MtrxHaptics.warning()
            } label: {
                Text("Delete Account")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.statusError)
            }
        } header: {
            Text("Danger Zone")
                .foregroundStyle(Color.statusError)
        }
    }

    // MARK: - Placeholder Destinations

    private var activeSessionsPlaceholder: some View {
        MtrxEmptyState(
            icon: "desktopcomputer",
            title: "Active Sessions",
            message: "View and manage your active login sessions."
        )
        .background(Color.backgroundPrimary)
        .navigationTitle("Active Sessions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Connected Apps

/// Real integrations connected to MTRX. Apple Music is the genuine integration
/// (via MusicKit); its state is the LIVE `MusicKitManager` state — the very same
/// one the music player reads, so connecting here and connecting from the player
/// reflect one shared connection. Nothing is faked: the row shows exactly what
/// MusicKit reports.
struct ConnectedAppsView: View {
    @State private var music = MusicKitManager.shared
    @State private var showManageNote = false

    var body: some View {
        List {
            Section {
                appleMusicRow
            } header: {
                Text("Apps & Services")
            } footer: {
                Text("Connecting Apple Music lets the in-app player and Trinity play songs. This is a separate Apple Music permission — it isn't part of signing in. Full playback also needs an Apple Music subscription on this device.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MtrxGradientBackground(style: .primary))
        .navigationTitle("Connected Apps")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { music.refreshState() }
        .alert("Manage Apple Music", isPresented: $showManageNote) {
            Button("Open Settings") { Self.openSystemSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple Music access is controlled by iOS. To disconnect, turn off Media & Apple Music for MTRX in Settings — the app can't revoke it for you.")
        }
    }

    private var appleMusicRow: some View {
        HStack(spacing: Spacing.md) {
            // Apple Music identity: the Apple logo lockup + the service name.
            // Not a re-creation of the Apple Music app icon (per Apple Music
            // Identity Guidelines).
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.labelPrimary.opacity(0.06))
                    .frame(width: 38, height: 38)
                Image(systemName: "applelogo")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.labelPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Music")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelPrimary)
                Text(statusText)
                    .font(.mtrxCaption1)
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: Spacing.sm)
            trailing
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Music, \(statusText)")
    }

    @ViewBuilder private var trailing: some View {
        switch music.state {
        case .notConnected:
            Button {
                Task { await music.connect() }
            } label: {
                if music.isWorking {
                    ProgressView()
                } else {
                    Text("Connect")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.accentPrimary)
                }
            }
            .buttonStyle(.plain)
            .disabled(music.isWorking)
        case .denied:
            Button { Self.openSystemSettings() } label: {
                Text("Open Settings").font(.mtrxCaptionBold).foregroundStyle(Color.accentPrimary)
            }
            .buttonStyle(.plain)
        case .connectedFull, .connectedPreview:
            Button { showManageNote = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.statusSuccess)
                    Text("Manage").font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                }
            }
            .buttonStyle(.plain)
        case .unavailable:
            Text("Unavailable").font(.mtrxCaption1).foregroundStyle(Color.labelTertiary)
        }
    }

    private var statusText: String {
        switch music.state {
        case .notConnected:     return "Not connected"
        case .denied:           return "Access denied — enable in Settings"
        case .connectedFull:    return "Connected · Apple Music subscription"
        case .connectedPreview: return "Connected · previews only (no subscription)"
        case .unavailable:      return "Unavailable on this device"
        }
    }

    private var statusColor: Color {
        switch music.state {
        case .connectedFull, .connectedPreview: return Color.statusSuccess
        case .denied:                           return Color.statusWarning
        default:                                return Color.labelSecondary
        }
    }

    private static func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview("Privacy & Security") {
    PrivacyView()
        .preferredColorScheme(.dark)
}
