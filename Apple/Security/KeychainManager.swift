// KeychainManager.swift
// MTRX Apple Integration — Security
// iCloud Keychain credential storage via Security framework

import Security
import Foundation

// MARK: - Keychain Manager

final class KeychainManager {

    // MARK: - Shared Instance

    static let shared = KeychainManager()

    // MARK: - Constants

    private let serviceName = "com.mtrx.wallet"
    private let accessGroup = "group.com.mtrx.shared"

    // MARK: - Store Credential

    /// Stores a credential securely in iCloud Keychain with biometric protection.
    func store(key: String, data: Data, biometricProtection: Bool = true, iCloudSync: Bool = true) throws {
        // Remove existing item first
        try? delete(key: key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessGroup as String: accessGroup
        ]

        if iCloudSync {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }

        if biometricProtection {
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .biometryCurrentSet,
                nil
            )
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    // MARK: - Retrieve Credential

    /// Retrieves a credential from iCloud Keychain, prompting biometric auth if required.
    func retrieve(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.retrieveFailed(status)
        }

        return data
    }

    // MARK: - Delete Credential

    /// Removes a credential from iCloud Keychain.
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Wallet Key Storage

    /// Stores a wallet private key with maximum security (device-only, biometric).
    func storeWalletKey(_ privateKey: Data, walletId: String) throws {
        let key = "wallet.privateKey.\(walletId)"

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: privateKey,
            kSecAttrAccessGroup as String: accessGroup
        ]

        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryCurrentSet, .privateKeyUsage],
            nil
        )
        query[kSecAttrAccessControl as String] = access

        try? delete(key: key)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    /// Retrieves a wallet private key, requiring biometric authentication.
    func retrieveWalletKey(walletId: String) throws -> Data {
        return try retrieve(key: "wallet.privateKey.\(walletId)")
    }

    // MARK: - Seed Phrase Storage

    /// Stores an encrypted seed phrase in the Keychain.
    func storeSeedPhrase(_ seedPhrase: Data, walletId: String) throws {
        try store(
            key: "wallet.seedPhrase.\(walletId)",
            data: seedPhrase,
            biometricProtection: true,
            iCloudSync: false // Never sync seed phrases
        )
    }

    /// Retrieves an encrypted seed phrase from the Keychain.
    func retrieveSeedPhrase(walletId: String) throws -> Data {
        return try retrieve(key: "wallet.seedPhrase.\(walletId)")
    }

    // MARK: - API Token Storage

    /// Stores an API authentication token.
    func storeAuthToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try store(key: "auth.token", data: data, biometricProtection: false, iCloudSync: true)
    }

    /// Retrieves the stored API authentication token.
    func retrieveAuthToken() throws -> String {
        let data = try retrieve(key: "auth.token")
        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return token
    }

    // MARK: - String Convenience

    /// Stores a string value in the Keychain.
    func storeString(_ value: String, key: String, biometric: Bool = false) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try store(key: key, data: data, biometricProtection: biometric)
    }

    /// Retrieves a string value from the Keychain.
    func retrieveString(key: String) throws -> String {
        let data = try retrieve(key: key)
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return value
    }

    // MARK: - Clear All

    /// Removes all MTRX credentials from the Keychain.
    func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Key Existence Check

    /// Checks whether a credential exists for the given key without retrieving it.
    func exists(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: false,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

// MARK: - Keychain Error

enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .storeFailed(let status): return "Keychain store failed with status: \(status)"
        case .retrieveFailed(let status): return "Keychain retrieve failed with status: \(status)"
        case .deleteFailed(let status): return "Keychain delete failed with status: \(status)"
        case .encodingFailed: return "Failed to encode data for Keychain storage"
        case .decodingFailed: return "Failed to decode data from Keychain"
        }
    }
}
