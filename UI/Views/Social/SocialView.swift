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
        case .verified: return "checkmark.seal.fill"
        case .unverified: return "exclamationmark.triangle"
        case .pending: return "clock"
        }
    }

    var color: Color {
        switch self {
        case .verified: return .green
        case .unverified: return .orange
        case .pending: return .gray
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
            try await Task.sleep(nanoseconds: 100_000_000)
            // Production: fetch from on-chain indexer + IPFS
            posts = []
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
        guard !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPublishing = true
        defer { isPublishing = false }

        do {
            // Production: sign message with wallet, post to chain, pin to IPFS
            try await Task.sleep(nanoseconds: 500_000_000)
            composerText = ""
            proofLinksToAttach = []
            isComposerPresented = false
            await loadPosts()
        } catch {
            errorMessage = "Failed to publish: \(error.localizedDescription)"
        }
    }

    func reactToPost(_ postId: String, emoji: String) async {
        // Production: submit on-chain reaction
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
                postsList
            }
            .navigationTitle("Social")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.isComposerPresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Create new post")
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
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                await viewModel.loadPosts()
            }
        }
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
        .background(Color(.systemBackground))
    }

    // MARK: - Posts List

    private var postsList: some View {
        List {
            if viewModel.isLoading && viewModel.posts.isEmpty {
                ForEach(0..<5, id: \.self) { _ in
                    PostSkeletonView()
                        .listRowSeparator(.hidden)
                }
            } else if viewModel.filteredPosts.isEmpty {
                emptyStateView
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.filteredPosts) { post in
                    PostCardView(
                        post: post,
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
            Image(systemName: "bubble.left.and.bubble.right")
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
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .accessibilityLabel("Post content")

                if !viewModel.proofLinksToAttach.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Proof Links")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(viewModel.proofLinksToAttach) { link in
                            HStack {
                                Image(systemName: "link")
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
                            .background(Color(.systemGray6))
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
                        Image(systemName: post.verificationStatus.icon)
                            .foregroundStyle(post.verificationStatus.color)
                            .font(.caption)
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
                    Image(systemName: "building.columns")
                    Text("Proposal #\(proposalId)")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            // Proof links
            if !post.proofLinks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(post.proofLinks) { link in
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text(link.title)
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            // Actions
            HStack(spacing: 20) {
                ForEach(post.reactions, id: \.emoji) { reaction in
                    Button {
                        onReact(reaction.emoji)
                    } label: {
                        HStack(spacing: 4) {
                            Text(reaction.emoji)
                            Text("\(reaction.count)")
                                .font(.caption)
                                .foregroundStyle(reaction.hasReacted ? .blue : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

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

                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                    Text("\(post.replyCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
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
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
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
                    .foregroundStyle(.green)

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
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                    Button {
                        UIPasteboard.general.url = url
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
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
