// AccountView.swift
// MTRX - Identity hub, portfolio summary, quick actions, and settings gateway
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI
import SafariServices

// MARK: - Account View

struct AccountView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var walletManager: WalletManager

    @State private var showSignOutAlert = false
    @State private var appeared = false
    @State private var copiedDID = false
    @State private var showEditProfile = false
    @State private var showHelp = false
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sectionGap) {
                    profileCard
                    portfolioSummary
                    quickActionsGrid
                    settingsSection
                    identityAndSecuritySection
                    signOutButton
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                MtrxHaptics.impact(.light)
                try? await Task.sleep(for: .seconds(0.6))
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    appState.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out? You will need to re-authenticate to access your account.")
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showHelp) {
                HelpSupportSheet()
            }
            .sheet(isPresented: $showAbout) {
                AboutSheet()
            }
            .navigationDestination(for: AccountNavDestination.self) { destination in
                switch destination {
                case .wallet:
                    AccountWalletView()
                case .staking:
                    StakingView()
                case .governance:
                    GovernanceView()
                case .messaging:
                    MessagingView()
                case .settings:
                    SettingsView()
                case .privacy:
                    PrivacyView()
                case .subscription:
                    SubscriptionView()
                case .notifications:
                    NotificationCenterView()
                case .accessControl:
                    AccessControlView()
                case .kyc:
                    KYCView()
                case .reputation:
                    ReputationView()
                case .credentials:
                    VerifiableCredentialView()
                case .loyalty:
                    LoyaltyView()
                case .licensing:
                    LicensingView()
                case .multiSig:
                    MultiSigView()
                case .treasury:
                    TreasuryView()
                case .attestations:
                    AttestationView()
                case .alerts:
                    AlertsView()
                }
            }
        }
        .onAppear {
            withAnimation(Motion.springDefault.delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        MtrxCard(style: .glass) {
            VStack(spacing: Spacing.md) {
                // Avatar with gradient ring
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.accentPrimary, .accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: Spacing.Size.avatarXLarge + 6, height: Spacing.Size.avatarXLarge + 6)

                    MtrxAvatar(
                        text: appState.displayName.isEmpty ? "M" : String(appState.displayName.prefix(2)),
                        color: .accentPrimary,
                        size: Spacing.Size.avatarXLarge
                    )
                }

                // Display name
                Text(appState.displayName.isEmpty ? "MTRX User" : appState.displayName)
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)

                // DID identifier
                HStack(spacing: Spacing.sm) {
                    Text(truncatedDID)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)

                    Button {
                        UIPasteboard.general.string = fullDID
                        withAnimation(Motion.springSnappy) { copiedDID = true }
                        MtrxHaptics.success()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copiedDID = false }
                        }
                    } label: {
                        Image(systemName: copiedDID ? Symbols.complete : Symbols.copy)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(copiedDID ? Color.statusSuccess : Color.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }

                // Member since
                Text("Member since \(memberSinceString)")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)

                // Edit profile button
                Button {
                    showEditProfile = true
                    MtrxHaptics.impact(.light)
                } label: {
                    Text("Edit Profile")
                }
                .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))
            }
            .frame(maxWidth: .infinity)
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0)
    }

    // MARK: - Portfolio Summary

    private var portfolioSummary: some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    Text("Portfolio Value")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                }

                HStack(alignment: .firstTextBaseline) {
                    MtrxAnimatedValue(
                        value: walletManager.totalPortfolioValue,
                        font: .mtrxMonoLarge
                    )

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: walletManager.portfolioChange24h >= 0 ? Symbols.trendUp : Symbols.trendDown)
                                .font(.system(size: 11, weight: .bold))
                            Text(String(format: "%.2f%%", walletManager.portfolioChange24h))
                                .font(.mtrxCaptionBold)
                        }
                        .foregroundStyle(walletManager.portfolioChange24h >= 0 ? Color.priceUp : Color.priceDown)

                        Text(String(format: "%@$%.2f", walletManager.portfolioChangeAbsolute >= 0 ? "+" : "", walletManager.portfolioChangeAbsolute))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                NavigationLink(value: AccountNavDestination.wallet) {
                    HStack {
                        Text("View Wallet")
                            .font(.mtrxCaptionBold)
                        Image(systemName: Symbols.forward)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.accentPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.accentPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0.05)
    }

    // MARK: - Quick Actions Grid

    private var quickActionsGrid: some View {
        VStack(spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Quick Actions")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm)
            ], spacing: Spacing.sm) {
                QuickActionCard(
                    icon: Symbols.wallet,
                    label: "Wallet & Portfolio",
                    color: .statusInfo,
                    destination: .wallet
                )

                QuickActionCard(
                    icon: Symbols.stake,
                    label: "Staking & DeFi",
                    color: .accentPrimary,
                    destination: .staking
                )

                QuickActionCard(
                    icon: Symbols.dao,
                    label: "Governance",
                    color: .accentTertiary,
                    destination: .governance
                )

                QuickActionCard(
                    icon: Symbols.message,
                    label: "Messaging",
                    color: .statusSuccess,
                    destination: .messaging
                )
            }
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0.1)
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(spacing: 0) {
            MtrxSectionHeader(title: "Settings")
                .padding(.bottom, Spacing.sm)

            VStack(spacing: 0) {
                NavigationLink(value: AccountNavDestination.settings) {
                    MtrxListRow(
                        icon: Symbols.settings,
                        iconColor: .labelSecondary,
                        title: "Preferences"
                    )
                }
                .buttonStyle(.plain)

                MtrxDivider().padding(.leading, Spacing.contentPadding + 28 + Spacing.ms)

                NavigationLink(value: AccountNavDestination.privacy) {
                    MtrxListRow(
                        icon: Symbols.encrypted,
                        iconColor: .statusWarning,
                        title: "Privacy & Security"
                    )
                }
                .buttonStyle(.plain)

                MtrxDivider().padding(.leading, Spacing.contentPadding + 28 + Spacing.ms)

                NavigationLink(value: AccountNavDestination.subscription) {
                    MtrxListRow(
                        icon: "crown.fill",
                        iconColor: .accentTertiary,
                        title: "Subscription"
                    )
                }
                .buttonStyle(.plain)

                MtrxDivider().padding(.leading, Spacing.contentPadding + 28 + Spacing.ms)

                NavigationLink(value: AccountNavDestination.notifications) {
                    MtrxListRow(
                        icon: Symbols.notification,
                        iconColor: .statusInfo,
                        title: "Notifications"
                    )
                }
                .buttonStyle(.plain)

                MtrxDivider().padding(.leading, Spacing.contentPadding + 28 + Spacing.ms)

                Button {
                    showHelp = true
                    MtrxHaptics.impact(.light)
                } label: {
                    MtrxListRow(
                        icon: Symbols.help,
                        iconColor: .labelTertiary,
                        title: "Help & Support"
                    )
                }
                .buttonStyle(.plain)

                MtrxDivider().padding(.leading, Spacing.contentPadding + 28 + Spacing.ms)

                Button {
                    showAbout = true
                    MtrxHaptics.impact(.light)
                } label: {
                    MtrxListRow(
                        icon: Symbols.info,
                        iconColor: .labelTertiary,
                        title: "About MTRX",
                        subtitle: "Version 2.4.0"
                    )
                }
                .buttonStyle(.plain)
            }
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0.15)
    }

    // MARK: - Identity & Security Section

    private var identityAndSecuritySection: some View {
        VStack(spacing: 0) {
            MtrxSectionHeader(title: "Identity & Security")
                .padding(.bottom, Spacing.sm)

            VStack(spacing: 0) {
                identityRow(destination: .accessControl, icon: "key.fill", iconColor: .accentPrimary, title: "Access Control")
                identityDivider()

                identityRow(destination: .kyc, icon: "person.text.rectangle", iconColor: .statusInfo, title: "Identity Verification")
                identityDivider()

                identityRow(destination: .reputation, icon: "star.fill", iconColor: .accentTertiary, title: "Reputation")
                identityDivider()

                identityRow(destination: .credentials, icon: "seal.fill", iconColor: .statusSuccess, title: "Credentials")
                identityDivider()

                identityRow(destination: .loyalty, icon: "gift.fill", iconColor: .accentSecondary, title: "Rewards & Loyalty")
                identityDivider()

                identityRow(destination: .licensing, icon: "doc.text.fill", iconColor: .statusInfo, title: "Licenses")
                identityDivider()

                identityRow(destination: .multiSig, icon: "lock.shield", iconColor: .statusWarning, title: "Multi-Sig Wallets")
                identityDivider()

                identityRow(destination: .treasury, icon: "building.columns", iconColor: .accentPrimary, title: "Treasury")
                identityDivider()

                identityRow(destination: .attestations, icon: "checkmark.seal.fill", iconColor: .statusSuccess, title: "Attestations")
                identityDivider()

                identityRow(destination: .alerts, icon: "bell.fill", iconColor: .statusError, title: "Alerts")
            }
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0.18)
    }

    private func identityRow(destination: AccountNavDestination, icon: String, iconColor: Color, title: String) -> some View {
        NavigationLink(value: destination) {
            MtrxListRow(icon: icon, iconColor: iconColor, title: title)
        }
        .buttonStyle(.plain)
    }

    private func identityDivider() -> some View {
        MtrxDivider().padding(.leading, Spacing.contentPadding + 28 + Spacing.ms)
    }

    // MARK: - Sign Out Button

    private var signOutButton: some View {
        Button {
            showSignOutAlert = true
            MtrxHaptics.warning()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                Text("Sign Out")
                    .font(.mtrxCalloutBold)
            }
            .foregroundStyle(Color.statusError)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.buttonVertical)
            .background(Color.statusError.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                    .stroke(Color.statusError.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0.2)
    }

    // MARK: - Helpers

    private var fullDID: String {
        let addr = appState.walletAddress.isEmpty ? "0x7a3b...f9e2" : appState.walletAddress
        return "did:mtrx:\(addr)"
    }

    private var truncatedDID: String {
        let addr = appState.walletAddress.isEmpty ? "0x7a3b...f9e2" : appState.walletAddress
        let did = "did:mtrx:\(addr)"
        if did.count > 28 {
            return "\(did.prefix(16))...\(did.suffix(8))"
        }
        return did
    }

    private var memberSinceString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: appState.joinDate)
    }
}

// MARK: - Navigation Destinations

enum AccountNavDestination: Hashable {
    case wallet
    case staking
    case governance
    case messaging
    case settings
    case privacy
    case subscription
    case notifications
    case accessControl
    case kyc
    case reputation
    case credentials
    case loyalty
    case licensing
    case multiSig
    case treasury
    case attestations
    case alerts
}

// MARK: - Quick Action Card

struct QuickActionCard: View {
    let icon: String
    let label: String
    let color: Color
    let destination: AccountNavDestination

    var body: some View {
        NavigationLink(value: destination) {
            MtrxCard(style: .standard) {
                VStack(spacing: Spacing.ms) {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 44, height: 44)
                        .background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                    Text(label)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var initialized = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Avatar
                    MtrxCard(style: .glass) {
                        VStack(spacing: Spacing.md) {
                            ZStack {
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.accentPrimary, .accentSecondary],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                                    .frame(width: Spacing.Size.avatarXLarge + 6, height: Spacing.Size.avatarXLarge + 6)

                                MtrxAvatar(
                                    text: initials,
                                    color: .accentPrimary,
                                    size: Spacing.Size.avatarXLarge
                                )
                            }

                            Text("Tap to change photo")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Form fields
                    VStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Display Name")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)
                            MtrxTextField(
                                placeholder: "Your name",
                                text: $displayName,
                                icon: "person.fill"
                            )
                        }

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Bio")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)
                            TextEditor(text: $bio)
                                .frame(minHeight: 110)
                                .scrollContentBackground(.hidden)
                                .padding(Spacing.sm)
                                .background(Color.surfaceOverlay)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                                .font(.mtrxBody)
                        }

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Wallet Address")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)
                            HStack {
                                Image(systemName: Symbols.wallet)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.labelTertiary)
                                Text(appState.walletAddress.isEmpty ? "0x7a3b...f9e2" : appState.walletAddress)
                                    .font(.mtrxMonoSmall)
                                    .foregroundStyle(Color.labelPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: Symbols.lock)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.labelTertiary)
                            }
                            .padding(.horizontal, Spacing.textFieldPadding)
                            .frame(height: Spacing.Size.textFieldHeight)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                        }
                    }
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.labelSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        appState.displayName = displayName
                        MtrxHaptics.success()
                        dismiss()
                    } label: {
                        Text("Save")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                }
            }
            .onAppear {
                guard !initialized else { return }
                displayName = appState.displayName
                initialized = true
            }
        }
    }

    private var initials: String {
        let source = displayName.isEmpty ? "M" : displayName
        return String(source.prefix(2))
    }
}

// MARK: - Help & Support Sheet

struct HelpSupportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedQuestion: Int? = nil

    private let faqs: [(question: String, answer: String)] = [
        ("How do I send tokens?", "Open the Wallet tab, tap Send, choose your token, paste the recipient address, and confirm with Face ID."),
        ("What is Trinity?", "Trinity is your private AI assistant inside MTRX. It can draft contracts, analyze portfolios, and execute on-chain actions on your behalf."),
        ("How do gas fees work?", "Gas pays validators to execute your transaction. MTRX shows estimated gas before you sign, and lets you choose Slow, Normal, or Fast tiers."),
        ("Is my wallet secure?", "Your private keys are stored in the Secure Enclave on your device. They never leave your phone, and biometrics are required for every signature."),
        ("How do I cancel my subscription?", "Open Account, then Subscription, and tap Manage. Cancellations take effect at the end of your current billing period.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sectionGap) {
                    // FAQ section
                    VStack(spacing: Spacing.sm) {
                        MtrxSectionHeader(title: "Common questions")

                        MtrxCard(style: .standard) {
                            VStack(spacing: 0) {
                                ForEach(Array(faqs.enumerated()), id: \.offset) { index, item in
                                    Button {
                                        withAnimation(Motion.springSnappy) {
                                            expandedQuestion = expandedQuestion == index ? nil : index
                                        }
                                        MtrxHaptics.selection()
                                    } label: {
                                        VStack(alignment: .leading, spacing: Spacing.sm) {
                                            HStack {
                                                Text(item.question)
                                                    .font(.mtrxCalloutBold)
                                                    .foregroundStyle(Color.labelPrimary)
                                                    .multilineTextAlignment(.leading)
                                                Spacer()
                                                Image(systemName: expandedQuestion == index ? "chevron.up" : "chevron.down")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(Color.labelTertiary)
                                            }

                                            if expandedQuestion == index {
                                                Text(item.answer)
                                                    .font(.mtrxCaption1)
                                                    .foregroundStyle(Color.labelSecondary)
                                                    .multilineTextAlignment(.leading)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .padding(.vertical, Spacing.sm)
                                    }
                                    .buttonStyle(.plain)

                                    if index < faqs.count - 1 {
                                        MtrxDivider()
                                    }
                                }
                            }
                        }
                    }

                    // Contact section
                    VStack(spacing: Spacing.sm) {
                        MtrxSectionHeader(title: "Contact")

                        MtrxCard(style: .standard) {
                            VStack(spacing: Spacing.sm) {
                                Button {
                                    if let url = URL(string: "mailto:support@openmatrix-ai.com") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: Symbols.message)
                                        Text("Email support")
                                        Spacer()
                                        Image(systemName: Symbols.externalLink)
                                            .font(.system(size: 12))
                                    }
                                }
                                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular, fullWidth: true))

                                Button {
                                    MtrxHaptics.impact(.light)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: Symbols.trinity)
                                        Text("Chat with Trinity")
                                        Spacer()
                                        Image(systemName: Symbols.forward)
                                            .font(.system(size: 12))
                                    }
                                }
                                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
                            }
                        }
                    }

                    // Resources section
                    VStack(spacing: Spacing.sm) {
                        MtrxSectionHeader(title: "Resources")

                        MtrxCard(style: .standard) {
                            VStack(spacing: 0) {
                                resourceLink(title: "Terms of Service", url: "https://openmatrix-ai.com/terms")
                                MtrxDivider()
                                resourceLink(title: "Privacy Policy", url: "https://openmatrix-ai.com/privacy")
                                MtrxDivider()
                                resourceLink(title: "Documentation", url: "https://openmatrix-ai.com/docs")
                            }
                        }
                    }
                }
                .padding(Spacing.contentPadding)
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentPrimary)
                }
            }
        }
    }

    private func resourceLink(title: String, url: String) -> some View {
        Button {
            if let link = URL(string: url) {
                UIApplication.shared.open(link)
            }
        } label: {
            HStack {
                Text(title)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Image(systemName: Symbols.externalLink)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.labelTertiary)
            }
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About Sheet

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var safariURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Logo + version
                    VStack(spacing: Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentPrimary, Color.accentSecondary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 96, height: 96)
                                .shadow(color: Color.accentPrimary.opacity(0.4), radius: 18, y: 8)

                            Text("M")
                                .font(.system(size: 56, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, Spacing.lg)

                        Text("MTRX")
                            .font(.mtrxTitle1)
                            .foregroundStyle(Color.labelPrimary)

                        Text("Version 1.0.0 (build 6)")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    // About paragraph
                    MtrxCard(style: .glass) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("About")
                                .font(.mtrxHeadline)
                                .foregroundStyle(Color.labelPrimary)
                            Text("MTRX is the flagship mobile client for the 0pnMatrx platform — a privacy-first, on-chain operating system for smart contracts, decentralized governance, and AI-assisted finance. Trinity, your private AI agent, runs on-device so your data never leaves your phone.")
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Legal links
                    MtrxCard(style: .standard) {
                        VStack(spacing: 0) {
                            legalLink(title: "Privacy Policy", urlString: "https://openmatrix-ai.com/privacy")
                            MtrxDivider()
                            legalLink(title: "Terms of Service", urlString: "https://openmatrix-ai.com/terms")
                        }
                    }

                    // Credits
                    VStack(spacing: Spacing.sm) {
                        Text("Built by Dardan Rexhepi")
                            .font(.mtrxCalloutBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text("Powered by 0pnMatrx")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.top, Spacing.md)
                }
                .padding(Spacing.contentPadding)
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("About MTRX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentPrimary)
                }
            }
            .sheet(item: $safariURL) { url in
                MtrxSafariView(url: url)
            }
        }
    }

    private func legalLink(title: String, urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) {
                safariURL = url
            }
        } label: {
            HStack {
                Text(title)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Image(systemName: Symbols.externalLink)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.labelTertiary)
            }
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Safari View Wrapper

struct MtrxSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Preview

#Preview("Account") {
    AccountView()
        .preferredColorScheme(.dark)
        .environmentObject(AppState())
        .environmentObject(WalletManager())
}
