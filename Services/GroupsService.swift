import Foundation

// MARK: - Models

struct CommunityGroup: Codable, Identifiable {
    var id: String { groupId }
    let groupId: String
    let name: String
    let description: String
    let memberCount: Int
    let tokenGate: TokenGate?
    let category: String
    let isPrivate: Bool
}

struct TokenGate: Codable {
    let tokenAddress: String
    let minimumBalance: Double
    let tokenName: String
    let tokenSymbol: String
}

struct GroupPost: Codable, Identifiable {
    var id: String { postId }
    let postId: String
    let groupId: String
    let author: String
    let content: String
    let attachmentURL: String?
    let postedAt: Date
}

struct GroupParams: Codable {
    let name: String
    let description: String
    let tokenGateAddress: String?
    let minimumTokenBalance: Double?
    let category: String
    let isPrivate: Bool
}

// MARK: - Service

@MainActor
final class GroupsService {

    static let shared = GroupsService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getUserGroups(address: String) async throws -> [CommunityGroup] {
        try await api.get(path: "/groups", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func discoverGroups(category: String?) async throws -> [CommunityGroup] {
        var queryItems: [URLQueryItem] = []
        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        return try await api.get(path: "/groups/discover", queryItems: queryItems.isEmpty ? nil : queryItems)
    }

    func getGroupFeed(groupId: String) async throws -> [GroupPost] {
        try await api.get(path: "/groups/\(groupId)/feed")
    }

    func joinGroup(groupId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/groups/\(groupId)/join", body: nil as String?)
    }

    func leaveGroup(groupId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/groups/\(groupId)/leave", body: nil as String?)
    }

    func createGroup(params: GroupParams) async throws -> CommunityGroup {
        try await api.post(path: "/groups", body: params)
    }

    func postToGroup(groupId: String, content: String, attachmentData: Data?) async throws -> GroupPost {
        struct PostBody: Codable {
            let content: String
            let attachmentBase64: String?
        }
        let body = PostBody(
            content: content,
            attachmentBase64: attachmentData?.base64EncodedString()
        )
        return try await api.post(path: "/groups/\(groupId)/posts", body: body)
    }
}
