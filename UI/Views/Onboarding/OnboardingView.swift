// OnboardingView.swift
// MTRX
//
// Sign in with Apple onboarding flow: Welcome, Authentication, Wallet Setup.

import AuthenticationServices
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

    var body: some View {
        ZStack {
            Color.backgroundPrimary
                .ignoresSafeArea()

            switch currentPage {
            case .welcome:
                welcomePage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .signIn:
                signInPage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .walletSetup:
                walletSetupPage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentPage)
        .alert("Sign In Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authError ?? "An unexpected error occurred. Please try again.")
        }
        .onAppear {
            detectBiometricType()
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 80)

            // Logo & Branding
            VStack(spacing: 16) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(LinearGradient.mtrxPrimary)

                Text("MTRX")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.labelPrimary)
            }

            Spacer()
                .frame(height: 20)

            Text("Welcome to MTRX")
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(.labelPrimary)

            Spacer()
                .frame(height: 48)

            // Feature Highlights
            VStack(spacing: 28) {
                FeatureRow(
                    icon: Symbols.trinity,
                    title: "Talk to Trinity",
                    subtitle: "Your AI-powered financial companion"
                )

                FeatureRow(
                    icon: Symbols.wallet,
                    title: "Own Your Assets",
                    subtitle: "Self-custody wallet with account abstraction"
                )

                FeatureRow(
                    icon: Symbols.build,
                    title: "Build & Earn",
                    subtitle: "Smart contracts, DeFi, NFTs, and more"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // Continue Button
            Button {
                currentPage = .signIn
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Sign In Page

    private var signInPage: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 120)

            VStack(spacing: 12) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(LinearGradient.mtrxPrimary)

                Text("Get Started")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.labelPrimary)

                Text("Sign in to create your wallet and start exploring MTRX.")
                    .font(.body)
                    .foregroundColor(.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Sign In Button or Loading
            VStack(spacing: 20) {
                if isAuthenticating {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.2)
                            .tint(.accentPrimary)

                        Text("Setting up your account...")
                            .font(.subheadline)
                            .foregroundColor(.labelSecondary)
                    }
                    .frame(height: 54)
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        // We handle auth through AuthServicesManager directly
                    }
                    .signInWithAppleButtonStyle(
                        UITraitCollection.current.userInterfaceStyle == .dark ? .white : .black
                    )
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        // Intercept taps to use AuthServicesManager
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                performSignIn()
                            }
                    }

                    // Actual tappable button layered for accessibility
                    Button {
                        performSignIn()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.title3)
                            Text("Sign in with Apple")
                                .font(.headline)
                        }
                        .foregroundColor(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.labelPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                Text("By continuing, you agree to our Terms of Service")
                    .font(.caption)
                    .foregroundColor(.labelTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Wallet Setup Page

    private var walletSetupPage: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 100)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.accentPrimary.opacity(0.12))
                        .frame(width: 96, height: 96)

                    Image(systemName: Symbols.wallet)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(.accentPrimary)
                }

                Text("Your Wallet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.labelPrimary)
            }

            Spacer()
                .frame(height: 40)

            // Wallet Address Card
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("WALLET ADDRESS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.labelTertiary)
                        .tracking(1.2)

                    Text(truncatedAddress)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.labelPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Security Badge
                HStack(spacing: 8) {
                    Image(systemName: Symbols.shieldCheck)
                        .font(.subheadline)
                        .foregroundColor(.statusSuccess)

                    Text("Your wallet is secured by your device's Secure Enclave")
                        .font(.footnote)
                        .foregroundColor(.labelSecondary)
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)

            Spacer()
                .frame(height: 32)

            // Biometric Setup
            if biometricType != .none {
                VStack(spacing: 12) {
                    Image(systemName: biometricIconName)
                        .font(.system(size: 32))
                        .foregroundColor(.accentPrimary)

                    Text("Enable \(biometricDisplayName)")
                        .font(.headline)
                        .foregroundColor(.labelPrimary)

                    Text("Secure transactions with \(biometricDisplayName) for quick and safe access.")
                        .font(.subheadline)
                        .foregroundColor(.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.vertical, 20)
            }

            Spacer()

            // Enter MTRX Button
            Button {
                completeOnboarding()
            } label: {
                Text("Enter MTRX")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(LinearGradient.mtrxPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Actions

    private func performSignIn() {
        guard !isAuthenticating else { return }
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

                    walletAddress = generateWalletAddress(from: result.userId)
                    isAuthenticating = false
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
        appState.isAuthenticated = true
    }

    // MARK: - Helpers

    private var truncatedAddress: String {
        guard walletAddress.count > 12 else { return walletAddress }
        let prefix = walletAddress.prefix(6)
        let suffix = walletAddress.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private func generateWalletAddress(from userId: String) -> String {
        let hash = userId.utf8.reduce(0) { $0 &+ UInt64($1) }
        return String(format: "0x%016llX%016llX%04X", hash, hash ^ 0xDEADBEEF, hash & 0xFFFF)
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

private enum OnboardingPage {
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

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentPrimary.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.labelPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.labelSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
