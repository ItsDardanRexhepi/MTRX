// MessagingView.swift
// MTRX -- End-to-end encrypted messaging
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - Models

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let text: String
    let isFromUser: Bool
    let timestamp: Date
    let senderName: String
    /// Incognito messages vanish when the user leaves incognito mode.
    var isEphemeral: Bool = false
}

struct ChatConversation: Identifiable, Hashable {
    let id: String
    let contactName: String
    let contactInitials: String
    let contactColor: Color
    let lastMessageText: String
    let timestamp: Date
    let unreadCount: Int
    /// A conversation just started from contacts — opens with an empty thread.
    var isNew: Bool = false
}

// MARK: - View Model

@MainActor
final class MessagingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var conversations: [ChatConversation]
    @Published var selectedConversation: ChatConversation?
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    /// True while the conversation list is the local sample (no live messaging backend).
    @Published var isDemo: Bool = true

    private static func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return (parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return name.prefix(2).uppercased()
    }

    private static func color(for name: String) -> Color {
        let palette: [Color] = [.accentPrimary, .statusInfo, .statusSuccess, .statusWarning, .purple]
        return palette[abs(name.hashValue) % palette.count]
    }

    /// Live conversations from MessagingService when configured; else the local sample.
    func loadConversations() async {
        guard PendingCredentials.isBackendConfigured, MtrxSession.walletAddress != nil else {
            isDemo = true
            return
        }
        if let live = try? await MessagingService.shared.getConversations() {
            conversations = live.map { c in
                let name = c.peerENS ?? c.peerAddress
                return ChatConversation(
                    id: c.conversationId, contactName: name,
                    contactInitials: Self.initials(for: name),
                    contactColor: Self.color(for: name),
                    lastMessageText: c.lastMessage ?? "",
                    timestamp: c.lastMessageAt ?? Date(),
                    unreadCount: c.unreadCount
                )
            }
            isDemo = false
        } else {
            isDemo = true
        }
    }

    /// Incognito chat mode — anything sent while on is ephemeral and
    /// purged the moment the user leaves the mode (or the chat).
    @Published var incognito = false {
        didSet {
            if !incognito && oldValue { purgeEphemeral() }
        }
    }

    func purgeEphemeral() {
        guard messages.contains(where: { $0.isEphemeral }) else { return }
        withAnimation(Motion.springDefault) {
            messages.removeAll { $0.isEphemeral }
        }
    }

    // MARK: - Init

    init() {
        let now = Date()
        self.conversations = [
            ChatConversation(
                id: "conv_1",
                contactName: "Elena Vasquez",
                contactInitials: "EV",
                contactColor: .accentPrimary,
                lastMessageText: "The contract deployment went through!",
                timestamp: now.addingTimeInterval(-120),
                unreadCount: 3
            ),
            ChatConversation(
                id: "conv_2",
                contactName: "Marcus Chen",
                contactInitials: "MC",
                contactColor: .statusInfo,
                lastMessageText: "Can you review the latest proposal?",
                timestamp: now.addingTimeInterval(-3600),
                unreadCount: 1
            ),
            ChatConversation(
                id: "conv_3",
                contactName: "Aisha Patel",
                contactInitials: "AP",
                contactColor: .statusSuccess,
                lastMessageText: "Thanks for the staking walkthrough",
                timestamp: now.addingTimeInterval(-7200),
                unreadCount: 0
            ),
            ChatConversation(
                id: "conv_4",
                contactName: "Jordan Blake",
                contactInitials: "JB",
                contactColor: .accentTertiary,
                lastMessageText: "Let me know when the DAO vote is live",
                timestamp: now.addingTimeInterval(-86400),
                unreadCount: 0
            ),
            ChatConversation(
                id: "conv_5",
                contactName: "Priya Sharma",
                contactInitials: "PS",
                contactColor: .trinityPrimary,
                lastMessageText: "I sent 2.5 ETH to the escrow",
                timestamp: now.addingTimeInterval(-172800),
                unreadCount: 2
            ),
        ]
    }

    // MARK: - Load Messages

    func loadMessages(for conversation: ChatConversation) async {
        selectedConversation = conversation

        // A conversation just started from contacts opens with a clean thread.
        if conversation.isNew {
            messages = []
            return
        }

        // Live thread from MessagingService when configured; else demo thread.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            if let live = try? await MessagingService.shared.getMessages(conversationId: conversation.id) {
                messages = live.map { m in
                    let fromUser = m.senderAddress.lowercased() == address.lowercased()
                    return ChatMessage(
                        id: m.messageId, text: m.content, isFromUser: fromUser,
                        timestamp: m.sentAt,
                        senderName: fromUser ? "You" : conversation.contactName
                    )
                }
                return
            }
        }

        let now = Date()
        messages = [
            ChatMessage(id: "m1", text: "Hey, did you see the new governance proposal?", isFromUser: false, timestamp: now.addingTimeInterval(-3600), senderName: conversation.contactName),
            ChatMessage(id: "m2", text: "Not yet, which one?", isFromUser: true, timestamp: now.addingTimeInterval(-3540), senderName: "You"),
            ChatMessage(id: "m3", text: "The treasury rebalancing one. Proposal #47.", isFromUser: false, timestamp: now.addingTimeInterval(-3480), senderName: conversation.contactName),
            ChatMessage(id: "m4", text: "Just pulled it up. The allocation looks solid.", isFromUser: true, timestamp: now.addingTimeInterval(-3000), senderName: "You"),
            ChatMessage(id: "m5", text: "Right? 40% to dev grants is exactly what we need.", isFromUser: false, timestamp: now.addingTimeInterval(-2940), senderName: conversation.contactName),
            ChatMessage(id: "m6", text: "I'm going to vote yes. Are you delegating or voting directly?", isFromUser: true, timestamp: now.addingTimeInterval(-2400), senderName: "You"),
            ChatMessage(id: "m7", text: "Voting directly this time. Too important to delegate.", isFromUser: false, timestamp: now.addingTimeInterval(-2340), senderName: conversation.contactName),
            ChatMessage(id: "m8", text: "Agreed. Also, the escrow contract just cleared audit.", isFromUser: true, timestamp: now.addingTimeInterval(-1800), senderName: "You"),
            ChatMessage(id: "m9", text: "That's huge! When does it go live?", isFromUser: false, timestamp: now.addingTimeInterval(-1740), senderName: conversation.contactName),
            ChatMessage(id: "m10", text: "Deploying to mainnet tomorrow morning.", isFromUser: true, timestamp: now.addingTimeInterval(-1200), senderName: "You"),
            ChatMessage(id: "m11", text: "The contract deployment went through!", isFromUser: false, timestamp: now.addingTimeInterval(-120), senderName: conversation.contactName),
        ]
    }

    // MARK: - Send Message

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newMessage = ChatMessage(
            id: UUID().uuidString,
            text: trimmed,
            isFromUser: true,
            timestamp: Date(),
            senderName: "You",
            isEphemeral: incognito
        )
        messages.append(newMessage)
        inputText = ""
        MtrxHaptics.impact(.light)
    }

    // MARK: - Start Conversation (from contacts)

    /// Begin (or reopen) an encrypted conversation with an imported contact.
    func startConversation(with contact: PhoneContact) -> ChatConversation {
        if let existing = conversations.first(where: { $0.contactName == contact.fullName }) {
            return existing
        }
        let conversation = ChatConversation(
            id: UUID().uuidString,
            contactName: contact.fullName,
            contactInitials: contact.initials,
            contactColor: contact.color,
            lastMessageText: "Say hi to start the conversation",
            timestamp: Date(),
            unreadCount: 0,
            isNew: true
        )
        conversations.insert(conversation, at: 0)
        MtrxHaptics.impact(.medium)
        return conversation
    }

    // MARK: - Delete Conversation

    func deleteConversation(_ conversation: ChatConversation) {
        conversations.removeAll { $0.id == conversation.id }
        MtrxHaptics.impact(.medium)
    }
}

// MARK: - Messaging View

struct MessagingView: View {

    @StateObject private var viewModel = MessagingViewModel()
    @State private var showNewMessage = false
    @State private var pendingConversation: ChatConversation?

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                if viewModel.conversations.isEmpty {
                    MtrxEmptyState(
                        icon: "envelope",
                        title: "No Messages",
                        message: "Start a conversation with someone in your network to begin messaging securely.",
                        actionLabel: "New Message"
                    ) {
                        showNewMessage = true
                    }
                } else {
                    conversationList
                }
            }
            .navigationTitle("Messages")
            .task { await viewModel.loadConversations() }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewMessage = true
                        MtrxHaptics.selection()
                    } label: {
                        Image(systemName: Symbols.add)
                            .accessibilityLabel("New message")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
            }
            .navigationDestination(item: $pendingConversation) { conversation in
                ConversationDetailView(viewModel: viewModel, conversation: conversation)
            }
            .sheet(isPresented: $showNewMessage) {
                newMessageSheet
            }
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.conversations) { conversation in
                    NavigationLink {
                        ConversationDetailView(viewModel: viewModel, conversation: conversation)
                    } label: {
                        conversationRow(conversation)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteConversation(conversation)
                        } label: {
                            Label("Delete", systemImage: Symbols.delete)
                        }
                    }

                    MtrxDivider()
                        .padding(.leading, 76)
                }
            }
            .padding(.top, Spacing.xs)
        }
    }

    // MARK: - Conversation Row

    private func conversationRow(_ conversation: ChatConversation) -> some View {
        HStack(spacing: Spacing.avatarContentGap) {
            MtrxAvatar(
                text: conversation.contactInitials,
                color: conversation.contactColor,
                size: 44
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.contactName)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)

                Text(conversation.lastMessageText)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(formattedTimestamp(conversation.timestamp))
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)

                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color.accentPrimary)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.listRowVertical)
        .contentShape(Rectangle())
    }

    // MARK: - New Message Sheet

    private var newMessageSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MtrxSheetHeader(title: "New Message", subtitle: "Connect with people you know") {
                    showNewMessage = false
                }
                ContactsImportView { contact in
                    let conversation = viewModel.startConversation(with: contact)
                    showNewMessage = false
                    // Let the sheet finish dismissing before pushing the chat.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        pendingConversation = conversation
                    }
                }
            }
            .background(Color.backgroundPrimary)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Timestamp Formatting

    private func formattedTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Conversation Detail View

struct ConversationDetailView: View {

    @ObservedObject var viewModel: MessagingViewModel
    let conversation: ChatConversation
    @FocusState private var isInputFocused: Bool
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            messageList
            MtrxDivider()
            inputBar
        }
        .background(Color.black)
        .navigationTitle(conversation.contactName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: Spacing.ms) {
                    // Incognito switch — chat goes ephemeral while on.
                    Button {
                        MtrxHaptics.impact(.medium)
                        withAnimation(Motion.springSnappy) {
                            viewModel.incognito.toggle()
                        }
                    } label: {
                        Image(systemName: viewModel.incognito
                              ? "theatermasks.fill" : "theatermasks")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(viewModel.incognito ? Color.purple : Color.labelSecondary)
                            .accessibilityLabel("Toggle incognito mode")
                    }

                    Image(systemName: Symbols.messageEncrypted)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if viewModel.incognito {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Incognito — messages sent now disappear when you leave this mode")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.purple.opacity(0.85))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await viewModel.loadMessages(for: conversation)
            appeared = true
        }
        .onDisappear {
            // Leaving the chat ends the incognito session.
            viewModel.purgeEphemeral()
            viewModel.incognito = false
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    encryptionBanner
                        .padding(.top, Spacing.md)

                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        let showTimeLabel = shouldShowTimeLabel(at: index)

                        if showTimeLabel {
                            timeLabel(for: message.timestamp)
                        }

                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastID = viewModel.messages.last?.id {
                    withAnimation(Motion.springSnappy) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let lastID = viewModel.messages.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Encryption Banner

    private var encryptionBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: Symbols.encrypted)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentPrimary)

            Text("Messages are end-to-end encrypted")
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelTertiary)
        }
        .padding(.horizontal, Spacing.ms)
        .padding(.vertical, Spacing.sm)
        .background(Color.surfaceOverlay.opacity(0.5))
        .clipShape(Capsule())
    }

    // MARK: - Time Label

    private func shouldShowTimeLabel(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = viewModel.messages[index].timestamp
        let previous = viewModel.messages[index - 1].timestamp
        return current.timeIntervalSince(previous) > 600
    }

    private func timeLabel(for date: Date) -> some View {
        Text(formattedTimeLabel(date))
            .font(.mtrxCaption2)
            .foregroundStyle(Color.labelTertiary)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
    }

    private func formattedTimeLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "h:mm a"
            return "Yesterday \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isFromUser { Spacer(minLength: Spacing.xxl) }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.mtrxBody)
                    .foregroundStyle(message.isFromUser ? .white : Color.labelPrimary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        message.isEphemeral
                            ? AnyShapeStyle(Color.purple.opacity(0.75))
                            : AnyShapeStyle(message.isFromUser ? Color.accentPrimary : Color.surfaceCard)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                message.isEphemeral ? Color.purple : Color.clear,
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    )

                if message.isEphemeral {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                        Text("Disappears")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.purple.opacity(0.9))
                }
            }

            if !message.isFromUser { Spacer(minLength: Spacing.xxl) }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Message...", text: $viewModel.inputText, axis: .vertical)
                .font(.mtrxBody)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, Spacing.ms)
                .padding(.vertical, Spacing.sm)
                .background(Color.surfaceOverlay)
                .clipShape(Capsule())

            Button {
                viewModel.sendMessage()
            } label: {
                Image(systemName: Symbols.send)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.labelTertiary
                            : Color.accentPrimary
                    )
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            // Bleeds past the bottom so the keyboard's rounded corners
            // never expose dark notches at the seam.
            Rectangle()
                .fill(Color.backgroundPrimary)
                .padding(.bottom, -40)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Preview

#Preview("Messages") {
    MessagingView()
        .preferredColorScheme(.dark)
}

#Preview("Conversation") {
    let vm = MessagingViewModel()
    NavigationStack {
        ConversationDetailView(
            viewModel: vm,
            conversation: vm.conversations[0]
        )
    }
    .preferredColorScheme(.dark)
}
