// MessagingView.swift
// MTRX - XMTP end-to-end encrypted wallet-to-wallet messaging
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI
import Combine

// MARK: - Models

struct Conversation: Identifiable, Equatable {
    let id: String
    let participants: [Participant]
    let isGroup: Bool
    let groupName: String?
    let lastMessage: Message?
    let unreadCount: Int
    let createdAt: Date
    let isEncrypted: Bool

    var displayName: String {
        if let name = groupName { return name }
        let others = participants.filter { !$0.isCurrentUser }
        if others.count == 1 {
            return others[0].displayName
        }
        return others.prefix(3).map(\.displayName).joined(separator: ", ")
    }

    struct Participant: Identifiable, Equatable {
        let id: String
        let walletAddress: String
        let displayName: String
        let isCurrentUser: Bool
        let ensName: String?
    }
}

struct Message: Identifiable, Equatable {
    let id: String
    let senderAddress: String
    let senderDisplayName: String
    let content: MessageContent
    let timestamp: Date
    let isFromCurrentUser: Bool
    let deliveryStatus: DeliveryStatus

    enum MessageContent: Equatable {
        case text(String)
        case transaction(txHash: String, amount: String, token: String)
        case proofLink(url: URL, title: String)
        case governanceVote(proposalId: String, vote: String)
    }

    enum DeliveryStatus: Equatable {
        case sending
        case sent
        case delivered
        case failed
    }
}

// MARK: - ViewModel

@MainActor
final class MessagingViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var messageText = ""
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var showNewConversation = false
    @Published var newRecipientAddress = ""
    @Published var isGroupChat = false
    @Published var groupParticipants: [String] = []
    @Published var groupName = ""
    @Published var searchText = ""

    static let maxGroupSize = 10

    private var cancellables = Set<AnyCancellable>()

    var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Production: fetch from XMTP client
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }

    func loadMessages(for conversation: Conversation) async {
        selectedConversation = conversation
        isLoading = true
        defer { isLoading = false }
        do {
            // Production: fetch decrypted messages from XMTP
            try await Task.sleep(nanoseconds: 100_000_000)
            messages = []
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        do {
            // Production: encrypt and send via XMTP protocol
            try await Task.sleep(nanoseconds: 300_000_000)
            messageText = ""
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }

    func createConversation() async {
        guard !newRecipientAddress.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Production: create XMTP conversation
            try await Task.sleep(nanoseconds: 300_000_000)
            showNewConversation = false
            newRecipientAddress = ""
            groupParticipants = []
            groupName = ""
        } catch {
            errorMessage = "Failed to create conversation: \(error.localizedDescription)"
        }
    }

    func createGroupConversation() async {
        guard groupParticipants.count >= 2,
              groupParticipants.count <= Self.maxGroupSize else {
            errorMessage = "Group chat requires 2-\(Self.maxGroupSize) participants"
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            // Production: create XMTP group conversation
            try await Task.sleep(nanoseconds: 500_000_000)
            showNewConversation = false
            groupParticipants = []
            groupName = ""
            isGroupChat = false
        } catch {
            errorMessage = "Failed to create group: \(error.localizedDescription)"
        }
    }

    func addGroupParticipant() {
        let address = newRecipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty,
              !groupParticipants.contains(address),
              groupParticipants.count < Self.maxGroupSize else { return }
        groupParticipants.append(address)
        newRecipientAddress = ""
    }

    func removeGroupParticipant(_ address: String) {
        groupParticipants.removeAll { $0 == address }
    }
}

// MARK: - Main View

struct MessagingView: View {
    @StateObject private var viewModel = MessagingViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.selectedConversation != nil {
                    chatView
                } else {
                    conversationListView
                }
            }
            .navigationTitle(viewModel.selectedConversation?.displayName ?? "Messages")
            .navigationBarTitleDisplayMode(viewModel.selectedConversation != nil ? .inline : .large)
            .toolbar {
                if viewModel.selectedConversation != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            viewModel.selectedConversation = nil
                            viewModel.messages = []
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(viewModel.selectedConversation?.displayName ?? "")
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                Text("End-to-End Encrypted")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.green)
                        }
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.showNewConversation = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("New conversation")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showNewConversation) {
                newConversationSheet
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                await viewModel.loadConversations()
            }
        }
    }

    // MARK: - Conversation List

    private var conversationListView: some View {
        List {
            if viewModel.isLoading && viewModel.conversations.isEmpty {
                ForEach(0..<5, id: \.self) { _ in
                    ConversationSkeletonRow()
                }
            } else if viewModel.filteredConversations.isEmpty {
                emptyConversationsView
            } else {
                ForEach(viewModel.filteredConversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await viewModel.loadMessages(for: conversation) }
                        }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchText, prompt: "Search conversations")
        .refreshable {
            await viewModel.loadConversations()
        }
    }

    private var emptyConversationsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Conversations")
                .font(.title3.weight(.semibold))
            Text("Start an end-to-end encrypted conversation with any wallet address using XMTP.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New Message") {
                viewModel.showNewConversation = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        encryptionBanner

                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
            messageInputBar
        }
    }

    private var encryptionBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("Messages are end-to-end encrypted via XMTP. Only participants can read them.")
                .font(.caption2)
        }
        .foregroundStyle(.green)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.08))
        .cornerRadius(12)
        .padding(.bottom, 8)
    }

    private var messageInputBar: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $viewModel.messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .accessibilityLabel("Message input")

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Group {
                    if viewModel.isSending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(width: 34, height: 34)
                .background(viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(.systemGray4) : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Circle())
            }
            .disabled(viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - New Conversation Sheet

    private var newConversationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Group Chat", isOn: $viewModel.isGroupChat)
                }

                if viewModel.isGroupChat {
                    Section("Group Details") {
                        TextField("Group Name", text: $viewModel.groupName)

                        HStack {
                            TextField("Wallet address or ENS", text: $viewModel.newRecipientAddress)
                                .textInputAutocapitalization(.never)
                            Button("Add") {
                                viewModel.addGroupParticipant()
                            }
                            .disabled(viewModel.newRecipientAddress.isEmpty)
                        }

                        ForEach(viewModel.groupParticipants, id: \.self) { address in
                            HStack {
                                Text(truncatedAddress(address))
                                    .font(.caption.monospaced())
                                Spacer()
                                Button {
                                    viewModel.removeGroupParticipant(address)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("\(viewModel.groupParticipants.count)/\(MessagingViewModel.maxGroupSize) participants")
                    }
                } else {
                    Section("Recipient") {
                        TextField("Wallet address or ENS name", text: $viewModel.newRecipientAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.asciiCapable)
                    }
                }

                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.green)
                        Text("All messages are end-to-end encrypted via XMTP protocol.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(viewModel.isGroupChat ? "New Group" : "New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.showNewConversation = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if viewModel.isGroupChat {
                                await viewModel.createGroupConversation()
                            } else {
                                await viewModel.createConversation()
                            }
                        }
                    }
                    .disabled(viewModel.isGroupChat
                              ? viewModel.groupParticipants.count < 2
                              : viewModel.newRecipientAddress.isEmpty)
                }
            }
        }
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 48, height: 48)
                if conversation.isGroup {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(conversation.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if conversation.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    if let lastMsg = conversation.lastMessage {
                        Text(lastMsg.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if let lastMsg = conversation.lastMessage {
                        switch lastMsg.content {
                        case .text(let text):
                            Text(text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        case .transaction(_, let amount, let token):
                            Label("\(amount) \(token)", systemImage: "arrow.left.arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .proofLink(_, let title):
                            Label(title, systemImage: "link")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .governanceVote(let proposalId, _):
                            Label("Vote on #\(proposalId)", systemImage: "building.columns")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.displayName), \(conversation.unreadCount) unread messages")
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isFromCurrentUser { Spacer(minLength: 60) }

            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if !message.isFromCurrentUser {
                    Text(message.senderDisplayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                messageContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isFromCurrentUser ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(message.isFromCurrentUser ? .white : .primary)
                    .cornerRadius(18, corners: message.isFromCurrentUser
                                  ? [.topLeading, .topTrailing, .bottomLeading]
                                  : [.topLeading, .topTrailing, .bottomTrailing])

                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                    deliveryIcon
                }
                .foregroundStyle(.secondary)
            }

            if !message.isFromCurrentUser { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var messageContent: some View {
        switch message.content {
        case .text(let text):
            Text(text)
                .font(.body)

        case .transaction(let txHash, let amount, let token):
            VStack(alignment: .leading, spacing: 6) {
                Label("Transaction", systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
                Text("\(amount) \(token)")
                    .font(.title3.weight(.bold))
                Text(String(txHash.prefix(16)) + "...")
                    .font(.caption2.monospaced())
                    .opacity(0.7)
            }

        case .proofLink(let url, let title):
            VStack(alignment: .leading, spacing: 4) {
                Label("Proof Link", systemImage: "checkmark.shield")
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.subheadline)
                Text(url.absoluteString)
                    .font(.caption2)
                    .opacity(0.7)
            }

        case .governanceVote(let proposalId, let vote):
            VStack(alignment: .leading, spacing: 4) {
                Label("Governance Vote", systemImage: "building.columns")
                    .font(.caption.weight(.semibold))
                Text("Proposal #\(proposalId)")
                    .font(.subheadline)
                Text("Voted: \(vote)")
                    .font(.caption)
                    .opacity(0.7)
            }
        }
    }

    @ViewBuilder
    private var deliveryIcon: some View {
        switch message.deliveryStatus {
        case .sending:
            Image(systemName: "clock")
                .font(.caption2)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
        case .delivered:
            Image(systemName: "checkmark")
                .font(.caption2)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .offset(x: 4)
                )
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Supporting

struct ConversationSkeletonRow: View {
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 12) {
            Circle().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 14)
                RoundedRectangle(cornerRadius: 4).frame(width: 200, height: 10)
            }
        }
        .foregroundStyle(Color(.systemGray5))
        .opacity(shimmer ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview("Messaging") {
    MessagingView()
}
