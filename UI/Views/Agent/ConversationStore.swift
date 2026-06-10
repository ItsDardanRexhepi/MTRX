// ConversationStore.swift
// MTRX
//
// Saved chats. Every conversation belongs to exactly one agent —
// Trinity, Morpheus, or Neo — and persists across launches as JSON in
// Application Support. The active conversation updates continuously as
// messages arrive; old chats can be reopened from the history sheet.

import Combine
import Foundation
import SwiftUI

// MARK: - Chat Conversation

struct AgentChatRecord: Identifiable, Codable {
    let id: UUID
    var agentRaw: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [AgentMessage]

    var agent: AgentAccessControl.ActiveAgent {
        AgentAccessControl.ActiveAgent(rawValue: agentRaw) ?? .trinity
    }

    var agentDisplayName: String {
        switch agent {
        case .trinity: return "Trinity"
        case .morpheus: return "Morpheus"
        case .neo: return "Neo"
        }
    }
}

// MARK: - Conversation Store

@MainActor
final class ConversationStore: ObservableObject {

    static let shared = ConversationStore()

    /// Newest-first.
    @Published private(set) var conversations: [AgentChatRecord] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTRX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Conversations.json")
    }()

    private init() {
        load()
    }

    // MARK: API

    func create(agent: AgentAccessControl.ActiveAgent) -> AgentChatRecord {
        let convo = AgentChatRecord(
            id: UUID(),
            agentRaw: agent.rawValue,
            title: "New chat",
            createdAt: Date(),
            updatedAt: Date(),
            messages: []
        )
        conversations.insert(convo, at: 0)
        persist()
        return convo
    }

    /// Write the latest messages into a conversation and float it to the
    /// top. The first user message becomes the saved title.
    func update(id: UUID, agentRaw: String, messages: [AgentMessage]) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        var convo = conversations[idx]
        convo.messages = messages
        convo.agentRaw = agentRaw
        convo.updatedAt = Date()
        if convo.title == "New chat",
           let firstUser = messages.first(where: { $0.role == .user }) {
            convo.title = String(firstUser.text.prefix(48))
        }
        conversations.remove(at: idx)
        conversations.insert(convo, at: 0)
        persist()
    }

    func conversation(id: UUID) -> AgentChatRecord? {
        conversations.first { $0.id == id }
    }

    func mostRecent(agent: AgentAccessControl.ActiveAgent) -> AgentChatRecord? {
        conversations.first { $0.agentRaw == agent.rawValue }
    }

    func delete(id: UUID) {
        conversations.removeAll { $0.id == id }
        persist()
    }

    // MARK: Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AgentChatRecord].self, from: data)
        else { return }
        conversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var saveTask: Task<Void, Never>?

    /// Debounced atomic write — chat turns arrive in bursts.
    private func persist() {
        saveTask?.cancel()
        let snapshot = conversations
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}

// MARK: - Chat History Sheet

/// Lists saved chats and starts new ones, one tap per agent.
struct ChatHistorySheet: View {
    @ObservedObject private var store = ConversationStore.shared
    @Environment(\.dismiss) private var dismiss

    let currentID: UUID?
    let allowNeo: Bool
    let onSelect: (AgentChatRecord) -> Void
    let onNew: (AgentAccessControl.ActiveAgent) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Start a new chat") {
                    newChatRow("Trinity", color: .trinityPrimary, agent: .trinity)
                    newChatRow("Morpheus", color: .statusError, agent: .morpheus)
                    if allowNeo {
                        newChatRow("Neo", color: .statusSuccess, agent: .neo)
                    }
                }

                if !store.conversations.isEmpty {
                    Section("Saved chats") {
                        ForEach(store.conversations) { convo in
                            Button {
                                MtrxHaptics.impact(.light)
                                onSelect(convo)
                                dismiss()
                            } label: {
                                conversationRow(convo)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for offset in offsets {
                                store.delete(id: store.conversations[offset].id)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func newChatRow(_ name: String, color: Color, agent: AgentAccessControl.ActiveAgent) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            onNew(agent)
            dismiss()
        } label: {
            HStack(spacing: Spacing.ms) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text("New chat with \(name)")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func conversationRow(_ convo: AgentChatRecord) -> some View {
        HStack(spacing: Spacing.ms) {
            Circle()
                .fill(agentColor(convo.agent))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(convo.title)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                Text("\(convo.agentDisplayName) · \(convo.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            if convo.id == currentID {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentPrimary)
            }
        }
        .contentShape(Rectangle())
    }

    private func agentColor(_ agent: AgentAccessControl.ActiveAgent) -> Color {
        switch agent {
        case .trinity: return .trinityPrimary
        case .morpheus: return .statusError
        case .neo: return .statusSuccess
        }
    }
}
