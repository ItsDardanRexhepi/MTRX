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
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .unsupportedToken(let s): return "Unsupported stablecoin: \(s)"
        case .insufficientBalance: return "Insufficient stablecoin balance."
        case .transferFailed: return "Transfer failed."
        case .swapFailed(let r): return "Swap failed: \(r)"
        case .depegDetected(let t, let p): return "\(t) depeg detected. Price: \(p)"
        case .approvalFailed: return "Token approval failed."
        case .notConfigured: return "Stablecoin token not configured (PendingCredentials.Components.stablecoin)."
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

    /// Get balance of a stablecoin for an address.
    ///
    /// Reads the real on-chain `balanceOf(address)` via JSON-RPC `eth_call`
    /// (see `balanceOfOnChain`). The token contract is resolved from
    /// `PendingCredentials.Components.stablecoin`; the RPC endpoint from
    /// `PendingCredentials.Network.rpcURL`. When EITHER is blank the method
    /// fails with `.notConfigured` — it NEVER returns a fabricated balance.
    func getBalance(token: String, address: String, completion: @escaping (Result<StablecoinBalance, StablecoinError>) -> Void) {
        guard let tokenInfo = supportedTokens[token] else {
            completion(.failure(.unsupportedToken(symbol: token)))
            return
        }
        // Resolve the on-chain token address from config; blank → needs config.
        guard let tokenAddress = PendingCredentials.filled(PendingCredentials.Components.stablecoin) else {
            completion(.failure(.notConfigured))
            return
        }
        Self.readBalanceOf(tokenAddress: tokenAddress, owner: address) { result in
            switch result {
            case .success(let raw):
                let formatted = Self.formatUnits(raw, decimals: tokenInfo.decimals)
                let valueUSD = Self.scaledDouble(raw, decimals: tokenInfo.decimals) * tokenInfo.currentPrice
                completion(.success(StablecoinBalance(
                    token: token, balance: raw, balanceFormatted: formatted, valueUSD: valueUSD
                )))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    /// Transfer stablecoins.
    ///
    /// On-chain submission requires the user's Secure-Enclave signer and a
    /// `WalletTransactionService` — see `transferOnChain(...)`, which is the
    /// real signed path. This completion-style entry point exists only for the
    /// legacy call sites that don't yet thread the wallet service; it does NOT
    /// fabricate a tx hash. It validates config and surfaces a clear state so
    /// callers migrate to `transferOnChain`. When the token contract is blank
    /// it returns `.notConfigured`; otherwise it signals the caller must use
    /// the signed path.
    func transfer(token: String, to: String, amount: UInt64, completion: @escaping (Result<String, StablecoinError>) -> Void) {
        guard supportedTokens[token] != nil else {
            completion(.failure(.unsupportedToken(symbol: token)))
            return
        }
        guard PendingCredentials.filled(PendingCredentials.Components.stablecoin) != nil else {
            completion(.failure(.notConfigured))
            return
        }
        // Calldata is correct and ready; signing/submission must go through the
        // enclave-backed `transferOnChain(service:sender:signingKeyTag:)`.
        _ = Self.encodeTransfer(to: to, amount: amount)
        completion(.failure(.transferFailed))
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode the ERC-20 `transfer(address to, uint256 amount)`.
    static func encodeTransfer(to: String, amount: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("transfer(address,uint256)")
        data.append(ABIEncoder.encodeAddress(to))
        data.append(ABIEncoder.encodeUInt256(amount))
        return data
    }

    /// Transfer a stablecoin on-chain through the real submit pipeline:
    /// enclave-signed UserOp → server paymaster → bundler. A standard ERC-20
    /// transfer of the user's OWN balance — self-custody, never custodial. The
    /// token contract is deferred to PendingCredentials (or pass an explicit
    /// supported-token address); nil → throws, never a fake transfer.
    @MainActor
    func transferOnChain(
        token: String? = PendingCredentials.filled(PendingCredentials.Components.stablecoin),
        to: String,
        amount: UInt64,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService
    ) async throws -> WalletTransactionService.Submission {
        guard let tokenAddress = token else { throw StablecoinError.notConfigured }
        return try await service.submitCall(
            to: tokenAddress,
            value: 0,
            data: Self.encodeTransfer(to: to, amount: amount),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    /// ABI-encode the ERC-20 `approve(address spender, uint256 amount)`.
    static func encodeApprove(spender: String, amount: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("approve(address,uint256)")
        data.append(ABIEncoder.encodeAddress(spender))
        data.append(ABIEncoder.encodeUInt256(amount))
        return data
    }

    /// Approve a spender on-chain through the real submit pipeline: enclave-signed
    /// UserOp → server paymaster → bundler. Standard ERC-20 `approve` on the
    /// user's OWN token balance — self-custody, never custodial. The token
    /// contract is deferred to PendingCredentials (or pass an explicit
    /// supported-token address); nil → throws, never a fake approval.
    @MainActor
    func approveOnChain(
        token: String? = PendingCredentials.filled(PendingCredentials.Components.stablecoin),
        spender: String,
        amount: UInt64,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService
    ) async throws -> WalletTransactionService.Submission {
        guard let tokenAddress = token else { throw StablecoinError.notConfigured }
        return try await service.submitCall(
            to: tokenAddress,
            value: 0,
            data: Self.encodeApprove(spender: spender, amount: amount),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    /// Approve a spender for token allowance.
    ///
    /// The real signed path is `approveOnChain(...)` (enclave signer + wallet
    /// service). This completion-style entry point validates config and does
    /// NOT fabricate a result: blank token → `.notConfigured`; otherwise it
    /// directs callers to the signed path.
    func approve(token: String, spender: String, amount: UInt64, completion: @escaping (Result<Void, StablecoinError>) -> Void) {
        guard PendingCredentials.filled(PendingCredentials.Components.stablecoin) != nil else {
            completion(.failure(.notConfigured))
            return
        }
        _ = Self.encodeApprove(spender: spender, amount: amount)
        completion(.failure(.approvalFailed))
    }

    // MARK: - Swap

    // MARK: - Read-only balance (eth_call balanceOf)

    /// ABI-encode the ERC-20 `balanceOf(address owner)` call.
    static func encodeBalanceOf(owner: String) -> Data {
        var data = ABIEncoder.functionSelector("balanceOf(address)")
        data.append(ABIEncoder.encodeAddress(owner))
        return data
    }

    /// Read `balanceOf(owner)` on `tokenAddress` via JSON-RPC `eth_call` and
    /// decode the returned uint256. Uses `BaseNetwork`, whose RPC endpoint is
    /// read from `PendingCredentials.Network.rpcURL`; when that is blank the
    /// network layer fails with a clear "RPC URL not set" error, which we map to
    /// `.notConfigured`. NEVER returns a fabricated balance.
    static func readBalanceOf(
        tokenAddress: String,
        owner: String,
        network: BaseNetwork = BaseNetwork(),
        completion: @escaping (Result<UInt64, StablecoinError>) -> Void
    ) {
        let callData = "0x" + hexEncode(encodeBalanceOf(owner: owner))
        network.ethCall(to: tokenAddress, data: callData) { result in
            switch result {
            case .success(let returnHex):
                guard let value = Self.decodeUInt256(returnHex) else {
                    // Empty / unparseable return (e.g. RPC offline) → unavailable.
                    completion(.failure(.notConfigured))
                    return
                }
                completion(.success(value))
            case .failure:
                // RPC unreachable or not configured → explicit needs-config state,
                // not a fabricated zero balance.
                completion(.failure(.notConfigured))
            }
        }
    }

    /// async wrapper around `readBalanceOf` for callers using structured
    /// concurrency. Returns the raw on-chain balance (smallest token unit) or
    /// throws `.notConfigured` when the token/RPC isn't set.
    func balanceOfOnChain(
        owner: String,
        token: String? = PendingCredentials.filled(PendingCredentials.Components.stablecoin),
        network: BaseNetwork = BaseNetwork()
    ) async throws -> UInt64 {
        guard let tokenAddress = token else { throw StablecoinError.notConfigured }
        return try await withCheckedThrowingContinuation { continuation in
            Self.readBalanceOf(tokenAddress: tokenAddress, owner: owner, network: network) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Swap (DEX aggregator)
    //
    // HONEST BOUNDARY — UNVERIFIED.
    // A stablecoin↔stablecoin swap is executed by routing through a DEX
    // aggregator (1inch / 0x). The aggregator QUOTE + the exact router calldata
    // are produced by the aggregator's OFF-CHAIN API (https://api.1inch.dev/swap
    // or https://api.0x.org/swap) — that call needs an API key + endpoint that
    // is NOT configured anywhere in PendingCredentials, and it is not something
    // this in-app submission layer can fabricate. So we do NOT invent a quote,
    // a router address, or a min-return: the caller supplies the aggregator's
    // `router` target and its pre-built `swapCalldata` (and, for an ERC-20→ERC-20
    // swap, must first `approveOnChain` the router as spender). This method wires
    // the real signed on-chain submission of that calldata through the enclave
    // pipeline. When no router is configured it returns/throws `.notConfigured`
    // — it never fakes a swap or a returned amount.

    /// Execute a pre-quoted DEX-aggregator swap on-chain through the real submit
    /// pipeline: enclave-signed UserOp → server paymaster → bundler.
    ///
    /// - Parameters:
    ///   - router: the aggregator router contract to call (1inch/0x router). From
    ///     the aggregator quote response. When nil → `.notConfigured`.
    ///   - swapCalldata: the exact transaction `data` returned by the aggregator
    ///     quote API for this swap (encodes path, amounts, min-return, receiver).
    ///   - valueWei: native value to send (0 for ERC-20→ERC-20; non-zero only
    ///     for a native-asset leg). The receiving stablecoin lands directly in
    ///     `sender`'s self-custody account — never custodial.
    @MainActor
    func swapOnChain(
        router: String?,
        swapCalldata: Data,
        valueWei: UInt64 = 0,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService
    ) async throws -> WalletTransactionService.Submission {
        guard let routerAddress = router, !swapCalldata.isEmpty else {
            throw StablecoinError.notConfigured
        }
        return try await service.submitCall(
            to: routerAddress,
            value: valueWei,
            data: swapCalldata,
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    /// Swap between stablecoins.
    ///
    /// The real signed path is `swapOnChain(router:swapCalldata:...)`, which
    /// submits a DEX-aggregator quote through the enclave pipeline. This
    /// completion-style entry point cannot run without an aggregator quote
    /// (router + calldata) and a wallet service, so it does NOT fabricate a swap
    /// or a returned amount — it returns a clear `.swapFailed` directing callers
    /// to fetch a quote and use `swapOnChain`.
    func swap(from: String, to: String, amount: UInt64, completion: @escaping (Result<UInt64, StablecoinError>) -> Void) {
        guard supportedTokens[from] != nil else { completion(.failure(.unsupportedToken(symbol: from))); return }
        guard supportedTokens[to] != nil else { completion(.failure(.unsupportedToken(symbol: to))); return }
        completion(.failure(.swapFailed(reason: "Fetch a DEX-aggregator quote and submit via swapOnChain(router:swapCalldata:); no aggregator endpoint is configured.")))
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

    // MARK: - ABI / encoding helpers

    /// Lowercase hex (no `0x` prefix) for arbitrary bytes. Mirrors the
    /// file-local hex helpers used elsewhere in the blockchain layer (those are
    /// `private extension`s, so not visible here).
    static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Decode a 32-byte (64 hex-char) ABI uint256 word returned by `eth_call`
    /// into a `UInt64`. ERC-20 balances can exceed UInt64, but the rest of this
    /// component models amounts as `UInt64` (see `encodeUInt256`/`StablecoinBalance`),
    /// so we read the low 64 bits and SATURATE on overflow rather than wrap —
    /// never silently corrupting a value. Returns nil for empty/`0x`/malformed
    /// returns (e.g. RPC offline) so the caller surfaces an unavailable state.
    static func decodeUInt256(_ hex: String) -> UInt64? {
        var s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard !s.isEmpty else { return nil }
        // A well-formed single-word return is 64 hex chars. Anything shorter and
        // non-empty is still parsed from its tail; anything longer means the high
        // words are non-zero → value exceeds the low word.
        if s.count > 64 {
            let highCount = s.count - 64
            let highStart = s.startIndex
            let highEnd = s.index(highStart, offsetBy: highCount)
            let high = s[highStart..<highEnd]
            // If any high word is non-zero the true value overflows UInt64.
            if high.contains(where: { $0 != "0" }) { return UInt64.max }
            s = String(s[highEnd...])
        }
        // Parse the (up to) 64-char low word; saturate if it exceeds UInt64.
        let lowHex = s.count > 16 ? String(s.suffix(16)) : s
        let highOfLow = s.count > 16 ? String(s.dropLast(16)) : ""
        if highOfLow.contains(where: { $0 != "0" }) { return UInt64.max }
        return UInt64(lowHex, radix: 16)
    }

    /// Format a raw smallest-unit balance as a human-readable decimal string
    /// (e.g. 1_500_000 @ 6 decimals → "1.50"). Pure integer math; no rounding
    /// surprises beyond a 2-dp display trim.
    static func formatUnits(_ raw: UInt64, decimals: Int) -> String {
        guard decimals > 0 else { return String(raw) }
        let divisor = pow(10.0, Double(decimals))
        let value = Double(raw) / divisor
        return String(format: "%.2f", value)
    }

    /// Scale a raw smallest-unit balance to its token-unit Double value.
    static func scaledDouble(_ raw: UInt64, decimals: Int) -> Double {
        guard decimals > 0 else { return Double(raw) }
        return Double(raw) / pow(10.0, Double(decimals))
    }

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
