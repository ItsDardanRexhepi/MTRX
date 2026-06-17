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
    @discardableResult
    func ensureKey(tag: String) throws -> Bool {
        if try loadKeyData(tag: tag) != nil { return false }
        if isSecureEnclaveAvailable {
            let key = try SecureEnclave.P256.Signing.PrivateKey()
            try storeKeyData(key.dataRepresentation, tag: tag)
        } else {
            let key = P256.Signing.PrivateKey()
            try storeKeyData(key.rawRepresentation, tag: tag)
        }
        return true
    }

    /// Raw public key bytes for `tag`, creating the key on first use.
    func publicKeyData(tag: String) throws -> Data {
        try ensureKey(tag: tag)
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
