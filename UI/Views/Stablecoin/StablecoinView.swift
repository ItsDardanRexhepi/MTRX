// StablecoinView.swift
// MTRX
//
// Stablecoin management — balances, yield, convert, depeg monitor with color-coded status.

import SwiftUI

// MARK: - Data Models

struct StablecoinItem: Identifiable {
    let id = UUID()
    let symbol: String
    let balance: String
    let usdValue: String
    let yieldAPY: String?
}

struct PegItem: Identifiable {
    let id = UUID()
    let symbol: String
    let currentPrice: String
    let deviation: String
    let status: String
}

// MARK: - View Model

@MainActor
class StablecoinViewModel: ObservableObject {
    @Published var balances: [StablecoinItem] = []
    @Published var pegStatuses: [PegItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Convert form
    @Published var convertAmount: String = ""
    @Published var fromToken: String = "USDC"
    @Published var toToken: String = "DAI"
    @Published var isConverting: Bool = false
    @Published var isDemo: Bool = false

    var availableTokens: [String] {
        balances.map(\.symbol)
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live peg status (global) + balances (per-wallet) from StablecoinService
        // when configured; else demo.
        if PendingCredentials.isBackendConfigured {
            do {
                let pegs = try await StablecoinService.shared.getPegStatus()
                pegStatuses = pegs.map {
                    PegItem(
                        symbol: $0.symbol,
                        currentPrice: String(format: "$%.4f", $0.currentPrice),
                        deviation: String(format: "%+.2f%%", $0.pegDeviation),
                        status: $0.status
                    )
                }
                if let address = MtrxSession.walletAddress {
                    let live = try await StablecoinService.shared.getStablecoinBalances(address: address)
                    balances = live.map {
                        StablecoinItem(
                            symbol: $0.symbol,
                            balance: String(format: "%.2f", $0.balance),
                            usdValue: String(format: "$%.2f", $0.usdValue),
                            yieldAPY: $0.yieldAPY.map { String(format: "%.1f%%", $0) }
                        )
                    }
                } else {
                    // No signed-in wallet yet: no balances to show (peg status is global).
                    balances = []
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live stablecoin data unavailable — showing demo."
            }
        }

        balances = StablecoinViewModel.sampleBalances
        pegStatuses = StablecoinViewModel.samplePegStatuses
        isDemo = true
        isLoading = false
    }

    func convert() async {
        guard !convertAmount.isEmpty else { return }
        isConverting = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            isConverting = false
            convertAmount = ""
        } catch {
            isConverting = false
        }
    }

    func swapDirection() {
        let temp = fromToken
        fromToken = toToken
        toToken = temp
    }

    static let sampleBalances: [StablecoinItem] = [
        StablecoinItem(symbol: "USDC", balance: "12,450.00", usdValue: "$12,450.00", yieldAPY: "4.2%"),
        StablecoinItem(symbol: "DAI", balance: "8,200.50", usdValue: "$8,200.50", yieldAPY: "3.8%"),
        StablecoinItem(symbol: "USDT", balance: "5,100.00", usdValue: "$5,100.00", yieldAPY: nil),
        StablecoinItem(symbol: "FRAX", balance: "2,340.75", usdValue: "$2,340.75", yieldAPY: "5.1%"),
        StablecoinItem(symbol: "GHO", balance: "1,000.00", usdValue: "$1,000.00", yieldAPY: "6.3%")
    ]

    static let samplePegStatuses: [PegItem] = [
        PegItem(symbol: "USDC", currentPrice: "$1.0001", deviation: "+0.01%", status: "Stable"),
        PegItem(symbol: "DAI", currentPrice: "$0.9998", deviation: "-0.02%", status: "Stable"),
        PegItem(symbol: "USDT", currentPrice: "$0.9994", deviation: "-0.06%", status: "Stable"),
        PegItem(symbol: "FRAX", currentPrice: "$0.9971", deviation: "-0.29%", status: "Warning"),
        PegItem(symbol: "GHO", currentPrice: "$0.9842", deviation: "-1.58%", status: "Depegged")
    ]
}

// MARK: - Stablecoin View

struct StablecoinView: View {
    @StateObject private var viewModel = StablecoinViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.balances.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.balances.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    stablecoinContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Stablecoins")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Content

    private var stablecoinContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                balancesSection
                convertSection
                depegMonitorSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Balances Section

    private var balancesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Balances")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.balances) { coin in
                balanceCard(coin)
            }
        }
    }

    private func balanceCard(_ coin: StablecoinItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                MtrxAvatar(text: coin.symbol, color: .accentPrimary, size: 40)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(coin.symbol)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text(coin.usdValue)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text(coin.balance)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                    if let apy = coin.yieldAPY {
                        HStack(spacing: 2) {
                            Image(systemName: Symbols.trendUp)
                                .font(.system(size: 10))
                            Text(apy)
                                .font(.mtrxCaptionBold)
                        }
                        .foregroundStyle(Color.priceUp)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Convert Section

    private var convertSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Convert")
                .padding(.horizontal, Spacing.contentPadding)

            MtrxCard(style: .glass, accentEdge: .leading) {
                VStack(spacing: Spacing.md) {
                    // From
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("From")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        HStack(spacing: Spacing.sm) {
                            Picker("From", selection: $viewModel.fromToken) {
                                ForEach(viewModel.availableTokens, id: \.self) { token in
                                    Text(token).tag(token)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.accentPrimary)

                            MtrxTextField(
                                placeholder: "0.00",
                                text: $viewModel.convertAmount,
                                keyboardType: .decimalPad
                            )
                        }
                    }

                    // Swap button
                    HStack {
                        Spacer()
                        Button {
                            viewModel.swapDirection()
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentPrimary)
                                .frame(width: 36, height: 36)
                                .background(Color.surfaceOverlay)
                                .clipShape(Circle())
                                .accessibilityLabel("Swap direction")
                        }
                        Spacer()
                    }

                    // To
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("To")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        HStack(spacing: Spacing.sm) {
                            Picker("To", selection: $viewModel.toToken) {
                                ForEach(viewModel.availableTokens, id: \.self) { token in
                                    Text(token).tag(token)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.accentPrimary)

                            Text(viewModel.convertAmount.isEmpty ? "0.00" : viewModel.convertAmount)
                                .font(.mtrxMono)
                                .foregroundStyle(Color.labelSecondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    Button {
                        Task { await viewModel.convert() }
                    } label: {
                        Text(viewModel.isConverting ? "Converting..." : "Convert")
                    }
                    .buttonStyle(MtrxButtonStyle(
                        variant: .primary,
                        size: .large,
                        isLoading: viewModel.isConverting,
                        fullWidth: true
                    ))
                    .disabled(viewModel.convertAmount.isEmpty || viewModel.isConverting)
                    .opacity(viewModel.convertAmount.isEmpty ? 0.5 : 1)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Depeg Monitor

    private var depegMonitorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Depeg Monitor")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.pegStatuses) { peg in
                pegStatusCard(peg)
            }
        }
    }

    private func pegStatusCard(_ peg: PegItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                Circle()
                    .fill(pegColor(for: peg.status))
                    .frame(width: 10, height: 10)

                Text(peg.symbol)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(peg.currentPrice)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                    Text(peg.deviation)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(pegColor(for: peg.status))
                }

                MtrxBadge(text: peg.status, style: pegBadgeStyle(for: peg.status))
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Helpers

    private func pegColor(for status: String) -> Color {
        switch status {
        case "Stable": return .statusSuccess
        case "Warning": return .statusWarning
        case "Depegged": return .statusError
        default: return .labelTertiary
        }
    }

    private func pegBadgeStyle(for status: String) -> MtrxBadge.BadgeStyle {
        switch status {
        case "Stable": return .success
        case "Warning": return .warning
        case "Depegged": return .error
        default: return .neutral
        }
    }
}

// MARK: - Preview

#Preview {
    StablecoinView()
        .preferredColorScheme(.dark)
}
