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
    /// Read path can't run: neither the pool contract address
    /// (PendingCredentials.Components.deFiLending) nor the backend gateway
    /// (PendingCredentials.Backend.gatewayURL) is configured, or the RPC URL is
    /// blank. We return this rather than fabricating pool numbers.
    case notConfigured
    /// On-chain/gateway response was malformed or undecodable.
    case invalidResponse

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
        case .notConfigured: return "Lending pool data unavailable — set PendingCredentials.Components.deFiLending (+ Network.rpcURL) or PendingCredentials.Backend.gatewayURL."
        case .invalidResponse: return "Lending pool data could not be decoded."
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
    /// READ-ONLY chain access (eth_call). Optional so existing call sites that
    /// only need the display models keep compiling; when nil, contract reads
    /// fail gracefully with `.notConfigured`.
    private let network: BaseNetwork?
    /// Pool contract address for the on-chain read path. Deferred to
    /// PendingCredentials — blank → no real read is attempted.
    private let poolContract: String?
    /// Optional off-chain gateway base URL. When set it is preferred over the
    /// raw eth_call read path (server pre-decodes pool data). Resolved the same
    /// way as MTRXAPIClient: PendingCredentials → MTRX_RUNTIME_URL env.
    private let gatewayURL: String?
    /// Assets the read path queries when no explicit list is given. The pool
    /// contract is asked for each via `getPool(address)` (see fetchPools).
    private let readableAssets: [String]
    private var pools: [String: LendingPool] = [:]
    private var positions: [String: LendingPosition] = [:]
    private let processingQueue = DispatchQueue(label: "com.mtrx.defi.lending", qos: .userInitiated)

    /// URLSession for the optional backend-gateway read path.
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Initialization

    /// `network`, `poolContract`, and `gatewayURL` are injectable (tests) and
    /// otherwise resolved from PendingCredentials so nothing is hardcoded and
    /// every read degrades to a clear `.notConfigured` state while blank.
    init(erc4337Manager: ERC4337Manager,
         network: BaseNetwork? = nil,
         poolContract: String? = PendingCredentials.filled(PendingCredentials.Components.deFiLending),
         gatewayURL: String? = PendingCredentials.filled(PendingCredentials.Backend.gatewayURL)
            ?? ProcessInfo.processInfo.environment["MTRX_RUNTIME_URL"],
         readableAssets: [String] = ["USDC", "ETH", "DAI"]) {
        self.erc4337Manager = erc4337Manager
        self.network = network
        self.poolContract = poolContract
        self.gatewayURL = gatewayURL
        self.readableAssets = readableAssets
    }

    // MARK: - Pool Operations

    /// Fetch available lending pool data (collateral factor, APYs, reserves)
    /// over a READ-ONLY path. This is the only network-touching method here —
    /// the mutating methods below stay display-only/refusing.
    ///
    /// Source preference (no fabrication, ever):
    ///   1. Backend gateway, if `Backend.gatewayURL` is set (server pre-decodes
    ///      pool data into JSON) — preferred because it can return all pools in
    ///      one round-trip.
    ///   2. Otherwise the pool contract via `eth_call` (one read per asset),
    ///      which needs both the pool contract address AND `Network.rpcURL`.
    ///   3. If neither is configured, fail with `.notConfigured` — never a
    ///      stub list, never fabricated numbers.
    func fetchPools(completion: @escaping (Result<[LendingPool], DeFiLendingError>) -> Void) {
        if let gateway = gatewayURL {
            fetchPoolsFromGateway(base: gateway, completion: completion)
            return
        }
        guard let contract = poolContract, let network = network else {
            completion(.failure(.notConfigured))
            return
        }
        fetchPoolsOnChain(contract: contract, network: network, completion: completion)
    }

    // MARK: - Read path: backend gateway

    /// Off-chain read: `GET {base}/v1/lending/pools`. The server is the one that
    /// talks to the chain and pre-decodes the pool structs; we only map its
    /// honest JSON. Any transport/decode failure surfaces as an error — we never
    /// substitute placeholder pools.
    private func fetchPoolsFromGateway(base: String,
                                       completion: @escaping (Result<[LendingPool], DeFiLendingError>) -> Void) {
        guard let url = URL(string: base.hasSuffix("/") ? base + "v1/lending/pools" : base + "/v1/lending/pools") else {
            completion(.failure(.notConfigured))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(.networkError(underlying: error)))
                return
            }
            guard let data = data,
                  let dtos = try? JSONDecoder().decode([GatewayPoolDTO].self, from: data) else {
                completion(.failure(.invalidResponse))
                return
            }
            let mapped = dtos.map { $0.toLendingPool() }
            self.processingQueue.async {
                for pool in mapped { self.pools[pool.asset] = pool }
            }
            completion(.success(mapped))
        }.resume()
    }

    /// Wire DTO for the gateway read path. Mirrors `LendingPool`; values are
    /// produced server-side from real on-chain reads. Snake/camel tolerant via
    /// explicit CodingKeys.
    private struct GatewayPoolDTO: Decodable {
        let poolAddress: String
        let asset: String
        let totalDeposits: UInt64
        let totalBorrows: UInt64
        let supplyAPY: Double
        let borrowAPY: Double
        let collateralFactor: Double
        let liquidationThreshold: Double
        let liquidationPenalty: Double

        func toLendingPool() -> LendingPool {
            let utilization = totalDeposits > 0 ? Double(totalBorrows) / Double(totalDeposits) : 0
            return LendingPool(
                poolAddress: poolAddress, asset: asset,
                totalDeposits: totalDeposits, totalBorrows: totalBorrows,
                supplyAPY: supplyAPY, borrowAPY: borrowAPY,
                utilizationRate: utilization,
                collateralFactor: collateralFactor,
                liquidationThreshold: liquidationThreshold,
                liquidationPenalty: liquidationPenalty
            )
        }
    }

    // MARK: - Read path: on-chain eth_call

    /// On-chain read: query the pool contract per asset via `eth_call`. Reads
    /// are gas-free and unsigned, so this stays within the "display-only"
    /// contract — it never mutates state. `network.ethCall` itself fails
    /// gracefully (`.connectionFailed`) when `Network.rpcURL` is blank, which we
    /// translate to `.notConfigured`.
    ///
    /// BOUNDARY: the exact `getReserveData`/`getPool` view selector and the
    /// packed-struct layout depend on the deployed lending contract's ABI. We
    /// encode a conventional `getPool(string)` view and decode the first six
    /// 32-byte words in the documented order below. If your contract differs,
    /// adjust `encodeGetPool` and `decodePool` to match its ABI (the wiring,
    /// config-gating, and honesty guarantees are unaffected). Marked UNVERIFIED.
    private func fetchPoolsOnChain(contract: String,
                                   network: BaseNetwork,
                                   completion: @escaping (Result<[LendingPool], DeFiLendingError>) -> Void) {
        let group = DispatchGroup()
        var collected: [LendingPool] = []
        var firstError: DeFiLendingError?
        let lock = NSLock()

        for asset in readableAssets {
            group.enter()
            let callData = Self.hexString(Self.encodeGetPool(asset: asset))
            network.ethCall(to: contract, data: callData) { result in
                defer { group.leave() }
                switch result {
                case .success(let hex):
                    guard let pool = Self.decodePool(poolAddress: contract, asset: asset, returnHex: hex) else {
                        lock.lock(); if firstError == nil { firstError = .invalidResponse }; lock.unlock()
                        return
                    }
                    lock.lock(); collected.append(pool); lock.unlock()
                case .failure(let netError):
                    // Blank RPC surfaces here as connectionFailed — map to the
                    // honest needs-config state rather than a fabricated pool.
                    lock.lock()
                    if firstError == nil {
                        if case .connectionFailed = netError { firstError = .notConfigured }
                        else { firstError = .networkError(underlying: netError) }
                    }
                    lock.unlock()
                }
            }
        }

        group.notify(queue: processingQueue) { [weak self] in
            if collected.isEmpty, let error = firstError {
                completion(.failure(error))
                return
            }
            for pool in collected { self?.pools[pool.asset] = pool }
            completion(.success(collected))
        }
    }

    /// ABI-encode the read selector `getPool(string)`. The asset symbol is a
    /// dynamic `string` arg: head holds the offset (0x20), tail holds the
    /// length-prefixed, right-padded UTF-8 bytes.
    static func encodeGetPool(asset: String) -> Data {
        var data = ABIEncoder.functionSelector("getPool(string)")
        data.append(ABIEncoder.encodeOffset(32))           // offset to the string arg
        data.append(ABIEncoder.encodeBytes(Data(asset.utf8))) // length + padded bytes
        return data
    }

    /// Decode the packed pool struct returned by `getPool`. Expected word order
    /// (each a 32-byte big-endian word):
    ///   [0] totalDeposits (uint256)
    ///   [1] totalBorrows  (uint256)
    ///   [2] supplyAPY      (uint256, ray/1e27-style fixed point → fraction)
    ///   [3] borrowAPY      (uint256, same scale)
    ///   [4] collateralFactor     (uint256, basis points, 1e4 = 100%)
    ///   [5] liquidationThreshold (uint256, basis points)
    ///   [6] liquidationPenalty   (uint256, basis points) — optional
    /// Returns nil (→ `.invalidResponse`) if fewer than six words are present.
    /// We never invent missing fields.
    static func decodePool(poolAddress: String, asset: String, returnHex: String) -> LendingPool? {
        let words = hexWords(returnHex)
        guard words.count >= 6 else { return nil }

        let totalDeposits = words[0]
        let totalBorrows  = words[1]
        // APYs are returned as ray-scaled fixed point on most lending protocols
        // (1e27 = 100%). Convert to a plain fraction for display.
        let supplyAPY = Double(words[2]) / 1e27
        let borrowAPY = Double(words[3]) / 1e27
        // Risk parameters are basis points (1e4 = 100%).
        let collateralFactor     = Double(words[4]) / 1e4
        let liquidationThreshold = Double(words[5]) / 1e4
        let liquidationPenalty   = words.count >= 7 ? Double(words[6]) / 1e4 : 0
        let utilization = totalDeposits > 0 ? Double(totalBorrows) / Double(totalDeposits) : 0

        return LendingPool(
            poolAddress: poolAddress, asset: asset,
            totalDeposits: totalDeposits, totalBorrows: totalBorrows,
            supplyAPY: supplyAPY, borrowAPY: borrowAPY,
            utilizationRate: utilization,
            collateralFactor: collateralFactor,
            liquidationThreshold: liquidationThreshold,
            liquidationPenalty: liquidationPenalty
        )
    }

    /// `0x`-prefix hex-encode calldata for `eth_call` (which takes a hex String).
    private static func hexString(_ data: Data) -> String {
        "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    /// Split an `eth_call` hex return (`0x` + N*64 hex chars) into UInt64 words.
    /// Each ABI word is 32 bytes; we read the low 8 bytes (sufficient for the
    /// magnitudes used here) as a big-endian UInt64. Returns [] on malformed
    /// input so callers fail with `.invalidResponse` rather than guessing.
    private static func hexWords(_ hex: String) -> [UInt64] {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard !clean.isEmpty, clean.count % 64 == 0 else { return [] }
        var words: [UInt64] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let wordEnd = clean.index(index, offsetBy: 64)
            let word = clean[index..<wordEnd]
            // Low 16 hex chars (8 bytes) of the 32-byte word.
            let low = word.suffix(16)
            guard let value = UInt64(low, radix: 16) else { return [] }
            words.append(value)
            index = wordEnd
        }
        return words
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
