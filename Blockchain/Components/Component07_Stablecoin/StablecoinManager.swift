// StablecoinManager.swift
// MTRX Blockchain - Components - Stablecoin
//
// Stablecoin operations: USDC/DAI integration, stability mechanisms

import Foundation

// MARK: - Protocols

protocol StablecoinManagerDelegate: AnyObject {
    func stablecoin(_ manager: StablecoinManager, didTransfer amount: UInt64, token: String)
    func stablecoin(_ manager: StablecoinManager, didSwap fromToken: String, toToken: String, amount: UInt64)
    func stablecoin(_ manager: StablecoinManager, didFailWithError error: StablecoinError)
}

// MARK: - Data Models

struct StablecoinToken {
    let symbol: String
    let name: String
    let contractAddress: String
    let decimals: Int
    let issuer: String
    let totalSupply: UInt64
    let pegTarget: Double // e.g., 1.0 for USD peg
    let currentPrice: Double
    let isSupported: Bool
}

struct StablecoinBalance {
    let token: String
    let balance: UInt64
    let balanceFormatted: String
    let valueUSD: Double
}

enum StablecoinError: Error, LocalizedError {
    case unsupportedToken(symbol: String)
    case insufficientBalance
    case transferFailed
    case swapFailed(reason: String)
    case depegDetected(token: String, price: Double)
    case approvalFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedToken(let s): return "Unsupported stablecoin: \(s)"
        case .insufficientBalance: return "Insufficient stablecoin balance."
        case .transferFailed: return "Transfer failed."
        case .swapFailed(let r): return "Swap failed: \(r)"
        case .depegDetected(let t, let p): return "\(t) depeg detected. Price: \(p)"
        case .approvalFailed: return "Token approval failed."
        }
    }
}

// MARK: - StablecoinManager

final class StablecoinManager {

    // MARK: - Properties

    weak var delegate: StablecoinManagerDelegate?

    private let erc4337Manager: ERC4337Manager
    private var supportedTokens: [String: StablecoinToken] = [:]
    private var balances: [String: [StablecoinBalance]] = [:] // address -> balances
    private let depegThreshold: Double = 0.02 // 2% deviation
    private let processingQueue = DispatchQueue(label: "com.mtrx.stablecoin", qos: .userInitiated)

    // MARK: - Base Contract Addresses

    static let usdcAddress = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
    static let daiAddress = "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb"
    static let usdtAddress = "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2"

    // MARK: - Initialization

    init(erc4337Manager: ERC4337Manager) {
        self.erc4337Manager = erc4337Manager
        registerDefaultTokens()
    }

    // MARK: - Token Operations

    /// Get balance of a stablecoin for an address
    func getBalance(token: String, address: String, completion: @escaping (Result<StablecoinBalance, StablecoinError>) -> Void) {
        guard supportedTokens[token] != nil else {
            completion(.failure(.unsupportedToken(symbol: token)))
            return
        }
        // TODO: Call balanceOf on token contract
        completion(.success(StablecoinBalance(token: token, balance: 0, balanceFormatted: "0.00", valueUSD: 0)))
    }

    /// Transfer stablecoins
    func transfer(token: String, to: String, amount: UInt64, completion: @escaping (Result<String, StablecoinError>) -> Void) {
        guard supportedTokens[token] != nil else {
            completion(.failure(.unsupportedToken(symbol: token)))
            return
        }
        // TODO: ABI-encode transfer(address,uint256), submit via ERC-4337
        delegate?.stablecoin(self, didTransfer: amount, token: token)
        completion(.failure(.transferFailed))
    }

    /// Approve a spender for token allowance
    func approve(token: String, spender: String, amount: UInt64, completion: @escaping (Result<Void, StablecoinError>) -> Void) {
        // TODO: ABI-encode approve(address,uint256), submit via ERC-4337
        completion(.failure(.approvalFailed))
    }

    // MARK: - Swap

    /// Swap between stablecoins
    func swap(from: String, to: String, amount: UInt64, completion: @escaping (Result<UInt64, StablecoinError>) -> Void) {
        guard supportedTokens[from] != nil else { completion(.failure(.unsupportedToken(symbol: from))); return }
        guard supportedTokens[to] != nil else { completion(.failure(.unsupportedToken(symbol: to))); return }
        // TODO: Route swap through DEX aggregator
        delegate?.stablecoin(self, didSwap: from, toToken: to, amount: amount)
        completion(.failure(.swapFailed(reason: "Not implemented")))
    }

    // MARK: - Stability Monitoring

    /// Check if a stablecoin is depegged
    func checkPegStatus(token: String) -> Result<Bool, StablecoinError> {
        guard let tokenInfo = supportedTokens[token] else { return .failure(.unsupportedToken(symbol: token)) }
        let deviation = abs(tokenInfo.currentPrice - tokenInfo.pegTarget) / tokenInfo.pegTarget
        if deviation > depegThreshold {
            delegate?.stablecoin(self, didFailWithError: .depegDetected(token: token, price: tokenInfo.currentPrice))
            return .success(false)
        }
        return .success(true)
    }

    /// Get all supported stablecoins
    func getSupportedTokens() -> [StablecoinToken] { return Array(supportedTokens.values) }

    // MARK: - Private

    private func registerDefaultTokens() {
        supportedTokens["USDC"] = StablecoinToken(
            symbol: "USDC", name: "USD Coin", contractAddress: StablecoinManager.usdcAddress,
            decimals: 6, issuer: "Circle", totalSupply: 0, pegTarget: 1.0, currentPrice: 1.0, isSupported: true
        )
        supportedTokens["DAI"] = StablecoinToken(
            symbol: "DAI", name: "Dai Stablecoin", contractAddress: StablecoinManager.daiAddress,
            decimals: 18, issuer: "MakerDAO", totalSupply: 0, pegTarget: 1.0, currentPrice: 1.0, isSupported: true
        )
    }
}
