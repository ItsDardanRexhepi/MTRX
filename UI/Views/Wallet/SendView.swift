// SendView.swift
// MTRX
//
// Send token flow — recipient input, amount entry, fee estimate, confirmation.

import SwiftUI

// MARK: - Send View

struct SendView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTokenIndex: Int = 0
    @State private var recipientAddress: String = ""
    @State private var amountText: String = ""
    @State private var showReview: Bool = false
    @State private var isVisible: Bool = false
    @State private var showTokenPicker: Bool = false
    @State private var showQRAlert: Bool = false
    @State private var showSendConfirmation: Bool = false

    private var selectedToken: AppTokenBalance {
        guard walletManager.tokens.indices.contains(selectedTokenIndex) else {
            return walletManager.tokens[0]
        }
        return walletManager.tokens[selectedTokenIndex]
    }

    private var amount: Double {
        Double(amountText) ?? 0
    }

    private var usdEquivalent: Double {
        amount * selectedToken.priceUSD
    }

    private var estimatedGasFee: Double { 0.42 }

    private var isValidAddress: Bool {
        recipientAddress.count >= 10
    }

    private var isValidAmount: Bool {
        amount > 0 && amount <= selectedToken.balance
    }

    private var canProceed: Bool {
        isValidAddress && isValidAmount
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(title: "Send", subtitle: "Transfer tokens") {
                        dismiss()
                    }

                    if showReview {
                        reviewSection
                    } else {
                        formSection
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
            .onAppear {
                withAnimation(Motion.springDefault) {
                    isVisible = true
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .alert("QR Scanner", isPresented: $showQRAlert) {
            Button("OK") {}
        } message: {
            Text("QR Scanner requires camera permission. Paste an address instead.")
        }
        .alert("Not Available Yet", isPresented: $showSendConfirmation) {
            Button("OK") {}
        } message: {
            Text("On-chain sending isn't available in this build yet. Your funds have not moved.")
        }
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: Spacing.lg) {
            tokenSelector
            recipientField
            amountField
            feeEstimate
            sendButton
        }
        .padding(.horizontal, Spacing.contentPadding)
        .mtrxFadeInFromBottom(isVisible: isVisible)
    }

    // MARK: - Token Selector

    private var tokenSelector: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Token")
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)

            Button {
                MtrxHaptics.selection()
                showTokenPicker.toggle()
            } label: {
                HStack(spacing: Spacing.ms) {
                    MtrxAvatar(
                        text: selectedToken.symbol,
                        color: selectedToken.iconColor,
                        size: Spacing.Size.avatarSmall
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedToken.name)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text("Balance: \(formatBalance(selectedToken.balance)) \(selectedToken.symbol)")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    Image(systemName: Symbols.forward)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                        .rotationEffect(.degrees(showTokenPicker ? 90 : 0))
                }
                .mtrxCardStyle()
            }
            .buttonStyle(.plain)

            if showTokenPicker {
                tokenPickerList
                    .transition(.mtrxScale)
            }
        }
    }

    private var tokenPickerList: some View {
        VStack(spacing: 0) {
            ForEach(Array(walletManager.tokens.enumerated()), id: \.element.id) { index, token in
                Button {
                    MtrxHaptics.selection()
                    withAnimation(Motion.springSnappy) {
                        selectedTokenIndex = index
                        showTokenPicker = false
                        amountText = ""
                    }
                } label: {
                    HStack(spacing: Spacing.ms) {
                        MtrxAvatar(text: token.symbol, color: token.iconColor, size: 28)

                        Text(token.symbol)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)

                        Spacer()

                        Text(formatBalance(token.balance))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)

                        if index == selectedTokenIndex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                    .padding(.horizontal, Spacing.ms)
                }
                .buttonStyle(.plain)

                if index < walletManager.tokens.count - 1 {
                    MtrxDivider()
                        .padding(.leading, Spacing.xl)
                }
            }
        }
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }

    // MARK: - Recipient Field

    private var recipientField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recipient")
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)

            HStack(spacing: Spacing.sm) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.labelTertiary)
                    .frame(width: 20)

                TextField("Address or ENS name", text: $recipientAddress)
                    .font(.mtrxMono)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)

                Button {
                    MtrxHaptics.impact(.light)
                    if let clipboard = UIPasteboard.general.string {
                        recipientAddress = clipboard
                    }
                } label: {
                    Image(systemName: Symbols.paste)
                        .accessibilityLabel("Paste from clipboard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentPrimary)
                }

                Button {
                    MtrxHaptics.impact(.light)
                    showQRAlert = true
                } label: {
                    Image(systemName: Symbols.qrScanner)
                        .accessibilityLabel("Scan QR code")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentPrimary)
                }
            }
            .padding(.horizontal, Spacing.textFieldPadding)
            .frame(height: Spacing.Size.textFieldHeight)
            .background(Color.surfaceOverlay)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

            if !recipientAddress.isEmpty && !isValidAddress {
                Text("Enter a valid address or ENS name")
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.statusError)
            }
        }
    }

    // MARK: - Amount Field

    private var amountField: some View {
        VStack(spacing: Spacing.ms) {
            Text("Amount")
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            MtrxCard(style: .glass) {
                VStack(spacing: Spacing.ms) {
                    HStack {
                        Spacer()
                        TextField("0.00", text: $amountText)
                            .font(.mtrxMonoLarge)
                            .foregroundStyle(Color.labelPrimary)
                            .multilineTextAlignment(.center)
                            .keyboardType(.decimalPad)
                            .minimumScaleFactor(0.5)
                        Spacer()
                    }

                    Text(formatUSD(usdEquivalent))
                        .font(.mtrxMono)
                        .foregroundStyle(Color.labelSecondary)

                    Button {
                        MtrxHaptics.impact(.light)
                        amountText = formatBalance(selectedToken.balance)
                    } label: {
                        Text("MAX")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.accentPrimary)
                            .padding(.horizontal, Spacing.ms)
                            .padding(.vertical, Spacing.xs)
                            .background(Color.accentPrimary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    if !amountText.isEmpty && amount > selectedToken.balance {
                        Text("Insufficient \(selectedToken.symbol) balance")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.statusError)
                    }
                }
            }
        }
    }

    // MARK: - Fee Estimate

    private var feeEstimate: some View {
        HStack {
            HStack(spacing: Spacing.xs) {
                Image(systemName: Symbols.gas)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.labelTertiary)
                Text("Estimated Fee")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }
            Spacer()
            Text(formatUSD(estimatedGasFee))
                .font(.mtrxMonoSmall)
                .foregroundStyle(Color.labelPrimary)
        }
        .padding(.horizontal, Spacing.sm)
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            MtrxHaptics.impact(.medium)
            withAnimation(Motion.springDefault) {
                showReview = true
            }
        } label: {
            Text("Review Transfer")
        }
        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
        .disabled(!canProceed)
        .opacity(canProceed ? 1 : 0.5)
    }

    // MARK: - Review Section

    private var reviewSection: some View {
        VStack(spacing: Spacing.lg) {
            MtrxCard(style: .elevated) {
                VStack(spacing: Spacing.md) {
                    reviewRow(label: "From", value: "My Wallet", mono: false)
                    MtrxDivider()
                    reviewRow(label: "To", value: truncateAddress(recipientAddress), mono: true)
                    MtrxDivider()
                    reviewRow(label: "Amount", value: "\(amountText) \(selectedToken.symbol)", mono: true)
                    MtrxDivider()
                    reviewRow(label: "Value", value: formatUSD(usdEquivalent), mono: true)
                    MtrxDivider()
                    reviewRow(label: "Network Fee", value: formatUSD(estimatedGasFee), mono: true)
                    MtrxDivider()
                    reviewRow(label: "Total Cost", value: formatUSD(usdEquivalent + estimatedGasFee), mono: true)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            VStack(spacing: Spacing.ms) {
                Button {
                    // Honest failure: no real signing/broadcast exists yet, so this
                    // must NOT claim the transfer succeeded. Surfaces "not available
                    // yet" instead of a fake "Transaction Sent". (Wiring to the real
                    // signed-transfer path is Phase 2, not here.)
                    MtrxHaptics.impact(.medium)
                    showSendConfirmation = true
                } label: {
                    Text("Confirm & Send")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))

                Button {
                    MtrxHaptics.impact(.light)
                    withAnimation(Motion.springDefault) {
                        showReview = false
                    }
                } label: {
                    Text("Edit")
                }
                .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .regular))
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
        .mtrxFadeInFromBottom(isVisible: true)
    }

    private func reviewRow(label: String, value: String, mono: Bool) -> some View {
        HStack {
            Text(label)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value)
                .font(mono ? .mtrxMonoSmall : .mtrxBody)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Helpers

    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = balance < 1 ? 6 : (balance < 100 ? 4 : 2)
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        let prefix = String(address.prefix(6))
        let suffix = String(address.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Preview

#Preview {
    SendView()
        .environmentObject(WalletManager())
        .preferredColorScheme(.dark)
}
