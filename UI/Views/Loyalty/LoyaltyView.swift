// LoyaltyView.swift
// MTRX
//
// Loyalty & rewards — program memberships, tier badges, earn/redeem points, cashback claims.

import SwiftUI

// MARK: - Data Models

struct ProgramItem: Identifiable {
    let id = UUID()
    let name: String
    let points: Int
    let tierName: String
}

struct CashbackItem: Identifiable {
    let id = UUID()
    let source: String
    let amount: String
    let token: String
    let earnedAt: String
    let claimed: Bool
}

// MARK: - View Model

@MainActor
class LoyaltyViewModel: ObservableObject {
    @Published var programs: [ProgramItem] = []
    @Published var cashback: [CashbackItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isClaiming: Bool = false
    @Published var selectedSegment: String = "Earn"
    @Published var isDemo: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM dd, yyyy"; return f
    }()

    let segments = ["Earn", "Redeem"]

    var totalPoints: Int {
        programs.reduce(0) { $0 + $1.points }
    }

    var unclaimedCashback: [CashbackItem] {
        cashback.filter { !$0.claimed }
    }

    var claimedCashback: [CashbackItem] {
        cashback.filter(\.claimed)
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live programs + cashback from LoyaltyService (per-wallet) when
        // configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                async let livePrograms = LoyaltyService.shared.getLoyaltyPoints(address: address)
                async let liveCashback = LoyaltyService.shared.getCashback(address: address)
                programs = try await livePrograms.map {
                    ProgramItem(name: $0.name, points: $0.points, tierName: $0.tierName)
                }
                cashback = try await liveCashback.map {
                    CashbackItem(
                        source: $0.source,
                        amount: String(format: "%.4f", $0.amount),
                        token: $0.token,
                        earnedAt: Self.dateFormatter.string(from: $0.earnedAt),
                        claimed: $0.claimed
                    )
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live loyalty data unavailable — showing demo."
            }
        }

        programs = LoyaltyViewModel.samplePrograms
        cashback = LoyaltyViewModel.sampleCashback
        isDemo = true
        isLoading = false
    }

    func claimCashback(_ item: CashbackItem) async {
        isClaiming = true
        do {
            try await Task.sleep(for: .seconds(1))
            if let idx = cashback.firstIndex(where: { $0.id == item.id }) {
                cashback[idx] = CashbackItem(
                    source: item.source,
                    amount: item.amount,
                    token: item.token,
                    earnedAt: item.earnedAt,
                    claimed: true
                )
            }
            isClaiming = false
        } catch {
            isClaiming = false
        }
    }

    func claimAllCashback() async {
        isClaiming = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            cashback = cashback.map { item in
                CashbackItem(
                    source: item.source,
                    amount: item.amount,
                    token: item.token,
                    earnedAt: item.earnedAt,
                    claimed: true
                )
            }
            isClaiming = false
        } catch {
            isClaiming = false
        }
    }

    static let samplePrograms: [ProgramItem] = [
        ProgramItem(name: "MTRX Rewards", points: 12_450, tierName: "Gold"),
        ProgramItem(name: "Uniswap LP Loyalty", points: 3_200, tierName: "Silver"),
        ProgramItem(name: "Aave Borrower Perks", points: 8_900, tierName: "Platinum"),
        ProgramItem(name: "ENS Early Adopter", points: 1_500, tierName: "Bronze")
    ]

    static let sampleCashback: [CashbackItem] = [
        CashbackItem(source: "Uniswap Swap", amount: "2.50", token: "USDC", earnedAt: "1h ago", claimed: false),
        CashbackItem(source: "Aave Repayment", amount: "5.80", token: "USDC", earnedAt: "3h ago", claimed: false),
        CashbackItem(source: "ENS Renewal", amount: "1.20", token: "ETH", earnedAt: "1d ago", claimed: false),
        CashbackItem(source: "Curve Swap", amount: "3.40", token: "USDC", earnedAt: "2d ago", claimed: true),
        CashbackItem(source: "Lido Staking", amount: "12.00", token: "USDC", earnedAt: "3d ago", claimed: true),
        CashbackItem(source: "Bridge Fee Rebate", amount: "0.80", token: "ETH", earnedAt: "5d ago", claimed: true)
    ]
}

// MARK: - Loyalty View

struct LoyaltyView: View {
    @StateObject private var viewModel = LoyaltyViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.programs.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.programs.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    loyaltyContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Loyalty")
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

    private var loyaltyContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                totalPointsHeader
                programsSection
                earnRedeemSegment
                cashbackSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Total Points Header

    private var totalPointsHeader: some View {
        MtrxCard(style: .glass, accentEdge: .top) {
            VStack(spacing: Spacing.md) {
                VStack(spacing: Spacing.xs) {
                    Text("Total Points")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Text(formattedPoints(viewModel.totalPoints))
                        .font(.mtrxMonoLarge)
                        .foregroundStyle(Color.accentPrimary)
                }

                HStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.xs) {
                        Text("\(viewModel.programs.count)")
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.labelPrimary)
                        Text("Programs")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                    VStack(spacing: Spacing.xs) {
                        Text("\(viewModel.unclaimedCashback.count)")
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.priceUp)
                        Text("Unclaimed")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Programs Section

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Programs")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.programs) { program in
                programCard(program)
            }
        }
    }

    private func programCard(_ program: ProgramItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                MtrxAvatar(
                    symbol: Symbols.reward,
                    color: tierColor(for: program.tierName),
                    size: 44
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(program.name)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    HStack(spacing: Spacing.xs) {
                        tierBadge(program.tierName)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text(formattedPoints(program.points))
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                    Text("points")
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Earn / Redeem Segment

    private var earnRedeemSegment: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(viewModel.segments, id: \.self) { segment in
                MtrxChip(
                    label: segment,
                    icon: segment == "Earn" ? Symbols.trendUp : Symbols.donate,
                    isSelected: viewModel.selectedSegment == segment
                ) {
                    withAnimation(Motion.springDefault) {
                        viewModel.selectedSegment = segment
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Cashback Section

    private var cashbackSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                MtrxSectionHeader(
                    title: viewModel.selectedSegment == "Earn" ? "Cashback" : "Redeem History"
                )
                Spacer()
                if viewModel.selectedSegment == "Earn" && !viewModel.unclaimedCashback.isEmpty {
                    Button {
                        Task { await viewModel.claimAllCashback() }
                    } label: {
                        Text(viewModel.isClaiming ? "Claiming..." : "Claim All")
                    }
                    .buttonStyle(MtrxButtonStyle(
                        variant: .primary,
                        size: .compact,
                        isLoading: viewModel.isClaiming
                    ))
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            let items = viewModel.selectedSegment == "Earn"
                ? viewModel.unclaimedCashback
                : viewModel.claimedCashback

            if items.isEmpty {
                MtrxEmptyState(
                    icon: viewModel.selectedSegment == "Earn" ? "gift.fill" : "arrow.uturn.left.circle.fill",
                    title: viewModel.selectedSegment == "Earn" ? "No Pending Cashback" : "No Redemptions Yet",
                    message: viewModel.selectedSegment == "Earn"
                        ? "Use DeFi protocols to earn cashback rewards."
                        : "Redeem your points at participating services."
                )
            } else {
                ForEach(items) { item in
                    cashbackCard(item)
                }
            }
        }
    }

    private func cashbackCard(_ item: CashbackItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                MtrxAvatar(
                    symbol: item.claimed ? Symbols.complete : Symbols.donate,
                    color: item.claimed ? .statusSuccess : .accentPrimary,
                    size: 36
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.source)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text(item.earnedAt)
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("+\(item.amount) \(item.token)")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(item.claimed ? Color.labelSecondary : Color.priceUp)

                    if !item.claimed {
                        Button {
                            Task { await viewModel.claimCashback(item) }
                        } label: {
                            Text("Claim")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                    } else {
                        MtrxBadge(text: "Claimed", style: .neutral)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Helpers

    private func formattedPoints(_ points: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: points)) ?? "\(points)"
    }

    private func tierColor(for tier: String) -> Color {
        switch tier {
        case "Bronze": return Color(red: 0.8, green: 0.5, blue: 0.2)
        case "Silver": return Color(white: 0.65)
        case "Gold": return Color(red: 1.0, green: 0.84, blue: 0.0)
        case "Platinum": return Color(red: 0.9, green: 0.9, blue: 0.95)
        default: return .labelSecondary
        }
    }

    private func tierBadge(_ tier: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: tierIcon(for: tier))
                .font(.system(size: 10))
            Text(tier)
                .font(.mtrxCaptionBold)
        }
        .foregroundStyle(tierColor(for: tier))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 3)
        .background(tierColor(for: tier).opacity(0.12))
        .clipShape(Capsule())
    }

    private func tierIcon(for tier: String) -> String {
        switch tier {
        case "Bronze": return "shield.fill"
        case "Silver": return "shield.fill"
        case "Gold": return "crown.fill"
        case "Platinum": return "diamond.fill"
        default: return "shield.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    LoyaltyView()
        .preferredColorScheme(.dark)
}
