// BlockchainBridge.swift
// MTRX Core - Blockchain
//
// Unified bridge layer connecting iOS views to blockchain operations.
// Routes all on-chain actions through the MTRX API runtime and manages
// transaction signing via ERC-4337 account abstraction.

import Foundation
import CryptoKit

// MARK: - Result Types

struct TransactionResult {
    let transactionHash: String
    let operationHash: String
    let status: TransactionStatus
    let gasUsed: UInt64
    let blockNumber: UInt64?
    let timestamp: Date

    enum TransactionStatus: String, Codable {
        case pending, confirmed, failed, reverted
    }
}

struct ContractResult {
    let contractAddress: String
    let deploymentTxHash: String
    let templateId: String
    let status: TransactionResult.TransactionStatus
    let abi: String?
}

struct NFTResult {
    let tokenId: String
    let contractAddress: String
    let transactionHash: String
    let metadataURI: String
    let status: TransactionResult.TransactionStatus
}

struct StakeResult {
    let stakeId: String
    let amountETH: Double
    let validator: String
    let estimatedAPY: Double
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct LoanResult {
    let loanId: String
    let collateralAsset: String
    let collateralAmount: UInt64
    let borrowAsset: String
    let borrowAmount: UInt64
    let interestRate: Double
    let healthFactor: Double
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct VoteResult {
    let proposalId: String
    let voteChoice: String
    let votingPower: UInt64
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct ClaimResult {
    let claimId: String
    let claimType: String
    let policyId: String
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct ListingResult {
    let listingId: String
    let itemId: String
    let price: UInt64
    let currency: String
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct FundraiserResult {
    let fundraiserId: String
    let title: String
    let goalAmount: UInt64
    let contractAddress: String
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct Portfolio {
    let walletAddress: String
    let totalValueUSD: Double
    let ethBalance: Double
    let tokenBalances: [TokenBalance]
    let nftHoldings: [NFTHolding]
    let activeStakes: [StakePosition_]
    let activeLoans: [LoanPosition]
    let pendingTransactions: [PendingTransaction]
    let lastUpdated: Date

    struct TokenBalance {
        let symbol: String
        let name: String
        let contractAddress: String
        let balance: Double
        let valueUSD: Double
        let decimals: Int
    }

    struct NFTHolding {
        let tokenId: String
        let contractAddress: String
        let name: String
        let imageURL: String?
        let estimatedValueUSD: Double?
    }

    struct StakePosition_ {
        let stakeId: String
        let amountETH: Double
        let validator: String
        let accruedRewards: Double
        let status: String
    }

    struct LoanPosition {
        let loanId: String
        let collateralAsset: String
        let collateralAmount: Double
        let borrowAsset: String
        let borrowAmount: Double
        let healthFactor: Double
    }

    struct PendingTransaction {
        let operationHash: String
        let type: String
        let submittedAt: Date
    }
}

struct AttestationResult {
    let attestationId: String
    let schemaId: String
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct IdentityResult {
    let did: String
    let attestations: [String]
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct PaymentResult {
    let paymentId: String
    let amount: UInt64
    let recipient: String
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct SwapResult {
    let swapId: String
    let fromToken: String
    let toToken: String
    let amountIn: UInt64
    let amountOut: UInt64
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct RewardResult {
    let rewardId: String
    let programId: String
    let pointsEarned: UInt64
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

struct SubscriptionResult {
    let subscriptionId: String
    let planId: String
    let expiresAt: Date
    let transactionHash: String
    let status: TransactionResult.TransactionStatus
}

// MARK: - Bridge Errors

enum BlockchainBridgeError: Error, LocalizedError {
    case walletNotConnected
    case apiRequestFailed(reason: String)
    case transactionFailed(reason: String)
    case signingFailed(reason: String)
    case invalidParameters(reason: String)
    case operationTimeout
    case networkUnavailable
    case insufficientFunds
    case contractError(reason: String)
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .walletNotConnected: return "No wallet connected. Create or recover a wallet first."
        case .apiRequestFailed(let r): return "API request failed: \(r)"
        case .transactionFailed(let r): return "Transaction failed: \(r)"
        case .signingFailed(let r): return "Signing failed: \(r)"
        case .invalidParameters(let r): return "Invalid parameters: \(r)"
        case .operationTimeout: return "Operation timed out waiting for confirmation."
        case .networkUnavailable: return "Blockchain network is unavailable."
        case .insufficientFunds: return "Insufficient funds for this transaction."
        case .contractError(let r): return "Smart contract error: \(r)"
        case .unsupportedOperation(let op): return "Unsupported operation: \(op)"
        }
    }
}

// MARK: - Transaction Tracking

/// Tracks in-flight transactions and their statuses.
final class TransactionTracker {

    struct TrackedTransaction {
        let operationHash: String
        let type: String
        let submittedAt: Date
        var status: TransactionResult.TransactionStatus
        var confirmedAt: Date?
        var transactionHash: String?
        var error: String?
    }

    private var transactions: [String: TrackedTransaction] = [:]
    private let lock = NSLock()

    func track(operationHash: String, type: String) {
        lock.lock()
        defer { lock.unlock() }
        transactions[operationHash] = TrackedTransaction(
            operationHash: operationHash,
            type: type,
            submittedAt: Date(),
            status: .pending
        )
    }

    func updateStatus(operationHash: String, status: TransactionResult.TransactionStatus, txHash: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        transactions[operationHash]?.status = status
        transactions[operationHash]?.transactionHash = txHash
        if status == .confirmed || status == .failed || status == .reverted {
            transactions[operationHash]?.confirmedAt = Date()
        }
    }

    func markFailed(operationHash: String, error: String) {
        lock.lock()
        defer { lock.unlock() }
        transactions[operationHash]?.status = .failed
        transactions[operationHash]?.error = error
        transactions[operationHash]?.confirmedAt = Date()
    }

    func getPending() -> [TrackedTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return transactions.values.filter { $0.status == .pending }
    }

    func getAll() -> [TrackedTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return Array(transactions.values).sorted { $0.submittedAt > $1.submittedAt }
    }

    func get(operationHash: String) -> TrackedTransaction? {
        lock.lock()
        defer { lock.unlock() }
        return transactions[operationHash]
    }
}

// MARK: - BlockchainBridge

/// Singleton bridge that exposes all blockchain operations to the iOS UI layer.
/// Every operation flows through:
///   View -> BlockchainBridge -> MTRXAPIClient -> Python Runtime -> Blockchain
/// with local ERC-4337 signing handled by ERC4337Manager.
final class BlockchainBridge {

    // MARK: - Singleton

    static let shared = BlockchainBridge()

    // MARK: - Dependencies

    private let apiClient: MTRXAPIClient
    private let session: URLSession
    private let baseURL: URL

    /// ERC-4337 manager for UserOperation construction and signing.
    /// Lazily configured when a wallet is connected.
    private(set) var erc4337Manager: ERC4337Manager?

    /// Transaction tracker for status monitoring.
    let transactionTracker = TransactionTracker()

    /// Currently connected wallet address.
    private(set) var connectedWalletAddress: String?

    // MARK: - Chain configuration (config-driven; TESTNET-ONLY in this phase)
    //
    // The chain id is NEVER a hardcoded mainnet constant. It reads
    // PendingCredentials.Network.chainID when set, otherwise defaults to Base Sepolia
    // testnet. A mainnet (or any non-testnet) value is caught and fails CLOSED before
    // any signing/submission by assertTestnetSigning().

    // Single source of truth for the chain policy lives on BaseNetworkConfig (the
    // sign primitive's guard uses it too). These alias it for the bridge-level
    // defense-in-depth guard so 84532 / 8453 are defined exactly once.
    /// Base mainnet chain id — explicitly forbidden for signing in this testnet-only phase.
    static let baseMainnetChainID: UInt64 = BaseNetworkConfig.baseMainnetChainID
    /// Base Sepolia testnet chain id — the only chain signing is permitted against now.
    static let baseSepoliaChainID: UInt64 = BaseNetworkConfig.permittedSigningChainID

    /// Active chain id. Config-driven (PendingCredentials.Network.chainID), defaulting
    /// to Base Sepolia testnet — never a hardcoded mainnet.
    private let chainId: UInt64 = {
        let configured = PendingCredentials.Network.chainID
        return configured > 0 ? UInt64(configured) : BlockchainBridge.baseSepoliaChainID
    }()

    /// Fail CLOSED before any signing/submission if the active chain is not the
    /// permitted testnet. In this testnet-only phase, signing is locked to Base
    /// Sepolia (84532); mainnet — or any other chain — must NEVER be signed against.
    /// Throws an honest error and signs nothing.
    private func assertTestnetSigning() throws {
        guard chainId == Self.baseSepoliaChainID else {
            let which = (chainId == Self.baseMainnetChainID) ? " (Base mainnet)" : ""
            throw BlockchainBridgeError.signingFailed(reason:
                "Testnet-only build — signing is restricted to Base Sepolia (\(Self.baseSepoliaChainID)). "
                + "Chain \(chainId)\(which) is not permitted. Nothing was signed.")
        }
    }

    private let bridgeQueue = DispatchQueue(label: "com.mtrx.blockchain.bridge", qos: .userInitiated)

    // MARK: - Initialization

    private init() {
        self.apiClient = MTRXAPIClient.shared

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)

        self.baseURL = URL(string: ProcessInfo.processInfo.environment["MTRX_API_URL"] ?? "https://api.mtrx.run/v1")!
    }

    // MARK: - Wallet Connection

    /// Connect a wallet and initialize the ERC-4337 manager.
    func connectWallet(address: String, bundlerURL: URL? = nil, paymasterAddress: String? = nil) {
        connectedWalletAddress = address

        // Endpoints from PendingCredentials — no hardcoded URLs. A non-routable
        // `.invalid` placeholder is used while a value is blank (safe no-op).
        let rpcURL = URL(string: PendingCredentials.filled(PendingCredentials.Network.rpcURL)
                         ?? "https://unconfigured.invalid")!
        let bundler = bundlerURL
            ?? URL(string: PendingCredentials.filled(PendingCredentials.AccountAbstraction.bundlerURL)
                   ?? "https://unconfigured.invalid")!
        let networkConfig = BaseNetworkConfig(rpcURL: rpcURL, chainId: chainId, bundlerURL: bundler)

        let manager = ERC4337Manager(
            paymasterAddress: paymasterAddress,
            bundlerURL: bundler,
            networkConfig: networkConfig
        )
        manager.setAccountAddress(address)
        self.erc4337Manager = manager
    }

    /// Disconnect the current wallet.
    func disconnectWallet() {
        connectedWalletAddress = nil
        erc4337Manager = nil
    }

    /// Whether a wallet is currently connected.
    var isWalletConnected: Bool {
        return connectedWalletAddress != nil
    }

    // MARK: - Core Transaction Methods

    /// Send a token/ETH transaction to an address.
    ///
    /// `amount` is wei as UInt64 — fine for ordinary transfers, but it caps out
    /// at ~18.4 ETH. For property-sized settlements use the `valueWei:` overload,
    /// which carries the value as a decimal string across the full uint256 range.
    func sendTransaction(to: String, amount: UInt64, data: Data = Data()) async throws -> TransactionResult {
        try assertTestnetSigning()   // testnet-only: fail closed before any build/sign
        guard let manager = erc4337Manager else { throw BlockchainBridgeError.walletNotConnected }

        // Build the UserOperation
        let opResult = manager.buildUserOperation(to: to, value: amount, data: data)
        let operation: UserOperation
        switch opResult {
        case .success(let op): operation = op
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: err.localizedDescription)
        }
        return try await finalizeAndSubmit(operation, to: to, amountLabel: String(amount), manager: manager)
    }

    /// Full-range settlement: `valueWei` is the amount as a decimal wei string,
    /// so a realistically-priced home (hundreds/thousands of ETH — far above the
    /// UInt64 ceiling) builds and signs a valid UserOperation. Honest failure is
    /// preserved: a genuinely invalid or >uint256 value throws
    /// `.transactionFailed` (via `.valueTooLarge`) and nothing is signed or sent.
    func sendTransaction(to: String, valueWei: String, data: Data = Data()) async throws -> TransactionResult {
        try assertTestnetSigning()   // testnet-only: fail closed before any build/sign
        guard let manager = erc4337Manager else { throw BlockchainBridgeError.walletNotConnected }

        let opResult = manager.buildUserOperation(to: to, valueWei: valueWei, data: data)
        let operation: UserOperation
        switch opResult {
        case .success(let op): operation = op
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: err.localizedDescription)
        }
        return try await finalizeAndSubmit(operation, to: to, amountLabel: valueWei, manager: manager)
    }

    /// Shared post-build pipeline for both value paths: estimate gas → optional
    /// verifying-paymaster splice → sign → submit → track → notify. Value-agnostic
    /// (the amount only rides along as `amountLabel` for the backend notify), so
    /// the UInt64 and full-range senders are byte-identical from here on.
    private func finalizeAndSubmit(_ operation: UserOperation,
                                   to: String,
                                   amountLabel: String,
                                   manager: ERC4337Manager) async throws -> TransactionResult {
        // Estimate gas via bundler
        let estimatedOp = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UserOperation, Error>) in
            manager.estimateGas(for: operation) { result in
                switch result {
                case .success(let op): continuation.resume(returning: op)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }

        // P5-2: gas-sponsorship splice. Request a verifying-paymaster signature
        // and fold its `paymasterAndData` into the op BEFORE signing (the
        // userOpHash covers keccak256(paymasterAndData)). Guarded by
        // isGasSponsorshipConfigured; if sponsorship isn't configured or the
        // server declines, the op is signed as-is and the sender pays its own
        // gas — never a fabricated sponsorship.
        var opToSign = estimatedOp
        if PendingCredentials.isGasSponsorshipConfigured {
            let validUntil = Int(Date().timeIntervalSince1970) + 3600
            let hexD: (Data) -> String = { "0x" + $0.map { String(format: "%02x", $0) }.joined() }
            let pmBody: [String: AnyCodableValue] = [
                "sender": .string(estimatedOp.sender),
                "nonce": .int(Int(estimatedOp.nonce)),
                "init_code": .string(hexD(estimatedOp.initCode)),
                "call_data": .string(hexD(estimatedOp.callData)),
                "call_gas_limit": .int(Int(estimatedOp.callGasLimit)),
                "verification_gas_limit": .int(Int(estimatedOp.verificationGasLimit)),
                "pre_verification_gas": .int(Int(estimatedOp.preVerificationGas)),
                "max_fee_per_gas": .int(Int(estimatedOp.maxFeePerGas)),
                "max_priority_fee_per_gas": .int(Int(estimatedOp.maxPriorityFeePerGas)),
                // Pin the chain explicitly so the digest the server signs is over
                // the SAME chainId the client's op targets — never a fragile
                // shared default (a divergence would silently invalidate the
                // sponsorship on-chain at bundle time).
                "chain_id": .int(Int(chainId)),
                "valid_until": .int(validUntil),
                "valid_after": .int(0),
                "action_type": .string("transfer"),
            ]
            if let pmHex = await MTRXAPIClient.shared.requestPaymasterAndData(pmBody),
               let pmData = Data(hexString: pmHex) {
                opToSign = estimatedOp.withPaymasterAndData(pmData)
            }
        }

        // Sign the (possibly sponsored) operation
        let signedOp = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UserOperation, Error>) in
            manager.signOperation(opToSign) { result in
                switch result {
                case .success(let op): continuation.resume(returning: op)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }

        // Submit to bundler
        let opHash = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            manager.submitOperation(signedOp) { result in
                switch result {
                case .success(let hash): continuation.resume(returning: hash)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }

        transactionTracker.track(operationHash: opHash, type: "transfer")

        // Also notify the API backend
        try await postToAPI(endpoint: "blockchain/transaction", body: [
            "operationHash": opHash,
            "to": to,
            "amount": amountLabel,
            "chainId": String(chainId)
        ])

        return TransactionResult(
            transactionHash: opHash,
            operationHash: opHash,
            status: .pending,
            gasUsed: estimatedOp.callGasLimit + estimatedOp.verificationGasLimit + estimatedOp.preVerificationGas,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Deploy a smart contract from a template.
    func deployContract(template: String, params: [String: Any]) async throws -> ContractResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/contract/deploy", body: [
            "template": template,
            "params": params,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let contractAddress = response["contractAddress"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Missing contract address in deployment response")
        }

        // Deploying a contract WRITES ON-CHAIN. Success requires a real on-chain submit
        // returning a validated op-hash — never the server-echoed "transactionHash". Same
        // load-bearing pattern as swap(): no try?-swallow; honest throw if there's no
        // executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let factoryAddress = response["factoryAddress"] as? String, !factoryAddress.isEmpty,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain contract deployment isn't available yet (the deploy service returned no executable calldata). Nothing was deployed.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: factoryAddress, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build deployment operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "contract_deploy")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Deployment submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return ContractResult(
            contractAddress: contractAddress,
            deploymentTxHash: opHash,   // real op-hash — never the server echo
            templateId: template,
            status: .pending,
            abi: response["abi"] as? String
        )
    }

    /// Mint an NFT with the given metadata.
    func mintNFT(metadata: [String: Any]) async throws -> NFTResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/nft/mint", body: [
            "metadata": metadata,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let tokenId = response["tokenId"] as? String,
              let contractAddress = response["contractAddress"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid mint response")
        }

        // Minting an NFT WRITES ON-CHAIN. Success requires a real on-chain submit returning a
        // validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain NFT minting isn't available yet (the mint service returned no executable calldata). Nothing was minted.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: contractAddress, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build mint operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "nft_mint")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Mint submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return NFTResult(
            tokenId: tokenId,
            contractAddress: contractAddress,
            transactionHash: opHash,   // real op-hash — never the server echo
            metadataURI: response["metadataURI"] as? String ?? "",
            status: .pending
        )
    }

    /// Stake ETH with a validator.
    func stake(amount: Double, validator: String) async throws -> StakeResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/staking/stake", body: [
            "amountETH": String(amount),
            "validator": validator,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let stakeId = response["stakeId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid staking response")
        }

        // Staking MOVES FUNDS. Success requires a real on-chain submit returning a
        // validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        // Convert ETH to wei and submit via ERC-4337
        let weiAmount = UInt64(amount * 1e18)
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let stakingContract = response["stakingContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain staking execution isn't available yet (the staking service returned no executable calldata). Nothing was staked.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: stakingContract, value: weiAmount, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build staking operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "stake")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Staking submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return StakeResult(
            stakeId: stakeId,
            amountETH: amount,
            validator: validator,
            estimatedAPY: response["estimatedAPY"] as? Double ?? 0.0,
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// Create a DeFi lending position.
    func createLoan(collateral: String, amount: UInt64) async throws -> LoanResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/defi/loan/create", body: [
            "collateralAsset": collateral,
            "borrowAmount": String(amount),
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let loanId = response["loanId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid loan creation response")
        }

        // Creating a loan MOVES FUNDS (collateral deposit + borrow). Success requires the
        // on-chain approve+borrow batch to be signed, submitted, and returned with a real
        // op-hash — never the server-echoed "transactionHash". Same load-bearing pattern as
        // swap(): no try?-swallow; honest throw if there's no executable path.
        guard let manager = erc4337Manager else { throw BlockchainBridgeError.walletNotConnected }

        guard let calldataItems = response["batchCalldata"] as? [[String: Any]], !calldataItems.isEmpty else {
            throw BlockchainBridgeError.unsupportedOperation(
                "On-chain loan execution isn't available yet (the loan service returned no approve+borrow calldata). Nothing was borrowed."
            )
        }

        // Parse EVERY calldata item. A partially-parsed batch (e.g. approve without the
        // borrow, or borrow without approve) is dangerous, so require all items to parse —
        // otherwise fail honestly rather than submit an incomplete batch.
        let calls: [(to: String, value: UInt64, data: Data)] = calldataItems.compactMap { item in
            guard let to = item["to"] as? String,
                  let dataHex = item["data"] as? String,
                  let data = Data(hexString: dataHex) else { return nil }
            let value = UInt64(item["value"] as? String ?? "0") ?? 0
            return (to: to, value: value, data: data)
        }
        guard calls.count == calldataItems.count, !calls.isEmpty else {
            throw BlockchainBridgeError.transactionFailed(reason: "Loan creation returned malformed calldata. Nothing was borrowed.")
        }

        let op: UserOperation
        switch manager.buildBatchUserOperation(calls: calls) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build loan operation: \(err.localizedDescription)")
        }

        // Load-bearing submit: throws on testnet-lock / signing / submission failure —
        // no try?-swallow. submitSignedOperation tracks the op and returns the real hash.
        let opHash = try await submitSignedOperation(op, type: "loan_create")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Loan submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return LoanResult(
            loanId: loanId,
            collateralAsset: collateral,
            collateralAmount: response["collateralAmount"] as? UInt64 ?? 0,
            borrowAsset: response["borrowAsset"] as? String ?? "USDC",
            borrowAmount: amount,
            interestRate: response["interestRate"] as? Double ?? 0.0,
            healthFactor: response["healthFactor"] as? Double ?? 0.0,
            transactionHash: opHash,   // real op-hash from the submitted UserOperation — never the server echo
            status: .pending
        )
    }

    /// Cast a vote on a governance proposal.
    func vote(proposalId: String, vote: String) async throws -> VoteResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/governance/vote", body: [
            "proposalId": proposalId,
            "vote": vote,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        // A vote is an on-chain governance action. Success requires a real on-chain submit
        // returning a validated op-hash — never the server-echoed "transactionHash". Same
        // load-bearing pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let govContract = response["governanceContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain vote execution isn't available yet (the governance service returned no executable calldata). Nothing was voted.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: govContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build vote operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "governance_vote")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Vote submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return VoteResult(
            proposalId: proposalId,
            voteChoice: vote,
            votingPower: response["votingPower"] as? UInt64 ?? 0,
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// File an insurance claim.
    func fileClaim(type: String, data: [String: Any]) async throws -> ClaimResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/insurance/claim", body: [
            "claimType": type,
            "claimData": data,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let claimId = response["claimId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid claim response")
        }

        // Filing a claim is an on-chain action against the insurance contract. Success
        // requires a real submit returning a validated op-hash — never the server-echoed
        // "transactionHash". Same load-bearing pattern as swap(): no try?-swallow; honest
        // throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let insuranceContract = response["insuranceContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain claim execution isn't available yet (the claim service returned no executable calldata). Nothing was filed.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: insuranceContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build claim operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "insurance_claim")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Claim submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return ClaimResult(
            claimId: claimId,
            claimType: type,
            policyId: response["policyId"] as? String ?? "",
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// List an item on the marketplace.
    func listItem(item: [String: Any], price: UInt64) async throws -> ListingResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        var body: [String: Any] = item
        body["price"] = String(price)
        body["walletAddress"] = connectedWalletAddress ?? ""
        body["chainId"] = String(chainId)

        let response = try await postToAPI(endpoint: "blockchain/marketplace/list", body: body)

        guard let listingId = response["listingId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid listing response")
        }

        // A listing PUTS AN ITEM ON-CHAIN (approval + list as a batch). Success requires a real
        // on-chain submit returning a validated op-hash — never the server-echoed "transactionHash".
        // Same load-bearing pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataItems = response["batchCalldata"] as? [[String: Any]],
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain listing execution isn't available yet (the marketplace service returned no executable calldata). Nothing was listed.")
        }

        let calls: [(to: String, value: UInt64, data: Data)] = calldataItems.compactMap { item in
            guard let to = item["to"] as? String,
                  let dataHex = item["data"] as? String,
                  let data = Data(hexString: dataHex) else { return nil }
            let value = UInt64(item["value"] as? String ?? "0") ?? 0
            return (to: to, value: value, data: data)
        }
        guard calls.count == calldataItems.count, !calls.isEmpty else {
            throw BlockchainBridgeError.transactionFailed(reason: "Listing calldata was malformed. Nothing was listed.")
        }

        let op: UserOperation
        switch manager.buildBatchUserOperation(calls: calls) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build listing operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "marketplace_list")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Listing submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return ListingResult(
            listingId: listingId,
            itemId: response["itemId"] as? String ?? "",
            price: price,
            currency: response["currency"] as? String ?? "ETH",
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// Create a fundraising campaign.
    func createFundraiser(title: String, goal: UInt64) async throws -> FundraiserResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/fundraising/create", body: [
            "title": title,
            "goalAmount": String(goal),
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let fundraiserId = response["fundraiserId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid fundraiser response")
        }

        // Creating a fundraiser deploys/registers an on-chain contract. Success requires a real
        // on-chain submit returning a validated op-hash — never the server-echoed "transactionHash".
        // Same load-bearing pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let factoryAddress = response["factoryAddress"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain fundraiser execution isn't available yet (the fundraising service returned no executable calldata). Nothing was created.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: factoryAddress, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build fundraiser operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "fundraiser_create")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Fundraiser submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return FundraiserResult(
            fundraiserId: fundraiserId,
            title: title,
            goalAmount: goal,
            contractAddress: response["contractAddress"] as? String ?? "",
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// Fetch the full portfolio for the connected wallet.
    func getPortfolio() async throws -> Portfolio {
        guard let walletAddress = connectedWalletAddress else {
            throw BlockchainBridgeError.walletNotConnected
        }

        let response = try await getFromAPI(endpoint: "blockchain/portfolio", query: [
            "walletAddress": walletAddress,
            "chainId": String(chainId)
        ])

        let tokenBalances: [Portfolio.TokenBalance] = (response["tokenBalances"] as? [[String: Any]] ?? []).map { t in
            Portfolio.TokenBalance(
                symbol: t["symbol"] as? String ?? "",
                name: t["name"] as? String ?? "",
                contractAddress: t["contractAddress"] as? String ?? "",
                balance: t["balance"] as? Double ?? 0.0,
                valueUSD: t["valueUSD"] as? Double ?? 0.0,
                decimals: t["decimals"] as? Int ?? 18
            )
        }

        let nftHoldings: [Portfolio.NFTHolding] = (response["nftHoldings"] as? [[String: Any]] ?? []).map { n in
            Portfolio.NFTHolding(
                tokenId: n["tokenId"] as? String ?? "",
                contractAddress: n["contractAddress"] as? String ?? "",
                name: n["name"] as? String ?? "",
                imageURL: n["imageURL"] as? String,
                estimatedValueUSD: n["estimatedValueUSD"] as? Double
            )
        }

        let activeStakes: [Portfolio.StakePosition_] = (response["activeStakes"] as? [[String: Any]] ?? []).map { s in
            Portfolio.StakePosition_(
                stakeId: s["stakeId"] as? String ?? "",
                amountETH: s["amountETH"] as? Double ?? 0.0,
                validator: s["validator"] as? String ?? "",
                accruedRewards: s["accruedRewards"] as? Double ?? 0.0,
                status: s["status"] as? String ?? "active"
            )
        }

        let activeLoans: [Portfolio.LoanPosition] = (response["activeLoans"] as? [[String: Any]] ?? []).map { l in
            Portfolio.LoanPosition(
                loanId: l["loanId"] as? String ?? "",
                collateralAsset: l["collateralAsset"] as? String ?? "",
                collateralAmount: l["collateralAmount"] as? Double ?? 0.0,
                borrowAsset: l["borrowAsset"] as? String ?? "",
                borrowAmount: l["borrowAmount"] as? Double ?? 0.0,
                healthFactor: l["healthFactor"] as? Double ?? 0.0
            )
        }

        let pendingTxs: [Portfolio.PendingTransaction] = transactionTracker.getPending().map { t in
            Portfolio.PendingTransaction(
                operationHash: t.operationHash,
                type: t.type,
                submittedAt: t.submittedAt
            )
        }

        return Portfolio(
            walletAddress: walletAddress,
            totalValueUSD: response["totalValueUSD"] as? Double ?? 0.0,
            ethBalance: response["ethBalance"] as? Double ?? 0.0,
            tokenBalances: tokenBalances,
            nftHoldings: nftHoldings,
            activeStakes: activeStakes,
            activeLoans: activeLoans,
            pendingTransactions: pendingTxs,
            lastUpdated: Date()
        )
    }

    // MARK: - Additional Operations

    /// Create an on-chain attestation (EAS).
    func createAttestation(schemaId: String, data: [String: Any]) async throws -> AttestationResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/attestation/create", body: [
            "schemaId": schemaId,
            "attestationData": data,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let attestationId = response["attestationId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid attestation response")
        }

        // An attestation WRITES ON-CHAIN STATE. Success requires a real on-chain submit
        // returning a validated op-hash — never the server-echoed "transactionHash". Same
        // load-bearing pattern as swap(): no try?-swallow; honest throw if there's no
        // executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let easContract = response["easContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain attestation execution isn't available yet (the attestation service returned no executable calldata). Nothing was attested.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: easContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build attestation operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "attestation")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Attestation submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return AttestationResult(
            attestationId: attestationId,
            schemaId: schemaId,
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// Register or update a decentralized identity.
    func registerIdentity(did: String, claims: [String: Any]) async throws -> IdentityResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/identity/register", body: [
            "did": did,
            "claims": claims,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        // Registering an identity WRITES ON-CHAIN STATE. A real success requires an
        // actual submit returning a validated op-hash — never the server-echoed
        // "transactionHash". Same load-bearing pattern as swap(): no try?-swallow;
        // honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let identityContract = response["identityContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain identity registration isn't available yet (the identity service returned no executable calldata). Nothing was registered.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: identityContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build identity operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "identity_register")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Identity registration did not return a valid operation hash. Nothing was confirmed.")
        }

        return IdentityResult(
            did: did,
            attestations: response["attestations"] as? [String] ?? [],
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// Execute a payment (stablecoin or token transfer).
    func sendPayment(to: String, amount: UInt64, currency: String) async throws -> PaymentResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/payments/send", body: [
            "to": to,
            "amount": String(amount),
            "currency": currency,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let paymentId = response["paymentId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid payment response")
        }

        // A payment MOVES FUNDS. Success requires a real on-chain submit returning a
        // validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let tokenContract = response["tokenContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain payment execution isn't available yet (the payment service returned no executable calldata). Nothing was paid.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: tokenContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build payment operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "payment")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Payment submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return PaymentResult(
            paymentId: paymentId,
            amount: amount,
            recipient: to,
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// Execute a DEX swap.
    func swap(fromToken: String, toToken: String, amountIn: UInt64, minAmountOut: UInt64) async throws -> SwapResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/dex/swap", body: [
            "fromToken": fromToken,
            "toToken": toToken,
            "amountIn": String(amountIn),
            "minAmountOut": String(minAmountOut),
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let swapId = response["swapId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid swap response")
        }

        // A swap MOVES FUNDS. It is "successful" ONLY when the on-chain approve+swap
        // batch is actually signed and submitted and the bundler returns a real
        // operation hash. The server-echoed "transactionHash" is NOT proof of execution
        // and must never be returned as success. The real op-hash from
        // submitSignedOperation — which fails closed on the testnet lock, signing, or
        // submission — is the sole source of truth; anything short of it fails honestly.
        guard let manager = erc4337Manager else { throw BlockchainBridgeError.walletNotConnected }

        guard let calldataItems = response["batchCalldata"] as? [[String: Any]], !calldataItems.isEmpty else {
            throw BlockchainBridgeError.unsupportedOperation(
                "On-chain swap execution isn't available yet (the route service returned no approve+swap calldata). Nothing was swapped."
            )
        }

        // Parse EVERY calldata item. A partially-parsed batch (e.g. approve without the
        // swap, or swap without approve) is dangerous, so require all items to parse —
        // otherwise fail honestly rather than submit an incomplete batch.
        let calls: [(to: String, value: UInt64, data: Data)] = calldataItems.compactMap { item in
            guard let to = item["to"] as? String,
                  let dataHex = item["data"] as? String,
                  let data = Data(hexString: dataHex) else { return nil }
            let value = UInt64(item["value"] as? String ?? "0") ?? 0
            return (to: to, value: value, data: data)
        }
        guard calls.count == calldataItems.count, !calls.isEmpty else {
            throw BlockchainBridgeError.transactionFailed(reason: "Swap route returned malformed calldata. Nothing was swapped.")
        }

        let op: UserOperation
        switch manager.buildBatchUserOperation(calls: calls) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build swap operation: \(err.localizedDescription)")
        }

        // Load-bearing submit: throws on testnet-lock / signing / submission failure —
        // no try?-swallow. submitSignedOperation tracks the op and returns the real hash.
        let opHash = try await submitSignedOperation(op, type: "dex_swap")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Swap submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return SwapResult(
            swapId: swapId,
            fromToken: fromToken,
            toToken: toToken,
            amountIn: amountIn,
            amountOut: response["amountOut"] as? UInt64 ?? 0,
            transactionHash: opHash,   // real op-hash from the submitted UserOperation — never the server echo
            status: .pending
        )
    }

    /// Earn loyalty/cashback rewards.
    func claimReward(programId: String, action: String) async throws -> RewardResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/rewards/claim", body: [
            "programId": programId,
            "action": action,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let rewardId = response["rewardId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid reward response")
        }

        // Claiming a reward MOVES FUNDS. Success requires a real on-chain submit returning a
        // validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let rewardsContract = response["rewardsContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain reward claim isn't available yet (the rewards service returned no executable calldata). Nothing was claimed.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: rewardsContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build reward-claim operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "reward_claim")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Reward-claim submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return RewardResult(
            rewardId: rewardId,
            programId: programId,
            pointsEarned: response["pointsEarned"] as? UInt64 ?? 0,
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// Create or renew a subscription.
    func subscribe(planId: String, durationMonths: Int) async throws -> SubscriptionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/subscriptions/create", body: [
            "planId": planId,
            "durationMonths": String(durationMonths),
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let subscriptionId = response["subscriptionId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid subscription response")
        }

        // A subscription MOVES FUNDS. Success requires a real on-chain submit returning a
        // validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        // The subscription amount must come from the server. Silently defaulting a missing
        // costWei to 0 would send a 0-value transaction the user believes is a real charge
        // (it would just bounce) — a quiet wrong thing. Fail honestly if the amount is
        // missing/unparseable. (An explicit "0" — a free tier — is allowed and parses fine.)
        guard let costWei = response["costWei"] as? String, let cost = UInt64(costWei) else {
            throw BlockchainBridgeError.transactionFailed(reason: "Couldn't determine the subscription amount. Nothing was charged.")
        }
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let subContract = response["subscriptionContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain subscription execution isn't available yet (the subscription service returned no executable calldata). Nothing was charged.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: subContract, value: cost, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build subscription operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "subscription")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Subscription submission did not return a valid operation hash. Nothing was confirmed.")
        }

        let expiresAt: Date
        if let expiresTimestamp = response["expiresAt"] as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: expiresTimestamp)
        } else {
            expiresAt = Calendar.current.date(byAdding: .month, value: durationMonths, to: Date()) ?? Date()
        }

        return SubscriptionResult(
            subscriptionId: subscriptionId,
            planId: planId,
            expiresAt: expiresAt,
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// Unstake ETH from a validator.
    func unstake(stakeId: String) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/staking/unstake", body: [
            "stakeId": stakeId,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard response["stakeId"] as? String != nil || response["transactionHash"] as? String != nil else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid unstake response")
        }

        // Unstaking MOVES FUNDS (withdraws principal/rewards). Success requires a real
        // on-chain submit returning a validated op-hash — never the server-echoed
        // "transactionHash". Same load-bearing pattern as swap(): no try?-swallow; honest
        // throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let stakingContract = response["stakingContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain unstake execution isn't available yet (the staking service returned no executable calldata). Nothing was unstaked.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: stakingContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build unstake operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "unstake")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Unstake submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return TransactionResult(
            transactionHash: opHash,   // real op-hash — never the server echo
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Repay a DeFi loan.
    func repayLoan(loanId: String, amount: UInt64) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/defi/loan/repay", body: [
            "loanId": loanId,
            "amount": String(amount),
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let manager = erc4337Manager else { throw BlockchainBridgeError.walletNotConnected }

        // Repaying a loan MOVES FUNDS. Success requires a real on-chain submit returning a
        // validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // batch pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataItems = response["batchCalldata"] as? [[String: Any]], !calldataItems.isEmpty else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain loan repayment isn't available yet (the loan service returned no executable calldata). Nothing was repaid.")
        }

        let calls: [(to: String, value: UInt64, data: Data)] = calldataItems.compactMap { item in
            guard let to = item["to"] as? String,
                  let dataHex = item["data"] as? String,
                  let data = Data(hexString: dataHex) else { return nil }
            let value = UInt64(item["value"] as? String ?? "0") ?? 0
            return (to: to, value: value, data: data)
        }
        guard calls.count == calldataItems.count, !calls.isEmpty else {
            throw BlockchainBridgeError.transactionFailed(reason: "Loan-repayment route returned malformed calldata. Nothing was repaid.")
        }

        let op: UserOperation
        switch manager.buildBatchUserOperation(calls: calls) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build loan-repayment operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "loan_repay")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Loan-repayment submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return TransactionResult(
            transactionHash: opHash,   // real op-hash — never the server echo
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Tokenize a real-world asset.
    func tokenizeAsset(assetData: [String: Any]) async throws -> ContractResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        var body = assetData
        body["walletAddress"] = connectedWalletAddress ?? ""
        body["chainId"] = String(chainId)

        let response = try await postToAPI(endpoint: "blockchain/rwa/tokenize", body: body)

        guard let contractAddress = response["contractAddress"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid tokenization response")
        }

        // Tokenizing an asset WRITES ON-CHAIN. Success requires a real on-chain submit returning
        // a validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let factoryAddress = response["factoryAddress"] as? String, !factoryAddress.isEmpty,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain asset tokenization isn't available yet (the RWA service returned no executable calldata). Nothing was tokenized.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: factoryAddress, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build tokenization operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "rwa_tokenize")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Tokenization submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return ContractResult(
            contractAddress: contractAddress,
            deploymentTxHash: opHash,   // real op-hash — never the server echo
            templateId: response["templateId"] as? String ?? "rwa",
            status: .pending,
            abi: response["abi"] as? String
        )
    }

    /// File a dispute for resolution.
    func fileDispute(counterparty: String, evidence: [String: Any]) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/disputes/file", body: [
            "counterparty": counterparty,
            "evidence": evidence,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        // Filing a dispute COMMITS EVIDENCE ON-CHAIN. Success requires a real on-chain submit
        // returning a validated op-hash — never the server-echoed "transactionHash". Same
        // load-bearing pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let disputeContract = response["disputeContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain dispute filing isn't available yet (the dispute service returned no executable calldata). Nothing was filed.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: disputeContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build dispute operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "dispute_file")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Dispute submission did not return a valid operation hash. Nothing was filed.")
        }

        return TransactionResult(
            transactionHash: opHash,   // real op-hash — never the server echo
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Register intellectual property on-chain.
    func registerIP(metadata: [String: Any]) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        var body = metadata
        body["walletAddress"] = connectedWalletAddress ?? ""
        body["chainId"] = String(chainId)

        let response = try await postToAPI(endpoint: "blockchain/ip/register", body: body)

        // IP registration WRITES STATE ON-CHAIN. Success requires a real on-chain submit
        // returning a validated op-hash — never the server-echoed "transactionHash". Same
        // load-bearing pattern as swap(): no try?-swallow; honest throw if there's no
        // executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let ipContract = response["ipContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain IP registration isn't available yet (the registration service returned no executable calldata). Nothing was registered.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: ipContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build IP registration operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "ip_register")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "IP registration submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return TransactionResult(
            transactionHash: opHash,   // real op-hash — never the server echo
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Submit a supply chain event.
    func recordSupplyChainEvent(productId: String, event: [String: Any]) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/supply-chain/event", body: [
            "productId": productId,
            "event": event,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        // Recording a supply-chain event WRITES STATE ON-CHAIN. Success requires a real
        // on-chain submit returning a validated op-hash — never the server-echoed
        // "transactionHash". Same load-bearing pattern as swap(): no try?-swallow; honest
        // throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let scContract = response["supplyChainContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain supply-chain event execution isn't available yet (the supply-chain service returned no executable calldata). Nothing was recorded.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: scContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build supply chain operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "supply_chain_event")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Supply chain submission did not return a valid operation hash. Nothing was recorded.")
        }

        return TransactionResult(
            transactionHash: opHash,   // real op-hash — never the server echo
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Request oracle data and store the result on-chain.
    func requestOracleData(feedId: String) async throws -> TransactionResult {
        // EXPLICIT honest failure (not incidental on postToAPI throwing when the server is
        // absent). This is a server-mediated path with NO app-side signing/submit, so it
        // cannot return a verifiable on-chain result and must NOT echo a server hash as
        // success. The moment a server exists, incidental honest-failure would silently
        // become a fake-success — so it fails honestly now. Real wiring requires the
        // server-vs-app-signer architecture decision (flagged separately). Nothing was requested.
        throw BlockchainBridgeError.unsupportedOperation("On-chain oracle data requests aren't available in this build yet. Nothing was requested.")
    }

    /// Contribute to a gaming ecosystem (in-game asset purchase, etc.).
    func purchaseGameAsset(gameId: String, assetId: String, price: UInt64) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/gaming/purchase", body: [
            "gameId": gameId,
            "assetId": assetId,
            "price": String(price),
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        // Purchasing a game asset MOVES FUNDS. Success requires a real on-chain submit returning
        // a validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let gameContract = response["gameContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain game-asset purchase isn't available yet (the gaming service returned no executable calldata). Nothing was purchased.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: gameContract, value: price, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build game-asset purchase operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "gaming_purchase")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Game-asset purchase submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return TransactionResult(
            transactionHash: opHash,   // real op-hash — never the server echo
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Issue a security token.
    func issueSecurityToken(params: [String: Any]) async throws -> ContractResult {
        // EXPLICIT honest failure on the MOST REGULATED path in the codebase. Securities
        // issuance is server-mediated with NO app-side signing/submit, so it cannot return a
        // verifiable on-chain result. It must NEVER echo a server hash as success — the moment
        // a server exists, incidental honest-failure (postToAPI throwing) would silently become
        // a fake-success on a securities path. Fails honestly now; real issuance requires both a
        // server-vs-app-signer architecture decision AND securities licensing (flagged
        // separately). Nothing was issued.
        throw BlockchainBridgeError.unsupportedOperation("Security-token issuance isn't available in this build yet. Nothing was issued.")
    }

    /// Mint a stablecoin or interact with the stablecoin module.
    func mintStablecoin(amount: UInt64, collateral: UInt64) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/stablecoin/mint", body: [
            "amount": String(amount),
            "collateral": String(collateral),
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        // Minting a stablecoin MOVES FUNDS. Success requires a real on-chain submit returning
        // a validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let stablecoinContract = response["stablecoinContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain stablecoin minting isn't available yet (the stablecoin service returned no executable calldata). Nothing was minted.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: stablecoinContract, value: collateral, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build stablecoin mint operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "stablecoin_mint")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Stablecoin mint submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return TransactionResult(
            transactionHash: opHash,   // real op-hash — never the server echo
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Execute an agentic payment (AI agent-to-agent value transfer).
    func agenticPayment(agentId: String, amount: UInt64, purpose: String) async throws -> PaymentResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/agentic-payments/send", body: [
            "agentId": agentId,
            "amount": String(amount),
            "purpose": purpose,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let paymentId = response["paymentId"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid agentic payment response")
        }

        // An agentic payment MOVES FUNDS on an agent's behalf. Success requires a real on-chain
        // submit returning a validated op-hash — never the server-echoed "transactionHash". Same
        // load-bearing pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let paymentContract = response["paymentContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain agentic payment execution isn't available yet (the payment service returned no executable calldata). Nothing was paid.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: paymentContract, value: amount, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build agentic payment operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "agentic_payment")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Agentic payment submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return PaymentResult(
            paymentId: paymentId,
            amount: amount,
            recipient: agentId,
            transactionHash: opHash,   // real op-hash — never the server echo
            status: .pending
        )
    }

    /// Execute a privacy-preserving transaction.
    func privateTransfer(to: String, amount: UInt64, note: Data) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/privacy/transfer", body: [
            "to": to,
            "amount": String(amount),
            "note": note.base64EncodedString(),
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        // A private transfer MOVES FUNDS. Success requires a real on-chain submit returning a
        // validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let privacyContract = response["privacyContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain private transfer execution isn't available yet (the privacy service returned no executable calldata). Nothing was transferred.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: privacyContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build private transfer operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "private_transfer")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Private transfer submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return TransactionResult(
            transactionHash: opHash,   // real op-hash — never the server echo
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Post to the social module (on-chain social graph).
    func socialPost(content: String, metadata: [String: Any]) async throws -> TransactionResult {
        // EXPLICIT honest failure (not incidental on postToAPI throwing). This is a
        // server-mediated path with NO app-side signing/submit, so it cannot return a
        // verifiable on-chain result and must NOT echo a server hash as success. Fails
        // honestly now; real wiring requires the server-vs-app-signer architecture decision
        // (flagged separately). Nothing was posted.
        throw BlockchainBridgeError.unsupportedOperation("On-chain social posting isn't available in this build yet. Nothing was posted.")
    }

    /// Redeem cashback or brand rewards.
    func redeemCashback(rewardId: String) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/cashback/redeem", body: [
            "rewardId": rewardId,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        // A cashback redemption MOVES FUNDS. Success requires a real on-chain submit returning
        // a validated op-hash — never the server-echoed "transactionHash". Same load-bearing
        // pattern as swap(): no try?-swallow; honest throw if there's no executable path.
        guard let calldataHex = response["calldata"] as? String,
              let calldata = Data(hexString: calldataHex),
              let cashbackContract = response["cashbackContract"] as? String,
              let manager = erc4337Manager else {
            throw BlockchainBridgeError.unsupportedOperation("On-chain cashback redemption isn't available yet (the cashback service returned no executable calldata). Nothing was redeemed.")
        }

        let op: UserOperation
        switch manager.buildUserOperation(to: cashbackContract, value: 0, data: calldata) {
        case .success(let built): op = built
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: "Could not build cashback redemption operation: \(err.localizedDescription)")
        }

        let opHash = try await submitSignedOperation(op, type: "cashback_redeem")
        guard opHash.hasPrefix("0x"), opHash.count > 2 else {
            throw BlockchainBridgeError.transactionFailed(reason: "Cashback redemption submission did not return a valid operation hash. Nothing was confirmed.")
        }

        return TransactionResult(
            transactionHash: opHash,   // real op-hash — never the server echo
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    // MARK: - Transaction Status

    /// Wait for a pending transaction to confirm.
    func waitForConfirmation(operationHash: String, timeout: TimeInterval = 60) async throws -> TransactionResult {
        guard let manager = erc4337Manager else { throw BlockchainBridgeError.walletNotConnected }

        let receipt = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OperationReceipt, Error>) in
            manager.waitForOperation(operationHash: operationHash, timeout: timeout) { result in
                switch result {
                case .success(let receipt): continuation.resume(returning: receipt)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }

        let status: TransactionResult.TransactionStatus = receipt.success ? .confirmed : .reverted
        transactionTracker.updateStatus(operationHash: operationHash, status: status, txHash: receipt.transactionHash)

        return TransactionResult(
            transactionHash: receipt.transactionHash,
            operationHash: operationHash,
            status: status,
            gasUsed: receipt.gasUsed,
            blockNumber: receipt.blockNumber,
            timestamp: Date()
        )
    }

    /// Get the current status of a tracked transaction.
    func getTransactionStatus(operationHash: String) -> TransactionResult.TransactionStatus? {
        return transactionTracker.get(operationHash: operationHash)?.status
    }

    // MARK: - Private Helpers

    /// Sign and submit a UserOperation, returning the operation hash.
    private func submitSignedOperation(_ operation: UserOperation, type: String) async throws -> String {
        try assertTestnetSigning()   // testnet-only: fail closed before sign/submit
        guard let manager = erc4337Manager else { throw BlockchainBridgeError.walletNotConnected }

        // Estimate gas
        let estimated = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UserOperation, Error>) in
            manager.estimateGas(for: operation) { result in
                switch result {
                case .success(let op): continuation.resume(returning: op)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }

        // Sign
        let signed = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UserOperation, Error>) in
            manager.signOperation(estimated) { result in
                switch result {
                case .success(let op): continuation.resume(returning: op)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }

        // Submit
        let opHash = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            manager.submitOperation(signed) { result in
                switch result {
                case .success(let hash): continuation.resume(returning: hash)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }

        transactionTracker.track(operationHash: opHash, type: type)
        return opHash
    }

    /// POST JSON to the MTRX API and return the parsed response.
    ///
    /// Uses the shared API client's auth token and the standard MTRX
    /// headers so the gateway can attribute the call to the right
    /// session, rate-limit it correctly, and tag the metrics.
    @discardableResult
    private func postToAPI(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1.0", forHTTPHeaderField: "X-MTRX-API-Version")
        request.setValue("ios", forHTTPHeaderField: "X-MTRX-Platform")
        request.setValue("bridge", forHTTPHeaderField: "X-MTRX-Component")
        if let token = apiClient.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let wallet = connectedWalletAddress {
            request.setValue(wallet, forHTTPHeaderField: "X-MTRX-Wallet")
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            throw BlockchainBridgeError.invalidParameters(reason: "Failed to serialize request body")
        }
        request.httpBody = httpBody

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlockchainBridgeError.networkUnavailable
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            switch httpResponse.statusCode {
            case 401, 403:
                throw BlockchainBridgeError.signingFailed(reason: "Unauthorized (HTTP \(httpResponse.statusCode))")
            case 402:
                throw BlockchainBridgeError.insufficientFunds
            case 408, 504:
                throw BlockchainBridgeError.operationTimeout
            case 409:
                throw BlockchainBridgeError.contractError(reason: "Conflict: \(bodyText)")
            case 429:
                throw BlockchainBridgeError.apiRequestFailed(reason: "Rate limited — please retry in a moment")
            case 500...599:
                throw BlockchainBridgeError.apiRequestFailed(reason: "Server error (HTTP \(httpResponse.statusCode)): \(bodyText)")
            default:
                throw BlockchainBridgeError.apiRequestFailed(reason: "HTTP \(httpResponse.statusCode): \(bodyText)")
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BlockchainBridgeError.apiRequestFailed(reason: "Invalid JSON response")
        }

        return json
    }

    /// GET from the MTRX API with query parameters.
    private func getFromAPI(endpoint: String, query: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw BlockchainBridgeError.invalidParameters(reason: "Invalid URL for endpoint: \(endpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1.0", forHTTPHeaderField: "X-MTRX-API-Version")
        request.setValue("ios", forHTTPHeaderField: "X-MTRX-Platform")
        request.setValue("bridge", forHTTPHeaderField: "X-MTRX-Component")
        if let token = apiClient.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let wallet = connectedWalletAddress {
            request.setValue(wallet, forHTTPHeaderField: "X-MTRX-Wallet")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BlockchainBridgeError.apiRequestFailed(reason: bodyText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BlockchainBridgeError.apiRequestFailed(reason: "Invalid JSON response")
        }

        return json
    }

    // MARK: - Matrix-to-0pnMatrx Session Bridge
    //
    // These methods implement the session-layer side of the bridge — the
    // plumbing that sits between the iOS Matrix shell and the 0pnMatrx
    // gateway's ``/bridge/v1/*`` endpoints. Everything above this line
    // deals with on-chain actions (component 1–30 calls that end in a
    // UserOperation). Everything below this line deals with session
    // lifecycle: creating a chat session, resuming one, sending chat
    // turns, linking the wallet to the session, and reading the
    // dashboard snapshot the home screen needs.
    //
    // All the requests are built by ``MTRXPackager.shared`` so we get the
    // standard headers and the packager's registered encoder/decoder for
    // free. The bridge then just executes them through the shared
    // session and returns the parsed response back to the caller.

    /// The currently active bridge session id, if any. The shell stores
    /// this in UserDefaults on first launch and restores it on subsequent
    /// launches so the user never loses their conversation.
    private(set) var activeSessionId: String?

    /// Create a new Matrix bridge session. Returns the new session id.
    /// Call this the first time the user launches the app, or whenever
    /// the previous session has expired.
    @discardableResult
    func createBridgeSession() async throws -> String {
        let request = try MTRXPackager.shared.packageBridgeSessionCreate(
            walletAddress: connectedWalletAddress
        )
        let json = try await executeBridgeRequest(request)
        guard let sessionId = json["sessionId"] as? String ?? json["session_id"] as? String else {
            throw BlockchainBridgeError.apiRequestFailed(reason: "Session create response missing session id")
        }
        activeSessionId = sessionId
        return sessionId
    }

    /// Resume a previously-created bridge session. Returns true if the
    /// gateway accepted the resume, false if the session had expired and
    /// the caller should create a new one.
    @discardableResult
    func resumeBridgeSession(sessionId: String) async throws -> Bool {
        let request = try MTRXPackager.shared.packageBridgeSessionResume(sessionId: sessionId)
        do {
            _ = try await executeBridgeRequest(request)
            activeSessionId = sessionId
            return true
        } catch BlockchainBridgeError.apiRequestFailed(let reason) where reason.contains("404") || reason.contains("410") {
            return false
        }
    }

    /// Send a chat turn to Trinity through the bridge. The reply is
    /// streamed through the SSE events stream, so this call just returns
    /// once the gateway has accepted the turn.
    func sendBridgeChat(message: String, attachments: [String]? = nil) async throws {
        guard let sessionId = activeSessionId else {
            throw BlockchainBridgeError.invalidParameters(reason: "No active bridge session")
        }
        let request = try MTRXPackager.shared.packageBridgeChat(
            sessionId: sessionId,
            message: message,
            attachments: attachments
        )
        _ = try await executeBridgeRequest(request)
    }

    /// Send a structured action reply (Confirm / Modify / Cancel /
    /// custom) through the bridge.
    func sendBridgeAction(action: String, payload: [String: Any]? = nil) async throws {
        guard let sessionId = activeSessionId else {
            throw BlockchainBridgeError.invalidParameters(reason: "No active bridge session")
        }
        // Convert the dictionary payload to AnyCodableValue for the packager.
        let codablePayload: [String: AnyCodableValue]?
        if let payload {
            codablePayload = payload.mapValues { AnyCodableValue.from($0) }
        } else {
            codablePayload = nil
        }
        let request = try MTRXPackager.shared.packageBridgeAction(
            sessionId: sessionId,
            action: action,
            payload: codablePayload
        )
        _ = try await executeBridgeRequest(request)
    }

    /// Link the currently-connected wallet to the active bridge session.
    /// Must be called after both `connectWallet` and `createBridgeSession`
    /// have completed.
    func linkWalletToSession(signature: String? = nil) async throws {
        guard let sessionId = activeSessionId else {
            throw BlockchainBridgeError.invalidParameters(reason: "No active bridge session")
        }
        guard let wallet = connectedWalletAddress else {
            throw BlockchainBridgeError.walletNotConnected
        }
        let request = try MTRXPackager.shared.packageBridgeWalletLink(
            sessionId: sessionId,
            walletAddress: wallet,
            chainId: Int(chainId),
            signature: signature
        )
        _ = try await executeBridgeRequest(request)
    }

    /// Fetch the dashboard snapshot the home screen needs. Returns the
    /// raw JSON so the caller can map it to its own view model.
    func fetchBridgeDashboard() async throws -> [String: Any] {
        guard let sessionId = activeSessionId else {
            throw BlockchainBridgeError.invalidParameters(reason: "No active bridge session")
        }
        let request = try MTRXPackager.shared.packageBridgeDashboard(sessionId: sessionId)
        return try await executeBridgeRequest(request)
    }

    /// Fetch the current list of 30 components and their health status.
    func fetchBridgeComponents() async throws -> [[String: Any]] {
        let request = try MTRXPackager.shared.packageBridgeComponentsList()
        let json = try await executeBridgeRequest(request)
        return (json["components"] as? [[String: Any]]) ?? []
    }

    /// Fetch the runtime config (feature flags, rate limits, supported
    /// chains) from the bridge.
    func fetchBridgeConfig() async throws -> [String: Any] {
        let request = try MTRXPackager.shared.packageBridgeConfig()
        return try await executeBridgeRequest(request)
    }

    /// Register an APNs push token so the bridge can forward Morpheus
    /// alerts as silent/critical pushes while the app is backgrounded.
    func registerPushToken(_ token: String, environment: String = "production") async throws {
        guard let sessionId = activeSessionId else {
            throw BlockchainBridgeError.invalidParameters(reason: "No active bridge session")
        }
        let request = try MTRXPackager.shared.packageBridgePushRegister(
            sessionId: sessionId,
            token: token,
            environment: environment
        )
        _ = try await executeBridgeRequest(request)
    }

    /// Run a pre-built bridge URLRequest and return the parsed JSON body.
    /// Centralises error mapping so every bridge-session helper produces
    /// the same BlockchainBridgeError cases.
    @discardableResult
    private func executeBridgeRequest(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlockchainBridgeError.networkUnavailable
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BlockchainBridgeError.apiRequestFailed(
                reason: "HTTP \(httpResponse.statusCode): \(bodyText)"
            )
        }

        if data.isEmpty {
            return [:]
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BlockchainBridgeError.apiRequestFailed(reason: "Invalid JSON response from bridge")
        }
        return json
    }
}

// MARK: - Data hex-string initializer (bridge-local)

private extension Data {
    init?(hexString: String) {
        let hex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
