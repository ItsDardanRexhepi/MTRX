import Foundation

// MARK: - Models

struct DAO: Codable, Identifiable {
    var id: String { daoId }
    let daoId: String
    let name: String
    let description: String
    let tokenSymbol: String
    let memberCount: Int
    let treasury: Double
}

struct Proposal: Codable, Identifiable {
    var id: String { proposalId }
    let proposalId: String
    let title: String
    let description: String
    let status: String
    let votesFor: Double
    let votesAgainst: Double
    let quorum: Double
    let endTime: Date
}

enum VoteSupport: String, Codable, CaseIterable {
    case for_ = "for"
    case against = "against"
    case abstain = "abstain"
}

struct VotingPower: Codable {
    let tokens: Double
    let delegatedTokens: Double
    let totalPower: Double
}

struct ProposalDraft: Codable {
    let title: String
    let description: String
    let actions: [String]
}

struct TreasuryBalance: Codable {
    let totalUSD: Double
    let assets: [TreasuryAsset]
    let daoId: String
}

struct TreasuryAsset: Codable, Identifiable {
    let id: UUID
    let token: String
    let symbol: String
    let balance: Double
    let usdValue: Double
}

struct TreasuryTransaction: Codable, Identifiable {
    let id: UUID
    let type: String
    let token: String
    let amount: Double
    let recipient: String?
    let timestamp: Date
    let txHash: String?
}

struct DelegationStatus: Codable {
    let delegatedTo: [DelegationEntry]
    let delegatedFrom: [DelegationEntry]
    let totalOutgoing: Double
    let totalIncoming: Double
}

struct DelegationEntry: Codable, Identifiable {
    let id: UUID
    let delegator: String
    let delegatee: String
    let token: String
    let amount: Double
    let since: Date
}

// MARK: - Service

@MainActor
final class GovernanceService {

    static let shared = GovernanceService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getDAOs(address: String) async throws -> [DAO] {
        try await api.get("/governance/daos", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getProposals(daoId: String) async throws -> [Proposal] {
        try await api.get("/governance/daos/\(daoId)/proposals")
    }

    func vote(proposalId: String, support: VoteSupport, reason: String?) async throws -> TransactionResult {
        struct VoteBody: Codable {
            let proposalId: String
            let support: VoteSupport
            let reason: String?
        }
        let body = VoteBody(proposalId: proposalId, support: support, reason: reason)
        return try await api.post("/governance/proposals/\(proposalId)/vote", body: body)
    }

    func createProposal(daoId: String, proposal: ProposalDraft) async throws -> TransactionResult {
        try await api.post("/governance/daos/\(daoId)/proposals", body: proposal)
    }

    func getVotingPower(daoId: String, address: String) async throws -> VotingPower {
        try await api.get("/governance/daos/\(daoId)/voting-power", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getTreasuryBalance(daoId: String) async throws -> TreasuryBalance {
        try await api.get("/governance/daos/\(daoId)/treasury")
    }

    func getTreasuryHistory(daoId: String) async throws -> [TreasuryTransaction] {
        try await api.get("/governance/daos/\(daoId)/treasury/history")
    }

    func proposeSpending(daoId: String, recipient: String, amount: String, token: String, description: String) async throws -> Proposal {
        struct SpendingBody: Codable {
            let recipient: String
            let amount: String
            let token: String
            let description: String
        }
        let body = SpendingBody(recipient: recipient, amount: amount, token: token, description: description)
        return try await api.post("/governance/daos/\(daoId)/treasury/propose", body: body)
    }

    func delegate(to address: String, token: String) async throws -> TransactionResult {
        struct DelegateBody: Codable {
            let to: String
            let token: String
        }
        let body = DelegateBody(to: address, token: token)
        return try await api.post("/governance/delegate", body: body)
    }

    func undelegate(token: String) async throws -> TransactionResult {
        struct UndelegateBody: Codable {
            let token: String
        }
        let body = UndelegateBody(token: token)
        return try await api.post("/governance/undelegate", body: body)
    }

    func getDelegations(address: String) async throws -> DelegationStatus {
        try await api.get("/governance/delegations", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }
}
