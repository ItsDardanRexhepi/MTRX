// FundraisingManager.swift
// MTRX Blockchain - Components - Fundraising (C22)
//
// 100% to recipient, vesting engine, milestone verification (oracle or contributor vote),
// auto-refund on missed deadline.

import Foundation
import Combine

// MARK: - Protocols

protocol FundraisingDelegate: AnyObject {
    func fundraising(_ manager: FundraisingManager, campaignCreated campaign: FundraisingCampaign)
    func fundraising(_ manager: FundraisingManager, contributionReceived contribution: FundContribution)
    func fundraising(_ manager: FundraisingManager, milestoneVerified milestone: FundMilestone)
    func fundraising(_ manager: FundraisingManager, autoRefundTriggered campaign: FundraisingCampaign)
    func fundraising(_ manager: FundraisingManager, vestingReleased vesting: VestingSchedule)
}

// MARK: - Data Models

enum CampaignStatus: String, Codable {
    case active, funded, milestonesPending, completed, refunded, expired
}

enum MilestoneVerificationType: String, Codable {
    case oracle
    case contributorVote
}

enum MilestoneStatus: String, Codable {
    case pending, verified, failed, disputed
}

struct FundraisingCampaign: Identifiable, Codable {
    let id: String
    let creatorAddress: String
    let recipientAddress: String
    let title: String
    let description: String
    let goalAmount: Double
    var raisedAmount: Double
    let deadline: Date
    var status: CampaignStatus
    var milestones: [FundMilestone]
    var contributorCount: Int
    /// Platform takes 0% — 100% goes to the recipient.
    let platformFeePercent: Double  // always 0.0
}

struct FundContribution: Identifiable, Codable {
    let id: String
    let campaignId: String
    let contributorAddress: String
    let amount: Double
    let timestamp: Date
    var refunded: Bool
}

struct FundMilestone: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let targetAmount: Double
    let deadline: Date
    var status: MilestoneStatus
    let verificationType: MilestoneVerificationType
    var oracleProof: String?
    var votesFor: Int
    var votesAgainst: Int
    var totalEligibleVoters: Int
}

struct VestingSchedule: Identifiable, Codable {
    let id: String
    let campaignId: String
    let recipientAddress: String
    let totalAmount: Double
    var releasedAmount: Double
    let vestingStart: Date
    let vestingEnd: Date
    let cliffDate: Date?
    var releases: [VestingRelease]
}

struct VestingRelease: Identifiable, Codable {
    let id: String
    let amount: Double
    let releasedAt: Date
    let milestoneId: String?
}

enum FundraisingError: Error, LocalizedError {
    case campaignNotFound(String)
    case campaignExpired
    case goalAlreadyMet
    case milestoneNotFound(String)
    case milestoneDeadlineMissed
    case autoRefundTriggered
    case vestingNotReady
    case verificationFailed(String)
    case insufficientVotes

    var errorDescription: String? {
        switch self {
        case .campaignNotFound(let id): return "Campaign not found: \(id)"
        case .campaignExpired: return "Campaign deadline has passed."
        case .goalAlreadyMet: return "Funding goal already met."
        case .milestoneNotFound(let id): return "Milestone not found: \(id)"
        case .milestoneDeadlineMissed: return "Milestone deadline was missed. Auto-refund triggered."
        case .autoRefundTriggered: return "Auto-refund has been triggered for this campaign."
        case .vestingNotReady: return "Vesting release not yet available."
        case .verificationFailed(let r): return "Verification failed: \(r)"
        case .insufficientVotes: return "Not enough contributor votes for verification."
        }
    }
}

// MARK: - FundraisingManager

final class FundraisingManager: ObservableObject {

    static let shared = FundraisingManager()

    /// 100% goes to the recipient. Platform fee is zero.
    static let platformFeePercent: Double = 0.0

    weak var delegate: FundraisingDelegate?

    @Published private(set) var campaigns: [FundraisingCampaign] = []
    @Published private(set) var contributions: [FundContribution] = []
    @Published private(set) var vestingSchedules: [VestingSchedule] = []
    @Published private(set) var isLoading = false

    private var campaignStore: [String: FundraisingCampaign] = [:]
    private var contributionsByCampaign: [String: [FundContribution]] = [:]
    private var vestingStore: [String: VestingSchedule] = [:]

    // MARK: - Campaign Creation

    func createCampaign(creator: String, recipient: String, title: String, description: String, goalAmount: Double, deadline: Date, milestones: [FundMilestone]) async throws -> FundraisingCampaign {
        let campaign = FundraisingCampaign(
            id: UUID().uuidString,
            creatorAddress: creator,
            recipientAddress: recipient,
            title: title,
            description: description,
            goalAmount: goalAmount,
            raisedAmount: 0,
            deadline: deadline,
            status: .active,
            milestones: milestones,
            contributorCount: 0,
            platformFeePercent: Self.platformFeePercent
        )

        campaignStore[campaign.id] = campaign
        contributionsByCampaign[campaign.id] = []
        await MainActor.run { campaigns.append(campaign) }
        delegate?.fundraising(self, campaignCreated: campaign)
        return campaign
    }

    // MARK: - Contributions (100% to Recipient)

    func contribute(campaignId: String, contributorAddress: String, amount: Double) async throws -> FundContribution {
        guard var campaign = campaignStore[campaignId] else {
            throw FundraisingError.campaignNotFound(campaignId)
        }
        guard campaign.status == .active else {
            throw FundraisingError.campaignExpired
        }
        guard Date() < campaign.deadline else {
            // Auto-refund on missed deadline
            try await triggerAutoRefund(campaignId: campaignId)
            throw FundraisingError.campaignExpired
        }

        let contribution = FundContribution(
            id: UUID().uuidString,
            campaignId: campaignId,
            contributorAddress: contributorAddress,
            amount: amount,
            timestamp: Date(),
            refunded: false
        )

        campaign.raisedAmount += amount
        campaign.contributorCount += 1
        if campaign.raisedAmount >= campaign.goalAmount {
            campaign.status = .funded
        }
        campaignStore[campaignId] = campaign
        contributionsByCampaign[campaignId, default: []].append(contribution)

        await MainActor.run { contributions.append(contribution) }
        await updateCampaignInPublished(campaign)
        delegate?.fundraising(self, contributionReceived: contribution)
        return contribution
    }

    // MARK: - Milestone Verification

    /// Verify a milestone via oracle proof.
    func verifyMilestoneByOracle(campaignId: String, milestoneId: String, oracleProof: String) async throws {
        guard var campaign = campaignStore[campaignId] else {
            throw FundraisingError.campaignNotFound(campaignId)
        }
        guard let mIdx = campaign.milestones.firstIndex(where: { $0.id == milestoneId }) else {
            throw FundraisingError.milestoneNotFound(milestoneId)
        }
        guard campaign.milestones[mIdx].verificationType == .oracle else {
            throw FundraisingError.verificationFailed("This milestone requires contributor vote, not oracle.")
        }

        // Check deadline
        if Date() > campaign.milestones[mIdx].deadline {
            try await triggerAutoRefund(campaignId: campaignId)
            throw FundraisingError.milestoneDeadlineMissed
        }

        campaign.milestones[mIdx].status = .verified
        campaign.milestones[mIdx].oracleProof = oracleProof
        campaignStore[campaignId] = campaign
        await updateCampaignInPublished(campaign)
        delegate?.fundraising(self, milestoneVerified: campaign.milestones[mIdx])
    }

    /// Cast a contributor vote for milestone verification.
    func voteMilestone(campaignId: String, milestoneId: String, voterAddress: String, approve: Bool) async throws {
        guard var campaign = campaignStore[campaignId] else {
            throw FundraisingError.campaignNotFound(campaignId)
        }
        guard let mIdx = campaign.milestones.firstIndex(where: { $0.id == milestoneId }) else {
            throw FundraisingError.milestoneNotFound(milestoneId)
        }
        guard campaign.milestones[mIdx].verificationType == .contributorVote else {
            throw FundraisingError.verificationFailed("This milestone uses oracle, not contributor vote.")
        }

        if Date() > campaign.milestones[mIdx].deadline {
            try await triggerAutoRefund(campaignId: campaignId)
            throw FundraisingError.milestoneDeadlineMissed
        }

        if approve {
            campaign.milestones[mIdx].votesFor += 1
        } else {
            campaign.milestones[mIdx].votesAgainst += 1
        }

        // Auto-verify if majority approves
        let totalVotes = campaign.milestones[mIdx].votesFor + campaign.milestones[mIdx].votesAgainst
        if totalVotes >= campaign.milestones[mIdx].totalEligibleVoters / 2 + 1 {
            if campaign.milestones[mIdx].votesFor > campaign.milestones[mIdx].votesAgainst {
                campaign.milestones[mIdx].status = .verified
                delegate?.fundraising(self, milestoneVerified: campaign.milestones[mIdx])
            } else {
                campaign.milestones[mIdx].status = .failed
            }
        }

        campaignStore[campaignId] = campaign
        await updateCampaignInPublished(campaign)
    }

    // MARK: - Auto-Refund on Missed Deadline

    func triggerAutoRefund(campaignId: String) async throws {
        guard var campaign = campaignStore[campaignId] else {
            throw FundraisingError.campaignNotFound(campaignId)
        }

        campaign.status = .refunded
        campaignStore[campaignId] = campaign

        // Mark all contributions as refunded
        if var contribs = contributionsByCampaign[campaignId] {
            for i in contribs.indices {
                contribs[i].refunded = true
            }
            contributionsByCampaign[campaignId] = contribs
        }

        await updateCampaignInPublished(campaign)
        delegate?.fundraising(self, autoRefundTriggered: campaign)
    }

    /// Check all active campaigns for missed deadlines and auto-refund.
    func checkDeadlines() async {
        let now = Date()
        for (id, campaign) in campaignStore where campaign.status == .active {
            if now > campaign.deadline {
                try? await triggerAutoRefund(campaignId: id)
            }
            // Check individual milestones
            for milestone in campaign.milestones where milestone.status == .pending {
                if now > milestone.deadline {
                    try? await triggerAutoRefund(campaignId: id)
                    break
                }
            }
        }
    }

    // MARK: - Vesting Engine

    func createVestingSchedule(campaignId: String, recipient: String, totalAmount: Double, vestingStart: Date, vestingEnd: Date, cliffDate: Date?) async throws -> VestingSchedule {
        let schedule = VestingSchedule(
            id: UUID().uuidString,
            campaignId: campaignId,
            recipientAddress: recipient,
            totalAmount: totalAmount,
            releasedAmount: 0,
            vestingStart: vestingStart,
            vestingEnd: vestingEnd,
            cliffDate: cliffDate,
            releases: []
        )

        vestingStore[schedule.id] = schedule
        await MainActor.run { vestingSchedules.append(schedule) }
        return schedule
    }

    func releaseVestedFunds(vestingId: String, milestoneId: String? = nil) async throws -> VestingRelease {
        guard var schedule = vestingStore[vestingId] else {
            throw FundraisingError.vestingNotReady
        }

        let now = Date()
        if let cliff = schedule.cliffDate, now < cliff {
            throw FundraisingError.vestingNotReady
        }

        let elapsed = now.timeIntervalSince(schedule.vestingStart)
        let total = schedule.vestingEnd.timeIntervalSince(schedule.vestingStart)
        let vestedFraction = min(1.0, max(0, elapsed / total))
        let totalVested = schedule.totalAmount * vestedFraction
        let releasable = totalVested - schedule.releasedAmount

        guard releasable > 0 else {
            throw FundraisingError.vestingNotReady
        }

        let release = VestingRelease(
            id: UUID().uuidString,
            amount: releasable,
            releasedAt: now,
            milestoneId: milestoneId
        )

        schedule.releasedAmount += releasable
        schedule.releases.append(release)
        vestingStore[vestingId] = schedule
        await updateVestingInPublished(schedule)
        delegate?.fundraising(self, vestingReleased: schedule)
        return release
    }

    // MARK: - Queries

    func getCampaign(id: String) -> FundraisingCampaign? { campaignStore[id] }

    func getContributions(campaignId: String) -> [FundContribution] {
        contributionsByCampaign[campaignId] ?? []
    }

    // MARK: - Private

    @MainActor
    private func updateCampaignInPublished(_ campaign: FundraisingCampaign) {
        if let idx = campaigns.firstIndex(where: { $0.id == campaign.id }) {
            campaigns[idx] = campaign
        }
    }

    @MainActor
    private func updateVestingInPublished(_ schedule: VestingSchedule) {
        if let idx = vestingSchedules.firstIndex(where: { $0.id == schedule.id }) {
            vestingSchedules[idx] = schedule
        }
    }
}
