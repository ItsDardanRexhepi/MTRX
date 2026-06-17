// DEXManager.swift
// MTRX Blockchain - Components - DEX (C21)
//
// Zero-fee trading via Uniswap v3/v4 on Base, platform absorbs LP fees,
// all prices sourced from C11 oracle.

import Foundation
import Combine

// MARK: - Protocols

protocol DEXDelegate: AnyObject {
    func dex(_ manager: DEXManager, swapCompleted swap: DEXSwap)
    func dex(_ manager: DEXManager, liquidityProvided event: LiquidityProvision)
    func dex(_ manager: DEXManager, priceUpdated pair: String, price: Double)
}

// MARK: - Data Models

enum UniswapVersion: String, Codable {
    case v3, v4
}

struct DEXPool: Identifiable, Codable {
    let id: String
    let token0: String
    let token1: String
    let contractAddress: String
    let uniswapVersion: UniswapVersion
    var reserve0: Double
    var reserve1: Double
    var totalLiquidity: Double
    let lpFeeRate: Double          // e.g. 0.003 — absorbed by platform
    var volume24h: Double
    var currentPrice: Double       // from C11 oracle
}

struct DEXSwap: Identifiable, Codable {
    let id: String
    let poolId: String
    let userAddress: String
    let tokenIn: String
    let tokenOut: String
    let amountIn: Double
    let amountOut: Double
    let userFee: Double            // always 0 — zero-fee to user
    let platformAbsorbedFee: Double // platform pays LP fee
    let oraclePrice: Double
    let executedAt: Date
    let txHash: String?
}

struct LiquidityProvision: Identifiable, Codable {
    let id: String
    let poolId: String
    let providerAddress: String
    let amount0: Double
    let amount1: Double
    let lpTokensMinted: Double
    let timestamp: Date
    let isRemoval: Bool
}

enum DEXError: Error, LocalizedError {
    case poolNotFound(String)
    case insufficientLiquidity
    case oraclePriceUnavailable(String)
    case slippageExceeded
    case swapFailed(String)
    case invalidAmount
    case displayOnly

    var errorDescription: String? {
        switch self {
        case .poolNotFound(let id): return "Pool not found: \(id)"
        case .insufficientLiquidity: return "Insufficient liquidity in pool."
        case .oraclePriceUnavailable(let pair): return "Oracle price unavailable for \(pair)."
        case .slippageExceeded: return "Price slippage exceeds tolerance."
        case .swapFailed(let r): return "Swap failed: \(r)"
        case .invalidAmount: return "Amount must be greater than zero."
        case .displayOnly: return "DEX swaps are display-only in this build — swap yourself in self-custody on the DEX's own interface."
        }
    }
}

// MARK: - DEXManager
//
// REGULATED COMPONENT — DISPLAY-ONLY.
// Operating an exchange / facilitating token swaps can constitute regulated
// activity. This build displays pools, quotes and price data but performs NO
// in-app execution. swap/addLiquidity refuse with `.displayOnly` rather than
// fabricating reserve changes. Quote math (calculateSwapOutput) stays for
// display. Gated by FeatureFlags.mvpMode upstream.

final class DEXManager: ObservableObject {

    static let shared = DEXManager()

    /// User pays zero fees. Platform absorbs LP fees.
    static let userFeeRate: Double = 0.0
    static let chain = "Base"

    weak var delegate: DEXDelegate?

    @Published private(set) var pools: [DEXPool] = []
    @Published private(set) var swaps: [DEXSwap] = []
    @Published private(set) var isLoading = false

    private var poolStore: [String: DEXPool] = [:]
    /// Oracle price cache — must be populated from C11 OracleComponent.
    private var oraclePrices: [String: Double] = [:]   // "ETH/USDC" -> price

    // MARK: - Oracle Integration (C11)

    /// Set oracle price for a pair. Must be called by C11 or its adapter.
    func setOraclePrice(pair: String, price: Double) {
        oraclePrices[pair] = price
    }

    func getOraclePrice(pair: String) -> Double? {
        oraclePrices[pair]
    }

    // MARK: - Pool Management

    func createPool(token0: String, token1: String, contractAddress: String, version: UniswapVersion, lpFeeRate: Double = 0.003) async throws -> DEXPool {
        let pair = "\(token0)/\(token1)"
        guard let price = oraclePrices[pair] else {
            throw DEXError.oraclePriceUnavailable(pair)
        }

        let pool = DEXPool(
            id: UUID().uuidString,
            token0: token0,
            token1: token1,
            contractAddress: contractAddress,
            uniswapVersion: version,
            reserve0: 0,
            reserve1: 0,
            totalLiquidity: 0,
            lpFeeRate: lpFeeRate,
            volume24h: 0,
            currentPrice: price
        )

        poolStore[pool.id] = pool
        await MainActor.run { pools.append(pool) }
        return pool
    }

    // MARK: - Zero-Fee Swaps

    /// Execute a swap. User pays zero fees; platform absorbs LP cost.
    /// Swap — REGULATED display-only: refuses (no in-app execution). Previously
    /// simulated a constant-product swap and mutated reserves; that is removed.
    func swap(poolId: String, userAddress: String, tokenIn: String, amountIn: Double, minAmountOut: Double) async throws -> DEXSwap {
        throw DEXError.displayOnly
    }

    /// Constant-product AMM with LP fee absorbed by platform.
    private func calculateSwapOutput(pool: DEXPool, tokenIn: String, amountIn: Double) throws -> (amountOut: Double, platformFee: Double) {
        let (reserveIn, reserveOut): (Double, Double) = tokenIn == pool.token0
            ? (pool.reserve0, pool.reserve1)
            : (pool.reserve1, pool.reserve0)

        guard reserveIn > 0 && reserveOut > 0 else {
            throw DEXError.insufficientLiquidity
        }

        // LP fee is deducted from input but paid by platform
        let effectiveInput = amountIn * (1.0 - pool.lpFeeRate)
        let platformFee = amountIn * pool.lpFeeRate

        let numerator = effectiveInput * reserveOut
        let denominator = reserveIn + effectiveInput
        let amountOut = numerator / denominator

        guard amountOut < reserveOut else {
            throw DEXError.insufficientLiquidity
        }

        return (amountOut, platformFee)
    }

    // MARK: - Liquidity

    /// Add liquidity — REGULATED display-only: refuses (no in-app execution).
    func addLiquidity(poolId: String, provider: String, amount0: Double, amount1: Double) async throws -> LiquidityProvision {
        throw DEXError.displayOnly
    }

    /// Remove liquidity — REGULATED display-only: refuses (no in-app execution).
    func removeLiquidity(poolId: String, provider: String, lpTokens: Double) async throws -> LiquidityProvision {
        throw DEXError.displayOnly
    }

    // MARK: - Queries

    func getPool(id: String) -> DEXPool? { poolStore[id] }

    func getPoolByPair(token0: String, token1: String) -> DEXPool? {
        poolStore.values.first {
            ($0.token0 == token0 && $0.token1 == token1) ||
            ($0.token0 == token1 && $0.token1 == token0)
        }
    }

    func getSwaps(userAddress: String) -> [DEXSwap] {
        swaps.filter { $0.userAddress == userAddress }
    }

    func totalPlatformAbsorbedFees() -> Double {
        swaps.reduce(0) { $0 + $1.platformAbsorbedFee }
    }

    // MARK: - Private

    @MainActor
    private func updatePoolInPublished(_ pool: DEXPool) {
        if let idx = pools.firstIndex(where: { $0.id == pool.id }) {
            pools[idx] = pool
        }
    }
}
