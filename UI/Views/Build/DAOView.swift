// DAOView.swift
// MTRX
//
// Component 6 — DAO dashboard with proposals, voting interface, and treasury.

import SwiftUI

// MARK: - DAO View

struct DAOView: View {
    @State private var selectedTab: DAOTab = .proposals
    @State private var proposals: [DAOProposal] = DAOProposal.sampleData
    @State private var treasuryBalance: String = "$1,245,670"
    @State private var memberCount: Int = 2_456
    @State private var votingPower: String = "1,250 MTRX"

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sectionGap) {
                daoHeader
                statsBar
                tabSelector
                tabContent
            }
        }
        .navigationTitle("DAO")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Create proposal
                } label: {
                    Image(systemName: Symbols.addCircle)
                }
            }
        }
    }

    // MARK: - DAO Header

    private var daoHeader: some View {
        VStack(spacing: Spacing.sm) {
            Circle()
                .fill(LinearGradient.mtrxPrimary)
                .frame(width: Spacing.Size.avatarXLarge, height: Spacing.Size.avatarXLarge)
                .overlay(
                    Image(systemName: Symbols.dao)
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                )

            Text("MTRX DAO")
                .font(.mtrxTitle2)

            Text("Decentralized governance for the MTRX ecosystem")
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.md) {
                Label(votingPower, systemImage: Symbols.vote)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.accentPrimary)

                Label("Member", systemImage: Symbols.verified)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.statusSuccess)
            }
        }
        .padding(Spacing.contentPadding)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: Spacing.md) {
            DAOStatCell(title: "Treasury", value: treasuryBalance, icon: Symbols.treasury)
            DAOStatCell(title: "Members", value: "\(memberCount)", icon: Symbols.backers)
            DAOStatCell(title: "Proposals", value: "\(proposals.count)", icon: Symbols.proposal)
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(DAOTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .proposals:
            proposalsContent
        case .treasury:
            treasuryContent
        case .delegates:
            delegatesContent
        }
    }

    // MARK: - Proposals

    private var proposalsContent: some View {
        LazyVStack(spacing: Spacing.sm) {
            ForEach(proposals) { proposal in
                NavigationLink {
                    ProposalDetailView(proposal: proposal)
                } label: {
                    ProposalCard(proposal: proposal)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Treasury

    private var treasuryContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Treasury Balance")
                .font(.mtrxTitle3)

            Text(treasuryBalance)
                .font(.mtrxMonoLarge)
                .foregroundStyle(Color.accentPrimary)

            Divider()

            VStack(spacing: Spacing.sm) {
                TreasuryAssetRow(token: "USDC", amount: "$800,000", percentage: 64)
                TreasuryAssetRow(token: "ETH", amount: "$345,670", percentage: 28)
                TreasuryAssetRow(token: "MTRX", amount: "$100,000", percentage: 8)
            }

            Divider()

            Text("Recent Treasury Activity")
                .font(.mtrxHeadline)

            ForEach(0..<3, id: \.self) { i in
                HStack {
                    Image(systemName: i % 2 == 0 ? Symbols.send : Symbols.receive)
                        .foregroundStyle(i % 2 == 0 ? Color.statusError : Color.statusSuccess)
                    VStack(alignment: .leading) {
                        Text(i % 2 == 0 ? "Grant Payment" : "Revenue")
                            .font(.mtrxBodyBold)
                        Text("Proposal #\(100 + i)")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Text(i % 2 == 0 ? "-$25,000" : "+$12,500")
                        .font(.mtrxBodyTabular)
                        .foregroundStyle(i % 2 == 0 ? Color.statusError : Color.statusSuccess)
                }
            }
        }
        .padding(Spacing.contentPadding)
    }

    // MARK: - Delegates

    private var delegatesContent: some View {
        LazyVStack(spacing: Spacing.sm) {
            ForEach(DelegateItem.sampleData) { delegate in
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(Color.accentPrimary.opacity(0.2))
                        .frame(width: Spacing.Size.avatarMedium, height: Spacing.Size.avatarMedium)
                        .overlay(
                            Text(String(delegate.name.prefix(2)))
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.accentPrimary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(delegate.name)
                            .font(.mtrxBodyBold)
                        Text(delegate.address)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(delegate.votingPower)
                            .font(.mtrxBodyTabular)
                        Text("\(delegate.proposalsVoted) votes")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                .padding(Spacing.sm)
                .background(Color.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }
}

// MARK: - Proposal Card

struct ProposalCard: View {
    let proposal: DAOProposal

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("#\(proposal.number)")
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color.labelTertiary)

                Text(proposal.title)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)

                Spacer()

                Text(proposal.status.rawValue)
                    .font(.mtrxCaptionBold)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background(proposal.status.color.opacity(0.15))
                    .foregroundStyle(proposal.status.color)
                    .clipShape(Capsule())
            }

            Text(proposal.summary)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)

            // Vote bars
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.voteFor)
                        .frame(width: geo.size.width * proposal.forPercentage)

                    Rectangle()
                        .fill(Color.voteAgainst)
                        .frame(width: geo.size.width * proposal.againstPercentage)

                    Rectangle()
                        .fill(Color.voteAbstain)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            HStack {
                HStack(spacing: Spacing.xs) {
                    Circle().fill(Color.voteFor).frame(width: 8, height: 8)
                    Text("\(Int(proposal.forPercentage * 100))% For")
                }

                HStack(spacing: Spacing.xs) {
                    Circle().fill(Color.voteAgainst).frame(width: 8, height: 8)
                    Text("\(Int(proposal.againstPercentage * 100))% Against")
                }

                Spacer()

                Text(proposal.deadline)
                    .foregroundStyle(Color.labelTertiary)
            }
            .font(.mtrxCaption2)
        }
        .padding(Spacing.cardPadding)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Proposal Detail View

struct ProposalDetailView: View {
    let proposal: DAOProposal
    @State private var selectedVote: VoteChoice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("#\(proposal.number) \(proposal.title)")
                        .font(.mtrxTitle2)

                    Text("Proposed by \(proposal.proposer)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                Text(proposal.summary)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)

                // Vote section
                if proposal.status == .active {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Cast Your Vote")
                            .font(.mtrxTitle3)

                        HStack(spacing: Spacing.sm) {
                            ForEach(VoteChoice.allCases, id: \.self) { choice in
                                Button {
                                    withAnimation(Motion.springSnappy) {
                                        selectedVote = choice
                                    }
                                } label: {
                                    VStack(spacing: Spacing.xs) {
                                        Image(systemName: choice.icon)
                                            .font(.system(size: 24))
                                        Text(choice.rawValue)
                                            .font(.mtrxCaptionBold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(Spacing.md)
                                    .background(
                                        selectedVote == choice
                                            ? choice.color.opacity(0.2)
                                            : Color.surfaceOverlay
                                    )
                                    .foregroundStyle(
                                        selectedVote == choice
                                            ? choice.color
                                            : Color.labelPrimary
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm)
                                            .stroke(selectedVote == choice ? choice.color : .clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button { } label: {
                            Text("Submit Vote")
                                .font(.mtrxHeadline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: Spacing.Size.buttonHeight)
                                .background(selectedVote != nil ? Color.accentPrimary : Color.labelTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        }
                        .disabled(selectedVote == nil)
                    }
                }
            }
            .padding(Spacing.contentPadding)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Supporting Components

struct DAOStatCell: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentPrimary)
            Text(value)
                .font(.mtrxHeadline)
            Text(title)
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

struct TreasuryAssetRow: View {
    let token: String
    let amount: String
    let percentage: Int

    var body: some View {
        HStack {
            Text(token)
                .font(.mtrxBodyBold)
            Spacer()
            Text(amount)
                .font(.mtrxBodyTabular)
            Text("(\(percentage)%)")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
        }
    }
}

// MARK: - Enums & Models

enum DAOTab: String, CaseIterable {
    case proposals = "Proposals"
    case treasury = "Treasury"
    case delegates = "Delegates"
}

enum VoteChoice: String, CaseIterable {
    case forVote = "For"
    case against = "Against"
    case abstain = "Abstain"

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

enum ProposalStatus: String {
    case active = "Active"
    case passed = "Passed"
    case defeated = "Defeated"
    case queued = "Queued"
    case executed = "Executed"

    var color: Color {
        switch self {
        case .active: return .statusInfo
        case .passed: return .statusSuccess
        case .defeated: return .statusError
        case .queued: return .statusWarning
        case .executed: return .accentPrimary
        }
    }
}

struct DAOProposal: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let summary: String
    let proposer: String
    let status: ProposalStatus
    let forPercentage: Double
    let againstPercentage: Double
    let deadline: String

    static let sampleData: [DAOProposal] = [
        DAOProposal(number: 42, title: "Treasury Diversification", summary: "Diversify 20% of treasury into ETH and stablecoins for risk management.", proposer: "0xab12...ef34", status: .active, forPercentage: 0.68, againstPercentage: 0.22, deadline: "2d left"),
        DAOProposal(number: 41, title: "Developer Grant Program", summary: "Allocate $100K for quarterly developer grants.", proposer: "0x9876...5432", status: .passed, forPercentage: 0.82, againstPercentage: 0.12, deadline: "Ended"),
        DAOProposal(number: 40, title: "Protocol Fee Reduction", summary: "Reduce protocol fees from 0.3% to 0.25%.", proposer: "0xfedc...ba98", status: .active, forPercentage: 0.45, againstPercentage: 0.35, deadline: "5d left"),
    ]
}

struct DelegateItem: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let votingPower: String
    let proposalsVoted: Int

    static let sampleData: [DelegateItem] = [
        DelegateItem(name: "Alice.eth", address: "0xab12...ef34", votingPower: "125K", proposalsVoted: 38),
        DelegateItem(name: "Bob.eth", address: "0x9876...5432", votingPower: "89K", proposalsVoted: 25),
        DelegateItem(name: "Carol.eth", address: "0xfedc...ba98", votingPower: "67K", proposalsVoted: 42),
    ]
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DAOView()
    }
}
