// CashbackManager.swift
// MTRX Blockchain - Components - Cashback
//
// On-chain cashback: transaction rewards, tiered rates, claim processing

import Foundation
import Combine

// MARK: - Data Models

struct CashbackProgram: Identifiable, Codable {
    let id: String
    let name: String
    let merchantAddress: String
    let baseRate: Double // e.g. 0.01 for 1%
    let maxRate: Double
    let rewardToken: String
    let tiers: [CashbackTier]
    var isActive: Bool
}

struct CashbackTier: Identifiable, Codable {
    let id: String
    let name: String
    let minSpend: Double
    let rate: Double
}

struct CashbackReward: Identifiable, Codable {
    let id: String
    let userAddress: String
    let programId: String
    let purchaseAmount: Double
    let cashbackAmount: Double
    let rewardToken: String
    let earnedAt: Date
    var isClaimed: Bool
    let transactionRef: String?
}

enum CashbackError: Error, LocalizedError {
    case programNotFound(String)
    case noPendingRewards
    case claimFailed(String)
    case programInactive

    var errorDescription: String? {
        switch self {
        case .programNotFound(let id): return "Cashback program not found: \(id)"
        case .noPendingRewards: return "No pending cashback rewards."
        case .claimFailed(let r): return "Claim failed: \(r)"
        case .programInactive: return "Cashback program is inactive."
        }
    }
}

// MARK: - CashbackManager

final class CashbackManager: ObservableObject {

    static let shared = CashbackManager()

    @Published private(set) var programs: [CashbackProgram] = []
    @Published private(set) var pendingRewards: [CashbackReward] = []
    @Published private(set) var claimedRewards: [CashbackReward] = []

    private var programStore: [String: CashbackProgram] = [:]
    private var rewardStore: [String: CashbackReward] = [:]

    // MARK: - Programs

    func createProgram(name: String, merchant: String, baseRate: Double, maxRate: Double, rewardToken: String, tiers: [CashbackTier]) async throws -> CashbackProgram {
        let program = CashbackProgram(
            id: UUID().uuidString, name: name, merchantAddress: merchant,
            baseRate: baseRate, maxRate: maxRate, rewardToken: rewardToken,
            tiers: tiers, isActive: true
        )
        programStore[program.id] = program
        await MainActor.run { programs.append(program) }
        return program
    }

    // MARK: - Earning

    func processPurchase(programId: String, user: String, purchaseAmount: Double, transactionRef: String? = nil) async throws -> CashbackReward {
        guard let program = programStore[programId], program.isActive else {
            throw CashbackError.programNotFound(programId)
        }

        let rate = calculateRate(program: program, user: user)
        let cashbackAmount = purchaseAmount * rate

        let reward = CashbackReward(
            id: UUID().uuidString, userAddress: user, programId: programId,
            purchaseAmount: purchaseAmount, cashbackAmount: cashbackAmount,
            rewardToken: program.rewardToken, earnedAt: Date(),
            isClaimed: false, transactionRef: transactionRef
        )

        rewardStore[reward.id] = reward
        await MainActor.run { pendingRewards.append(reward) }
        return reward
    }

    // MARK: - Claiming

    func claimRewards(user: String) async throws -> Double {
        let pending = rewardStore.values.filter { $0.userAddress == user && !$0.isClaimed }
        guard !pending.isEmpty else { throw CashbackError.noPendingRewards }

        var totalClaimed: Double = 0
        for reward in pending {
            var r = reward
            r.isClaimed = true
            rewardStore[r.id] = r
            totalClaimed += r.cashbackAmount
        }

        await MainActor.run {
            pendingRewards.removeAll { $0.userAddress == user }
            claimedRewards.append(contentsOf: pending)
        }

        return totalClaimed
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `claim(address user)`.
    static func encodeClaim(user: String) -> Data {
        var data = ABIEncoder.functionSelector("claim(address)")
        data.append(ABIEncoder.encodeAddress(user))
        return data
    }

    /// Claim accrued cashback on-chain through the real submit pipeline:
    /// enclave-signed UserOp → server paymaster → bundler. Contract address
    /// deferred to PendingCredentials (nil until set → throws, never a fake claim).
    @MainActor
    func claimOnChain(
        user: String,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.cashback)
    ) async throws -> WalletTransactionService.Submission {
        guard let cashback = contract else {
            throw CashbackError.claimFailed("Cashback contract not configured (PendingCredentials.Components.cashback)")
        }
        return try await service.submitCall(
            to: cashback,
            value: 0,
            data: Self.encodeClaim(user: user),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    func getPendingTotal(user: String) -> Double {
        rewardStore.values
            .filter { $0.userAddress == user && !$0.isClaimed }
            .reduce(0) { $0 + $1.cashbackAmount }
    }

    // MARK: - Private

    private func calculateRate(program: CashbackProgram, user: String) -> Double {
        let totalSpend = rewardStore.values
            .filter { $0.userAddress == user && $0.programId == program.id }
            .reduce(0) { $0 + $1.purchaseAmount }

        let applicableTier = program.tiers
            .filter { totalSpend >= $0.minSpend }
            .max { $0.rate < $1.rate }

        return min(applicableTier?.rate ?? program.baseRate, program.maxRate)
    }
}
