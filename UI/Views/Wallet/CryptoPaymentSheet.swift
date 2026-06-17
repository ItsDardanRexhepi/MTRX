// CryptoPaymentSheet.swift
// MTRX — Pay a merchant in crypto (NOT Apple Pay)
//
// A reusable, honest payment sheet: given a recipient address + amount it
// gates on Face ID, then signs and submits a REAL on-chain transfer via
// BlockchainBridge (ERC-4337). It only shows success when the send returns a
// real transaction hash; if no wallet is connected or the chain isn't
// configured the send throws and the sheet surfaces the real error — it never
// fakes a completed payment.
//
// This is reusable infrastructure: present it from any surface that has a real
// recipient + amount (it is intentionally NOT wired to the demo, ETH-priced
// events, which have no payee address).

import SwiftUI

struct CryptoPaymentSheet: View {

    let recipient: String          // 0x… address to pay
    let amount: Decimal            // human amount, in `token` units
    let token: String              // e.g. "ETH"
    let memo: String?              // what's being paid for
    var onComplete: ((TransactionResult) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .review
    @State private var txHash: String?
    @State private var errorText: String?

    enum Phase { case review, authenticating, sending, success, failure }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            header

            switch phase {
            case .review:         reviewBody
            case .authenticating: statusBody(icon: "faceid", text: "Confirm with Face ID…", tint: .accentPrimary)
            case .sending:        statusBody(icon: "arrow.up.circle", text: "Submitting payment…", tint: .accentPrimary, spin: true)
            case .success:        successBody
            case .failure:        failureBody
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Pay")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: Symbols.close)
                    .accessibilityLabel("Close")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.labelSecondary)
            }
        }
    }

    // MARK: - Review

    private var reviewBody: some View {
        VStack(spacing: Spacing.md) {
            VStack(spacing: Spacing.xs) {
                Text(amountText)
                    .font(.mtrxDisplaySmall)
                    .foregroundStyle(Color.labelPrimary)
                    .monospacedDigit()
                if let memo, !memo.isEmpty {
                    Text(memo)
                        .font(.mtrxSubheadline)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            detailRow("To", shortAddress)

            Button {
                Task { await pay() }
            } label: {
                Text("Confirm payment")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
            .disabled(!isValid)

            if !isValid {
                Text(invalidReason)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.statusError)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.mtrxCallout).foregroundStyle(Color.labelTertiary)
            Spacer()
            Text(value).font(.mtrxCallout.monospaced()).foregroundStyle(Color.labelPrimary)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Status / Result

    private func statusBody(icon: String, text: String, tint: Color, spin: Bool = false) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: spin)
            Text(text).font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.lg)
    }

    private var successBody: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.statusSuccess)
            Text("Payment sent")
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)
            if let txHash {
                Text("Tx \(txHash.prefix(10))…\(txHash.suffix(6))")
                    .font(.mtrxCaption1.monospaced())
                    .foregroundStyle(Color.labelTertiary)
            }
            Button { dismiss() } label: { Text("Done") }
                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular, fullWidth: true))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.md)
    }

    private var failureBody: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.statusError)
            Text(errorText ?? "Payment failed")
                .font(.mtrxCallout)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Spacing.sm) {
                Button { phase = .review } label: { Text("Try again") }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
                Button { dismiss() } label: { Text("Cancel") }
                    .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .regular, fullWidth: true))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.md)
    }

    // MARK: - Payment

    @MainActor
    private func pay() async {
        guard BlockchainBridge.shared.isWalletConnected else {
            fail("Connect a wallet before paying.")
            return
        }
        guard isValidAddress, let wei = weiAmount else {
            fail(invalidReason)
            return
        }

        // Face ID confirmation for the transfer.
        phase = .authenticating
        do {
            let ok = try await BiometricAuth.shared.authenticate(
                reason: "Confirm payment of \(amountText)"
            )
            guard ok else { phase = .review; return }
        } catch {
            fail((error as? LocalizedError)?.errorDescription ?? "Authentication failed.")
            return
        }

        // Real on-chain send.
        phase = .sending
        do {
            let result = try await BlockchainBridge.shared.sendTransaction(to: recipient, amount: wei)
            txHash = result.transactionHash
            phase = .success
            MtrxHaptics.success()
            onComplete?(result)
        } catch {
            fail((error as? LocalizedError)?.errorDescription ?? "The transfer could not be completed.")
        }
    }

    private func fail(_ message: String) {
        errorText = message
        phase = .failure
    }

    // MARK: - Validation / formatting

    private var isValid: Bool { isValidAddress && weiAmount != nil }

    private var isValidAddress: Bool {
        recipient.hasPrefix("0x") && recipient.count == 42 &&
            recipient.dropFirst(2).allSatisfy { $0.isHexDigit }
    }

    /// `amount` (in token units) → wei, guarded to fit the bridge's UInt64.
    private var weiAmount: UInt64? {
        guard amount > 0 else { return nil }
        let wei = (amount as NSDecimalNumber).multiplying(byPowerOf10: 18)
        guard wei.compare(NSDecimalNumber(value: UInt64.max)) != .orderedDescending else { return nil }
        return wei.uint64Value
    }

    private var amountText: String { "\(amount) \(token)" }

    private var shortAddress: String {
        guard recipient.count >= 12 else { return recipient }
        return "\(recipient.prefix(6))…\(recipient.suffix(4))"
    }

    private var invalidReason: String {
        if !isValidAddress { return "Recipient address is invalid." }
        if weiAmount == nil { return "Amount is invalid." }
        return ""
    }
}
