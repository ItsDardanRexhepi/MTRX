// AccountView.swift
// MTRX - Identity hub, portfolio summary, quick actions, and settings gateway
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - Account View

struct AccountView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var walletManager: WalletManager

    @State private var showSignOutAlert = false
    @State private var appeared = false
    @State private var copiedDID = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sectionGap) {
                    profileCard
                    portfolioSummary
                    quickActionsGrid
                    settingsSection
                    signOutButton
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(.primary))
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
            .navigationDestination(for: AccountNavDestination.self) { destination in
                switch destination {
                case .wallet:
                    WalletView()
                case .staking:
                    StakingPlaceholderView()
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
                    NotificationCenterPlaceholderView()
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
                Button {} label: {
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

                Button {} label: {
                    MtrxListRow(
                        icon: Symbols.help,
                        iconColor: .labelTertiary,
                        title: "Help & Support"
                    )
                }
                .buttonStyle(.plain)

                MtrxDivider().padding(.leading, Spacing.contentPadding + 28 + Spacing.ms)

                Button {} label: {
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

// MARK: - Placeholder Views

struct StakingPlaceholderView: View {
    var body: some View {
        ZStack {
            MtrxGradientBackground(.primary)
            VStack(spacing: Spacing.lg) {
                Image(systemName: Symbols.stake)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.accentPrimary)
                Text("Staking & DeFi")
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)
                Text("Manage your staking positions, liquidity pools, and DeFi strategies.")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .navigationTitle("Staking & DeFi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationCenterPlaceholderView: View {
    var body: some View {
        ZStack {
            MtrxGradientBackground(.primary)
            VStack(spacing: Spacing.lg) {
                Image(systemName: Symbols.notification)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.statusInfo)
                Text("Notifications")
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)
                Text("Transaction alerts, governance updates, and social activity will appear here.")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview("Account") {
    AccountView()
        .preferredColorScheme(.dark)
        .environmentObject(AppState())
        .environmentObject(WalletManager())
}
