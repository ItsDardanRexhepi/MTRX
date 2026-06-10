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

    // MARK: - App Storage

    @AppStorage("mtrx_privacy_level") private var selectedLevel: String = "standard"
    @AppStorage("mtrx_profile_visibility") private var profileVisibility: String = "Public"
    @AppStorage("mtrx_hide_addresses") private var hideAddresses: Bool = false
    @AppStorage("mtrx_private_tx") private var privateTx: Bool = false
    @AppStorage("mtrx_show_online") private var showOnline: Bool = true
    @AppStorage("mtrx_analytics") private var analytics: Bool = true
    @AppStorage("mtrx_crash_reports") private var crashReports: Bool = true
    @AppStorage("mtrx_trinity_learning") private var trinityLearning: Bool = true

    // MARK: - State

    @State private var showDeleteConfirmation = false
    @State private var showExportReady = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                privacyLevelSection
                profileVisibilitySection
                dataSection
                securitySection
                dangerZoneSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Privacy & Security")
            .confirmationDialog(
                "Delete Account",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete my account permanently", role: .destructive) {
                    MtrxHaptics.error()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action is irreversible. All data, tokens, and history associated with your account will be permanently deleted.")
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

    // MARK: - Security Section

    private var securitySection: some View {
        Section {
            NavigationLink {
                connectedAppsPlaceholder
            } label: {
                HStack {
                    Text("Connected Apps")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Text("3 connected")
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

    private var connectedAppsPlaceholder: some View {
        MtrxEmptyState(
            icon: "app.connected.to.app.below.fill",
            title: "Connected Apps",
            message: "Manage applications connected to your MTRX account."
        )
        .background(Color.backgroundPrimary)
        .navigationTitle("Connected Apps")
        .navigationBarTitleDisplayMode(.inline)
    }

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

// MARK: - Preview

#Preview("Privacy & Security") {
    PrivacyView()
        .preferredColorScheme(.dark)
}
