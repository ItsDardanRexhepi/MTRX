// GroupsView.swift
// MTRX
//
// Community groups — create, discover, join token-gated groups with feeds.

import SwiftUI

// MARK: - View Model

final class GroupsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var myGroups: [CommunityGroup] = []
    @Published var discoverGroups: [CommunityGroup] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isEmpty: Bool = false

    // Group Detail
    @Published var selectedGroup: CommunityGroup?
    @Published var showDetail: Bool = false
    @Published var groupFeed: [GroupPost] = []

    // Create Group
    @Published var createName: String = ""
    @Published var createDescription: String = ""
    @Published var createTokenGated: Bool = false
    @Published var createTokenAddress: String = ""
    @Published var createMinBalance: String = "1"
    @Published var isCreating: Bool = false
    @Published var createSuccess: Bool = false

    // Post
    @Published var newPostText: String = ""
    @Published var isPosting: Bool = false

    let categories = ["DeFi", "NFT", "Gaming", "Governance", "Development", "Social", "Education"]

    // MARK: - Load

    func loadGroups() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.myGroups = CommunityGroup.sampleMine
            self.discoverGroups = CommunityGroup.sampleDiscover
            self.isEmpty = self.myGroups.isEmpty
            self.isLoading = false
        }
    }

    // MARK: - Group Detail

    func openGroup(_ group: CommunityGroup) {
        selectedGroup = group
        groupFeed = GroupPost.sampleData
        showDetail = true
    }

    // MARK: - Join/Leave

    func toggleMembership(_ group: CommunityGroup) {
        if let index = myGroups.firstIndex(where: { $0.id == group.id }) {
            let removed = myGroups.remove(at: index)
            var updated = removed
            updated.isMember = false
            discoverGroups.insert(updated, at: 0)
        } else if let index = discoverGroups.firstIndex(where: { $0.id == group.id }) {
            var removed = discoverGroups.remove(at: index)
            removed.isMember = true
            myGroups.insert(removed, at: 0)
        }
        isEmpty = myGroups.isEmpty
    }

    // MARK: - Create

    func createGroup() {
        guard !createName.isEmpty else {
            errorMessage = "Group name is required."
            return
        }
        isCreating = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            let group = CommunityGroup(
                name: self.createName,
                description: self.createDescription,
                category: "Social",
                memberCount: 1,
                isTokenGated: self.createTokenGated,
                tokenRequirement: self.createTokenGated ? "\(self.createMinBalance) tokens" : nil,
                isMember: true,
                hasActivity: false
            )
            self.myGroups.insert(group, at: 0)
            self.isEmpty = false
            self.isCreating = false
            self.createSuccess = true
            self.resetCreateForm()
        }
    }

    // MARK: - Post

    func postToGroup() {
        guard !newPostText.isEmpty else { return }
        isPosting = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let post = GroupPost(author: "You", content: self.newPostText, timestamp: Date())
            self.groupFeed.insert(post, at: 0)
            self.newPostText = ""
            self.isPosting = false
        }
    }

    private func resetCreateForm() {
        createName = ""
        createDescription = ""
        createTokenGated = false
        createTokenAddress = ""
        createMinBalance = "1"
    }
}

// MARK: - Models

struct CommunityGroup: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: String
    var memberCount: Int
    let isTokenGated: Bool
    let tokenRequirement: String?
    var isMember: Bool
    let hasActivity: Bool
}

extension CommunityGroup {
    static var sampleMine: [CommunityGroup] {
        [
            CommunityGroup(name: "DeFi Builders", description: "A community for DeFi protocol builders and researchers.", category: "DeFi", memberCount: 342, isTokenGated: true, tokenRequirement: "10 MTRX", isMember: true, hasActivity: true),
            CommunityGroup(name: "NFT Collectors", description: "Share and discuss NFT collections and trends.", category: "NFT", memberCount: 1205, isTokenGated: false, tokenRequirement: nil, isMember: true, hasActivity: true),
            CommunityGroup(name: "Governance Forum", description: "Discuss and coordinate governance proposals.", category: "Governance", memberCount: 89, isTokenGated: true, tokenRequirement: "100 MTRX", isMember: true, hasActivity: false),
        ]
    }

    static var sampleDiscover: [CommunityGroup] {
        [
            CommunityGroup(name: "Smart Contract Security", description: "Auditing tips and security best practices.", category: "Development", memberCount: 567, isTokenGated: false, tokenRequirement: nil, isMember: false, hasActivity: true),
            CommunityGroup(name: "Yield Farmers Anonymous", description: "Sharing yield strategies and alpha.", category: "DeFi", memberCount: 2340, isTokenGated: true, tokenRequirement: "1 ETH", isMember: false, hasActivity: true),
            CommunityGroup(name: "Web3 Gaming Guild", description: "Coordinate gaming strategies and tournaments.", category: "Gaming", memberCount: 890, isTokenGated: false, tokenRequirement: nil, isMember: false, hasActivity: false),
        ]
    }
}

struct GroupPost: Identifiable {
    let id = UUID()
    let author: String
    let content: String
    let timestamp: Date

    static var sampleData: [GroupPost] {
        [
            GroupPost(author: "alice.eth", content: "Just deployed a new yield aggregator on mainnet. Looking for beta testers.", timestamp: Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()),
            GroupPost(author: "bob.eth", content: "Has anyone looked into the new EIP for account abstraction? Thoughts?", timestamp: Calendar.current.date(byAdding: .hour, value: -3, to: Date()) ?? Date()),
            GroupPost(author: "carol.eth", content: "This group's discussions and proposals appear here.\nJoin the conversation to see member updates and active votes.", timestamp: Calendar.current.date(byAdding: .hour, value: -6, to: Date()) ?? Date()),
        ]
    }
}

// MARK: - View

struct GroupsView: View {
    @StateObject private var viewModel = GroupsViewModel()
    @State private var selectedTab: GroupTab = .myGroups

    private let accentColor = Color(red: 0.0, green: 0.675, blue: 0.694)

    enum GroupTab: String, CaseIterable {
        case myGroups = "My Groups"
        case discover = "Discover"
        case create = "Create"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                tabContent
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { viewModel.loadGroups() }
            .alert("Group Created", isPresented: $viewModel.createSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your group has been created successfully.")
            }
            .sheet(isPresented: $viewModel.showDetail) {
                if let group = viewModel.selectedGroup {
                    groupDetailSheet(group)
                }
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(GroupTab.allCases, id: \.self) { tab in
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
        case .myGroups:
            myGroupsSection
        case .discover:
            discoverSection
        case .create:
            createSection
        }
    }

    // MARK: - My Groups

    private var myGroupsSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading groups...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isEmpty {
                ContentUnavailableView("No Groups", systemImage: "person.3", description: Text("Join or create a group to get started."))
            } else {
                List {
                    ForEach(viewModel.myGroups) { group in
                        groupRow(group)
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.openGroup(group) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func groupRow(_ group: CommunityGroup) -> some View {
        HStack(spacing: Spacing.ms) {
            Circle()
                .fill(accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(group.name.prefix(2)).uppercased())
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(accentColor)
                )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(group.name)
                        .font(.mtrxHeadline)
                    if group.hasActivity {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Label("\(group.memberCount)", systemImage: "person.2")
                        .font(.mtrxCaption1)
                        .foregroundStyle(.secondary)

                    if group.isTokenGated {
                        Label(group.tokenRequirement ?? "Token Gated", systemImage: "lock.fill")
                            .font(.mtrxCaption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Text(group.category)
                .font(.mtrxCaption2)
                .foregroundStyle(accentColor)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(accentColor.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - Discover

    private var discoverSection: some View {
        Group {
            if viewModel.discoverGroups.isEmpty {
                ContentUnavailableView("Nothing to Discover", systemImage: "magnifyingglass", description: Text("No new groups available right now."))
            } else {
                List {
                    ForEach(viewModel.discoverGroups) { group in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            groupRow(group)

                            Text(group.description)
                                .font(.mtrxCaption1)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Button {
                                viewModel.toggleMembership(group)
                            } label: {
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                    Text("Join Group")
                                }
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
                                .background(accentColor)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Create

    private var createSection: some View {
        Form {
            Section("Group Info") {
                TextField("Group name", text: $viewModel.createName)
                TextEditor(text: $viewModel.createDescription)
                    .frame(minHeight: 80)
            }

            Section("Token Gate") {
                Toggle("Token Gated", isOn: $viewModel.createTokenGated)
                    .tint(accentColor)

                if viewModel.createTokenGated {
                    TextField("Token contract address", text: $viewModel.createTokenAddress)
                        .font(.mtrxMono)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack {
                        Text("Min Balance")
                        Spacer()
                        TextField("1", text: $viewModel.createMinBalance)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
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
                    viewModel.createGroup()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isCreating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle")
                            Text("Create Group")
                                .font(.mtrxHeadline)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                }
                .disabled(viewModel.isCreating)
                .listRowInsets(EdgeInsets())
                .padding(Spacing.contentPadding)
            }
        }
    }

    // MARK: - Group Detail Sheet

    private func groupDetailSheet(_ group: CommunityGroup) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    VStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(accentColor.opacity(0.2))
                            .frame(width: 72, height: 72)
                            .overlay(
                                Text(String(group.name.prefix(2)).uppercased())
                                    .font(.mtrxTitle3)
                                    .foregroundStyle(accentColor)
                            )

                        Text(group.name)
                            .font(.mtrxTitle2)

                        Text(group.description)
                            .font(.mtrxSubheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: Spacing.lg) {
                            Label("\(group.memberCount) members", systemImage: "person.2.fill")
                            if group.isTokenGated {
                                Label(group.tokenRequirement ?? "", systemImage: "lock.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.mtrxCaption1)
                        .foregroundStyle(.secondary)

                        Button {
                            viewModel.toggleMembership(group)
                            viewModel.showDetail = false
                        } label: {
                            Text(group.isMember ? "Leave Group" : "Join Group")
                                .font(.mtrxHeadline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.buttonVertical)
                                .background(group.isMember ? Color.red : accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        }
                    }
                    .mtrxCardStyle()

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Feed")
                            .font(.mtrxTitle3)

                        HStack {
                            TextField("Write a post...", text: $viewModel.newPostText)
                                .font(.mtrxBody)
                                .padding(.horizontal, Spacing.textFieldPadding)
                                .padding(.vertical, Spacing.sm)
                                .background(Color(.systemGray6))
                                .clipShape(Capsule())

                            Button {
                                viewModel.postToGroup()
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .foregroundStyle(viewModel.newPostText.isEmpty ? .gray : accentColor)
                            }
                            .disabled(viewModel.newPostText.isEmpty || viewModel.isPosting)
                        }

                        ForEach(viewModel.groupFeed) { post in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack {
                                    Text(post.author)
                                        .font(.mtrxCaptionBold)
                                    Spacer()
                                    Text(post.timestamp, style: .relative)
                                        .font(.mtrxCaption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(post.content)
                                    .font(.mtrxSubheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(Spacing.sm)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        }
                    }
                }
                .padding(Spacing.contentPadding)
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.showDetail = false }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    GroupsView()
}
