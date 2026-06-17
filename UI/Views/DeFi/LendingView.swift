// LendingView.swift
// MTRX
//
// DeFi lending markets — supply, borrow, positions, health factor, and action flows.

import SwiftUI

// MARK: - Data Models

struct LendingMarketDisplay: Identifiable {
    let id: String
    let token: String
    let symbol: String
    let supplyAPY: Double
    let borrowAPR: Double
    let totalSupply: Double
    let totalBorrow: Double

    init(
        id: String = UUID().uuidString,
        token: String,
        symbol: String,
        supplyAPY: Double,
        borrowAPR: Double,
        totalSupply: Double,
        totalBorrow: Double
    ) {
        self.id = id
        self.token = token
        self.symbol = symbol
        self.supplyAPY = supplyAPY
        self.borrowAPR = borrowAPR
        self.totalSupply = totalSupply
        self.totalBorrow = totalBorrow
    }
}

struct LendingPositionDisplay {
    let suppliedAmount: Double
    let suppliedToken: String
    let earnedInterest: Double
    let borrowedAmount: Double
    let borrowedToken: String
    let accruedInterest: Double
    let healthFactor: Double
}

// MARK: - View Model

@MainActor
class LendingViewModel: ObservableObject {
    @Published var markets: [LendingMarketDisplay] = []
    @Published var position: LendingPositionDisplay?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedTab: LendingTab = .supply
    @Published var showActionSheet: Bool = false
    @Published var actionType: LendingAction?
    @Published var actionMarket: LendingMarketDisplay?
    @Published var actionAmount: String = ""
    @Published var isSubmitting: Bool = false
    @Published var isDemo: Bool = false

    enum LendingTab: String, CaseIterable {
        case supply = "Supply"
        case borrow = "Borrow"
    }

    enum LendingAction: String {
        case supply = "Supply"
        case withdraw = "Withdraw"
        case borrow = "Borrow"
        case repay = "Repay"
    }

    var healthLabel: String {
        guard let hf = position?.healthFactor else { return "N/A" }
        switch hf {
        case 3.0...: return "Very Safe"
        case 2.0..<3.0: return "Safe"
        case 1.5..<2.0: return "Caution"
        default: return "At Risk"
        }
    }

    var healthColor: Color {
        guard let hf = position?.healthFactor else { return .labelTertiary }
        switch hf {
        case 3.0...: return .healthGood
        case 2.0..<3.0: return .statusInfo
        case 1.5..<2.0: return .healthModerate
        default: return .healthCritical
        }
    }

    var healthProgress: Double {
        guard let hf = position?.healthFactor else { return 0 }
        return min(hf / 4.0, 1.0)
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live markets from LendingService when configured; else demo.
        if PendingCredentials.isBackendConfigured {
            do {
                let live = try await LendingService.shared.getLendingMarkets()
                markets = live.map { m in
                    LendingMarketDisplay(
                        id: m.id.uuidString, token: m.token, symbol: m.symbol,
                        supplyAPY: m.supplyAPY, borrowAPR: m.borrowAPR,
                        totalSupply: m.totalSupply, totalBorrow: m.totalBorrow
                    )
                }
                // A user position needs a signed-in wallet; left nil (no open
                // position) when live until that's wired.
                position = nil
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live lending markets unavailable — showing demo."
            }
        }

        markets = LendingViewModel.sampleMarkets
        position = LendingViewModel.samplePosition
        isDemo = true
        isLoading = false
    }

    func beginAction(_ action: LendingAction, market: LendingMarketDisplay) {
        actionType = action
        actionMarket = market
        actionAmount = ""
        showActionSheet = true
    }

    func submitAction() async {
        guard let _ = actionType, let _ = actionMarket else { return }
        isSubmitting = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            isSubmitting = false
            showActionSheet = false
        } catch {
            isSubmitting = false
        }
    }

    static let sampleMarkets: [LendingMarketDisplay] = [
        LendingMarketDisplay(token: "Ethereum", symbol: "ETH", supplyAPY: 3.2, borrowAPR: 4.8, totalSupply: 245_000_000, totalBorrow: 128_000_000),
        LendingMarketDisplay(token: "USD Coin", symbol: "USDC", supplyAPY: 5.8, borrowAPR: 7.2, totalSupply: 890_000_000, totalBorrow: 612_000_000),
        LendingMarketDisplay(token: "Wrapped Bitcoin", symbol: "WBTC", supplyAPY: 1.4, borrowAPR: 3.6, totalSupply: 42_000_000, totalBorrow: 18_000_000),
        LendingMarketDisplay(token: "DAI", symbol: "DAI", supplyAPY: 5.1, borrowAPR: 6.9, totalSupply: 320_000_000, totalBorrow: 198_000_000),
        LendingMarketDisplay(token: "Chainlink", symbol: "LINK", supplyAPY: 2.1, borrowAPR: 5.5, totalSupply: 56_000_000, totalBorrow: 22_000_000)
    ]

    static let samplePosition = LendingPositionDisplay(
        suppliedAmount: 2.5,
        suppliedToken: "ETH",
        earnedInterest: 0.018,
        borrowedAmount: 1200,
        borrowedToken: "USDC",
        accruedInterest: 14.30,
        healthFactor: 2.85
    )
}

// MARK: - Lending View

struct LendingView: View {
    @StateObject private var viewModel = LendingViewModel()

    // MARK: - Body

    var body: some View { _regulatedBody.mvpGated() }

    @ViewBuilder private var _regulatedBody: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.markets.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.markets.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    lendingContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Lending")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showActionSheet) {
                actionSheet
            }
        }
    }

    // MARK: - Content

    private var lendingContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                if viewModel.position != nil {
                    positionCard
                }
                tabSelector
                marketsList
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Position Card

    private var positionCard: some View {
        MtrxCard(style: .glass) {
            VStack(spacing: Spacing.md) {
                Text("Your Position")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                MtrxDivider()

                if let pos = viewModel.position {
                    HStack(spacing: Spacing.xl) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Supplied")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                            Text(String(format: "%.4f %@", pos.suppliedAmount, pos.suppliedToken))
                                .font(.mtrxMono)
                                .foregroundStyle(Color.labelPrimary)
                            Text(String(format: "+%.4f earned", pos.earnedInterest))
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.priceUp)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: Spacing.xs) {
                            Text("Borrowed")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                            Text(String(format: "%.2f %@", pos.borrowedAmount, pos.borrowedToken))
                                .font(.mtrxMono)
                                .foregroundStyle(Color.labelPrimary)
                            Text(String(format: "+%.2f owed", pos.accruedInterest))
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.statusWarning)
                        }
                    }

                    MtrxDivider()

                    healthFactorBar
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Health Factor Bar

    private var healthFactorBar: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Text("Health Factor")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                Spacer()
                Text(viewModel.healthLabel)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(viewModel.healthColor)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.surfaceOverlay)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(viewModel.healthColor)
                        .frame(width: geometry.size.width * viewModel.healthProgress, height: 8)
                        .animation(Motion.springDefault, value: viewModel.healthProgress)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(LendingViewModel.LendingTab.allCases, id: \.self) { tab in
                Button {
                    MtrxHaptics.selection()
                    withAnimation(Motion.springSnappy) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.mtrxCalloutBold)
                        .foregroundStyle(viewModel.selectedTab == tab ? Color.accentPrimary : Color.labelSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.ms)
                        .overlay(alignment: .bottom) {
                            if viewModel.selectedTab == tab {
                                Rectangle()
                                    .fill(Color.accentPrimary)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Markets List

    private var marketsList: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(viewModel.markets) { market in
                marketRow(market)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    private func marketRow(_ market: LendingMarketDisplay) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.ms) {
                HStack(spacing: Spacing.ms) {
                    MtrxAvatar(text: market.symbol, color: .accentPrimary, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(market.token)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(market.symbol)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if viewModel.selectedTab == .supply {
                            Text(String(format: "%.1f%% APY", market.supplyAPY))
                                .font(.mtrxHeadlineTabular)
                                .foregroundStyle(Color.priceUp)
                        } else {
                            Text(String(format: "%.1f%% APR", market.borrowAPR))
                                .font(.mtrxHeadlineTabular)
                                .foregroundStyle(Color.statusWarning)
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Supply")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(formatLargeNumber(market.totalSupply))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total Borrow")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(formatLargeNumber(market.totalBorrow))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    if viewModel.selectedTab == .supply {
                        Button {
                            viewModel.beginAction(.supply, market: market)
                        } label: {
                            Text("Supply")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact, fullWidth: true))

                        Button {
                            viewModel.beginAction(.withdraw, market: market)
                        } label: {
                            Text("Withdraw")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact, fullWidth: true))
                    } else {
                        Button {
                            viewModel.beginAction(.borrow, market: market)
                        } label: {
                            Text("Borrow")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact, fullWidth: true))

                        Button {
                            viewModel.beginAction(.repay, market: market)
                        } label: {
                            Text("Repay")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact, fullWidth: true))
                    }
                }
            }
        }
    }

    // MARK: - Action Sheet

    private var actionSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                MtrxSheetHeader(
                    title: viewModel.actionType?.rawValue ?? "Action",
                    subtitle: viewModel.actionMarket?.token
                ) {
                    viewModel.showActionSheet = false
                }

                if let market = viewModel.actionMarket {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Amount")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        MtrxTextField(
                            placeholder: "0.00",
                            text: $viewModel.actionAmount,
                            keyboardType: .decimalPad
                        )
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    MtrxCard(style: .standard) {
                        VStack(spacing: Spacing.ms) {
                            HStack {
                                Text("Token")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                                Spacer()
                                Text(market.symbol)
                                    .font(.mtrxMonoSmall)
                                    .foregroundStyle(Color.labelPrimary)
                            }
                            MtrxDivider()
                            HStack {
                                Text(viewModel.selectedTab == .supply ? "APY" : "APR")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                                Spacer()
                                Text(String(format: "%.1f%%", viewModel.selectedTab == .supply ? market.supplyAPY : market.borrowAPR))
                                    .font(.mtrxMonoSmall)
                                    .foregroundStyle(Color.labelPrimary)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                }

                Spacer()

                Button {
                    Task { await viewModel.submitAction() }
                } label: {
                    Text(viewModel.isSubmitting ? "Processing..." : "Confirm \(viewModel.actionType?.rawValue ?? "")")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .primary,
                    size: .large,
                    isLoading: viewModel.isSubmitting,
                    fullWidth: true
                ))
                .disabled(viewModel.actionAmount.isEmpty || viewModel.isSubmitting)
                .opacity(viewModel.actionAmount.isEmpty ? 0.5 : 1)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "$%.1fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
}

// MARK: - Preview

#Preview {
    LendingView()
        .preferredColorScheme(.dark)
}
