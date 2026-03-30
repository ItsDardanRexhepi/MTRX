// StakingManager.swift
// MTRX Blockchain - Components - Staking (C16)
//
// Staking with 5% flat commission, 1 ETH minimum,
// canonical APY calculator (single source of truth for the whole platform).

import Foundation
import Combine

// MARK: - Protocols

protocol StakingDelegate: AnyObject {
    func staking(_ manager: StakingManager, stakeCreated stake: StakePosition)
    func staking(_ manager: StakingManager, rewardsClaimed reward: StakingRewardEvent)
    func staking(_ manager: StakingManager, unstakeCompleted stake: StakePosition)
}

// MARK: - Data Models

enum StakeStatus: String, Codable {
    case active, pendingUnstake, unstaked, slashed
}

struct StakePosition: Identifiable, Codable {
    let id: String
    let stakerAddress: String
    let amountETH: Double
    let stakedAt: Date
    var status: StakeStatus
    var accruedRewards: Double
    var lastRewardCalculation: Date
}

struct StakingRewardEvent: Identifiable, Codable {
    let id: String
    let stakeId: String
    let grossReward: Double
    let commission: Double     // 5% flat
    let netReward: Double
    let claimedAt: Date
    let txHash: String?
}

/// Canonical APY snapshot used by C20 Dashboard and any other component.
struct APYSnapshot: Codable {
    let calculatedAt: Date
    let baseAPY: Double
    let effectiveAPY: Double       // after 5% commission
    let totalStakedETH: Double
    let validatorCount: Int
    let networkRewardRate: Double
}

enum StakingError: Error, LocalizedError {
    case belowMinimumStake
    case stakeNotFound(String)
    case alreadyUnstaking
    case insufficientRewards
    case calculationFailed(String)

    var errorDescription: String? {
        switch self {
        case .belowMinimumStake: return "Minimum stake is 1 ETH."
        case .stakeNotFound(let id): return "Stake not found: \(id)"
        case .alreadyUnstaking: return "Unstake already in progress."
        case .insufficientRewards: return "No rewards accrued yet."
        case .calculationFailed(let r): return "APY calculation failed: \(r)"
        }
    }
}

// MARK: - StakingManager

final class StakingManager: ObservableObject {

    static let shared = StakingManager()

    /// Platform commission on staking rewards.
    static let commissionRate: Double = 0.05      // 5% flat
    /// Minimum stake in ETH.
    static let minimumStakeETH: Double = 1.0

    weak var delegate: StakingDelegate?

    @Published private(set) var stakes: [StakePosition] = []
    @Published private(set) var rewardEvents: [StakingRewardEvent] = []
    @Published private(set) var isLoading = false

    /// Canonical APY — single source of truth for the entire platform.
    /// C20 Dashboard and any other component must read from here.
    @Published private(set) var currentAPY: APYSnapshot?

    private var stakeStore: [String: StakePosition] = [:]

    // MARK: - Canonical APY Calculator

    /// Recalculate APY. This is the SINGLE SOURCE OF TRUTH for the platform.
    /// All components (especially C20 Dashboard) must consume this value rather
    /// than computing their own.
    func recalculateAPY(networkRewardRate: Double, validatorCount: Int) async -> APYSnapshot {
        let totalStaked = stakeStore.values
            .filter { $0.status == .active }
            .reduce(0.0) { $0 + $1.amountETH }

        let baseAPY = networkRewardRate * 100.0  // e.g. 0.045 -> 4.5%
        let effectiveAPY = baseAPY * (1.0 - Self.commissionRate)

        let snapshot = APYSnapshot(
            calculatedAt: Date(),
            baseAPY: baseAPY,
            effectiveAPY: effectiveAPY,
            totalStakedETH: totalStaked,
            validatorCount: validatorCount,
            networkRewardRate: networkRewardRate
        )

        await MainActor.run { currentAPY = snapshot }
        return snapshot
    }

    /// Public read-only accessor for other components.
    func getCanonicalAPY() -> APYSnapshot? {
        currentAPY
    }

    // MARK: - Staking

    /// Stake ETH. Minimum 1 ETH.
    func stake(stakerAddress: String, amountETH: Double) async throws -> StakePosition {
        guard amountETH >= Self.minimumStakeETH else {
            throw StakingError.belowMinimumStake
        }

        let position = StakePosition(
            id: UUID().uuidString,
            stakerAddress: stakerAddress,
            amountETH: amountETH,
            stakedAt: Date(),
            status: .active,
            accruedRewards: 0,
            lastRewardCalculation: Date()
        )

        stakeStore[position.id] = position
        await MainActor.run { stakes.append(position) }
        delegate?.staking(self, stakeCreated: position)
        return position
    }

    /// Initiate unstake.
    func unstake(stakeId: String) async throws -> StakePosition {
        guard var position = stakeStore[stakeId] else {
            throw StakingError.stakeNotFound(stakeId)
        }
        guard position.status == .active else {
            throw StakingError.alreadyUnstaking
        }

        position.status = .pendingUnstake
        stakeStore[stakeId] = position
        await updatePositionInPublished(position)
        return position
    }

    /// Finalise unstake after cooldown.
    func finaliseUnstake(stakeId: String) async throws -> StakePosition {
        guard var position = stakeStore[stakeId] else {
            throw StakingError.stakeNotFound(stakeId)
        }
        guard position.status == .pendingUnstake else {
            throw StakingError.stakeNotFound(stakeId)
        }

        position.status = .unstaked
        stakeStore[stakeId] = position
        await updatePositionInPublished(position)
        delegate?.staking(self, unstakeCompleted: position)
        return position
    }

    // MARK: - Rewards

    /// Accrue rewards for a stake based on time elapsed and canonical APY.
    func accrueRewards(stakeId: String) async throws {
        guard var position = stakeStore[stakeId], position.status == .active else {
            throw StakingError.stakeNotFound(stakeId)
        }
        guard let apy = currentAPY else {
            throw StakingError.calculationFailed("No APY snapshot available.")
        }

        let elapsed = Date().timeIntervalSince(position.lastRewardCalculation)
        let yearSeconds: Double = 365.25 * 24 * 3600
        let grossReward = position.amountETH * (apy.baseAPY / 100.0) * (elapsed / yearSeconds)
        let netReward = grossReward * (1.0 - Self.commissionRate)

        position.accruedRewards += netReward
        position.lastRewardCalculation = Date()
        stakeStore[stakeId] = position
        await updatePositionInPublished(position)
    }

    /// Claim accrued rewards. 5% commission deducted.
    func claimRewards(stakeId: String) async throws -> StakingRewardEvent {
        guard var position = stakeStore[stakeId] else {
            throw StakingError.stakeNotFound(stakeId)
        }
        guard position.accruedRewards > 0 else {
            throw StakingError.insufficientRewards
        }

        let gross = position.accruedRewards / (1.0 - Self.commissionRate)
        let commission = gross * Self.commissionRate
        let net = position.accruedRewards

        let event = StakingRewardEvent(
            id: UUID().uuidString,
            stakeId: stakeId,
            grossReward: gross,
            commission: commission,
            netReward: net,
            claimedAt: Date(),
            txHash: nil
        )

        position.accruedRewards = 0
        stakeStore[stakeId] = position

        await MainActor.run {
            rewardEvents.append(event)
        }
        await updatePositionInPublished(position)
        delegate?.staking(self, rewardsClaimed: event)
        return event
    }

    // MARK: - Queries

    func getStakes(for address: String) -> [StakePosition] {
        stakeStore.values.filter { $0.stakerAddress == address }
    }

    func getTotalStaked() -> Double {
        stakeStore.values
            .filter { $0.status == .active }
            .reduce(0.0) { $0 + $1.amountETH }
    }

    // MARK: - Private

    @MainActor
    private func updatePositionInPublished(_ position: StakePosition) {
        if let idx = stakes.firstIndex(where: { $0.id == position.id }) {
            stakes[idx] = position
        }
    }
}
