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

            // Phone verification (SMS OTP, Phase 2)
            Section("Verification") {
                NavigationLink {
                    PhoneVerificationView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect phone number")
                                .font(.mtrxBody).foregroundStyle(Color.labelPrimary)
                            Text("Verify your phone with an SMS code")
                                .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                        }
                    } icon: {
                        Image(systemName: "phone.badge.checkmark")
                            .foregroundStyle(Color.statusInfo)
                    }
                }
            }

            // Wallet backup & recovery (Phase 4-A)
            Section("Wallet recovery") {
                NavigationLink {
                    RecoveryView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Backup & recovery")
                                .font(.mtrxBody).foregroundStyle(Color.labelPrimary)
                            Text("Back up your wallet to iCloud and check its protection")
                                .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                        }
                    } icon: {
                        Image(systemName: "lock.rotation")
                            .foregroundStyle(Color.statusInfo)
                    }
                }
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

// MARK: - Wallet Recovery (Phase 4-A / step 4)
//
// This screen is UI + wiring only — it DRIVES the existing, tested recovery code
// (`WalletCreation.backupActiveWallet` → `backupToCloud`, `recoverWallet` →
// `performWalletRecovery`, and the W2/W3 `restoreActiveWallet` outcome). No crypto is
// reimplemented here, and NO value/UserOperation is signed: backup/restore move only the wallet's
// recoverable METADATA (address + public key) and re-validate the key reference. The Tier-A reset
// ACTION (step 5) and the Tier-B guardian-rotation recovery are intentionally NOT wired here.

@MainActor
final class RecoveryViewModel: ObservableObject {
    enum SignerStatus { case unknown, protected, needsReset(String), identityOnly, noWallet }
    enum ActionState: Equatable { case idle, inProgress, success(String), failure(String) }

    @Published var signerStatus: SignerStatus = .unknown
    @Published var backupState: ActionState = .idle
    @Published var restoreState: ActionState = .idle
    @Published var guardians: [RecoveryGuardian] = []

    private let creator = WalletCreation()

    /// Refresh the (honest) signer status by re-running the W2/W3 validated restore. Sync probes only
    /// — no signing, no prompt.
    func refresh() {
        switch creator.restoreActiveWallet() {
        case .restored:           signerStatus = .protected
        case .needsReset(let r):  signerStatus = .needsReset(r)
        case .identityOnly:       signerStatus = .identityOnly
        case .noWallet:           signerStatus = .noWallet
        }
        guardians = creator.getGuardians()
    }

    func backUp() {
        backupState = .inProgress
        creator.backupActiveWallet { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.backupState = .success("Backed up to iCloud Keychain.")
                case .failure(let error):
                    self?.backupState = .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }
        }
    }

    func restore() {
        restoreState = .inProgress
        creator.recoverWallet { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.restoreState = .success("Wallet details restored from iCloud.")
                    self?.refresh()
                case .failure(.invalidRecoveryData):
                    self?.restoreState = .failure("No iCloud backup was found for this account.")
                case .failure(let error):
                    self?.restoreState = .failure(error.errorDescription ?? "Restore couldn't be completed.")
                }
            }
        }
    }
}

struct RecoveryView: View {
    @StateObject private var vm = RecoveryViewModel()

    var body: some View {
        List {
            Section("Wallet protection") { signerStatusRow }

            Section("iCloud backup") {
                Text("Backs up your wallet's recoverable details — address and public key — to your "
                     + "iCloud Keychain. Your signing key never leaves this device.")
                    .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                Button { vm.backUp() } label: {
                    Label("Back up to iCloud", systemImage: "icloud.and.arrow.up")
                }
                .disabled(vm.backupState == .inProgress)
                stateRow(vm.backupState)
            }

            Section("Restore") {
                Text("Restores your wallet's details from an iCloud backup — e.g. on a new device. "
                     + "Regaining the ability to sign may still require recovery.")
                    .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                Button { vm.restore() } label: {
                    Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                }
                .disabled(vm.restoreState == .inProgress)
                stateRow(vm.restoreState)
            }

            Section("Recovery guardians") {
                if vm.guardians.isEmpty {
                    Text("No guardians added.")
                        .font(.mtrxCaption1).foregroundStyle(Color.labelTertiary)
                } else {
                    ForEach(vm.guardians, id: \.address) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.mtrxBody).foregroundStyle(Color.labelPrimary)
                            Text(g.address).font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Wallet Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.refresh() }
    }

    @ViewBuilder private var signerStatusRow: some View {
        switch vm.signerStatus {
        case .unknown:
            ProgressView()
        case .protected:
            Label("Protected — your signing key is biometric-secured.", systemImage: "checkmark.shield.fill")
                .font(.mtrxCallout).foregroundStyle(Color.statusSuccess)
        case .needsReset(let reason):
            VStack(alignment: .leading, spacing: 4) {
                Label("Your signing key needs to be reset", systemImage: "exclamationmark.triangle.fill")
                    .font(.mtrxCalloutBold).foregroundStyle(Color.statusWarning)
                Text(reason).font(.mtrxCaption2).foregroundStyle(Color.labelSecondary)
            }
        case .identityOnly:
            Label("Restored from iCloud — this device has no signing key yet. Set up recovery to sign.",
                  systemImage: "key.slash")
                .font(.mtrxCallout).foregroundStyle(Color.statusInfo)
        case .noWallet:
            Text("No wallet on this device yet.")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
        }
    }

    @ViewBuilder private func stateRow(_ state: RecoveryViewModel.ActionState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .inProgress:
            HStack(spacing: 8) { ProgressView(); Text("Working…").font(.mtrxCaption2).foregroundStyle(Color.labelTertiary) }
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill").font(.mtrxCaption1).foregroundStyle(Color.statusSuccess)
        case .failure(let msg):
            Label(msg, systemImage: "exclamationmark.circle.fill").font(.mtrxCaption1).foregroundStyle(Color.statusWarning)
        }
    }
}
