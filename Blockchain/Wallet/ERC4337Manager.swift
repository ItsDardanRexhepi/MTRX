// ERC4337Manager.swift
// MTRX Blockchain - Wallet
//
// ERC-4337 Account Abstraction on Base L2

import Foundation

// MARK: - Protocols

protocol ERC4337ManagerDelegate: AnyObject {
    func manager(_ manager: ERC4337Manager, didSubmitOperation operation: UserOperation)
    func manager(_ manager: ERC4337Manager, didFailWithError error: ERC4337Error)
    func manager(_ manager: ERC4337Manager, didConfirmOperation operationHash: String)
}

// MARK: - Data Models

struct UserOperation: Codable {
    let sender: String
    let nonce: UInt64
    let initCode: Data
    let callData: Data
    let callGasLimit: UInt64
    let verificationGasLimit: UInt64
    let preVerificationGas: UInt64
    let maxFeePerGas: UInt64
    let maxPriorityFeePerGas: UInt64
    let paymasterAndData: Data
    let signature: Data

    var hash: String {
        // Compute UserOperation hash per ERC-4337 spec
        return computeHash()
    }

    private func computeHash() -> String {
        // TODO: Implement keccak256 hashing of packed UserOperation fields
        return ""
    }
}

struct SmartAccountConfig {
    let factoryAddress: String
    let implementationAddress: String
    let salt: UInt64
    let ownerAddress: String
}

enum ERC4337Error: Error, LocalizedError {
    case accountNotDeployed
    case invalidEntryPoint
    case bundlerRejected(reason: String)
    case paymasterRefused
    case insufficientGas
    case invalidSignature
    case nonceMismatch
    case simulationFailed(reason: String)
    case networkError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .accountNotDeployed: return "Smart account has not been deployed yet."
        case .invalidEntryPoint: return "Invalid EntryPoint contract address."
        case .bundlerRejected(let reason): return "Bundler rejected operation: \(reason)"
        case .paymasterRefused: return "Paymaster refused to sponsor this operation."
        case .insufficientGas: return "Insufficient gas for operation execution."
        case .invalidSignature: return "UserOperation signature is invalid."
        case .nonceMismatch: return "Account nonce mismatch."
        case .simulationFailed(let reason): return "Simulation failed: \(reason)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

// MARK: - ERC4337Manager

final class ERC4337Manager {

    // MARK: - Properties

    weak var delegate: ERC4337ManagerDelegate?

    /// The smart account address managed by this instance
    private(set) var accountAddress: String?

    /// ERC-4337 EntryPoint contract address on Base
    let entryPointAddress: String

    /// Paymaster contract address for gas sponsorship
    let paymasterAddress: String?

    /// Bundler RPC endpoint URL
    private let bundlerURL: URL

    /// Base network configuration
    private let networkConfig: BaseNetworkConfig

    /// Current account nonce
    private var currentNonce: UInt64 = 0

    /// Whether the smart account has been deployed on-chain
    private(set) var isAccountDeployed: Bool = false

    /// Pending operations awaiting confirmation
    private var pendingOperations: [String: UserOperation] = [:]

    /// Operation submission queue
    private let operationQueue = DispatchQueue(label: "com.mtrx.erc4337.operations", qos: .userInitiated)

    // MARK: - Initialization

    init(
        entryPointAddress: String = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789",
        paymasterAddress: String? = nil,
        bundlerURL: URL,
        networkConfig: BaseNetworkConfig
    ) {
        self.entryPointAddress = entryPointAddress
        self.paymasterAddress = paymasterAddress
        self.bundlerURL = bundlerURL
        self.networkConfig = networkConfig
    }

    // MARK: - Account Management

    /// Compute the counterfactual address for a smart account
    func computeAccountAddress(config: SmartAccountConfig) -> String {
        // TODO: Implement CREATE2 address derivation
        // Uses factory address, implementation, salt, and owner
        return ""
    }

    /// Deploy the smart account on-chain via the factory
    func deployAccount(config: SmartAccountConfig, completion: @escaping (Result<String, ERC4337Error>) -> Void) {
        operationQueue.async { [weak self] in
            guard let self = self else { return }
            // TODO: Construct initCode from factory + createAccount calldata
            // Submit as part of the first UserOperation
            let address = self.computeAccountAddress(config: config)
            self.accountAddress = address
            self.isAccountDeployed = true
            completion(.success(address))
        }
    }

    /// Check if the smart account is deployed on-chain
    func checkAccountDeployment(address: String, completion: @escaping (Bool) -> Void) {
        // TODO: Call eth_getCode on the account address
        completion(false)
    }

    // MARK: - UserOperation Construction

    /// Build a UserOperation for a single contract call
    func buildUserOperation(
        to: String,
        value: UInt64,
        data: Data,
        sponsorGas: Bool = true
    ) -> Result<UserOperation, ERC4337Error> {
        guard let sender = accountAddress else {
            return .failure(.accountNotDeployed)
        }

        let callData = encodeExecuteCalldata(to: to, value: value, data: data)
        let initCode = isAccountDeployed ? Data() : buildInitCode()

        let operation = UserOperation(
            sender: sender,
            nonce: currentNonce,
            initCode: initCode,
            callData: callData,
            callGasLimit: 200_000,
            verificationGasLimit: 100_000,
            preVerificationGas: 50_000,
            maxFeePerGas: 1_000_000,
            maxPriorityFeePerGas: 1_000_000,
            paymasterAndData: sponsorGas ? buildPaymasterData() : Data(),
            signature: Data()
        )

        return .success(operation)
    }

    /// Build a batched UserOperation for multiple contract calls
    func buildBatchUserOperation(
        calls: [(to: String, value: UInt64, data: Data)],
        sponsorGas: Bool = true
    ) -> Result<UserOperation, ERC4337Error> {
        guard let sender = accountAddress else {
            return .failure(.accountNotDeployed)
        }

        let callData = encodeBatchExecuteCalldata(calls: calls)

        let operation = UserOperation(
            sender: sender,
            nonce: currentNonce,
            initCode: isAccountDeployed ? Data() : buildInitCode(),
            callData: callData,
            callGasLimit: 300_000 * UInt64(calls.count),
            verificationGasLimit: 150_000,
            preVerificationGas: 50_000,
            maxFeePerGas: 1_000_000,
            maxPriorityFeePerGas: 1_000_000,
            paymasterAndData: sponsorGas ? buildPaymasterData() : Data(),
            signature: Data()
        )

        return .success(operation)
    }

    // MARK: - Gas Estimation

    /// Estimate gas for a UserOperation using the bundler
    func estimateGas(for operation: UserOperation, completion: @escaping (Result<UserOperation, ERC4337Error>) -> Void) {
        // TODO: Call eth_estimateUserOperationGas on bundler
        // Update callGasLimit, verificationGasLimit, preVerificationGas
        completion(.success(operation))
    }

    // MARK: - Bundler Submission

    /// Submit a signed UserOperation to the bundler
    func submitOperation(_ operation: UserOperation, completion: @escaping (Result<String, ERC4337Error>) -> Void) {
        operationQueue.async { [weak self] in
            guard let self = self else { return }

            // TODO: Serialize UserOperation and send to bundler via eth_sendUserOperation
            // Store in pending operations
            let opHash = operation.hash
            self.pendingOperations[opHash] = operation
            self.currentNonce += 1

            DispatchQueue.main.async {
                self.delegate?.manager(self, didSubmitOperation: operation)
                completion(.success(opHash))
            }
        }
    }

    /// Check the status of a submitted UserOperation
    func getOperationReceipt(operationHash: String, completion: @escaping (Result<OperationReceipt, ERC4337Error>) -> Void) {
        // TODO: Call eth_getUserOperationReceipt on bundler
        completion(.failure(.simulationFailed(reason: "Not implemented")))
    }

    /// Wait for a UserOperation to be included in a block
    func waitForOperation(operationHash: String, timeout: TimeInterval = 60, completion: @escaping (Result<OperationReceipt, ERC4337Error>) -> Void) {
        // TODO: Poll for receipt with exponential backoff
        completion(.failure(.simulationFailed(reason: "Not implemented")))
    }

    // MARK: - Signature

    /// Sign a UserOperation with the account owner's key
    func signOperation(_ operation: UserOperation, completion: @escaping (Result<UserOperation, ERC4337Error>) -> Void) {
        // TODO: Sign using Secure Enclave key
        // Hash the operation, sign with owner key, return updated operation
        completion(.success(operation))
    }

    // MARK: - Private Helpers

    private func encodeExecuteCalldata(to: String, value: UInt64, data: Data) -> Data {
        // TODO: ABI-encode execute(address, uint256, bytes)
        return Data()
    }

    private func encodeBatchExecuteCalldata(calls: [(to: String, value: UInt64, data: Data)]) -> Data {
        // TODO: ABI-encode executeBatch(address[], uint256[], bytes[])
        return Data()
    }

    private func buildInitCode() -> Data {
        // TODO: Encode factory address + createAccount calldata
        return Data()
    }

    private func buildPaymasterData() -> Data {
        guard let paymaster = paymasterAddress else { return Data() }
        // TODO: Encode paymaster address + paymaster-specific data
        _ = paymaster
        return Data()
    }
}

// MARK: - Supporting Types

struct OperationReceipt {
    let operationHash: String
    let transactionHash: String
    let blockNumber: UInt64
    let success: Bool
    let gasUsed: UInt64
    let logs: [OperationLog]
}

struct OperationLog {
    let address: String
    let topics: [String]
    let data: Data
}

struct BaseNetworkConfig {
    let rpcURL: URL
    let chainId: UInt64
    let bundlerURL: URL
}
