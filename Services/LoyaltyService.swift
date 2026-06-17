import Foundation

// MARK: - Models

struct LoyaltyProgram: Codable, Identifiable {
    var id: String { programId }
    let programId: String
    let name: String
    let points: Int
    let tier: Int
    let tierName: String
}

struct EarnAction: Codable, Identifiable {
    let id: UUID
    let action: String
    let points: Int
    let description: String
}

struct RedemptionOption: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let pointsCost: Int
    let type: String
}

struct SvcCashbackReward: Codable, Identifiable {
    var id: String { rewardId }
    let rewardId: String
    let source: String
    let amount: Double
    let token: String
    let earnedAt: Date
    let claimed: Bool
}

// MARK: - Service

@MainActor
final class LoyaltyService {

    static let shared = LoyaltyService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getLoyaltyPoints(address: String) async throws -> [LoyaltyProgram] {
        try await api.get(path: "/loyalty/programs", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getEarnActions(programId: String) async throws -> [EarnAction] {
        try await api.get(path: "/loyalty/programs/\(programId)/earn")
    }

    func getRedemptionOptions(programId: String) async throws -> [RedemptionOption] {
        try await api.get(path: "/loyalty/programs/\(programId)/redeem")
    }

    func redeemPoints(programId: String, optionId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/loyalty/programs/\(programId)/redeem", body: ["optionId": optionId])
    }

    func getCashback(address: String) async throws -> [SvcCashbackReward] {
        try await api.get(path: "/loyalty/cashback", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func claimCashback(rewardId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/loyalty/cashback/\(rewardId)/claim", body: nil as String?)
    }
}
