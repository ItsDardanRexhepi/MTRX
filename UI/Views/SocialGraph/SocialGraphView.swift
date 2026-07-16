// SocialGraphView.swift
// MTRX
//
// Social graph — following/followers lists, activity feed, follow/unfollow management.

import SwiftUI

// MARK: - Data Models

struct ProfileItem: Identifiable {
    let id = UUID()
    let address: String
    let ens: String?
    let followerCount: Int
    var isFollowing: Bool
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let actor: String
    let type: String
    let description: String
    let timestamp: String
}

// MARK: - View Model

@MainActor
class SocialGraphViewModel: ObservableObject {
    @Published var following: [ProfileItem] = []
    @Published var followers: [ProfileItem] = []
    @Published var feed: [ActivityItem] = []
    @Published var selectedTab: String = "Following"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isDemo: Bool = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    let tabs = ["Following", "Followers", "Feed"]

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live social graph from SocialGraphService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                async let followingReq = SocialGraphService.shared.getFollowing(address: address)
                async let followersReq = SocialGraphService.shared.getFollowers(address: address)
                async let feedReq = SocialGraphService.shared.getActivityFeed(address: address)
                following = try await followingReq.map { p in
                    ProfileItem(address: p.address, ens: p.ens, followerCount: p.followerCount, isFollowing: p.isFollowing)
                }
                followers = try await followersReq.map { p in
                    ProfileItem(address: p.address, ens: p.ens, followerCount: p.followerCount, isFollowing: p.isFollowing)
                }
                feed = try await feedReq.map { a in
                    ActivityItem(actor: a.actor, type: a.type, description: a.description,
                                 timestamp: Self.relativeFormatter.localizedString(for: a.timestamp, relativeTo: Date()))
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live social graph unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(700))
            following = SocialGraphViewModel.sampleFollowing
            followers = SocialGraphViewModel.sampleFollowers
            feed = SocialGraphViewModel.sampleFeed
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load social graph."
            isLoading = false
        }
    }

    func toggleFollow(for profile: ProfileItem) async {
        do {
            try await Task.sleep(for: .milliseconds(500))

            if let idx = following.firstIndex(where: { $0.id == profile.id }) {
                following[idx] = ProfileItem(
                    address: profile.address,
                    ens: profile.ens,
                    followerCount: profile.followerCount,
                    isFollowing: !profile.isFollowing
                )
            }

            if let idx = followers.firstIndex(where: { $0.id == profile.id }) {
                followers[idx] = ProfileItem(
                    address: profile.address,
                    ens: profile.ens,
                    followerCount: profile.followerCount,
                    isFollowing: !profile.isFollowing
                )
            }
        } catch { }
    }

    static let sampleFollowing: [ProfileItem] = [
        ProfileItem(address: "0x1a2b...3c4d", ens: "vitalik.eth", followerCount: 148200, isFollowing: true),
        ProfileItem(address: "0x5e6f...7a8b", ens: "stani.eth", followerCount: 42300, isFollowing: true),
        ProfileItem(address: "0x9c0d...1e2f", ens: nil, followerCount: 1280, isFollowing: true),
        ProfileItem(address: "0x3a4b...5c6d", ens: "punk6529.eth", followerCount: 89400, isFollowing: true)
    ]

    static let sampleFollowers: [ProfileItem] = [
        ProfileItem(address: "0xaa11...bb22", ens: "alice.eth", followerCount: 340, isFollowing: false),
        ProfileItem(address: "0xcc33...dd44", ens: nil, followerCount: 56, isFollowing: true),
        ProfileItem(address: "0xee55...ff66", ens: "bob.eth", followerCount: 1120, isFollowing: false),
        ProfileItem(address: "0x7788...9900", ens: "carol.eth", followerCount: 780, isFollowing: true)
    ]

    static let sampleFeed: [ActivityItem] = [
        ActivityItem(actor: "vitalik.eth", type: "follow", description: "followed stani.eth", timestamp: "2m ago"),
        ActivityItem(actor: "alice.eth", type: "mint", description: "minted Pudgy Penguin #4521", timestamp: "15m ago"),
        ActivityItem(actor: "punk6529.eth", type: "swap", description: "swapped 10 ETH for USDC", timestamp: "1h ago"),
        ActivityItem(actor: "bob.eth", type: "vote", description: "voted on Aave Proposal #142", timestamp: "3h ago"),
        ActivityItem(actor: "stani.eth", type: "post", description: "published a new Lens post", timestamp: "5h ago")
    ]
}

// MARK: - Social Graph View

struct SocialGraphView: View {
    @StateObject private var viewModel = SocialGraphViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.following.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.following.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    socialContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Social Graph")
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

    private var socialContent: some View {
        VStack(spacing: 0) {
            tabPicker
            tabContent
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(viewModel.tabs, id: \.self) { tab in
                    MtrxChip(
                        label: tabLabel(for: tab),
                        isSelected: viewModel.selectedTab == tab
                    ) {
                        withAnimation(Motion.springDefault) {
                            viewModel.selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func tabLabel(for tab: String) -> String {
        switch tab {
        case "Following": return "Following (\(viewModel.following.count))"
        case "Followers": return "Followers (\(viewModel.followers.count))"
        default: return tab
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sm) {
                switch viewModel.selectedTab {
                case "Following":
                    profileList(viewModel.following)
                case "Followers":
                    profileList(viewModel.followers)
                case "Feed":
                    activityFeed
                default:
                    EmptyView()
                }
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Profile List

    private func profileList(_ profiles: [ProfileItem]) -> some View {
        ForEach(profiles) { profile in
            profileRow(profile)
        }
    }

    private func profileRow(_ profile: ProfileItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                MtrxAvatar(
                    text: profile.ens ?? String(profile.address.prefix(4)),
                    color: .accentPrimary,
                    size: 44
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(profile.ens ?? profile.address)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.backers)
                            .font(.system(size: 11))
                        Text(formattedCount(profile.followerCount))
                            .font(.mtrxCaption1)
                    }
                    .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                Button {
                    Task { await viewModel.toggleFollow(for: profile) }
                } label: {
                    Text(profile.isFollowing ? "Unfollow" : "Follow")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: profile.isFollowing ? .secondary : .primary,
                    size: .compact
                ))
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Activity Feed

    private var activityFeed: some View {
        ForEach(viewModel.feed) { activity in
            MtrxCard(style: .standard) {
                HStack(spacing: Spacing.ms) {
                    MtrxAvatar(
                        symbol: activityIcon(for: activity.type),
                        color: activityColor(for: activity.type),
                        size: 36
                    )

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.xs) {
                            Text(activity.actor)
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.accentPrimary)
                            Text(activity.description)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelPrimary)
                        }
                        Text(activity.timestamp)
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Helpers

    private func formattedCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK followers", Double(count) / 1000.0)
        }
        return "\(count) followers"
    }

    private func activityIcon(for type: String) -> String {
        switch type {
        case "follow": return Symbols.backers
        case "mint": return Symbols.nft
        case "swap": return Symbols.swap
        case "vote": return Symbols.vote
        case "post": return Symbols.post
        case "property_purchase", "tokenize_asset": return Symbols.property
        default: return Symbols.globe
        }
    }

    private func activityColor(for type: String) -> Color {
        switch type {
        case "follow": return .accentPrimary
        case "mint": return .statusInfo
        case "swap": return .statusSuccess
        case "vote": return .accentTertiary
        case "post": return .trinityPrimary
        case "property_purchase", "tokenize_asset": return .accentPrimary
        default: return .labelSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    SocialGraphView()
        .preferredColorScheme(.dark)
}
