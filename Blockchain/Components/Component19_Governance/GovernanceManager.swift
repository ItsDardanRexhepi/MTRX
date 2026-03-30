// GovernanceManager.swift
// MTRX Blockchain - Components - Governance (C19)
//
// Three voting models (1-person-1-vote, token-weighted, quadratic),
// participation-based quorum, bilateral disputes rejected and redirected to C30.

import Foundation
import Combine

// MARK: - Protocols

protocol GovernanceDelegate: AnyObject {
    func governance(_ manager: GovernanceManager, proposalCreated proposal: GovernanceProposal)
    func governance(_ manager: GovernanceManager, voteCast vote: GovernanceVote)
    func governance(_ manager: GovernanceManager, proposalResolved proposal: GovernanceProposal)
    func governance(_ manager: GovernanceManager, bilateralDisputeRedirected disputeInfo: String)
}

// MARK: - Data Models

enum VotingModel: String, Codable, CaseIterable {
    /// Each eligible voter gets exactly one vote.
    case onePersonOneVote
    /// Votes weighted by token holdings.
    case tokenWeighted
    /// Cost of N votes = N^2 tokens. Reduces plutocratic influence.
    case quadratic
}

enum ProposalStatus: String, Codable {
    case active, passed, rejected, executed, cancelled
}

struct GovernanceProposal: Identifiable, Codable {
    let id: String
    let daoId: String
    let title: String
    let description: String
    let proposerAddress: String
    let votingModel: VotingModel
    let createdAt: Date
    let votingDeadline: Date
    var status: ProposalStatus
    var forVotes: Double
    var againstVotes: Double
    var abstainVotes: Double
    var participantCount: Int
    let quorumType: QuorumType
    var executionPayload: String?
}

/// Participation-based quorum: quorum is met when a percentage of eligible
/// voters actually vote, rather than a fixed token threshold.
enum QuorumType: Codable {
    case participationBased(requiredPercent: Double)  // e.g. 0.10 = 10%

    enum CodingKeys: String, CodingKey {
        case type, requiredPercent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let pct = try c.decode(Double.self, forKey: .requiredPercent)
        self = .participationBased(requiredPercent: pct)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .participationBased(let pct):
            try c.encode("participationBased", forKey: .type)
            try c.encode(pct, forKey: .requiredPercent)
        }
    }
}

struct GovernanceVote: Identifiable, Codable {
    let id: String
    let proposalId: String
    let voterAddress: String
    let choice: VoteChoice
    let weight: Double       // actual power after model calculation
    let tokenBalance: Double // raw token balance at snapshot
    let castAt: Date
}

enum VoteChoice: String, Codable {
    case forProposal, against, abstain
}

enum GovernanceError: Error, LocalizedError {
    case proposalNotFound(String)
    case votingClosed
    case alreadyVoted
    case quorumNotMet
    case bilateralDisputeRejected
    case insufficientTokens
    case invalidModel

    var errorDescription: String? {
        switch self {
        case .proposalNotFound(let id): return "Proposal not found: \(id)"
        case .votingClosed: return "Voting period has ended."
        case .alreadyVoted: return "Address has already voted on this proposal."
        case .quorumNotMet: return "Participation-based quorum has not been met."
        case .bilateralDisputeRejected: return "Bilateral disputes are not handled by governance. Redirecting to C30 Dispute Resolution."
        case .insufficientTokens: return "Insufficient tokens for quadratic voting."
        case .invalidModel: return "Invalid voting model configuration."
        }
    }
}

// MARK: - GovernanceManager

final class GovernanceManager: ObservableObject {

    static let shared = GovernanceManager()

    weak var delegate: GovernanceDelegate?

    @Published private(set) var proposals: [GovernanceProposal] = []
    @Published private(set) var votes: [GovernanceVote] = []
    @Published private(set) var isLoading = false

    private var proposalStore: [String: GovernanceProposal] = [:]
    private var votesByProposal: [String: [GovernanceVote]] = [:]
    private var eligibleVoterCounts: [String: Int] = [:]   // daoId -> count

    // MARK: - Proposal Creation

    func createProposal(daoId: String, title: String, description: String, proposer: String, votingModel: VotingModel, votingDuration: TimeInterval, quorumPercent: Double = 0.10, executionPayload: String? = nil) async throws -> GovernanceProposal {
        let proposal = GovernanceProposal(
            id: UUID().uuidString,
            daoId: daoId,
            title: title,
            description: description,
            proposerAddress: proposer,
            votingModel: votingModel,
            createdAt: Date(),
            votingDeadline: Date().addingTimeInterval(votingDuration),
            status: .active,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            participantCount: 0,
            quorumType: .participationBased(requiredPercent: quorumPercent),
            executionPayload: executionPayload
        )

        proposalStore[proposal.id] = proposal
        votesByProposal[proposal.id] = []
        await MainActor.run { proposals.append(proposal) }
        delegate?.governance(self, proposalCreated: proposal)
        return proposal
    }

    // MARK: - Voting

    /// Cast a vote using the proposal's voting model.
    func castVote(proposalId: String, voterAddress: String, choice: VoteChoice, tokenBalance: Double) async throws -> GovernanceVote {
        guard var proposal = proposalStore[proposalId] else {
            throw GovernanceError.proposalNotFound(proposalId)
        }
        guard proposal.status == .active, Date() < proposal.votingDeadline else {
            throw GovernanceError.votingClosed
        }
        // Prevent double voting
        if votesByProposal[proposalId]?.contains(where: { $0.voterAddress == voterAddress }) == true {
            throw GovernanceError.alreadyVoted
        }

        let weight = calculateVoteWeight(model: proposal.votingModel, tokenBalance: tokenBalance)

        let vote = GovernanceVote(
            id: UUID().uuidString,
            proposalId: proposalId,
            voterAddress: voterAddress,
            choice: choice,
            weight: weight,
            tokenBalance: tokenBalance,
            castAt: Date()
        )

        switch choice {
        case .forProposal: proposal.forVotes += weight
        case .against:     proposal.againstVotes += weight
        case .abstain:     proposal.abstainVotes += weight
        }
        proposal.participantCount += 1
        proposalStore[proposalId] = proposal
        votesByProposal[proposalId, default: []].append(vote)

        await MainActor.run { votes.append(vote) }
        await updateProposalInPublished(proposal)
        delegate?.governance(self, voteCast: vote)
        return vote
    }

    // MARK: - Vote Weight Calculation

    /// Calculate vote weight based on the voting model.
    func calculateVoteWeight(model: VotingModel, tokenBalance: Double) -> Double {
        switch model {
        case .onePersonOneVote:
            return 1.0
        case .tokenWeighted:
            return tokenBalance
        case .quadratic:
            // sqrt(tokens) votes; cost of N votes = N^2
            return sqrt(tokenBalance)
        }
    }

    // MARK: - Proposal Resolution

    /// Resolve proposal after voting deadline, checking participation-based quorum.
    func resolveProposal(proposalId: String, totalEligibleVoters: Int) async throws -> GovernanceProposal {
        guard var proposal = proposalStore[proposalId] else {
            throw GovernanceError.proposalNotFound(proposalId)
        }

        // Check participation-based quorum
        switch proposal.quorumType {
        case .participationBased(let requiredPercent):
            let participationRate = totalEligibleVoters > 0
                ? Double(proposal.participantCount) / Double(totalEligibleVoters)
                : 0
            guard participationRate >= requiredPercent else {
                proposal.status = .rejected
                proposalStore[proposalId] = proposal
                await updateProposalInPublished(proposal)
                throw GovernanceError.quorumNotMet
            }
        }

        proposal.status = proposal.forVotes > proposal.againstVotes ? .passed : .rejected
        proposalStore[proposalId] = proposal
        await updateProposalInPublished(proposal)
        delegate?.governance(self, proposalResolved: proposal)
        return proposal
    }

    // MARK: - Bilateral Dispute Rejection

    /// Bilateral disputes are NOT handled by governance.
    /// They must go to C30 (Dispute Resolution).
    func attemptBilateralDispute(partyA: String, partyB: String, description: String) async throws {
        let info = "Bilateral dispute between \(partyA) and \(partyB): \(description)"
        delegate?.governance(self, bilateralDisputeRedirected: info)
        throw GovernanceError.bilateralDisputeRejected
    }

    // MARK: - Queries

    func getProposal(id: String) -> GovernanceProposal? {
        proposalStore[id]
    }

    func getActiveProposals(daoId: String) -> [GovernanceProposal] {
        proposalStore.values.filter { $0.daoId == daoId && $0.status == .active }
    }

    func getVotes(proposalId: String) -> [GovernanceVote] {
        votesByProposal[proposalId] ?? []
    }

    func setEligibleVoterCount(daoId: String, count: Int) {
        eligibleVoterCounts[daoId] = count
    }

    // MARK: - Private

    @MainActor
    private func updateProposalInPublished(_ proposal: GovernanceProposal) {
        if let idx = proposals.firstIndex(where: { $0.id == proposal.id }) {
            proposals[idx] = proposal
        }
    }
}
