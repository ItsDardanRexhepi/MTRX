// SecureEnclaveManager.swift
// MTRX — Core/Wallet
//
// CryptoKit key generation and storage. Signing keys live in the
// Secure Enclave on real devices; a software P-256 key (stored in the
// Keychain) is the fallback where the enclave is unavailable
// (Simulator, older hardware). Private key material never leaves the
// device and is never exposed to callers — only public keys and
// signatures cross this boundary.

import CryptoKit
import Foundation
import Security

final class SecureEnclaveManager {

    static let shared = SecureEnclaveManager()

    enum KeyError: Error, LocalizedError {
        case keychainStatus(OSStatus)
        case corruptKeyData

        var errorDescription: String? {
            switch self {
            case .keychainStatus(let s): return "Keychain error (\(s))."
            case .corruptKeyData: return "Stored key data is unreadable."
            }
        }
    }

    /// Whether this device has a usable Secure Enclave.
    var isSecureEnclaveAvailable: Bool {
        SecureEnclave.isAvailable
    }

    // MARK: - Public API

    /// Create the key for `tag` if it doesn't exist. Returns true when a
    /// new key was generated, false when one already existed.
    ///
    /// When `biometricGated` is true AND a Secure Enclave is present, the key is bound to
    /// `.privateKeyUsage + .biometryCurrentSet`: every private-key operation (signing) then
    /// requires biometric auth, enforced by the enclave itself, and the key is invalidated if
    /// the enrolled biometrics change. This is the transaction-signing key's gate; identity-proof
    /// keys are created ungated (the default). The software fallback (Simulator / no enclave) is
    /// NOT gated here — that is hardened separately in P3.3 (KeychainManager.storeWalletKey).
    @discardableResult
    func ensureKey(tag: String, biometricGated: Bool = false) throws -> Bool {
        if try loadKeyData(tag: tag) != nil { return false }
        if isSecureEnclaveAvailable {
            let key: SecureEnclave.P256.Signing.PrivateKey
            if biometricGated {
                key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: biometricAccessControl())
            } else {
                key = try SecureEnclave.P256.Signing.PrivateKey()
            }
            try storeKeyData(key.dataRepresentation, tag: tag)
        } else {
            let key = P256.Signing.PrivateKey()
            try storeKeyData(key.rawRepresentation, tag: tag)
        }
        return true
    }

    /// Raw public key bytes for `tag`, creating the key on first use.
    func publicKeyData(tag: String, biometricGated: Bool = false) throws -> Data {
        try ensureKey(tag: tag, biometricGated: biometricGated)
        guard let stored = try loadKeyData(tag: tag) else {
            throw KeyError.corruptKeyData
        }
        if isSecureEnclaveAvailable,
           let seKey = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored) {
            return seKey.publicKey.rawRepresentation
        }
        if let soft = try? P256.Signing.PrivateKey(rawRepresentation: stored) {
            return soft.publicKey.rawRepresentation
        }
        throw KeyError.corruptKeyData
    }

    /// DER signature over SHA-256(data) using the key for `tag`.
    func sign(_ data: Data, tag: String) throws -> Data {
        try ensureKey(tag: tag)
        guard let stored = try loadKeyData(tag: tag) else {
            throw KeyError.corruptKeyData
        }
        let digest = SHA256.hash(data: data)
        if isSecureEnclaveAvailable,
           let seKey = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored) {
            return try seKey.signature(for: digest).derRepresentation
        }
        if let soft = try? P256.Signing.PrivateKey(rawRepresentation: stored) {
            return try soft.signature(for: digest).derRepresentation
        }
        throw KeyError.corruptKeyData
    }

    /// Whether a key already exists for `tag` — read-only, never creates one.
    func hasKey(tag: String) -> Bool {
        ((try? loadKeyData(tag: tag)) ?? nil) != nil
    }

    /// Remove the key for `tag` (sign-out / account reset).
    func deleteKey(tag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain plumbing

    private let service = "com.opnmatrx.mtrx.wallet-keys"

    /// Access control binding a Secure Enclave key to the user's current biometrics:
    /// `.privateKeyUsage` (operations run in the enclave) + `.biometryCurrentSet` (biometric
    /// required per use; the key is invalidated if the enrolled biometric set changes).
    private func biometricAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error
        ) else {
            if let err = error?.takeRetainedValue() { throw err }
            throw KeyError.corruptKeyData
        }
        return access
    }

    private func storeKeyData(_ data: Data, tag: String) throws {
        deleteKey(tag: tag)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyError.keychainStatus(status) }
    }

    private func loadKeyData(tag: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeyError.keychainStatus(status) }
        return item as? Data
    }
}
