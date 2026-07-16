// AccountView.swift
// MTRX - Identity hub, portfolio summary, quick actions, and settings gateway
// Copyright 2026 OPN MATRX. All rights reserved.

import PhotosUI
import SwiftUI
import SafariServices


// MARK: - App Version

/// Single source of truth for the app version, shown app-wide (Account → About
/// row, Settings → About row, and the About sheet) — all read straight from the
/// bundle so they can't drift or go stale on a build bump. (They used to be
/// hardcoded — Account read "2.4.0", Settings read "2.4.0", the sheet read
/// "1.0.0 (build 6)", while the bundle truth at the time was 1.0.0 (187).)
/// Internal, not private, so SettingsView shares the same source.
enum AppVersionInfo {
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var short: String { info["CFBundleShortVersionString"] as? String ?? "—" }
    static var build: String { info["CFBundleVersion"] as? String ?? "—" }
    /// Compact "1.0.0 (187)" — for a trailing row value (Settings).
    static var shortWithBuild: String { "\(short) (\(build))" }
    /// List-row subtitle — build-inclusive so the build is confirmable WITHOUT
    /// opening the sheet, e.g. "Version 1.0.0 (187)".
    static var rowSubtitle: String { "Version \(shortWithBuild)" }
    /// Full form for the About sheet, e.g. "Version 1.0.0 (build 187)".
    static var fullDisplay: String { "Version \(short) (build \(build))" }
}


// MARK: - Account Avatar

/// The Account profile picture: a chosen photo, the Social photo, or
/// the default monogram in a user-picked color. Photo persists on
/// disk; the monogram color in UserDefaults.
@MainActor
final class AccountAvatar: ObservableObject {

    static let shared = AccountAvatar()

    @Published var image: UIImage?
    @AppStorage("com.mtrx.account.monogramHex") var monogramHex: String = ""

    static let monogramPresets: [(name: String, color: Color, hex: String)] = [
        ("Aqua", Color(red: 0.23, green: 0.92, blue: 0.96), "3BEBF5"),
        ("Leaf", Color(red: 0.30, green: 0.87, blue: 0.46), "4CDE76"),
        ("Violet", Color(red: 0.62, green: 0.40, blue: 0.96), "9E66F5"),
        ("Rose", Color(red: 0.95, green: 0.36, blue: 0.42), "F25C6B"),
        ("Amber", Color(red: 0.98, green: 0.65, blue: 0.15), "FAA626"),
        ("Sky", Color(red: 0.25, green: 0.55, blue: 0.98), "408CFA"),
    ]

    private var fileURL: URL {
        SocialIdentity.mediaDirectory.appendingPathComponent("account-avatar.jpg")
    }

    private init() {
        if let data = try? Data(contentsOf: fileURL) {
            image = UIImage(data: data)
        }
    }

    func set(_ newImage: UIImage) {
        image = newImage
        if let data = newImage.jpegData(compressionQuality: 0.85) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func useSocialPhoto() {
        if let social = SocialIdentity.shared.avatarImage {
            set(social)
        }
    }

    func clearPhoto() {
        image = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    var monogramColor: Color {
        Self.monogramPresets.first(where: { $0.hex == monogramHex })?.color ?? .accentPrimary
    }
}

// MARK: - Account View

struct AccountView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var walletManager: WalletManager

    @State private var presentedDestination: AccountNavDestination?
    @State private var showSignOutAlert = false
    @ObservedObject private var accountAvatar = AccountAvatar.shared
    @State private var showAvatarOptions = false
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var showMonogramColors = false
    @State private var showAvatarPicker = false
    @State private var appeared = false
    @State private var copiedDID = false
    @State private var showEditProfile = false
    @State private var showHelp = false
    @State private var showAbout = false
    @State private var showWorkspaceEditor = false
    /// The four workspace tiles the user has chosen, persisted. Editable
    /// just like the Home quick actions.
    @AppStorage("com.mtrx.account.workspace") private var workspaceRaw =
        "governance,messaging,rewards,settings"

    private var workspaceOptions: [WorkspaceOption] {
        let chosen = workspaceRaw.split(separator: ",").compactMap { WorkspaceOption(rawValue: String($0)) }
        let base = chosen.isEmpty ? [.governance, .messaging, .rewards, .settings] : chosen
        return base.filter { !FeatureFlags.mvpMode || !$0.isRegulated }
    }

    var body: some View {
        NavigationStack {
            // A fixed, non-scrolling page: the flexible gap ABOVE Sign Out
            // fills whatever height the screen has, so Sign Out settles just
            // above the dock. The whole page is then laid out at the reference
            // iPhone's proportions and scaled to THIS device (see Home), so
            // Account looks identical on every iPhone — nothing clipped, nothing
            // off-screen, and never a scroll.
            VStack(spacing: Spacing.md) {
                profileCard
                portfolioSummary
                workspaceSection
                Spacer(minLength: 0)
                // Nudged ~0.25% below baseline; nothing else moves.
                signOutButton
                    .offset(y: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)
            .fitToReferenceScreen()
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(item: $presentedDestination) { destination in
                switch destination {
                case .wallet:
                    // A sheet doesn't inherit the presenter's NavigationStack —
                    // wrap so links inside the wallet (e.g. My properties) push.
                    NavigationStack { AccountWalletView() }
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
        .sheet(isPresented: $showWorkspaceEditor) {
            WorkspaceEditSheet(workspaceRaw: $workspaceRaw)
        }
        .onAppear {
            withAnimation(Motion.springDefault.delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        // One compact, fully-tappable header: tap anywhere to edit, tap the
        // photo for photo options. No separate edit button. Settings lives in
        // the workspace grid below, so it isn't duplicated here.
        MtrxCard(style: .glass) {
            HStack(spacing: Spacing.md) {
                avatarButton

                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.displayName.isEmpty ? "MTRX User" : appState.displayName)
                        .font(.mtrxTitle3)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    HStack(spacing: Spacing.xs) {
                        Text(truncatedDID)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Button {
                            UIPasteboard.general.string = fullDID
                            withAnimation(Motion.springSnappy) { copiedDID = true }
                            MtrxHaptics.success()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { copiedDID = false }
                            }
                        } label: {
                            Image(systemName: copiedDID ? Symbols.complete : Symbols.copy)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(copiedDID ? Color.statusSuccess : Color.accentPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy decentralized identifier")
                        .accessibilityValue(copiedDID ? "Copied" : "")
                    }

                    Text("Member since \(memberSinceString)")
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.labelTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                MtrxHaptics.impact(.light)
                showEditProfile = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens edit profile")
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0)
    }

    /// The avatar — tap it for photo options (Social photo, library, camera,
    /// monogram color). Lives inside the left profile tile.
    private var avatarButton: some View {
        Button {
            MtrxHaptics.impact(.light)
            showAvatarOptions = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [accountAvatar.monogramColor, .accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: Spacing.Size.avatarLarge + 5, height: Spacing.Size.avatarLarge + 5)

                    if let photo = accountAvatar.image {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: Spacing.Size.avatarLarge, height: Spacing.Size.avatarLarge)
                            .clipShape(Circle())
                    } else {
                        MtrxAvatar(
                            text: appState.displayName.isEmpty ? "M" : String(appState.displayName.prefix(2)),
                            color: accountAvatar.monogramColor,
                            size: Spacing.Size.avatarLarge
                        )
                    }
                }

                Image(systemName: "camera.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentPrimary)
                    .background(Circle().fill(Color.black))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile photo")
        .accessibilityHint("Change photo")
        .confirmationDialog("Profile Photo", isPresented: $showAvatarOptions, titleVisibility: .visible) {
            if SocialIdentity.shared.avatarImage != nil {
                Button("Use my Social photo") {
                    accountAvatar.useSocialPhoto()
                    MtrxHaptics.success()
                }
            }
            Button("Choose a different photo") { showAvatarPicker = true }
            Button("Change monogram color") { showMonogramColors = true }
            if accountAvatar.image != nil {
                Button("Remove photo", role: .destructive) {
                    accountAvatar.clearPhoto()
                    MtrxHaptics.impact(.light)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showAvatarPicker, selection: $avatarPickerItem, matching: .images)
        .onChange(of: avatarPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    accountAvatar.set(image)
                    MtrxHaptics.success()
                }
                avatarPickerItem = nil
            }
        }
        .sheet(isPresented: $showMonogramColors) {
            VStack(spacing: Spacing.lg) {
                Text("Monogram color")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)

                HStack(spacing: Spacing.md) {
                    ForEach(AccountAvatar.monogramPresets, id: \.hex) { preset in
                        Button {
                            accountAvatar.monogramHex = preset.hex
                            accountAvatar.clearPhoto()
                            MtrxHaptics.selection()
                            showMonogramColors = false
                        } label: {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle().stroke(.white.opacity(0.9), lineWidth: 2.5)
                                        .opacity(accountAvatar.monogramHex == preset.hex ? 1 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Your initials wear this color when no photo is set.")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }
            .padding(Spacing.xl)
            .presentationDetents([.height(220)])
            .presentationBackground(.thinMaterial)
        }
    }

    // MARK: - Portfolio Summary

    private var portfolioSummary: some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.xs) {
                HStack {
                    Text("Portfolio Value")
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                }

                HStack(alignment: .firstTextBaseline) {
                    MtrxAnimatedValue(
                        value: walletManager.totalPortfolioValue,
                        font: .system(size: 24, weight: .heavy, design: .rounded)
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(VoiceOverSupport.portfolioLabel(
                    value: walletManager.totalPortfolioValue.formatted(.currency(code: "USD")),
                    change: String(format: "%.2f%%", walletManager.portfolioChange24h),
                    isPositive: walletManager.portfolioChange24h >= 0
                ))

                Button { presentedDestination = AccountNavDestination.wallet } label: {
                    HStack {
                        Text("View Wallet")
                            .font(.mtrxCaptionBold)
                        Image(systemName: Symbols.forward)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.accentPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.accentPrimary.opacity(0.12))
                    .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.sm)
                }
                .buttonStyle(.plain)

                // Identity lives here too — verification, credentials,
                // reputation, and access control, one tap from the top.
                HStack(spacing: Spacing.sm) {
                    portfolioChip("person.text.rectangle", "Verify", .statusInfo, .kyc)
                    portfolioChip("seal.fill", "Credentials", .statusSuccess, .credentials)
                    portfolioChip("star.fill", "Reputation", .accentTertiary, .reputation)
                    portfolioChip("key.fill", "Access", .accentPrimary, .accessControl)
                }
            }
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0.05)
    }

    private func portfolioChip(_ icon: String, _ label: String, _ color: Color, _ destination: AccountNavDestination) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            presentedDestination = destination
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.13))
                    .clipShape(Circle())
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chunked Spaces
    //
    // Reorganized for how minds scan: small named groups of 3-4 (never
    // an 11-row wall), grids for choices, rows only for low-stakes
    // app plumbing. Identity → money → identity → workspace → app.

    private func spaceGrid<Tiles: View>(_ title: String, delay: Double, @ViewBuilder tiles: () -> Tiles) -> some View {
        VStack(spacing: Spacing.sm) {
            MtrxSectionHeader(title: title)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.sm),
                    GridItem(.flexible(), spacing: Spacing.sm)
                ],
                spacing: Spacing.sm
            ) {
                tiles()
            }
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: delay)
    }

    private var workspaceSection: some View {
        // A 2×2 grid the user curates — pick any four from the workspace
        // options, just like Home's quick actions. Tap the header chevron
        // (or long-press a tile) to customize.
        let tiles = workspaceOptions
        return VStack(spacing: Spacing.sm) {
            Button {
                MtrxHaptics.impact(.light)
                showWorkspaceEditor = true
            } label: {
                HStack(spacing: 6) {
                    MtrxSectionHeader(title: "Your workspace")
                    Image(systemName: "chevron.right.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                        .accessibilityHidden(true)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: Spacing.sm) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: Spacing.sm) {
                        ForEach(0..<2, id: \.self) { col in
                            let index = row * 2 + col
                            if index < tiles.count {
                                let opt = tiles[index]
                                QuickActionCard(icon: opt.icon, label: opt.title, color: opt.color,
                                                destination: opt.destination,
                                                onOpen: { presentedDestination = $0 },
                                                useLoopGlyph: opt == .messaging)
                                    .onLongPressGesture {
                                        MtrxHaptics.impact(.medium)
                                        showWorkspaceEditor = true
                                    }
                            } else {
                                Button { showWorkspaceEditor = true } label: {
                                    MtrxCard(style: .standard) {
                                        VStack(spacing: Spacing.sm) {
                                            Image(systemName: "plus")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color.accentPrimary)
                                                .frame(width: 46, height: 46)
                                            Text("Add")
                                                .font(.mtrxCalloutBold)
                                                .foregroundStyle(Color.labelSecondary)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0.09)
    }

    /// One home for everything app-level: settings (notifications live
    /// inside), privacy, subscription, help, and about.
    private var appSection: some View {
        VStack(spacing: 0) {
            MtrxSectionHeader(title: "App & Support")
                .padding(.bottom, Spacing.sm)

            VStack(spacing: 0) {
                identityRow(destination: .settings, icon: Symbols.settings, iconColor: .labelSecondary, title: "Settings")
                identityDivider()
                identityRow(destination: .privacy, icon: "lock.fill", iconColor: .statusWarning, title: "Privacy & Security")
                identityDivider()
                identityRow(destination: .subscription, icon: "crown.fill", iconColor: .accentSecondary, title: "Subscription")
                identityDivider()

                Button {
                    showHelp = true
                    MtrxHaptics.impact(.light)
                } label: {
                    MtrxListRow(icon: Symbols.help, iconColor: .labelTertiary, title: "Help & Support")
                }
                .buttonStyle(.plain)
                identityDivider()

                Button {
                    showAbout = true
                    MtrxHaptics.impact(.light)
                } label: {
                    MtrxListRow(icon: Symbols.info, iconColor: .labelTertiary, title: "About MTRX", subtitle: AppVersionInfo.rowSubtitle)
                }
                .buttonStyle(.plain)
            }
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
        }
        .mtrxFadeInFromBottom(isVisible: appeared, delay: 0.11)
    }

    private func identityRow(destination: AccountNavDestination, icon: String, iconColor: Color, title: String) -> some View {
        Button { presentedDestination = destination } label: {
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
        // Enlarged 1% per spec; the label stays centered within the button.
        .scaleEffect(1.01)
        // Nudged 0.1% of screen height down per spec.
        .offset(y: 0.85)
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

enum AccountNavDestination: Hashable, Identifiable {
    var id: Self { self }

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

// MARK: - Workspace Options (editable)

/// Everything that can live in one of the four workspace quadrants. The
/// user picks any four; the choice persists.
enum WorkspaceOption: String, CaseIterable, Identifiable {
    case governance, messaging, rewards, settings
    case wallet, staking, reputation, credentials
    case verify, access, notifications, treasury

    var id: String { rawValue }

    /// Hidden in MVP mode — regulated financial surface.
    var isRegulated: Bool { self == .staking }

    var title: String {
        switch self {
        case .governance: return "Governance"
        case .messaging: return "Messaging"
        case .rewards: return "Rewards"
        case .settings: return "Settings"
        case .wallet: return "Wallet"
        case .staking: return "Staking"
        case .reputation: return "Reputation"
        case .credentials: return "Credentials"
        case .verify: return "Verify"
        case .access: return "Access"
        case .notifications: return "Notifications"
        case .treasury: return "Treasury"
        }
    }

    var icon: String {
        switch self {
        case .governance: return Symbols.dao
        case .messaging: return Symbols.message
        case .rewards: return "gift.fill"
        case .settings: return Symbols.settings
        case .wallet: return "wallet.pass.fill"
        case .staking: return "lock.shield.fill"
        case .reputation: return "star.fill"
        case .credentials: return "seal.fill"
        case .verify: return "person.text.rectangle.fill"
        case .access: return "key.fill"
        case .notifications: return "bell.fill"
        case .treasury: return "building.columns.fill"
        }
    }

    var color: Color {
        switch self {
        case .governance: return .accentTertiary
        case .messaging: return .statusInfo
        case .rewards: return .accentSecondary
        case .settings: return .labelSecondary
        case .wallet: return .accentPrimary
        case .staking: return .statusSuccess
        case .reputation: return .accentSecondary
        case .credentials: return .statusSuccess
        case .verify: return .statusInfo
        case .access: return .accentPrimary
        case .notifications: return .statusWarning
        case .treasury: return .accentTertiary
        }
    }

    var destination: AccountNavDestination {
        switch self {
        case .governance: return .governance
        case .messaging: return .messaging
        case .rewards: return .loyalty
        case .settings: return .settings
        case .wallet: return .wallet
        case .staking: return .staking
        case .reputation: return .reputation
        case .credentials: return .credentials
        case .verify: return .kyc
        case .access: return .accessControl
        case .notifications: return .notifications
        case .treasury: return .treasury
        }
    }
}

// MARK: - Workspace Editor

/// Pick exactly which four tiles fill the workspace grid. Selecting is
/// capped at four; tap a selected tile to free a slot.
struct WorkspaceEditSheet: View {
    @Binding var workspaceRaw: String
    @Environment(\.dismiss) private var dismiss

    private var chosen: [WorkspaceOption] {
        workspaceRaw.split(separator: ",").compactMap { WorkspaceOption(rawValue: String($0)) }
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Pick up to four tiles for your workspace. Tap a selected one to remove it.")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .padding(.horizontal, Spacing.contentPadding)

                    LazyVGrid(columns: columns, spacing: Spacing.sm) {
                        ForEach(WorkspaceOption.allCases.filter { !FeatureFlags.mvpMode || !$0.isRegulated }) { option in
                            let isOn = chosen.contains(option)
                            let rank = chosen.firstIndex(of: option).map { $0 + 1 }
                            Button { toggle(option) } label: {
                                VStack(spacing: Spacing.sm) {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(option.color)
                                        .frame(width: 44, height: 44)
                                        .background(option.color.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                                    Text(option.title)
                                        .font(.mtrxCalloutBold)
                                        .foregroundStyle(Color.labelPrimary)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .background(Color.surfaceCard.opacity(isOn ? 0.9 : 0.4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                                        .stroke(isOn ? option.color.opacity(0.6) : Color.white.opacity(0.06), lineWidth: isOn ? 1.5 : 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    if let rank {
                                        Text("\(rank)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Circle().fill(option.color))
                                            .padding(6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                }
                .padding(.vertical, Spacing.md)
            }
            .background(Color.black.opacity(0.18).ignoresSafeArea())
            .navigationTitle("Edit workspace")
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackground(.ultraThinMaterial)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentPrimary)
                }
            }
        }
    }

    private func toggle(_ option: WorkspaceOption) {
        MtrxHaptics.impact(.light)
        var list = chosen
        if let i = list.firstIndex(of: option) {
            list.remove(at: i)
        } else if list.count < 4 {
            list.append(option)
        } else {
            // Full — replace the last slot.
            list[3] = option
        }
        workspaceRaw = list.map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - Quick Action Card

struct QuickActionCard: View {
    let icon: String
    let label: String
    let color: Color
    let destination: AccountNavDestination
    let onOpen: (AccountNavDestination) -> Void
    var useLoopGlyph: Bool = false

    var body: some View {
        Button { onOpen(destination) } label: {
            MtrxCard(style: .standard) {
                VStack(spacing: Spacing.sm) {
                    ZStack {
                        if useLoopGlyph {
                            LoopArrowGlyph(color: color).padding(10)
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(color)
                        }
                    }
                        .frame(width: 46, height: 46)
                        .background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                    Text(label)
                        .font(.mtrxCalloutBold)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                // A taller fixed tile — sized so the 2×2 workspace grid fills the
                // space down toward Sign Out instead of leaving a dead gap. Still a
                // fixed height (not greedy): the flexible Spacer above Sign Out absorbs
                // any residual and fitToReferenceScreen keeps the page from scrolling.
                .frame(maxWidth: .infinity)
                .frame(height: 122)
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
                                    .minimumScaleFactor(0.75)
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
            .background(Color.black.opacity(0.18).ignoresSafeArea())
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackground(.ultraThinMaterial)
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
            // Sized to fit on a single screen — no scrolling. The credits anchor to
            // the bottom; everything above is compacted to leave headroom.
            VStack(spacing: Spacing.md) {
                // Logo + version
                VStack(spacing: Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentPrimary, Color.accentSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.accentPrimary.opacity(0.4), radius: 14, y: 6)

                        Text("M")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, Spacing.xs)

                    Text("MTRX")
                        .font(.mtrxTitle2)
                        .foregroundStyle(Color.labelPrimary)

                    Text(AppVersionInfo.fullDisplay)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                // About paragraph
                MtrxCard(style: .glass) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("About")
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)
                        Text("MTRX is the flagship mobile client for the 0pnMatrx platform — a privacy-first, on-chain operating system for smart contracts, decentralized governance, and AI-assisted finance. Trinity, your private AI agent, runs on-device so your data never leaves your phone.")
                            .font(.mtrxSubheadline)
                            .foregroundStyle(Color.labelSecondary)
                            .lineSpacing(2)
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

                Spacer(minLength: Spacing.sm)

                // Credits
                VStack(spacing: Spacing.xs) {
                    Text("Built by Dardan Rexhepi")
                        .font(.mtrxCalloutBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text("Powered by 0pnMatrx")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(Spacing.contentPadding)
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
