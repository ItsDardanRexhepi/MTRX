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

    /// Base network chain ID.
    private let chainId: UInt64 = 8453

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

        let rpcURL = URL(string: "https://mainnet.base.org")!
        let bundler = bundlerURL ?? URL(string: "https://bundler.base.org")!
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
    func sendTransaction(to: String, amount: UInt64, data: Data = Data()) async throws -> TransactionResult {
        guard let manager = erc4337Manager else { throw BlockchainBridgeError.walletNotConnected }

        // Build the UserOperation
        let opResult = manager.buildUserOperation(to: to, value: amount, data: data)
        let operation: UserOperation
        switch opResult {
        case .success(let op): operation = op
        case .failure(let err): throw BlockchainBridgeError.transactionFailed(reason: err.localizedDescription)
        }

        // Estimate gas via bundler
        let estimatedOp = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UserOperation, Error>) in
            manager.estimateGas(for: operation) { result in
                switch result {
                case .success(let op): continuation.resume(returning: op)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }

        // Sign the operation
        let signedOp = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UserOperation, Error>) in
            manager.signOperation(estimatedOp) { result in
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
            "amount": String(amount),
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

        guard let contractAddress = response["contractAddress"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Missing contract address in deployment response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "contract_deploy")

        // If we have calldata from the API, submit via ERC-4337
        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let manager = erc4337Manager {
            let factoryAddress = response["factoryAddress"] as? String ?? ""
            let opResult = manager.buildUserOperation(to: factoryAddress, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "contract_deploy")
            }
        }

        return ContractResult(
            contractAddress: contractAddress,
            deploymentTxHash: txHash,
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
              let contractAddress = response["contractAddress"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid mint response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "nft_mint")

        // Submit the mint calldata via ERC-4337
        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: contractAddress, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "nft_mint")
            }
        }

        return NFTResult(
            tokenId: tokenId,
            contractAddress: contractAddress,
            transactionHash: txHash,
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

        guard let stakeId = response["stakeId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid staking response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "stake")

        // Convert ETH to wei and submit via ERC-4337
        let weiAmount = UInt64(amount * 1e18)
        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let stakingContract = response["stakingContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: stakingContract, value: weiAmount, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "stake")
            }
        }

        return StakeResult(
            stakeId: stakeId,
            amountETH: amount,
            validator: validator,
            estimatedAPY: response["estimatedAPY"] as? Double ?? 0.0,
            transactionHash: txHash,
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

        guard let loanId = response["loanId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid loan creation response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "loan_create")

        // Submit approval + borrow as a batch operation
        if let calldataItems = response["batchCalldata"] as? [[String: Any]],
           let manager = erc4337Manager {
            let calls: [(to: String, value: UInt64, data: Data)] = calldataItems.compactMap { item in
                guard let to = item["to"] as? String,
                      let dataHex = item["data"] as? String,
                      let data = Data(hexString: dataHex) else { return nil }
                let value = UInt64(item["value"] as? String ?? "0") ?? 0
                return (to: to, value: value, data: data)
            }
            if !calls.isEmpty {
                let batchResult = manager.buildBatchUserOperation(calls: calls)
                if case .success(let op) = batchResult {
                    _ = try? await submitSignedOperation(op, type: "loan_create")
                }
            }
        }

        return LoanResult(
            loanId: loanId,
            collateralAsset: collateral,
            collateralAmount: response["collateralAmount"] as? UInt64 ?? 0,
            borrowAsset: response["borrowAsset"] as? String ?? "USDC",
            borrowAmount: amount,
            interestRate: response["interestRate"] as? Double ?? 0.0,
            healthFactor: response["healthFactor"] as? Double ?? 0.0,
            transactionHash: txHash,
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid vote response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "governance_vote")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let govContract = response["governanceContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: govContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "governance_vote")
            }
        }

        return VoteResult(
            proposalId: proposalId,
            voteChoice: vote,
            votingPower: response["votingPower"] as? UInt64 ?? 0,
            transactionHash: txHash,
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

        guard let claimId = response["claimId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid claim response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "insurance_claim")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let insuranceContract = response["insuranceContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: insuranceContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "insurance_claim")
            }
        }

        return ClaimResult(
            claimId: claimId,
            claimType: type,
            policyId: response["policyId"] as? String ?? "",
            transactionHash: txHash,
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

        guard let listingId = response["listingId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid listing response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "marketplace_list")

        // Marketplace listing typically needs approval + list as batch
        if let calldataItems = response["batchCalldata"] as? [[String: Any]],
           let manager = erc4337Manager {
            let calls: [(to: String, value: UInt64, data: Data)] = calldataItems.compactMap { item in
                guard let to = item["to"] as? String,
                      let dataHex = item["data"] as? String,
                      let data = Data(hexString: dataHex) else { return nil }
                let value = UInt64(item["value"] as? String ?? "0") ?? 0
                return (to: to, value: value, data: data)
            }
            if !calls.isEmpty {
                let batchResult = manager.buildBatchUserOperation(calls: calls)
                if case .success(let op) = batchResult {
                    _ = try? await submitSignedOperation(op, type: "marketplace_list")
                }
            }
        }

        return ListingResult(
            listingId: listingId,
            itemId: response["itemId"] as? String ?? "",
            price: price,
            currency: response["currency"] as? String ?? "ETH",
            transactionHash: txHash,
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

        guard let fundraiserId = response["fundraiserId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid fundraiser response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "fundraiser_create")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let factoryAddress = response["factoryAddress"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: factoryAddress, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "fundraiser_create")
            }
        }

        return FundraiserResult(
            fundraiserId: fundraiserId,
            title: title,
            goalAmount: goal,
            contractAddress: response["contractAddress"] as? String ?? "",
            transactionHash: txHash,
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

        guard let attestationId = response["attestationId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid attestation response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "attestation")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let easContract = response["easContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: easContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "attestation")
            }
        }

        return AttestationResult(
            attestationId: attestationId,
            schemaId: schemaId,
            transactionHash: txHash,
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid identity response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "identity_register")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let identityContract = response["identityContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: identityContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "identity_register")
            }
        }

        return IdentityResult(
            did: did,
            attestations: response["attestations"] as? [String] ?? [],
            transactionHash: txHash,
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

        guard let paymentId = response["paymentId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid payment response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "payment")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let tokenContract = response["tokenContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: tokenContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "payment")
            }
        }

        return PaymentResult(
            paymentId: paymentId,
            amount: amount,
            recipient: to,
            transactionHash: txHash,
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

        guard let swapId = response["swapId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid swap response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "dex_swap")

        // Swap typically needs approve + swap as batch
        if let calldataItems = response["batchCalldata"] as? [[String: Any]],
           let manager = erc4337Manager {
            let calls: [(to: String, value: UInt64, data: Data)] = calldataItems.compactMap { item in
                guard let to = item["to"] as? String,
                      let dataHex = item["data"] as? String,
                      let data = Data(hexString: dataHex) else { return nil }
                let value = UInt64(item["value"] as? String ?? "0") ?? 0
                return (to: to, value: value, data: data)
            }
            if !calls.isEmpty {
                let batchResult = manager.buildBatchUserOperation(calls: calls)
                if case .success(let op) = batchResult {
                    _ = try? await submitSignedOperation(op, type: "dex_swap")
                }
            }
        }

        return SwapResult(
            swapId: swapId,
            fromToken: fromToken,
            toToken: toToken,
            amountIn: amountIn,
            amountOut: response["amountOut"] as? UInt64 ?? 0,
            transactionHash: txHash,
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

        guard let rewardId = response["rewardId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid reward response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "reward_claim")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let rewardsContract = response["rewardsContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: rewardsContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "reward_claim")
            }
        }

        return RewardResult(
            rewardId: rewardId,
            programId: programId,
            pointsEarned: response["pointsEarned"] as? UInt64 ?? 0,
            transactionHash: txHash,
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

        guard let subscriptionId = response["subscriptionId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid subscription response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "subscription")

        let cost = UInt64(response["costWei"] as? String ?? "0") ?? 0
        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let subContract = response["subscriptionContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: subContract, value: cost, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "subscription")
            }
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
            transactionHash: txHash,
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid unstake response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "unstake")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let stakingContract = response["stakingContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: stakingContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "unstake")
            }
        }

        return TransactionResult(
            transactionHash: txHash,
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid repayment response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "loan_repay")

        if let calldataItems = response["batchCalldata"] as? [[String: Any]],
           let manager = erc4337Manager {
            let calls: [(to: String, value: UInt64, data: Data)] = calldataItems.compactMap { item in
                guard let to = item["to"] as? String,
                      let dataHex = item["data"] as? String,
                      let data = Data(hexString: dataHex) else { return nil }
                let value = UInt64(item["value"] as? String ?? "0") ?? 0
                return (to: to, value: value, data: data)
            }
            if !calls.isEmpty {
                let batchResult = manager.buildBatchUserOperation(calls: calls)
                if case .success(let op) = batchResult {
                    _ = try? await submitSignedOperation(op, type: "loan_repay")
                }
            }
        }

        return TransactionResult(
            transactionHash: txHash,
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

        guard let contractAddress = response["contractAddress"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid tokenization response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "rwa_tokenize")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let factoryAddress = response["factoryAddress"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: factoryAddress, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "rwa_tokenize")
            }
        }

        return ContractResult(
            contractAddress: contractAddress,
            deploymentTxHash: txHash,
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid dispute response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "dispute_file")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let disputeContract = response["disputeContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: disputeContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "dispute_file")
            }
        }

        return TransactionResult(
            transactionHash: txHash,
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid IP registration response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "ip_register")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let ipContract = response["ipContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: ipContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "ip_register")
            }
        }

        return TransactionResult(
            transactionHash: txHash,
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid supply chain response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "supply_chain_event")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let scContract = response["supplyChainContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: scContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "supply_chain_event")
            }
        }

        return TransactionResult(
            transactionHash: txHash,
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Request oracle data and store the result on-chain.
    func requestOracleData(feedId: String) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/oracle/request", body: [
            "feedId": feedId,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid oracle response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "oracle_request")

        return TransactionResult(
            transactionHash: txHash,
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid gaming purchase response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "gaming_purchase")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let gameContract = response["gameContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: gameContract, value: price, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "gaming_purchase")
            }
        }

        return TransactionResult(
            transactionHash: txHash,
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Issue a security token.
    func issueSecurityToken(params: [String: Any]) async throws -> ContractResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        var body = params
        body["walletAddress"] = connectedWalletAddress ?? ""
        body["chainId"] = String(chainId)

        let response = try await postToAPI(endpoint: "blockchain/securities/issue", body: body)

        guard let contractAddress = response["contractAddress"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid securities response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "security_issue")

        return ContractResult(
            contractAddress: contractAddress,
            deploymentTxHash: txHash,
            templateId: response["templateId"] as? String ?? "security_token",
            status: .pending,
            abi: response["abi"] as? String
        )
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid stablecoin mint response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "stablecoin_mint")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let stablecoinContract = response["stablecoinContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: stablecoinContract, value: collateral, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "stablecoin_mint")
            }
        }

        return TransactionResult(
            transactionHash: txHash,
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

        guard let paymentId = response["paymentId"] as? String,
              let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid agentic payment response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "agentic_payment")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let paymentContract = response["paymentContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: paymentContract, value: amount, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "agentic_payment")
            }
        }

        return PaymentResult(
            paymentId: paymentId,
            amount: amount,
            recipient: agentId,
            transactionHash: txHash,
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

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid private transfer response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "private_transfer")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let privacyContract = response["privacyContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: privacyContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "private_transfer")
            }
        }

        return TransactionResult(
            transactionHash: txHash,
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Post to the social module (on-chain social graph).
    func socialPost(content: String, metadata: [String: Any]) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/social/post", body: [
            "content": content,
            "metadata": metadata,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid social post response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "social_post")

        return TransactionResult(
            transactionHash: txHash,
            operationHash: opHash,
            status: .pending,
            gasUsed: 0,
            blockNumber: nil,
            timestamp: Date()
        )
    }

    /// Redeem cashback or brand rewards.
    func redeemCashback(rewardId: String) async throws -> TransactionResult {
        guard isWalletConnected else { throw BlockchainBridgeError.walletNotConnected }

        let response = try await postToAPI(endpoint: "blockchain/cashback/redeem", body: [
            "rewardId": rewardId,
            "walletAddress": connectedWalletAddress ?? "",
            "chainId": String(chainId)
        ])

        guard let txHash = response["transactionHash"] as? String else {
            throw BlockchainBridgeError.transactionFailed(reason: "Invalid cashback redemption response")
        }

        let opHash = response["operationHash"] as? String ?? txHash
        transactionTracker.track(operationHash: opHash, type: "cashback_redeem")

        if let calldataHex = response["calldata"] as? String,
           let calldata = Data(hexString: calldataHex),
           let cashbackContract = response["cashbackContract"] as? String,
           let manager = erc4337Manager {
            let opResult = manager.buildUserOperation(to: cashbackContract, value: 0, data: calldata)
            if case .success(let op) = opResult {
                _ = try? await submitSignedOperation(op, type: "cashback_redeem")
            }
        }

        return TransactionResult(
            transactionHash: txHash,
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
