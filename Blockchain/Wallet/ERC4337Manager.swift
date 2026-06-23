// ERC4337Manager.swift
// MTRX Blockchain - Wallet
//
// ERC-4337 Account Abstraction on Base L2

import Foundation
import CryptoKit
import LocalAuthentication

// MARK: - Protocols

protocol ERC4337ManagerDelegate: AnyObject {
    func manager(_ manager: ERC4337Manager, didSubmitOperation operation: UserOperation)
    func manager(_ manager: ERC4337Manager, didFailWithError error: ERC4337Error)
    func manager(_ manager: ERC4337Manager, didConfirmOperation operationHash: String)
}

// MARK: - Keccak256 Utility

/// True Ethereum keccak256 (Keccak-f[1600], rate 1088, capacity 512, original
/// Keccak `0x01` padding — NOT NIST SHA3-256's `0x06`). Pure Swift, no external
/// dependency. This is the hash Ethereum requires for function selectors, the
/// ERC-4337 UserOperation hash, and CREATE2 addresses. Verified against known
/// vectors in `WalletTests` (e.g. keccak256("") and the standard ERC-20 selectors).
enum Keccak256 {

    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]

    // Rho rotation offsets, indexed [x + 5*y].
    private static let rotationOffsets: [Int] = [
        0, 1, 62, 28, 27,
        36, 44, 6, 55, 20,
        3, 10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2, 61, 56, 14,
    ]

    @inline(__always)
    private static func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
        n == 0 ? x : (x << UInt64(n)) | (x >> UInt64(64 - n))
    }

    private static func keccakF(_ a: inout [UInt64]) {
        for round in 0..<24 {
            // Theta
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 { c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] }
            var d = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 { d[x] = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1) }
            for y in 0..<5 { for x in 0..<5 { a[x + 5 * y] ^= d[x] } }
            // Rho + Pi
            var b = [UInt64](repeating: 0, count: 25)
            for y in 0..<5 {
                for x in 0..<5 {
                    let idx = x + 5 * y
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(a[idx], rotationOffsets[idx])
                }
            }
            // Chi
            for y in 0..<5 {
                for x in 0..<5 {
                    a[x + 5 * y] = b[x + 5 * y] ^ (~b[(x + 1) % 5 + 5 * y] & b[(x + 2) % 5 + 5 * y])
                }
            }
            // Iota
            a[0] ^= roundConstants[round]
        }
    }

    static func hash(data: Data) -> Data {
        let rate = 136 // bytes (1088 bits) for keccak-256
        var message = [UInt8](data)
        // Padding: append 0x01, zero-fill to a multiple of rate, set the final byte's high bit.
        message.append(0x01)
        while message.count % rate != 0 { message.append(0x00) }
        message[message.count - 1] |= 0x80

        var state = [UInt64](repeating: 0, count: 25)
        var offset = 0
        while offset < message.count {
            for i in 0..<(rate / 8) {
                var lane: UInt64 = 0
                for j in 0..<8 { lane |= UInt64(message[offset + i * 8 + j]) << UInt64(8 * j) }
                state[i] ^= lane
            }
            keccakF(&state)
            offset += rate
        }

        // Squeeze the first 32 bytes (4 little-endian lanes).
        var out = [UInt8]()
        out.reserveCapacity(32)
        for i in 0..<4 {
            let lane = state[i]
            for j in 0..<8 { out.append(UInt8((lane >> UInt64(8 * j)) & 0xff)) }
        }
        return Data(out)
    }

    static func hashHex(data: Data) -> String {
        let bytes = hash(data: data)
        return "0x" + bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ABI Encoding Helpers

enum ABIEncoder {

    /// Pad a 20-byte address to 32 bytes (left-padded with zeros).
    static func encodeAddress(_ hex: String) -> Data {
        let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let addressBytes = Data(hexString: cleaned) ?? Data(repeating: 0, count: 20)
        var padded = Data(repeating: 0, count: 12)
        padded.append(addressBytes)
        return padded
    }

    /// Encode a UInt64 value into a 32-byte big-endian word.
    static func encodeUInt256(_ value: UInt64) -> Data {
        var padded = Data(repeating: 0, count: 24)
        var bigEndian = value.bigEndian
        padded.append(Data(bytes: &bigEndian, count: 8))
        return padded
    }

    /// Encode raw bytes with length prefix and padding.
    static func encodeBytes(_ data: Data) -> Data {
        let lengthWord = encodeUInt256(UInt64(data.count))
        let paddingNeeded = (32 - (data.count % 32)) % 32
        var result = lengthWord
        result.append(data)
        result.append(Data(repeating: 0, count: paddingNeeded))
        return result
    }

    /// Encode a dynamic bytes offset pointer.
    static func encodeOffset(_ offset: UInt64) -> Data {
        return encodeUInt256(offset)
    }

    /// Compute the 4-byte function selector from a function signature string.
    static func functionSelector(_ signature: String) -> Data {
        let sigData = Data(signature.utf8)
        let hash = Keccak256.hash(data: sigData)
        return hash.prefix(4)
    }
}

// MARK: - Data hex-string initializer

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

    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
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
        return computeHash()
    }

    /// Pack fields per ERC-4337 spec and compute keccak256.
    ///
    /// packForHash = abi.encode(
    ///   sender, nonce,
    ///   keccak256(initCode), keccak256(callData),
    ///   callGasLimit, verificationGasLimit, preVerificationGas,
    ///   maxFeePerGas, maxPriorityFeePerGas,
    ///   keccak256(paymasterAndData)
    /// )
    /// hash = keccak256(packForHash)
    private func computeHash() -> String {
        var packed = Data()

        // sender (address, 32-byte padded)
        packed.append(ABIEncoder.encodeAddress(sender))

        // nonce
        packed.append(ABIEncoder.encodeUInt256(nonce))

        // keccak256(initCode)
        packed.append(Keccak256.hash(data: initCode))

        // keccak256(callData)
        packed.append(Keccak256.hash(data: callData))

        // gas fields
        packed.append(ABIEncoder.encodeUInt256(callGasLimit))
        packed.append(ABIEncoder.encodeUInt256(verificationGasLimit))
        packed.append(ABIEncoder.encodeUInt256(preVerificationGas))
        packed.append(ABIEncoder.encodeUInt256(maxFeePerGas))
        packed.append(ABIEncoder.encodeUInt256(maxPriorityFeePerGas))

        // keccak256(paymasterAndData)
        packed.append(Keccak256.hash(data: paymasterAndData))

        return Keccak256.hashHex(data: packed)
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
    /// Testnet-only lock: refused to sign against a non-permitted chain (e.g. mainnet).
    case signingChainNotPermitted(chainId: UInt64)

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
        case .signingChainNotPermitted(let id):
            return "Testnet-only build — signing is restricted to Base Sepolia "
                + "(\(BaseNetworkConfig.permittedSigningChainID)); chain \(id) is not permitted. Nothing was signed."
        }
    }
}

// MARK: - ERC4337Manager

final class ERC4337Manager {

    // MARK: - Properties

    weak var delegate: ERC4337ManagerDelegate?

    /// The smart account address managed by this instance
    private(set) var accountAddress: String?

    /// The user's Secure Enclave key tag used to sign UserOperations (set when
    /// the wallet connects). Signing NEVER falls back to a throwaway key — if
    /// this is nil, `signOperation` fails. P-256/RIP-7212 CONSTRAINT: the on-chain
    /// account factory + validation MUST verify P-256 (secp256r1) signatures,
    /// because the Secure Enclave signs P-256 and cannot produce secp256k1.
    private(set) var signingKeyTag: String?

    /// ERC-4337 EntryPoint contract address on Base
    let entryPointAddress: String

    /// Paymaster contract address for gas sponsorship
    let paymasterAddress: String?

    /// Bundler RPC endpoint URL
    private let bundlerURL: URL

    /// Base network configuration
    private let networkConfig: BaseNetworkConfig

    /// URL session for bundler RPC calls
    private let session: URLSession

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
        entryPointAddress: String = PendingCredentials.filled(PendingCredentials.AccountAbstraction.entryPointAddress) ?? "",
        paymasterAddress: String? = PendingCredentials.filled(PendingCredentials.AccountAbstraction.paymasterAddress),
        bundlerURL: URL,
        networkConfig: BaseNetworkConfig,
        session: URLSession? = nil
    ) {
        self.entryPointAddress = entryPointAddress
        self.paymasterAddress = paymasterAddress
        self.bundlerURL = bundlerURL
        self.networkConfig = networkConfig

        if let session = session {
            // Injected (e.g. a MockURLProtocol session in tests).
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Account Management

    /// Set the account address externally (used by BlockchainBridge for connecting existing wallets).
    func setAccountAddress(_ address: String) {
        self.accountAddress = address
    }

    /// Configure the Secure Enclave key tag this manager signs UserOperations
    /// with (e.g. WalletCore's "wallet.<appleUserId>"). Required before signing.
    func configureSigningKey(tag: String) {
        self.signingKeyTag = tag
    }

    /// Compute the counterfactual address for a smart account using CREATE2.
    ///
    /// address = keccak256(0xff ++ factory ++ salt ++ keccak256(initCodeHash))[12:]
    func computeAccountAddress(config: SmartAccountConfig) -> String {
        // Build the init code that the factory would deploy
        let createAccountCalldata = encodeCreateAccountCalldata(
            owner: config.ownerAddress,
            salt: config.salt
        )

        // keccak256 of the init code (implementation bytecode proxy)
        let initCodeHash = Keccak256.hash(data: createAccountCalldata)

        // Salt as 32 bytes
        let saltBytes = ABIEncoder.encodeUInt256(config.salt)

        // Pack: 0xff ++ factory ++ salt ++ keccak256(initCode)
        var packed = Data([0xff])
        let factoryClean = config.factoryAddress.hasPrefix("0x")
            ? String(config.factoryAddress.dropFirst(2))
            : config.factoryAddress
        packed.append(Data(hexString: factoryClean) ?? Data(repeating: 0, count: 20))
        packed.append(saltBytes)
        packed.append(initCodeHash)

        let hash = Keccak256.hash(data: packed)
        // Last 20 bytes are the address
        let addressBytes = hash.suffix(20)
        return "0x" + addressBytes.hexString
    }

    /// Deploy the smart account on-chain via the factory
    func deployAccount(config: SmartAccountConfig, completion: @escaping (Result<String, ERC4337Error>) -> Void) {
        operationQueue.async { [weak self] in
            guard let self = self else { return }

            let address = self.computeAccountAddress(config: config)
            self.accountAddress = address

            // Build a UserOperation with initCode to deploy the account
            let initCode = self.buildInitCode(owner: config.ownerAddress, salt: config.salt)
            // Send a no-op callData (0x) so the first UserOp deploys the account
            let deployOp = UserOperation(
                sender: address,
                nonce: 0,
                initCode: initCode,
                callData: Data(),
                callGasLimit: 300_000,
                verificationGasLimit: 500_000,
                preVerificationGas: 100_000,
                maxFeePerGas: 1_000_000,
                maxPriorityFeePerGas: 1_000_000,
                paymasterAndData: self.buildPaymasterData(),
                signature: Data()
            )

            self.submitOperation(deployOp) { result in
                switch result {
                case .success:
                    self.isAccountDeployed = true
                    completion(.success(address))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// Check if the smart account is deployed on-chain
    func checkAccountDeployment(address: String, completion: @escaping (Bool) -> Void) {
        let rpcURL = networkConfig.rpcURL
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getCode",
            "params": [address, "latest"],
            "id": 1
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? String else {
                completion(false)
                return
            }
            // If code is "0x" or empty, account is not deployed
            let deployed = result != "0x" && result.count > 2
            completion(deployed)
        }.resume()
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

    /// Build an unsigned UserOperation that calls `execute(target, value, data)`
    /// on the smart account. Paymaster data + signature are attached later by the
    /// sponsorship and enclave-signing steps of the submit pipeline.
    func buildUserOperation(to target: String, value: UInt64, data: Data) -> Result<UserOperation, ERC4337Error> {
        guard let sender = accountAddress else { return .failure(.accountNotDeployed) }
        let callData = encodeExecuteCalldata(to: target, value: value, data: data)
        let operation = UserOperation(
            sender: sender,
            nonce: currentNonce,
            initCode: isAccountDeployed ? Data() : buildInitCode(),
            callData: callData,
            callGasLimit: 200_000,
            verificationGasLimit: 150_000,
            preVerificationGas: 50_000,
            maxFeePerGas: 1_000_000,
            maxPriorityFeePerGas: 1_000_000,
            paymasterAndData: Data(),
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

    /// Estimate gas for a UserOperation by calling eth_estimateUserOperationGas on the bundler.
    func estimateGas(for operation: UserOperation, completion: @escaping (Result<UserOperation, ERC4337Error>) -> Void) {
        let opDict = serializeUserOperation(operation)

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_estimateUserOperationGas",
            "params": [opDict, entryPointAddress],
            "id": 1
        ]

        sendBundlerRequest(body: body) { result in
            switch result {
            case .success(let json):
                guard let resultDict = json["result"] as? [String: Any] else {
                    completion(.failure(.simulationFailed(reason: "Invalid gas estimation response")))
                    return
                }

                let callGas = self.parseHexUInt64(resultDict["callGasLimit"]) ?? operation.callGasLimit
                let verificationGas = self.parseHexUInt64(resultDict["verificationGasLimit"]) ?? operation.verificationGasLimit
                let preVerificationGas = self.parseHexUInt64(resultDict["preVerificationGas"]) ?? operation.preVerificationGas

                let updated = UserOperation(
                    sender: operation.sender,
                    nonce: operation.nonce,
                    initCode: operation.initCode,
                    callData: operation.callData,
                    callGasLimit: callGas,
                    verificationGasLimit: verificationGas,
                    preVerificationGas: preVerificationGas,
                    maxFeePerGas: operation.maxFeePerGas,
                    maxPriorityFeePerGas: operation.maxPriorityFeePerGas,
                    paymasterAndData: operation.paymasterAndData,
                    signature: operation.signature
                )
                completion(.success(updated))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Bundler Submission

    /// Submit a signed UserOperation to the bundler via eth_sendUserOperation.
    func submitOperation(_ operation: UserOperation, completion: @escaping (Result<String, ERC4337Error>) -> Void) {
        operationQueue.async { [weak self] in
            guard let self = self else { return }

            let opDict = self.serializeUserOperation(operation)

            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "eth_sendUserOperation",
                "params": [opDict, self.entryPointAddress],
                "id": 1
            ]

            self.sendBundlerRequest(body: body) { result in
                switch result {
                case .success(let json):
                    guard let opHash = json["result"] as? String else {
                        let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown bundler error"
                        self.delegate?.manager(self, didFailWithError: .bundlerRejected(reason: errorMsg))
                        completion(.failure(.bundlerRejected(reason: errorMsg)))
                        return
                    }

                    self.pendingOperations[opHash] = operation
                    self.currentNonce += 1

                    DispatchQueue.main.async {
                        self.delegate?.manager(self, didSubmitOperation: operation)
                        completion(.success(opHash))
                    }

                case .failure(let error):
                    DispatchQueue.main.async {
                        self.delegate?.manager(self, didFailWithError: error)
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    /// Check the status of a submitted UserOperation
    func getOperationReceipt(operationHash: String, completion: @escaping (Result<OperationReceipt, ERC4337Error>) -> Void) {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getUserOperationReceipt",
            "params": [operationHash],
            "id": 1
        ]

        sendBundlerRequest(body: body) { result in
            switch result {
            case .success(let json):
                guard let resultDict = json["result"] as? [String: Any],
                      let txHash = resultDict["transactionHash"] as? String,
                      let success = resultDict["success"] as? Bool else {
                    completion(.failure(.simulationFailed(reason: "Receipt not available yet")))
                    return
                }

                let blockNumber = self.parseHexUInt64(resultDict["blockNumber"]) ?? 0
                let gasUsed = self.parseHexUInt64(resultDict["actualGasUsed"]) ?? 0

                var logs: [OperationLog] = []
                if let logsArray = resultDict["logs"] as? [[String: Any]] {
                    logs = logsArray.map { logDict in
                        OperationLog(
                            address: logDict["address"] as? String ?? "",
                            topics: logDict["topics"] as? [String] ?? [],
                            data: Data(hexString: (logDict["data"] as? String ?? "")) ?? Data()
                        )
                    }
                }

                let receipt = OperationReceipt(
                    operationHash: operationHash,
                    transactionHash: txHash,
                    blockNumber: blockNumber,
                    success: success,
                    gasUsed: gasUsed,
                    logs: logs
                )

                if success {
                    self.pendingOperations.removeValue(forKey: operationHash)
                    DispatchQueue.main.async {
                        self.delegate?.manager(self, didConfirmOperation: operationHash)
                    }
                }

                completion(.success(receipt))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Wait for a UserOperation to be included in a block with exponential backoff.
    func waitForOperation(operationHash: String, timeout: TimeInterval = 60, completion: @escaping (Result<OperationReceipt, ERC4337Error>) -> Void) {
        let startTime = Date()
        var delay: TimeInterval = 1.0

        func poll() {
            guard Date().timeIntervalSince(startTime) < timeout else {
                completion(.failure(.simulationFailed(reason: "Timeout waiting for operation confirmation")))
                return
            }

            getOperationReceipt(operationHash: operationHash) { result in
                switch result {
                case .success(let receipt):
                    completion(.success(receipt))
                case .failure:
                    // Exponential backoff: 1s, 2s, 4s, 8s, capped at 10s
                    let currentDelay = delay
                    delay = min(delay * 2, 10.0)
                    DispatchQueue.global().asyncAfter(deadline: .now() + currentDelay) {
                        poll()
                    }
                }
            }
        }

        poll()
    }

    // MARK: - Signature

    /// Sign a UserOperation with the account owner's **Secure Enclave** key.
    ///
    /// This NEVER signs with a throwaway/ephemeral key. If no enclave key tag has
    /// been configured (`configureSigningKey(tag:)`), it fails — a signature from
    /// a random key would never validate against the on-chain account owner, so
    /// refusing is correct. The actual signing goes through the enclave provider
    /// (CryptoKit SecureEnclave.P256 / software-P256 fallback), keyed to the
    /// user's tag.
    ///
    /// P-256/RIP-7212 CONSTRAINT: the on-chain account validation MUST verify
    /// P-256 (secp256r1) — the Secure Enclave cannot produce secp256k1 sigs.
    func signOperation(_ operation: UserOperation, context: LAContext? = nil, completion: @escaping (Result<UserOperation, ERC4337Error>) -> Void) {
        guard let keyTag = signingKeyTag else {
            // No enclave signing key configured — refuse rather than sign with a
            // throwaway key (which would fail on-chain validation anyway).
            completion(.failure(.invalidSignature))
            return
        }
        signOperation(operation, with: DefaultSecureEnclaveProvider(), keyTag: keyTag, context: context, completion: completion)
    }

    /// Sign a UserOperation using an externally provided Secure Enclave provider.
    ///
    /// `context` (P3.2, decision #2): an already-authenticated `LAContext` the
    /// enclave reuses so a biometric-gated key doesn't prompt a second time for
    /// the same user action. `nil` (default) → the enclave authenticates this
    /// signature on its own with a fresh, reuse-0 context.
    func signOperation(_ operation: UserOperation, with secureEnclave: SecureEnclaveProvider, keyTag: String, context: LAContext? = nil, completion: @escaping (Result<UserOperation, ERC4337Error>) -> Void) {
        // Testnet-only lock (P2.0): this is the SINGLE sign primitive every signing path
        // funnels into (BlockchainBridge, NFTManager, DAOManager, WalletTransactionService,
        // and any future caller). Fail CLOSED before computing the message or producing any
        // signature if the chain is not the permitted testnet (Base Sepolia). Mainnet — and
        // every other chain — must never be signed against in this phase.
        guard networkConfig.isSigningPermitted else {
            completion(.failure(.signingChainNotPermitted(chainId: networkConfig.chainId)))
            return
        }
        let opHash = operation.hash
        guard let hashData = Data(hexString: opHash) else {
            completion(.failure(.invalidSignature))
            return
        }

        var message = Data()
        message.append(hashData)
        message.append(ABIEncoder.encodeAddress(entryPointAddress))
        message.append(ABIEncoder.encodeUInt256(networkConfig.chainId))
        let messageHash = Keccak256.hash(data: message)

        do {
            let sigData = try secureEnclave.sign(data: messageHash, withKeyTag: keyTag, context: context)

            let signedOp = UserOperation(
                sender: operation.sender,
                nonce: operation.nonce,
                initCode: operation.initCode,
                callData: operation.callData,
                callGasLimit: operation.callGasLimit,
                verificationGasLimit: operation.verificationGasLimit,
                preVerificationGas: operation.preVerificationGas,
                maxFeePerGas: operation.maxFeePerGas,
                maxPriorityFeePerGas: operation.maxPriorityFeePerGas,
                paymasterAndData: operation.paymasterAndData,
                signature: sigData
            )
            completion(.success(signedOp))
        } catch {
            completion(.failure(.invalidSignature))
        }
    }

    // MARK: - Private Helpers

    /// ABI-encode execute(address target, uint256 value, bytes data)
    /// Selector: 0xb61d27f6
    private func encodeExecuteCalldata(to: String, value: UInt64, data: Data) -> Data {
        // Function selector for execute(address,uint256,bytes)
        let selector = ABIEncoder.functionSelector("execute(address,uint256,bytes)")

        var encoded = Data()
        encoded.append(selector)

        // target address
        encoded.append(ABIEncoder.encodeAddress(to))

        // value
        encoded.append(ABIEncoder.encodeUInt256(value))

        // offset to bytes data (3 words = 96 bytes)
        encoded.append(ABIEncoder.encodeOffset(96))

        // bytes data (length-prefixed + padded)
        encoded.append(ABIEncoder.encodeBytes(data))

        return encoded
    }

    /// ABI-encode executeBatch(address[] dest, uint256[] values, bytes[] func)
    /// Selector: 0x18dfb3c7
    private func encodeBatchExecuteCalldata(calls: [(to: String, value: UInt64, data: Data)]) -> Data {
        let selector = ABIEncoder.functionSelector("executeBatch(address[],uint256[],bytes[])")

        let count = UInt64(calls.count)

        // We need three dynamic arrays. Offsets point to where each array starts
        // after the three offset words (3 * 32 = 96 bytes from start of params).
        var addressArray = Data()
        addressArray.append(ABIEncoder.encodeUInt256(count)) // length
        for call in calls {
            addressArray.append(ABIEncoder.encodeAddress(call.to))
        }

        var valuesArray = Data()
        valuesArray.append(ABIEncoder.encodeUInt256(count)) // length
        for call in calls {
            valuesArray.append(ABIEncoder.encodeUInt256(call.value))
        }

        // bytes[] is an array of dynamic elements, each with its own offset
        var bytesArray = Data()
        bytesArray.append(ABIEncoder.encodeUInt256(count)) // length

        // First, compute offsets for each bytes element
        // Offsets are relative to the start of the bytes[] data (after the length word)
        // Each offset word is 32 bytes, so base offset = count * 32
        var bytesPayloads: [Data] = []
        for call in calls {
            bytesPayloads.append(ABIEncoder.encodeBytes(call.data))
        }

        var runningOffset = count * 32 // skip the offset words themselves
        for payload in bytesPayloads {
            bytesArray.append(ABIEncoder.encodeOffset(runningOffset))
            runningOffset += UInt64(payload.count)
        }
        for payload in bytesPayloads {
            bytesArray.append(payload)
        }

        // Compute offsets for the three top-level arrays
        let offset0: UInt64 = 96 // 3 offset words
        let offset1 = offset0 + UInt64(addressArray.count)
        let offset2 = offset1 + UInt64(valuesArray.count)

        var encoded = Data()
        encoded.append(selector)
        encoded.append(ABIEncoder.encodeOffset(offset0))
        encoded.append(ABIEncoder.encodeOffset(offset1))
        encoded.append(ABIEncoder.encodeOffset(offset2))
        encoded.append(addressArray)
        encoded.append(valuesArray)
        encoded.append(bytesArray)

        return encoded
    }

    /// Build init code: factory address (20 bytes) + createAccount(owner, salt) calldata.
    private func buildInitCode() -> Data {
        guard let account = accountAddress else { return Data() }
        // Use account address as a stand-in for owner in the default path;
        // in practice the owner address is stored in the smart account config.
        return buildInitCode(owner: account, salt: 0)
    }

    private func buildInitCode(owner: String = "", salt: UInt64 = 0) -> Data {
        // Factory address comes from PendingCredentials — no hardcoded value.
        // P-256 CONSTRAINT: this MUST be a P-256 / secp256r1-verifying account
        // factory (RIP-7212 / WebAuthn-style). The owner key is an Apple Secure
        // Enclave P-256 key, which cannot produce secp256k1 signatures, so a
        // stock secp256k1 SimpleAccountFactory would reject every UserOperation.
        let factoryAddress = PendingCredentials.filled(PendingCredentials.AccountAbstraction.accountFactoryAddress) ?? ""
        let factoryClean = factoryAddress.hasPrefix("0x") ? String(factoryAddress.dropFirst(2)) : factoryAddress
        let factoryBytes = Data(hexString: factoryClean) ?? Data(repeating: 0, count: 20)

        let calldata = encodeCreateAccountCalldata(owner: owner, salt: salt)

        var initCode = Data()
        initCode.append(factoryBytes)
        initCode.append(calldata)
        return initCode
    }

    /// Encode createAccount(address owner, uint256 salt)
    private func encodeCreateAccountCalldata(owner: String, salt: UInt64) -> Data {
        let selector = ABIEncoder.functionSelector("createAccount(address,uint256)")
        var data = Data()
        data.append(selector)
        data.append(ABIEncoder.encodeAddress(owner))
        data.append(ABIEncoder.encodeUInt256(salt))
        return data
    }

    /// Paymaster data is NOT assembled here. A valid verifying-paymaster
    /// `paymasterAndData` requires the paymaster's signature, and that key lives
    /// ONLY on the server — never in the app. So this returns empty ("unsponsored
    /// / self-paid"); the real, server-signed `paymasterAndData` is fetched from
    /// PendingCredentials.AccountAbstraction.paymasterSignatureEndpoint by
    /// GasSponsorship and attached to the UserOperation there. (Previously this
    /// emitted a 65-byte zero signature — a fake the EntryPoint would reject;
    /// that has been removed.)
    private func buildPaymasterData() -> Data {
        return Data()
    }

    // MARK: - Bundler RPC Helpers

    /// Serialize a UserOperation to a JSON-compatible dictionary for bundler RPC calls.
    private func serializeUserOperation(_ op: UserOperation) -> [String: Any] {
        return [
            "sender": op.sender,
            "nonce": "0x" + String(op.nonce, radix: 16),
            "initCode": "0x" + op.initCode.hexString,
            "callData": "0x" + op.callData.hexString,
            "callGasLimit": "0x" + String(op.callGasLimit, radix: 16),
            "verificationGasLimit": "0x" + String(op.verificationGasLimit, radix: 16),
            "preVerificationGas": "0x" + String(op.preVerificationGas, radix: 16),
            "maxFeePerGas": "0x" + String(op.maxFeePerGas, radix: 16),
            "maxPriorityFeePerGas": "0x" + String(op.maxPriorityFeePerGas, radix: 16),
            "paymasterAndData": "0x" + op.paymasterAndData.hexString,
            "signature": "0x" + op.signature.hexString
        ]
    }

    /// Send a JSON-RPC request to the bundler endpoint.
    private func sendBundlerRequest(body: [String: Any], completion: @escaping (Result<[String: Any], ERC4337Error>) -> Void) {
        var request = URLRequest(url: bundlerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(.simulationFailed(reason: "Failed to serialize RPC request")))
            return
        }
        request.httpBody = httpBody

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(underlying: error)))
                return
            }

            guard let data = data else {
                completion(.failure(.simulationFailed(reason: "Empty response from bundler")))
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.simulationFailed(reason: "Invalid JSON response from bundler")))
                return
            }

            // Check for JSON-RPC error
            if let errorDict = json["error"] as? [String: Any],
               let message = errorDict["message"] as? String {
                let code = errorDict["code"] as? Int ?? -1
                if message.lowercased().contains("nonce") {
                    completion(.failure(.nonceMismatch))
                } else if message.lowercased().contains("paymaster") {
                    completion(.failure(.paymasterRefused))
                } else if message.lowercased().contains("gas") {
                    completion(.failure(.insufficientGas))
                } else {
                    completion(.failure(.bundlerRejected(reason: "[\(code)] \(message)")))
                }
                return
            }

            completion(.success(json))
        }.resume()
    }

    /// Parse a hex string or number from a JSON-RPC response into UInt64.
    private func parseHexUInt64(_ value: Any?) -> UInt64? {
        if let hex = value as? String {
            let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
            return UInt64(clean, radix: 16)
        }
        if let num = value as? Int {
            return UInt64(num)
        }
        if let num = value as? UInt64 {
            return num
        }
        return nil
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

extension BaseNetworkConfig {
    /// The ONLY chain id signing is permitted against in this TESTNET-ONLY phase
    /// (Base Sepolia). Single source of truth — referenced by the sign primitive and
    /// by BlockchainBridge's defense-in-depth guard.
    static let permittedSigningChainID: UInt64 = 84_532   // Base Sepolia
    /// Base mainnet — named only to make the forbidden value explicit and searchable.
    static let baseMainnetChainID: UInt64 = 8_453

    /// True only when signing is allowed against this config's chain (testnet-only lock).
    var isSigningPermitted: Bool { chainId == Self.permittedSigningChainID }
}
