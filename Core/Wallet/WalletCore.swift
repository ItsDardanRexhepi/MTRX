// WalletCore.swift
// MTRX — Core/Wallet
//
// App-facing wallet façade: one-tap creation (no seed phrase), Face ID
// unlock, deterministic address derived from a device-held key. The
// chain-specific machinery (ERC-4337 deployment, gas sponsorship,
// Base RPC) lives in Blockchain/Wallet — this layer is what the UI
// talks to.

import CryptoKit
import Foundation

@MainActor
final class WalletCore: ObservableObject {

    static let shared = WalletCore()

    // MARK: - Published state

    @Published private(set) var address: String?
    @Published private(set) var isUnlocked: Bool = false

    // MARK: - Dependencies

    private let enclave = SecureEnclaveManager.shared
    private let biometrics = BiometricAuth.shared
    private let sync = WalletSync.shared

    private let addressDefaultsKey = "com.mtrx.walletAddress"

    private init() {
        address = UserDefaults.standard.string(forKey: addressDefaultsKey)
    }

    // MARK: - Creation

    /// One-tap wallet creation. Generates (or reuses) the device signing
    /// key for this Apple user and derives a stable address from its
    /// public key — the same user always gets the same address back, and
    /// there is no seed phrase to lose.
    @discardableResult
    func createWalletIfNeeded(appleUserId: String) throws -> String {
        if let existing = address, !existing.isEmpty { return existing }

        let tag = keyTag(for: appleUserId)
        let publicKey = try enclave.publicKeyData(tag: tag)
        let derived = Self.deriveAddress(fromPublicKey: publicKey)

        address = derived
        UserDefaults.standard.set(derived, forKey: addressDefaultsKey)
        UserDefaults.standard.set(derived, forKey: "com.mtrx.walletAddress." + appleUserId)
        sync.pushMetadata(address: derived)
        return derived
    }

    // MARK: - Lock / unlock

    /// Face ID (or passcode fallback) gate in front of signing actions.
    func unlock() async throws {
        guard !isUnlocked else { return }
        let ok = try await biometrics.authenticate(reason: "Unlock your MTRX wallet")
        isUnlocked = ok
    }

    func lock() {
        isUnlocked = false
    }

    // MARK: - Signing

    /// Sign an intent envelope / message hash with the wallet key.
    /// Requires an unlocked wallet.
    func sign(_ data: Data, appleUserId: String) async throws -> Data {
        if !isUnlocked { try await unlock() }
        // Per-transaction Face ID at the moment of signing (Phase 4 fund protection).
        // When the user keeps this on (default), EVERY signature requires a fresh
        // Face ID — not just the one-time wallet unlock. authenticate() throws on
        // failure/cancel, so a failed Face ID never produces a signature. The key
        // never leaves the Secure Enclave; the server never signs.
        if SecurityPreferences.shared.requireBiometricForSigning {
            _ = try await biometrics.authenticate(
                reason: "Approve this transaction with Face ID")
        }
        return try enclave.sign(data, tag: keyTag(for: appleUserId))
    }

    // MARK: - Reset

    /// Wipe the wallet for sign-out. The key is destroyed; a future
    /// sign-in with the same Apple ID regenerates a fresh key/address.
    func reset(appleUserId: String) {
        enclave.deleteKey(tag: keyTag(for: appleUserId))
        UserDefaults.standard.removeObject(forKey: addressDefaultsKey)
        address = nil
        isUnlocked = false
    }

    // MARK: - Helpers

    private func keyTag(for appleUserId: String) -> String {
        "wallet." + appleUserId
    }

    /// Deterministic 0x address from a public key (keccak-style display
    /// derivation using SHA-256; the canonical on-chain address is
    /// assigned by the ERC-4337 factory at first deployment).
    static func deriveAddress(fromPublicKey publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "0x" + String(hex.prefix(40))
    }
}
