// PhoneVerificationView.swift
// MTRX — Connect your phone via SMS one-time code (Phase 2).
//
// Two-step OTP flow wired to the server endpoints
// (/security/phone/request + /security/phone/verify). The code is generated,
// rate-limited, and verified server-side; the app only relays the user's input.

import SwiftUI

struct PhoneVerificationView: View {
    private enum Step { case phone, code, done }

    @State private var step: Step = .phone
    @State private var phone = ""
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false
    @AppStorage("sec.connectedPhone") private var connectedPhone = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if !connectedPhone.isEmpty {
                Section("Connected") {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.statusSuccess)
                        Text(connectedPhone).font(.mtrxBody).foregroundStyle(Color.labelPrimary)
                    }
                }
            }

            switch step {
            case .phone: phoneSection
            case .code:  codeSection
            case .done:  doneSection
            }

            if let error {
                Section {
                    Text(error).font(.mtrxCaption1).foregroundStyle(Color.statusError)
                }
            }
        }
        .navigationTitle("Connect Phone")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
    }

    // MARK: - Steps

    @ViewBuilder private var phoneSection: some View {
        Section {
            TextField("+1 555 123 4567", text: $phone)
                .keyboardType(.phonePad)
                .font(.mtrxBody)
            Button {
                Task { await sendCode() }
            } label: {
                HStack {
                    if busy { ProgressView().tint(Color.trinityPrimary) }
                    Text(busy ? "Sending…" : "Send code")
                }
            }
            .disabled(phone.trimmingCharacters(in: .whitespaces).count < 7 || busy)
        } header: {
            Text("Phone number")
        } footer: {
            Text("We'll text you a one-time code to verify this number. Standard rates apply.")
                .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
        }
    }

    @ViewBuilder private var codeSection: some View {
        Section {
            TextField("6-digit code", text: $code)
                .keyboardType(.numberPad)
                .font(.mtrxMonoMedium)
            Button {
                Task { await verify() }
            } label: {
                HStack {
                    if busy { ProgressView().tint(Color.trinityPrimary) }
                    Text(busy ? "Verifying…" : "Verify")
                }
            }
            .disabled(code.trimmingCharacters(in: .whitespaces).count < 4 || busy)

            Button("Use a different number") {
                step = .phone; code = ""; error = nil
            }
            .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
        } header: {
            Text("Enter the code sent to \(phone)")
        }
    }

    @ViewBuilder private var doneSection: some View {
        Section {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40)).foregroundStyle(Color.statusSuccess)
                Text("Phone connected").font(.mtrxBodyBold).foregroundStyle(Color.labelPrimary)
                Text(connectedPhone).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            Button("Done") { dismiss() }
        }
    }

    // MARK: - Actions

    private func sendCode() async {
        error = nil; busy = true; defer { busy = false }
        do {
            let res = try await MTRXAPIClient.shared.requestPhoneOTP(phone: phone)
            if res.sent == true {
                step = .code
            } else {
                error = res.reason ?? "Couldn't send a code. Try again."
            }
        } catch {
            self.error = "Couldn't send a code right now. Check your connection and try again."
        }
    }

    private func verify() async {
        error = nil; busy = true; defer { busy = false }
        do {
            let res = try await MTRXAPIClient.shared.verifyPhoneOTP(phone: phone, code: code)
            if res.verified == true {
                connectedPhone = phone
                step = .done
            } else {
                error = res.reason ?? "That code didn't match. Try again."
            }
        } catch {
            self.error = "Couldn't verify right now. Check your connection and try again."
        }
    }
}
