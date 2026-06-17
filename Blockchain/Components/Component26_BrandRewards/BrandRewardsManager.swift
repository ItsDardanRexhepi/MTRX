// BrandRewardsManager.swift
// MTRX Blockchain - Components - Brand Rewards
//
// Brand partnership rewards: campaigns, NFT drops, cross-brand interoperability

import Foundation
import Combine

// MARK: - Data Models

struct BrandCampaign: Identifiable, Codable {
    let id: String
    let brandName: String
    let brandAddress: String
    let title: String
    let description: String
    let startDate: Date
    let endDate: Date
    let rewardType: BrandRewardType
    let totalBudget: Double
    let rewardToken: String
    var claimedCount: Int
    let maxClaims: Int
    var status: BrandCampaignStatus
    let eligibilityCriteria: [EligibilityCriterion]
}

enum BrandRewardType: String, Codable {
    case tokenDrop, nftMint, discount, exclusiveAccess, cashback, experience
}

enum BrandCampaignStatus: String, Codable {
    case scheduled, active, paused, completed, exhausted
}

struct EligibilityCriterion: Codable {
    let type: EligibilityType
    let parameter: String
    let value: String
}

enum EligibilityType: String, Codable {
    case minTransactionCount, minHoldingAmount, loyaltyTier, nftHolder, daoMember
}

struct BrandRewardClaim: Identifiable, Codable {
    let id: String
    let campaignId: String
    let userAddress: String
    let rewardAmount: Double
    let rewardToken: String
    let claimedAt: Date
    let transactionHash: String?
}

struct BrandPartnership: Identifiable, Codable {
    let id: String
    let brand1Address: String
    let brand2Address: String
    let name: String
    let crossRewardMultiplier: Double
    let startDate: Date
    var isActive: Bool
}

enum BrandRewardsError: Error, LocalizedError {
    case campaignNotFound(String)
    case campaignNotActive
    case maxClaimsReached
    case notEligible(String)
    case alreadyClaimed
    case budgetExhausted
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .campaignNotFound(let id): return "Campaign not found: \(id)"
        case .campaignNotActive: return "Campaign is not active."
        case .maxClaimsReached: return "Maximum claims reached."
        case .notEligible(let r): return "Not eligible: \(r)"
        case .alreadyClaimed: return "Reward already claimed."
        case .budgetExhausted: return "Campaign budget exhausted."
        case .notConfigured: return "Brand-rewards contract not configured (PendingCredentials.Components.brandRewards)."
        }
    }
}

// MARK: - BrandRewardsManager

final class BrandRewardsManager: ObservableObject {

    static let shared = BrandRewardsManager()

    @Published private(set) var activeCampaigns: [BrandCampaign] = []
    @Published private(set) var userClaims: [BrandRewardClaim] = []
    @Published private(set) var partnerships: [BrandPartnership] = []

    private var campaignStore: [String: BrandCampaign] = [:]
    private var claimsByUser: [String: Set<String>] = [:] // userAddress -> Set<campaignId>

    // MARK: - Campaign Management

    func createCampaign(brand: String, brandAddress: String, title: String, description: String, rewardType: BrandRewardType, budget: Double, rewardToken: String, maxClaims: Int, duration: TimeInterval, criteria: [EligibilityCriterion] = []) async throws -> BrandCampaign {
        let campaign = BrandCampaign(
            id: UUID().uuidString, brandName: brand, brandAddress: brandAddress,
            title: title, description: description,
            startDate: Date(), endDate: Date().addingTimeInterval(duration),
            rewardType: rewardType, totalBudget: budget, rewardToken: rewardToken,
            claimedCount: 0, maxClaims: maxClaims, status: .active,
            eligibilityCriteria: criteria
        )
        campaignStore[campaign.id] = campaign
        await MainActor.run { activeCampaigns.append(campaign) }
        return campaign
    }

    // MARK: - Claiming

    func claimReward(campaignId: String, user: String) async throws -> BrandRewardClaim {
        guard var campaign = campaignStore[campaignId] else {
            throw BrandRewardsError.campaignNotFound(campaignId)
        }
        guard campaign.status == .active else { throw BrandRewardsError.campaignNotActive }
        guard campaign.claimedCount < campaign.maxClaims else { throw BrandRewardsError.maxClaimsReached }

        let userCampaigns = claimsByUser[user] ?? []
        guard !userCampaigns.contains(campaignId) else { throw BrandRewardsError.alreadyClaimed }

        let rewardPerClaim = campaign.totalBudget / Double(campaign.maxClaims)

        let claim = BrandRewardClaim(
            id: UUID().uuidString, campaignId: campaignId, userAddress: user,
            rewardAmount: rewardPerClaim, rewardToken: campaign.rewardToken,
            claimedAt: Date(), transactionHash: nil
        )

        campaign.claimedCount += 1
        if campaign.claimedCount >= campaign.maxClaims { campaign.status = .exhausted }
        campaignStore[campaignId] = campaign

        claimsByUser[user, default: []].insert(campaignId)
        await MainActor.run { userClaims.append(claim) }
        return claim
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `claimReward(uint256 campaignId)`.
    static func encodeClaimReward(campaignId: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("claimReward(uint256)")
        data.append(ABIEncoder.encodeUInt256(campaignId))
        return data
    }

    /// Claim a brand-campaign reward on-chain through the real submit pipeline:
    /// enclave-signed UserOp → server paymaster → bundler. Contract address
    /// deferred to PendingCredentials (nil until set → throws, never a fake claim).
    @MainActor
    func claimRewardOnChain(
        campaignId: UInt64,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.brandRewards)
    ) async throws -> WalletTransactionService.Submission {
        guard let brand = contract else { throw BrandRewardsError.notConfigured }
        return try await service.submitCall(
            to: brand,
            value: 0,
            data: Self.encodeClaimReward(campaignId: campaignId),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Partnerships

    func createPartnership(brand1: String, brand2: String, name: String, multiplier: Double) async throws -> BrandPartnership {
        let partnership = BrandPartnership(
            id: UUID().uuidString, brand1Address: brand1, brand2Address: brand2,
            name: name, crossRewardMultiplier: multiplier, startDate: Date(), isActive: true
        )
        await MainActor.run { partnerships.append(partnership) }
        return partnership
    }

    // MARK: - Queries

    func getEligibleCampaigns(for user: String) -> [BrandCampaign] {
        let claimed = claimsByUser[user] ?? []
        return campaignStore.values.filter {
            $0.status == .active && !claimed.contains($0.id)
        }
    }

    func getCampaignProgress(campaignId: String) -> Double {
        guard let campaign = campaignStore[campaignId] else { return 0 }
        return Double(campaign.claimedCount) / Double(campaign.maxClaims)
    }
}
