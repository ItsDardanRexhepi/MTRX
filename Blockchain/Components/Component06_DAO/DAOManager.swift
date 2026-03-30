// DAOManager.swift
// MTRX Blockchain - Components - DAO
//
// DAO creation and governance: proposals, voting, execution

import Foundation

// MARK: - Protocols

protocol DAOManagerDelegate: AnyObject {
    func dao(_ manager: DAOManager, didCreateDAO daoId: String)
    func dao(_ manager: DAOManager, didCreateProposal proposalId: String)
    func dao(_ manager: DAOManager, didExecuteProposal proposalId: String)
    func dao(_ manager: DAOManager, didFailWithError error: DAOError)
}

// MARK: - Data Models

struct DAOConfig {
    let daoId: String
    let name: String
    let governanceToken: String
    let quorumThreshold: Double
    let votingPeriod: TimeInterval
    let executionDelay: TimeInterval
    let proposalThreshold: UInt64
    let members: [String]
    let createdAt: Date
}

struct Proposal {
    let proposalId: String
    let daoId: String
    let proposer: String
    let title: String
    let description: String
    let actions: [ProposalAction]
    let votesFor: UInt64
    let votesAgainst: UInt64
    let votesAbstain: UInt64
    let status: ProposalStatus
    let createdAt: Date
    let votingEndsAt: Date
    let executionETA: Date?
}

struct ProposalAction {
    let target: String
    let value: UInt64
    let calldata: Data
    let description: String
}

enum ProposalStatus: String {
    case pending, active, defeated, succeeded, queued, executed, canceled, expired
}

struct Vote {
    let voter: String
    let proposalId: String
    let support: VoteType
    let weight: UInt64
    let reason: String?
    let timestamp: Date
}

enum VoteType: Int { case against = 0, forProposal = 1, abstain = 2 }

enum DAOError: Error, LocalizedError {
    case daoNotFound
    case proposalNotFound
    case insufficientVotingPower
    case votingPeriodEnded
    case quorumNotReached
    case alreadyVoted
    case executionFailed
    case proposalNotSucceeded

    var errorDescription: String? {
        switch self {
        case .daoNotFound: return "DAO not found."
        case .proposalNotFound: return "Proposal not found."
        case .insufficientVotingPower: return "Insufficient voting power."
        case .votingPeriodEnded: return "Voting period has ended."
        case .quorumNotReached: return "Quorum not reached."
        case .alreadyVoted: return "Already voted on this proposal."
        case .executionFailed: return "Proposal execution failed."
        case .proposalNotSucceeded: return "Proposal did not succeed."
        }
    }
}

// MARK: - DAOManager

final class DAOManager {

    // MARK: - Properties

    weak var delegate: DAOManagerDelegate?

    private let erc4337Manager: ERC4337Manager
    private var daos: [String: DAOConfig] = [:]
    private var proposals: [String: Proposal] = [:]
    private var votes: [String: [Vote]] = [:] // proposalId -> votes
    private let processingQueue = DispatchQueue(label: "com.mtrx.dao", qos: .userInitiated)

    // MARK: - Initialization

    init(erc4337Manager: ERC4337Manager) {
        self.erc4337Manager = erc4337Manager
    }

    // MARK: - DAO Creation

    /// Create a new DAO
    func createDAO(name: String, governanceToken: String, quorum: Double, votingPeriod: TimeInterval, members: [String], completion: @escaping (Result<DAOConfig, DAOError>) -> Void) {
        let config = DAOConfig(
            daoId: UUID().uuidString, name: name, governanceToken: governanceToken,
            quorumThreshold: quorum, votingPeriod: votingPeriod, executionDelay: 86400,
            proposalThreshold: 1000, members: members, createdAt: Date()
        )
        daos[config.daoId] = config
        delegate?.dao(self, didCreateDAO: config.daoId)
        completion(.success(config))
    }

    // MARK: - Proposals

    /// Create a new proposal
    func createProposal(daoId: String, proposer: String, title: String, description: String, actions: [ProposalAction], completion: @escaping (Result<Proposal, DAOError>) -> Void) {
        guard let dao = daos[daoId] else {
            completion(.failure(.daoNotFound))
            return
        }
        let proposal = Proposal(
            proposalId: UUID().uuidString, daoId: daoId, proposer: proposer,
            title: title, description: description, actions: actions,
            votesFor: 0, votesAgainst: 0, votesAbstain: 0, status: .active,
            createdAt: Date(), votingEndsAt: Date().addingTimeInterval(dao.votingPeriod),
            executionETA: nil
        )
        proposals[proposal.proposalId] = proposal
        votes[proposal.proposalId] = []
        delegate?.dao(self, didCreateProposal: proposal.proposalId)
        completion(.success(proposal))
    }

    /// Cast a vote on a proposal
    func castVote(proposalId: String, voter: String, support: VoteType, weight: UInt64, reason: String? = nil, completion: @escaping (Result<Vote, DAOError>) -> Void) {
        guard var proposal = proposals[proposalId] else {
            completion(.failure(.proposalNotFound))
            return
        }
        guard proposal.status == .active else {
            completion(.failure(.votingPeriodEnded))
            return
        }
        guard Date() < proposal.votingEndsAt else {
            completion(.failure(.votingPeriodEnded))
            return
        }
        let existingVotes = votes[proposalId] ?? []
        guard !existingVotes.contains(where: { $0.voter == voter }) else {
            completion(.failure(.alreadyVoted))
            return
        }

        let vote = Vote(voter: voter, proposalId: proposalId, support: support, weight: weight, reason: reason, timestamp: Date())
        votes[proposalId, default: []].append(vote)

        // Update tallies
        var votesFor = proposal.votesFor
        var votesAgainst = proposal.votesAgainst
        var votesAbstain = proposal.votesAbstain
        switch support {
        case .forProposal: votesFor += weight
        case .against: votesAgainst += weight
        case .abstain: votesAbstain += weight
        }
        proposal = Proposal(
            proposalId: proposal.proposalId, daoId: proposal.daoId, proposer: proposal.proposer,
            title: proposal.title, description: proposal.description, actions: proposal.actions,
            votesFor: votesFor, votesAgainst: votesAgainst, votesAbstain: votesAbstain,
            status: proposal.status, createdAt: proposal.createdAt,
            votingEndsAt: proposal.votingEndsAt, executionETA: proposal.executionETA
        )
        proposals[proposalId] = proposal
        completion(.success(vote))
    }

    /// Execute a succeeded proposal
    func executeProposal(proposalId: String, completion: @escaping (Result<Void, DAOError>) -> Void) {
        guard let proposal = proposals[proposalId] else {
            completion(.failure(.proposalNotFound))
            return
        }
        guard proposal.status == .succeeded || proposal.votesFor > proposal.votesAgainst else {
            completion(.failure(.proposalNotSucceeded))
            return
        }
        // TODO: Execute proposal actions via ERC-4337 batch UserOperation
        delegate?.dao(self, didExecuteProposal: proposalId)
        completion(.failure(.executionFailed))
    }

    // MARK: - Query

    func getDAO(id: String) -> DAOConfig? { return daos[id] }
    func getProposals(daoId: String) -> [Proposal] { return proposals.values.filter { $0.daoId == daoId } }
    func getVotes(proposalId: String) -> [Vote] { return votes[proposalId] ?? [] }
}
