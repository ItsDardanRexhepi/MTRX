import Foundation

// MARK: - Models

struct SocialProfile: Codable, Identifiable {
    var id: String { address }
    let address: String
    let ens: String?
    let displayName: String?
    let bio: String?
    let followerCount: Int
    let followingCount: Int
    let isFollowing: Bool
}

struct SocialActivity: Codable, Identifiable {
    var id: String { activityId }
    let activityId: String
    let actor: String
    let type: String
    let description: String
    let timestamp: Date
    let txHash: String?
}

// MARK: - Service

@MainActor
final class SocialGraphService {

    static let shared = SocialGraphService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getFollowing(address: String) async throws -> [SocialProfile] {
        try await api.get("/social/\(address)/following")
    }

    func getFollowers(address: String) async throws -> [SocialProfile] {
        try await api.get("/social/\(address)/followers")
    }

    func getActivityFeed(address: String) async throws -> [SocialActivity] {
        try await api.get("/social/\(address)/activity")
    }

    func follow(address: String) async throws -> TransactionResult {
        try await api.post("/social/follow", body: ["address": address])
    }

    func unfollow(address: String) async throws -> TransactionResult {
        try await api.post("/social/unfollow", body: ["address": address])
    }

    func getSuggestions(address: String) async throws -> [SocialProfile] {
        try await api.get("/social/\(address)/suggestions")
    }
}
