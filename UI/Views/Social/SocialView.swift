// SocialView.swift
// MTRX - On-chain social feed with governance, messaging, and proof sharing
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - Social Tab Sections

enum SocialTab: String, CaseIterable {
    case feed = "Feed"
    case governance = "Governance"
    case messaging = "Messaging"
}

// MARK: - Feed Filters

enum FeedFilter: String, CaseIterable {
    case all = "All"
    case verified = "Verified Only"
    case following = "Following"
    case trending = "Trending"
}

// MARK: - Social Post Model

struct SocialPostDisplay: Identifiable {
    let id: String
    let displayName: String
    let handle: String
    let avatarInitials: String
    let avatarColor: Color
    let timestamp: Date
    let body: String
    let isVerified: Bool
    let hasOnChainProof: Bool
    let proofHash: String?
    let governanceTag: String?
    var likeCount: Int
    var repostCount: Int
    var commentCount: Int
    var isLiked: Bool
    var isReposted: Bool
}

// MARK: - Governance Proposal Model

struct SocialGovernanceProposal: Identifiable {
    let id: String
    let title: String
    let description: String
    let votesFor: Int
    let votesAgainst: Int
    let quorumProgress: Double
    let endDate: Date
    let status: ProposalStatus
    var hasVoted: Bool

    var totalVotes: Int { votesFor + votesAgainst }
    var forPercentage: Double {
        totalVotes > 0 ? Double(votesFor) / Double(totalVotes) : 0
    }

    enum ProposalStatus: String {
        case active = "Active"
        case passed = "Passed"
        case rejected = "Rejected"
        case queued = "Queued"
    }
}

// MARK: - Message Thread Model

struct MessageThread: Identifiable {
    let id: String
    let name: String
    let avatarInitials: String
    let avatarColor: Color
    let lastMessage: String
    let timestamp: Date
    let unreadCount: Int
    let isEncrypted: Bool
}

// MARK: - View Model

@MainActor
final class SocialViewModel: ObservableObject {

    // MARK: State

    @Published var selectedTab: SocialTab = .feed
    @Published var selectedFilter: FeedFilter = .all
    @Published var posts: [SocialPostDisplay] = []
    @Published var proposals: [SocialGovernanceProposal] = []
    @Published var pastProposals: [SocialGovernanceProposal] = []
    @Published var threads: [MessageThread] = []
    @Published var isLoading = false
    @Published var isComposerPresented = false
    @Published var showPastProposals = false
    @Published var delegationPower: String = "12,450 MTRX"
    @Published var delegatedTo: String = "Self"

    // MARK: Init

    init() {
        loadSampleData()
    }

    // MARK: Filtered Posts

    var filteredPosts: [SocialPostDisplay] {
        switch selectedFilter {
        case .all:
            return posts
        case .verified:
            return posts.filter { $0.isVerified }
        case .following:
            return posts.filter { ["@elena.eth", "@ravi_dao", "@sofia.base"].contains($0.handle) }
        case .trending:
            return posts.sorted { ($0.likeCount + $0.repostCount) > ($1.likeCount + $1.repostCount) }
        }
    }

    // MARK: Actions

    func refresh() async {
        isLoading = true
        try? await Task.sleep(for: .seconds(0.8))
        isLoading = false
    }

    func toggleLike(postId: String) {
        guard let idx = posts.firstIndex(where: { $0.id == postId }) else { return }
        let wasLiked = posts[idx].isLiked
        posts[idx].isLiked = !wasLiked
        posts[idx].likeCount += wasLiked ? -1 : 1
        MtrxHaptics.impact(.light)
    }

    func toggleRepost(postId: String) {
        guard let idx = posts.firstIndex(where: { $0.id == postId }) else { return }
        let was = posts[idx].isReposted
        posts[idx].isReposted = !was
        posts[idx].repostCount += was ? -1 : 1
        MtrxHaptics.selection()
    }

    func voteOnProposal(_ id: String) {
        guard let idx = proposals.firstIndex(where: { $0.id == id }) else { return }
        proposals[idx].hasVoted = true
        MtrxHaptics.success()
    }

    // MARK: Sample Data

    private func loadSampleData() {
        let now = Date()
        posts = [
            SocialPostDisplay(id: "p1", displayName: "Elena Vasquez", handle: "@elena.eth", avatarInitials: "EV", avatarColor: .accentPrimary, timestamp: now.addingTimeInterval(-7200), body: "Just deployed our new escrow contract on Base. Fully audited, open-source, and gas-optimized. The future of trustless agreements is here.", isVerified: true, hasOnChainProof: true, proofHash: "0xa1b2c3...d4e5", governanceTag: nil, likeCount: 142, repostCount: 38, commentCount: 24, isLiked: false, isReposted: false),

            SocialPostDisplay(id: "p2", displayName: "Ravi Patel", handle: "@ravi_dao", avatarInitials: "RP", avatarColor: .statusInfo, timestamp: now.addingTimeInterval(-3600), body: "Governance Proposal #47 is live. We are voting on allocating 50,000 MTRX from the treasury toward developer grants. This could accelerate ecosystem growth significantly. Cast your vote before Friday.", isVerified: true, hasOnChainProof: false, proofHash: nil, governanceTag: "Proposal #47", likeCount: 89, repostCount: 52, commentCount: 31, isLiked: true, isReposted: false),

            SocialPostDisplay(id: "p3", displayName: "Sofia Nakamura", handle: "@sofia.base", avatarInitials: "SN", avatarColor: .accentTertiary, timestamp: now.addingTimeInterval(-10800), body: "Staked 25,000 MTRX in the new 90-day vault. APY looking solid at 8.7%. Who else is locking in?", isVerified: true, hasOnChainProof: true, proofHash: "0xf6g7h8...i9j0", governanceTag: nil, likeCount: 67, repostCount: 15, commentCount: 12, isLiked: false, isReposted: true),

            SocialPostDisplay(id: "p4", displayName: "Crypto Nomad", handle: "@nomad_anon", avatarInitials: "CN", avatarColor: .labelTertiary, timestamp: now.addingTimeInterval(-14400), body: "Has anyone tried the new parametric insurance module? Looking for real user feedback before I commit funds.", isVerified: false, hasOnChainProof: false, proofHash: nil, governanceTag: nil, likeCount: 23, repostCount: 4, commentCount: 18, isLiked: false, isReposted: false),

            SocialPostDisplay(id: "p5", displayName: "MTRX Foundation", handle: "@mtrx_official", avatarInitials: "MF", avatarColor: .accentPrimary, timestamp: now.addingTimeInterval(-21600), body: "Protocol upgrade v2.4 is now live on mainnet. Key improvements: 40% gas reduction on contract deployments, enhanced privacy features with ZK proofs, and new delegation mechanics for governance. Full changelog on our docs.", isVerified: true, hasOnChainProof: true, proofHash: "0xk1l2m3...n4o5", governanceTag: nil, likeCount: 534, repostCount: 187, commentCount: 92, isLiked: false, isReposted: false),

            SocialPostDisplay(id: "p6", displayName: "DeFi Builder", handle: "@defi_build3r", avatarInitials: "DB", avatarColor: .statusSuccess, timestamp: now.addingTimeInterval(-28800), body: "Built a prediction market on MTRX in 3 hours using the smart contract templates. The developer experience is genuinely impressive.", isVerified: false, hasOnChainProof: true, proofHash: "0xp6q7r8...s9t0", governanceTag: nil, likeCount: 98, repostCount: 29, commentCount: 14, isLiked: false, isReposted: false),

            SocialPostDisplay(id: "p7", displayName: "Governance Watcher", handle: "@gov_watch", avatarInitials: "GW", avatarColor: .voteFor, timestamp: now.addingTimeInterval(-36000), body: "Treasury report Q1 2026: 2.4M MTRX allocated, 1.8M disbursed across 12 grants. Transparency dashboard updated with full on-chain audit trail.", isVerified: true, hasOnChainProof: true, proofHash: "0xu1v2w3...x4y5", governanceTag: "Treasury Report", likeCount: 312, repostCount: 104, commentCount: 47, isLiked: false, isReposted: false),

            SocialPostDisplay(id: "p8", displayName: "Anonymous", handle: "@anon_user42", avatarInitials: "AU", avatarColor: .labelQuaternary, timestamp: now.addingTimeInterval(-43200), body: "First time using decentralized messaging with E2E encryption. Feels good to own my data.", isVerified: false, hasOnChainProof: false, proofHash: nil, governanceTag: nil, likeCount: 15, repostCount: 2, commentCount: 5, isLiked: false, isReposted: false),
        ]

        proposals = [
            SocialGovernanceProposal(id: "gp1", title: "Allocate 50K MTRX for Developer Grants", description: "Proposal to fund ecosystem developer grants from the community treasury to accelerate dApp development on MTRX.", votesFor: 842000, votesAgainst: 215000, quorumProgress: 0.73, endDate: now.addingTimeInterval(172800), status: .active, hasVoted: false),
            SocialGovernanceProposal(id: "gp2", title: "Reduce Protocol Fee from 0.3% to 0.1%", description: "Lower the base protocol fee to encourage higher transaction volume and attract new users to the ecosystem.", votesFor: 1200000, votesAgainst: 890000, quorumProgress: 0.91, endDate: now.addingTimeInterval(86400), status: .active, hasVoted: false),
            SocialGovernanceProposal(id: "gp3", title: "Launch Cross-Chain Bridge to Solana", description: "Fund development of a trustless bridge connecting MTRX to Solana for cross-chain asset transfers.", votesFor: 650000, votesAgainst: 120000, quorumProgress: 0.45, endDate: now.addingTimeInterval(432000), status: .active, hasVoted: false),
            SocialGovernanceProposal(id: "gp4", title: "Implement ZK-Proof Identity Verification", description: "Add zero-knowledge proof identity verification to the protocol for privacy-preserving KYC compliance.", votesFor: 980000, votesAgainst: 340000, quorumProgress: 0.82, endDate: now.addingTimeInterval(259200), status: .active, hasVoted: true),
        ]

        pastProposals = [
            SocialGovernanceProposal(id: "gp5", title: "Treasury Diversification Strategy", description: "Diversify 20% of the treasury into stablecoins.", votesFor: 1500000, votesAgainst: 300000, quorumProgress: 1.0, endDate: now.addingTimeInterval(-604800), status: .passed, hasVoted: true),
            SocialGovernanceProposal(id: "gp6", title: "Increase Staking Rewards to 12% APY", description: "Temporarily increase staking rewards.", votesFor: 400000, votesAgainst: 900000, quorumProgress: 1.0, endDate: now.addingTimeInterval(-1209600), status: .rejected, hasVoted: true),
        ]

        threads = [
            MessageThread(id: "t1", name: "Elena Vasquez", avatarInitials: "EV", avatarColor: .accentPrimary, lastMessage: "The escrow contract is ready for review.", timestamp: now.addingTimeInterval(-1800), unreadCount: 2, isEncrypted: true),
            MessageThread(id: "t2", name: "MTRX DAO Council", avatarInitials: "DC", avatarColor: .statusInfo, lastMessage: "Vote reminder: Proposal #47 closes Friday.", timestamp: now.addingTimeInterval(-5400), unreadCount: 5, isEncrypted: true),
            MessageThread(id: "t3", name: "Ravi Patel", avatarInitials: "RP", avatarColor: .accentTertiary, lastMessage: "Can you delegate your votes to me for this cycle?", timestamp: now.addingTimeInterval(-14400), unreadCount: 0, isEncrypted: true),
            MessageThread(id: "t4", name: "DeFi Builders", avatarInitials: "DB", avatarColor: .statusSuccess, lastMessage: "New template dropped for prediction markets.", timestamp: now.addingTimeInterval(-43200), unreadCount: 0, isEncrypted: false),
            MessageThread(id: "t5", name: "Sofia Nakamura", avatarInitials: "SN", avatarColor: .accentTertiary, lastMessage: "Thanks for the staking tip!", timestamp: now.addingTimeInterval(-86400), unreadCount: 1, isEncrypted: true),
        ]
    }
}

// MARK: - Social View

struct SocialView: View {
    @StateObject private var viewModel = SocialViewModel()
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    tabSelector
                    tabContent
                }
                .background(MtrxGradientBackground(style: .primary))

                composeButton
            }
            .navigationTitle("Social")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.isComposerPresented) {
                composeSheet
            }
        }
        .onAppear {
            withAnimation(Motion.springDefault.delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(SocialTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(Motion.springSnappy) {
                        viewModel.selectedTab = tab
                    }
                    MtrxHaptics.selection()
                } label: {
                    Text(tab.rawValue)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(viewModel.selectedTab == tab ? .white : Color.labelSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            viewModel.selectedTab == tab
                            ? Capsule().fill(Color.accentPrimary)
                            : Capsule().fill(Color.surfaceOverlay)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
        .background(Color.backgroundPrimary)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .feed:
            feedSection
        case .governance:
            governanceSection
        case .messaging:
            messagingSection
        }
    }

    // MARK: - Compose FAB

    private var composeButton: some View {
        Button {
            viewModel.isComposerPresented = true
            MtrxHaptics.impact(.medium)
        } label: {
            Image(systemName: Symbols.add)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentPrimary)
                .clipShape(Circle())
                .shadow(color: Color.accentPrimary.opacity(0.4), radius: 8, y: 4)
                .shadow(color: Color.accentPrimary.opacity(0.2), radius: 16, y: 8)
        }
        .padding(.trailing, Spacing.ml)
        .padding(.bottom, Spacing.lg)
        .mtrxScaleIn(isVisible: appeared, delay: 0.3)
    }

    // MARK: - Compose Sheet

    private var composeSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                TextEditor(text: .constant(""))
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.ms)
                    .background(Color.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                    .font(.mtrxBody)

                HStack {
                    Button {} label: {
                        Label("Attach Proof", systemImage: Symbols.link)
                            .font(.mtrxCaptionBold)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))

                    Spacer()
                }

                Spacer()
            }
            .padding(Spacing.contentPadding)
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.isComposerPresented = false }
                        .foregroundStyle(Color.labelSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") { viewModel.isComposerPresented = false }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Feed Section

    private var feedSection: some View {
        VStack(spacing: 0) {
            filterChips
            ScrollView {
                LazyVStack(spacing: Spacing.ms) {
                    ForEach(Array(viewModel.filteredPosts.enumerated()), id: \.element.id) { index, post in
                        PostCardView(
                            post: post,
                            onLike: { viewModel.toggleLike(postId: post.id) },
                            onRepost: { viewModel.toggleRepost(postId: post.id) }
                        )
                        .mtrxStaggeredAppearance(index: index, isVisible: appeared)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(FeedFilter.allCases, id: \.self) { filter in
                    MtrxChip(
                        label: filter.rawValue,
                        isSelected: viewModel.selectedFilter == filter
                    ) {
                        withAnimation(Motion.springSnappy) {
                            viewModel.selectedFilter = filter
                        }
                        MtrxHaptics.selection()
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Governance Section

    private var governanceSection: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                // Delegation card
                MtrxCard(style: .glass) {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Your Voting Power")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                            Text(viewModel.delegationPower)
                                .font(.mtrxMonoMedium)
                                .foregroundStyle(Color.labelPrimary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: Spacing.xs) {
                            Text("Delegated To")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                            Text(viewModel.delegatedTo)
                                .font(.mtrxCalloutBold)
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                }

                // Active proposals
                MtrxSectionHeader(title: "Active Proposals", subtitle: "\(viewModel.proposals.count) open")

                ForEach(Array(viewModel.proposals.enumerated()), id: \.element.id) { index, proposal in
                    SocialProposalCardView(
                        proposal: proposal,
                        onVote: { viewModel.voteOnProposal(proposal.id) }
                    )
                    .mtrxStaggeredAppearance(index: index, isVisible: appeared)
                }

                // Past proposals
                MtrxDivider()
                    .padding(.vertical, Spacing.sm)

                Button {
                    withAnimation(Motion.springDefault) {
                        viewModel.showPastProposals.toggle()
                    }
                } label: {
                    HStack {
                        Text("Past Proposals")
                            .font(.mtrxCalloutBold)
                            .foregroundStyle(Color.labelPrimary)
                        Spacer()
                        Image(systemName: viewModel.showPastProposals ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
                .buttonStyle(.plain)

                if viewModel.showPastProposals {
                    ForEach(viewModel.pastProposals) { proposal in
                        SocialProposalCardView(proposal: proposal, onVote: {})
                            .opacity(0.7)
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Messaging Section

    private var messagingSection: some View {
        Group {
            if viewModel.threads.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.message,
                    title: "No Messages",
                    message: "Start a conversation with another MTRX user using end-to-end encrypted messaging.",
                    actionLabel: "New Message"
                ) {}
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.threads.enumerated()), id: \.element.id) { index, thread in
                            MessageThreadRow(thread: thread)
                                .mtrxStaggeredAppearance(index: index, isVisible: appeared)

                            if index < viewModel.threads.count - 1 {
                                MtrxDivider()
                                    .padding(.leading, Spacing.contentPadding + Spacing.Size.avatarMedium + Spacing.ms)
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
        }
    }
}

// MARK: - Post Card View

struct PostCardView: View {
    let post: SocialPostDisplay
    var onLike: () -> Void = {}
    var onRepost: () -> Void = {}

    @State private var isExpanded = false
    @State private var likeScale: CGFloat = 1.0

    private let expandThreshold = 180

    var body: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.ms) {
                postHeader
                postBody
                if post.hasOnChainProof {
                    proofLink
                }
                if let tag = post.governanceTag {
                    governanceTag(tag)
                }
                engagementBar
            }
        }
    }

    // MARK: Header

    private var postHeader: some View {
        HStack(spacing: Spacing.avatarContentGap) {
            MtrxAvatar(text: post.avatarInitials, color: post.avatarColor, size: Spacing.Size.avatarMedium)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(post.displayName)
                        .font(.mtrxCalloutBold)
                        .foregroundStyle(Color.labelPrimary)

                    if post.isVerified {
                        Image(systemName: Symbols.verified)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentPrimary)
                    }
                }

                HStack(spacing: Spacing.xs) {
                    Text(post.handle)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)

                    Text("  \(relativeTimestamp(post.timestamp))")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                }
            }

            Spacer()

            Button {} label: {
                Image(systemName: Symbols.more)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.labelTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Body

    @ViewBuilder
    private var postBody: some View {
        let shouldTruncate = post.body.count > expandThreshold && !isExpanded

        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(shouldTruncate ? String(post.body.prefix(expandThreshold)) + "..." : post.body)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelPrimary)
                .lineSpacing(3)

            if post.body.count > expandThreshold {
                Button {
                    withAnimation(Motion.springDefault) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "Read more")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.accentPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Proof Link

    private var proofLink: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: Symbols.lock)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.statusSuccess)

            Text("View on-chain proof")
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.statusSuccess)

            if let hash = post.proofHash {
                Text(hash)
                    .font(.mtrxMonoTiny)
                    .foregroundStyle(Color.labelTertiary)
            }

            Spacer()

            Image(systemName: Symbols.externalLink)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.statusSuccess)
        }
        .padding(Spacing.sm)
        .background(Color.statusSuccess.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }

    // MARK: Governance Tag

    private func governanceTag(_ tag: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: Symbols.dao)
                .font(.system(size: 11, weight: .semibold))
            Text(tag)
                .font(.mtrxCaptionBold)
        }
        .foregroundStyle(Color.statusInfo)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.statusInfo.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: Engagement Bar

    private var engagementBar: some View {
        HStack(spacing: Spacing.ml) {
            // Like
            Button {
                withAnimation(Motion.springBouncy) {
                    likeScale = 1.3
                }
                onLike()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(Motion.springSnappy) {
                        likeScale = 1.0
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: post.isLiked ? Symbols.like : "heart")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(post.isLiked ? Color.statusError : Color.labelTertiary)
                        .scaleEffect(likeScale)
                    Text("\(post.likeCount)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(post.isLiked ? Color.statusError : Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)

            // Repost
            Button {
                onRepost()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: Symbols.repost)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(post.isReposted ? Color.statusSuccess : Color.labelTertiary)
                    Text("\(post.repostCount)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(post.isReposted ? Color.statusSuccess : Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)

            // Comment
            Button {} label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.labelTertiary)
                    Text("\(post.commentCount)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Share
            Button {} label: {
                Image(systemName: Symbols.share)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.labelTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private func relativeTimestamp(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

// MARK: - Proposal Card View

struct SocialProposalCardView: View {
    let proposal: SocialGovernanceProposal
    var onVote: () -> Void = {}

    var body: some View {
        MtrxCard(style: .standard, accentEdge: .leading) {
            VStack(alignment: .leading, spacing: Spacing.ms) {
                // Status badge + time remaining
                HStack {
                    MtrxBadge(
                        text: proposal.status.rawValue,
                        style: statusBadgeStyle
                    )
                    Spacer()
                    if proposal.status == .active {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: Symbols.clock)
                                .font(.system(size: 11))
                            Text(timeRemaining)
                                .font(.mtrxCaption1)
                        }
                        .foregroundStyle(Color.labelSecondary)
                    }
                }

                // Title + description
                Text(proposal.title)
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)

                Text(proposal.description)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)

                // Vote progress bar
                VStack(spacing: Spacing.xs) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.voteAgainst.opacity(0.3))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.voteFor)
                                .frame(width: geo.size.width * proposal.forPercentage, height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("For \(Int(proposal.forPercentage * 100))%")
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.voteFor)
                        Spacer()
                        Text("Against \(Int((1 - proposal.forPercentage) * 100))%")
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.voteAgainst)
                    }
                }

                // Quorum + vote button
                HStack {
                    MtrxProgressRing(
                        progress: proposal.quorumProgress,
                        size: 40,
                        lineWidth: 4,
                        color: proposal.quorumProgress >= 1.0 ? .quorumMet : .accentPrimary
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quorum")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Text(proposal.quorumProgress >= 1.0 ? "Reached" : "\(Int(proposal.quorumProgress * 100))%")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(proposal.quorumProgress >= 1.0 ? Color.quorumMet : Color.labelPrimary)
                    }

                    Spacer()

                    if proposal.status == .active {
                        Button {
                            onVote()
                        } label: {
                            Text(proposal.hasVoted ? "Voted" : "Vote")
                        }
                        .buttonStyle(MtrxButtonStyle(
                            variant: proposal.hasVoted ? .ghost : .primary,
                            size: .compact
                        ))
                        .disabled(proposal.hasVoted)
                    }
                }
            }
        }
    }

    private var statusBadgeStyle: MtrxBadge.BadgeStyle {
        switch proposal.status {
        case .active: return .accent
        case .passed: return .success
        case .rejected: return .error
        case .queued: return .info
        }
    }

    private var timeRemaining: String {
        let interval = proposal.endDate.timeIntervalSince(Date())
        if interval <= 0 { return "Ended" }
        let hours = Int(interval / 3600)
        if hours < 24 { return "\(hours)h left" }
        let days = hours / 24
        return "\(days)d \(hours % 24)h left"
    }
}

// MARK: - Message Thread Row

struct MessageThreadRow: View {
    let thread: MessageThread

    var body: some View {
        HStack(spacing: Spacing.avatarContentGap) {
            ZStack(alignment: .bottomTrailing) {
                MtrxAvatar(
                    text: thread.avatarInitials,
                    color: thread.avatarColor,
                    size: Spacing.Size.avatarMedium
                )

                if thread.isEncrypted {
                    Image(systemName: Symbols.lock)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.statusSuccess)
                        .clipShape(Circle())
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(thread.name)
                        .font(.mtrxCalloutBold)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Text(relativeTimestamp(thread.timestamp))
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }

                HStack {
                    Text(thread.lastMessage)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)

                    Spacer()

                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.accentPrimary)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.ms)
        .contentShape(Rectangle())
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}

// MARK: - Preview

#Preview("Social") {
    SocialView()
        .preferredColorScheme(.dark)
        .environmentObject(AppState())
        .environmentObject(WalletManager())
}
