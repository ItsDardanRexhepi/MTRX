// StakingView.swift
// MTRX
//
// Staking interface — ETH staking, token staking pools, positions, unstake flow, claim rewards.

import SwiftUI

// MARK: - Data Models

struct StakingPool: Identifiable {
    let id: String
    let token: String
    let symbol: String
    let apy: Double
    let totalStaked: Double
    let minStake: Double

    init(
        id: String = UUID().uuidString,
        token: String,
        symbol: String,
        apy: Double,
        totalStaked: Double,
        minStake: Double
    ) {
        self.id = id
        self.token = token
        self.symbol = symbol
        self.apy = apy
        self.totalStaked = totalStaked
        self.minStake = minStake
    }
}

struct StakingPosition: Identifiable {
    let id: String
    let token: String
    let symbol: String
    let stakedAmount: Double
    let rewardsEarned: Double
    let apy: Double
    let unbondingAmount: Double
    let unbondingDaysLeft: Int?

    init(
        id: String = UUID().uuidString,
        token: String,
        symbol: String,
        stakedAmount: Double,
        rewardsEarned: Double,
        apy: Double,
        unbondingAmount: Double = 0,
        unbondingDaysLeft: Int? = nil
    ) {
        self.id = id
        self.token = token
        self.symbol = symbol
        self.stakedAmount = stakedAmount
        self.rewardsEarned = rewardsEarned
        self.apy = apy
        self.unbondingAmount = unbondingAmount
        self.unbondingDaysLeft = unbondingDaysLeft
    }
}

// MARK: - View Model

@MainActor
class StakingViewModel: ObservableObject {
    @Published var pools: [StakingPool] = []
    @Published var positions: [StakingPosition] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // ETH Staking
    @Published var ethStakeAmount: String = ""
    @Published var isStaking: Bool = false
    @Published var showUnstakeSheet: Bool = false
    @Published var unstakeAmount: String = ""
    @Published var isUnstaking: Bool = false
    @Published var isClaimingRewards: Bool = false

    var ethStakeAPY: Double { 3.8 }
    var stETHRate: Double { 1.0 }

    var stETHReceived: String {
        guard let amount = Double(ethStakeAmount), amount > 0 else { return "0.00" }
        return String(format: "%.4f", amount * stETHRate)
    }

    var totalStakedValue: Double {
        positions.reduce(0) { $0 + $1.stakedAmount }
    }

    var totalRewards: Double {
        positions.reduce(0) { $0 + $1.rewardsEarned }
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            try await Task.sleep(for: .milliseconds(700))
            pools = StakingViewModel.samplePools
            positions = StakingViewModel.samplePositions
            isLoading = false
        } catch {
            errorMessage = "Unable to load staking data."
            isLoading = false
        }
    }

    func stakeETH() async {
        guard let amount = Double(ethStakeAmount), amount > 0 else { return }
        isStaking = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            isStaking = false
            ethStakeAmount = ""
        } catch {
            isStaking = false
        }
    }

    func unstake() async {
        isUnstaking = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            isUnstaking = false
            showUnstakeSheet = false
            unstakeAmount = ""
        } catch {
            isUnstaking = false
        }
    }

    func claimRewards() async {
        isClaimingRewards = true
        do {
            try await Task.sleep(for: .seconds(1))
            isClaimingRewards = false
        } catch {
            isClaimingRewards = false
        }
    }

    static let samplePools: [StakingPool] = [
        StakingPool(token: "Chainlink", symbol: "LINK", apy: 5.2, totalStaked: 18_000_000, minStake: 10),
        StakingPool(token: "Polygon", symbol: "MATIC", apy: 4.8, totalStaked: 42_000_000, minStake: 100),
        StakingPool(token: "Aave", symbol: "AAVE", apy: 6.1, totalStaked: 8_500_000, minStake: 1),
        StakingPool(token: "Uniswap", symbol: "UNI", apy: 3.4, totalStaked: 12_000_000, minStake: 50)
    ]

    static let samplePositions: [StakingPosition] = [
        StakingPosition(
            token: "Ethereum", symbol: "ETH",
            stakedAmount: 2.0, rewardsEarned: 0.032, apy: 3.8,
            unbondingAmount: 0.5, unbondingDaysLeft: 2
        ),
        StakingPosition(
            token: "Chainlink", symbol: "LINK",
            stakedAmount: 250, rewardsEarned: 4.8, apy: 5.2
        )
    ]
}

// MARK: - Staking View

struct StakingView: View {
    @StateObject private var viewModel = StakingViewModel()

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
                    stakingContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Staking")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showUnstakeSheet) {
                unstakeSheet
            }
        }
    }

    // MARK: - Content

    private var stakingContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                ethStakingSection
                if !viewModel.positions.isEmpty {
                    positionsSection
                }
                poolsSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - ETH Staking Section

    private var ethStakingSection: some View {
        MtrxCard(style: .glass, accentEdge: .leading) {
            VStack(spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Stake ETH")
                            .font(.mtrxTitle3)
                            .foregroundStyle(Color.labelPrimary)
                        Text(String(format: "%.1f%% APY", viewModel.ethStakeAPY))
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.priceUp)
                    }
                    Spacer()
                    MtrxAvatar(text: "ETH", color: .accentPrimary, size: 44)
                }

                MtrxDivider()

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Amount to Stake")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)
                    MtrxTextField(
                        placeholder: "0.00 ETH",
                        text: $viewModel.ethStakeAmount,
                        keyboardType: .decimalPad
                    )
                }

                HStack {
                    Text("You will receive")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text("\(viewModel.stETHReceived) stETH")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                }

                Button {
                    Task { await viewModel.stakeETH() }
                } label: {
                    Text(viewModel.isStaking ? "Staking..." : "Stake ETH")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .primary,
                    size: .large,
                    isLoading: viewModel.isStaking,
                    fullWidth: true
                ))
                .disabled(viewModel.ethStakeAmount.isEmpty || viewModel.isStaking)
                .opacity(viewModel.ethStakeAmount.isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Positions Section

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Your Positions")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.positions) { position in
                positionCard(position)
            }
        }
    }

    private func positionCard(_ position: StakingPosition) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.md) {
                HStack {
                    MtrxAvatar(text: position.symbol, color: .accentPrimary, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(position.token)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(String(format: "%.1f%% APY", position.apy))
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.priceUp)
                    }
                    Spacer()
                }

                MtrxDivider()

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Staked")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(String(format: "%.4f %@", position.stakedAmount, position.symbol))
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Rewards Earned")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(String(format: "+%.4f %@", position.rewardsEarned, position.symbol))
                            .font(.mtrxMono)
                            .foregroundStyle(Color.priceUp)
                    }
                }

                // Unbonding queue
                if position.unbondingAmount > 0, let days = position.unbondingDaysLeft {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: Symbols.pending)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.statusWarning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.4f %@ unbonding", position.unbondingAmount, position.symbol))
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelPrimary)
                            Text("Your ETH will be available in ~\(days) days")
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        Spacer()
                    }
                    .padding(Spacing.sm)
                    .background(Color.statusWarning.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.xs, style: .continuous))
                }

                HStack(spacing: Spacing.sm) {
                    Button {
                        viewModel.showUnstakeSheet = true
                    } label: {
                        Text("Unstake")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact, fullWidth: true))

                    Button {
                        Task { await viewModel.claimRewards() }
                    } label: {
                        Text(viewModel.isClaimingRewards ? "Claiming..." : "Claim Rewards")
                    }
                    .buttonStyle(MtrxButtonStyle(
                        variant: .primary,
                        size: .compact,
                        isLoading: viewModel.isClaimingRewards,
                        fullWidth: true
                    ))
                    .disabled(position.rewardsEarned <= 0 || viewModel.isClaimingRewards)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Pools Section

    private var poolsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Token Staking Pools")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.pools) { pool in
                MtrxCard(style: .standard) {
                    HStack(spacing: Spacing.ms) {
                        MtrxAvatar(text: pool.symbol, color: .accentPrimary, size: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(pool.token)
                                .font(.mtrxBodyBold)
                                .foregroundStyle(Color.labelPrimary)
                            Text(String(format: "Min: %.0f %@", pool.minStake, pool.symbol))
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f%%", pool.apy))
                                .font(.mtrxHeadlineTabular)
                                .foregroundStyle(Color.priceUp)
                            Text("APY")
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                        }

                        Image(systemName: Symbols.forward)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Unstake Sheet

    private var unstakeSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                MtrxSheetHeader(title: "Unstake", subtitle: "Withdraw your staked tokens") {
                    viewModel.showUnstakeSheet = false
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Amount to Unstake")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)
                    MtrxTextField(
                        placeholder: "0.00",
                        text: $viewModel.unstakeAmount,
                        keyboardType: .decimalPad
                    )
                }
                .padding(.horizontal, Spacing.contentPadding)

                // Warning
                HStack(spacing: Spacing.sm) {
                    Image(systemName: Symbols.alertWarning)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.statusWarning)
                    Text("Your ETH will be available in ~3 days after unstaking. You will continue earning rewards during this period.")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(Spacing.md)
                .background(Color.statusWarning.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                .padding(.horizontal, Spacing.contentPadding)

                Spacer()

                Button {
                    Task { await viewModel.unstake() }
                } label: {
                    Text(viewModel.isUnstaking ? "Unstaking..." : "Confirm Unstake")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .primary,
                    size: .large,
                    isLoading: viewModel.isUnstaking,
                    fullWidth: true
                ))
                .disabled(viewModel.unstakeAmount.isEmpty || viewModel.isUnstaking)
                .opacity(viewModel.unstakeAmount.isEmpty ? 0.5 : 1)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Preview

#Preview {
    StakingView()
        .preferredColorScheme(.dark)
}
