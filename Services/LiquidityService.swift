// LiquidityService.swift
// MTRX — Liquidity pool operations via 0pnMatrx gateway

import Foundation

// MARK: - Models

struct LiquidityPool: Codable, Identifiable {
    var id: String { poolId }
    let poolId: String
    let token0: String
    let token1: String
    let fee: Double
    let apr: Double
    let tvl: Double
    let volume24h: Double

    private enum CodingKeys: String, CodingKey {
        case poolId, token0, token1, fee, apr, tvl, volume24h
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.poolId = try container.decode(String.self, forKey: .poolId)
        self.token0 = try container.decode(String.self, forKey: .token0)
        self.token1 = try container.decode(String.self, forKey: .token1)
        self.fee = (try? container.decode(Double.self, forKey: .fee)) ?? 0
        self.apr = (try? container.decode(Double.self, forKey: .apr)) ?? 0
        self.tvl = (try? container.decode(Double.self, forKey: .tvl)) ?? 0
        self.volume24h = (try? container.decode(Double.self, forKey: .volume24h)) ?? 0
    }
}

struct LPPosition: Codable, Identifiable {
    var id: String { positionId }
    let positionId: String
    let pool: String
    let token0Amount: Double
    let token1Amount: Double
    let unclaimedFees: Double
    let impermanentLoss: Double

    private enum CodingKeys: String, CodingKey {
        case positionId, pool, token0Amount, token1Amount, unclaimedFees, impermanentLoss
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.positionId = try container.decode(String.self, forKey: .positionId)
        self.pool = try container.decode(String.self, forKey: .pool)
        self.token0Amount = (try? container.decode(Double.self, forKey: .token0Amount)) ?? 0
        self.token1Amount = (try? container.decode(Double.self, forKey: .token1Amount)) ?? 0
        self.unclaimedFees = (try? container.decode(Double.self, forKey: .unclaimedFees)) ?? 0
        self.impermanentLoss = (try? container.decode(Double.self, forKey: .impermanentLoss)) ?? 0
    }
}

struct PriceRange: Codable {
    let lower: Double
    let upper: Double
}

// MARK: - LiquidityService

@MainActor
final class LiquidityService {
    static let shared = LiquidityService()
    private let client = MTRXAPIClient.shared

    private init() {}

    // MARK: - Pools

    func getPools() async throws -> [LiquidityPool] {
        let pools: [LiquidityPool] = try await client.get(
            path: "/api/v1/defi/liquidity/pools"
        )
        return pools
    }

    // MARK: - User Positions

    func getUserPositions(address: String) async throws -> [LPPosition] {
        let positions: [LPPosition] = try await client.get(
            path: "/api/v1/defi/liquidity/positions",
            queryItems: [URLQueryItem(name: "address", value: address)]
        )
        return positions
    }

    // MARK: - Add Liquidity

    func addLiquidity(poolId: String, amount0: String, amount1: String, priceRange: PriceRange) async throws -> TransactionResult {
        struct AddLiquidityRequest: Encodable {
            let poolId: String
            let amount0: String
            let amount1: String
            let priceRange: PriceRange
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/liquidity/add",
            body: AddLiquidityRequest(
                poolId: poolId,
                amount0: amount0,
                amount1: amount1,
                priceRange: priceRange
            )
        )
        return result
    }

    // MARK: - Remove Liquidity

    func removeLiquidity(positionId: String, percent: Int) async throws -> TransactionResult {
        struct RemoveLiquidityRequest: Encodable {
            let positionId: String
            let percent: Int
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/liquidity/remove",
            body: RemoveLiquidityRequest(positionId: positionId, percent: percent)
        )
        return result
    }
}
