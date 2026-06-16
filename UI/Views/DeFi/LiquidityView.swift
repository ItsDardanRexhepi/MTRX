// LiquidityView.swift
// MTRX
//
// Liquidity pools — pool list with APR/TVL/volume, LP positions, add/remove liquidity, impermanent loss.

import SwiftUI

// MARK: - Data Models

struct LiquidityPool: Identifiable {
    let id: String
    let tokenA: String
    let tokenB: String
    let apr: Double
    let tvl: Double
    let volume24h: Double
    let userShare: Double?
    let earnedFees: Double?

    init(
        id: String = UUID().uuidString,
        tokenA: String,
        tokenB: String,
        apr: Double,
        tvl: Double,
        volume24h: Double,
        userShare: Double? = nil,
        earnedFees: Double? = nil
    ) {
        self.id = id
        self.tokenA = tokenA
        self.tokenB = tokenB
        self.apr = apr
        self.tvl = tvl
        self.volume24h = volume24h
        self.userShare = userShare
        self.earnedFees = earnedFees
    }

    var pairLabel: String { "\(tokenA)/\(tokenB)" }
}

// MARK: - View Model

@MainActor
class LiquidityViewModel: ObservableObject {
    @Published var pools: [LiquidityPool] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showAddLiquidity: Bool = false
    @Published var showRemoveLiquidity: Bool = false
    @Published var selectedPool: LiquidityPool?

    // Add liquidity state
    @Published var addAmountA: String = ""
    @Published var addAmountB: String = ""
    @Published var priceRangeLow: String = ""
    @Published var priceRangeHigh: String = ""
    @Published var isAdding: Bool = false

    // Remove liquidity state
    @Published var removePercentage: Double = 50
    @Published var isRemoving: Bool = false

    var userPositions: [LiquidityPool] {
        pools.filter { $0.userShare != nil }
    }

    var impermanentLossLabel: String {
        "Price changes between paired tokens may reduce your position value compared to simply holding. This is normal for liquidity providers."
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live pools from the gateway; fall back to samples if it isn't up.
        if let live = try? await MTRXAPIClient.shared.liquidityPools(), !live.pools.isEmpty {
            pools = live.pools.map {
                LiquidityPool(tokenA: $0.tokenA, tokenB: $0.tokenB, apr: $0.apr,
                              tvl: $0.tvl, volume24h: $0.volume24h,
                              userShare: $0.userShare, earnedFees: $0.earnedFees)
            }
            isLoading = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(700))
            pools = LiquidityViewModel.samplePools
            isLoading = false
        } catch {
            errorMessage = "Unable to load pools."
            isLoading = false
        }
    }

    func addLiquidity() async {
        isAdding = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            isAdding = false
            showAddLiquidity = false
        } catch {
            isAdding = false
        }
    }

    func removeLiquidity() async {
        isRemoving = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            isRemoving = false
            showRemoveLiquidity = false
        } catch {
            isRemoving = false
        }
    }

    static let samplePools: [LiquidityPool] = [
        LiquidityPool(tokenA: "ETH", tokenB: "USDC", apr: 12.4, tvl: 84_500_000, volume24h: 12_300_000, userShare: 0.0012, earnedFees: 38.50),
        LiquidityPool(tokenA: "ETH", tokenB: "WBTC", apr: 8.2, tvl: 42_000_000, volume24h: 6_800_000),
        LiquidityPool(tokenA: "USDC", tokenB: "DAI", apr: 4.6, tvl: 120_000_000, volume24h: 28_000_000, userShare: 0.0003, earnedFees: 12.20),
        LiquidityPool(tokenA: "ETH", tokenB: "LINK", apr: 18.7, tvl: 8_200_000, volume24h: 1_900_000),
        LiquidityPool(tokenA: "WBTC", tokenB: "USDC", apr: 6.8, tvl: 56_000_000, volume24h: 9_400_000)
    ]
}

// MARK: - Liquidity View

struct LiquidityView: View {
    @StateObject private var viewModel = LiquidityViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.pools.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.pools.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    liquidityContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Liquidity")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showAddLiquidity) {
                addLiquiditySheet
            }
            .sheet(isPresented: $viewModel.showRemoveLiquidity) {
                removeLiquiditySheet
            }
        }
    }

    // MARK: - Content

    private var liquidityContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                if !viewModel.userPositions.isEmpty {
                    userPositionsSection
                }
                poolListSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - User Positions

    private var userPositionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Your Positions")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.userPositions) { pool in
                MtrxCard(style: .glass) {
                    VStack(spacing: Spacing.md) {
                        HStack {
                            HStack(spacing: -8) {
                                MtrxAvatar(text: pool.tokenA, color: .accentPrimary, size: 32)
                                MtrxAvatar(text: pool.tokenB, color: .accentSecondary, size: 32)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pool.pairLabel)
                                    .font(.mtrxBodyBold)
                                    .foregroundStyle(Color.labelPrimary)
                                Text(String(format: "%.2f%% APR", pool.apr))
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.priceUp)
                            }
                            Spacer()
                        }

                        MtrxDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Pool Share")
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelTertiary)
                                Text(String(format: "%.4f%%", (pool.userShare ?? 0) * 100))
                                    .font(.mtrxMonoSmall)
                                    .foregroundStyle(Color.labelPrimary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: Spacing.xs) {
                                Text("Earned Fees")
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelTertiary)
                                Text(String(format: "$%.2f", pool.earnedFees ?? 0))
                                    .font(.mtrxMonoSmall)
                                    .foregroundStyle(Color.priceUp)
                            }
                        }

                        // Impermanent loss indicator
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: Symbols.alertInfo)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.statusInfo)
                            Text(viewModel.impermanentLossLabel)
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                        }
                        .padding(Spacing.sm)
                        .background(Color.statusInfo.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.xs, style: .continuous))

                        HStack(spacing: Spacing.sm) {
                            Button {
                                viewModel.selectedPool = pool
                                viewModel.showAddLiquidity = true
                            } label: {
                                Text("Add More")
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact, fullWidth: true))

                            Button {
                                viewModel.selectedPool = pool
                                viewModel.showRemoveLiquidity = true
                            } label: {
                                Text("Remove")
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact, fullWidth: true))
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Pool List

    private var poolListSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "All Pools")
                .padding(.horizontal, Spacing.contentPadding)

            // Column headers
            HStack {
                Text("Pool")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("APR")
                    .frame(width: 60, alignment: .trailing)
                Text("TVL")
                    .frame(width: 70, alignment: .trailing)
                Text("Volume")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.mtrxCaption2)
            .foregroundStyle(Color.labelTertiary)
            .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.pools) { pool in
                Button {
                    viewModel.selectedPool = pool
                    viewModel.showAddLiquidity = true
                } label: {
                    poolRow(pool)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func poolRow(_ pool: LiquidityPool) -> some View {
        HStack {
            HStack(spacing: Spacing.sm) {
                HStack(spacing: -6) {
                    MtrxAvatar(text: pool.tokenA, color: .accentPrimary, size: 24)
                    MtrxAvatar(text: pool.tokenB, color: .accentSecondary, size: 24)
                }
                Text(pool.pairLabel)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f%%", pool.apr))
                .font(.mtrxMonoSmall)
                .foregroundStyle(Color.priceUp)
                .frame(width: 60, alignment: .trailing)

            Text(formatCompact(pool.tvl))
                .font(.mtrxMonoSmall)
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 70, alignment: .trailing)

            Text(formatCompact(pool.volume24h))
                .font(.mtrxMonoSmall)
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, Spacing.ms)
        .padding(.horizontal, Spacing.contentPadding)
        .contentShape(Rectangle())
    }

    // MARK: - Add Liquidity Sheet

    private var addLiquiditySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(
                        title: "Add Liquidity",
                        subtitle: viewModel.selectedPool?.pairLabel
                    ) {
                        viewModel.showAddLiquidity = false
                    }

                    if let pool = viewModel.selectedPool {
                        VStack(spacing: Spacing.md) {
                            // Token A amount
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(pool.tokenA)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.labelSecondary)
                                MtrxTextField(
                                    placeholder: "0.00",
                                    text: $viewModel.addAmountA,
                                    keyboardType: .decimalPad
                                )
                            }

                            // Token B amount
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(pool.tokenB)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.labelSecondary)
                                MtrxTextField(
                                    placeholder: "0.00",
                                    text: $viewModel.addAmountB,
                                    keyboardType: .decimalPad
                                )
                            }

                            // Price range
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Price Range")
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.labelSecondary)
                                HStack(spacing: Spacing.sm) {
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text("Low")
                                            .font(.mtrxCaption2)
                                            .foregroundStyle(Color.labelTertiary)
                                        MtrxTextField(
                                            placeholder: "Min price",
                                            text: $viewModel.priceRangeLow,
                                            keyboardType: .decimalPad
                                        )
                                    }
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text("High")
                                            .font(.mtrxCaption2)
                                            .foregroundStyle(Color.labelTertiary)
                                        MtrxTextField(
                                            placeholder: "Max price",
                                            text: $viewModel.priceRangeHigh,
                                            keyboardType: .decimalPad
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.contentPadding)

                        MtrxCard(style: .standard) {
                            VStack(spacing: Spacing.ms) {
                                HStack {
                                    Text("Pool APR")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                    Spacer()
                                    Text(String(format: "%.1f%%", pool.apr))
                                        .font(.mtrxMonoSmall)
                                        .foregroundStyle(Color.priceUp)
                                }
                                MtrxDivider()
                                HStack {
                                    Text("TVL")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                    Spacer()
                                    Text(formatCompact(pool.tvl))
                                        .font(.mtrxMonoSmall)
                                        .foregroundStyle(Color.labelPrimary)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.contentPadding)
                    }

                    Spacer(minLength: Spacing.xl)

                    Button {
                        Task { await viewModel.addLiquidity() }
                    } label: {
                        Text(viewModel.isAdding ? "Adding Liquidity..." : "Add Liquidity")
                    }
                    .buttonStyle(MtrxButtonStyle(
                        variant: .primary,
                        size: .large,
                        isLoading: viewModel.isAdding,
                        fullWidth: true
                    ))
                    .disabled(viewModel.addAmountA.isEmpty || viewModel.addAmountB.isEmpty || viewModel.isAdding)
                    .opacity(viewModel.addAmountA.isEmpty || viewModel.addAmountB.isEmpty ? 0.5 : 1)
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.bottom, Spacing.lg)
                }
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Remove Liquidity Sheet

    private var removeLiquiditySheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                MtrxSheetHeader(
                    title: "Remove Liquidity",
                    subtitle: viewModel.selectedPool?.pairLabel
                ) {
                    viewModel.showRemoveLiquidity = false
                }

                VStack(spacing: Spacing.md) {
                    Text(String(format: "%.0f%%", viewModel.removePercentage))
                        .font(.mtrxMonoLarge)
                        .foregroundStyle(Color.labelPrimary)

                    Slider(value: $viewModel.removePercentage, in: 1...100, step: 1)
                        .tint(Color.accentPrimary)
                        .padding(.horizontal, Spacing.contentPadding)

                    HStack {
                        ForEach([25.0, 50.0, 75.0, 100.0], id: \.self) { pct in
                            Button {
                                MtrxHaptics.selection()
                                withAnimation(Motion.springSnappy) {
                                    viewModel.removePercentage = pct
                                }
                            } label: {
                                Text(String(format: "%.0f%%", pct))
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(viewModel.removePercentage == pct ? .white : Color.labelSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Spacing.sm)
                                    .background(viewModel.removePercentage == pct ? Color.accentPrimary : Color.surfaceOverlay)
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                }

                Spacer()

                Button {
                    Task { await viewModel.removeLiquidity() }
                } label: {
                    Text(viewModel.isRemoving ? "Removing..." : "Remove Liquidity")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .destructive,
                    size: .large,
                    isLoading: viewModel.isRemoving,
                    fullWidth: true
                ))
                .disabled(viewModel.isRemoving)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

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
    LiquidityView()
        .preferredColorScheme(.dark)
}
