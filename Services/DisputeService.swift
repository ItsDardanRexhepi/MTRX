import Foundation

// MARK: - Models

struct SvcDisputeCase: Codable, Identifiable {
    var id: String { disputeId }
    let disputeId: String
    let creator: String
    let respondent: String
    let description: String
    let status: String
    let stake: Double
    let votesFor: Int
    let votesAgainst: Int
    let deadline: Date
}

struct DisputeParams: Codable {
    let respondent: String
    let description: String
    let stake: Double
}

// MARK: - Service

@MainActor
final class DisputeService {

    static let shared = DisputeService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func createDispute(params: DisputeParams) async throws -> SvcDisputeCase {
        // Gateway contract: POST /api/v1/dispute/file {complainant, respondent,
        // dispute_type, description, stake_amount} (enveloped response). The
        // server rejects an under-staked filing — honest failure, no theater.
        struct FileBody: Encodable {
            let complainant: String
            let respondent: String
            let disputeType: String
            let description: String
            let stakeAmount: Double
        }
        let complainant = await api.walletPathIdentity()
        return try await api.postEnveloped(path: "/api/v1/dispute/file", body: FileBody(
            complainant: complainant,
            respondent: params.respondent,
            disputeType: "contract_breach",
            description: params.description,
            stakeAmount: params.stake))
    }

    func getDisputes(address: String) async throws -> [SvcDisputeCase] {
        try await api.get(path: "/disputes", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getOpenJuryCases() async throws -> [SvcDisputeCase] {
        try await api.get(path: "/disputes/jury", queryItems: nil)
    }

    /// Gateway contract: POST /api/v1/dispute/vote {dispute_id, juror, vote}
    /// where vote is "claimant" or "respondent" — only selected panel jurors
    /// may vote (server-enforced).
    func submitVote(disputeId: String, vote: String, justification: String = "") async throws -> SvcTransactionResult {
        struct VoteBody: Encodable {
            let disputeId: String
            let juror: String
            let vote: String
            let justification: String
        }
        let juror = await api.walletPathIdentity()
        return try await api.postEnveloped(path: "/api/v1/dispute/vote", body: VoteBody(
            disputeId: disputeId, juror: juror, vote: vote, justification: justification))
    }

    /// Gateway contract: POST /api/v1/dispute/claim {dispute_id, claimant} —
    /// records entitlement post-resolution (idempotent server-side); the
    /// platform holds no funds, settlement is on-chain later.
    func claimReward(disputeId: String) async throws -> SvcTransactionResult {
        struct ClaimBody: Encodable {
            let disputeId: String
            let claimant: String
        }
        let claimant = await api.walletPathIdentity()
        return try await api.postEnveloped(path: "/api/v1/dispute/claim", body: ClaimBody(
            disputeId: disputeId, claimant: claimant))
    }
}
