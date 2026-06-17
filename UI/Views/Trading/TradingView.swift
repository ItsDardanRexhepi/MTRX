// TradingView.swift
// MTRX
//
// Perpetual trading interface — market list, long/short picker, leverage slider, size input,
// Morpheus warning at high leverage, open positions with colored PnL.

import SwiftUI

// MARK: - Data Models

struct PerpMarketItem: Identifiable {
    let id = UUID()
    let name: String
    let indexPrice: String
    let fundingRate: String
}

struct PositionItem: Identifiable {
    let id = UUID()
    let market: String
    let side: String
    let size: String
    let entryPrice: String
    let pnl: String
    let liquidationPrice: String
}

// MARK: - View Model

@MainActor
class TradingViewModel: ObservableObject {
    @Published var markets: [PerpMarketItem] = []
    @Published var positions: [PositionItem] = []
    @Published var selectedSide: String = "Long"
    @Published var leverage: Double = 1
    @Published var size: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isDemo: Bool = false

    let sides = ["Long", "Short"]

    var leverageText: String {
        "\(Int(leverage))x"
    }

    var morpheusWarning: String? {
        guard leverage > 5 else { return nil }
        if leverage > 15 {
            return "You take the red pill, you stay in Wonderland, and I show you how deep the rabbit hole goes. Liquidation risk is extreme."
        } else if leverage > 10 {
            return "I can only show you the door. You're the one that has to walk through it. High leverage magnifies both gains and losses."
        } else {
            return "Remember, all I'm offering is the truth. Nothing more. Elevated leverage increases liquidation risk significantly."
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live perps from DerivativesService when configured; markets are global,
        // positions are per-wallet. Else demo.
        if PendingCredentials.isBackendConfigured {
            do {
                let liveMarkets = try await DerivativesService.shared.getMarkets()
                markets = liveMarkets.map { m in
                    PerpMarketItem(
                        name: m.name,
                        indexPrice: "$" + m.indexPrice.formatted(.number.precision(.fractionLength(2))),
                        fundingRate: String(format: "%+.4f%%", m.fundingRate)
                    )
                }
                if let address = MtrxSession.walletAddress {
                    let livePositions = try await DerivativesService.shared.getUserPositions(address: address)
                    positions = livePositions.map { p in
                        PositionItem(
                            market: p.market,
                            side: p.side.rawValue.capitalized,
                            size: p.size.formatted(.number.precision(.fractionLength(4))),
                            entryPrice: "$" + p.entryPrice.formatted(.number.precision(.fractionLength(2))),
                            pnl: (p.unrealizedPnl >= 0 ? "+$" : "-$") + abs(p.unrealizedPnl).formatted(.number.precision(.fractionLength(2))),
                            liquidationPrice: "$" + p.liquidationPrice.formatted(.number.precision(.fractionLength(2)))
                        )
                    }
                } else {
                    positions = []
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live markets unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(600))
            markets = TradingViewModel.sampleMarkets
            positions = TradingViewModel.samplePositions
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load trading data."
            isLoading = false
        }
    }

    static let sampleMarkets: [PerpMarketItem] = [
        PerpMarketItem(name: "ETH-PERP", indexPrice: "$3,361.20", fundingRate: "+0.0042%"),
        PerpMarketItem(name: "BTC-PERP", indexPrice: "$67,842.50", fundingRate: "+0.0031%"),
        PerpMarketItem(name: "SOL-PERP", indexPrice: "$148.75", fundingRate: "-0.0015%"),
        PerpMarketItem(name: "ARB-PERP", indexPrice: "$1.24", fundingRate: "+0.0058%"),
        PerpMarketItem(name: "LINK-PERP", indexPrice: "$14.82", fundingRate: "+0.0022%")
    ]

    static let samplePositions: [PositionItem] = [
        PositionItem(market: "ETH-PERP", side: "Long", size: "2.5 ETH", entryPrice: "$3,280.00", pnl: "+$202.50", liquidationPrice: "$2,870.00"),
        PositionItem(market: "BTC-PERP", side: "Short", size: "0.1 BTC", entryPrice: "$68,200.00", pnl: "-$35.75", liquidationPrice: "$72,100.00")
    ]
}

// MARK: - Trading View

struct TradingView: View {
    @StateObject private var viewModel = TradingViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.markets.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.markets.isEmpty {
                    errorState(message: error)
                } else {
                    tradingContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Trading")
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

    private var tradingContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                marketsSection
                orderSection
                if !viewModel.positions.isEmpty {
                    positionsSection
                }
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Markets Section

    private var marketsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Perpetual Markets")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.markets) { market in
                marketRow(market)
            }
        }
    }

    private func marketRow(_ market: PerpMarketItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(market.name)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text("Funding: \(market.fundingRate)")
                        .font(.mtrxCaption2)
                        .foregroundStyle(market.fundingRate.hasPrefix("-") ? Color.priceDown : Color.priceUp)
                }

                Spacer()

                Text(market.indexPrice)
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color.labelPrimary)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Order Section

    private var orderSection: some View {
        MtrxCard(style: .glass, accentEdge: .leading) {
            VStack(spacing: Spacing.md) {
                Text("New Position")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Long / Short Picker
                Picker("Side", selection: $viewModel.selectedSide) {
                    ForEach(viewModel.sides, id: \.self) { side in
                        Text(side).tag(side)
                    }
                }
                .pickerStyle(.segmented)

                // Leverage Slider
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text("Leverage")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text(viewModel.leverageText)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(leverageColor)
                    }

                    Slider(value: $viewModel.leverage, in: 1...20, step: 1)
                        .tint(leverageColor)

                    HStack {
                        Text("1x")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Spacer()
                        Text("20x")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                // Morpheus Warning
                if let warning = viewModel.morpheusWarning {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.statusWarning)
                        Text(warning)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.statusWarning)
                            .italic()
                    }
                    .padding(Spacing.sm)
                    .background(Color.statusWarning.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }

                // Size Input
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Size")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)

                    HStack {
                        TextField("0.00", text: $viewModel.size)
                            .font(.mtrxMono)
                            .keyboardType(.decimalPad)
                        Text("USD")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(Spacing.ms)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }

                // Place Order Button
                Button {
                    // Place order action
                } label: {
                    Text(viewModel.selectedSide == "Long" ? "Open Long" : "Open Short")
                        .font(.mtrxBodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.ms)
                        .background(viewModel.selectedSide == "Long" ? Color.priceUp : Color.priceDown)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
                .disabled(viewModel.size.isEmpty)
                .opacity(viewModel.size.isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Positions Section

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Open Positions")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.positions) { position in
                positionCard(position)
            }
        }
    }

    private func positionCard(_ position: PositionItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(position.market)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(position.side)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(position.side == "Long" ? Color.priceUp : Color.priceDown)
                    }

                    Spacer()

                    Text(position.pnl)
                        .font(.mtrxHeadlineTabular)
                        .foregroundStyle(position.pnl.hasPrefix("+") ? Color.priceUp : Color.priceDown)
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Size")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(position.size)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    Spacer()

                    VStack(spacing: Spacing.xs) {
                        Text("Entry")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(position.entryPrice)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Liq. Price")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(position.liquidationPrice)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.statusError)
                    }
                }

                Button {
                    // Close position
                } label: {
                    Text("Close Position")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.statusError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.statusError.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.statusWarning)
            Text(message)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.675, blue: 0.694))
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var leverageColor: Color {
        if viewModel.leverage <= 5 {
            return Color(red: 0.0, green: 0.675, blue: 0.694)
        } else if viewModel.leverage <= 10 {
            return .statusWarning
        } else {
            return .statusError
        }
    }
}

// MARK: - Preview

#Preview {
    TradingView()
        .preferredColorScheme(.dark)
}
