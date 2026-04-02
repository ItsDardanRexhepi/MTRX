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

    private let api = MTRXAPIClient.shared
    private var cancellables = Set<AnyCancellable>()

    var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    func loadConversations() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: [String: AnyCodableValue] = try await api.get(path: "/api/v1/messaging/conversations")
            conversations = parseConversations(response)
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }

    func loadMessages(for conversation: Conversation) async {
        selectedConversation = conversation
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: [String: AnyCodableValue] = try await api.get(
                path: "/api/v1/messaging/conversations/\(conversation.id)/messages"
            )
            messages = parseMessages(response)
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let convoId = selectedConversation?.id else { return }
        isSending = true
        defer { isSending = false }

        let pendingMessage = Message(
            id: UUID().uuidString,
            senderAddress: "self",
            senderDisplayName: "You",
            content: .text(text),
            timestamp: Date(),
            isFromCurrentUser: true,
            deliveryStatus: .sending
        )
        messages.append(pendingMessage)
        let pendingId = pendingMessage.id
        messageText = ""

        do {
            let _: [String: AnyCodableValue] = try await api.postRaw(
                path: "/api/v1/messaging/conversations/\(convoId)/messages",
                body: ["content": text, "content_type": "text"]
            )
            if let idx = messages.firstIndex(where: { $0.id == pendingId }) {
                messages[idx] = Message(
                    id: pendingMessage.id,
                    senderAddress: pendingMessage.senderAddress,
                    senderDisplayName: pendingMessage.senderDisplayName,
                    content: pendingMessage.content,
                    timestamp: pendingMessage.timestamp,
                    isFromCurrentUser: true,
                    deliveryStatus: .sent
                )
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == pendingId }) {
                messages[idx] = Message(
                    id: pendingMessage.id,
                    senderAddress: pendingMessage.senderAddress,
                    senderDisplayName: pendingMessage.senderDisplayName,
                    content: pendingMessage.content,
                    timestamp: pendingMessage.timestamp,
                    isFromCurrentUser: true,
                    deliveryStatus: .failed
                )
            }
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }

    func createConversation() async {
        guard !newRecipientAddress.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let _: [String: AnyCodableValue] = try await api.postRaw(
                path: "/api/v1/messaging/conversations",
                body: ["recipient": newRecipientAddress, "is_group": false]
            )
            showNewConversation = false
            newRecipientAddress = ""
            await loadConversations()
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
            let _: [String: AnyCodableValue] = try await api.postRaw(
                path: "/api/v1/messaging/conversations",
                body: [
                    "participants": groupParticipants.joined(separator: ","),
                    "is_group": "true",
                    "group_name": groupName,
                ]
            )
            showNewConversation = false
            groupParticipants = []
            groupName = ""
            isGroupChat = false
            await loadConversations()
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

    // MARK: - Parsing

    private func parseConversations(_ response: [String: AnyCodableValue]) -> [Conversation] {
        guard case .array(let items) = response["conversations"] ?? response["data"] ?? .null else {
            return []
        }
        return items.compactMap { item -> Conversation? in
            guard case .dictionary(let dict) = item else { return nil }
            let id = dict["id"]?.stringValue ?? UUID().uuidString
            let isGroup = dict["is_group"]?.boolValue ?? false
            let gName = dict["group_name"]?.stringValue
            let unread = dict["unread_count"]?.intValue ?? 0
            let encrypted = dict["is_encrypted"]?.boolValue ?? true

            var participants: [Conversation.Participant] = []
            if case .array(let pList) = dict["participants"] {
                participants = pList.compactMap { p -> Conversation.Participant? in
                    guard case .dictionary(let pd) = p else { return nil }
                    return Conversation.Participant(
                        id: pd["id"]?.stringValue ?? UUID().uuidString,
                        walletAddress: pd["wallet_address"]?.stringValue ?? "",
                        displayName: pd["display_name"]?.stringValue ?? pd["wallet_address"]?.stringValue ?? "",
                        isCurrentUser: pd["is_current_user"]?.boolValue ?? false,
                        ensName: pd["ens_name"]?.stringValue
                    )
                }
            }

            return Conversation(
                id: id,
                participants: participants,
                isGroup: isGroup,
                groupName: gName,
                lastMessage: nil,
                unreadCount: unread,
                createdAt: Date(),
                isEncrypted: encrypted
            )
        }
    }

    private func parseMessages(_ response: [String: AnyCodableValue]) -> [Message] {
        guard case .array(let items) = response["messages"] ?? response["data"] ?? .null else {
            return []
        }
        return items.compactMap { item -> Message? in
            guard case .dictionary(let dict) = item else { return nil }
            let id = dict["id"]?.stringValue ?? UUID().uuidString
            let sender = dict["sender_address"]?.stringValue ?? ""
            let senderName = dict["sender_display_name"]?.stringValue ?? sender
            let contentText = dict["content"]?.stringValue ?? ""
            let isFromSelf = dict["is_from_current_user"]?.boolValue ?? false
            let contentType = dict["content_type"]?.stringValue ?? "text"

            let content: Message.MessageContent
            switch contentType {
            case "transaction":
                content = .transaction(
                    txHash: dict["tx_hash"]?.stringValue ?? "",
                    amount: dict["amount"]?.stringValue ?? "0",
                    token: dict["token"]?.stringValue ?? "ETH"
                )
            case "proof_link":
                content = .proofLink(
                    url: URL(string: dict["url"]?.stringValue ?? "https://basescan.org") ?? URL(string: "https://basescan.org")!,
                    title: dict["title"]?.stringValue ?? "Proof"
                )
            case "governance_vote":
                content = .governanceVote(
                    proposalId: dict["proposal_id"]?.stringValue ?? "",
                    vote: dict["vote"]?.stringValue ?? ""
                )
            default:
                content = .text(contentText)
            }

            return Message(
                id: id,
                senderAddress: sender,
                senderDisplayName: senderName,
                content: content,
                timestamp: Date(),
                isFromCurrentUser: isFromSelf,
                deliveryStatus: .delivered
            )
        }
    }
}

// MARK: - Main View

struct MessagingView: View {
    @StateObject private var viewModel = MessagingViewModel()

    var body: some View {
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
                            Image(systemName: Symbols.back)
                            Text("Back")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(viewModel.selectedConversation?.displayName ?? "")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 4) {
                            Image(systemName: Symbols.lock)
                                .font(.caption2)
                            Text("End-to-End Encrypted")
                                .font(.caption2)
                        }
                        .foregroundStyle(.statusSuccess)
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showNewConversation = true
                    } label: {
                        Image(systemName: Symbols.post)
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

    // MARK: - Conversation List

    private var conversationListView: some View {
        Group {
            if viewModel.isLoading && viewModel.conversations.isEmpty {
                List {
                    ForEach(0..<5, id: \.self) { _ in
                        ConversationSkeletonRow()
                    }
                }
                .listStyle(.plain)
            } else if let error = viewModel.errorMessage, viewModel.conversations.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: Symbols.alertWarning)
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Could Not Load Messages")
                        .font(.title3.weight(.semibold))
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await viewModel.loadConversations() }
                    } label: {
                        Label("Retry", systemImage: Symbols.refresh)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if viewModel.filteredConversations.isEmpty {
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
        }
    }

    private var emptyConversationsView: some View {
        VStack(spacing: 16) {
            Image(systemName: Symbols.encrypted)
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

                        if viewModel.isLoading {
                            ProgressView("Loading messages...")
                                .padding()
                        }

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
            Image(systemName: Symbols.lock)
                .font(.caption2)
            Text("Messages are end-to-end encrypted via XMTP. Only participants can read them.")
                .font(.caption2)
        }
        .foregroundStyle(.statusSuccess)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.statusSuccess.opacity(0.08))
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
                .background(Color.backgroundSecondary)
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
        .background(Color.backgroundPrimary)
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
                        Image(systemName: Symbols.lock)
                            .foregroundStyle(.statusSuccess)
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
                    Image(systemName: Symbols.backers)
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
                        Image(systemName: Symbols.lock)
                            .font(.caption2)
                            .foregroundStyle(.statusSuccess)
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
                            Label("\(amount) \(token)", systemImage: Symbols.transaction)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .proofLink(_, let title):
                            Label(title, systemImage: Symbols.link)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .governanceVote(let proposalId, _):
                            Label("Vote on #\(proposalId)", systemImage: Symbols.dao)
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
                Label("Transaction", systemImage: Symbols.transaction)
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
                Label("Governance Vote", systemImage: Symbols.dao)
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
            Image(systemName: Symbols.clock)
                .font(.caption2)
        case .sent:
            Image(systemName: Symbols.complete)
                .font(.caption2)
        case .delivered:
            Image(systemName: Symbols.complete)
                .font(.caption2)
                .overlay(
                    Image(systemName: Symbols.complete)
                        .font(.caption2)
                        .offset(x: 4)
                )
        case .failed:
            Image(systemName: Symbols.failed)
                .font(.caption2)
                .foregroundStyle(.statusError)
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
    NavigationStack {
        MessagingView()
    }
}
