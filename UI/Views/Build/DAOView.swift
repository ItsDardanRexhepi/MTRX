// DAOView.swift
// MTRX
//
// DAO governance interface with proposals, treasury, and delegate management.

import SwiftUI

// MARK: - DAO ViewModel

@MainActor
final class DAOViewModel: ObservableObject {
    @Published var proposals: [DAOGovernanceProposal] = []
    @Published var treasuryAssets: [TreasuryToken] = []
    @Published var treasuryTransactions: [TreasuryTx] = []
    @Published var delegates: [DelegateInfo] = []
    @Published var selectedTab: GovernanceTab = .proposals
    @Published var isLoading: Bool = false
    @Published var isDemo: Bool = true

    // Voting
    @Published var selectedProposal: DAOGovernanceProposal?
    @Published var showVoteSheet: Bool = false
    @Published var selectedVoteChoice: GovernanceVoteChoice?
    @Published var isVoting: Bool = false
    @Published var showPastProposals: Bool = false

    // Delegation
    @Published var currentDelegateAddress: String = "Self"
    @Published var currentVotingPower: String = "1,250 MTRX"

    // Treasury
    var totalTreasuryValue: Double {
        treasuryAssets.reduce(0) { $0 + $1.valueUSD }
    }

    var formattedTreasuryValue: String {
        String(format: "$%,.0f", totalTreasuryValue)
    }

    // Active / Past split
    var activeProposals: [DAOGovernanceProposal] {
        proposals.filter { $0.status == .active }
    }

    var pastProposals: [DAOGovernanceProposal] {
        proposals.filter { $0.status != .active }
    }

    // MARK: - Load

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true

        // Live proposals from the gateway; fall back to samples if it isn't up.
        if let live = try? await MTRXAPIClient.shared.daoProposals(), !live.proposals.isEmpty {
            isDemo = false
            proposals = live.proposals.map { p in
                DAOGovernanceProposal(
                    number: p.number, title: p.title, description_: p.description ?? "",
                    proposer: p.proposer,
                    status: GovernanceOutcome(rawValue: p.status) ?? .active,
                    votesFor: p.votesFor, votesAgainst: p.votesAgainst,
                    quorumRequired: p.quorumRequired,
                    timeRemaining: p.timeRemaining ?? ""
                )
            }
        } else {
            isDemo = true
            try? await Task.sleep(nanoseconds: 800_000_000)
            proposals = DAOGovernanceProposal.sampleData
        }

        // Treasury + delegates stay on sample data until those endpoints exist.
        treasuryAssets = TreasuryToken.sampleData
        treasuryTransactions = TreasuryTx.sampleData
        delegates = DelegateInfo.sampleData

        isLoading = false
    }

    func refresh() async {
        proposals = []
        treasuryAssets = []
        delegates = []
        await loadAll()
    }

    // MARK: - Vote

    func openVoteSheet(for proposal: DAOGovernanceProposal) {
        selectedProposal = proposal
        selectedVoteChoice = nil
        showVoteSheet = true
        MtrxHaptics.impact(.medium)
    }

    func castVote() {
        guard selectedVoteChoice != nil else { return }
        isVoting = true
        MtrxHaptics.impact(.heavy)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isVoting = false
            self?.showVoteSheet = false
            MtrxHaptics.success()
        }
    }

    func changeTab(_ tab: GovernanceTab) {
        withAnimation(Motion.springSnappy) {
            selectedTab = tab
        }
        MtrxHaptics.selection()
    }
}

// MARK: - Tab

enum GovernanceTab: String, CaseIterable, Identifiable {
    case proposals = "Proposals"
    case treasury = "Treasury"
    case delegates = "Delegates"

    var id: String { rawValue }
}

// MARK: - Vote Choice

enum GovernanceVoteChoice: String, CaseIterable, Identifiable {
    case forVote = "For"
    case against = "Against"
    case abstain = "Abstain"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .forVote: return Symbols.voteYes
        case .against: return Symbols.voteNo
        case .abstain: return Symbols.voteAbstain
        }
    }

    var color: Color {
        switch self {
        case .forVote: return .voteFor
        case .against: return .voteAgainst
        case .abstain: return .voteAbstain
        }
    }
}

// MARK: - Proposal Status

enum GovernanceOutcome: String {
    case active = "Active"
    case passed = "Passed"
    case rejected = "Rejected"
    case quorumNotMet = "No Quorum"

    var color: Color {
        switch self {
        case .active: return .statusInfo
        case .passed: return .statusSuccess
        case .rejected: return .statusError
        case .quorumNotMet: return .statusWarning
        }
    }

    var badgeStyle: MtrxBadge.BadgeStyle {
        switch self {
        case .active: return .info
        case .passed: return .success
        case .rejected: return .error
        case .quorumNotMet: return .warning
        }
    }
}

// MARK: - Data Models

struct DAOGovernanceProposal: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let description_: String
    let proposer: String
    let status: GovernanceOutcome
    let votesFor: Int
    let votesAgainst: Int
    let quorumRequired: Int
    let timeRemaining: String

    var totalVotes: Int { votesFor + votesAgainst }
    var forPercentage: Double { totalVotes > 0 ? Double(votesFor) / Double(totalVotes) : 0 }
    var againstPercentage: Double { totalVotes > 0 ? Double(votesAgainst) / Double(totalVotes) : 0 }
    var quorumProgress: Double { Double(totalVotes) / Double(max(quorumRequired, 1)) }

    static let sampleData: [DAOGovernanceProposal] = [
        DAOGovernanceProposal(number: 47, title: "Treasury Diversification into ETH", description_: "Diversify 20% of the treasury holdings into ETH to reduce stablecoin concentration risk. The conversion would happen over 4 weeks via TWAP orders to minimize slippage. This strengthens our position during market volatility.", proposer: "alice.eth", status: .active, votesFor: 680, votesAgainst: 220, quorumRequired: 1000, timeRemaining: "2d 14h"),
        DAOGovernanceProposal(number: 46, title: "Developer Grant Program Q2", description_: "Allocate $100K from treasury for quarterly developer grants. Funds will support open-source tooling, protocol integrations, and security audits. Grant committee of 5 delegates will review applications.", proposer: "bob.eth", status: .active, votesFor: 450, votesAgainst: 350, quorumRequired: 1000, timeRemaining: "5d 8h"),
        DAOGovernanceProposal(number: 45, title: "Reduce Protocol Fee to 0.25%", description_: "Lower the base protocol fee from 0.3% to 0.25% to increase competitiveness and attract more volume. Modeling shows the reduced fee would be offset by higher transaction volume within 3 months.", proposer: "carol.eth", status: .active, votesFor: 520, votesAgainst: 180, quorumRequired: 800, timeRemaining: "12h"),
        DAOGovernanceProposal(number: 44, title: "Launch Staking Rewards V2", description_: "Upgrade the staking rewards mechanism to include tiered bonuses for long-term stakers. 30-day lock: 1x, 90-day lock: 1.5x, 180-day lock: 2.5x multiplier.", proposer: "dave.eth", status: .passed, votesFor: 890, votesAgainst: 110, quorumRequired: 800, timeRemaining: "Ended"),
        DAOGovernanceProposal(number: 43, title: "Add Insurance Pool Coverage", description_: "Create a dedicated insurance pool funded by 5% of protocol revenue. Coverage would protect users against smart contract exploits up to $500K per incident.", proposer: "alice.eth", status: .rejected, votesFor: 320, votesAgainst: 480, quorumRequired: 800, timeRemaining: "Ended"),
        DAOGovernanceProposal(number: 42, title: "Governance Minimum Threshold", description_: "Raise the minimum token threshold to submit a proposal from 100 MTRX to 500 MTRX to reduce spam proposals and improve governance signal quality.", proposer: "frank.eth", status: .quorumNotMet, votesFor: 200, votesAgainst: 150, quorumRequired: 800, timeRemaining: "Ended"),
    ]
}

struct TreasuryToken: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let balance: Double
    let valueUSD: Double
    let iconColor: Color

    static let sampleData: [TreasuryToken] = [
        TreasuryToken(symbol: "USDC", name: "USD Coin", balance: 800_000, valueUSD: 800_000, iconColor: .green),
        TreasuryToken(symbol: "ETH", name: "Ethereum", balance: 105.2, valueUSD: 345_670, iconColor: .blue),
        TreasuryToken(symbol: "MTRX", name: "Matrix Token", balance: 5_000_000, valueUSD: 117_000, iconColor: .accentPrimary),
        TreasuryToken(symbol: "WBTC", name: "Wrapped Bitcoin", balance: 0.85, valueUSD: 57_706, iconColor: .orange),
    ]
}

struct TreasuryTx: Identifiable {
    let id = UUID()
    let type: TxDirection
    let title: String
    let relatedProposal: String
    let amount: String
    let date: String

    enum TxDirection { case inflow, outflow }

    static let sampleData: [TreasuryTx] = [
        TreasuryTx(type: .outflow, title: "Developer Grant - Q1", relatedProposal: "Prop #41", amount: "-$25,000", date: "Mar 15"),
        TreasuryTx(type: .inflow, title: "Protocol Revenue", relatedProposal: "Automated", amount: "+$12,500", date: "Mar 14"),
        TreasuryTx(type: .outflow, title: "Security Audit Payment", relatedProposal: "Prop #39", amount: "-$18,000", date: "Mar 10"),
        TreasuryTx(type: .inflow, title: "Protocol Revenue", relatedProposal: "Automated", amount: "+$11,800", date: "Mar 7"),
        TreasuryTx(type: .outflow, title: "Marketing Campaign", relatedProposal: "Prop #38", amount: "-$8,000", date: "Mar 1"),
    ]
}

struct DelegateInfo: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let votingPower: String
    let votingPowerNumeric: Int
    let proposalsVoted: Int
    let delegatorCount: Int
    let avatarColor: Color

    static let sampleData: [DelegateInfo] = [
        DelegateInfo(name: "alice.eth", address: "0xab12...ef34", votingPower: "125,000", votingPowerNumeric: 125000, proposalsVoted: 42, delegatorCount: 89, avatarColor: .purple),
        DelegateInfo(name: "bob.eth", address: "0x9876...5432", votingPower: "89,000", votingPowerNumeric: 89000, proposalsVoted: 38, delegatorCount: 56, avatarColor: .blue),
        DelegateInfo(name: "carol.eth", address: "0xfedc...ba98", votingPower: "67,500", votingPowerNumeric: 67500, proposalsVoted: 45, delegatorCount: 34, avatarColor: .green),
        DelegateInfo(name: "dave.eth", address: "0x1234...abcd", votingPower: "52,000", votingPowerNumeric: 52000, proposalsVoted: 31, delegatorCount: 28, avatarColor: .orange),
        DelegateInfo(name: "eve.eth", address: "0x5678...efgh", votingPower: "41,200", votingPowerNumeric: 41200, proposalsVoted: 27, delegatorCount: 19, avatarColor: .pink),
        DelegateInfo(name: "frank.eth", address: "0x9abc...1234", votingPower: "33,800", votingPowerNumeric: 33800, proposalsVoted: 22, delegatorCount: 15, avatarColor: .accentPrimary),
    ]
}

// MARK: - DAO View

struct DAOView: View {
    @StateObject private var viewModel = DAOViewModel()
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                if viewModel.isLoading && viewModel.proposals.isEmpty {
                    loadingState
                } else {
                    contentView
                }
            }
            .navigationTitle("Governance")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showVoteSheet) {
                if let proposal = viewModel.selectedProposal {
                    VoteSheet(proposal: proposal, viewModel: viewModel)
                        .presentationDetents([.large])
                }
            }
            .task {
                guard !appeared else { return }
                appeared = true
                await viewModel.loadAll()
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            segmentPills
                .padding(.top, Spacing.sm)

            TabView(selection: $viewModel.selectedTab) {
                proposalsTab
                    .tag(GovernanceTab.proposals)

                treasuryTab
                    .tag(GovernanceTab.treasury)

                delegatesTab
                    .tag(GovernanceTab.delegates)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .demoBadge(viewModel.isDemo)
    }

    // MARK: - Segment Pills

    private var segmentPills: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(GovernanceTab.allCases) { tab in
                Button {
                    viewModel.changeTab(tab)
                } label: {
                    Text(tab.rawValue)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(viewModel.selectedTab == tab ? .white : Color.labelPrimary)
                        .padding(.horizontal, Spacing.ml)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            viewModel.selectedTab == tab
                                ? Color.accentPrimary
                                : Color.surfaceOverlay
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Proposals Tab

    private var proposalsTab: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                // Active Proposals
                if !viewModel.activeProposals.isEmpty {
                    MtrxSectionHeader(title: "Active", subtitle: "\(viewModel.activeProposals.count) proposals")
                        .padding(.horizontal, Spacing.contentPadding)

                    ForEach(Array(viewModel.activeProposals.enumerated()), id: \.element.id) { index, proposal in
                        DAOProposalCardView(proposal: proposal) {
                            viewModel.openVoteSheet(for: proposal)
                        }
                        .padding(.horizontal, Spacing.contentPadding)
                        .mtrxStaggeredAppearance(index: index, isVisible: appeared)
                    }
                }

                // Past Proposals
                if !viewModel.pastProposals.isEmpty {
                    Button {
                        withAnimation(Motion.springDefault) {
                            viewModel.showPastProposals.toggle()
                        }
                        MtrxHaptics.selection()
                    } label: {
                        HStack {
                            Text("Past Proposals")
                                .font(.mtrxHeadline)
                                .foregroundStyle(Color.labelPrimary)

                            Text("\(viewModel.pastProposals.count)")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)

                            Spacer()

                            Image(systemName: viewModel.showPastProposals ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.labelTertiary)
                        }
                        .padding(.horizontal, Spacing.contentPadding)
                        .padding(.vertical, Spacing.sm)
                    }
                    .buttonStyle(.plain)

                    if viewModel.showPastProposals {
                        ForEach(viewModel.pastProposals) { proposal in
                            PastProposalRow(proposal: proposal)
                                .padding(.horizontal, Spacing.contentPadding)
                        }
                    }
                }
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Treasury Tab

    private var treasuryTab: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Total value card
                MtrxStatCard(
                    title: "Total Treasury Value",
                    value: viewModel.formattedTreasuryValue,
                    change: "+$24,500 (30d)",
                    isPositive: true,
                    icon: Symbols.treasury
                )
                .padding(.horizontal, Spacing.contentPadding)

                // Asset allocation
                MtrxSectionHeader(title: "Asset Allocation")
                    .padding(.horizontal, Spacing.contentPadding)

                VStack(spacing: Spacing.xs) {
                    ForEach(viewModel.treasuryAssets) { asset in
                        MtrxCard(style: .standard) {
                            HStack(spacing: Spacing.ms) {
                                MtrxAvatar(
                                    text: asset.symbol,
                                    color: asset.iconColor,
                                    size: Spacing.Size.avatarSmall
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(asset.name)
                                        .font(.mtrxCalloutBold)
                                        .foregroundStyle(Color.labelPrimary)

                                    Text(formatBalance(asset.balance, symbol: asset.symbol))
                                        .font(.mtrxMonoSmall)
                                        .foregroundStyle(Color.labelSecondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(format: "$%,.0f", asset.valueUSD))
                                        .font(.mtrxMono)
                                        .foregroundStyle(Color.labelPrimary)

                                    let pct = viewModel.totalTreasuryValue > 0 ? (asset.valueUSD / viewModel.totalTreasuryValue * 100) : 0
                                    Text(String(format: "%.1f%%", pct))
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelTertiary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                // Recent transactions
                MtrxSectionHeader(title: "Recent Activity")
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)

                VStack(spacing: Spacing.xs) {
                    ForEach(viewModel.treasuryTransactions) { tx in
                        MtrxCard(style: .standard) {
                            HStack(spacing: Spacing.ms) {
                                Image(systemName: tx.type == .inflow ? Symbols.receive : Symbols.send)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(tx.type == .inflow ? Color.statusSuccess : Color.statusError)
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tx.title)
                                        .font(.mtrxCallout)
                                        .foregroundStyle(Color.labelPrimary)
                                    Text(tx.relatedProposal)
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelTertiary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(tx.amount)
                                        .font(.mtrxMono)
                                        .foregroundStyle(tx.type == .inflow ? Color.statusSuccess : Color.statusError)
                                    Text(tx.date)
                                        .font(.mtrxCaption2)
                                        .foregroundStyle(Color.labelTertiary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Delegates Tab

    private var delegatesTab: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Your delegation info
                MtrxCard(style: .elevated, accentEdge: .top) {
                    VStack(spacing: Spacing.ms) {
                        MtrxSectionHeader(title: "Your Delegation")

                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Delegated To")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                                Text(viewModel.currentDelegateAddress)
                                    .font(.mtrxCalloutBold)
                                    .foregroundStyle(Color.labelPrimary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: Spacing.xs) {
                                Text("Voting Power")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                                Text(viewModel.currentVotingPower)
                                    .font(.mtrxMono)
                                    .foregroundStyle(Color.accentPrimary)
                            }
                        }

                        MtrxDivider()

                        // Self-delegate option
                        Button {
                            viewModel.currentDelegateAddress = "Self"
                            MtrxHaptics.success()
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(Color.accentPrimary)
                                Text("Delegate to Self")
                                    .font(.mtrxCalloutBold)
                                    .foregroundStyle(Color.accentPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                // Delegate list
                MtrxSectionHeader(title: "Top Delegates")
                    .padding(.horizontal, Spacing.contentPadding)

                ForEach(viewModel.delegates) { delegate in
                    DelegateCardView(delegate: delegate) {
                        withAnimation(Motion.springDefault) {
                            viewModel.currentDelegateAddress = delegate.name
                        }
                        MtrxHaptics.success()
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                }
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: Spacing.ms) {
                HStack(spacing: Spacing.xs) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(Color.surfaceOverlay).frame(height: 34)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
                .mtrxShimmer(isActive: true)

                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.surfaceOverlay).frame(height: 16)
                        RoundedRectangle(cornerRadius: 3).fill(Color.surfaceOverlay).frame(width: 200, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Color.surfaceOverlay).frame(height: 8)
                        HStack {
                            RoundedRectangle(cornerRadius: 3).fill(Color.surfaceOverlay).frame(width: 60, height: 10)
                            Spacer()
                            RoundedRectangle(cornerRadius: 3).fill(Color.surfaceOverlay).frame(width: 80, height: 10)
                        }
                    }
                    .mtrxCardStyle()
                    .mtrxShimmer(isActive: true)
                }
            }
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Helpers

    private func formatBalance(_ balance: Double, symbol: String) -> String {
        switch symbol {
        case "USDC": return String(format: "%,.0f %@", balance, symbol)
        case "ETH": return String(format: "%.2f %@", balance, symbol)
        case "WBTC": return String(format: "%.4f %@", balance, symbol)
        default: return String(format: "%,.0f %@", balance, symbol)
        }
    }
}

// MARK: - Proposal Card

struct DAOProposalCardView: View {
    let proposal: DAOGovernanceProposal
    let onVote: () -> Void

    var body: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.ms) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(proposal.title)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(2)

                        Text(proposal.description_)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    MtrxProgressRing(
                        progress: min(proposal.quorumProgress, 1.0),
                        size: 40,
                        lineWidth: 3,
                        color: proposal.quorumProgress >= 1.0 ? .quorumMet : .labelTertiary,
                        showLabel: true
                    )
                }

                // Vote bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if proposal.forPercentage > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.voteFor)
                                .frame(width: max(geo.size.width * proposal.forPercentage, 4))
                        }
                        if proposal.againstPercentage > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.voteAgainst)
                                .frame(width: max(geo.size.width * proposal.againstPercentage, 4))
                        }
                    }
                }
                .frame(height: 8)
                .background(Color.surfaceOverlay)
                .clipShape(Capsule())

                // Vote counts
                HStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.xs) {
                        Circle().fill(Color.voteFor).frame(width: 8, height: 8)
                        Text("\(Int(proposal.forPercentage * 100))% For")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    HStack(spacing: Spacing.xs) {
                        Circle().fill(Color.voteAgainst).frame(width: 8, height: 8)
                        Text("\(Int(proposal.againstPercentage * 100))% Against")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    Text(proposal.timeRemaining)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.accentPrimary)
                }

                // Action row
                HStack {
                    Text("by \(proposal.proposer)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)

                    Spacer()

                    Button(action: onVote) {
                        Text("Vote")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                }
            }
        }
    }
}

// MARK: - Past Proposal Row

struct PastProposalRow: View {
    let proposal: DAOGovernanceProposal

    var body: some View {
        MtrxCard(style: .outlined) {
            HStack(spacing: Spacing.ms) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text("#\(proposal.number)")
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelTertiary)
                        Text(proposal.title)
                            .font(.mtrxCallout)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Text("by \(proposal.proposer)")
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                MtrxBadge(text: proposal.status.rawValue, style: proposal.status.badgeStyle)
            }
        }
    }
}

// MARK: - Vote Sheet

struct VoteSheet: View {
    let proposal: DAOGovernanceProposal
    @ObservedObject var viewModel: DAOViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                        // Proposal detail
                        MtrxCard(style: .elevated) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                HStack {
                                    Text("#\(proposal.number)")
                                        .font(.mtrxMonoSmall)
                                        .foregroundStyle(Color.labelTertiary)
                                    Spacer()
                                    MtrxBadge(text: "Active", style: .info)
                                }

                                Text(proposal.title)
                                    .font(.mtrxTitle3)
                                    .foregroundStyle(Color.labelPrimary)

                                Text(proposal.description_)
                                    .font(.mtrxBody)
                                    .foregroundStyle(Color.labelSecondary)
                                    .lineSpacing(4)

                                MtrxDivider()

                                HStack {
                                    Text("Proposer")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelTertiary)
                                    Spacer()
                                    Text(proposal.proposer)
                                        .font(.mtrxMonoSmall)
                                        .foregroundStyle(Color.labelPrimary)
                                }

                                HStack {
                                    Text("Time Remaining")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelTertiary)
                                    Spacer()
                                    Text(proposal.timeRemaining)
                                        .font(.mtrxCaptionBold)
                                        .foregroundStyle(Color.accentPrimary)
                                }
                            }
                        }

                        // Vote options
                        MtrxSectionHeader(title: "Cast Your Vote")

                        VStack(spacing: Spacing.ms) {
                            ForEach(GovernanceVoteChoice.allCases) { choice in
                                Button {
                                    withAnimation(Motion.springSnappy) {
                                        viewModel.selectedVoteChoice = choice
                                    }
                                    MtrxHaptics.selection()
                                } label: {
                                    HStack(spacing: Spacing.ms) {
                                        // Radio indicator
                                        ZStack {
                                            Circle()
                                                .stroke(viewModel.selectedVoteChoice == choice ? choice.color : Color.labelTertiary, lineWidth: 2)
                                                .frame(width: 22, height: 22)

                                            if viewModel.selectedVoteChoice == choice {
                                                Circle()
                                                    .fill(choice.color)
                                                    .frame(width: 12, height: 12)
                                            }
                                        }

                                        Image(systemName: choice.icon)
                                            .font(.system(size: 22, weight: .medium))
                                            .foregroundStyle(viewModel.selectedVoteChoice == choice ? choice.color : Color.labelSecondary)

                                        Text(choice.rawValue)
                                            .font(.mtrxTitle3)
                                            .foregroundStyle(viewModel.selectedVoteChoice == choice ? choice.color : Color.labelPrimary)

                                        Spacer()
                                    }
                                    .padding(Spacing.md)
                                    .background(
                                        viewModel.selectedVoteChoice == choice
                                            ? choice.color.opacity(0.1)
                                            : Color.surfaceCard
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                                            .stroke(
                                                viewModel.selectedVoteChoice == choice ? choice.color : Color.separatorStandard,
                                                lineWidth: viewModel.selectedVoteChoice == choice ? 2 : 0.5
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Vote weight
                        MtrxCard(style: .glass) {
                            HStack {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: Symbols.vote)
                                        .foregroundStyle(Color.accentPrimary)
                                    Text("Your Vote Weight")
                                        .font(.mtrxCallout)
                                        .foregroundStyle(Color.labelSecondary)
                                }
                                Spacer()
                                Text(viewModel.currentVotingPower)
                                    .font(.mtrxMono)
                                    .foregroundStyle(Color.accentPrimary)
                            }
                        }

                        Spacer().frame(height: Spacing.xxl)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                }

                // Cast vote button
                VStack {
                    Spacer()

                    Button {
                        viewModel.castVote()
                    } label: {
                        Text("Cast Vote")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: viewModel.isVoting, fullWidth: true))
                    .disabled(viewModel.selectedVoteChoice == nil || viewModel.isVoting)
                    .padding(Spacing.contentPadding)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: Symbols.close)
                            .accessibilityLabel("Close")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
        }
    }
}

// MARK: - Delegate Card

struct DelegateCardView: View {
    let delegate: DelegateInfo
    let onDelegate: () -> Void

    var body: some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                MtrxAvatar(
                    text: delegate.name,
                    color: delegate.avatarColor,
                    size: Spacing.Size.avatarMedium
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(delegate.name)
                        .font(.mtrxCalloutBold)
                        .foregroundStyle(Color.labelPrimary)

                    HStack(spacing: Spacing.sm) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: Symbols.vote)
                                .font(.system(size: 10))
                            Text("\(delegate.votingPower)")
                        }
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelSecondary)

                        HStack(spacing: Spacing.xs) {
                            Image(systemName: Symbols.proposal)
                                .font(.system(size: 10))
                            Text("\(delegate.proposalsVoted) voted")
                        }
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                    }
                }

                Spacer()

                Button(action: onDelegate) {
                    Text("Delegate")
                }
                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DAOView()
        .preferredColorScheme(.dark)
}
