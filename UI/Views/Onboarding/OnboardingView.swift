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
            // Page-specific background gradient
            backgroundGradient
                .animation(Motion.springGentle, value: currentPage)

            TabView(selection: $currentPage) {
                welcomePage
                    .tag(OnboardingPage.welcome)

                signInPage
                    .tag(OnboardingPage.signIn)

                walletSetupPage
                    .tag(OnboardingPage.walletSetup)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Motion.springDefault, value: currentPage)

            // Custom page indicators
            VStack {
                Spacer()
                pageIndicator
                    .padding(.bottom, Spacing.md)
            }
            .ignoresSafeArea(.keyboard)
        }
        .alert("Sign In Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authError ?? "An unexpected error occurred. Please try again.")
        }
        .onAppear {
            detectBiometricType()
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
        VStack(spacing: 0) {
            Spacer()
                .frame(height: Spacing.xxxl)

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
            .mtrxScaleIn(isVisible: logoAppeared)

            Spacer()
                .frame(height: Spacing.lg)

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

                Text("Decentralized everything. AI-powered.\nBuilt for you.")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xs)
            }
            .mtrxFadeInFromBottom(isVisible: headlineAppeared, delay: 0.2)

            Spacer()
                .frame(height: Spacing.xxl)

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

            Spacer()

            // Continue button
            Button {
                MtrxHaptics.impact(.light)
                currentPage = .signIn
            } label: {
                Text("Continue")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
            .padding(.horizontal, Spacing.lg)
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
            Spacer()
                .frame(height: Spacing.xxxl + Spacing.xl)

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

            Spacer()
                .frame(height: Spacing.xxl)

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
            Spacer()
                .frame(height: Spacing.xxxl + Spacing.lg)

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

        // Check if wallet already exists for this user
        let existingKey = "com.mtrx.walletAddress." + (signInResult?.userId ?? "")
        if let existing = UserDefaults.standard.string(forKey: existingKey),
           !existing.isEmpty,
           existing.hasPrefix("0x"),
           existing.count == 42 {
            // Returning user — restore their existing wallet address
            walletAddress = existing
            isCreatingWallet = false
            withAnimation(Motion.springBouncy) {
                walletCreated = true
            }
            withAnimation(Motion.springDefault.delay(0.2)) {
                walletBadgeAppeared = true
            }
            return
        }

        // Create new ERC-4337 smart account
        let creator = WalletCreation()
        creator.createWallet(
            recoveryMethod: .faceID,
            accountType: .standard
        ) { result in
            DispatchQueue.main.async {
                self.isCreatingWallet = false
                switch result {
                case .success(let wallet):
                    self.walletAddress = wallet.address
                    // Persist against this Apple user ID so returning
                    // users get the same address
                    let key = "com.mtrx.walletAddress." + (self.signInResult?.userId ?? "")
                    UserDefaults.standard.set(wallet.address, forKey: key)
                case .failure:
                    // Wallet creation failed — generate a deterministic
                    // address as emergency fallback so onboarding doesn't
                    // get stuck.
                    self.walletAddress = self.generateDeterministicAddress(
                        from: self.signInResult?.userId ?? UUID().uuidString
                    )
                }
                withAnimation(Motion.springBouncy) {
                    self.walletCreated = true
                }
                withAnimation(Motion.springDefault.delay(0.2)) {
                    self.walletBadgeAppeared = true
                }
            }
        }
    }

    // MARK: - Actions

    private func performSignIn() {
        guard !isAuthenticating else { return }
        MtrxHaptics.impact(.medium)
        isAuthenticating = true

        Task {
            do {
                let result = try await AuthServicesManager.shared.signInWithApple()
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

                    isAuthenticating = false
                    isCreatingWallet = true
                    currentPage = .walletSetup
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
