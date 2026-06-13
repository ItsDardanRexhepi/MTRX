// SocialView.swift
// MTRX - On-chain social feed with governance, messaging, and proof sharing
// Copyright 2026 OPN MATRX. All rights reserved.

import PhotosUI
import SwiftUI

// MARK: - Social Tab Sections

enum SocialTab: String, CaseIterable {
    case feed = "Feed"
    case governance = "Governance"
    case messaging = "Messaging"
    case groups = "Groups"
    case network = "Network"
    case live = "Live"

    var icon: String {
        switch self {
        case .feed: return "house"
        case .governance: return "building.columns"
        case .messaging: return "bubble.left.and.bubble.right"
        case .groups: return "person.3"
        case .network: return "point.3.connected.trianglepath.dotted"
        case .live: return "dot.radiowaves.left.and.right"
        }
    }
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
    /// Rich attachments — photo, video file in the social media
    /// directory, or an external link.
    var imageData: Data? = nil
    var videoFileName: String? = nil
    var linkURL: String? = nil
    /// Set when this post was brought over from another platform.
    var importedFrom: String? = nil
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

    /// One feed for the whole app — the Social tab and the Home feed
    /// window read and write the same posts, so a like anywhere is a
    /// like everywhere.
    static let shared = SocialViewModel()

    // MARK: State

    @Published var selectedTab: SocialTab = .feed
    @Published var selectedFilter: FeedFilter = .all
    @Published var posts: [SocialPostDisplay] = []
    @Published var proposals: [SocialGovernanceProposal] = []
    @Published var pastProposals: [SocialGovernanceProposal] = []
    @Published var threads: [MessageThread] = []
    @Published var isLoading = false
    @Published var isComposerPresented = false
    @Published var composerText = ""
    @Published var attachProof = false
    @Published var composerImageData: Data?
    @Published var composerVideoFileName: String?
    @Published var composerLink = ""
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

    /// Endless timeline: when the user nears the bottom, older pages
    /// materialize — no stopping cues, capped so memory stays sane.
    private var timelinePage = 0

    func loadMoreTimeline() {
        guard timelinePage < 6, posts.count < 200 else { return }
        timelinePage += 1
        let page = timelinePage
        let base = Array(posts.suffix(8))
        let older: [SocialPostDisplay] = base.map { p in
            SocialPostDisplay(
                id: UUID().uuidString,
                displayName: p.displayName,
                handle: p.handle,
                avatarInitials: p.avatarInitials,
                avatarColor: p.avatarColor,
                timestamp: p.timestamp.addingTimeInterval(-86_400 * Double(page)),
                body: p.body,
                isVerified: p.isVerified,
                hasOnChainProof: p.hasOnChainProof,
                proofHash: p.proofHash,
                governanceTag: p.governanceTag,
                likeCount: max(1, p.likeCount * 2 / 3),
                repostCount: p.repostCount * 2 / 3,
                commentCount: p.commentCount * 2 / 3,
                isLiked: false,
                isReposted: false,
                imageData: p.imageData,
                videoFileName: p.videoFileName,
                linkURL: p.linkURL,
                importedFrom: p.importedFrom
            )
        }
        posts.append(contentsOf: older)
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

    /// Publish the composer text — and any attached photo, video, or
    /// link — as a new post at the top of the feed.
    func publishPost(displayName rawName: String) {
        let displayName = rawName.isEmpty ? "You" : rawName
        let body = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachment = composerImageData != nil || composerVideoFileName != nil
        guard !body.isEmpty || hasAttachment else { return }

        let initials = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        let handle = SocialIdentity.shared.handle(displayName: rawName)
        let link = composerLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLink = link.isEmpty
            ? nil
            : (link.hasPrefix("http") ? link : "https://" + link)

        posts.insert(SocialPostDisplay(
            id: UUID().uuidString,
            displayName: displayName,
            handle: handle,
            avatarInitials: initials.isEmpty ? "ME" : initials,
            avatarColor: .trinityPrimary,
            timestamp: Date(),
            body: body,
            isVerified: true,
            hasOnChainProof: attachProof,
            proofHash: attachProof
                ? "0x" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased() + "...verified"
                : nil,
            governanceTag: nil,
            likeCount: 0,
            repostCount: 0,
            commentCount: 0,
            isLiked: false,
            isReposted: false,
            imageData: composerImageData,
            videoFileName: composerVideoFileName,
            linkURL: normalizedLink
        ), at: 0)

        composerText = ""
        attachProof = false
        composerImageData = nil
        composerVideoFileName = nil
        composerLink = ""
        isComposerPresented = false
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
    @ObservedObject private var viewModel = SocialViewModel.shared
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var socialIdentity = SocialIdentity.shared
    @ObservedObject private var theme = SocialTheme.shared
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var showProfile = false
    @State private var showThemePicker = false
    @State private var showNotifications = false
    @State private var showSocialSettings = false
    @State private var showUpsell = false
    @AppStorage("com.mtrx.subscriptionTier") private var tierRaw: String = SubscriptionTier.free.rawValue
    private var currentTier: SubscriptionTier { SubscriptionTier(rawValue: tierRaw) ?? .free }
    @Namespace private var tabUnderlineNS
    @State private var appeared = false
    @State private var showProofPicker = false
    @State private var commentingOnPost: SocialPostDisplay? = nil
    @State private var postActionTarget: SocialPostDisplay? = nil
    @State private var actionFeedback: String? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    tabSelector
                    tabContent
                }
                .background(MtrxGradientBackground(style: .primary))

                composeButton

                if let feedback = actionFeedback {
                    VStack {
                        Spacer()
                        MtrxToast(message: feedback)
                            .padding(.bottom, 96)
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear { DailyFlow.shared.mark(.social) }
            .navigationTitle("Social")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Your avatar on the left opens your profile.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        MtrxHaptics.impact(.light)
                        showProfile = true
                    } label: {
                        Group {
                            if let avatar = socialIdentity.avatarImage {
                                Image(uiImage: avatar).resizable().scaledToFill()
                            } else {
                                LinearGradient(colors: [.trinityPrimary, .trinitySecondary],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white)
                                    )
                            }
                        }
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        // The photo fills the whole circle, no outline — just
                        // a subtle ambient glow in the photo's own color.
                        .shadow(color: socialIdentity.avatarGlow.opacity(0.6), radius: 6)
                        .shadow(color: socialIdentity.avatarGlow.opacity(0.22), radius: 12)
                    }
                }

                // The MTRX mark sits center, like every timeline app.
                ToolbarItem(placement: .principal) {
                    Text("M")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [theme.accent, theme.accent.opacity(0.6)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .mtrxGlow(color: theme.accent, radius: 4)
                }

                // One settings entry — notifications, theme, and the AI
                // tools all live inside it now.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            MtrxHaptics.impact(.light)
                            showNotifications = true
                        } label: {
                            Label("Notifications", systemImage: "bell")
                        }

                        Button {
                            MtrxHaptics.impact(.light)
                            if currentTier >= .pro { showThemePicker = true } else { showUpsell = true }
                        } label: {
                            Label(currentTier >= .pro ? "Theme color" : "Theme color (Pro)",
                                  systemImage: currentTier >= .pro ? "paintpalette" : "lock.fill")
                        }

                        Button {
                            MtrxHaptics.selection()
                            if currentTier >= .enterprise {
                                withAnimation(Motion.springSnappy) {
                                    viewModel.selectedFilter =
                                        viewModel.selectedFilter == .trending ? .all : .trending
                                }
                            } else { showUpsell = true }
                        } label: {
                            Label(currentTier >= .enterprise ? "AI curation" : "AI curation (Enterprise)",
                                  systemImage: currentTier >= .enterprise ? "sparkles" : "lock.fill")
                        }

                        Divider()

                        Button {
                            MtrxHaptics.impact(.light)
                            showSocialSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showNotifications) {
                NotificationCenterView()
            }
            .sheet(isPresented: $showSocialSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showUpsell) {
                SubscriptionView()
            }
            .sheet(isPresented: $showProfile) {
                SocialProfileSheet(
                    myPosts: viewModel.posts.filter {
                        $0.handle == socialIdentity.handle(displayName: appState.displayName)
                    },
                    onImport: { imported in
                        viewModel.posts.insert(contentsOf: imported, at: 0)
                    }
                )
                .environmentObject(appState)
            }
            .sheet(isPresented: $showThemePicker) {
                SocialThemeSheet()
            }
            .sheet(isPresented: $viewModel.isComposerPresented) {
                composeSheet
                    .onChange(of: photoPickerItem) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                // Re-encode bounded JPEG so the feed stays light.
                                viewModel.composerImageData = image.jpegData(compressionQuality: 0.8)
                                MtrxHaptics.success()
                            }
                            photoPickerItem = nil
                        }
                    }
                    .onChange(of: videoPickerItem) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                viewModel.composerVideoFileName = SocialIdentity.saveMedia(data, fileExtension: "mov")
                                MtrxHaptics.success()
                            }
                            videoPickerItem = nil
                        }
                    }
            }
            .sheet(isPresented: $showProofPicker) {
                ProofPickerSheet { selection in
                    showProofPicker = false
                    showFeedback("Attached \(selection)")
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $commentingOnPost) { post in
                CommentComposerSheet(post: post)
                    .presentationDetents([.large])
            }
            .confirmationDialog(
                "Post options",
                isPresented: Binding(
                    get: { postActionTarget != nil },
                    set: { if !$0 { postActionTarget = nil } }
                ),
                titleVisibility: .hidden
            ) {
                Button("Report post", role: .destructive) {
                    showFeedback("Post reported")
                    postActionTarget = nil
                }
                Button("Hide from feed") {
                    showFeedback("Post hidden")
                    postActionTarget = nil
                }
                Button("Block user", role: .destructive) {
                    showFeedback("User blocked")
                    postActionTarget = nil
                }
                Button("Copy link") {
                    if let post = postActionTarget {
                        UIPasteboard.general.string = "https://openmatrix-ai.com/p/\(post.id)"
                    }
                    showFeedback("Link copied")
                    postActionTarget = nil
                }
                Button("Cancel", role: .cancel) {
                    postActionTarget = nil
                }
            }
        }
        .onAppear {
            withAnimation(Motion.springDefault.delay(0.1)) {
                appeared = true
            }
        }
    }

    private func showFeedback(_ message: String) {
        withAnimation(Motion.springDefault) {
            actionFeedback = message
        }
        MtrxHaptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Motion.springDefault) {
                actionFeedback = nil
            }
        }
    }

    // MARK: - Tab Selector

    /// Redesigned from scratch: a clean icon + label underline strip that
    /// reads as part of the header, not a row of chunky pills sitting on
    /// top of it. The active tab lights up with an animated accent
    /// underline; the rest stay quiet.
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.lg) {
                ForEach(SocialTab.allCases, id: \.self) { tab in
                    let isActive = viewModel.selectedTab == tab
                    Button {
                        withAnimation(Motion.springSnappy) { viewModel.selectedTab = tab }
                        MtrxHaptics.selection()
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(tab.rawValue)
                                    .font(.system(size: 14, weight: isActive ? .bold : .medium))
                            }
                            .foregroundStyle(isActive ? Color.labelPrimary : Color.labelTertiary)

                            // The animated underline rides under the active tab.
                            ZStack {
                                Capsule().fill(Color.clear).frame(height: 2.5)
                                if isActive {
                                    Capsule()
                                        .fill(theme.accent)
                                        .frame(height: 2.5)
                                        .matchedGeometryEffect(id: "socialTabUnderline", in: tabUnderlineNS)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.separatorStandard.opacity(0.4))
                .frame(height: 0.5)
        }
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
        case .groups:
            GroupsView()
        case .network:
            SocialGraphView()
        case .live:
            StreamingView()
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
                .background(theme.accent)
                .clipShape(Circle())
                .shadow(color: theme.accent.opacity(0.4), radius: 8, y: 4)
                .shadow(color: theme.accent.opacity(0.2), radius: 16, y: 8)
        }
        .padding(.trailing, Spacing.ml)
        .padding(.bottom, Spacing.lg)
        .mtrxScaleIn(isVisible: appeared, delay: 0.3)
    }

    // MARK: - Compose Sheet

    private var composeSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.composerText)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(Spacing.ms)
                        .background(Color.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                        .font(.mtrxBody)

                    if viewModel.composerText.isEmpty {
                        Text("What's happening?")
                            .font(.mtrxBody)
                            .foregroundStyle(Color.labelTertiary)
                            .padding(.top, Spacing.ms + 8)
                            .padding(.leading, Spacing.ms + 5)
                            .allowsHitTesting(false)
                    }
                }

                // Attachment previews
                if let imageData = viewModel.composerImageData, let image = UIImage(data: imageData) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                        Button {
                            viewModel.composerImageData = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .padding(6)
                    }
                }
                if viewModel.composerVideoFileName != nil {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "video.fill")
                            .foregroundStyle(Color.accentPrimary)
                        Text("Video attached")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelPrimary)
                        Spacer()
                        Button { viewModel.composerVideoFileName = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.labelTertiary)
                        }
                    }
                    .padding(Spacing.ms)
                    .background(Color.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }

                // Link field
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "link")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.labelTertiary)
                    TextField("Add a link (optional)", text: $viewModel.composerLink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.mtrxCaption1)
                }
                .padding(Spacing.ms)
                .background(Color.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                HStack(spacing: Spacing.sm) {
                    // Photo
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: 38, height: 38)
                            .background(Color.accentPrimary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    // Video
                    PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                        Image(systemName: "video")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: 38, height: 38)
                            .background(Color.accentPrimary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    // On-chain proof
                    Button {
                        viewModel.attachProof.toggle()
                        MtrxHaptics.impact(.light)
                    } label: {
                        Image(systemName: viewModel.attachProof ? "checkmark.seal.fill" : "checkmark.seal")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(viewModel.attachProof ? Color.statusSuccess : Color.accentPrimary)
                            .frame(width: 38, height: 38)
                            .background((viewModel.attachProof ? Color.statusSuccess : Color.accentPrimary).opacity(0.12))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("\(viewModel.composerText.count)/280")
                        .font(.mtrxCaption1)
                        .foregroundStyle(
                            viewModel.composerText.count > 280 ? Color.statusError : Color.labelTertiary
                        )
                }

                Spacer()
            }
            .padding(Spacing.contentPadding)
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.composerText = ""
                        viewModel.isComposerPresented = false
                    }
                    .foregroundStyle(Color.labelSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        viewModel.publishPost(displayName: appState.displayName)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                    .disabled(
                        (viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && viewModel.composerImageData == nil
                            && viewModel.composerVideoFileName == nil)
                            || viewModel.composerText.count > 280
                    )
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Feed Section

    private var feedSection: some View {
        VStack(spacing: 0) {
            // A colorful wash behind the stories + tabs that fades down
            // into the feed — the top of Social feels alive, the colors
            // dissolving as you move into the timeline.
            VStack(spacing: 0) {
                StoriesRail()
                filterChips
            }
            .background(
                LinearGradient(
                    colors: [
                        theme.accent.opacity(0.22),
                        Color.purple.opacity(0.12),
                        Color.pink.opacity(0.06),
                        .clear
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            )

            ScrollView {
                // Flat, edge-to-edge timeline rows with hairline
                // separators — the modern feed look.
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredPosts.enumerated()), id: \.element.id) { index, post in
                        PostCardView(
                            post: post,
                            onLike: { viewModel.toggleLike(postId: post.id) },
                            onRepost: { viewModel.toggleRepost(postId: post.id) },
                            onMenu: { postActionTarget = post },
                            onComment: { commentingOnPost = post }
                        )
                        .mtrxStaggeredAppearance(index: index, isVisible: appeared)
                        .onAppear {
                            if post.id == viewModel.filteredPosts.last?.id {
                                viewModel.loadMoreTimeline()
                            }
                        }

                        MtrxDivider()
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Filter Chips

    /// Timeline tabs — For You and Following, underline indicator.
    private var filterChips: some View {
        HStack(spacing: 0) {
            timelineTab("For You", filter: .all)
            timelineTab("Following", filter: .following)
        }
        .overlay(alignment: .bottom) {
            MtrxDivider()
        }
    }

    private func timelineTab(_ title: String, filter: FeedFilter) -> some View {
        Button {
            withAnimation(Motion.springSnappy) {
                viewModel.selectedFilter = filter
            }
            MtrxHaptics.selection()
        } label: {
            VStack(spacing: 11) {
                Text(title)
                    .font(.system(size: 15, weight: viewModel.selectedFilter == filter ? .bold : .semibold))
                    .foregroundStyle(viewModel.selectedFilter == filter ? Color.labelPrimary : Color.labelTertiary)

                ZStack {
                    Color.clear.frame(width: 58, height: 3)
                    if viewModel.selectedFilter == filter {
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: 58, height: 3)
                            .matchedGeometryEffect(id: "timelineUnderline", in: tabUnderlineNS)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    /// The full messaging experience — thread list, conversations you
    /// can open, and a working send box — not a static preview.
    private var messagingSection: some View {
        MessagingView()
    }
}

// MARK: - Post Card View

struct PostCardView: View {
    let post: SocialPostDisplay
    var onLike: () -> Void = {}
    var onRepost: () -> Void = {}
    var onMenu: () -> Void = {}
    var onComment: () -> Void = {}

    @State private var isExpanded = false
    @State private var bookmarked = false

    private let expandThreshold = 280

    /// Deterministic demo view count — stable per post, feels alive.
    private var viewCount: Int {
        post.likeCount * 83 + post.repostCount * 41 + post.commentCount * 17 + 412
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.ms) {
            MtrxAvatar(text: post.avatarInitials, color: post.avatarColor, size: 40)

            VStack(alignment: .leading, spacing: 7) {
                headerLine
                bodyText

                if post.imageData != nil || post.videoFileName != nil || post.linkURL != nil {
                    PostAttachmentView(
                        imageData: post.imageData,
                        videoFileName: post.videoFileName,
                        linkURL: post.linkURL
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 2)
                }

                if post.hasOnChainProof {
                    proofChip
                }
                if let tag = post.governanceTag {
                    governanceChip(tag)
                }
                if let origin = post.importedFrom {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Imported from \(origin)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.labelTertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.surfaceOverlay)
                    .clipShape(Capsule())
                }

                actionRow
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.ms)
        .contentShape(Rectangle())
    }

    // MARK: Header line — name · handle · time, menu at right

    private var headerLine: some View {
        HStack(spacing: 4) {
            Text(post.displayName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)

            if post.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentPrimary)
            }

            Text(post.handle)
                .font(.system(size: 14))
                .foregroundStyle(Color.labelTertiary)
                .lineLimit(1)

            Text("· \(relativeTimestamp(post.timestamp))")
                .font(.system(size: 14))
                .foregroundStyle(Color.labelTertiary)
                .layoutPriority(1)

            Spacer(minLength: 4)

            Button {
                onMenu()
                MtrxHaptics.impact(.light)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.labelTertiary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Body text

    @ViewBuilder
    private var bodyText: some View {
        let shouldTruncate = post.body.count > expandThreshold && !isExpanded

        if !post.body.isEmpty {
            Text(shouldTruncate ? String(post.body.prefix(expandThreshold)) + "…" : post.body)
                .font(.system(size: 15))
                .foregroundStyle(Color.labelPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if post.body.count > expandThreshold {
                Button {
                    withAnimation(Motion.springDefault) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Show less" : "Show more")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: On-chain proof / governance chips

    private var proofChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("On-chain proof")
                .font(.system(size: 12, weight: .semibold))
            if let hash = post.proofHash {
                Text(hash)
                    .font(.mtrxMonoSmall)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.statusSuccess)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.statusSuccess.opacity(0.10))
        .clipShape(Capsule())
    }

    private func governanceChip(_ tag: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(tag)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.statusInfo)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.statusInfo.opacity(0.10))
        .clipShape(Capsule())
    }

    // MARK: Action row — reply · repost · like · views · bookmark/share

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionButton(
                icon: "bubble.left",
                count: post.commentCount,
                tint: Color.labelTertiary
            ) { onComment() }

            Spacer()

            actionButton(
                icon: "arrow.2.squarepath",
                count: post.repostCount,
                tint: post.isReposted ? Color.statusSuccess : Color.labelTertiary
            ) { onRepost() }

            Spacer()

            actionButton(
                icon: post.isLiked ? "heart.fill" : "heart",
                count: post.likeCount,
                tint: post.isLiked ? Color(red: 0.97, green: 0.26, blue: 0.45) : Color.labelTertiary
            ) { onLike() }

            Spacer()

            actionButton(
                icon: "chart.bar.xaxis",
                count: viewCount,
                tint: Color.labelTertiary
            ) {}

            Spacer()

            HStack(spacing: Spacing.ms) {
                Button {
                    bookmarked.toggle()
                    MtrxHaptics.impact(.light)
                } label: {
                    Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15))
                        .foregroundStyle(bookmarked ? Color.accentPrimary : Color.labelTertiary)
                }
                .buttonStyle(.plain)

                ShareLink(item: post.body.isEmpty ? "Shared from MTRX" : post.body) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.labelTertiary)
                }
            }
        }
        .padding(.trailing, 2)
    }

    private func actionButton(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            MtrxHaptics.impact(.light)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                if count > 0 {
                    Text(Self.compact(count))
                        .font(.system(size: 13))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    /// 1.2K-style compact counts.
    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
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

// MARK: - Proof Picker Sheet

struct ProofPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (String) -> Void

    private let options: [(label: String, icon: String, kind: String)] = [
        ("Attach transaction hash", Symbols.transaction, "transaction"),
        ("Attach contract address", Symbols.contract, "contract"),
        ("Attach NFT", Symbols.nft, "NFT")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                MtrxCard(style: .standard) {
                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            Button {
                                onSelect(option.kind)
                                MtrxHaptics.selection()
                            } label: {
                                HStack(spacing: Spacing.ms) {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(Color.accentPrimary)
                                        .frame(width: 28, height: 28)
                                    Text(option.label)
                                        .font(.mtrxBody)
                                        .foregroundStyle(Color.labelPrimary)
                                    Spacer()
                                    Image(systemName: Symbols.forward)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.labelTertiary)
                                }
                                .padding(.vertical, Spacing.sm)
                            }
                            .buttonStyle(.plain)

                            if index < options.count - 1 {
                                MtrxDivider()
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(Spacing.contentPadding)
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Attach Proof")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        }
    }
}

// MARK: - Comment Composer Sheet

struct CommentComposerSheet: View {
    let post: SocialPostDisplay
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Original post snippet
                        MtrxCard(style: .glass) {
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                MtrxAvatar(
                                    text: post.avatarInitials,
                                    color: post.avatarColor,
                                    size: Spacing.Size.avatarSmall
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: Spacing.xs) {
                                        Text(post.displayName)
                                            .font(.mtrxCalloutBold)
                                            .foregroundStyle(Color.labelPrimary)
                                        Text(post.handle)
                                            .font(.mtrxCaption1)
                                            .foregroundStyle(Color.labelSecondary)
                                    }
                                    Text(post.body)
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                        .lineLimit(3)
                                }
                            }
                        }

                        Text("\(post.commentCount) comments")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                            .padding(.top, Spacing.sm)

                        // Placeholder comments
                        ForEach(placeholderComments(for: post), id: \.id) { comment in
                            CommentRow(comment: comment)
                        }
                    }
                    .padding(Spacing.contentPadding)
                }
                .background(MtrxGradientBackground(style: .primary))

                MtrxDivider()

                // Composer
                HStack(spacing: Spacing.sm) {
                    MtrxTextField(
                        placeholder: "Add a comment…",
                        text: $draft,
                        icon: "bubble.left"
                    )

                    Button {
                        MtrxHaptics.success()
                        draft = ""
                        dismiss()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(Spacing.contentPadding)
                .background(Color.backgroundPrimary)
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        }
    }

    private func placeholderComments(for post: SocialPostDisplay) -> [PlaceholderComment] {
        let templates: [(String, String, String, Color)] = [
            ("Maya Reyes", "@maya.eth", "MR", .accentPrimary),
            ("Theo Lin", "@theo_dev", "TL", .statusInfo),
            ("Aisha Khan", "@aisha.base", "AK", .accentTertiary),
            ("DeFi Daily", "@defidaily", "DD", .statusSuccess),
            ("Crypto Curious", "@curious42", "CC", .labelTertiary)
        ]
        let bodies = [
            "This is huge for the ecosystem.",
            "Have you seen the gas costs lately though?",
            "Following — interested to see how this plays out.",
            "Big if true. Source on the audit?",
            "Reposting to my thread."
        ]
        let count = max(1, min(post.commentCount, 5))
        return (0..<count).map { i in
            let t = templates[i % templates.count]
            return PlaceholderComment(
                id: "\(post.id)-c\(i)",
                displayName: t.0,
                handle: t.1,
                avatarInitials: t.2,
                avatarColor: t.3,
                body: bodies[i % bodies.count]
            )
        }
    }
}

struct PlaceholderComment: Identifiable {
    let id: String
    let displayName: String
    let handle: String
    let avatarInitials: String
    let avatarColor: Color
    let body: String
}

struct CommentRow: View {
    let comment: PlaceholderComment

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            MtrxAvatar(
                text: comment.avatarInitials,
                color: comment.avatarColor,
                size: Spacing.Size.avatarSmall
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.xs) {
                    Text(comment.displayName)
                        .font(.mtrxCalloutBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text(comment.handle)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                }
                Text(comment.body)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Preview

#Preview("Social") {
    SocialView()
        .preferredColorScheme(.dark)
        .environmentObject(AppState())
        .environmentObject(WalletManager())
}
