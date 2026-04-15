// StakingService.swift
// MTRX — Staking operations via 0pnMatrx gateway

import Foundation

// MARK: - Models

struct StakingOption: Codable, Identifiable {
    var id: String { poolId }
    let poolId: String
    let name: String
    let token: String
    let rewardToken: String
    let apy: Double
    let lockPeriodDays: Int
    let minStake: Double

    private enum CodingKeys: String, CodingKey {
        case poolId, name, token, rewardToken, apy, lockPeriodDays, minStake
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.poolId = try container.decode(String.self, forKey: .poolId)
        self.name = try container.decode(String.self, forKey: .name)
        self.token = try container.decode(String.self, forKey: .token)
        self.rewardToken = (try? container.decode(String.self, forKey: .rewardToken)) ?? ""
        self.apy = (try? container.decode(Double.self, forKey: .apy)) ?? 0
        self.lockPeriodDays = (try? container.decode(Int.self, forKey: .lockPeriodDays)) ?? 0
        self.minStake = (try? container.decode(Double.self, forKey: .minStake)) ?? 0
    }
}

struct StakePosition: Codable, Identifiable {
    var id: String { stakeId }
    let stakeId: String
    let pool: String
    let stakedAmount: Double
    let rewardAmount: Double
    let unbondingAmount: Double
    let unbondingAvailableAt: Date?

    private enum CodingKeys: String, CodingKey {
        case stakeId, pool, stakedAmount, rewardAmount, unbondingAmount, unbondingAvailableAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stakeId = try container.decode(String.self, forKey: .stakeId)
        self.pool = try container.decode(String.self, forKey: .pool)
        self.stakedAmount = (try? container.decode(Double.self, forKey: .stakedAmount)) ?? 0
        self.rewardAmount = (try? container.decode(Double.self, forKey: .rewardAmount)) ?? 0
        self.unbondingAmount = (try? container.decode(Double.self, forKey: .unbondingAmount)) ?? 0
        self.unbondingAvailableAt = try? container.decode(Date.self, forKey: .unbondingAvailableAt)
    }
}

// MARK: - StakingService

@MainActor
final class StakingService {
    static let shared = StakingService()
    private let client = MTRXAPIClient.shared

    private init() {}

    // MARK: - Staking Options

    func getStakingOptions() async throws -> [StakingOption] {
        let options: [StakingOption] = try await client.get(
            path: "/api/v1/defi/staking/options"
        )
        return options
    }

    // MARK: - User Stakes

    func getUserStakes(address: String) async throws -> [StakePosition] {
        let stakes: [StakePosition] = try await client.get(
            path: "/api/v1/defi/staking/positions",
            queryItems: [URLQueryItem(name: "address", value: address)]
        )
        return stakes
    }

    // MARK: - Stake

    func stake(token: String, amount: String, poolId: String) async throws -> TransactionResult {
        struct StakeRequest: Encodable {
            let token: String
            let amount: String
            let poolId: String
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/staking/stake",
            body: StakeRequest(token: token, amount: amount, poolId: poolId)
        )
        return result
    }

    // MARK: - Unstake

    func unstake(stakeId: String, amount: String) async throws -> TransactionResult {
        struct UnstakeRequest: Encodable {
            let stakeId: String
            let amount: String
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/staking/unstake",
            body: UnstakeRequest(stakeId: stakeId, amount: amount)
        )
        return result
    }

    // MARK: - Claim Rewards

    func claimRewards(stakeId: String) async throws -> TransactionResult {
        struct ClaimRequest: Encodable {
            let stakeId: String
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/staking/claim",
            body: ClaimRequest(stakeId: stakeId)
        )
        return result
    }
}
