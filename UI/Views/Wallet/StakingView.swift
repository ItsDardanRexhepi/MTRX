// UI/Views/Wallet/StakingView.swift
// MTRX — Staking & DeFi Positions

import SwiftUI

struct StakingView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var appeared = false

    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .primary)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Portfolio summary
                    portfolioCard

                    // Active positions
                    positionsSection

                    // Staking options
                    stakingOptionsSection
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("Staking & DeFi")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(Motion.springDefault.delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Portfolio Card

    private var portfolioCard: some View {
        MtrxCard(style: .elevated) {
            VStack(spacing: Spacing.sm) {
                Text("Total Staked Value")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)

                Text("$\(totalStakedValue, specifier: "%.2f")")
                    .font(.mtrxLargeTitle)
                    .foregroundStyle(Color.labelPrimary)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                    Text("+8.7% APY avg")
                        .font(.mtrxCaption1)
                }
                .foregroundStyle(Color.priceUp)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.cardPadding)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    // MARK: - Positions

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Active Positions")

            if walletManager.defiPositions.isEmpty {
                MtrxEmptyState(
                    icon: "lock.circle",
                    title: "No Staking Positions",
                    message: "Start earning yield by staking your tokens."
                )
            }

            ForEach(walletManager.defiPositions) { position in
                MtrxCard(style: .standard) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: position.icon)
                            .font(.title3)
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: 40, height: 40)
                            .background(Color.accentPrimary.opacity(0.15), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(position.protocol_)
                                .font(.mtrxHeadline)
                            Text(position.type)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("$\(position.value, specifier: "%.2f")")
                                .font(.mtrxBody)
                                .monospacedDigit()
                            Text("\(position.apy, specifier: "%.1f")% APY")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.priceUp)
                        }
                    }
                    .padding(Spacing.cardPadding)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    // MARK: - Staking Options

    private var stakingOptionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Stake More")

            ForEach(stakingOptions, id: \.name) { option in
                MtrxCard(style: .standard) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: option.icon)
                            .font(.title3)
                            .foregroundStyle(Color.accentSecondary)
                            .frame(width: 40, height: 40)
                            .background(Color.accentSecondary.opacity(0.15), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name)
                                .font(.mtrxHeadline)
                            Text(option.description)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(option.apy, specifier: "%.1f")%")
                                .font(.mtrxBody.bold())
                                .foregroundStyle(Color.priceUp)
                            Text("APY")
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                        }
                    }
                    .padding(Spacing.cardPadding)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    // MARK: - Data

    private var totalStakedValue: Double {
        walletManager.defiPositions.reduce(0) { $0 + $1.value }
    }

    private var stakingOptions: [StakingOption] {
        [
            StakingOption(name: "MTRX Staking", description: "Lock MTRX tokens for rewards", apy: 8.7, icon: "lock.circle"),
            StakingOption(name: "ETH Liquid Staking", description: "Stake ETH via Lido or Rocket Pool", apy: 4.2, icon: "drop.circle"),
            StakingOption(name: "LP Farming", description: "Provide liquidity to earn fees", apy: 12.5, icon: "arrow.left.arrow.right.circle"),
        ]
    }
}

private struct StakingOption {
    let name: String
    let description: String
    let apy: Double
    let icon: String
}
