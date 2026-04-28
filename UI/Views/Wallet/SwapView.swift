// SwapView.swift
// MTRX
//
// Token swap interface — from/to selection, slippage, route info, confirmation.

import SwiftUI

// MARK: - Swap View

struct SwapView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var fromTokenIndex: Int = 0
    @State private var toTokenIndex: Int = 1
    @State private var fromAmountText: String = ""
    @State private var slippage: SlippageTolerance = .medium
    @State private var customSlippageText: String = ""
    @State private var showCustomSlippage: Bool = false
    @State private var swapRotation: Double = 0
    @State private var showConfirmation: Bool = false
    @State private var isVisible: Bool = false
    @State private var showFromPicker: Bool = false
    @State private var showToPicker: Bool = false

    // MARK: - Derived State

    private var fromToken: AppTokenBalance {
        guard walletManager.tokens.indices.contains(fromTokenIndex) else {
            return walletManager.tokens[0]
        }
        return walletManager.tokens[fromTokenIndex]
    }

    private var toToken: AppTokenBalance {
        guard walletManager.tokens.indices.contains(toTokenIndex) else {
            return walletManager.tokens[1]
        }
        return walletManager.tokens[toTokenIndex]
    }

    private var fromAmount: Double {
        Double(fromAmountText) ?? 0
    }

    private var exchangeRate: Double {
        guard toToken.priceUSD > 0 else { return 0 }
        return fromToken.priceUSD / toToken.priceUSD
    }

    private var toAmount: Double {
        fromAmount * exchangeRate
    }

    private var priceImpact: Double {
        guard fromAmount > 0 else { return 0 }
        let impact = min(fromAmount * fromToken.priceUSD / 50000.0, 5.0)
        return impact
    }

    private var effectiveSlippage: Double {
        switch slippage {
        case .low: return 0.5
        case .medium: return 1.0
        case .high: return 3.0
        case .custom: return Double(customSlippageText) ?? 1.0
        }
    }

    private var minimumReceived: Double {
        toAmount * (1 - effectiveSlippage / 100)
    }

    private var canSwap: Bool {
        fromAmount > 0 && fromAmount <= fromToken.balance && fromTokenIndex != toTokenIndex
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(title: "Swap", subtitle: "Exchange tokens instantly") {
                        dismiss()
                    }

                    if showConfirmation {
                        confirmationSection
                    } else {
                        swapForm
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
    }

    // MARK: - Swap Form

    private var swapForm: some View {
        VStack(spacing: Spacing.sm) {
            fromCard
            swapDirectionButton
            toCard
            swapDetails
            reviewButton
        }
        .padding(.horizontal, Spacing.contentPadding)
        .mtrxFadeInFromBottom(isVisible: isVisible)
    }

    // MARK: - From Card

    private var fromCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("From")
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)

            MtrxCard(style: .standard) {
                VStack(spacing: Spacing.ms) {
                    HStack {
                        tokenSelectorButton(
                            token: fromToken,
                            showPicker: $showFromPicker
                        )
                        Spacer()
                        TextField("0.00", text: $fromAmountText)
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.labelPrimary)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        Text("Balance: \(formatBalance(fromToken.balance))")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)

                        Button {
                            MtrxHaptics.impact(.light)
                            fromAmountText = formatBalance(fromToken.balance)
                        } label: {
                            Text("MAX")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.accentPrimary)
                        }

                        Spacer()

                        if fromAmount > 0 {
                            Text(formatUSD(fromAmount * fromToken.priceUSD))
                                .font(.mtrxMonoSmall)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }

                    if fromAmount > fromToken.balance {
                        Text("Insufficient balance")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.statusError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if showFromPicker {
                tokenPickerList(
                    excluding: toTokenIndex,
                    selection: $fromTokenIndex,
                    showPicker: $showFromPicker
                )
                .transition(.mtrxScale)
            }
        }
    }

    // MARK: - Swap Direction Button

    private var swapDirectionButton: some View {
        HStack {
            Spacer()
            Button {
                MtrxHaptics.impact(.medium)
                withAnimation(Motion.springBouncy) {
                    swapRotation += 180
                    let temp = fromTokenIndex
                    fromTokenIndex = toTokenIndex
                    toTokenIndex = temp
                    fromAmountText = ""
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.surfaceCard)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(Color.accentPrimary.opacity(0.3), lineWidth: 1)
                        )

                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accentPrimary)
                        .rotationEffect(.degrees(swapRotation))
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, -Spacing.xs)
    }

    // MARK: - To Card

    private var toCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("To")
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)

            MtrxCard(style: .standard) {
                VStack(spacing: Spacing.ms) {
                    HStack {
                        tokenSelectorButton(
                            token: toToken,
                            showPicker: $showToPicker
                        )
                        Spacer()

                        if fromAmount > 0 {
                            Text(formatSwapAmount(toAmount))
                                .font(.mtrxMonoMedium)
                                .foregroundStyle(Color.labelPrimary)
                                .contentTransition(.numericText())
                        } else {
                            Text("0.00")
                                .font(.mtrxMonoMedium)
                                .foregroundStyle(Color.labelTertiary)
                        }
                    }

                    HStack {
                        Text("Balance: \(formatBalance(toToken.balance))")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()

                        if fromAmount > 0 {
                            Text(formatUSD(toAmount * toToken.priceUSD))
                                .font(.mtrxMonoSmall)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                }
            }

            if showToPicker {
                tokenPickerList(
                    excluding: fromTokenIndex,
                    selection: $toTokenIndex,
                    showPicker: $showToPicker
                )
                .transition(.mtrxScale)
            }
        }
    }

    // MARK: - Token Selector Button

    private func tokenSelectorButton(token: AppTokenBalance, showPicker: Binding<Bool>) -> some View {
        Button {
            MtrxHaptics.selection()
            withAnimation(Motion.springSnappy) {
                showPicker.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                MtrxAvatar(text: token.symbol, color: token.iconColor, size: 28)
                Text(token.symbol)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.labelTertiary)
            }
            .padding(.horizontal, Spacing.ms)
            .padding(.vertical, Spacing.sm)
            .background(Color.surfaceOverlay)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Token Picker List

    private func tokenPickerList(excluding: Int, selection: Binding<Int>, showPicker: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(walletManager.tokens.enumerated()), id: \.element.id) { index, token in
                if index != excluding {
                    Button {
                        MtrxHaptics.selection()
                        withAnimation(Motion.springSnappy) {
                            selection.wrappedValue = index
                            showPicker.wrappedValue = false
                            fromAmountText = ""
                        }
                    } label: {
                        HStack(spacing: Spacing.ms) {
                            MtrxAvatar(text: token.symbol, color: token.iconColor, size: 28)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(token.symbol)
                                    .font(.mtrxBodyBold)
                                    .foregroundStyle(Color.labelPrimary)
                                Text(token.name)
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelSecondary)
                            }

                            Spacer()

                            Text(formatBalance(token.balance))
                                .font(.mtrxMonoSmall)
                                .foregroundStyle(Color.labelSecondary)

                            if index == selection.wrappedValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.accentPrimary)
                            }
                        }
                        .padding(.vertical, Spacing.sm)
                        .padding(.horizontal, Spacing.ms)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }

    // MARK: - Swap Details

    private var swapDetails: some View {
        VStack(spacing: Spacing.ms) {
            // Exchange rate
            if fromAmount > 0 {
                HStack {
                    Text("Rate")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text("1 \(fromToken.symbol) = \(formatSwapAmount(exchangeRate)) \(toToken.symbol)")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                }
            }

            // Slippage
            slippageSelector

            // Price impact
            if fromAmount > 0 {
                HStack {
                    Text("Price Impact")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text(String(format: "%.2f%%", priceImpact))
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(priceImpact < 1 ? Color.priceUp : (priceImpact < 3 ? Color.statusWarning : Color.statusError))
                }

                // Minimum received
                HStack {
                    Text("Min. Received")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text("\(formatSwapAmount(minimumReceived)) \(toToken.symbol)")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                }
            }

            // Route
            HStack {
                Text("Route")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                Spacer()
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                    Text("Via Uniswap V3")
                        .font(.mtrxCaption1)
                }
                .foregroundStyle(Color.accentPrimary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Slippage Selector

    private var slippageSelector: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Slippage Tolerance")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)

            HStack(spacing: Spacing.sm) {
                ForEach(SlippageTolerance.allCases, id: \.self) { option in
                    Button {
                        MtrxHaptics.selection()
                        withAnimation(Motion.springSnappy) {
                            slippage = option
                            showCustomSlippage = option == .custom
                        }
                    } label: {
                        Text(option.label)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(slippage == option ? .white : Color.labelSecondary)
                            .padding(.horizontal, Spacing.ms)
                            .padding(.vertical, Spacing.chipVertical)
                            .background(slippage == option ? Color.accentPrimary : Color.surfaceOverlay)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if showCustomSlippage {
                HStack(spacing: Spacing.sm) {
                    TextField("1.0", text: $customSlippageText)
                        .font(.mtrxMono)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 60)
                    Text("%")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(.horizontal, Spacing.ms)
                .frame(height: 36)
                .background(Color.surfaceOverlay)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                .transition(.mtrxScale)
            }
        }
    }

    // MARK: - Review Button

    private var reviewButton: some View {
        Button {
            MtrxHaptics.impact(.medium)
            withAnimation(Motion.springDefault) {
                showConfirmation = true
            }
        } label: {
            Text("Review Swap")
        }
        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
        .disabled(!canSwap)
        .opacity(canSwap ? 1 : 0.5)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Confirmation Section

    private var confirmationSection: some View {
        VStack(spacing: Spacing.lg) {
            // Visual summary
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    VStack(spacing: Spacing.xs) {
                        MtrxAvatar(text: fromToken.symbol, color: fromToken.iconColor, size: Spacing.Size.avatarLarge)
                        Text(fromToken.symbol)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    VStack(spacing: 2) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.accentPrimary)
                    }

                    VStack(spacing: Spacing.xs) {
                        MtrxAvatar(text: toToken.symbol, color: toToken.iconColor, size: Spacing.Size.avatarLarge)
                        Text(toToken.symbol)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }

                Text("\(fromAmountText) \(fromToken.symbol)")
                    .font(.mtrxMonoMedium)
                    .foregroundStyle(Color.labelPrimary)

                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentPrimary)

                Text("\(formatSwapAmount(toAmount)) \(toToken.symbol)")
                    .font(.mtrxMonoMedium)
                    .foregroundStyle(Color.labelPrimary)
            }
            .padding(.horizontal, Spacing.contentPadding)

            // Detail card
            MtrxCard(style: .elevated) {
                VStack(spacing: Spacing.ms) {
                    confirmRow(label: "Rate", value: "1 \(fromToken.symbol) = \(formatSwapAmount(exchangeRate)) \(toToken.symbol)")
                    MtrxDivider()
                    confirmRow(label: "Slippage", value: String(format: "%.1f%%", effectiveSlippage))
                    MtrxDivider()
                    confirmRow(label: "Min. Received", value: "\(formatSwapAmount(minimumReceived)) \(toToken.symbol)")
                    MtrxDivider()
                    confirmRow(label: "Price Impact", value: String(format: "%.2f%%", priceImpact))
                    MtrxDivider()
                    confirmRow(label: "Network Fee", value: "$0.38")
                    MtrxDivider()
                    confirmRow(label: "Route", value: "Uniswap V3")
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            VStack(spacing: Spacing.ms) {
                Button {
                    MtrxHaptics.success()
                    dismiss()
                } label: {
                    Text("Confirm Swap")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))

                Button {
                    MtrxHaptics.impact(.light)
                    withAnimation(Motion.springDefault) {
                        showConfirmation = false
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

    private func confirmRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value)
                .font(.mtrxMonoSmall)
                .foregroundStyle(Color.labelPrimary)
        }
    }

    // MARK: - Formatters

    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = balance < 1 ? 6 : (balance < 100 ? 4 : 2)
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }

    private func formatSwapAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if value < 0.01 {
            formatter.maximumFractionDigits = 8
            formatter.minimumFractionDigits = 4
        } else if value < 1 {
            formatter.maximumFractionDigits = 6
            formatter.minimumFractionDigits = 4
        } else if value < 1000 {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Slippage Tolerance

enum SlippageTolerance: CaseIterable {
    case low, medium, high, custom

    var label: String {
        switch self {
        case .low: return "0.5%"
        case .medium: return "1%"
        case .high: return "3%"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Preview

#Preview {
    SwapView()
        .environmentObject(WalletManager())
        .preferredColorScheme(.dark)
}
