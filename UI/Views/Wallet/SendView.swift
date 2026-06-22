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
    // P2.1 asset scope: non-native (ERC-20) sends are out of scope for the first real
    // flow. They get an explicit honest "token sends not available" and never reach the
    // ETH-only signed path — so a wrong-asset send (sending native value for a token) is
    // impossible.
    @State private var showTokenUnavailable: Bool = false
    // P2.2: real native-ETH send state. "Transaction Sent" fires ONLY on a real op-hash;
    // sendError carries the real, honest error on any failure (nothing is ever faked).
    @State private var isSending: Bool = false
    @State private var sendError: String?
    @State private var sentHash: String?

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

    /// True only for the chain's NATIVE asset (Base Sepolia ETH). The first real Send
    /// flow (P2.2) supports native ETH only; non-native ERC-20 tokens are honest-failed
    /// so a wrong-asset send is impossible — BlockchainBridge.sendTransaction moves
    /// native value, not ERC-20 transfer calldata.
    ///
    /// Keyed off the STRUCTURAL `isNative` flag (set from token metadata), NOT the symbol
    /// string — so a token cannot be treated as native by spoofing its symbol "ETH".
    private var isNativeSend: Bool {
        selectedToken.isNative
    }

    /// `amount` (ETH units) → wei, guarded to fit BlockchainBridge's UInt64. nil if invalid.
    private var weiAmount: UInt64? {
        guard amount > 0 else { return nil }
        let wei = NSDecimalNumber(value: amount).multiplying(byPowerOf10: 18)
        guard wei.compare(NSDecimalNumber(value: UInt64.max)) != .orderedDescending else { return nil }
        return wei.uint64Value
    }

    // MARK: - Real native-ETH send (P2.2)

    /// Real native-ETH testnet send: biometric → advisory gate consult → real signed
    /// broadcast → success ONLY on a real op-hash. Every failure (no wallet, bad amount,
    /// cancelled Face ID, gate deny, network/revert) surfaces the real error honestly;
    /// nothing ever fakes "Transaction Sent". Does nothing for non-native tokens.
    @MainActor
    private func sendNative() async {
        guard isNativeSend else { return }
        sendError = nil

        // Precondition: a connected wallet + a valid native amount. Honest-fail otherwise.
        guard BlockchainBridge.shared.isWalletConnected else {
            sendError = "Connect a wallet before sending. Nothing was sent."
            return
        }
        guard let wei = weiAmount else {
            sendError = "Enter a valid ETH amount. Nothing was sent."
            return
        }

        // 1. Biometric gate BEFORE signing. A cancelled / failed Face ID ABORTS — no sign.
        do {
            let ok = try await BiometricAuth.shared.authenticate(reason: "Confirm sending \(amountText) ETH")
            guard ok else { return }   // user cancelled → abort; nothing signed, nothing sent
        } catch {
            sendError = (error as? LocalizedError)?.errorDescription ?? "Face ID was not confirmed. Nothing was sent."
            return
        }

        // 2. Advisory security gate consult (Requirement 5, Option B — NOT enforcement;
        //    see MTRXAPIClient.securityPreflightAllowsSend). An explicit deny aborts.
        let allowed = await MTRXAPIClient.shared.securityPreflightAllowsSend(
            to: recipientAddress, valueUSD: usdEquivalent, chainId: BlockchainBridge.baseSepoliaChainID)
        guard allowed else {
            sendError = "This transfer couldn't be authorized right now. Nothing was sent."
            return
        }

        // 3. Real signed testnet send. Success ONLY when it broadcasts and returns a hash.
        isSending = true
        do {
            let result = try await BlockchainBridge.shared.sendTransaction(to: recipientAddress, amount: wei)
            isSending = false
            sentHash = result.transactionHash   // honest success — a real op-hash
            MtrxHaptics.success()
        } catch {
            isSending = false
            sendError = (error as? LocalizedError)?.errorDescription ?? "The transfer could not be completed. Nothing was sent."
        }
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
        // Success — fires ONLY when the send actually broadcast and returned a real hash.
        .alert("Transaction Sent", isPresented: Binding(
            get: { sentHash != nil },
            set: { if !$0 { sentHash = nil } }
        )) {
            Button("Done") { sentHash = nil; dismiss() }
        } message: {
            Text("Sent \(amountText) ETH. Transaction \(truncateAddress(sentHash ?? "")).")
        }
        // Honest failure — the real error from any stage (no wallet, bad amount, Face ID
        // cancelled, gate deny, network/revert). Never a fake success.
        .alert("Send Failed", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK") { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
        .alert("Token Sends Unavailable", isPresented: $showTokenUnavailable) {
            Button("OK") {}
        } message: {
            Text("Only ETH sends are supported in this build. \(selectedToken.symbol) sending isn't available yet — nothing was sent.")
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
                    MtrxHaptics.impact(.medium)
                    if isNativeSend {
                        // Native ETH: real signed testnet send (P2.2). biometric →
                        // advisory gate → broadcast → success ONLY on a real op-hash.
                        Task { await sendNative() }
                    } else {
                        // Non-native (ERC-20): out of scope for the first real flow.
                        // Honest-fail explicitly so a token never reaches the ETH-only
                        // path (which would otherwise move native value = wrong asset).
                        showTokenUnavailable = true
                    }
                } label: {
                    Text(isSending ? "Sending…" : "Confirm & Send")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
                .disabled(isSending)

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
