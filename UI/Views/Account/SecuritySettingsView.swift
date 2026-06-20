// SecuritySettingsView.swift
// MTRX — Settings → Security (Phase 4 user-side fund protection).
//
// Surfaces the protective DEFAULTS the user owns and controls, with clear copy so
// they understand these are protections they can raise, lower, or disable for
// their own wallet. The system never overrides their choice over their own funds.

import SwiftUI

struct SecuritySettingsView: View {
    @State private var prefs = SecurityPreferences.shared
    @State private var showResetConfirm = false

    var body: some View {
        @Bindable var prefs = prefs

        List {
            Section {
                Text("These are protective defaults for your own wallet. You're in "
                     + "control — raise, lower, or turn off any of them. MTRX never "
                     + "moves your funds; only your device can sign.")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            // Extra confirmation over a threshold
            Section("Large transaction confirmation") {
                Toggle(isOn: $prefs.extraConfirmEnabled) {
                    label("Extra confirmation",
                          "Show a plain-language confirmation before transfers over "
                          + "the amount below.")
                }
                if prefs.extraConfirmEnabled {
                    Stepper(value: $prefs.extraConfirmThresholdUSD, in: 0...1_000_000, step: 500) {
                        amountRow("Over", prefs.extraConfirmThresholdUSD)
                    }
                }
            }

            // Cooling-off / time-delay
            Section("Cooling-off delay") {
                Toggle(isOn: $prefs.coolingOffEnabled) {
                    label("Time-delay large moves",
                          "Hold big transfers for a window so you can cancel them if "
                          + "your account is compromised.")
                }
                if prefs.coolingOffEnabled {
                    Stepper(value: $prefs.coolingOffThresholdUSD, in: 0...5_000_000, step: 1_000) {
                        amountRow("Over", prefs.coolingOffThresholdUSD)
                    }
                    Picker("Delay", selection: $prefs.coolingOffDelaySeconds) {
                        Text("15 min").tag(900.0)
                        Text("1 hour").tag(3_600.0)
                        Text("4 hours").tag(14_400.0)
                        Text("24 hours").tag(86_400.0)
                    }
                }
            }

            // Daily soft threshold (extra verification, not a block)
            Section("Daily limit alert") {
                Toggle(isOn: $prefs.dailySoftEnabled) {
                    label("Daily verification threshold",
                          "Ask for extra verification once your transfers pass this "
                          + "amount in a day. It's a check, not a block — it's your money.")
                }
                if prefs.dailySoftEnabled {
                    Stepper(value: $prefs.dailySoftThresholdUSD, in: 0...10_000_000, step: 5_000) {
                        amountRow("Over", prefs.dailySoftThresholdUSD)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Text("Reset to recommended defaults")
                        .font(.mtrxBody)
                }
            }
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset all security settings to the recommended defaults?",
                            isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { prefs.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Rows

    private func label(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.mtrxBody).foregroundStyle(Color.labelPrimary)
            Text(subtitle).font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
        }
    }

    private func amountRow(_ prefix: String, _ amount: Double) -> some View {
        HStack {
            Text(prefix).font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(Self.usd(amount)).font(.mtrxCalloutBold).foregroundStyle(Color.labelPrimary)
        }
    }

    private static func usd(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}
