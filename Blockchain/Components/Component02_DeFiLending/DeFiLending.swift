// DeFiLending.swift
// MTRX Blockchain - Components - DeFi Lending
//
// DeFi lending protocol integration: collateral, borrowing, liquidation

import Foundation

// MARK: - Protocols

protocol DeFiLendingDelegate: AnyObject {
    func lending(_ manager: DeFiLending, didDeposit amount: UInt64, asset: String)
    func lending(_ manager: DeFiLending, didBorrow amount: UInt64, asset: String)
    func lending(_ manager: DeFiLending, liquidationWarning position: LendingPosition)
    func lending(_ manager: DeFiLending, didFailWithError error: DeFiLendingError)
}

// MARK: - Data Models

struct LendingPool {
    let poolAddress: String
    let asset: String
    let totalDeposits: UInt64
    let totalBorrows: UInt64
    let supplyAPY: Double
    let borrowAPY: Double
    let utilizationRate: Double
    let collateralFactor: Double
    let liquidationThreshold: Double
    let liquidationPenalty: Double
}

struct LendingPosition {
    let positionId: String
    let userAddress: String
    let collateralAsset: String
    let collateralAmount: UInt64
    let borrowAsset: String
    let borrowAmount: UInt64
    let healthFactor: Double
    let interestAccrued: UInt64
    let createdAt: Date

    var isAtRisk: Bool { healthFactor < 1.2 }
    var isLiquidatable: Bool { healthFactor < 1.0 }
}

struct LiquidationEvent {
    let positionId: String
    let liquidator: String
    let collateralSeized: UInt64
    let debtRepaid: UInt64
    let penalty: UInt64
    let timestamp: Date
}

enum DeFiLendingError: Error, LocalizedError {
    case insufficientCollateral
    case poolNotFound(asset: String)
    case borrowLimitExceeded
    case liquidationFailed
    case repaymentExceedsDebt
    case priceOracleError
    case networkError(underlying: Error)
    case displayOnly

    var errorDescription: String? {
        switch self {
        case .insufficientCollateral: return "Insufficient collateral for this borrow."
        case .poolNotFound(let a): return "Lending pool not found for asset: \(a)"
        case .borrowLimitExceeded: return "Borrow limit exceeded."
        case .liquidationFailed: return "Liquidation execution failed."
        case .repaymentExceedsDebt: return "Repayment amount exceeds outstanding debt."
        case .priceOracleError: return "Failed to fetch price from oracle."
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .displayOnly: return "Lending is display-only in this build — execute it yourself in self-custody on the protocol's own interface."
        }
    }
}

// MARK: - DeFiLending
//
// REGULATED COMPONENT — DISPLAY-ONLY.
// Lending/borrowing is a regulated financial activity. This build provides
// read/display only (pools, positions, health factor). It performs NO in-app
// execution — not custodial, and not even user-signed self-custody — so that the
// app never originates a regulated lending transaction. The mutating methods
// below intentionally refuse with `.displayOnly`. (Also gated by
// FeatureFlags.mvpMode upstream.) Wiring a self-custody path later would be a
// one-line route through WalletTransactionService, identical to the
// non-regulated components — left out deliberately.

final class DeFiLending {

    // MARK: - Properties

    weak var delegate: DeFiLendingDelegate?

    private let erc4337Manager: ERC4337Manager
    private var pools: [String: LendingPool] = [:]
    private var positions: [String: LendingPosition] = [:]
    private let processingQueue = DispatchQueue(label: "com.mtrx.defi.lending", qos: .userInitiated)

    // MARK: - Initialization

    init(erc4337Manager: ERC4337Manager) {
        self.erc4337Manager = erc4337Manager
    }

    // MARK: - Pool Operations

    /// Fetch available lending pools
    func fetchPools(completion: @escaping (Result<[LendingPool], DeFiLendingError>) -> Void) {
        // TODO: Query lending protocol contracts for pool data
        completion(.success(Array(pools.values)))
    }

    /// Get details for a specific lending pool
    func getPool(asset: String) -> Result<LendingPool, DeFiLendingError> {
        guard let pool = pools[asset] else { return .failure(.poolNotFound(asset: asset)) }
        return .success(pool)
    }

    // MARK: - Deposit / Withdraw

    /// Deposit collateral — REGULATED display-only: refuses (no in-app execution).
    func deposit(asset: String, amount: UInt64, completion: @escaping (Result<String, DeFiLendingError>) -> Void) {
        completion(.failure(.displayOnly))
    }

    /// Withdraw collateral — REGULATED display-only: refuses (no in-app execution).
    func withdraw(asset: String, amount: UInt64, completion: @escaping (Result<String, DeFiLendingError>) -> Void) {
        completion(.failure(.displayOnly))
    }

    // MARK: - Borrow / Repay

    /// Borrow — REGULATED display-only: refuses (no in-app execution).
    func borrow(asset: String, amount: UInt64, completion: @escaping (Result<LendingPosition, DeFiLendingError>) -> Void) {
        completion(.failure(.displayOnly))
    }

    /// Repay — REGULATED display-only: refuses (no in-app execution).
    func repay(positionId: String, amount: UInt64, completion: @escaping (Result<LendingPosition, DeFiLendingError>) -> Void) {
        completion(.failure(.displayOnly))
    }

    // MARK: - Liquidation

    /// Check positions for liquidation risk
    func checkLiquidations() -> [LendingPosition] {
        return positions.values.filter { $0.isLiquidatable }
    }

    /// Liquidation — REGULATED display-only: refuses (no in-app execution).
    func liquidate(positionId: String, completion: @escaping (Result<LiquidationEvent, DeFiLendingError>) -> Void) {
        completion(.failure(.displayOnly))
    }

    // MARK: - Health Factor

    /// Calculate health factor for a position
    func calculateHealthFactor(position: LendingPosition) -> Double {
        guard let pool = pools[position.collateralAsset] else { return 0 }
        // healthFactor = (collateralValue * liquidationThreshold) / borrowValue
        let collateralValue = Double(position.collateralAmount)
        let borrowValue = Double(position.borrowAmount + position.interestAccrued)
        guard borrowValue > 0 else { return Double.infinity }
        return (collateralValue * pool.liquidationThreshold) / borrowValue
    }

    /// Get all user positions
    func getPositions(for userAddress: String) -> [LendingPosition] {
        return positions.values.filter { $0.userAddress == userAddress }
    }
}
