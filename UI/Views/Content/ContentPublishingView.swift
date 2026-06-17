// ContentPublishingView.swift
// MTRX
//
// Decentralized content publishing — create, browse, and tip on-chain content.

import SwiftUI
import PhotosUI

// MARK: - View Model

final class ContentPublishingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var feedPosts: [ContentPost] = []
    @Published var myPosts: [ContentPost] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isEmpty: Bool = false

    // Create Post
    @Published var postTitle: String = ""
    @Published var postBody: String = ""
    @Published var selectedStorageLayer: StorageLayer = .ipfs
    @Published var selectedImageItem: PhotosPickerItem?
    @Published var selectedImageData: Data?
    @Published var isPublishing: Bool = false
    @Published var publishedHash: String?

    // Tip
    @Published var showTipSheet: Bool = false
    @Published var tipAmount: String = "0.01"
    @Published var tipTarget: ContentPost?
    @Published var isTipping: Bool = false

    enum StorageLayer: String, CaseIterable {
        case ipfs = "IPFS"
        case arweave = "Arweave"

        var icon: String {
            switch self {
            case .ipfs: return "externaldrive.connected.to.line.below"
            case .arweave: return "archivebox"
            }
        }
    }

    // MARK: - Load

    func loadContent() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.feedPosts = ContentPost.sampleFeed
            self.myPosts = ContentPost.sampleMine
            self.isEmpty = self.feedPosts.isEmpty
            self.isLoading = false
        }
    }

    // MARK: - Publish

    /// Request/response shapes for the real `/storage/files` pin.
    private struct PublishBody: Encodable {
        let filename: String
        let mimeType: String
        let layer: String
        let dataBase64: String
    }
    private struct PublishedFile: Decodable {
        let cid: String
    }

    func publishPost() {
        guard !postTitle.isEmpty, !postBody.isEmpty else {
            errorMessage = "Title and body are required."
            return
        }
        isPublishing = true
        errorMessage = nil

        let title = postTitle
        let body = postBody
        let layer = selectedStorageLayer.rawValue
        let imageData = selectedImageData

        Task {
            // Pin the real content bytes — the backend assigns the CID. We never
            // fabricate one; on failure we surface the error.
            let contentData: Data
            let mimeType: String
            if let imageData {
                contentData = imageData
                mimeType = "application/octet-stream"
            } else {
                contentData = Data("\(title)\n\n\(body)".utf8)
                mimeType = "text/markdown"
            }
            let reqBody = PublishBody(
                filename: title,
                mimeType: mimeType,
                layer: layer,
                dataBase64: contentData.base64EncodedString()
            )
            do {
                let published: PublishedFile = try await MTRXAPIClient.shared.post(path: "/storage/files", body: reqBody)
                await MainActor.run {
                    let newPost = ContentPost(
                        author: "You",
                        authorAddress: "0xYour...Addr",
                        title: title,
                        body: body,
                        contentHash: published.cid,
                        storageLayer: layer,
                        timestamp: Date(),
                        tips: 0,
                        hasImage: imageData != nil
                    )
                    self.feedPosts.insert(newPost, at: 0)
                    self.myPosts.insert(newPost, at: 0)
                    self.publishedHash = published.cid
                    self.isPublishing = false
                    self.resetPostForm()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Publish failed: \(error.localizedDescription)"
                    self.isPublishing = false
                }
            }
        }
    }

    // MARK: - Tip

    func initiateTip(for post: ContentPost) {
        tipTarget = post
        showTipSheet = true
    }

    func sendTip() {
        guard let target = tipTarget, let amount = Double(tipAmount), amount > 0 else { return }
        isTipping = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            if let index = self.feedPosts.firstIndex(where: { $0.id == target.id }) {
                self.feedPosts[index].tips += amount
            }
            self.isTipping = false
            self.showTipSheet = false
            self.tipTarget = nil
            self.tipAmount = "0.01"
        }
    }

    // MARK: - Image Handling

    func handleImageSelection() {
        guard let item = selectedImageItem else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run { selectedImageData = data }
            }
        }
    }

    private func resetPostForm() {
        postTitle = ""
        postBody = ""
        selectedImageItem = nil
        selectedImageData = nil
        selectedStorageLayer = .ipfs
    }
}

// MARK: - Models

struct ContentPost: Identifiable {
    let id = UUID()
    let author: String
    let authorAddress: String
    let title: String
    let body: String
    let contentHash: String
    let storageLayer: String
    let timestamp: Date
    var tips: Double
    let hasImage: Bool

    static var sampleFeed: [ContentPost] {
        [
            ContentPost(author: "alice.eth", authorAddress: "0xA1b2...C3d4", title: "The Future of Decentralized Identity", body: "Exploring how self-sovereign identity will reshape digital interactions and eliminate centralized gatekeepers.", contentHash: "QmX7v2n3...abc", storageLayer: "IPFS", timestamp: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date(), tips: 0.45, hasImage: true),
            ContentPost(author: "bob.eth", authorAddress: "0xE5f6...G7h8", title: "DeFi Yield Strategies Q2 2026", body: "A comprehensive analysis of current yield farming opportunities across major protocols.", contentHash: "QmY8w3o4...def", storageLayer: "Arweave", timestamp: Calendar.current.date(byAdding: .hour, value: -5, to: Date()) ?? Date(), tips: 1.2, hasImage: false),
            ContentPost(author: "carol.eth", authorAddress: "0xI9j0...K1l2", title: "Smart Contract Security Checklist", body: "Essential security patterns every Solidity developer should implement before deploying to mainnet.", contentHash: "QmZ9x4p5...ghi", storageLayer: "IPFS", timestamp: Calendar.current.date(byAdding: .hour, value: -12, to: Date()) ?? Date(), tips: 0.8, hasImage: false),
        ]
    }

    static var sampleMine: [ContentPost] {
        [
            ContentPost(author: "You", authorAddress: "0xYour...Addr", title: "My First On-Chain Post", body: "Testing the decentralized publishing flow on MTRX.", contentHash: "QmA1b2c3...jkl", storageLayer: "IPFS", timestamp: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(), tips: 0.1, hasImage: false),
        ]
    }
}

// MARK: - View

struct ContentPublishingView: View {
    @StateObject private var viewModel = ContentPublishingViewModel()
    @State private var selectedTab: ContentTab = .feed

    private let accentColor = Color(red: 0.0, green: 0.675, blue: 0.694)

    enum ContentTab: String, CaseIterable {
        case feed = "Feed"
        case create = "Create"
        case myContent = "My Content"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                tabContent
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Content")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { viewModel.loadContent() }
            .sheet(isPresented: $viewModel.showTipSheet) {
                tipSheet
            }
            .alert("Published", isPresented: Binding(
                get: { viewModel.publishedHash != nil },
                set: { if !$0 { viewModel.publishedHash = nil } }
            )) {
                Button("Copy Hash") {
                    UIPasteboard.general.string = viewModel.publishedHash
                    viewModel.publishedHash = nil
                }
                Button("OK", role: .cancel) { viewModel.publishedHash = nil }
            } message: {
                Text("Content hash:\n\(viewModel.publishedHash ?? "")")
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(ContentTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .feed:
            feedSection
        case .create:
            createSection
        case .myContent:
            myContentSection
        }
    }

    // MARK: - Feed

    private var feedSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading feed...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isEmpty {
                ContentUnavailableView("No Content", systemImage: "doc.text", description: Text("Follow addresses to see their published content."))
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(viewModel.feedPosts) { post in
                            postCard(post)
                        }
                    }
                    .padding(Spacing.contentPadding)
                }
            }
        }
    }

    private func postCard(_ post: ContentPost) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author)
                        .font(.mtrxHeadline)
                    Text(post.authorAddress)
                        .font(.mtrxMonoTiny)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(post.timestamp, style: .relative)
                    .font(.mtrxCaption2)
                    .foregroundStyle(.tertiary)
            }

            Text(post.title)
                .font(.mtrxBodyBold)

            Text(post.body)
                .font(.mtrxSubheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if post.hasImage {
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm)
                    .fill(Color(.systemGray5))
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    )
            }

            HStack {
                Label(post.storageLayer, systemImage: post.storageLayer == "IPFS" ? "externaldrive.connected.to.line.below" : "archivebox")
                    .font(.mtrxCaption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if post.tips > 0 {
                    Label(String(format: "%.2f ETH", post.tips), systemImage: "heart.fill")
                        .font(.mtrxCaption1)
                        .foregroundStyle(.pink)
                }

                Button {
                    viewModel.initiateTip(for: post)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "gift")
                        Text("Tip")
                    }
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
        .mtrxCardStyle()
    }

    // MARK: - Create

    private var createSection: some View {
        Form {
            Section("Title") {
                TextField("Post title", text: $viewModel.postTitle)
                    .font(.mtrxBody)
            }

            Section("Body") {
                TextEditor(text: $viewModel.postBody)
                    .font(.mtrxBody)
                    .frame(minHeight: 120)
            }

            Section("Image") {
                PhotosPicker(selection: $viewModel.selectedImageItem, matching: .images) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                            .foregroundStyle(accentColor)
                        Text(viewModel.selectedImageData != nil ? "Image selected" : "Add image")
                            .foregroundStyle(viewModel.selectedImageData != nil ? .primary : .secondary)
                    }
                }
                .onChange(of: viewModel.selectedImageItem) { _, _ in
                    viewModel.handleImageSelection()
                }

                if viewModel.selectedImageData != nil {
                    Button("Remove Image", role: .destructive) {
                        viewModel.selectedImageItem = nil
                        viewModel.selectedImageData = nil
                    }
                }
            }

            Section("Storage Layer") {
                Picker("Storage", selection: $viewModel.selectedStorageLayer) {
                    ForEach(ContentPublishingViewModel.StorageLayer.allCases, id: \.self) { layer in
                        Label(layer.rawValue, systemImage: layer.icon).tag(layer)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.mtrxFootnote)
                }
            }

            Section {
                Button {
                    viewModel.publishPost()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isPublishing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Publish")
                                .font(.mtrxHeadline)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                }
                .disabled(viewModel.isPublishing)
                .listRowInsets(EdgeInsets())
                .padding(Spacing.contentPadding)
            }
        }
    }

    // MARK: - My Content

    private var myContentSection: some View {
        Group {
            if viewModel.myPosts.isEmpty {
                ContentUnavailableView("No Posts Yet", systemImage: "square.and.pencil", description: Text("Your published content will appear here."))
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(viewModel.myPosts) { post in
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(post.title)
                                    .font(.mtrxHeadline)

                                Text(post.body)
                                    .font(.mtrxSubheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                HStack {
                                    Text(post.contentHash)
                                        .font(.mtrxMonoTiny)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .truncationMode(.middle)

                                    Spacer()

                                    Text(post.timestamp, format: .dateTime.month().day())
                                        .font(.mtrxCaption2)
                                        .foregroundStyle(.tertiary)
                                }

                                if post.tips > 0 {
                                    HStack {
                                        Image(systemName: "heart.fill")
                                            .foregroundStyle(.pink)
                                        Text(String(format: "%.2f ETH earned", post.tips))
                                            .font(.mtrxCaptionBold)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .mtrxCardStyle()
                        }
                    }
                    .padding(Spacing.contentPadding)
                }
            }
        }
    }

    // MARK: - Tip Sheet

    private var tipSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                if let target = viewModel.tipTarget {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(accentColor)

                        Text("Tip \(target.author)")
                            .font(.mtrxTitle3)

                        Text(target.title)
                            .font(.mtrxSubheadline)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Amount (ETH)", text: $viewModel.tipAmount)
                        .font(.mtrxMonoMedium)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))

                    Button {
                        viewModel.sendTip()
                    } label: {
                        HStack {
                            if viewModel.isTipping {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Send Tip")
                                    .font(.mtrxHeadline)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.buttonVertical)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                    }
                    .disabled(viewModel.isTipping)
                }

                Spacer()
            }
            .padding(Spacing.contentPadding)
            .navigationTitle("Send Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showTipSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview {
    ContentPublishingView()
}
