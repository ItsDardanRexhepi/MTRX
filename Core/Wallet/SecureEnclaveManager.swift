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
import LocalAuthentication
import Security

final class SecureEnclaveManager {

    static let shared = SecureEnclaveManager()

    enum KeyError: Error, LocalizedError {
        case keychainStatus(OSStatus)
        case corruptKeyData
        case authenticationRequired

        var errorDescription: String? {
            switch self {
            case .keychainStatus(let s): return "Keychain error (\(s))."
            case .corruptKeyData: return "Stored key data is unreadable."
            case .authenticationRequired: return "Authentication required — nothing was signed."
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
    /// keys are created ungated (the default).
    ///
    /// P3.3 — the software fallback (Simulator / no enclave) is gated too. When `biometricGated`
    /// is true and no enclave is present, the software private key is stored under a keychain
    /// `.biometryCurrentSet` access control (biometric required to read it for signing) and the
    /// public key is stored in an ungated companion item (so address derivation never prompts).
    /// This closes the last "every signing path requires biometric" hole P3.1/P3.2 deferred.
    /// (`KeychainManager.storeWalletKey` carried this hardening but is unusable as-is: its access
    /// group `group.com.mtrx.shared` is not entitled, and its service differs from this one — so
    /// the hardening lives here, in the working key store.)
    @discardableResult
    func ensureKey(tag: String, biometricGated: Bool = false) throws -> Bool {
        if keyExistsNoPrompt(tag: tag) { return false }
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
            if biometricGated {
                try storeGatedSoftwareKey(key, tag: tag)
            } else {
                try storeKeyData(key.rawRepresentation, tag: tag)
            }
        }
        return true
    }

    /// Raw public key bytes for `tag`, creating the key on first use. Never triggers biometric:
    /// enclave keys expose their public key freely, and software-gated keys (P3.3) keep the public
    /// key in an ungated companion item so address derivation doesn't prompt.
    func publicKeyData(tag: String, biometricGated: Bool = false) throws -> Data {
        try ensureKey(tag: tag, biometricGated: biometricGated)
        // Software-gated key: read ONLY the ungated public companion (no biometric prompt). If the
        // companion is missing (corruption / interrupted store), fail honestly — do NOT fall
        // through to read the gated private, which would prompt biometric just for address
        // derivation (P3.3 adversarial review, HIGH). The gated private item is never read here.
        if !isSecureEnclaveAvailable, biometricGated {
            guard let pub = try loadKeyData(tag: publicTag(tag)) else {
                throw KeyError.corruptKeyData
            }
            return pub
        }
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
    ///
    /// Biometric handling (P3.2). When the key for `tag` is biometric-gated
    /// (P3.1, `.biometryCurrentSet`), the Secure Enclave requires a Face ID /
    /// Touch ID check for this signature. The `context` controls that check:
    ///
    /// - Pass an already-authenticated `LAContext` (e.g. the one the Send UI
    ///   evaluated a moment ago) to REUSE that authentication, so the user is
    ///   not prompted a second time for the same action (decision #2).
    /// - Pass `nil` (the default) and each signature gets its OWN fresh context
    ///   with reuse-duration 0 — no silent reuse of an unrelated recent unlock;
    ///   the enclave authenticates this signature on its own.
    ///
    /// A declined / cancelled / failed biometric does NOT produce a signature:
    /// the enclave signature is load-bearing and any auth failure surfaces as
    /// `KeyError.authenticationRequired` — never a silently-skipped or faked sig.
    func sign(_ data: Data, tag: String, context: LAContext? = nil) throws -> Data {
        // sign() NEVER creates a key. Creation — with the correct gating — is the caller's job via
        // publicKeyData / generateKeyPair / ensureKey. A missing key here throws (corruptKeyData)
        // rather than lazily minting an UNGATED key and signing with it, which would BYPASS the
        // biometric gate (P3.3 adversarial review, CRITICAL). loadKeyData returning nil below is
        // the honest "no usable key" failure.
        let digest = SHA256.hash(data: data)
        // Reuse the caller's authenticated context, or mint a fresh one that refuses to reuse any
        // prior unlock (reuse-duration 0). Used by BOTH the enclave gate (at signature time) and
        // the P3.3 software gate (at the keychain read).
        let authContext = context ?? freshSigningContext()

        if isSecureEnclaveAvailable {
            // Enclave key: the keychain blob is ungated; biometric is enforced by the enclave at
            // signature time via `authContext` (P3.2). Load-bearing — a decline throws honestly and
            // does NOT fall through once the enclave key reconstructs.
            if let stored = try loadKeyData(tag: tag),
               let seKey = try? SecureEnclave.P256.Signing.PrivateKey(
                dataRepresentation: stored, authenticationContext: authContext) {
                do {
                    return try seKey.signature(for: digest).derRepresentation
                } catch {
                    throw mapSigningError(error)
                }
            }
            // Not an enclave-format blob (e.g. a software key minted when no enclave was present).
            // Fall through to the software path — NOT an auth failure.
        }

        // Software path (Simulator / no enclave). For a P3.3 biometric-gated key the private item
        // carries a `.biometryCurrentSet` access control, so reading it requires biometric —
        // threaded through `authContext`. A declined/failed biometric makes `loadKeyData` throw
        // `KeyError.authenticationRequired`; we never fall through to an unauthenticated signature.
        // For an ungated software key the context is simply unused (no prompt).
        guard let stored = try loadKeyData(tag: tag, context: authContext) else {
            throw KeyError.corruptKeyData
        }
        guard let soft = try? P256.Signing.PrivateKey(rawRepresentation: stored) else {
            throw KeyError.corruptKeyData
        }
        return try soft.signature(for: digest).derRepresentation
    }

    // MARK: - Signing auth context

    /// A fresh authentication context for a single signature that refuses to
    /// reuse any earlier biometric unlock (reuse-duration 0). Each standalone
    /// signature therefore authenticates on its own.
    private func freshSigningContext() -> LAContext {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        return context
    }

    /// Map an enclave signing failure to an honest, user-facing error. A
    /// biometric-gated key fails to sign only when authentication is declined,
    /// cancelled, failed, locked out, or the key was invalidated by a biometric
    /// change (Phase 4 recovery territory). In every case the truth is the same:
    /// nothing was signed and the user must authenticate.
    private func mapSigningError(_ error: Error) -> Error {
        if error is KeyError { return error }
        return KeyError.authenticationRequired
    }

    /// Whether a key already exists for `tag` — read-only, never creates one, and never prompts
    /// biometric (a gated key would otherwise prompt just to check existence).
    func hasKey(tag: String) -> Bool {
        keyExistsNoPrompt(tag: tag)
    }

    /// Remove the key for `tag` (sign-out / account reset) — including its ungated public
    /// companion if the key was a P3.3 software-gated key.
    func deleteKey(tag: String) {
        deleteItem(tag: tag)
        deleteItem(tag: publicTag(tag))
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

    /// Store ungated key data (enclave blob, ungated software key, or the public companion of a
    /// software-gated key). Single-item replace — does NOT touch companions.
    private func storeKeyData(_ data: Data, tag: String) throws {
        deleteItem(tag: tag)
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

    /// P3.3 — store a software P-256 key biometric-gated: the private key under a keychain
    /// `.biometryCurrentSet` access control (biometric required to read it for signing), the public
    /// key under an ungated companion item (so address derivation never prompts). Mirrors the
    /// enclave gate; `.privateKeyUsage` is enclave-only and intentionally omitted here. Requires an
    /// enrolled biometric — on a device/Simulator with none, the gated store fails honestly rather
    /// than silently creating an ungated signing key.
    private func storeGatedSoftwareKey(_ key: P256.Signing.PrivateKey, tag: String) throws {
        // Ungated public companion first (so a later failure leaves nothing signable behind).
        try storeKeyData(key.publicKey.rawRepresentation, tag: publicTag(tag))
        deleteItem(tag: tag)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            deleteItem(tag: publicTag(tag))
            if let err = error?.takeRetainedValue() { throw err }
            throw KeyError.corruptKeyData
        }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecValueData as String: key.rawRepresentation,
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            deleteItem(tag: publicTag(tag))   // roll back — never leave a half-stored key
            throw KeyError.keychainStatus(status)
        }
    }

    private func loadKeyData(tag: String, context: LAContext? = nil) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let context = context {
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        if status == errSecUserCanceled || status == errSecAuthFailed {
            // Biometric declined/failed on a P3.3-gated key — honest, load-bearing failure.
            throw KeyError.authenticationRequired
        }
        guard status == errSecSuccess else { throw KeyError.keychainStatus(status) }
        return item as? Data
    }

    /// Existence check that NEVER triggers biometric: asking for the data of a gated key would
    /// prompt, so we skip the auth UI and treat "present but needs auth" (`errSecInteractionNotAllowed`)
    /// as existing.
    private func keyExistsNoPrompt(tag: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Delete exactly one keychain item for `tag` (no companion handling).
    private func deleteItem(tag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Companion tag holding the ungated public key for a P3.3 software-gated key.
    private func publicTag(_ tag: String) -> String { tag + ".public" }
}
