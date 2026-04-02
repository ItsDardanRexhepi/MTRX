// SettingsView.swift
// MTRX - User preferences: security, notifications, display, network, about
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI
import LocalAuthentication

// MARK: - ViewModel

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSignOutConfirm = false
    @Published var selectedNetwork: NetworkOption = .mainnet
    @Published var autoLockTimeout: AutoLockTimeout = .fiveMinutes

    enum NetworkOption: String, CaseIterable {
        case mainnet = "Base Mainnet"
        case testnet = "Base Sepolia (Testnet)"

        var chainId: Int {
            switch self {
            case .mainnet: return 8453
            case .testnet: return 84532
            }
        }
    }

    enum AutoLockTimeout: String, CaseIterable {
        case immediate = "Immediately"
        case oneMinute = "1 Minute"
        case fiveMinutes = "5 Minutes"
        case fifteenMinutes = "15 Minutes"
        case thirtyMinutes = "30 Minutes"
        case never = "Never"
    }

    func loadSettings() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: [String: AnyCodableValue] = try await MTRXAPIClient.shared.get(path: "/api/v1/account/settings")
            if case .dictionary(let d) = response["settings"] ?? response["data"] ?? .dictionary(response) {
                if let networkRaw = d["network"]?.stringValue,
                   let network = NetworkOption.allCases.first(where: { $0.rawValue == networkRaw }) {
                    selectedNetwork = network
                }
            }
        } catch {
            // Use defaults on failure
        }
    }

    func saveNetworkSelection() async {
        do {
            let _: [String: AnyCodableValue] = try await MTRXAPIClient.shared.postRaw(
                path: "/api/v1/account/settings",
                body: ["network": selectedNetwork.rawValue, "chain_id": "\(selectedNetwork.chainId)"]
            )
        } catch {
            errorMessage = "Failed to save network preference: \(error.localizedDescription)"
        }
    }

    func signOut() {
        MTRXAPIClient.shared.clearToken()
    }
}

// MARK: - View

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var appState: AppState

    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("biometricsEnabled") private var biometricsEnabled = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("darkMode") private var darkMode = true
    @AppStorage("selectedLanguage") private var selectedLanguage = "English"
    @AppStorage("selectedTheme") private var selectedTheme = "System"

    private let languages = ["English", "Spanish", "French", "German", "Japanese", "Korean", "Chinese"]
    private let themes = ["System", "Light", "Dark"]
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        Form {
            securitySection
            notificationsSection
            displaySection
            networkSection
            aboutSection
            signOutSection
        }
        .navigationTitle("Settings")
        .task {
            await viewModel.loadSettings()
        }
        .alert("Sign Out", isPresented: $viewModel.showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                viewModel.signOut()
                appState.isAuthenticated = false
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        Section("Security") {
            Toggle(isOn: $biometricsEnabled) {
                Label {
                    Text(biometricLabel)
                } icon: {
                    Image(systemName: Symbols.biometric)
                }
            }

            Picker(selection: $viewModel.autoLockTimeout) {
                ForEach(SettingsViewModel.AutoLockTimeout.allCases, id: \.self) { timeout in
                    Text(timeout.rawValue).tag(timeout)
                }
            } label: {
                Label("Auto-Lock", systemImage: Symbols.lock)
            }

            NavigationLink {
                Text("Change your PIN to secure wallet transactions.")
                    .padding()
                    .navigationTitle("Change PIN")
            } label: {
                Label("Change PIN", systemImage: Symbols.key)
            }

            NavigationLink {
                Text("Manage devices with access to this account.")
                    .padding()
                    .navigationTitle("Connected Devices")
            } label: {
                Label("Connected Devices", systemImage: "desktopcomputer")
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle(isOn: $notificationsEnabled) {
                Label("Push Notifications", systemImage: Symbols.notification)
            }

            NavigationLink {
                notificationPreferences
            } label: {
                Label("Notification Preferences", systemImage: Symbols.settings)
            }
        }
    }

    private var notificationPreferences: some View {
        Form {
            Section("Transaction Alerts") {
                Toggle("Incoming transfers", isOn: .constant(true))
                Toggle("Outgoing confirmations", isOn: .constant(true))
                Toggle("Failed transactions", isOn: .constant(true))
            }
            Section("Governance") {
                Toggle("New proposals", isOn: .constant(true))
                Toggle("Voting reminders", isOn: .constant(true))
                Toggle("Proposal results", isOn: .constant(true))
            }
            Section("Social") {
                Toggle("New messages", isOn: .constant(true))
                Toggle("Post interactions", isOn: .constant(true))
            }
            Section("DeFi") {
                Toggle("Position health alerts", isOn: .constant(true))
                Toggle("APY changes", isOn: .constant(false))
            }
        }
        .navigationTitle("Notification Preferences")
    }

    // MARK: - Display

    private var displaySection: some View {
        Section("Display") {
            Picker(selection: $selectedTheme) {
                ForEach(themes, id: \.self) { theme in
                    Text(theme).tag(theme)
                }
            } label: {
                Label("Theme", systemImage: "paintbrush.fill")
            }

            Picker(selection: $selectedLanguage) {
                ForEach(languages, id: \.self) { lang in
                    Text(lang).tag(lang)
                }
            } label: {
                Label("Language", systemImage: Symbols.globe)
            }

            Toggle(isOn: $hapticFeedback) {
                Label("Haptic Feedback", systemImage: "hand.tap.fill")
            }

            NavigationLink {
                Form {
                    Section {
                        Text("USD").tag("USD")
                        Text("ETH").tag("ETH")
                        Text("BTC").tag("BTC")
                    }
                }
                .navigationTitle("Currency Display")
            } label: {
                Label("Currency Display", systemImage: Symbols.fee)
            }
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        Section("Network") {
            Picker(selection: $viewModel.selectedNetwork) {
                ForEach(SettingsViewModel.NetworkOption.allCases, id: \.self) { network in
                    Text(network.rawValue).tag(network)
                }
            } label: {
                Label("Network", systemImage: Symbols.globe)
            }
            .onChange(of: viewModel.selectedNetwork) { _, _ in
                Task { await viewModel.saveNetworkSelection() }
            }

            HStack {
                Label("Chain ID", systemImage: Symbols.link)
                Spacer()
                Text("\(viewModel.selectedNetwork.chainId)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Label("Version", systemImage: Symbols.info)
                Spacer()
                Text("\(appVersion) (\(buildNumber))")
                    .foregroundColor(.secondary)
            }

            HStack {
                Label("Network", systemImage: Symbols.globe)
                Spacer()
                Text(viewModel.selectedNetwork.rawValue)
                    .foregroundColor(.secondary)
            }

            NavigationLink {
                ScrollView {
                    Text("This application uses the following open source libraries:\n\n- SwiftUI (Apple)\n- Combine (Apple)\n- XMTP (XMTP Labs)\n- WalletConnect (WalletConnect)\n\nFull license texts are available in the source repository.")
                        .padding()
                }
                .navigationTitle("Open Source Licenses")
            } label: {
                Label("Open Source Licenses", systemImage: "doc.text")
            }

            NavigationLink {
                Text("https://mtrx.app/privacy")
                    .padding()
                    .navigationTitle("Privacy Policy")
            } label: {
                Label("Privacy Policy", systemImage: Symbols.privacy)
            }

            NavigationLink {
                Text("https://mtrx.app/terms")
                    .padding()
                    .navigationTitle("Terms of Service")
            } label: {
                Label("Terms of Service", systemImage: "doc.plaintext")
            }
        }
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.showSignOutConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    private var biometricLabel: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Biometric Lock"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        @unknown default: return "Biometric Lock"
        }
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
            .environmentObject(AppState())
    }
}
