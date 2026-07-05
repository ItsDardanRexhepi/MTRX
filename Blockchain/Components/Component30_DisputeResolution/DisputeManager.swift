// DisputeManager.swift
// MTRX Blockchain - Components - Dispute Resolution
//
// On-chain dispute resolution: filing, arbitration, evidence, enforcement

import Foundation
import Combine

// MARK: - Data Models

struct Dispute: Identifiable, Codable {
    let id: String
    let claimantAddress: String
    let respondentAddress: String
    let contractId: String?
    let title: String
    let description: String
    let category: DisputeCategory
    let filedAt: Date
    var status: DisputeStatus
    var evidence: [DisputeEvidence]
    var arbitratorAddress: String?
    let stakeAmount: Double
    let stakeToken: String
    var resolution: Resolution?
    let deadline: Date
}

enum DisputeCategory: String, Codable {
    case contractBreach, paymentDispute, deliveryFailure
    case qualityIssue, fraudClaim, ipInfringement, other
}

enum DisputeStatus: String, Codable {
    case filed, underReview, arbitrationAssigned, evidenceCollection
    case deliberation, resolved, appealed, expired
}

struct DisputeEvidence: Identifiable, Codable {
    let id: String
    let disputeId: String
    let submittedBy: String
    let type: EvidenceType
    let contentHash: String
    let description: String
    let submittedAt: Date
    let attestationId: String?
}

enum EvidenceType: String, Codable {
    case document, screenshot, transactionRecord, contractCode
    case communication, thirdPartyAttestation, expertOpinion
}

struct Resolution: Codable {
    let outcome: ResolutionOutcome
    let arbitratorAddress: String
    let reasoning: String
    let awardAmount: Double?
    let awardToken: String?
    let resolvedAt: Date
    let enforcementAction: EnforcementAction?
}

enum ResolutionOutcome: String, Codable {
    case claimantWins, respondentWins, splitDecision, dismissed, settled
}

enum EnforcementAction: String, Codable {
    case fundsRelease, contractTermination, penaltyApplied
    case reputationPenalty, blacklist, none
}

struct Arbitrator: Identifiable, Codable {
    let id: String
    let address: String
    let name: String
    var casesResolved: Int
    var rating: Double
    let specializations: [DisputeCategory]
    let stakeRequired: Double
}

enum DisputeError: Error, LocalizedError {
    case disputeNotFound(String)
    case evidenceSubmissionClosed
    case notPartyToDispute
    case arbitratorNotAssigned
    case alreadyResolved
    case deadlinePassed
    case insufficientStake
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .disputeNotFound(let id): return "Dispute not found: \(id)"
        case .evidenceSubmissionClosed: return "Evidence submission period has closed."
        case .notPartyToDispute: return "You are not a party to this dispute."
        case .arbitratorNotAssigned: return "No arbitrator assigned yet."
        case .alreadyResolved: return "Dispute has already been resolved."
        case .deadlinePassed: return "Dispute resolution deadline has passed."
        case .insufficientStake: return "Insufficient stake to file dispute."
        case .notConfigured: return "Dispute contract not configured (PendingCredentials.Components.disputeResolution)."
        }
    }
}

// MARK: - DisputeManager

final class DisputeManager: ObservableObject {

    static let shared = DisputeManager()

    @Published private(set) var activeDisputes: [Dispute] = []
    @Published private(set) var resolvedDisputes: [Dispute] = []
    @Published private(set) var availableArbitrators: [Arbitrator] = []

    private var disputeStore: [String: Dispute] = [:]
    private var arbitratorStore: [String: Arbitrator] = [:]

    // MARK: - Filing

    func fileDispute(claimant: String, respondent: String, contractId: String?, title: String, description: String, category: DisputeCategory, stakeAmount: Double, stakeToken: String, deadlineDays: Int = 30) async throws -> Dispute {
        let dispute = Dispute(
            id: UUID().uuidString, claimantAddress: claimant,
            respondentAddress: respondent, contractId: contractId,
            title: title, description: description, category: category,
            filedAt: Date(), status: .filed, evidence: [],
            arbitratorAddress: nil, stakeAmount: stakeAmount,
            stakeToken: stakeToken, resolution: nil,
            deadline: Date().addingTimeInterval(TimeInterval(deadlineDays * 86400))
        )

        disputeStore[dispute.id] = dispute
        await MainActor.run { activeDisputes.append(dispute) }
        return dispute
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `fileDispute(address respondent, bytes32 caseHash, uint256 stake)`.
    static func encodeFileDispute(respondent: String, caseHash: Data, stake: UInt64) -> Data {
        var hashWord = Data(repeating: 0, count: 32)
        let head = caseHash.prefix(32)
        hashWord.replaceSubrange(0..<head.count, with: head)
        var out = ABIEncoder.functionSelector("fileDispute(address,bytes32,uint256)")
        out.append(ABIEncoder.encodeAddress(respondent))
        out.append(hashWord)
        out.append(ABIEncoder.encodeUInt256(stake))
        return out
    }

    /// File a dispute on-chain (with the user-staked bond) through the real submit
    /// pipeline: enclave-signed UserOp → server paymaster → bundler. `stakeWei` is
    /// the bond sent with the call (user-signed self-custody). Contract address
    /// deferred to PendingCredentials (nil until set → throws, never a fake filing).
    @MainActor
    func fileDisputeOnChain(
        respondent: String,
        caseHash: Data,
        stake: UInt64,
        stakeWei: UInt64 = 0,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.disputeResolution)
    ) async throws -> WalletTransactionService.Submission {
        guard let dispute = contract else { throw DisputeError.notConfigured }
        return try await service.submitCall(
            to: dispute,
            value: stakeWei,
            data: Self.encodeFileDispute(respondent: respondent, caseHash: caseHash, stake: stake),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    func getDispute(id: String) -> Dispute? { disputeStore[id] }

    // MARK: - Evidence

    func submitEvidence(disputeId: String, submitter: String, type: EvidenceType, contentHash: String, description: String, attestationId: String? = nil) async throws -> DisputeEvidence {
        guard var dispute = disputeStore[disputeId] else {
            throw DisputeError.disputeNotFound(disputeId)
        }
        guard dispute.status != .resolved && dispute.status != .expired else {
            throw DisputeError.alreadyResolved
        }
        guard dispute.claimantAddress == submitter || dispute.respondentAddress == submitter else {
            throw DisputeError.notPartyToDispute
        }

        let evidence = DisputeEvidence(
            id: UUID().uuidString, disputeId: disputeId,
            submittedBy: submitter, type: type,
            contentHash: contentHash, description: description,
            submittedAt: Date(), attestationId: attestationId
        )

        dispute.evidence.append(evidence)
        disputeStore[disputeId] = dispute
        return evidence
    }

    // MARK: - Arbitration

    func assignArbitrator(disputeId: String, arbitratorAddress: String) async throws {
        guard var dispute = disputeStore[disputeId] else {
            throw DisputeError.disputeNotFound(disputeId)
        }

        dispute.arbitratorAddress = arbitratorAddress
        dispute.status = .arbitrationAssigned
        disputeStore[disputeId] = dispute
    }

    func resolveDispute(disputeId: String, arbitrator: String, outcome: ResolutionOutcome, reasoning: String, awardAmount: Double? = nil, awardToken: String? = nil, enforcement: EnforcementAction? = nil) async throws -> Resolution {
        guard var dispute = disputeStore[disputeId] else {
            throw DisputeError.disputeNotFound(disputeId)
        }
        guard dispute.arbitratorAddress == arbitrator else {
            throw DisputeError.arbitratorNotAssigned
        }
        guard dispute.status != .resolved else {
            throw DisputeError.alreadyResolved
        }

        let resolution = Resolution(
            outcome: outcome, arbitratorAddress: arbitrator,
            reasoning: reasoning, awardAmount: awardAmount,
            awardToken: awardToken, resolvedAt: Date(),
            enforcementAction: enforcement
        )

        dispute.resolution = resolution
        dispute.status = .resolved
        disputeStore[disputeId] = dispute

        await MainActor.run { [dispute] in
            activeDisputes.removeAll { $0.id == disputeId }
            resolvedDisputes.append(dispute)
        }

        return resolution
    }

    // MARK: - Arbitrator Management

    func registerArbitrator(address: String, name: String, specializations: [DisputeCategory], stakeRequired: Double) async throws -> Arbitrator {
        let arbitrator = Arbitrator(
            id: UUID().uuidString, address: address, name: name,
            casesResolved: 0, rating: 5.0,
            specializations: specializations, stakeRequired: stakeRequired
        )
        arbitratorStore[address] = arbitrator
        await MainActor.run { availableArbitrators.append(arbitrator) }
        return arbitrator
    }

    // MARK: - Queries

    func getDisputesForUser(address: String) -> [Dispute] {
        disputeStore.values.filter { $0.claimantAddress == address || $0.respondentAddress == address }
    }

    func getPendingDeadlines(address: String) -> [Dispute] {
        getDisputesForUser(address: address)
            .filter { $0.status != .resolved && $0.status != .expired }
            .sorted { $0.deadline < $1.deadline }
    }
}
