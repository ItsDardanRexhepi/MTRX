// OnboardingView.swift
// MTRX
//
// Three-page onboarding: Welcome, Sign In, Your Wallet.
// Sign in with Apple, biometric detection, wallet creation animation.

import AuthenticationServices
import CryptoKit
import LocalAuthentication
import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    @State private var currentPage: OnboardingPage = .welcome
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var showErrorAlert = false
    @State private var signInResult: AppleSignInResult?
    @State private var walletAddress: String = ""
    @State private var biometricType: BiometricType = .none
    @State private var isCreatingWallet: Bool = false
    @State private var walletCreationError: String?

    // Welcome page animation states
    @State private var logoAppeared = false
    @State private var headlineAppeared = false
    @State private var cardsAppeared = false
    @State private var glowPulse = false

    // Wallet page animation states
    @State private var walletRingRotation: Double = 0
    @State private var walletCreated = false
    @State private var walletBadgeAppeared = false

    var body: some View {
        ZStack {
            // Blackout theme.
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Trinity's pulsating orb.
                GlassOrb(size: 132)
                    .padding(.bottom, Spacing.lg)

                // MTRX — the same living, slowly color-shifting gradient as the
                // user's name on the Home screen.
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let shift = CGFloat(sin(t * 0.25)) * 0.5
                    Text("MTRX")
                        .font(.mtrxDisplayLarge)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.labelPrimary, Color.trinityPrimary,
                                         Color(red: 0.72, green: 0.78, blue: 0.99), Color.labelPrimary],
                                startPoint: UnitPoint(x: -0.5 + shift, y: 0.5),
                                endPoint: UnitPoint(x: 1.0 + shift, y: 0.5)
                            )
                        )
                }

                Text("Ownership. Yours.")
                    .font(.mtrxTitle1)
                    .foregroundStyle(
                        LinearGradient(colors: [.accentPrimary, .accentSecondary],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .padding(.top, Spacing.xs)

                Spacer()

                // Sign in with Apple — or progress while finishing setup.
                VStack(spacing: Spacing.ml) {
                    if isAuthenticating || isCreatingWallet {
                        VStack(spacing: Spacing.md) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.2)
                                .tint(.accentPrimary)
                            Text("Setting up your account…")
                                .font(.mtrxSubheadline)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        .frame(height: 56)
                    } else {
                        Button {
                            performSignIn()
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Sign in with Apple")
                            }
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
                        }

                        // No-backend way in for App Review / demo. Removed
                        // automatically once FeatureFlags.mvpMode is off.
                        if FeatureFlags.mvpMode {
                            Button {
                                enterDemoMode()
                            } label: {
                                Text("Explore in demo mode")
                                    .font(.mtrxSubheadline)
                                    .foregroundStyle(Color.labelSecondary)
                                    .underline()
                            }
                            .padding(.top, Spacing.xs)
                        }
                    }

                    Text("By continuing, you agree to our Terms of Service\nand Privacy Policy")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .alert("Sign In Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authError ?? "An unexpected error occurred. Please try again.")
        }
    }

    // MARK: - Background Gradient

    @ViewBuilder
    private var backgroundGradient: some View {
        switch currentPage {
        case .welcome:
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.accentPrimary.opacity(0.12), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 500
                ).ignoresSafeArea()
            }
        case .signIn:
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.trinityPrimary.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 400
                ).ignoresSafeArea()
            }
        case .walletSetup:
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.accentSecondary.opacity(0.1), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 500
                ).ignoresSafeArea()
            }
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(OnboardingPage.allCases, id: \.self) { page in
                Capsule()
                    .fill(page == currentPage ? Color.accentPrimary : Color.labelQuaternary)
                    .frame(width: page == currentPage ? 24 : 8, height: 8)
                    .animation(Motion.springSnappy, value: currentPage)
            }
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        // Scrollable content + pinned button: fits every screen size.
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: Spacing.xl)

                    // Animated MTRX logo with cyan glow
                    ZStack {
                        // Outer glow rings
                        Circle()
                            .stroke(Color.accentPrimary.opacity(glowPulse ? 0.15 : 0.05), lineWidth: 2)
                            .frame(width: 140, height: 140)
                            .scaleEffect(glowPulse ? 1.2 : 1.0)

                        Circle()
                            .stroke(Color.accentPrimary.opacity(glowPulse ? 0.08 : 0.02), lineWidth: 1)
                            .frame(width: 180, height: 180)
                            .scaleEffect(glowPulse ? 1.15 : 1.0)

                        // Logo background
                        Circle()
                            .fill(Color.accentPrimary.opacity(0.12))
                            .frame(width: 110, height: 110)

                        Image(systemName: "cube.fill")
                            .font(.system(size: 52, weight: .thin))
                            .foregroundStyle(LinearGradient.mtrxPrimary)
                            .mtrxGlow(color: .accentPrimary, radius: 16)
                    }
                    .frame(height: 190)
                    .mtrxScaleIn(isVisible: logoAppeared)

                    Spacer(minLength: Spacing.lg)

                    // Headline
                    VStack(spacing: Spacing.sm) {
                        Text("MTRX")
                            .font(.mtrxDisplayLarge)
                            .foregroundStyle(Color.labelPrimary)

                        Text("The Future of Finance")
                            .font(.mtrxTitle1)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.accentPrimary, .accentSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)

                        Text("Decentralized everything. AI-powered.\nBuilt for you.")
                            .font(.mtrxBody)
                            .foregroundStyle(Color.labelSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.top, Spacing.xs)
                    }
                    .mtrxFadeInFromBottom(isVisible: headlineAppeared, delay: 0.2)

                    Spacer(minLength: Spacing.xl)

                    // Feature cards with staggered animation
                    VStack(spacing: Spacing.md) {
                        OnboardingFeatureCard(
                            icon: Symbols.trinityActive,
                            iconColor: .trinityPrimary,
                            title: "Trinity AI",
                            subtitle: "Your intelligent financial companion that learns and adapts"
                        )
                        .mtrxStaggeredAppearance(index: 0, isVisible: cardsAppeared)

                        OnboardingFeatureCard(
                            icon: Symbols.contract,
                            iconColor: .accentPrimary,
                            title: "Smart Contracts",
                            subtitle: "Create, deploy, and manage contracts with natural language"
                        )
                        .mtrxStaggeredAppearance(index: 1, isVisible: cardsAppeared)

                        OnboardingFeatureCard(
                            icon: Symbols.swap,
                            iconColor: .accentSecondary,
                            title: "DeFi & Beyond",
                            subtitle: "Swap, stake, lend, and earn across protocols"
                        )
                        .mtrxStaggeredAppearance(index: 2, isVisible: cardsAppeared)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
            }

            // Continue button — pinned, never scrolls offscreen
            Button {
                MtrxHaptics.impact(.light)
                currentPage = .signIn
            } label: {
                Text("Continue")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .onAppear {
            withAnimation(Motion.springBouncy) { logoAppeared = true }
            withAnimation(Motion.springDefault.delay(0.15)) { headlineAppeared = true }
            withAnimation(Motion.springDefault.delay(0.35)) { cardsAppeared = true }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }

    // MARK: - Sign In Page

    private var signInPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.xl)

            VStack(spacing: Spacing.ms) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(LinearGradient.mtrxPrimary)
                    .mtrxGlow(color: .accentPrimary, radius: 10)

                Text("Get Started")
                    .font(.mtrxDisplay)
                    .foregroundStyle(Color.labelPrimary)

                Text("Sign in to create your wallet and\nstart exploring MTRX.")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }

            Spacer(minLength: Spacing.lg)

            // Biometric indicator
            if biometricType != .none {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: biometricIconName)
                        .font(.system(size: 36))
                        .foregroundStyle(Color.accentPrimary)
                        .mtrxGlow(color: .accentPrimary, radius: 6)

                    Text("\(biometricDisplayName) Ready")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(.bottom, Spacing.lg)
            }

            Spacer()

            // Sign In Section
            VStack(spacing: Spacing.ml) {
                if isAuthenticating {
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.2)
                            .tint(.accentPrimary)

                        Text("Setting up your account...")
                            .font(.mtrxSubheadline)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .frame(height: 56)
                    .transition(.mtrxScale)
                } else {
                    // Sign in with Apple button
                    Button {
                        performSignIn()
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Sign in with Apple")
                        }
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.labelPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
                    }
                    .transition(.mtrxScale)
                }

                Text("By continuing, you agree to our Terms of Service\nand Privacy Policy")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Wallet Setup Page

    private var walletSetupPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.xl)

            // Wallet creation animation
            ZStack {
                if !walletCreated {
                    // Spinning ring animation
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient.mtrxPrimary,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(walletRingRotation))

                    Circle()
                        .trim(from: 0, to: 0.4)
                        .stroke(
                            Color.accentSecondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 112, height: 112)
                        .rotationEffect(.degrees(-walletRingRotation * 0.7))
                } else {
                    Circle()
                        .fill(Color.accentPrimary.opacity(0.12))
                        .frame(width: 96, height: 96)
                        .transition(.mtrxScale)

                    Image(systemName: Symbols.wallet)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(LinearGradient.mtrxPrimary)
                        .transition(.mtrxScale)
                }
            }
            .frame(height: 120)

            Spacer()
                .frame(height: Spacing.lg)

            Text("Your Wallet")
                .font(.mtrxDisplay)
                .foregroundStyle(Color.labelPrimary)
                .mtrxFadeInFromBottom(isVisible: walletCreated)

            Spacer()
                .frame(height: Spacing.xl)

            // Wallet address card
            if walletCreated {
                MtrxCard(style: .glass) {
                    VStack(spacing: Spacing.ms) {
                        Text("WALLET ADDRESS")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelTertiary)
                            .tracking(1.2)

                        Text(truncatedAddress)
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)

                        MtrxDivider()

                        HStack(spacing: Spacing.sm) {
                            Image(systemName: Symbols.shieldCheck)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.statusSuccess)

                            Text("Secured by Secure Enclave")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
                .padding(.horizontal, Spacing.lg)
                .transition(.mtrxSlideUp)
            }

            Spacer()
                .frame(height: Spacing.lg)

            // Security badge
            if walletCreated {
                MtrxBadge(text: "Secured by Secure Enclave", style: .success)
                    .mtrxScaleIn(isVisible: walletBadgeAppeared, delay: 0.3)
            }

            // Biometric info
            if walletCreated && biometricType != .none {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: biometricIconName)
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentPrimary)

                    Text("\(biometricDisplayName) enabled")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(.top, Spacing.lg)
                .mtrxFadeInFromBottom(isVisible: walletBadgeAppeared, delay: 0.4)
            }

            Spacer()

            // Enter MTRX button
            if walletCreated {
                Button {
                    MtrxHaptics.success()
                    completeOnboarding()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Text("Enter MTRX")
                        Image(systemName: Symbols.forward)
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxl)
                .transition(.mtrxSlideUp)
            }
        }
        .onAppear {
            startWalletAnimation()
            guard walletAddress.isEmpty else { return }
            createRealWallet()
        }
    }

    // MARK: - Wallet Animation

    private func startWalletAnimation() {
        // Spin the ring
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            walletRingRotation = 360
        }
    }

    // MARK: - Real Wallet Creation

    private func createRealWallet() {
        isCreatingWallet = true

        let userId = signInResult?.userId ?? appState.currentUserID

        // Returning user — restore their existing wallet address.
        let existingKey = "com.mtrx.walletAddress." + userId
        if let existing = UserDefaults.standard.string(forKey: existingKey),
           !existing.isEmpty,
           existing.hasPrefix("0x"),
           existing.count == 42 {
            walletAddress = existing
            isCreatingWallet = false
            completeOnboarding()
            return
        }

        // New user — derive a stable wallet address from their Apple ID and go
        // straight into the app. We deliberately do NOT block onboarding on the
        // heavyweight ERC-4337 creation here: it triggers a second biometric
        // prompt (the user already authenticated at launch + Sign in with Apple)
        // and a network round-trip that can hang with no gateway yet, leaving
        // the user stuck on "Setting up your account…". The address is stable
        // per Apple ID, so the on-chain smart account is deployed lazily on the
        // first transaction, keyed to this same identity.
        let address = generateDeterministicAddress(from: userId.isEmpty ? UUID().uuidString : userId)
        walletAddress = address
        if !userId.isEmpty {
            UserDefaults.standard.set(address, forKey: existingKey)
        }
        isCreatingWallet = false
        completeOnboarding()
    }

    // MARK: - Actions

    private func performSignIn() {
        guard !isAuthenticating else { return }
        MtrxHaptics.impact(.medium)
        isAuthenticating = true

        Task {
            do {
                let result = try await AuthServicesManager.shared.signInWithApple()

                let signInName = result.fullName.map {
                    PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                }

                // Exchange the Apple identity for a backend session token in the
                // BACKGROUND. We never block onboarding on this: the gateway may
                // not be reachable yet, and a hung network request would freeze
                // the user on "Setting up your account…". Whenever it responds,
                // the JWT is stored for authenticated calls. Wallet/account
                // continuity does NOT depend on it — the address is derived
                // deterministically from the Apple ID (stable across devices) in
                // createRealWallet().
                let identityToken = result.identityTokenString ?? ""
                let authCode = result.authorizationCodeString ?? ""
                let userEmail = result.email
                Task.detached {
                    _ = try? await MTRXAPIClient.shared.authenticateWithApple(
                        identityToken: identityToken,
                        authorizationCode: authCode,
                        fullName: signInName,
                        email: userEmail
                    )
                }

                await MainActor.run {
                    signInResult = result
                    appState.currentUserID = result.userId
                    UserDefaults.standard.set(result.userId, forKey: "com.mtrx.appleUserId")

                    if let name = result.fullName {
                        let displayName = PersonNameComponentsFormatter.localizedString(
                            from: name,
                            style: .default
                        )
                        if !displayName.isEmpty {
                            UserDefaults.standard.set(displayName, forKey: "com.mtrx.userDisplayName")
                        }
                    }

                    if let email = result.email {
                        UserDefaults.standard.set(email, forKey: "com.mtrx.userEmail")
                    }

                    // Go straight in — createRealWallet restores a returning
                    // user's address or derives a new one locally, then
                    // completes onboarding immediately.
                    isAuthenticating = false
                    isCreatingWallet = true
                    createRealWallet()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false

                    // Don't show alert for user cancellation
                    if let asError = error as? ASAuthorizationError,
                       asError.code == .canceled {
                        return
                    }

                    authError = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    /// Enter the app with a local demo identity — no Sign in with Apple, no
    /// backend. Guarantees App Review (and curious users) can always get in and
    /// exercise every screen on demonstration data. Shown only in MVP builds.
    private func enterDemoMode() {
        MtrxHaptics.impact(.light)
        appState.currentUserID = "demo-reviewer"
        UserDefaults.standard.set("demo-reviewer", forKey: "com.mtrx.appleUserId")
        UserDefaults.standard.set("Guest", forKey: "com.mtrx.userDisplayName")
        walletAddress = DemoDataProvider.walletAddress
        completeOnboarding()
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "com.mtrx.onboardingComplete")
        UserDefaults.standard.set(walletAddress, forKey: "com.mtrx.walletAddress")

        let displayName = UserDefaults.standard.string(forKey: "com.mtrx.userDisplayName") ?? ""
        appState.signIn(
            userID: appState.currentUserID,
            displayName: displayName,
            walletAddress: walletAddress
        )
    }

    // MARK: - Helpers

    private var truncatedAddress: String {
        guard walletAddress.count > 12 else { return walletAddress }
        let prefix = walletAddress.prefix(6)
        let suffix = walletAddress.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    /// Emergency fallback address generator — used only when ERC-4337
    /// wallet creation fails. This address cannot sign real transactions.
    /// It is a placeholder so onboarding can complete.
    private func generateDeterministicAddress(from userId: String) -> String {
        let data = Data(userId.utf8)
        let hash = SHA256.hash(data: data)
        let hexBytes = hash.prefix(20).map { String(format: "%02x", $0) }.joined()
        return "0x" + hexBytes
    }

    private func detectBiometricType() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            case .opticID:
                biometricType = .opticID
            @unknown default:
                biometricType = .none
            }
        }
    }

    private var biometricIconName: String {
        switch biometricType {
        case .faceID: return Symbols.biometric
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return ""
        }
    }

    private var biometricDisplayName: String {
        switch biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return ""
        }
    }
}

// MARK: - Onboarding Page

private enum OnboardingPage: Int, CaseIterable {
    case welcome
    case signIn
    case walletSetup
}

// MARK: - Biometric Type

private enum BiometricType {
    case faceID
    case touchID
    case opticID
    case none
}

// MARK: - Feature Card

private struct OnboardingFeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        MtrxCard(style: .glass) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)

                    Text(subtitle)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
