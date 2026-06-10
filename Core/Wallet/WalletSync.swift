// WalletSync.swift
// MTRX — Core/Wallet
//
// Cross-device sync of NON-SECRET wallet metadata (address, display
// preferences) via iCloud Key-Value Store when the entitlement and an
// iCloud account are present, with a local fallback otherwise. Private
// keys never sync — they are device-bound in the Secure Enclave by
// design; a new device derives its own key and the account links by
// Apple user ID.

import Foundation

final class WalletSync {

    static let shared = WalletSync()

    private let addressKey = "com.mtrx.sync.walletAddress"
    private let updatedAtKey = "com.mtrx.sync.updatedAt"

    /// iCloud KVS is only usable with the iCloud entitlement and a
    /// signed-in account. We detect at runtime and degrade silently to
    /// local storage so the app never breaks without it.
    var isCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private init() {
        if isCloudAvailable {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(storeDidChange(_:)),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default
            )
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    // MARK: - Push / pull

    /// Publish wallet metadata for the user's other devices.
    func pushMetadata(address: String) {
        if isCloudAvailable {
            let store = NSUbiquitousKeyValueStore.default
            store.set(address, forKey: addressKey)
            store.set(Date().timeIntervalSince1970, forKey: updatedAtKey)
            store.synchronize()
        } else {
            UserDefaults.standard.set(address, forKey: addressKey)
        }
    }

    /// Latest synced wallet address, if any device has published one.
    func pulledAddress() -> String? {
        if isCloudAvailable {
            return NSUbiquitousKeyValueStore.default.string(forKey: addressKey)
        }
        return UserDefaults.standard.string(forKey: addressKey)
    }

    // MARK: - Change observation

    /// Called when another device updates the synced metadata.
    @objc private func storeDidChange(_ note: Notification) {
        NotificationCenter.default.post(
            name: WalletSync.metadataDidChange,
            object: nil,
            userInfo: ["address": pulledAddress() as Any]
        )
    }

    /// Posted when wallet metadata changes from another device.
    static let metadataDidChange = Notification.Name("com.mtrx.walletSync.metadataDidChange")
}
