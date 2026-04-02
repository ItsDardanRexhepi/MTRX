// SocialView.swift
// MTRX - On-chain social feed with governance messaging and proof sharing
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI
import Combine

// MARK: - Models

enum PostVerificationStatus: String, Codable, CaseIterable {
    case verified = "verified"
    case unverified = "unverified"
    case pending = "pending"

    var icon: String {
        switch self {
        case .verified: return Symbols.verified
        case .unverified: return Symbols.alertWarning
        case .pending: return Symbols.pending
        }
    }

    var color: Color {
        switch self {
        case .verified: return .statusSuccess
        case .unverified: return .statusWarning
        case .pending: return .labelTertiary
        }
    }

    var label: String {
        switch self {
        case .verified: return "On-Chain Verified"
        case .unverified: return "Unverified"
        case .pending: return "Pending Verification"
        }
    }
}

struct SocialPost: Identifiable, Codable, Equatable {
    let id: String
    let authorAddress: String
    let authorDisplayName: String
    let authorAvatarURL: URL?
    let content: String
    let timestamp: Date
    let verificationStatus: PostVerificationStatus
    let transactionHash: String?
    let proofLinks: [ProofLink]
    let governanceProposalId: String?
    let reactions: [Reaction]
    let replyCount: Int
    let chainId: Int
    var likeCount: Int
    var repostCount: Int
    var hasLiked: Bool
    var hasReposted: Bool

    struct ProofLink: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let url: URL
        let chainExplorerURL: URL?
    }

    struct Reaction: Codable, Equatable {
        let emoji: String
        let count: Int
        let hasReacted: Bool
    }

    init(id: String, authorAddress: String, authorDisplayName: String, authorAvatarURL: URL? = nil, content: String, timestamp: Date, verificationStatus: PostVerificationStatus, transactionHash: String? = nil, proofLinks: [ProofLink] = [], governanceProposalId: String? = nil, reactions: [Reaction] = [], replyCount: Int = 0, chainId: Int = 8453, likeCount: Int = 0, repostCount: Int = 0, hasLiked: Bool = false, hasReposted: Bool = false) {
        self.id = id
        self.authorAddress = authorAddress
        self.authorDisplayName = authorDisplayName
        self.authorAvatarURL = authorAvatarURL
        self.content = content
        self.timestamp = timestamp
        self.verificationStatus = verificationStatus
        self.transactionHash = transactionHash
        self.proofLinks = proofLinks
        self.governanceProposalId = governanceProposalId
        self.reactions = reactions
        self.replyCount = replyCount
        self.chainId = chainId
        self.likeCount = likeCount
        self.repostCount = repostCount
        self.hasLiked = hasLiked
        self.hasReposted = hasReposted
    }
}

// MARK: - ViewModel

@MainActor
final class SocialViewModel: ObservableObject {
    @Published var posts: [SocialPost] = []
    @Published var filteredPosts: [SocialPost] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var selectedFilter: PostFilter = .all
    @Published var composerText = ""
    @Published var isComposerPresented = false
    @Published var isPublishing = false
    @Published var proofLinksToAttach: [SocialPost.ProofLink] = []

    enum PostFilter: String, CaseIterable {
        case all = "All"
        case verified = "Verified"
        case governance = "Governance"
        case myPosts = "My Posts"
    }

    private var cancellables = Set<AnyCancellable>()
    private let currentWalletAddress: String
    private let api = MTRXAPIClient.shared

    init(walletAddress: String = "") {
        self.currentWalletAddress = walletAddress
        setupFilterSubscription()
    }

    private func setupFilterSubscription() {
        $selectedFilter
            .combineLatest($posts)
            .map { filter, posts in
                switch filter {
                case .all:
                    return posts
                case .verified:
                    return posts.filter { $0.verificationStatus == .verified }
                case .governance:
                    return posts.filter { $0.governanceProposalId != nil }
                case .myPosts:
                    return posts.filter { [weak self] in
                        $0.authorAddress == self?.currentWalletAddress
                    }
                }
            }
            .assign(to: &$filteredPosts)
    }

    func loadPosts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: [String: AnyCodableValue] = try await api.listFeed()
            posts = parseFeedResponse(response)
        } catch {
            errorMessage = "Failed to load posts: \(error.localizedDescription)"
        }
    }

    func refreshPosts() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await loadPosts()
    }

    func publishPost() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isPublishing = true
        defer { isPublishing = false }

        do {
            let attachments = proofLinksToAttach.map { $0.url.absoluteString }
            let request = PostCreateRequest(
                content: trimmed,
                attachments: attachments.isEmpty ? nil : attachments,
                visibility: "public"
            )
            let _: [String: AnyCodableValue] = try await api.createPost(request)
            composerText = ""
            proofLinksToAttach = []
            isComposerPresented = false
            await loadPosts()
        } catch {
            errorMessage = "Failed to publish: \(error.localizedDescription)"
        }
    }

    func likePost(_ postId: String) async {
        guard let idx = posts.firstIndex(where: { $0.id == postId }) else { return }
        let wasLiked = posts[idx].hasLiked
        posts[idx].hasLiked = !wasLiked
        posts[idx].likeCount += wasLiked ? -1 : 1

        do {
            let _: [String: AnyCodableValue] = try await api.postRaw(
                path: "/api/v1/social/posts/\(postId)/like",
                body: ["action": wasLiked ? "unlike" : "like"]
            )
        } catch {
            posts[idx].hasLiked = wasLiked
            posts[idx].likeCount += wasLiked ? 1 : -1
        }
    }

    func repostPost(_ postId: String) async {
        guard let idx = posts.firstIndex(where: { $0.id == postId }) else { return }
        let wasReposted = posts[idx].hasReposted
        posts[idx].hasReposted = !wasReposted
        posts[idx].repostCount += wasReposted ? -1 : 1

        do {
            let _: [String: AnyCodableValue] = try await api.postRaw(
                path: "/api/v1/social/posts/\(postId)/repost",
                body: ["action": wasReposted ? "unrepost" : "repost"]
            )
        } catch {
            posts[idx].hasReposted = wasReposted
            posts[idx].repostCount += wasReposted ? 1 : -1
        }
    }

    func reactToPost(_ postId: String, emoji: String) async {
        do {
            let _: [String: AnyCodableValue] = try await api.postRaw(
                path: "/api/v1/social/posts/\(postId)/react",
                body: ["emoji": emoji]
            )
            await loadPosts()
        } catch {
            errorMessage = "Failed to react: \(error.localizedDescription)"
        }
    }

    func shareProofLink(for post: SocialPost) -> URL? {
        guard let txHash = post.transactionHash else { return nil }
        return URL(string: "https://basescan.org/tx/\(txHash)")
    }

    func addProofLink(title: String, url: URL) {
        let link = SocialPost.ProofLink(
            id: UUID().uuidString,
            title: title,
            url: url,
            chainExplorerURL: nil
        )
        proofLinksToAttach.append(link)
    }

    // MARK: - Response Parsing

    private func parseFeedResponse(_ response: [String: AnyCodableValue]) -> [SocialPost] {
        guard case .array(let items) = response["posts"] ?? response["data"] ?? .null else {
            return []
        }
        return items.compactMap { item -> SocialPost? in
            guard case .dictionary(let dict) = item else { return nil }
            let id = dict["id"]?.stringValue ?? UUID().uuidString
            let content = dict["content"]?.stringValue ?? ""
            let authorAddress = dict["author_address"]?.stringValue ?? dict["author"]?.stringValue ?? ""
            let authorName = dict["author_display_name"]?.stringValue ?? dict["author_name"]?.stringValue ?? truncatedAddress(authorAddress)
            let statusRaw = dict["verification_status"]?.stringValue ?? "unverified"
            let status = PostVerificationStatus(rawValue: statusRaw) ?? .unverified
            let txHash = dict["transaction_hash"]?.stringValue ?? dict["tx_hash"]?.stringValue
            let proposalId = dict["governance_proposal_id"]?.stringValue
            let replyCount = dict["reply_count"]?.intValue ?? 0
            let likeCount = dict["like_count"]?.intValue ?? 0
            let repostCount = dict["repost_count"]?.intValue ?? 0
            let hasLiked = dict["has_liked"]?.boolValue ?? false
            let hasReposted = dict["has_reposted"]?.boolValue ?? false
            let chainId = dict["chain_id"]?.intValue ?? 8453

            return SocialPost(
                id: id,
                authorAddress: authorAddress,
                authorDisplayName: authorName,
                content: content,
                timestamp: Date(),
                verificationStatus: status,
                transactionHash: txHash,
                governanceProposalId: proposalId,
                replyCount: replyCount,
                chainId: chainId,
                likeCount: likeCount,
                repostCount: repostCount,
                hasLiked: hasLiked,
                hasReposted: hasReposted
            )
        }
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

// MARK: - Main View

struct SocialView: View {
    @StateObject private var viewModel: SocialViewModel
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showProofLinkSheet = false
    @State private var proofLinkTitle = ""
    @State private var proofLinkURL = ""

    init(walletAddress: String = "") {
        _viewModel = StateObject(wrappedValue: SocialViewModel(walletAddress: walletAddress))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if viewModel.isLoading && viewModel.posts.isEmpty {
                    loadingView
                } else if let error = viewModel.errorMessage, viewModel.posts.isEmpty {
                    errorView(error)
                } else {
                    postsList
                }
            }
            .navigationTitle("Social")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            MessagingView()
                        } label: {
                            Image(systemName: Symbols.message)
                        }
                        .accessibilityLabel("Messages")

                        NavigationLink {
                            GovernanceView()
                        } label: {
                            Image(systemName: Symbols.dao)
                        }
                        .accessibilityLabel("Governance")

                        Button {
                            viewModel.isComposerPresented = true
                        } label: {
                            Image(systemName: Symbols.post)
                        }
                        .accessibilityLabel("Create new post")
                    }
                }
            }
            .sheet(isPresented: $viewModel.isComposerPresented) {
                composerSheet
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareProofView(url: url)
                }
            }
            .task {
                await viewModel.loadPosts()
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    PostSkeletonView()
                }
            }
            .padding()
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: Symbols.alertWarning)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Something Went Wrong")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadPosts() }
            } label: {
                Label("Retry", systemImage: Symbols.refresh)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SocialViewModel.PostFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: viewModel.selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.backgroundPrimary)
    }

    // MARK: - Posts List

    private var postsList: some View {
        List {
            if viewModel.filteredPosts.isEmpty {
                emptyStateView
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.filteredPosts) { post in
                    PostCardView(
                        post: post,
                        onLike: {
                            Task { await viewModel.likePost(post.id) }
                        },
                        onRepost: {
                            Task { await viewModel.repostPost(post.id) }
                        },
                        onComment: {
                            // Future: open comment thread
                        },
                        onReact: { emoji in
                            Task { await viewModel.reactToPost(post.id, emoji: emoji) }
                        },
                        onShareProof: {
                            shareURL = viewModel.shareProofLink(for: post)
                            showShareSheet = shareURL != nil
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refreshPosts()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: Symbols.social)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Posts Yet")
                .font(.title3.weight(.semibold))
            Text("Be the first to share on-chain updates with the community.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Create Post") {
                viewModel.isComposerPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Composer

    private var composerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $viewModel.composerText)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.backgroundSecondary)
                    .cornerRadius(12)
                    .accessibilityLabel("Post content")

                if !viewModel.proofLinksToAttach.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Proof Links")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(viewModel.proofLinksToAttach) { link in
                            HStack {
                                Image(systemName: Symbols.link)
                                Text(link.title)
                                    .font(.caption)
                                Spacer()
                                Button {
                                    viewModel.proofLinksToAttach.removeAll { $0.id == link.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color.backgroundSecondary)
                            .cornerRadius(8)
                        }
                    }
                }

                Button {
                    showProofLinkSheet = true
                } label: {
                    Label("Attach Proof Link", systemImage: "link.badge.plus")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.isComposerPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await viewModel.publishPost() }
                    } label: {
                        if viewModel.isPublishing {
                            ProgressView()
                        } else {
                            Text("Publish")
                        }
                    }
                    .disabled(viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isPublishing)
                }
            }
            .sheet(isPresented: $showProofLinkSheet) {
                proofLinkInputSheet
            }
        }
    }

    private var proofLinkInputSheet: some View {
        NavigationStack {
            Form {
                Section("Link Details") {
                    TextField("Title", text: $proofLinkTitle)
                    TextField("URL", text: $proofLinkURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("Add Proof Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showProofLinkSheet = false
                        proofLinkTitle = ""
                        proofLinkURL = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let url = URL(string: proofLinkURL) {
                            viewModel.addProofLink(title: proofLinkTitle, url: url)
                        }
                        showProofLinkSheet = false
                        proofLinkTitle = ""
                        proofLinkURL = ""
                    }
                    .disabled(proofLinkTitle.isEmpty || URL(string: proofLinkURL) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Post Card

struct PostCardView: View {
    let post: SocialPost
    var onLike: () -> Void = {}
    var onRepost: () -> Void = {}
    var onComment: () -> Void = {}
    let onReact: (String) -> Void
    let onShareProof: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(String(post.authorDisplayName.prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(post.authorDisplayName)
                            .font(.subheadline.weight(.semibold))
                        if post.verificationStatus == .verified {
                            Image(systemName: post.verificationStatus.icon)
                                .foregroundStyle(post.verificationStatus.color)
                                .font(.caption)
                        }
                    }
                    Text(truncatedAddress(post.authorAddress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(post.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Verification badge
            HStack(spacing: 4) {
                Image(systemName: post.verificationStatus.icon)
                    .font(.caption2)
                Text(post.verificationStatus.label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(post.verificationStatus.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(post.verificationStatus.color.opacity(0.12))
            .cornerRadius(6)

            // Content
            Text(post.content)
                .font(.body)

            // Governance tag
            if let proposalId = post.governanceProposalId {
                HStack(spacing: 4) {
                    Image(systemName: Symbols.dao)
                    Text("Proposal #\(proposalId)")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.statusInfo)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.statusInfo.opacity(0.1))
                .cornerRadius(6)
            }

            // Proof links
            if !post.proofLinks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(post.proofLinks) { link in
                        HStack(spacing: 4) {
                            Image(systemName: Symbols.link)
                                .font(.caption2)
                            Text(link.title)
                                .font(.caption)
                                .foregroundStyle(.statusInfo)
                        }
                    }
                }
            }

            // Actions: Like, Comment, Repost, Reactions, Proof
            HStack(spacing: 16) {
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: post.hasLiked ? Symbols.like : "heart")
                            .foregroundStyle(post.hasLiked ? .statusError : .secondary)
                        Text("\(post.likeCount)")
                            .font(.caption)
                            .foregroundStyle(post.hasLiked ? .statusError : .secondary)
                    }
                }
                .buttonStyle(.plain)

                Button(action: onComment) {
                    HStack(spacing: 4) {
                        Image(systemName: Symbols.comment)
                        Text("\(post.replyCount)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: onRepost) {
                    HStack(spacing: 4) {
                        Image(systemName: Symbols.repost)
                            .foregroundStyle(post.hasReposted ? .statusSuccess : .secondary)
                        Text("\(post.repostCount)")
                            .font(.caption)
                            .foregroundStyle(post.hasReposted ? .statusSuccess : .secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if post.transactionHash != nil {
                    Button {
                        onShareProof()
                    } label: {
                        Label("Proof", systemImage: "checkmark.shield")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding()
        .background(Color.backgroundPrimary)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(post.authorDisplayName), \(post.verificationStatus.label). \(post.content)")
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.backgroundSecondary)
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PostSkeletonView: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 14)
                    RoundedRectangle(cornerRadius: 4).frame(width: 80, height: 10)
                }
            }
            RoundedRectangle(cornerRadius: 4).frame(height: 14)
            RoundedRectangle(cornerRadius: 4).frame(width: 200, height: 14)
        }
        .foregroundStyle(Color(.systemGray5))
        .padding()
        .opacity(shimmer ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
        .accessibilityLabel("Loading post")
    }
}

struct ShareProofView: View {
    let url: URL

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.statusSuccess)

                Text("On-Chain Proof")
                    .font(.title2.weight(.bold))

                Text("Share this transaction proof link to verify the authenticity of this post on Base network.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        .padding()
                        .background(Color.backgroundSecondary)
                        .cornerRadius(8)

                    Button {
                        UIPasteboard.general.url = url
                    } label: {
                        Label("Copy Link", systemImage: Symbols.copy)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Share Proof")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview("Social Feed") {
    SocialView(walletAddress: "0x1234567890abcdef1234567890abcdef12345678")
}
