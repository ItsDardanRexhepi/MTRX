// WalletCreation.swift
// MTRX Blockchain - Wallet
//
// One-tap wallet creation with no seed phrase, Face ID recovery

import Foundation

// MARK: - Protocols

protocol WalletCreationDelegate: AnyObject {
    func walletCreation(_ creator: WalletCreation, didCreateWallet wallet: SmartWallet)
    func walletCreation(_ creator: WalletCreation, didFailWithError error: WalletCreationError)
    func walletCreation(_ creator: WalletCreation, didRecoverWallet wallet: SmartWallet)
}

protocol BiometricAuthProvider {
    func authenticateWithBiometrics(reason: String, completion: @escaping (Result<Bool, Error>) -> Void)
    func isBiometricAvailable() -> Bool
}

protocol SecureEnclaveProvider {
    func generateKeyPair(tag: String) throws -> SecureEnclaveKeyPair
    func sign(data: Data, withKeyTag tag: String) throws -> Data
    func deleteKey(tag: String) throws
    func keyExists(tag: String) -> Bool
}

// MARK: - Data Models

struct SmartWallet {
    let address: String
    let publicKey: Data
    let createdAt: Date
    let recoveryMethod: RecoveryMethod
    let accountType: AccountType
    let isDeployed: Bool
}

struct SecureEnclaveKeyPair {
    let publicKey: Data
    let keyTag: String
}

enum RecoveryMethod: String, Codable {
    case faceID = "face_id"
    case touchID = "touch_id"
    case cloudBackup = "cloud_backup"
    case socialRecovery = "social_recovery"
    case guardians = "guardians"
}

enum AccountType: String, Codable {
    case standard = "standard"
    case multiSig = "multi_sig"
    case socialRecovery = "social_recovery"
}

enum WalletCreationError: Error, LocalizedError {
    case biometricsUnavailable
    case secureEnclaveError(reason: String)
    case keyGenerationFailed
    case accountDeploymentFailed
    case recoverySetupFailed
    case biometricAuthFailed
    case walletAlreadyExists
    case cloudBackupFailed
    case guardianSetupFailed
    case invalidRecoveryData

    var errorDescription: String? {
        switch self {
        case .biometricsUnavailable: return "Biometric authentication is not available on this device."
        case .secureEnclaveError(let reason): return "Secure Enclave error: \(reason)"
        case .keyGenerationFailed: return "Failed to generate cryptographic key pair."
        case .accountDeploymentFailed: return "Smart account deployment failed."
        case .recoverySetupFailed: return "Recovery method setup failed."
        case .biometricAuthFailed: return "Biometric authentication failed."
        case .walletAlreadyExists: return "A wallet already exists for this device."
        case .cloudBackupFailed: return "Cloud backup of recovery data failed."
        case .guardianSetupFailed: return "Guardian setup for social recovery failed."
        case .invalidRecoveryData: return "Recovery data is invalid or corrupted."
        }
    }
}

// MARK: - WalletCreation

final class WalletCreation {

    // MARK: - Properties

    weak var delegate: WalletCreationDelegate?

    private let biometricProvider: BiometricAuthProvider
    private let secureEnclaveProvider: SecureEnclaveProvider
    private let erc4337Manager: ERC4337Manager

    /// Currently active wallet, if any
    private(set) var activeWallet: SmartWallet?

    /// Keychain key tag prefix for MTRX wallets
    private let keyTagPrefix = "com.mtrx.wallet.key"

    /// Recovery guardians for social recovery
    private var recoveryGuardians: [RecoveryGuardian] = []

    /// Cloud backup identifier
    private var cloudBackupID: String?

    private let creationQueue = DispatchQueue(label: "com.mtrx.wallet.creation", qos: .userInitiated)

    // MARK: - Initialization

    init(
        biometricProvider: BiometricAuthProvider,
        secureEnclaveProvider: SecureEnclaveProvider,
        erc4337Manager: ERC4337Manager
    ) {
        self.biometricProvider = biometricProvider
        self.secureEnclaveProvider = secureEnclaveProvider
        self.erc4337Manager = erc4337Manager
    }

    /// Convenience initializer using default providers.
    convenience init() {
        let networkConfig = BaseNetworkConfig(
            rpcURL: URL(string: "https://mainnet.base.org")!,
            chainId: 8453,
            bundlerURL: URL(string: "https://bundler.base.org")!
        )
        self.init(
            biometricProvider: DefaultBiometricAuthProvider(),
            secureEnclaveProvider: DefaultSecureEnclaveProvider(),
            erc4337Manager: ERC4337Manager(
                bundlerURL: networkConfig.bundlerURL,
                networkConfig: networkConfig
            )
        )
    }

    // MARK: - One-Tap Wallet Creation

    /// Create a new wallet with a single tap. No seed phrase required.
    func createWallet(
        recoveryMethod: RecoveryMethod = .faceID,
        accountType: AccountType = .standard,
        completion: @escaping (Result<SmartWallet, WalletCreationError>) -> Void
    ) {
        guard activeWallet == nil else {
            completion(.failure(.walletAlreadyExists))
            return
        }

        guard biometricProvider.isBiometricAvailable() else {
            completion(.failure(.biometricsUnavailable))
            return
        }

        // Step 1: Authenticate with biometrics
        biometricProvider.authenticateWithBiometrics(reason: "Create your MTRX wallet") { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.creationQueue.async {
                    self.performWalletCreation(
                        recoveryMethod: recoveryMethod,
                        accountType: accountType,
                        completion: completion
                    )
                }
            case .failure:
                completion(.failure(.biometricAuthFailed))
            }
        }
    }

    // MARK: - Recovery

    /// Recover wallet using Face ID and cloud backup
    func recoverWallet(completion: @escaping (Result<SmartWallet, WalletCreationError>) -> Void) {
        biometricProvider.authenticateWithBiometrics(reason: "Recover your MTRX wallet") { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.creationQueue.async {
                    self.performWalletRecovery(completion: completion)
                }
            case .failure:
                completion(.failure(.biometricAuthFailed))
            }
        }
    }

    /// Recover wallet using social recovery guardians
    func recoverWithGuardians(
        approvals: [GuardianApproval],
        completion: @escaping (Result<SmartWallet, WalletCreationError>) -> Void
    ) {
        creationQueue.async { [weak self] in
            guard let self = self else { return }

            // Verify guardian threshold is met
            let threshold = self.recoveryGuardians.isEmpty ? 2 : (self.recoveryGuardians.count / 2) + 1
            guard approvals.count >= threshold else {
                completion(.failure(.guardianSetupFailed))
                return
            }

            // TODO: Submit guardian signatures to smart account recovery module
            // Rotate owner key on-chain
            self.performGuardianRecovery(approvals: approvals, completion: completion)
        }
    }

    // MARK: - Guardian Management

    /// Add a recovery guardian
    func addGuardian(_ guardian: RecoveryGuardian) {
        recoveryGuardians.append(guardian)
    }

    /// Remove a recovery guardian
    func removeGuardian(address: String) {
        recoveryGuardians.removeAll { $0.address == address }
    }

    /// Get current guardians
    func getGuardians() -> [RecoveryGuardian] {
        return recoveryGuardians
    }

    // MARK: - Signing

    /// Sign data using the Secure Enclave key
    func sign(data: Data, completion: @escaping (Result<Data, WalletCreationError>) -> Void) {
        biometricProvider.authenticateWithBiometrics(reason: "Sign transaction") { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                do {
                    let keyTag = "\(self.keyTagPrefix).owner"
                    let signature = try self.secureEnclaveProvider.sign(data: data, withKeyTag: keyTag)
                    completion(.success(signature))
                } catch {
                    completion(.failure(.secureEnclaveError(reason: error.localizedDescription)))
                }
            case .failure:
                completion(.failure(.biometricAuthFailed))
            }
        }
    }

    // MARK: - Private Implementation

    private func performWalletCreation(
        recoveryMethod: RecoveryMethod,
        accountType: AccountType,
        completion: @escaping (Result<SmartWallet, WalletCreationError>) -> Void
    ) {
        // Step 2: Generate key pair in Secure Enclave
        let keyTag = "\(keyTagPrefix).owner.\(UUID().uuidString)"
        let keyPair: SecureEnclaveKeyPair
        do {
            keyPair = try secureEnclaveProvider.generateKeyPair(tag: keyTag)
        } catch {
            completion(.failure(.keyGenerationFailed))
            return
        }

        // Step 3: Derive smart account address from public key
        let accountAddress = deriveAccountAddress(from: keyPair.publicKey)

        // Step 4: Setup recovery method
        setupRecovery(method: recoveryMethod, publicKey: keyPair.publicKey) { [weak self] recoveryResult in
            guard let self = self else { return }

            switch recoveryResult {
            case .success:
                let wallet = SmartWallet(
                    address: accountAddress,
                    publicKey: keyPair.publicKey,
                    createdAt: Date(),
                    recoveryMethod: recoveryMethod,
                    accountType: accountType,
                    isDeployed: false
                )
                self.activeWallet = wallet

                DispatchQueue.main.async {
                    self.delegate?.walletCreation(self, didCreateWallet: wallet)
                    completion(.success(wallet))
                }

            case .failure(let error):
                // Clean up generated key on failure
                try? self.secureEnclaveProvider.deleteKey(tag: keyTag)
                completion(.failure(error))
            }
        }
    }

    private func performWalletRecovery(completion: @escaping (Result<SmartWallet, WalletCreationError>) -> Void) {
        // TODO: Retrieve encrypted recovery data from cloud backup
        // Decrypt using Secure Enclave
        // Restore wallet state
        guard let backupID = cloudBackupID else {
            completion(.failure(.invalidRecoveryData))
            return
        }

        _ = backupID
        // TODO: Fetch backup, decrypt, re-derive account
        completion(.failure(.invalidRecoveryData))
    }

    private func performGuardianRecovery(
        approvals: [GuardianApproval],
        completion: @escaping (Result<SmartWallet, WalletCreationError>) -> Void
    ) {
        // TODO: Generate new key pair in Secure Enclave
        // Submit guardian approvals to smart account recovery module
        // Execute owner rotation on-chain
        completion(.failure(.guardianSetupFailed))
    }

    private func deriveAccountAddress(from publicKey: Data) -> String {
        // TODO: Compute CREATE2 address from factory + owner public key
        return "0x" + publicKey.prefix(20).map { String(format: "%02x", $0) }.joined()
    }

    private func setupRecovery(
        method: RecoveryMethod,
        publicKey: Data,
        completion: @escaping (Result<Void, WalletCreationError>) -> Void
    ) {
        switch method {
        case .faceID, .touchID:
            // Key is already in Secure Enclave, biometric-protected
            // Backup encrypted key reference to cloud
            backupToCloud(publicKey: publicKey) { result in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure:
                    completion(.failure(.cloudBackupFailed))
                }
            }
        case .cloudBackup:
            backupToCloud(publicKey: publicKey) { result in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure:
                    completion(.failure(.cloudBackupFailed))
                }
            }
        case .socialRecovery, .guardians:
            guard !recoveryGuardians.isEmpty else {
                completion(.failure(.guardianSetupFailed))
                return
            }
            // TODO: Deploy social recovery module with guardian addresses
            completion(.success(()))
        }
    }

    private func backupToCloud(publicKey: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        // TODO: Encrypt key reference and store in iCloud Keychain
        let backupID = UUID().uuidString
        self.cloudBackupID = backupID
        completion(.success(()))
    }
}

// MARK: - Supporting Types

struct RecoveryGuardian {
    let address: String
    let name: String
    let addedAt: Date
    let isConfirmed: Bool
}

struct GuardianApproval {
    let guardianAddress: String
    let signature: Data
    let timestamp: Date
}

// MARK: - Default Provider Implementations

/// Default biometric authentication using LocalAuthentication.
final class DefaultBiometricAuthProvider: BiometricAuthProvider {
    func authenticateWithBiometrics(reason: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        // TODO: Integrate LAContext for Face ID / Touch ID
        completion(.success(true))
    }

    func isBiometricAvailable() -> Bool {
        return true
    }
}

/// Default Secure Enclave provider using the Security framework.
final class DefaultSecureEnclaveProvider: SecureEnclaveProvider {
    func generateKeyPair(tag: String) throws -> SecureEnclaveKeyPair {
        // TODO: Use SecKeyCreateRandomKey with kSecAttrTokenIDSecureEnclave
        let randomBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return SecureEnclaveKeyPair(publicKey: Data(randomBytes), keyTag: tag)
    }

    func sign(data: Data, withKeyTag tag: String) throws -> Data {
        // TODO: Use SecKeyCreateSignature with Secure Enclave key
        return Data(count: 64)
    }

    func deleteKey(tag: String) throws {
        // TODO: Use SecItemDelete to remove Secure Enclave key
    }

    func keyExists(tag: String) -> Bool {
        // TODO: Use SecItemCopyMatching to check key existence
        return false
    }
}
