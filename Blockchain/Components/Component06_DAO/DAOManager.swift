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

struct DAOProposal {
    let proposalId: String
    let daoId: String
    let proposer: String
    let title: String
    let description: String
    let actions: [ProposalAction]
    let votesFor: UInt64
    let votesAgainst: UInt64
    let votesAbstain: UInt64
    let status: DAOProposalStatus
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

enum DAOProposalStatus: String {
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
    case notConfigured

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
        case .notConfigured: return "DAO/governor contract not configured (PendingCredentials.Components.dao)."
        }
    }
}

// MARK: - DAOManager

final class DAOManager {

    // MARK: - Properties

    weak var delegate: DAOManagerDelegate?

    private let erc4337Manager: ERC4337Manager
    private var daos: [String: DAOConfig] = [:]
    private var proposals: [String: DAOProposal] = [:]
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
    func createProposal(daoId: String, proposer: String, title: String, description: String, actions: [ProposalAction], completion: @escaping (Result<DAOProposal, DAOError>) -> Void) {
        guard let dao = daos[daoId] else {
            completion(.failure(.daoNotFound))
            return
        }
        let proposal = DAOProposal(
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
        proposal = DAOProposal(
            proposalId: proposal.proposalId, daoId: proposal.daoId, proposer: proposal.proposer,
            title: proposal.title, description: proposal.description, actions: proposal.actions,
            votesFor: votesFor, votesAgainst: votesAgainst, votesAbstain: votesAbstain,
            status: proposal.status, createdAt: proposal.createdAt,
            votingEndsAt: proposal.votingEndsAt, executionETA: proposal.executionETA
        )
        proposals[proposalId] = proposal
        completion(.success(vote))
    }

    /// Execute a succeeded proposal by dispatching its actions on-chain as ONE
    /// atomic batched UserOperation (enclave-signed, self-custodial). `sender` is
    /// the user's smart-account address and `signingKeyTag` its Secure Enclave key
    /// tag — required to sign the batch; the server never signs.
    ///
    /// The delegate's `didExecuteProposal` fires ONLY after the bundler accepts
    /// the signed batch op (returns a real userOp hash) — never optimistically.
    /// On any failure (needs-config, build, sign, or bundler reject) the proposal
    /// is left as-is and the error is surfaced — no fake success.
    func executeProposal(
        proposalId: String,
        sender: String,
        signingKeyTag: String,
        completion: @escaping (Result<WalletTransactionService.Submission, DAOError>) -> Void
    ) {
        guard let proposal = proposals[proposalId] else {
            completion(.failure(.proposalNotFound))
            return
        }
        guard proposal.status == .succeeded || proposal.votesFor > proposal.votesAgainst else {
            completion(.failure(.proposalNotSucceeded))
            return
        }

        // Run the real batch path. Mark executed + notify the delegate ONLY on a
        // confirmed bundler submission; map every failure honestly.
        Task { @MainActor in
            do {
                let submission = try await self.executeProposalOnChain(
                    actions: proposal.actions,
                    sender: sender,
                    signingKeyTag: signingKeyTag
                )
                self.proposals[proposalId] = DAOProposal(
                    proposalId: proposal.proposalId, daoId: proposal.daoId, proposer: proposal.proposer,
                    title: proposal.title, description: proposal.description, actions: proposal.actions,
                    votesFor: proposal.votesFor, votesAgainst: proposal.votesAgainst, votesAbstain: proposal.votesAbstain,
                    status: .executed, createdAt: proposal.createdAt,
                    votingEndsAt: proposal.votingEndsAt, executionETA: proposal.executionETA
                )
                self.delegate?.dao(self, didExecuteProposal: proposalId)
                completion(.success(submission))
            } catch let error as DAOError {
                self.delegate?.dao(self, didFailWithError: error)
                completion(.failure(error))
            } catch {
                // Build/sign/bundler errors from the spine surface as executionFailed.
                self.delegate?.dao(self, didFailWithError: .executionFailed)
                completion(.failure(.executionFailed))
            }
        }
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `castVote(uint256 proposalId, uint8 support)` (OZ Governor).
    static func encodeCastVote(proposalId: UInt64, support: VoteType) -> Data {
        var data = ABIEncoder.functionSelector("castVote(uint256,uint8)")
        data.append(ABIEncoder.encodeUInt256(proposalId))
        data.append(ABIEncoder.encodeUInt256(UInt64(support.rawValue)))
        return data
    }

    /// Cast an on-chain governance vote through the real submit pipeline:
    /// enclave-signed UserOp → server paymaster → bundler. `proposalId` is the
    /// on-chain numeric proposal id (distinct from the off-chain UUID). Contract
    /// address deferred to PendingCredentials (nil until set → throws, never faked).
    @MainActor
    func castVoteOnChain(
        proposalId: UInt64,
        support: VoteType,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.dao)
    ) async throws -> WalletTransactionService.Submission {
        guard let governor = contract else { throw DAOError.notConfigured }
        return try await service.submitCall(
            to: governor,
            value: 0,
            data: Self.encodeCastVote(proposalId: proposalId, support: support),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    /// Execute a succeeded proposal's actions on-chain as ONE atomic batched
    /// UserOperation through the real submit pipeline:
    ///
    ///   ERC4337Manager.buildBatchUserOperation(execute each ProposalAction)
    ///     → server verifying-paymaster (GasSponsorship — key on server only)
    ///     → ENCLAVE SIGN (P-256, Face-ID-gated inside WalletCore on the spine)
    ///     → bundler submit
    ///
    /// The smart account's `executeBatch(address[],uint256[],bytes[])` fans the
    /// proposal's (target, value, calldata) actions out atomically — exactly the
    /// governance-execution semantics, in a single self-custodial UserOp.
    ///
    /// WHY NOT `service.submitCall`: `WalletTransactionService` only exposes a
    /// SINGLE-call entry point; there is no batch entry point on the service. So
    /// this mirrors the spine's own internal build→sponsor→sign→submit sequence
    /// using the public `ERC4337Manager` batch builder, reading every external
    /// value from `PendingCredentials` (nothing hardcoded). No private key ever
    /// lives in the app — the wallet signature comes from the Secure Enclave, the
    /// paymaster signature from the server.
    ///
    /// `actions` are the proposal's on-chain actions (each target/value/calldata).
    /// `sender` is the user's smart-account address; `signingKeyTag` its enclave
    /// key tag. Returns the bundler's userOp hash — never a fabricated hash.
    ///
    /// GRACEFUL CONFIG: throws `DAOError.notConfigured` when the chain core
    /// (PendingCredentials rpc/chainID/entryPoint/factory + bundler) isn't filled,
    /// and `DAOError.executionFailed` if a proposal carries no actions to execute.
    @MainActor
    func executeProposalOnChain(
        actions: [ProposalAction],
        sender: String,
        signingKeyTag: String,
        userTier: UserTier = .free
    ) async throws -> WalletTransactionService.Submission {
        // Nothing to dispatch — refuse rather than claim a no-op succeeded.
        guard !actions.isEmpty else { throw DAOError.executionFailed }

        // Chain core must be configured (same gate as the spine's
        // WalletTransactionService.Config.fromPendingCredentials()). Reads each
        // value from PendingCredentials — never hardcoded. Blank → needs-config.
        guard PendingCredentials.isChainConfigured,
              let rpc = PendingCredentials.filled(PendingCredentials.Network.rpcURL)
                .flatMap({ URL(string: $0) }),
              let bundler = PendingCredentials.filled(PendingCredentials.AccountAbstraction.bundlerURL)
                .flatMap({ URL(string: $0) })
        else {
            throw DAOError.notConfigured
        }

        let networkConfig = BaseNetworkConfig(
            rpcURL: rpc,
            chainId: UInt64(PendingCredentials.Network.chainID),
            bundlerURL: bundler
        )
        let paymasterAddress = PendingCredentials.filled(PendingCredentials.AccountAbstraction.paymasterAddress)
        let manager = ERC4337Manager(
            entryPointAddress: PendingCredentials.filled(PendingCredentials.AccountAbstraction.entryPointAddress) ?? "",
            paymasterAddress: paymasterAddress,
            bundlerURL: bundler,
            networkConfig: networkConfig
        )
        manager.setAccountAddress(sender)
        manager.configureSigningKey(tag: signingKeyTag)

        // 1. Build the unsigned BATCH op (real ABI-encoded executeBatch calldata):
        //    one account call per ProposalAction (target, value, calldata).
        let calls: [(to: String, value: UInt64, data: Data)] = actions.map {
            (to: $0.target, value: $0.value, data: $0.calldata)
        }
        let op: UserOperation
        switch manager.buildBatchUserOperation(calls: calls) {
        case .success(let built): op = built
        case .failure: throw DAOError.executionFailed
        }

        // 2. Fetch verifying-paymaster data from the SERVER (key never in app). If
        //    the policy/budget declines or the server is unreachable, proceed
        //    UNSPONSORED — we never fabricate paymaster data.
        let sponsorship = GasSponsorship(
            paymasterAddress: paymasterAddress ?? "",
            platformBudgetWei: 1_000_000_000_000_000_000, // 1 ETH default platform budget
            paymasterSignatureEndpoint: PendingCredentials.AccountAbstraction.paymasterSignatureEndpoint,
            entryPoint: PendingCredentials.AccountAbstraction.entryPointAddress,
            chainID: PendingCredentials.Network.chainID
        )
        let sponsoredOp = (try? await sponsorship.sponsoredOperation(op, userAddress: sender, userTier: userTier)) ?? op

        // 3. Sign with the user's Secure Enclave key (P-256, Face-ID-gated inside
        //    the enclave provider). NEVER a throwaway key — refuses if unset.
        let signedOp = try await Self.signed(manager, sponsoredOp)

        // 4. Submit the signed batch op to the bundler.
        let hash = try await Self.submitted(manager, signedOp)
        return WalletTransactionService.Submission(userOpHash: hash, signedOperation: signedOp)
    }

    // MARK: - Continuation bridges to the completion-based ERC4337Manager
    //
    // These mirror the private bridges inside WalletTransactionService (which are
    // not visible here) so the batch path runs the exact same enclave-sign →
    // bundler-submit sequence as the single-call spine.

    private static func signed(_ manager: ERC4337Manager, _ op: UserOperation) async throws -> UserOperation {
        try await withCheckedThrowingContinuation { continuation in
            manager.signOperation(op) { result in
                switch result {
                case .success(let signed): continuation.resume(returning: signed)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func submitted(_ manager: ERC4337Manager, _ op: UserOperation) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            manager.submitOperation(op) { result in
                switch result {
                case .success(let hash): continuation.resume(returning: hash)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Query

    func getDAO(id: String) -> DAOConfig? { return daos[id] }
    func getProposals(daoId: String) -> [DAOProposal] { return proposals.values.filter { $0.daoId == daoId } }
    func getVotes(proposalId: String) -> [Vote] { return votes[proposalId] ?? [] }
}
