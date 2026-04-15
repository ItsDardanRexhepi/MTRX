import Foundation

// MARK: - Models

struct Campaign: Codable, Identifiable {
    var id: String { campaignId }
    let campaignId: String
    let title: String
    let description: String
    let goal: Double
    let raised: Double
    let backers: Int
    let deadline: Date
    let status: String
    let creator: String
    let tiers: [RewardTier]
}

struct RewardTier: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let minimumContribution: Double
    let maxBackers: Int?
    let currentBackers: Int
}

struct CampaignParams: Codable {
    let title: String
    let description: String
    let goal: Double
    let token: String
    let deadline: Date
    let tiers: [RewardTier]
}

// MARK: - Service

@MainActor
final class FundraisingService {

    static let shared = FundraisingService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getCampaigns() async throws -> [Campaign] {
        try await api.get("/fundraising/campaigns", queryItems: nil)
    }

    func createCampaign(params: CampaignParams) async throws -> Campaign {
        try await api.post("/fundraising/campaigns", body: params)
    }

    func backCampaign(campaignId: String, amount: String, tierIndex: Int) async throws -> TransactionResult {
        try await api.post("/fundraising/campaigns/\(campaignId)/back", body: [
            "amount": amount,
            "tierIndex": String(tierIndex)
        ])
    }

    func withdrawFunds(campaignId: String) async throws -> TransactionResult {
        try await api.post("/fundraising/campaigns/\(campaignId)/withdraw", body: nil as String?)
    }

    func claimRefund(campaignId: String) async throws -> TransactionResult {
        try await api.post("/fundraising/campaigns/\(campaignId)/refund", body: nil as String?)
    }
}
