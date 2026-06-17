import Foundation

// MARK: - Models

struct SvcContentPost: Codable, Identifiable {
    var id: String { contentId }
    let contentId: String
    let title: String
    let body: String
    let author: String
    let attachmentCIDs: [String]
    let publishedAt: Date
    let contentHash: String
    let storageLayer: String
}

// MARK: - Service

@MainActor
final class ContentService {

    static let shared = ContentService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getFeed(addresses: [String]) async throws -> [SvcContentPost] {
        try await api.post(path: "/content/feed", body: ["addresses": addresses])
    }

    func publishContent(title: String, body: String, attachments: [Data]) async throws -> SvcContentPost {
        struct PublishBody: Codable {
            let title: String
            let body: String
            let attachments: [String]
        }
        let encoded = attachments.map { $0.base64EncodedString() }
        let payload = PublishBody(title: title, body: body, attachments: encoded)
        return try await api.post(path: "/content", body: payload)
    }

    func getContent(contentId: String) async throws -> SvcContentPost {
        try await api.get(path: "/content/\(contentId)")
    }

    func getUserContent(address: String) async throws -> [SvcContentPost] {
        try await api.get(path: "/content", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func tipAuthor(address: String, amount: String, token: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/content/tip", body: [
            "address": address,
            "amount": amount,
            "token": token
        ])
    }
}
