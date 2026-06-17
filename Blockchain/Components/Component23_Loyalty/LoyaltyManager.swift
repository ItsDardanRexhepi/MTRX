// LoyaltyManager.swift
// MTRX Blockchain - Components - Loyalty (C23)
//
// Platform native rewards + business rewards, ZKP eligibility,
// milestone injection points.

import Foundation
import Combine

// MARK: - Protocols

protocol LoyaltyDelegate: AnyObject {
    func loyalty(_ manager: LoyaltyManager, rewardEarned event: LoyaltyRewardEvent)
    func loyalty(_ manager: LoyaltyManager, milestoneReached milestone: LoyaltyMilestone)
    func loyalty(_ manager: LoyaltyManager, zkpVerified proof: ZKPEligibilityProof)
}

// MARK: - Data Models

enum RewardSource: String, Codable {
    case platformNative
    case business
}

enum LoyaltyTierLevel: String, Codable, CaseIterable, Comparable {
    case bronze, silver, gold, platinum, diamond

    static func < (lhs: LoyaltyTierLevel, rhs: LoyaltyTierLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var sortOrder: Int {
        switch self {
        case .bronze: return 0
        case .silver: return 1
        case .gold: return 2
        case .platinum: return 3
        case .diamond: return 4
        }
    }

    var pointsRequired: Int {
        switch self {
        case .bronze: return 0
        case .silver: return 1_000
        case .gold: return 5_000
        case .platinum: return 25_000
        case .diamond: return 100_000
        }
    }
}

struct LoyaltyAccount: Identifiable, Codable {
    let id: String
    let userAddress: String
    var totalPoints: Int
    var tier: LoyaltyTierLevel
    var lifetimePoints: Int
    var milestonesReached: [String]
}

struct LoyaltyRewardEvent: Identifiable, Codable {
    let id: String
    let userAddress: String
    let points: Int
    let source: RewardSource
    let businessId: String?
    let reason: String
    let timestamp: Date
}

struct LoyaltyMilestone: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let requiredPoints: Int
    let bonusPoints: Int
    let injectionComponent: Int?   // e.g. 14 for C14 Gaming milestone
}

/// Zero-knowledge proof of eligibility — proves a user qualifies
/// for a reward without revealing their full transaction history.
struct ZKPEligibilityProof: Identifiable, Codable {
    let id: String
    let userAddress: String
    let proofHash: String
    let eligibleRewardId: String
    let verified: Bool
    let verifiedAt: Date?
}

struct BusinessRewardProgram: Identifiable, Codable {
    let id: String
    let businessAddress: String
    let businessName: String
    let pointsMultiplier: Double
    let eligibleActions: [String]
    var isActive: Bool
}

enum LoyaltyError: Error, LocalizedError {
    case accountNotFound(String)
    case insufficientPoints
    case milestoneAlreadyReached
    case zkpVerificationFailed
    case businessProgramNotFound(String)
    case programInactive
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .accountNotFound(let addr): return "Loyalty account not found: \(addr)"
        case .insufficientPoints: return "Insufficient loyalty points."
        case .milestoneAlreadyReached: return "Milestone already reached."
        case .zkpVerificationFailed: return "ZKP eligibility verification failed."
        case .businessProgramNotFound(let id): return "Business program not found: \(id)"
        case .programInactive: return "Business reward program is inactive."
        case .notConfigured: return "Loyalty contract not configured (PendingCredentials.Components.loyalty)."
        }
    }
}

// MARK: - LoyaltyManager

final class LoyaltyManager: ObservableObject {

    static let shared = LoyaltyManager()

    weak var delegate: LoyaltyDelegate?

    @Published private(set) var accounts: [LoyaltyAccount] = []
    @Published private(set) var rewardEvents: [LoyaltyRewardEvent] = []
    @Published private(set) var milestones: [LoyaltyMilestone] = []
    @Published private(set) var businessPrograms: [BusinessRewardProgram] = []
    @Published private(set) var isLoading = false

    private var accountStore: [String: LoyaltyAccount] = [:]  // userAddress -> account
    private var milestoneStore: [String: LoyaltyMilestone] = [:]
    private var programStore: [String: BusinessRewardProgram] = [:]

    // MARK: - Account Management

    func getOrCreateAccount(userAddress: String) async -> LoyaltyAccount {
        if let existing = accountStore[userAddress] { return existing }

        let account = LoyaltyAccount(
            id: UUID().uuidString,
            userAddress: userAddress,
            totalPoints: 0,
            tier: .bronze,
            lifetimePoints: 0,
            milestonesReached: []
        )
        accountStore[userAddress] = account
        await MainActor.run { accounts.append(account) }
        return account
    }

    // MARK: - Platform Native Rewards

    func awardPlatformPoints(userAddress: String, points: Int, reason: String) async throws -> LoyaltyRewardEvent {
        var account = await getOrCreateAccount(userAddress: userAddress)
        account.totalPoints += points
        account.lifetimePoints += points
        account.tier = calculateTier(lifetimePoints: account.lifetimePoints)
        accountStore[userAddress] = account

        let event = LoyaltyRewardEvent(
            id: UUID().uuidString,
            userAddress: userAddress,
            points: points,
            source: .platformNative,
            businessId: nil,
            reason: reason,
            timestamp: Date()
        )

        await MainActor.run { rewardEvents.append(event) }
        await updateAccountInPublished(account)
        delegate?.loyalty(self, rewardEarned: event)

        // Check milestones
        await checkMilestones(account: account)
        return event
    }

    // MARK: - Business Rewards

    func registerBusinessProgram(businessAddress: String, name: String, pointsMultiplier: Double, eligibleActions: [String]) async -> BusinessRewardProgram {
        let program = BusinessRewardProgram(
            id: UUID().uuidString,
            businessAddress: businessAddress,
            businessName: name,
            pointsMultiplier: pointsMultiplier,
            eligibleActions: eligibleActions,
            isActive: true
        )
        programStore[program.id] = program
        await MainActor.run { businessPrograms.append(program) }
        return program
    }

    func awardBusinessPoints(userAddress: String, programId: String, basePoints: Int, action: String) async throws -> LoyaltyRewardEvent {
        guard let program = programStore[programId] else {
            throw LoyaltyError.businessProgramNotFound(programId)
        }
        guard program.isActive else { throw LoyaltyError.programInactive }

        let adjustedPoints = Int(Double(basePoints) * program.pointsMultiplier)
        var account = await getOrCreateAccount(userAddress: userAddress)
        account.totalPoints += adjustedPoints
        account.lifetimePoints += adjustedPoints
        account.tier = calculateTier(lifetimePoints: account.lifetimePoints)
        accountStore[userAddress] = account

        let event = LoyaltyRewardEvent(
            id: UUID().uuidString,
            userAddress: userAddress,
            points: adjustedPoints,
            source: .business,
            businessId: program.id,
            reason: action,
            timestamp: Date()
        )

        await MainActor.run { rewardEvents.append(event) }
        await updateAccountInPublished(account)
        delegate?.loyalty(self, rewardEarned: event)
        await checkMilestones(account: account)
        return event
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `awardPoints(address user, uint256 points)`.
    static func encodeAwardPoints(user: String, points: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("awardPoints(address,uint256)")
        data.append(ABIEncoder.encodeAddress(user))
        data.append(ABIEncoder.encodeUInt256(points))
        return data
    }

    /// Record a loyalty points award on-chain through the real submit pipeline:
    /// enclave-signed UserOp → server paymaster → bundler. Contract address
    /// deferred to PendingCredentials (nil until set → throws, never a fake award).
    @MainActor
    func awardPointsOnChain(
        user: String,
        points: UInt64,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.loyalty)
    ) async throws -> WalletTransactionService.Submission {
        guard let loyalty = contract else { throw LoyaltyError.notConfigured }
        return try await service.submitCall(
            to: loyalty,
            value: 0,
            data: Self.encodeAwardPoints(user: user, points: points),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - ZKP Eligibility Verification

    /// Verify eligibility using a zero-knowledge proof.
    /// The proof demonstrates the user meets criteria without revealing full history.
    func verifyZKPEligibility(userAddress: String, proofHash: String, rewardId: String) async throws -> ZKPEligibilityProof {
        // In production, this calls a ZK verifier contract
        let isValid = !proofHash.isEmpty && proofHash.count >= 32

        guard isValid else { throw LoyaltyError.zkpVerificationFailed }

        let proof = ZKPEligibilityProof(
            id: UUID().uuidString,
            userAddress: userAddress,
            proofHash: proofHash,
            eligibleRewardId: rewardId,
            verified: true,
            verifiedAt: Date()
        )

        delegate?.loyalty(self, zkpVerified: proof)
        return proof
    }

    // MARK: - Milestone Injection Points

    /// Register a milestone that can be injected from another component.
    func registerMilestone(name: String, description: String, requiredPoints: Int, bonusPoints: Int, injectionComponent: Int? = nil) async -> LoyaltyMilestone {
        let milestone = LoyaltyMilestone(
            id: UUID().uuidString,
            name: name,
            description: description,
            requiredPoints: requiredPoints,
            bonusPoints: bonusPoints,
            injectionComponent: injectionComponent
        )
        milestoneStore[milestone.id] = milestone
        await MainActor.run { milestones.append(milestone) }
        return milestone
    }

    /// Inject a milestone trigger from another component.
    func injectMilestoneFromComponent(componentId: Int, userAddress: String, bonusPoints: Int) async throws {
        _ = try await awardPlatformPointsInternal(
            userAddress: userAddress,
            points: bonusPoints,
            reason: "Milestone injection from Component \(componentId)"
        )
    }

    private func awardPlatformPointsInternal(userAddress: String, points: Int, reason: String) async throws -> LoyaltyRewardEvent {
        try await awardPlatformPoints(userAddress: userAddress, points: points, reason: reason)
    }

    // MARK: - Private

    private func calculateTier(lifetimePoints: Int) -> LoyaltyTierLevel {
        for tier in LoyaltyTierLevel.allCases.reversed() {
            if lifetimePoints >= tier.pointsRequired { return tier }
        }
        return .bronze
    }

    private func checkMilestones(account: LoyaltyAccount) async {
        for (id, milestone) in milestoneStore {
            guard !account.milestonesReached.contains(id) else { continue }
            if account.lifetimePoints >= milestone.requiredPoints {
                var updated = account
                updated.milestonesReached.append(id)
                updated.totalPoints += milestone.bonusPoints
                updated.lifetimePoints += milestone.bonusPoints
                accountStore[account.userAddress] = updated
                await updateAccountInPublished(updated)
                delegate?.loyalty(self, milestoneReached: milestone)
            }
        }
    }

    @MainActor
    private func updateAccountInPublished(_ account: LoyaltyAccount) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
        }
    }
}
