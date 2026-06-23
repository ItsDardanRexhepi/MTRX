// WalletCreation.swift
// MTRX Blockchain - Wallet
//
// One-tap wallet creation with no seed phrase, Face ID recovery

import CryptoKit
import Foundation
import Security

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
    func generateKeyPair(tag: String, biometricGated: Bool) throws -> SecureEnclaveKeyPair
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
        // Endpoints come from PendingCredentials — no hardcoded URLs. While a
        // value is blank a non-routable `.invalid` placeholder is used so no real
        // call can succeed (safe no-op) until the config is filled in; chain id
        // stays 0 (unconfigured) rather than assuming a network.
        let rpc = URL(string: PendingCredentials.filled(PendingCredentials.Network.rpcURL)
                      ?? "https://unconfigured.invalid")!
        let bundler = URL(string: PendingCredentials.filled(PendingCredentials.AccountAbstraction.bundlerURL)
                          ?? "https://unconfigured.invalid")!
        let networkConfig = BaseNetworkConfig(
            rpcURL: rpc,
            chainId: UInt64(PendingCredentials.Network.chainID),
            bundlerURL: bundler
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
            keyPair = try secureEnclaveProvider.generateKeyPair(tag: keyTag, biometricGated: true)
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
        // Retrieve the AES-GCM-encrypted backup + key from iCloud Keychain
        // (synced across the user's devices) and restore the wallet's metadata.
        // NOTE: the Secure Enclave private key is non-exportable and is NOT in
        // the backup — this restores the wallet's identity (address + owner
        // public key). Regaining signing CONTROL on a brand-new device requires
        // social recovery (guardian owner-rotation), not this metadata restore.
        do {
            guard let ciphertext = try Self.iCloudKeychainLoad(account: Self.backupCiphertextAccount),
                  let keyData = try Self.iCloudKeychainLoad(account: Self.backupKeyAccount) else {
                completion(.failure(.invalidRecoveryData))
                return
            }
            let key = SymmetricKey(data: keyData)
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(box, using: key)
            let backup = try JSONDecoder().decode(RecoveryBackup.self, from: plaintext)
            let publicKey = Self.dataFromHex(backup.publicKeyHex)
            let wallet = SmartWallet(
                address: backup.address,
                publicKey: publicKey,
                createdAt: backup.createdAt,
                recoveryMethod: .cloudBackup,
                accountType: .standard,
                isDeployed: false
            )
            self.activeWallet = wallet
            DispatchQueue.main.async {
                self.delegate?.walletCreation(self, didRecoverWallet: wallet)
                completion(.success(wallet))
            }
        } catch {
            completion(.failure(.invalidRecoveryData))
        }
    }

    private func performGuardianRecovery(
        approvals: [GuardianApproval],
        completion: @escaping (Result<SmartWallet, WalletCreationError>) -> Void
    ) {
        // Social recovery rotates the account's owner key on-chain via the
        // recovery module. Requires the deployed module address (config) — with
        // it blank we fail loudly rather than pretend to recover.
        guard PendingCredentials.filled(PendingCredentials.Recovery.socialRecoveryModuleAddress) != nil else {
            completion(.failure(.guardianSetupFailed))
            return
        }

        // 1. Generate a NEW real Secure Enclave key for this device (the old
        //    device's key is unavailable — that's the whole point of recovery).
        let newKeyTag = "\(keyTagPrefix).owner.\(UUID().uuidString)"
        let newKeyPair: SecureEnclaveKeyPair
        do {
            newKeyPair = try secureEnclaveProvider.generateKeyPair(tag: newKeyTag, biometricGated: true)
        } catch {
            completion(.failure(.keyGenerationFailed))
            return
        }

        // 2. Submit the guardian-approved owner-rotation as a UserOperation to
        //    the recovery module through the real submit pipeline. With the chain
        //    unconfigured the pipeline is nil and we fail (never fake a rotation).
        let newAddress = deriveAccountAddress(from: newKeyPair.publicKey)
        Task { @MainActor in
            guard let service = WalletTransactionService() else {
                try? self.secureEnclaveProvider.deleteKey(tag: newKeyTag)
                completion(.failure(.guardianSetupFailed))
                return
            }
            do {
                _ = try await self.submitGuardianRotation(
                    newOwnerPublicKey: newKeyPair.publicKey,
                    moduleAddress: PendingCredentials.Recovery.socialRecoveryModuleAddress,
                    accountAddress: newAddress,
                    signingKeyTag: newKeyTag,
                    service: service
                )
                let wallet = SmartWallet(
                    address: newAddress,
                    publicKey: newKeyPair.publicKey,
                    createdAt: Date(),
                    recoveryMethod: .socialRecovery,
                    accountType: .socialRecovery,
                    isDeployed: true
                )
                self.activeWallet = wallet
                self.delegate?.walletCreation(self, didRecoverWallet: wallet)
                completion(.success(wallet))
            } catch {
                try? self.secureEnclaveProvider.deleteKey(tag: newKeyTag)
                completion(.failure(.guardianSetupFailed))
            }
        }
    }

    /// ABI-encode `rotateOwner(bytes newOwnerPublicKey)` for the recovery module.
    /// The deployed social-recovery module's ABI must match this selector.
    static func encodeRotateOwner(newOwnerPublicKey pub: Data) -> Data {
        var data = ABIEncoder.functionSelector("rotateOwner(bytes)")
        data.append(ABIEncoder.encodeUInt256(32))                 // offset to the bytes arg
        data.append(ABIEncoder.encodeUInt256(UInt64(pub.count)))  // dynamic length
        var padded = pub
        let remainder = pub.count % 32
        if remainder != 0 { padded.append(Data(repeating: 0, count: 32 - remainder)) }
        data.append(padded)
        return data
    }

    /// Submit the guardian-approved owner-rotation through the real submit
    /// pipeline (enclave-signed UserOperation to the recovery module). Returns
    /// the bundler userOp hash. The pipeline `service` is injectable for tests.
    @MainActor
    func submitGuardianRotation(
        newOwnerPublicKey: Data,
        moduleAddress: String,
        accountAddress: String,
        signingKeyTag: String,
        service: WalletTransactionService
    ) async throws -> String {
        let calldata = Self.encodeRotateOwner(newOwnerPublicKey: newOwnerPublicKey)
        let submission = try await service.submitCall(
            to: moduleAddress,
            value: 0,
            data: calldata,
            sender: accountAddress,
            signingKeyTag: signingKeyTag
        )
        return submission.userOpHash
    }

    private func deriveAccountAddress(from publicKey: Data) -> String {
        // Display address derived from the real Secure Enclave public key.
        // The canonical on-chain CREATE2 address is computed by ERC4337Manager
        // at first deployment using the factory from PendingCredentials.
        let digest = SHA256.hash(data: publicKey)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "0x" + String(hex.prefix(40))
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
            // Honest failure: the social recovery module is NOT deployed (there is no
            // on-chain guardian registry yet), so guardian recovery is NOT set up.
            // Report failure rather than a fake success that would tell the user their
            // wallet is recoverable via guardians when it is not. Phase 4 builds the
            // real module; until then this must say it isn't available.
            completion(.failure(.recoverySetupFailed))
        }
    }

    private func backupToCloud(publicKey: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let backup = RecoveryBackup(
                publicKeyHex: publicKey.map { String(format: "%02x", $0) }.joined(),
                address: deriveAccountAddress(from: publicKey),
                createdAt: Date()
            )
            let plaintext = try JSONEncoder().encode(backup)

            // Real AES-GCM encryption. Ciphertext + key go into iCloud Keychain
            // (synced across the user's devices). The Secure Enclave private key
            // is non-exportable and is deliberately NOT part of the backup —
            // only the recoverable wallet metadata is.
            let key = SymmetricKey(size: .bits256)
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let ciphertext = sealed.combined else {
                completion(.failure(WalletCreationError.cloudBackupFailed))
                return
            }
            let keyData = key.withUnsafeBytes { Data(Array($0)) }

            try Self.iCloudKeychainStore(account: Self.backupCiphertextAccount, data: ciphertext)
            try Self.iCloudKeychainStore(account: Self.backupKeyAccount, data: keyData)
            self.cloudBackupID = backup.address
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
}

// MARK: - Recovery Backup (AES-GCM + iCloud Keychain)

extension WalletCreation {

    /// The recoverable, non-secret wallet metadata. The signing private key is
    /// NOT here — Secure Enclave keys are non-exportable.
    struct RecoveryBackup: Codable {
        let publicKeyHex: String
        let address: String
        let createdAt: Date
    }

    fileprivate static let backupService = "com.opnmatrx.mtrx.recovery"
    fileprivate static let backupCiphertextAccount = "com.mtrx.recovery.ciphertext"
    fileprivate static let backupKeyAccount = "com.mtrx.recovery.key"

    /// Store `data` in iCloud Keychain (synchronizable → syncs across the user's
    /// devices when iCloud Keychain is enabled; the Keychain Sharing/iCloud
    /// entitlement gates real syncing).
    fileprivate static func iCloudKeychainStore(account: String, data: Data) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: backupService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw WalletCreationError.cloudBackupFailed }
    }

    fileprivate static func dataFromHex(_ hex: String) -> Data {
        var s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        if s.count % 2 != 0 { s = "0" + s }
        var data = Data(); data.reserveCapacity(s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let byte = UInt8(s[idx..<next], radix: 16) else { return Data() }
            data.append(byte)
            idx = next
        }
        return data
    }

    fileprivate static func iCloudKeychainLoad(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: backupService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw WalletCreationError.cloudBackupFailed }
        return item as? Data
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

/// Real biometric authentication — wraps the production BiometricAuth
/// (LocalAuthentication / LAContext) in Core/Wallet. No fake success.
final class DefaultBiometricAuthProvider: BiometricAuthProvider {
    func authenticateWithBiometrics(reason: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        Task {
            do {
                let ok = try await BiometricAuth.shared.authenticate(
                    reason: reason,
                    allowPasscodeFallback: true
                )
                if ok {
                    completion(.success(true))
                } else {
                    completion(.failure(WalletCreationError.biometricAuthFailed))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func isBiometricAvailable() -> Bool {
        BiometricAuth.shared.canUseBiometrics
    }
}

/// Real Secure Enclave provider — wraps the production SecureEnclaveManager
/// in Core/Wallet (CryptoKit SecureEnclave.P256, software P-256 fallback,
/// Keychain-backed). No random-byte keys, no zero-byte signatures.
final class DefaultSecureEnclaveProvider: SecureEnclaveProvider {

    private let manager = SecureEnclaveManager.shared

    func generateKeyPair(tag: String, biometricGated: Bool) throws -> SecureEnclaveKeyPair {
        // Creates the enclave key on first use and returns its REAL public key.
        // biometricGated=true binds the signing key to .biometryCurrentSet at the enclave.
        let publicKey = try manager.publicKeyData(tag: tag, biometricGated: biometricGated)
        return SecureEnclaveKeyPair(publicKey: publicKey, keyTag: tag)
    }

    func sign(data: Data, withKeyTag tag: String) throws -> Data {
        // Real P-256 DER signature over SHA-256(data) from the enclave key.
        try manager.sign(data, tag: tag)
    }

    func deleteKey(tag: String) throws {
        manager.deleteKey(tag: tag)
    }

    func keyExists(tag: String) -> Bool {
        manager.hasKey(tag: tag)
    }
}
