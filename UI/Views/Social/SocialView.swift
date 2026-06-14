// SocialView.swift
// MTRX - On-chain social feed with governance, messaging, and proof sharing
// Copyright 2026 OPN MATRX. All rights reserved.

import PhotosUI
import SwiftUI

// MARK: - Social Tab Sections

extension View {
    /// Reports a vertical scroll offset on iOS 18+, and no-ops gracefully
    /// below it.
    @ViewBuilder
    func mtrxTrackScrollY(_ action: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                action(y)
            }
        } else {
            self
        }
    }
}

enum SocialTab: String, CaseIterable {
    case feed = "Feed"
    case governance = "Governance"
    case search = "Search"
    case notifications = "Notifications"
    case messaging = "Messaging"
    // Groups now lives inside Messaging; Network/Live remain for deep links.
    case groups = "Groups"
    case network = "Network"
    case live = "Live"

    var icon: String {
        switch self {
        case .feed: return "house"
        case .governance: return "building.columns"
        case .search: return "magnifyingglass"
        case .notifications: return "bell"
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

// MARK: - Bookmark Store

/// Persists the IDs of posts the user has bookmarked, so they survive
/// relaunches and surface in the side-menu History.
final class SocialBookmarkStore: ObservableObject {
    static let shared = SocialBookmarkStore()
    private let key = "com.mtrx.social.bookmarks"
    @Published private(set) var ids: Set<String>

    private init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func isBookmarked(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}

// MARK: - Side Drawer Controller

/// Shared so the app-wide swipe gesture (in MainTabView) can open the
/// Social drawer with the same animation as tapping the avatar.
final class SocialDrawerController: ObservableObject {
    static let shared = SocialDrawerController()
    @Published var isOpen = false
    private init() {}
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

    // AI features (Social) — each genuinely shapes the feed.
    @Published var aiSmartSort = UserDefaults.standard.bool(forKey: "com.mtrx.social.ai.smartSort") {
        didSet { UserDefaults.standard.set(aiSmartSort, forKey: "com.mtrx.social.ai.smartSort") }
    }
    @Published var aiHideLowSignal = UserDefaults.standard.bool(forKey: "com.mtrx.social.ai.hideLow") {
        didSet { UserDefaults.standard.set(aiHideLowSignal, forKey: "com.mtrx.social.ai.hideLow") }
    }
    @Published var aiVerifiedFirst = UserDefaults.standard.bool(forKey: "com.mtrx.social.ai.verifiedFirst") {
        didSet { UserDefaults.standard.set(aiVerifiedFirst, forKey: "com.mtrx.social.ai.verifiedFirst") }
    }
    @Published var aiHideReposts = UserDefaults.standard.bool(forKey: "com.mtrx.social.ai.hideReposts") {
        didSet { UserDefaults.standard.set(aiHideReposts, forKey: "com.mtrx.social.ai.hideReposts") }
    }

    // MARK: Init

    init() {
        loadSampleData()
    }

    // MARK: Filtered Posts

    var filteredPosts: [SocialPostDisplay] {
        var result: [SocialPostDisplay]
        switch selectedFilter {
        case .all:
            result = posts
        case .verified:
            result = posts.filter { $0.isVerified }
        case .following:
            result = posts.filter { ["@elena.eth", "@ravi_dao", "@sofia.base"].contains($0.handle) }
        case .trending:
            result = posts.sorted { ($0.likeCount + $0.repostCount) > ($1.likeCount + $1.repostCount) }
        }

        // AI features layer on top, in order.
        if aiHideReposts { result = result.filter { !$0.isReposted } }
        if aiHideLowSignal { result = result.filter { ($0.likeCount + $0.repostCount) >= 50 } }
        if aiSmartSort {
            result = result.sorted { (engagement($0)) > (engagement($1)) }
        }
        if aiVerifiedFirst {
            result = result.sorted { $0.isVerified && !$1.isVerified }
        }
        return result
    }

    private func engagement(_ p: SocialPostDisplay) -> Int {
        p.likeCount * 3 + p.repostCount * 4 + p.commentCount * 2
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

    /// Share something built in the Build tab to the social feed so others
    /// can discover it.
    func postBuild(title: String, kind: String, address: String?, displayName rawName: String) {
        let displayName = rawName.isEmpty ? "You" : rawName
        let initials = displayName
            .split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined().uppercased()
        let handle = SocialIdentity.shared.handle(displayName: rawName)
        posts.insert(SocialPostDisplay(
            id: UUID().uuidString,
            displayName: displayName,
            handle: handle,
            avatarInitials: initials.isEmpty ? "ME" : initials,
            avatarColor: .trinityPrimary,
            timestamp: Date(),
            body: "Just shipped \(title) — a \(kind) built and deployed on MTRX. 🛠️ On-chain and ready.",
            isVerified: true,
            hasOnChainProof: address != nil,
            proofHash: address,
            governanceTag: nil,
            likeCount: 0,
            repostCount: 0,
            commentCount: 0,
            isLiked: false,
            isReposted: false,
            imageData: nil,
            videoFileName: nil,
            linkURL: nil
        ), at: 0)
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
    @EnvironmentObject private var walletManager: WalletManager
    @ObservedObject private var socialIdentity = SocialIdentity.shared
    @ObservedObject private var theme = SocialTheme.shared
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var showProfile = false
    @State private var showThemePicker = false
    @State private var showNotifications = false
    @State private var showSocialSettings = false
    @State private var showUpsell = false
    @State private var showAIFeatures = false
    // Twitter-style side drawer opened from the avatar.
    @ObservedObject private var drawer = SocialDrawerController.shared
    @State private var showTrinityChat = false
    @State private var showHistory = false
    @State private var showHelp = false
    /// A post the Home carousel asked us to scroll to.
    @State private var pendingOpenPostID: String?
    @AppStorage("com.mtrx.subscriptionTier") private var tierRaw: String = SubscriptionTier.free.rawValue
    private var currentTier: SubscriptionTier { SubscriptionTier(rawValue: tierRaw) ?? .free }
    @Namespace private var tabUnderlineNS
    @State private var appeared = false
    /// Immersive scroll: the header + tabs fade out smoothly as you move
    /// into the feed (continuous opacity tied directly to the scroll offset —
    /// no animations, timers, or layout changes, so it's buttery at any
    /// scroll speed). The dock always stays.
    @State private var feedScrollY: CGFloat = 0
    private let tabStripHeight: CGFloat = 58
    private var chromeOpacity: Double {
        // Fades quickly so the header/tabs are gone within a short scroll.
        Double(max(0, min(1, 1 - feedScrollY / 55)))
    }
    @State private var showProofPicker = false
    @State private var commentingOnPost: SocialPostDisplay? = nil
    @State private var postActionTarget: SocialPostDisplay? = nil
    @State private var actionFeedback: String? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if viewModel.selectedTab == .feed {
                        // Immersive feed: the header, tabs, and stories all
                        // live inside the scroll, so they simply scroll away
                        // as you move down — no overlay, no fade artifacts, no
                        // break. Just a normal, perfectly smooth scroll.
                        feedSection
                    } else {
                        VStack(spacing: 0) {
                            socialHeader
                            tabSelector
                            tabContent
                        }
                    }
                }
                .background(alignment: .top) {
                    // A smooth, natural themed wash that fades down into the
                    // black field — and fades out interactively as you scroll
                    // into the feed (only on the feed tab).
                    LinearGradient(
                        stops: [
                            .init(color: theme.accent.opacity(0.34), location: 0.0),
                            .init(color: theme.accent.opacity(0.20), location: 0.22),
                            .init(color: theme.accent.opacity(0.08), location: 0.5),
                            .init(color: theme.accent.opacity(0.02), location: 0.78),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 340)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .opacity(viewModel.selectedTab == .feed ? chromeOpacity : 1)
                    .allowsHitTesting(false)
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
            // Twitter-style side drawer: when open, the whole feed slides to
            // the right (leaving a sliver) and a dim scrim closes it on tap.
            // No scale — the sliver fills full-height so there's no black gap
            // in the top corner.
            .offset(x: drawer.isOpen ? sideMenuWidth : 0)
            .overlay {
                if drawer.isOpen {
                    Color.black.opacity(0.34)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeSideMenu() }
                        .transition(.opacity)
                }
            }
            .onAppear {
                DailyFlow.shared.mark(.social)
                socialIdentity.currentDisplayName = appState.displayName
            }
            .onChange(of: appState.displayName) { _, name in
                socialIdentity.currentDisplayName = name
            }
            .onReceive(NotificationCenter.default.publisher(for: .mtrxPopToRoot)) { note in
                // Re-tapping the Social dock tab returns to the Feed.
                if note.userInfo?["index"] as? Int == 3 {
                    withAnimation(Motion.springSnappy) { viewModel.selectedTab = .feed }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mtrxOpenPost)) { note in
                // Tapping a Home carousel card lands on that post in the feed.
                guard let id = note.userInfo?["id"] as? String else { return }
                viewModel.selectedTab = .feed
                viewModel.selectedFilter = .all
                pendingOpenPostID = id
            }
            .navigationBarTitleDisplayMode(.inline)
            // The header is a custom view now (no system toolbar) so there's
            // no iOS glass capsule around the avatar — just the photo.
            .toolbar(.hidden, for: .navigationBar)
            // Reset the immersive fade whenever the sub-tab changes.
            .onChange(of: viewModel.selectedTab) { _, _ in feedScrollY = 0 }
            .sheet(isPresented: $showNotifications) {
                NotificationCenterView()
            }
            .sheet(isPresented: $showSocialSettings) {
                SocialSettingsView()
            }
            .sheet(isPresented: $showUpsell) {
                SubscriptionView()
            }
            .sheet(isPresented: $showAIFeatures) {
                AIFeaturesSheet(currentTier: currentTier, viewModel: viewModel)
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
                // Only your own posts can be deleted from the feed.
                if let target = postActionTarget,
                   target.handle == socialIdentity.handle(displayName: appState.displayName) {
                    Button("Delete post", role: .destructive) {
                        viewModel.posts.removeAll { $0.id == target.id }
                        showFeedback("Post deleted")
                        postActionTarget = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    postActionTarget = nil
                }
            }

            if drawer.isOpen {
                sideMenu
                    .frame(width: sideMenuWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .leading))
                    .zIndex(5)
            }
            }
        }
        .onAppear {
            withAnimation(Motion.springDefault.delay(0.1)) {
                appeared = true
            }
        }
        .fullScreenCover(isPresented: $showTrinityChat) {
            AgentConversationView(
                userID: appState.currentUserID,
                initialAgent: .trinity,
                isModal: true
            )
            .environmentObject(appState)
            .environmentObject(walletManager)
        }
        .sheet(isPresented: $showHistory) {
            SocialHistorySheet()
        }
        .sheet(isPresented: $showHelp) {
            HelpSupportSheet()
        }
    }

    private var sideMenuWidth: CGFloat {
        UIScreen.main.bounds.width * 0.85
    }

    /// Soft rounded surface behind a menu group, so the rows read as a
    /// cohesive card instead of bare lines.
    private var sideMenuGroupBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }

    private func closeSideMenu() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            drawer.isOpen = false
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
    // MARK: - Side Menu (Twitter-style left drawer)

    private var sideMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile header
            VStack(alignment: .leading, spacing: 11) {
                Group {
                    if let avatar = socialIdentity.avatarImage {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [.trinityPrimary, .trinitySecondary],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                            )
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))

                HStack(spacing: 5) {
                    Text(appState.displayName.isEmpty ? "You" : appState.displayName)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(Color.labelPrimary)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.accent)
                }

                Text(socialIdentity.handle(displayName: appState.displayName))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.labelTertiary)

                HStack(spacing: Spacing.md) {
                    HStack(spacing: 4) {
                        Text("348").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.labelPrimary)
                        Text("Following").font(.system(size: 14)).foregroundStyle(Color.labelTertiary)
                    }
                    HStack(spacing: 4) {
                        Text("1,284").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.labelPrimary)
                        Text("Followers").font(.system(size: 14)).foregroundStyle(Color.labelTertiary)
                    }
                }
                .padding(.top, 3)
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.bottom, Spacing.lg)

            // Options grouped into two soft cards — so the menu reads as
            // tidy sections, not a loose stack of lines.
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(spacing: 0) {
                    sideMenuRow(icon: "person", title: "Profile") {
                        closeSideMenu(); showProfile = true
                    }
                    sideMenuRow(icon: "sparkles", title: "Trinity", orb: true) {
                        closeSideMenu(); showTrinityChat = true
                    }
                    sideMenuRow(icon: "clock.arrow.circlepath", title: "History") {
                        closeSideMenu(); showHistory = true
                    }
                }
                .background(sideMenuGroupBackground)

                VStack(spacing: 0) {
                    sideMenuRow(icon: "gearshape", title: "Settings and privacy") {
                        closeSideMenu(); showSocialSettings = true
                    }
                    sideMenuRow(icon: "questionmark.circle", title: "Help Center") {
                        closeSideMenu(); showHelp = true
                    }
                }
                .background(sideMenuGroupBackground)
            }
            .padding(.horizontal, Spacing.contentPadding)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 6)
        .background {
            ZStack(alignment: .top) {
                MtrxGradientBackground(style: .primary)
                LinearGradient(
                    stops: [
                        .init(color: theme.accent.opacity(0.30), location: 0.0),
                        .init(color: theme.accent.opacity(0.08), location: 0.4),
                        .init(color: .clear, location: 0.75),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 360)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .ignoresSafeArea()
        }
    }

    private func sideMenuRow(icon: String, title: String, orb: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            action()
        } label: {
            HStack(spacing: Spacing.md) {
                // Each row gets a soft glass chip behind its glyph, so the
                // list reads as a set of tactile items — not a stack of bare
                // lines. Trinity wears her living orb instead of a glyph.
                ZStack {
                    if orb {
                        GlassOrb(size: 34)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.05))
                            .overlay(Circle().stroke(Color.white.opacity(0.09), lineWidth: 1))
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
                .frame(width: 38, height: 38)

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.labelPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom Header (no system toolbar → no glass capsule)

    private var socialHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            // Avatar — opens the side menu, Twitter-style.
            Button {
                MtrxHaptics.impact(.light)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { drawer.isOpen = true }
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
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("M")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [theme.accent, theme.accent.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .mtrxGlow(color: theme.accent, radius: 4)
                // Keep the wordmark from inflating the row so the avatar and
                // gear stay centered on the same line.
                .frame(height: 36)

            Spacer()

            Menu {
                Button {
                    MtrxHaptics.impact(.light)
                    showNotifications = true
                } label: { Label("Notifications", systemImage: "bell") }

                Button {
                    MtrxHaptics.impact(.light)
                    if currentTier >= .pro { showThemePicker = true } else { showUpsell = true }
                } label: {
                    Label(currentTier >= .pro ? "Theme color" : "Theme color (Pro)",
                          systemImage: currentTier >= .pro ? "paintpalette" : "lock.fill")
                }

                Button {
                    MtrxHaptics.impact(.light)
                    showAIFeatures = true
                } label: { Label("AI features", systemImage: "sparkles") }

                Divider()

                Button {
                    MtrxHaptics.impact(.light)
                    showSocialSettings = true
                } label: { Label("Settings", systemImage: "gearshape") }
            } label: {
                // Same 36×36 footprint as the avatar so it mirrors it exactly
                // across the wordmark.
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .frame(height: 56)
    }

    /// Five top sections — Feed, Governance, Search, Alerts, Messages. Groups
    /// live inside Messages; Network/Live surface elsewhere.
    private var topTabs: [SocialTab] { [.feed, .governance, .search, .notifications, .messaging] }

    private var tabSelector: some View {
        // Five equal-width tabs so they always fit on one line and read as
        // evenly spaced. Each shows its icon over a compact label.
        HStack(spacing: 0) {
            ForEach(topTabs, id: \.self) { tab in
                let isActive = viewModel.selectedTab == tab
                Button {
                    withAnimation(Motion.springSnappy) { viewModel.selectedTab = tab }
                    MtrxHaptics.selection()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 10.5, weight: isActive ? .bold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.55)
                            .foregroundStyle(isActive ? Color.labelPrimary : Color.labelTertiary)

                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 2.5)
                            if isActive {
                                Capsule()
                                    .fill(theme.accent)
                                    .frame(height: 2.5)
                                    .matchedGeometryEffect(id: "socialTabUnderline", in: tabUnderlineNS)
                            }
                        }
                        .frame(width: 26)
                    }
                    .foregroundStyle(isActive ? Color.labelPrimary : Color.labelTertiary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .feed:
            feedSection
        case .governance:
            governanceSection
        case .search:
            SocialSearchView(viewModel: viewModel)
        case .notifications:
            SocialNotificationsView()
        case .messaging:
            messagesHub
        case .groups:
            GroupsView()
        case .network:
            SocialGraphView()
        case .live:
            StreamingView()
        }
    }

    // MARK: - Messages Hub (Messages + Groups merged)

    @State private var messagesSubTab: MessagesSubTab = .direct

    enum MessagesSubTab: String, CaseIterable { case direct = "Messages", groups = "Groups" }

    private var messagesHub: some View {
        VStack(spacing: 0) {
            // Switch between direct messages and groups without leaving the tab.
            Picker("", selection: $messagesSubTab) {
                ForEach(MessagesSubTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)

            switch messagesSubTab {
            case .direct: messagingSection
            case .groups: GroupsView()
            }
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

    /// Whether the post is ready to publish.
    private var composerCanPost: Bool {
        !(viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && viewModel.composerImageData == nil
          && viewModel.composerVideoFileName == nil)
        && viewModel.composerText.count <= 280
    }

    private var composeSheet: some View {
        VStack(spacing: 0) {
            // A clean custom header: balanced Cancel / title / Post, well
            // clear of the Dynamic Island, with a proper gradient Post pill.
            HStack {
                Button {
                    viewModel.composerText = ""
                    viewModel.isComposerPresented = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                Text("New post")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.labelPrimary)

                Spacer()

                Button {
                    viewModel.publishPost(displayName: appState.displayName)
                } label: {
                    Text("Post")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(composerCanPost ? .white : Color.labelTertiary)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(
                            Group {
                                if composerCanPost {
                                    LinearGradient(colors: [theme.accent, theme.accent.opacity(0.78)],
                                                   startPoint: .top, endPoint: .bottom)
                                } else {
                                    Color.surfaceCard
                                }
                            }
                        )
                        .clipShape(Capsule())
                        .shadow(color: composerCanPost ? theme.accent.opacity(0.35) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(!composerCanPost)
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.sm)

            MtrxDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Avatar beside the editor — reads as you, writing.
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        composerAvatar
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $viewModel.composerText)
                                .frame(minHeight: 130)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.labelPrimary)

                            if viewModel.composerText.isEmpty {
                                Text("What's happening?")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.labelTertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    // Attachment previews
                    if let imageData = viewModel.composerImageData, let image = UIImage(data: imageData) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
                            Button {
                                viewModel.composerImageData = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .padding(8)
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
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
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
                    .background(Color.surfaceCard.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
                .padding(Spacing.contentPadding)
            }

            // A grounded bottom bar — the writing tools + character counter.
            HStack(spacing: Spacing.md) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    composerToolIcon("photo", tint: Color.accentPrimary)
                }
                PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                    composerToolIcon("video", tint: Color.accentPrimary)
                }
                Button {
                    viewModel.attachProof.toggle()
                    MtrxHaptics.impact(.light)
                } label: {
                    composerToolIcon(viewModel.attachProof ? "checkmark.seal.fill" : "checkmark.seal",
                                     tint: viewModel.attachProof ? Color.statusSuccess : Color.accentPrimary)
                }

                Spacer()

                Text("\(viewModel.composerText.count)/280")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(viewModel.composerText.count > 280 ? Color.statusError : Color.labelTertiary)
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { MtrxDivider() }
        }
        .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
        .presentationDetents([.large])
    }

    private var composerAvatar: some View {
        Group {
            if let photo = socialIdentity.avatarImage {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.trinityPrimary, .trinitySecondary],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        Text(String((appState.displayName.isEmpty ? "Y" : appState.displayName).prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private func composerToolIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.12))
            .clipShape(Circle())
    }

    // MARK: - Feed Section

    private var feedSection: some View {
        // The whole top — header, tabs, stories, filter chips — is the first
        // run of the scroll, so it scrolls away cleanly and the feed engulfs
        // the screen. Only the dock stays.
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    socialHeader
                    tabSelector
                    StoriesRail()
                    filterChips

                    ForEach(Array(viewModel.filteredPosts.enumerated()), id: \.element.id) { index, post in
                        PostCardView(
                            post: post,
                            onLike: { viewModel.toggleLike(postId: post.id) },
                            onRepost: { viewModel.toggleRepost(postId: post.id) },
                            onMenu: { postActionTarget = post },
                            onComment: { commentingOnPost = post }
                        )
                        .id(post.id)
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
            .mtrxTrackScrollY { feedScrollY = $0 }
            .refreshable {
                await viewModel.refresh()
            }
            // Jump to a post requested from the Home feed carousel.
            .onChange(of: pendingOpenPostID) { _, id in
                guard let id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                    pendingOpenPostID = nil
                }
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
                // A warm, social framing — governance as a community you're
                // part of, not a spreadsheet.
                MtrxCard(style: .glass) {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            Circle().fill(theme.accent.opacity(0.16)).frame(width: 46, height: 46)
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(theme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You're shaping MTRX")
                                .font(.mtrxBodyBold)
                                .foregroundStyle(Color.labelPrimary)
                            Text("12,840 members are deciding what comes next — your voice counts here.")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }

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

                // Past proposals — a clear, full-width tappable card so the
                // whole row toggles (the chevron used to hide under the FAB).
                Button {
                    withAnimation(Motion.springDefault) {
                        viewModel.showPastProposals.toggle()
                    }
                    MtrxHaptics.selection()
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentPrimary)
                        Text("Past Proposals")
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Spacer()
                        Image(systemName: viewModel.showPastProposals ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.accentPrimary)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity)
                    .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.sm)

                if viewModel.showPastProposals {
                    ForEach(viewModel.pastProposals) { proposal in
                        SocialProposalCardView(proposal: proposal, onVote: {})
                            .opacity(0.7)
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
            // Extra room so the compose FAB never overlaps the last row.
            .padding(.bottom, 120)
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
    @ObservedObject private var bookmarks = SocialBookmarkStore.shared
    @ObservedObject private var identity = SocialIdentity.shared

    private let expandThreshold = 280

    /// Deterministic demo view count — stable per post, feels alive.
    private var viewCount: Int {
        post.likeCount * 83 + post.repostCount * 41 + post.commentCount * 17 + 412
    }

    /// This is the signed-in user's own post → show their real photo.
    private var isOwnPost: Bool { post.handle == identity.myHandle }

    /// A YouTube link sitting in the post text — pulled out so it plays
    /// inline instead of showing as a bare URL.
    private var bodyYouTubeID: String? {
        guard post.imageData == nil, post.videoFileName == nil, post.linkURL == nil else { return nil }
        for token in post.body.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let s = String(token)
            if s.contains("youtu"), let id = PostAttachmentView.youTubeID(from: s) { return id }
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.ms) {
            if isOwnPost, let photo = identity.avatarImage {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                MtrxAvatar(text: post.avatarInitials, color: post.avatarColor, size: 40)
            }

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

                // A YouTube link pasted into the post plays right here.
                if let ytID = bodyYouTubeID {
                    YouTubePlayerView(videoID: ytID)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
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
        // When a YouTube link plays inline, drop the bare URL from the text.
        let cleaned: String = {
            guard bodyYouTubeID != nil else { return post.body }
            return post.body
                .split(whereSeparator: { $0 == " " || $0 == "\n" })
                .filter { !$0.contains("youtu") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        let shouldTruncate = cleaned.count > expandThreshold && !isExpanded

        if !cleaned.isEmpty {
            Text(shouldTruncate ? String(cleaned.prefix(expandThreshold)) + "…" : cleaned)
                .font(.system(size: 15))
                .foregroundStyle(Color.labelPrimary)
                .lineSpacing(3)
                .textSelection(.enabled)
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
                    bookmarks.toggle(post.id)
                    MtrxHaptics.impact(.light)
                } label: {
                    Image(systemName: bookmarks.isBookmarked(post.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15))
                        .foregroundStyle(bookmarks.isBookmarked(post.id) ? Color.accentPrimary : Color.labelTertiary)
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

// MARK: - AI Features Sheet

/// Four meaningful AI features for the social feed — two unlock on Pro,
/// two more on Enterprise. Each genuinely reshapes the feed so they can
/// be toggled and tested live.
struct AIFeaturesSheet: View {
    let currentTier: SubscriptionTier
    @ObservedObject var viewModel: SocialViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showUpsell = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    tierGroup(
                        "Pro",
                        unlocked: currentTier >= .pro,
                        rows: [
                            ("Smart sort", "Reorders your feed by what's actually getting traction.", "wand.and.stars",
                             Binding(get: { viewModel.aiSmartSort }, set: { viewModel.aiSmartSort = $0 })),
                            ("Hide low-signal", "Filters out posts with little engagement.", "line.3.horizontal.decrease.circle",
                             Binding(get: { viewModel.aiHideLowSignal }, set: { viewModel.aiHideLowSignal = $0 })),
                        ]
                    )

                    tierGroup(
                        "Enterprise",
                        unlocked: currentTier >= .enterprise,
                        rows: [
                            ("Verified first", "Floats verified accounts to the top of your feed.", "checkmark.seal.fill",
                             Binding(get: { viewModel.aiVerifiedFirst }, set: { viewModel.aiVerifiedFirst = $0 })),
                            ("Hide reposts", "Shows only original posts — no reposts in the feed.", "arrow.2.squarepath",
                             Binding(get: { viewModel.aiHideReposts }, set: { viewModel.aiHideReposts = $0 })),
                        ]
                    )
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("AI features")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showUpsell) { SubscriptionView() }
        }
    }

    private func tierGroup(_ title: String, unlocked: Bool, rows: [(String, String, String, Binding<Bool>)]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                MtrxSectionHeader(title: title)
                Spacer()
                if !unlocked {
                    Button {
                        MtrxHaptics.impact(.light)
                        showUpsell = true
                    } label: {
                        Text("Unlock")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.accentSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(rows, id: \.0) { row in
                HStack(spacing: Spacing.md) {
                    Image(systemName: unlocked ? row.2 : "lock.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(unlocked ? Color.trinityPrimary : Color.labelTertiary)
                        .frame(width: 38, height: 38)
                        .background((unlocked ? Color.trinityPrimary : Color.labelTertiary).opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0).font(.mtrxCalloutBold).foregroundStyle(Color.labelPrimary)
                        Text(row.1).font(.mtrxCaption2).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    if unlocked {
                        Toggle("", isOn: row.3).labelsHidden().tint(Color.accentPrimary)
                    }
                }
                .padding(Spacing.ms)
                .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
                .opacity(unlocked ? 1 : 0.6)
            }
        }
    }
}

// MARK: - Social Settings (social-only)

/// Settings that belong to the Social experience only — never the whole
/// app. App-wide settings live in Account ▸ Settings.
struct SocialSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("com.mtrx.social.privateAccount") private var privateAccount = false
    @AppStorage("com.mtrx.social.autoplay") private var autoplayVideos = true
    @AppStorage("com.mtrx.social.sensitive") private var showSensitive = false
    @AppStorage("com.mtrx.social.readReceipts") private var readReceipts = true
    @AppStorage("com.mtrx.social.whoCanMessage") private var whoCanMessage = "Everyone"
    @AppStorage("com.mtrx.social.whoCanReply") private var whoCanReply = "Everyone"

    private let audiences = ["Everyone", "People you follow", "No one"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $privateAccount) {
                        socialLabel("Private account", "lock.fill", .statusWarning)
                    }.tint(Color.accentPrimary)
                    Picker(selection: $whoCanMessage) {
                        ForEach(audiences, id: \.self) { Text($0).tag($0) }
                    } label: { socialLabel("Who can message you", "envelope.fill", .statusInfo) }
                    Picker(selection: $whoCanReply) {
                        ForEach(audiences, id: \.self) { Text($0).tag($0) }
                    } label: { socialLabel("Who can reply", "arrowshape.turn.up.left.fill", .accentTertiary) }
                } header: { Text("Privacy") }

                Section {
                    Toggle(isOn: $autoplayVideos) {
                        socialLabel("Autoplay videos", "play.rectangle.fill", .accentPrimary)
                    }.tint(Color.accentPrimary)
                    Toggle(isOn: $showSensitive) {
                        socialLabel("Show sensitive content", "eye.fill", .statusError)
                    }.tint(Color.accentPrimary)
                } header: { Text("Content") }

                Section {
                    Toggle(isOn: $readReceipts) {
                        socialLabel("Read receipts", "checkmark.message.fill", .statusSuccess)
                    }.tint(Color.accentPrimary)
                } header: { Text("Messaging") } footer: {
                    Text("These settings only affect your Social experience. App-wide settings live in Account ▸ Settings.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Social Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func socialLabel(_ title: String, _ icon: String, _ color: Color) -> some View {
        Label {
            Text(title).font(.mtrxBody).foregroundStyle(Color.labelPrimary)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

// MARK: - Social Search (social-only)

/// Searches across the social feed (including posts imported from other
/// platforms). This is scoped to Social, not a system-wide search.
struct SocialSearchView: View {
    @ObservedObject var viewModel: SocialViewModel
    @State private var query = ""

    private let trending = ["#MTRX", "#DeFi", "#Governance", "#Base", "#Staking", "#RWA"]

    private var results: [SocialPostDisplay] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let needle = q.hasPrefix("#") ? String(q.dropFirst()) : q
        return viewModel.posts.filter {
            $0.body.localizedCaseInsensitiveContains(needle) ||
            $0.displayName.localizedCaseInsensitiveContains(needle) ||
            $0.handle.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MtrxSearchBar(text: $query, placeholder: "Search posts, people, tags")
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.vertical, Spacing.sm)

            if query.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        MtrxSectionHeader(title: "Trending")
                            .padding(.horizontal, Spacing.contentPadding)
                        ForEach(trending, id: \.self) { tag in
                            Button { query = tag } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "number")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.accentPrimary)
                                        .frame(width: 32, height: 32)
                                        .background(Color.accentPrimary.opacity(0.12))
                                        .clipShape(Circle())
                                    Text(tag).font(.mtrxBody).foregroundStyle(Color.labelPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.labelTertiary)
                                }
                                .padding(.horizontal, Spacing.contentPadding)
                                .padding(.vertical, Spacing.sm)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, Spacing.sm)
                }
            } else if results.isEmpty {
                MtrxEmptyState(icon: "magnifyingglass", title: "No results",
                               message: "Nothing matched “\(query)”. Try another search.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { post in
                            PostCardView(post: post)
                            MtrxDivider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Social Notifications (social-only)

/// Social notifications only — likes, reposts, follows, mentions. System
/// notifications live elsewhere (Account ▸ Settings ▸ Notifications).
struct SocialNotificationsView: View {
    private struct Notif: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let detail: String
        let time: String
    }

    private let items: [Notif] = [
        Notif(icon: "heart.fill", color: .statusError, title: "Elena Vasquez liked your post", detail: "“Just shipped the new escrow flow…”", time: "2m"),
        Notif(icon: "arrow.2.squarepath", color: .statusSuccess, title: "Ravi Patel reposted you", detail: "Governance Proposal #47", time: "18m"),
        Notif(icon: "person.fill.badge.plus", color: .accentPrimary, title: "Sofia Nakamura followed you", detail: "@sofia.base", time: "1h"),
        Notif(icon: "at", color: .accentTertiary, title: "You were mentioned", detail: "@elena.eth: “…ask @dardan about it”", time: "3h"),
        Notif(icon: "bubble.left.fill", color: .statusInfo, title: "New comment on your post", detail: "“This is huge for trustless deals.”", time: "5h"),
        Notif(icon: "checkmark.seal.fill", color: .accentSecondary, title: "Your post was verified on-chain", detail: "0xa1b2c3…d4e5", time: "1d"),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { n in
                    HStack(spacing: Spacing.ms) {
                        Image(systemName: n.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(n.color)
                            .frame(width: 38, height: 38)
                            .background(n.color.opacity(0.14))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.title).font(.mtrxCalloutBold).foregroundStyle(Color.labelPrimary)
                            Text(n.detail).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary).lineLimit(1)
                        }
                        Spacer()
                        Text(n.time).font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.vertical, Spacing.sm)
                    MtrxDivider()
                }
            }
            .padding(.top, Spacing.xs)
        }
    }
}

// MARK: - History (bookmarks + recently viewed)

/// The drawer's History entry. Holds the user's bookmarks and their
/// recently viewed posts — a home for everything they've saved.
struct SocialHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel = SocialViewModel.shared
    @ObservedObject private var bookmarks = SocialBookmarkStore.shared
    @State private var section: HistoryTab = .bookmarks

    enum HistoryTab: String, CaseIterable, Identifiable {
        case bookmarks = "Bookmarks"
        case recent = "Recent"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Picker("History", selection: $section) {
                        ForEach(HistoryTab.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)

                    if posts.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(posts) { post in
                                historyRow(post)
                                MtrxDivider()
                            }
                        }
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
            .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                }
            }
        }
    }

    /// Bookmarks surfaces posts the user has saved; Recent shows the
    /// freshest of the feed they've been scrolling.
    private var posts: [SocialPostDisplay] {
        switch section {
        case .bookmarks: return viewModel.posts.filter { bookmarks.isBookmarked($0.id) }
        case .recent:    return Array(viewModel.posts.prefix(12))
        }
    }

    private func historyRow(_ post: SocialPostDisplay) -> some View {
        HStack(alignment: .top, spacing: Spacing.ms) {
            Image(systemName: section == .bookmarks ? "bookmark.fill" : "clock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(section == .bookmarks ? Color.accentPrimary : Color.labelTertiary)
                .frame(width: 34, height: 34)
                .background((section == .bookmarks ? Color.accentPrimary : Color.labelTertiary).opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(post.displayName).font(.mtrxCalloutBold).foregroundStyle(Color.labelPrimary)
                    Text(post.handle).font(.mtrxCaption1).foregroundStyle(Color.labelTertiary)
                }
                Text(post.body)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: section == .bookmarks ? "bookmark" : "clock.arrow.circlepath")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.labelTertiary)
            Text(section == .bookmarks ? "No bookmarks yet" : "Nothing here yet")
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)
            Text(section == .bookmarks
                 ? "Tap the bookmark icon on any post to save it here."
                 : "Posts you open will show up here.")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        }
        .padding(.top, 80)
    }
}
