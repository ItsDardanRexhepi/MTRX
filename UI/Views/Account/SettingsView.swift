import SwiftUI
import LocalAuthentication

/// All user controls — notifications, privacy, display, security, connected devices, data export
struct SettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("biometricsEnabled") private var biometricsEnabled = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("darkMode") private var darkMode = true

    var body: some View {
        Form {
            Section("Security") {
                Toggle("Face ID / Touch ID", isOn: $biometricsEnabled)
                NavigationLink("Change PIN") { Text("PIN Change") }
                NavigationLink("Connected Devices") { Text("Devices") }
            }

            Section("Notifications") {
                Toggle("Push Notifications", isOn: $notificationsEnabled)
                NavigationLink("Notification Preferences") { Text("Configure per-component notifications") }
            }

            Section("Display") {
                Toggle("Dark Mode", isOn: $darkMode)
                Toggle("Haptic Feedback", isOn: $hapticFeedback)
                NavigationLink("Currency Display") { Text("USD / ETH / Custom") }
            }

            Section("Privacy") {
                NavigationLink("Privacy Controls", destination: PrivacyView())
                NavigationLink("Data Export") { Text("Export all your data as encrypted archive") }
            }

            Section("About") {
                HStack { Text("Version"); Spacer(); Text("1.0.0").foregroundColor(.secondary) }
                HStack { Text("Network"); Spacer(); Text("Base Mainnet").foregroundColor(.secondary) }
                NavigationLink("Open Source Licenses") { Text("Licenses") }
            }
        }
        .navigationTitle("Settings")
    }
}
