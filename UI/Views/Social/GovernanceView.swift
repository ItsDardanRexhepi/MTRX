// GovernanceView.swift
// MTRX -- On-chain governance feed with proposal voting
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - View Model

@MainActor
final class GovernanceViewModel: ObservableObject {

    struct Proposal: Identifiable {
        let id: String
        let title: String
        let author: String
        let description: String
        let forVotes: Int
        let againstVotes: Int
        let quorumProgress: Double
        let timeRemaining: String
        let status: Status
        let fullText: String

        var totalVotes: Int { forVotes + againstVotes }
        var forPercent: Double { totalVotes > 0 ? Double(forVotes) / Double(totalVotes) : 0 }
        var againstPercent: Double { totalVotes > 0 ? Double(againstVotes) / Double(totalVotes) : 0 }

        enum Status: String {
            case active   = "Active"
            case passed   = "Passed"
            case rejected = "Rejected"

            var badgeStyle: MtrxBadge.BadgeStyle {
                switch self {
                case .active:   return .info
                case .passed:   return .success
                case .rejected: return .error
                }
            }
        }
    }

    enum VoteOption: String, CaseIterable, Identifiable {
        case forVote  = "For"
        case against  = "Against"
        case abstain  = "Abstain"

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

    // MARK: Published State

    @Published var proposals: [Proposal] = []
    @Published var showVoteSheet = false
    @Published var selectedProposal: Proposal?
    @Published var selectedVote: VoteOption?
    @Published var hasVoted = false
    @Published var showHistory = false

    // MARK: Computed

    var activeProposals: [Proposal] { proposals.filter { $0.status == .active } }
    var historyProposals: [Proposal] { proposals.filter { $0.status != .active } }

    var votingPower: String { "12,450 MTRX" }
    var participationRate: String { "67%" }

    // MARK: Init

    init() { loadSampleData() }

    // MARK: Actions

    func confirmVote() {
        guard selectedProposal != nil, selectedVote != nil else { return }
        MtrxHaptics.success()
        hasVoted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showVoteSheet = false
            self?.hasVoted = false
            self?.selectedVote = nil
            self?.selectedProposal = nil
        }
    }

    func openVoteSheet(for proposal: Proposal) {
        selectedProposal = proposal
        selectedVote = nil
        hasVoted = false
        showVoteSheet = true
    }

    // MARK: Sample Data

    private func loadSampleData() {
        proposals = [
            Proposal(
                id: "MIP-42", title: "Increase Staking Rewards to 9.5% APY",
                author: "neo.eth", description: "Proposal to adjust the staking reward rate from the current 8.7% to 9.5% APY to incentivize long-term token holders and improve network security through increased stake participation.",
                forVotes: 8420, againstVotes: 2130, quorumProgress: 0.78,
                timeRemaining: "3d 14h left", status: .active,
                fullText: "This proposal seeks to increase the MTRX staking reward rate from 8.7% to 9.5% APY. The increase is designed to incentivize long-term holding and improve decentralization by encouraging more participants to stake. The treasury impact has been modeled and remains sustainable for the next 24 months."
            ),
            Proposal(
                id: "MIP-41", title: "Add Base L2 Bridge Support",
                author: "0xbuilder.eth", description: "Integrate native bridging support for Base Layer 2 to reduce gas costs and expand the ecosystem reach for MTRX smart contracts and token transfers.",
                forVotes: 11200, againstVotes: 890, quorumProgress: 0.92,
                timeRemaining: "1d 6h left", status: .active,
                fullText: "Integrate Coinbase Base L2 as a natively supported chain for bridging MTRX tokens and deploying smart contracts. This will significantly reduce gas costs for users and open access to the Base ecosystem. Implementation timeline is 6 weeks post-approval."
            ),
            Proposal(
                id: "MIP-40", title: "Treasury Allocation for Developer Grants",
                author: "dao_council.eth", description: "Allocate 500,000 MTRX from the treasury to fund developer grants for building dApps, tooling, and integrations on the MTRX protocol.",
                forVotes: 6750, againstVotes: 4200, quorumProgress: 0.65,
                timeRemaining: "5d 2h left", status: .active,
                fullText: "This proposal allocates 500,000 MTRX tokens from the DAO treasury to a developer grants program. Grants will be distributed quarterly over 12 months, with a review committee of 5 elected members overseeing fund allocation. Priority areas include DeFi integrations, developer tooling, and mobile SDK improvements."
            ),
            Proposal(
                id: "MIP-39", title: "Reduce Platform Fee from 2.5% to 1.5%",
                author: "community_voice.eth", description: "Lower the platform access contribution from 2.5% to 1.5% to make MTRX more competitive with other smart contract platforms.",
                forVotes: 14300, againstVotes: 1200, quorumProgress: 1.0,
                timeRemaining: "Ended", status: .passed,
                fullText: "Successfully passed. The platform fee has been reduced from 2.5% to 1.5% effective immediately. This change applies to all new smart contract deployments and marketplace transactions."
            ),
            Proposal(
                id: "MIP-38", title: "Mandatory KYC for Enterprise Tier",
                author: "compliance_wg.eth", description: "Require identity verification for Enterprise subscription tier users to meet regulatory compliance requirements in key markets.",
                forVotes: 3200, againstVotes: 9800, quorumProgress: 1.0,
                timeRemaining: "Ended", status: .rejected,
                fullText: "Rejected by the community. The proposal to require KYC for Enterprise users was voted down due to privacy concerns and the platform's commitment to permissionless access."
            ),
            Proposal(
                id: "MIP-37", title: "Enable Cross-Chain NFT Transfers",
                author: "nft_council.eth", description: "Implement cross-chain NFT bridging to allow MTRX NFTs to be transferred between Ethereum mainnet, Base, and Arbitrum.",
                forVotes: 10500, againstVotes: 2100, quorumProgress: 1.0,
                timeRemaining: "Ended", status: .passed,
                fullText: "Successfully passed. Cross-chain NFT transfers are now supported between Ethereum, Base, and Arbitrum networks. Implementation completed in Sprint 24."
            ),
        ]
    }
}

// MARK: - Main View

struct GovernanceView: View {
    @StateObject private var viewModel = GovernanceViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    statsBar
                    activeProposalsSection
                    historySection
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Governance")
            .sheet(isPresented: $viewModel.showVoteSheet) {
                voteSheet
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: Spacing.sm) {
            statPill(label: "Active Proposals", value: "\(viewModel.activeProposals.count)")
            statPill(label: "Voting Power", value: viewModel.votingPower)
            statPill(label: "Participation", value: viewModel.participationRate)
        }
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }

    // MARK: - Active Proposals

    private var activeProposalsSection: some View {
        VStack(spacing: Spacing.ms) {
            MtrxSectionHeader(title: "Active Proposals")

            if viewModel.activeProposals.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.dao,
                    title: "No Active Proposals",
                    message: "There are no governance proposals open for voting right now. Check back soon."
                )
            }

            ForEach(viewModel.activeProposals) { proposal in
                proposalCard(proposal)
            }
        }
    }

    private func proposalCard(_ proposal: GovernanceViewModel.Proposal) -> some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.ms) {
                // Top row: ID badge + status
                HStack {
                    MtrxBadge(text: proposal.id, style: .accent)
                    Spacer()
                    MtrxBadge(text: proposal.status.rawValue, style: proposal.status.badgeStyle)
                }

                // Title
                Text(proposal.title)
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(2)

                // Author
                Text("by \(proposal.author)")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)

                // Description
                Text(proposal.description)
                    .font(.mtrxSubheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)

                MtrxDivider()

                // Vote bar
                voteBar(forPercent: proposal.forPercent, againstPercent: proposal.againstPercent)

                // Quorum + time row
                HStack(spacing: Spacing.ms) {
                    MtrxProgressRing(
                        progress: proposal.quorumProgress,
                        size: 36,
                        lineWidth: 4,
                        color: proposal.quorumProgress >= 1.0 ? .quorumMet : .accentPrimary,
                        showLabel: true
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quorum")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(proposal.quorumProgress >= 1.0 ? "Reached" : "\(Int(proposal.quorumProgress * 100))% of target")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(proposal.quorumProgress >= 1.0 ? Color.quorumMet : Color.labelSecondary)
                    }

                    Spacer()

                    // Time remaining
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.clock)
                            .font(.system(size: 12))
                        Text(proposal.timeRemaining)
                            .font(.mtrxCaption1)
                    }
                    .foregroundStyle(Color.labelSecondary)
                }

                // Vote button
                if proposal.status == .active {
                    Button {
                        viewModel.openVoteSheet(for: proposal)
                    } label: {
                        Text("Vote")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Vote Bar

    private func voteBar(forPercent: Double, againstPercent: Double) -> some View {
        VStack(spacing: Spacing.xs) {
            // Percentage labels
            HStack {
                HStack(spacing: Spacing.xs) {
                    Circle().fill(Color.voteFor).frame(width: 8, height: 8)
                    Text("For \(Int(forPercent * 100))%")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.voteFor)
                }
                Spacer()
                HStack(spacing: Spacing.xs) {
                    Text("Against \(Int(againstPercent * 100))%")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.voteAgainst)
                    Circle().fill(Color.voteAgainst).frame(width: 8, height: 8)
                }
            }

            // Horizontal bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.voteFor)
                        .frame(width: max(geo.size.width * forPercent, 4))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.voteAgainst)
                        .frame(width: max(geo.size.width * againstPercent, 4))

                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .background(Capsule().fill(Color.surfaceOverlay))
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(spacing: Spacing.ms) {
            Button {
                withAnimation(Motion.springDefault) {
                    viewModel.showHistory.toggle()
                }
            } label: {
                HStack {
                    Text("History")
                        .font(.mtrxTitle3)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Image(systemName: viewModel.showHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)

            if viewModel.showHistory {
                ForEach(viewModel.historyProposals) { proposal in
                    MtrxCard(style: .outlined) {
                        HStack(spacing: Spacing.ms) {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.sm) {
                                    MtrxBadge(text: proposal.id, style: .neutral)
                                    MtrxBadge(text: proposal.status.rawValue, style: proposal.status.badgeStyle)
                                }
                                Text(proposal.title)
                                    .font(.mtrxSubheadline)
                                    .foregroundStyle(Color.labelPrimary)
                                    .lineLimit(1)
                                Text("by \(proposal.author)")
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelTertiary)
                            }
                            Spacer()
                        }
                    }
                    .transition(.mtrxSlideUp)
                }
            }
        }
    }

    // MARK: - Vote Sheet

    private var voteSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if let proposal = viewModel.selectedProposal {
                        MtrxSheetHeader(
                            title: "Cast Your Vote",
                            subtitle: proposal.id,
                            onDismiss: { viewModel.showVoteSheet = false }
                        )

                        // Full proposal text
                        MtrxCard(style: .standard) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(proposal.title)
                                    .font(.mtrxHeadline)
                                    .foregroundStyle(Color.labelPrimary)

                                Text("by \(proposal.author)")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)

                                MtrxDivider()

                                Text(proposal.fullText)
                                    .font(.mtrxBody)
                                    .foregroundStyle(Color.labelPrimary)
                                    .lineSpacing(4)
                            }
                        }

                        // Vote options
                        VStack(spacing: Spacing.ms) {
                            Text("Choose your vote")
                                .font(.mtrxCalloutBold)
                                .foregroundStyle(Color.labelPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(GovernanceViewModel.VoteOption.allCases) { option in
                                voteOptionCard(option)
                            }
                        }

                        // Vote weight
                        MtrxCard(style: .glass) {
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text("Your Vote Weight")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                    Text(viewModel.votingPower)
                                        .font(.mtrxMonoSmall)
                                        .foregroundStyle(Color.accentPrimary)
                                }
                                Spacer()
                                Image(systemName: Symbols.stake)
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.accentPrimary)
                            }
                        }

                        // Confirm button
                        if viewModel.hasVoted {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: Symbols.complete)
                                    .foregroundStyle(Color.statusSuccess)
                                Text("Vote submitted successfully")
                                    .font(.mtrxCalloutBold)
                                    .foregroundStyle(Color.statusSuccess)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                        } else {
                            Button {
                                viewModel.confirmVote()
                            } label: {
                                Text("Confirm Vote")
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
                            .disabled(viewModel.selectedVote == nil)
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Color.backgroundPrimary)
        }
    }

    private func voteOptionCard(_ option: GovernanceViewModel.VoteOption) -> some View {
        let isSelected = viewModel.selectedVote == option

        return Button {
            withAnimation(Motion.springSnappy) {
                viewModel.selectedVote = option
            }
            MtrxHaptics.selection()
        } label: {
            HStack(spacing: Spacing.ms) {
                Image(systemName: option.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : option.color)
                    .frame(width: 48, height: 48)
                    .background(isSelected ? option.color : option.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.rawValue)
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)
                    Text(voteDescription(for: option))
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: Symbols.alertSuccess)
                        .font(.system(size: 22))
                        .foregroundStyle(option.color)
                }
            }
            .padding(Spacing.md)
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                    .stroke(isSelected ? option.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func voteDescription(for option: GovernanceViewModel.VoteOption) -> String {
        switch option {
        case .forVote:  return "Support this proposal"
        case .against:  return "Oppose this proposal"
        case .abstain:  return "Participate without taking a side"
        }
    }
}

// MARK: - Preview

#Preview("Governance") {
    GovernanceView()
}
