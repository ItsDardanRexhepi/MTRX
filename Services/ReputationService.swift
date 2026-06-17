import Foundation

// MARK: - Models

struct ReputationProfile: Codable, Identifiable {
    var id: String { address }
    let address: String
    let ens: String?
    let score: Int
    let tier: String
    let breakdown: ReputationBreakdown
    let rank: Int
}

struct ReputationBreakdown: Codable {
    let transactionScore: Int
    let governanceScore: Int
    let attestationScore: Int
    let longevityScore: Int
}

struct ReputationAction: Codable, Identifiable {
    let id: UUID
    let action: String
    let pointsGain: Int
    let difficulty: String
    let category: String
}

// MARK: - Service

@MainActor
final class ReputationService {

    static let shared = ReputationService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getReputation(address: String) async throws -> ReputationProfile {
        try await api.get(path: "/reputation/\(address)")
    }

    func getLeaderboard(limit: Int) async throws -> [ReputationProfile] {
        try await api.get(path: "/reputation/leaderboard", queryItems: [
            URLQueryItem(name: "limit", value: String(limit))
        ])
    }

    func getImprovementActions(address: String) async throws -> [ReputationAction] {
        try await api.get(path: "/reputation/\(address)/actions")
    }
}
