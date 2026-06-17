import Foundation

// MARK: - Models

struct SvcCampaign: Codable, Identifiable {
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
    let tiers: [SvcRewardTier]
}

struct SvcRewardTier: Codable, Identifiable {
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
    let tiers: [SvcRewardTier]
}

// MARK: - Service

@MainActor
final class FundraisingService {

    static let shared = FundraisingService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getCampaigns() async throws -> [SvcCampaign] {
        try await api.get(path: "/fundraising/campaigns", queryItems: nil)
    }

    func createCampaign(params: CampaignParams) async throws -> SvcCampaign {
        try await api.post(path: "/fundraising/campaigns", body: params)
    }

    func backCampaign(campaignId: String, amount: String, tierIndex: Int) async throws -> SvcTransactionResult {
        try await api.post(path: "/fundraising/campaigns/\(campaignId)/back", body: [
            "amount": amount,
            "tierIndex": String(tierIndex)
        ])
    }

    func withdrawFunds(campaignId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/fundraising/campaigns/\(campaignId)/withdraw", body: nil as String?)
    }

    func claimRefund(campaignId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/fundraising/campaigns/\(campaignId)/refund", body: nil as String?)
    }
}
