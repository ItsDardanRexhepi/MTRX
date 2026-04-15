import Foundation

// MARK: - Models

struct XMTPConversation: Codable, Identifiable {
    var id: String { conversationId }
    let conversationId: String
    let peerAddress: String
    let peerENS: String?
    let lastMessage: String?
    let lastMessageAt: Date?
    let unreadCount: Int
}

struct XMTPMessage: Codable, Identifiable {
    var id: String { messageId }
    let messageId: String
    let conversationId: String
    let senderAddress: String
    let content: String
    let sentAt: Date
    let status: String
}

// MARK: - Service

@MainActor
final class MessagingService {

    static let shared = MessagingService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getConversations() async throws -> [XMTPConversation] {
        try await api.get("/messaging/conversations")
    }

    func getMessages(conversationId: String) async throws -> [XMTPMessage] {
        try await api.get("/messaging/conversations/\(conversationId)/messages")
    }

    func sendMessage(conversationId: String, content: String) async throws -> XMTPMessage {
        struct SendBody: Codable {
            let content: String
        }
        let body = SendBody(content: content)
        return try await api.post("/messaging/conversations/\(conversationId)/messages", body: body)
    }

    func startConversation(with address: String) async throws -> XMTPConversation {
        struct StartBody: Codable {
            let peerAddress: String
        }
        let body = StartBody(peerAddress: address)
        return try await api.post("/messaging/conversations", body: body)
    }
}
