// YieldView.swift
// MTRX
//
// Yield aggregator — best opportunities ranked by APY, risk labels, one-tap deposit, auto-compound, active positions.

import SwiftUI

// MARK: - Data Models

struct YieldStrategy: Identifiable {
    let id: String
    let name: String
    let protocol_: String
    let token: String
    let apy: Double
    let tvl: Double
    let risk: YieldRisk
    let autoCompound: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        protocol_: String,
        token: String,
        apy: Double,
        tvl: Double,
        risk: YieldRisk,
        autoCompound: Bool = false
    ) {
        self.id = id
        self.name = name
        self.protocol_ = protocol_
        self.token = token
        self.apy = apy
        self.tvl = tvl
        self.risk = risk
        self.autoCompound = autoCompound
    }
}

enum YieldRisk: String {
    case conservative = "Conservative"
    case moderate = "Moderate"
    case aggressive = "Aggressive"

    var color: Color {
        switch self {
        case .conservative: return .statusSuccess
        case .moderate: return .statusWarning
        case .aggressive: return .statusError
        }
    }
}

struct YieldPosition: Identifiable {
    let id: String
    let strategyName: String
    let token: String
    let deposited: Double
    let currentValue: Double
    let earned: Double
    let apy: Double
    let autoCompoundEnabled: Bool

    init(
        id: String = UUID().uuidString,
        strategyName: String,
        token: String,
        deposited: Double,
        currentValue: Double,
        earned: Double,
        apy: Double,
        autoCompoundEnabled: Bool = false
    ) {
        self.id = id
        self.strategyName = strategyName
        self.token = token
        self.deposited = deposited
        self.currentValue = currentValue
        self.earned = earned
        self.apy = apy
        self.autoCompoundEnabled = autoCompoundEnabled
    }
}

// MARK: - View Model

@MainActor
class YieldViewModel: ObservableObject {
    @Published var strategies: [YieldStrategy] = []
    @Published var positions: [YieldPosition] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showDepositSheet: Bool = false
    @Published var selectedStrategy: YieldStrategy?
    @Published var depositAmount: String = ""
    @Published var autoCompoundToggle: Bool = true
    @Published var isDepositing: Bool = false
    @Published var isDemo: Bool = false

    var sortedStrategies: [YieldStrategy] {
        strategies.sorted { $0.apy > $1.apy }
    }

    private static func mapRisk(_ raw: String) -> YieldRisk {
        switch raw.lowercased() {
        case "low", "conservative": return .conservative
        case "high", "aggressive": return .aggressive
        default: return .moderate
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live yield strategies from YieldService when configured; else demo.
        // The service exposes opportunities only (no per-wallet positions endpoint),
        // so positions stay empty when live until that's available.
        if PendingCredentials.isBackendConfigured {
            do {
                let live = try await YieldService.shared.getYieldOpportunities()
                strategies = live.map { o in
                    YieldStrategy(
                        id: o.strategyId, name: o.name, protocol_: o.protocolName,
                        token: o.token, apy: o.apy, tvl: o.tvl,
                        risk: Self.mapRisk(o.riskLevel), autoCompound: o.isAutoCompound
                    )
                }
                positions = []
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live yield data unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(700))
            strategies = YieldViewModel.sampleStrategies
            positions = YieldViewModel.samplePositions
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load yield opportunities."
            isLoading = false
        }
    }

    func deposit() async {
        // Honest failure: no real yield-deposit path is wired. Do NOT dismiss/clear as if
        // it worked — nothing was deposited.
        errorMessage = "Depositing isn't available in this build yet. Nothing was deposited."
    }

    static let sampleStrategies: [YieldStrategy] = [
        YieldStrategy(name: "USDC Lending", protocol_: "Aave V3", token: "USDC", apy: 5.8, tvl: 890_000_000, risk: .conservative),
        YieldStrategy(name: "ETH-USDC LP", protocol_: "Uniswap V3", token: "ETH/USDC", apy: 12.4, tvl: 84_500_000, risk: .moderate),
        YieldStrategy(name: "stETH Yield", protocol_: "Lido", token: "stETH", apy: 3.8, tvl: 12_400_000_000, risk: .conservative, autoCompound: true),
        YieldStrategy(name: "LINK Staking", protocol_: "Chainlink", token: "LINK", apy: 5.2, tvl: 18_000_000, risk: .conservative),
        YieldStrategy(name: "Leveraged ETH", protocol_: "Morpho", token: "ETH", apy: 18.2, tvl: 24_000_000, risk: .aggressive),
        YieldStrategy(name: "DAI Savings", protocol_: "Maker", token: "DAI", apy: 8.0, tvl: 1_200_000_000, risk: .conservative),
        YieldStrategy(name: "WBTC-ETH LP", protocol_: "Curve", token: "WBTC/ETH", apy: 9.6, tvl: 156_000_000, risk: .moderate)
    ]

    static let samplePositions: [YieldPosition] = [
        YieldPosition(strategyName: "USDC Lending", token: "USDC", deposited: 5000, currentValue: 5142.30, earned: 142.30, apy: 5.8, autoCompoundEnabled: true),
        YieldPosition(strategyName: "stETH Yield", token: "stETH", deposited: 1.5, currentValue: 1.518, earned: 0.018, apy: 3.8, autoCompoundEnabled: true)
    ]
}

// MARK: - Yield View

struct YieldView: View {
    @StateObject private var viewModel = YieldViewModel()

    // MARK: - Body

    var body: some View { _regulatedBody.mvpGated() }

    @ViewBuilder private var _regulatedBody: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.strategies.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.strategies.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    yieldContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Yield")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showDepositSheet) {
                depositSheet
            }
        }
    }

    // MARK: - Content

    private var yieldContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                if !viewModel.positions.isEmpty {
                    activePositionsSection
                }
                opportunitiesSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Active Positions

    private var activePositionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Active Positions")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.positions) { position in
                MtrxCard(style: .glass) {
                    VStack(spacing: Spacing.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(position.strategyName)
                                    .font(.mtrxBodyBold)
                                    .foregroundStyle(Color.labelPrimary)
                                Text(String(format: "%.1f%% APY", position.apy))
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.priceUp)
                            }
                            Spacer()
                            if position.autoCompoundEnabled {
                                MtrxBadge(text: "Auto-compound", style: .accent)
                            }
                        }

                        MtrxDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Deposited")
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelTertiary)
                                Text(formatTokenAmount(position.deposited, token: position.token))
                                    .font(.mtrxMono)
                                    .foregroundStyle(Color.labelPrimary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: Spacing.xs) {
                                Text("Earned")
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelTertiary)
                                Text(formatTokenAmount(position.earned, token: position.token, prefix: "+"))
                                    .font(.mtrxMono)
                                    .foregroundStyle(Color.priceUp)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Opportunities Section

    private var opportunitiesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Best Opportunities")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.sortedStrategies) { strategy in
                strategyRow(strategy)
            }
        }
    }

    private func strategyRow(_ strategy: YieldStrategy) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.ms) {
                HStack(spacing: Spacing.ms) {
                    MtrxAvatar(text: strategy.token, color: .accentPrimary, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(strategy.name)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(strategy.protocol_)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f%%", strategy.apy))
                            .font(.mtrxHeadlineTabular)
                            .foregroundStyle(Color.priceUp)
                        Text("APY")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                HStack {
                    // Risk label
                    MtrxBadge(
                        text: strategy.risk.rawValue,
                        style: riskBadgeStyle(strategy.risk)
                    )

                    if strategy.autoCompound {
                        MtrxBadge(text: "Auto-compound", style: .accent)
                    }

                    Spacer()

                    Text(formatCompact(strategy.tvl))
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Text("TVL")
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }

                Button {
                    viewModel.selectedStrategy = strategy
                    viewModel.autoCompoundToggle = strategy.autoCompound
                    viewModel.showDepositSheet = true
                } label: {
                    Text("Deposit")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact, fullWidth: true))
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Deposit Sheet

    private var depositSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                MtrxSheetHeader(
                    title: "Deposit",
                    subtitle: viewModel.selectedStrategy?.name
                ) {
                    viewModel.showDepositSheet = false
                }

                if let strategy = viewModel.selectedStrategy {
                    VStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Amount")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)
                            MtrxTextField(
                                placeholder: "0.00 \(strategy.token)",
                                text: $viewModel.depositAmount,
                                keyboardType: .decimalPad
                            )
                        }

                        MtrxCard(style: .standard) {
                            VStack(spacing: Spacing.ms) {
                                HStack {
                                    Text("Strategy")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                    Spacer()
                                    Text(strategy.name)
                                        .font(.mtrxCallout)
                                        .foregroundStyle(Color.labelPrimary)
                                }
                                MtrxDivider()
                                HStack {
                                    Text("APY")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                    Spacer()
                                    Text(String(format: "%.1f%%", strategy.apy))
                                        .font(.mtrxMonoSmall)
                                        .foregroundStyle(Color.priceUp)
                                }
                                MtrxDivider()
                                HStack {
                                    Text("Risk")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                    Spacer()
                                    MtrxBadge(
                                        text: strategy.risk.rawValue,
                                        style: riskBadgeStyle(strategy.risk)
                                    )
                                }
                                MtrxDivider()
                                Toggle(isOn: $viewModel.autoCompoundToggle) {
                                    Text("Auto-compound")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                }
                                .tint(Color.accentPrimary)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                }

                Spacer()

                Button {
                    Task { await viewModel.deposit() }
                } label: {
                    Text(viewModel.isDepositing ? "Depositing..." : "Confirm Deposit")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .primary,
                    size: .large,
                    isLoading: viewModel.isDepositing,
                    fullWidth: true
                ))
                .disabled(viewModel.depositAmount.isEmpty || viewModel.isDepositing)
                .opacity(viewModel.depositAmount.isEmpty ? 0.5 : 1)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

    private func riskBadgeStyle(_ risk: YieldRisk) -> MtrxBadge.BadgeStyle {
        switch risk {
        case .conservative: return .success
        case .moderate: return .warning
        case .aggressive: return .error
        }
    }

    private func formatTokenAmount(_ amount: Double, token: String, prefix: String = "") -> String {
        if amount >= 1000 {
            return String(format: "%@%.2f %@", prefix, amount, token)
        } else if amount >= 1 {
            return String(format: "%@%.4f %@", prefix, amount, token)
        } else {
            return String(format: "%@%.6f %@", prefix, amount, token)
        }
    }

    private func formatCompact(_ value: Double) -> String {
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
    YieldView()
        .preferredColorScheme(.dark)
}
