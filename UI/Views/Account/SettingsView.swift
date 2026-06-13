// SettingsView.swift
// MTRX
//
// Full settings screen: general, network, Trinity AI, security, advanced, about.
// Uses native List(.insetGrouped) for premium iOS settings feel.

import SwiftUI
import LocalAuthentication

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    // MARK: - General
    @AppStorage("mtrx_currency") private var selectedCurrency = "USD"
    @AppStorage("mtrx_theme") private var selectedTheme = "System"
    @AppStorage("mtrx_haptics") private var hapticFeedback = true

    // MARK: - Network
    @AppStorage("mtrx_chain") private var defaultChain = "Base"
    @AppStorage("mtrx_gas") private var gasStrategy = "Standard"

    // MARK: - Trinity AI
    @AppStorage("mtrx_trinity_proactive") private var proactiveAlerts = true
    @AppStorage("mtrx_trinity_style") private var communicationStyle = "Concise"
    @AppStorage("mtrx_trinity_expertise") private var expertiseLevel = "Intermediate"

    // MARK: - Security
    @AppStorage("mtrx_biometric") private var biometricLock = true
    @AppStorage("mtrx_autolock") private var autoLockInterval = "5 min"
    @AppStorage("mtrx_tx_signing") private var transactionSigning = true

    // MARK: - Alerts & Toast
    @State private var showClearCacheConfirm = false
    @State private var showResetPrefsConfirm = false
    @State private var showCacheCleared = false

    // MARK: - Static Data
    private let currencies = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "BTC", "ETH"]
    private let themes = ["System", "Light", "Dark"]
    private let chains = ["Base", "Ethereum", "Polygon", "Arbitrum", "Optimism"]
    private let gasStrategies = ["Slow", "Standard", "Fast"]
    private let autoLockOptions = ["Immediately", "1 min", "5 min", "15 min", "Never"]
    private let commStyles = ["Concise", "Detailed", "Conversational", "Technical"]
    private let expertiseLevels = ["Beginner", "Intermediate", "Advanced", "Expert"]

    // MARK: - Computed

    private var preferredScheme: ColorScheme? {
        switch selectedTheme {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }

    // MARK: - Notifications (lives inside Settings now)

    @State private var showNotificationCenter = false

    private var notificationsSection: some View {
        Section("Notifications") {
            Button {
                MtrxHaptics.impact(.light)
                showNotificationCenter = true
            } label: {
                HStack {
                    Label("Notification Center", systemImage: "bell.badge.fill")
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Image(systemName: Symbols.forward)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .sheet(isPresented: $showNotificationCenter) {
                NotificationCenterView()
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    generalSection
                    notificationsSection
                    networkSection
                    trinitySection
                    securitySection
                    advancedSection
                    aboutSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.backgroundGrouped.ignoresSafeArea())

                // Toast overlay
                if showCacheCleared {
                    MtrxToast(message: "Cache cleared successfully", icon: Symbols.complete, style: .success)
                        .transition(.mtrxSlideUp)
                        .padding(.bottom, Spacing.xl)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(Motion.springDefault) {
                                    showCacheCleared = false
                                }
                            }
                        }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(preferredScheme)

            // MARK: - Alerts
            .alert("Clear Cache", isPresented: $showClearCacheConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    MtrxHaptics.success()
                    withAnimation(Motion.springDefault) {
                        showCacheCleared = true
                    }
                }
            } message: {
                Text("This will remove all cached images, API responses, and temporary files. Your account data will not be affected.")
            }
            .alert("Reset Preferences", isPresented: $showResetPrefsConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset All", role: .destructive) {
                    resetAllPreferences()
                    MtrxHaptics.warning()
                }
            } message: {
                Text("All settings will return to their default values. This action cannot be undone.")
            }
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        Section {
            // Currency — navigation link to picker
            NavigationLink {
                CurrencyPickerView(selection: $selectedCurrency, currencies: currencies)
            } label: {
                settingsRow(
                    icon: "dollarsign.circle.fill",
                    iconColor: .statusSuccess,
                    title: "Currency",
                    value: selectedCurrency
                )
            }

            // Theme — inline picker
            Picker(selection: $selectedTheme) {
                ForEach(themes, id: \.self) { theme in
                    Text(theme).tag(theme)
                }
            } label: {
                Label {
                    Text("Theme")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: "paintbrush.fill", color: .accentTertiary)
                }
            }
            .onChange(of: selectedTheme) { _, _ in triggerHaptic() }

            // Haptic Feedback — toggle
            Toggle(isOn: $hapticFeedback) {
                Label {
                    Text("Haptic Feedback")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: "hand.tap.fill", color: .statusInfo)
                }
            }
            .tint(Color.accentPrimary)
            .onChange(of: hapticFeedback) { _, newValue in
                if newValue { MtrxHaptics.impact(.light) }
            }
        } header: {
            Text("General")
        } footer: {
            Text("Theme changes apply immediately. Currency affects how portfolio values are displayed.")
        }
    }

    // MARK: - Network Section

    private var networkSection: some View {
        Section {
            // Default Chain — navigation link to picker
            NavigationLink {
                ChainPickerView(selection: $defaultChain, chains: chains)
            } label: {
                settingsRow(
                    icon: Symbols.link,
                    iconColor: .accentPrimary,
                    title: "Default Chain",
                    value: defaultChain
                )
            }

            // Gas Strategy — inline picker
            Picker(selection: $gasStrategy) {
                ForEach(gasStrategies, id: \.self) { strategy in
                    Text(strategy).tag(strategy)
                }
            } label: {
                Label {
                    Text("Gas Strategy")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: Symbols.gas, color: .accentTertiary)
                }
            }
            .onChange(of: gasStrategy) { _, _ in triggerHaptic() }
        } header: {
            Text("Network")
        } footer: {
            Text("Gas strategy controls transaction speed and cost. The default chain is used for new operations.")
        }
    }

    // MARK: - Trinity AI Section

    private var trinitySection: some View {
        Section {
            // Proactive Alerts — toggle
            Toggle(isOn: $proactiveAlerts) {
                Label {
                    Text("Proactive Alerts")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: Symbols.notificationBadge, color: .trinityPrimary)
                }
            }
            .tint(Color.accentPrimary)
            .onChange(of: proactiveAlerts) { _, _ in triggerHaptic() }

            // Communication Style — navigation link to picker
            NavigationLink {
                StylePickerView(
                    title: "Communication Style",
                    selection: $communicationStyle,
                    options: commStyles,
                    descriptions: [
                        "Concise": "Short, direct answers with minimal explanation.",
                        "Detailed": "Thorough responses with context and reasoning.",
                        "Conversational": "Friendly, natural dialogue with follow-up suggestions.",
                        "Technical": "Precise, data-heavy responses with on-chain references."
                    ]
                )
            } label: {
                settingsRow(
                    icon: Symbols.textBubble,
                    iconColor: .trinitySecondary,
                    title: "Communication Style",
                    value: communicationStyle
                )
            }

            // Expertise Level — navigation link to picker
            NavigationLink {
                StylePickerView(
                    title: "Expertise Level",
                    selection: $expertiseLevel,
                    options: expertiseLevels,
                    descriptions: [
                        "Beginner": "Simplified terms, step-by-step guidance, glossary links.",
                        "Intermediate": "Standard explanations with key details.",
                        "Advanced": "Assumes familiarity with DeFi concepts and protocols.",
                        "Expert": "Raw data, minimal hand-holding, power-user defaults."
                    ]
                )
            } label: {
                settingsRow(
                    icon: Symbols.sparkle,
                    iconColor: .trinityPrimary,
                    title: "Expertise Level",
                    value: expertiseLevel
                )
            }
        } header: {
            Text("Trinity AI")
        } footer: {
            Text("Configure how Trinity communicates with you. Proactive alerts notify you of important on-chain events.")
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section {
            // Biometric Lock — toggle with dynamic label
            Toggle(isOn: $biometricLock) {
                Label {
                    Text(biometricLabel)
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: biometricIcon, color: .statusInfo)
                }
            }
            .tint(Color.accentPrimary)
            .onChange(of: biometricLock) { _, _ in triggerHaptic() }

            // Auto-Lock — navigation link to picker
            NavigationLink {
                AutoLockPickerView(selection: $autoLockInterval, options: autoLockOptions)
            } label: {
                settingsRow(
                    icon: Symbols.lock,
                    iconColor: .accentPrimary,
                    title: "Auto-Lock",
                    value: autoLockInterval
                )
            }

            // Transaction Signing — toggle
            Toggle(isOn: $transactionSigning) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transaction Signing")
                            .font(.mtrxBody)
                            .foregroundStyle(Color.labelPrimary)
                        Text("Require biometric for transactions")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                } icon: {
                    SettingsIcon(symbol: Symbols.contractSign, color: .statusWarning)
                }
            }
            .tint(Color.accentPrimary)
            .onChange(of: transactionSigning) { _, _ in triggerHaptic() }
        } header: {
            Text("Security")
        } footer: {
            Text("Biometric lock protects app access. Transaction signing requires confirmation before sending assets.")
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section {
            // Clear Cache
            Button {
                showClearCacheConfirm = true
            } label: {
                Label {
                    Text("Clear Cache")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: "trash", color: .labelSecondary)
                }
            }

            // Reset Preferences
            Button {
                showResetPrefsConfirm = true
            } label: {
                Label {
                    Text("Reset Preferences")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.statusError)
                } icon: {
                    SettingsIcon(symbol: "arrow.counterclockwise", color: .statusError)
                }
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Clearing the cache frees storage. Resetting preferences restores all defaults.")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            // Version — non-tappable
            HStack {
                Label {
                    Text("Version")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: Symbols.info, color: .labelSecondary)
                }
                Spacer()
                Text("1.0.0 (Build 1)")
                    .font(.mtrxFootnote)
                    .foregroundStyle(Color.labelSecondary)
            }

            // Terms of Service
            NavigationLink {
                PlaceholderLegalView(title: "Terms of Service")
            } label: {
                Label {
                    Text("Terms of Service")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: "doc.plaintext", color: .labelSecondary)
                }
            }

            // Privacy Policy
            NavigationLink {
                PlaceholderLegalView(title: "Privacy Policy")
            } label: {
                Label {
                    Text("Privacy Policy")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: Symbols.privacy, color: .labelSecondary)
                }
            }

            // Open Source Licenses
            NavigationLink {
                PlaceholderLegalView(title: "Open Source Licenses")
            } label: {
                Label {
                    Text("Open Source Licenses")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                } icon: {
                    SettingsIcon(symbol: "doc.text", color: .labelSecondary)
                }
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Row Helper

    private func settingsRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack {
            Label {
                Text(title)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelPrimary)
            } icon: {
                SettingsIcon(symbol: icon, color: iconColor)
            }
            Spacer()
            Text(value)
                .font(.mtrxFootnote)
                .foregroundStyle(Color.labelSecondary)
        }
    }

    // MARK: - Helpers

    private func triggerHaptic() {
        if hapticFeedback {
            MtrxHaptics.selection()
        }
    }

    private func resetAllPreferences() {
        selectedCurrency = "USD"
        selectedTheme = "System"
        hapticFeedback = true
        defaultChain = "Base"
        gasStrategy = "Standard"
        proactiveAlerts = true
        communicationStyle = "Concise"
        expertiseLevel = "Intermediate"
        biometricLock = true
        autoLockInterval = "5 min"
        transactionSigning = true
    }

    // MARK: - Biometric Detection

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

    private var biometricIcon: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return Symbols.biometric
        }
        switch context.biometryType {
        case .touchID: return "touchid"
        default: return Symbols.biometric
        }
    }
}

// MARK: - Settings Icon Component

private struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Currency Picker

private struct CurrencyPickerView: View {
    @Binding var selection: String
    let currencies: [String]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mtrx_haptics") private var hapticFeedback = true

    private let currencyNames: [String: String] = [
        "USD": "US Dollar",
        "EUR": "Euro",
        "GBP": "British Pound",
        "JPY": "Japanese Yen",
        "CHF": "Swiss Franc",
        "CAD": "Canadian Dollar",
        "AUD": "Australian Dollar",
        "BTC": "Bitcoin",
        "ETH": "Ethereum"
    ]

    var body: some View {
        List {
            ForEach(currencies, id: \.self) { currency in
                Button {
                    selection = currency
                    if hapticFeedback { MtrxHaptics.selection() }
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currency)
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelPrimary)
                            if let name = currencyNames[currency] {
                                Text(name)
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                            }
                        }
                        Spacer()
                        if currency == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundGrouped.ignoresSafeArea())
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Chain Picker

private struct ChainPickerView: View {
    @Binding var selection: String
    let chains: [String]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mtrx_haptics") private var hapticFeedback = true

    private let chainIcons: [String: String] = [
        "Base": "b.circle.fill",
        "Ethereum": "e.circle.fill",
        "Polygon": "p.circle.fill",
        "Arbitrum": "a.circle.fill",
        "Optimism": "o.circle.fill"
    ]

    var body: some View {
        List {
            ForEach(chains, id: \.self) { chain in
                Button {
                    selection = chain
                    if hapticFeedback { MtrxHaptics.selection() }
                    dismiss()
                } label: {
                    HStack(spacing: Spacing.ms) {
                        Image(systemName: chainIcons[chain] ?? "circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: 32)

                        Text(chain)
                            .font(.mtrxBody)
                            .foregroundStyle(Color.labelPrimary)

                        Spacer()

                        if chain == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundGrouped.ignoresSafeArea())
        .navigationTitle("Default Chain")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Style Picker (Communication / Expertise)

private struct StylePickerView: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var descriptions: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mtrx_haptics") private var hapticFeedback = true

    var body: some View {
        List {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    if hapticFeedback { MtrxHaptics.selection() }
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option)
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelPrimary)
                            if let desc = descriptions[option] {
                                Text(desc)
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        if option == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundGrouped.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Auto-Lock Picker

private struct AutoLockPickerView: View {
    @Binding var selection: String
    let options: [String]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mtrx_haptics") private var hapticFeedback = true

    var body: some View {
        List {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    if hapticFeedback { MtrxHaptics.selection() }
                    dismiss()
                } label: {
                    HStack {
                        Text(option)
                            .font(.mtrxBody)
                            .foregroundStyle(Color.labelPrimary)
                        Spacer()
                        if option == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundGrouped.ignoresSafeArea())
        .navigationTitle("Auto-Lock")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Placeholder Legal View

private struct PlaceholderLegalView: View {
    let title: String

    private var content: String {
        switch title {
        case "Terms of Service":
            return """
            Effective June 2026

            1. The Service. MTRX provides a consumer interface to the \
            0pnMatrx platform: AI-assisted finance, smart-contract \
            tooling, and on-chain social features. Demo environments \
            simulate execution and move no real funds.

            2. Eligibility. You must be at least 18 and legally able to \
            enter contracts in your jurisdiction.

            3. Your Account. Sign in with Apple secures your identity; \
            wallet keys are generated on-device in the Secure Enclave \
            and never leave your hardware. You are responsible for the \
            security of your device.

            4. Acceptable Use. No unlawful activity, market abuse, or \
            attempts to access other users' data or restricted system \
            layers. Guardian-agent interventions enforce these rules.

            5. No Financial Advice. Information in the app — including \
            agent responses — is not investment advice. Digital assets \
            are volatile; you may lose value.

            6. Liability. The service is provided "as is" to the extent \
            permitted by law. OPN MATRX disclaims indirect and \
            consequential damages.

            7. Changes. We may update these terms; continued use after \
            notice constitutes acceptance.
            """
        case "Privacy Policy":
            return """
            Effective June 2026

            What we collect. Account identifiers from Sign in with \
            Apple, app settings, and the content you create. Wallet \
            addresses are public by nature of blockchains.

            What stays on your device. Agent conversations run on-device \
            with Apple Intelligence; chat history, wallet keys, and \
            location never leave your iPhone. Weather and price lookups \
            query public APIs without your identity attached.

            What we don't do. No ad tracking, no selling of personal \
            data, no off-device profiling. Anonymous analytics and crash \
            reports are optional and controlled in Privacy settings.

            Your controls. Export your data, adjust privacy levels, or \
            delete your account at any time from Account → Privacy.

            Contact: privacy@openmatrix-ai.com
            """
        default:
            return """
            MTRX is built with the Swift open-source ecosystem and \
            gratefully acknowledges:

            • Swift & SwiftUI — Apache License 2.0, Apple Inc.
            • Swift Collections — Apache License 2.0
            • Swift Crypto — Apache License 2.0

            Market data is provided by the CoinGecko public API; weather \
            by Open-Meteo (CC BY 4.0); knowledge lookups by Wikipedia \
            (CC BY-SA). Full license texts are available from their \
            respective projects.
            """
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(title)
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)

                Text(content)
                    .font(.mtrxCallout)
                    .foregroundStyle(Color.labelSecondary)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.contentPadding)
        }
        .background(Color.backgroundGrouped.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview("Settings") {
    SettingsView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
