// AppAttestManager.swift
// MTRX Apple Integration — Security
//
// CLIENT half of two server-side layers in Matrix-Security-System:
//   • App Attest (server Package D — matrix_security/attest/app_attest.py): proves a
//     request comes from a genuine, unmodified MTRX build on a real Apple device,
//     using a Secure-Enclave-backed key Apple manages.
//   • Biometric Secure-Enclave owner factor (server Package E — owner.py): the owner
//     third factor is a Face/Touch-ID-gated App Attest assertion (immune to SIM-swap;
//     SMS-OTP is the fallback). The private key NEVER leaves the Secure Enclave — the
//     app produces only a signed assertion the server verifies.
//
// SERVER CONTRACT (matched exactly — see attest/CLIENT_INTEGRATION.md + app_attest.py):
//   • challenge:           32-byte hex string from new_challenge(identity)
//   • attestation hash:    SHA256( utf8(challenge) )            — same transform server uses
//   • assertion hash:      SHA256( utf8(challenge) + requestBytes )
//   • envelope (snake_case, read by the gate's context["app_attest"] AND by owner.py's
//     device_assertion):   { key_id, assertion_b64, client_data_hash, challenge }
//     where client_data_hash is base64 of the 32 raw bytes the device signed.
//
// FLAGS DEFAULT OFF (PendingCredentials.Security). With them off this layer is INERT:
// callers never reach it. It does nothing live until the security server is deployed
// and the flags are deliberately flipped per SECURITY_REVIEW_CHECKLIST §14.4.
//
// UNVERIFIED END-TO-END: App Attest and Secure-Enclave biometrics CANNOT run in the
// Simulator or CI — runtime proof needs (a) a physical iPhone, (b) the App Attest
// entitlement on the real App ID, (c) the deployed security server. See
// APP_SIDE_STATUS.md. The bar here is "compiles + matches the server contract,"
// not "verified working." Nothing in this file ever fakes a successful verification.

import DeviceCheck
import CryptoKit
import Foundation

// MARK: - App Attest Manager

final class AppAttestManager {

    static let shared = AppAttestManager()

    private let attestService = DCAppAttestService.shared

    /// The App Attest keyId, persisted in the **Keychain** (NOT UserDefaults),
    /// device-only and NOT iCloud-synced: the key is bound to THIS device's Secure
    /// Enclave, so a synced copy on another device would be useless. The keyId is not
    /// itself secret, so it is stored without a biometric ACL — assertions are gated
    /// behind biometrics explicitly, which avoids a double Face ID prompt on every send.
    private static let keyIdKeychainKey = "appattest.keyId"
    private var cachedKeyId: String?

    private init() {
        cachedKeyId = Self.loadKeyId()
    }

    // MARK: - Honest device readiness

    /// The real, observable state of this device — never guessed, never faked.
    enum Readiness: Equatable {
        case ready            // supported + a key is registered with the server
        case supportedNoKey   // supported, but needs the one-time attestation first
        case unsupported      // older hardware / Simulator — cannot attest at all
    }

    var isSupported: Bool { attestService.isSupported }
    var hasKey: Bool { cachedKeyId != nil }

    var readiness: Readiness {
        guard attestService.isSupported else { return .unsupported }
        return cachedKeyId == nil ? .supportedNoKey : .ready
    }

    // MARK: - Errors (typed + honest; callers degrade gracefully, never crash)

    enum AppAttestError: LocalizedError, Equatable {
        case notSupported                  // App Attest unavailable on this device
        case keyNotRegistered              // no attested key yet — call registerIfNeeded
        case keyLost                       // Apple no longer recognizes the key (restore/reinstall)
        case challengeUnavailable(String)  // network failure fetching the server challenge
        case attestationRejected(String)   // server declined the attestation
        case assertionFailed(String)       // DCAppAttestService failed to produce an assertion
        case biometricsFailed(String)      // owner/high-value gate not satisfied — NO silent downgrade

        var errorDescription: String? {
            switch self {
            case .notSupported:                return "This device can't use App Attest."
            case .keyNotRegistered:            return "This device hasn't been registered for secure actions yet."
            case .keyLost:                     return "The device security key needs to be set up again."
            case .challengeUnavailable(let r): return "Couldn't reach the security server: \(r)"
            case .attestationRejected(let r):  return "Device registration was rejected: \(r)"
            case .assertionFailed(let r):      return "Couldn't produce a device signature: \(r)"
            case .biometricsFailed(let r):     return "Face ID / Touch ID was not confirmed: \(r)"
            }
        }
    }

    // MARK: - Package D §1 — one-time key generation + attestation

    /// Idempotent registration. On a supported device with no key yet: generate a
    /// Secure-Enclave key, fetch a one-time server challenge, attest the key over
    /// SHA256(utf8(challenge)), send the attestation object to the server, and — only
    /// if the server accepts — persist the keyId in the Keychain. Returns the resulting
    /// readiness. No-op (no throw) on unsupported hardware or when already registered.
    @discardableResult
    func registerIfNeeded(identity: String) async throws -> Readiness {
        guard attestService.isSupported else { return .unsupported }
        if cachedKeyId != nil { return .ready }

        // (b) generate the Secure-Enclave-backed key (Apple returns an opaque keyId)
        let keyId: String
        do {
            keyId = try await attestService.generateKey()
        } catch {
            throw AppAttestError.assertionFailed("generateKey: \(error.localizedDescription)")
        }

        // (a) one-time challenge, bound to this identity, from the server
        let challenge = try await fetchChallenge(identity: identity)

        // (c) attest the key over SHA256(utf8(challenge)) — the exact transform the
        //     server reconstructs in verify_attestation.
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation: Data
        do {
            attestation = try await attestService.attestKey(keyId, clientDataHash: clientDataHash)
        } catch {
            throw AppAttestError.attestationRejected(error.localizedDescription)
        }

        // (d) register with the server. Persist the keyId ONLY after the server accepts
        //     — we never treat an unconfirmed key as registered.
        let result = try await MTRXAPIClient.shared.verifyAttestation(
            keyId: keyId,
            attestationObjectB64: attestation.base64EncodedString(),
            challenge: challenge
        )
        guard result.verified else {
            throw AppAttestError.attestationRejected(result.reason ?? "unverified")
        }

        Self.storeKeyId(keyId)
        cachedKeyId = keyId
        return .ready
    }

    // MARK: - Package D §2 / Package E — per-request assertion (the device factor)

    /// The EXACT envelope the server reads: the gate's `context["app_attest"]` and
    /// owner.py's `device_assertion` both use these snake_case keys.
    struct Envelope: Encodable, Equatable {
        let key_id: String
        let assertion_b64: String
        let client_data_hash: String   // base64 of the 32-byte SHA256 the device signed
        let challenge: String
    }

    /// Produce a signed assertion bound to *requestBytes* and a fresh server challenge.
    ///
    /// - requireBiometrics: when true (owner-gated / high-value — Package E), the user
    ///   MUST pass Face/Touch ID (passcode fallback) BEFORE the assertion is produced,
    ///   so a stolen, already-unlocked phone still can't silently authorize the action.
    ///   A biometric failure THROWS `.biometricsFailed` and does NOT downgrade to any
    ///   weaker path — the caller decides whether to offer the explicit OTP fallback.
    func makeAssertion(
        for requestBytes: Data,
        identity: String,
        requireBiometrics: Bool,
        biometricReason: String = "Confirm it's you to authorize this action"
    ) async throws -> Envelope {
        guard attestService.isSupported else { throw AppAttestError.notSupported }
        guard let keyId = cachedKeyId else { throw AppAttestError.keyNotRegistered }

        // Package E §1 — the biometric gate runs BEFORE signing. No silent fallback.
        if requireBiometrics {
            do {
                _ = try await BiometricAuth.shared.authenticate(
                    reason: biometricReason, allowPasscodeFallback: true)
            } catch {
                throw AppAttestError.biometricsFailed(error.localizedDescription)
            }
        }

        // (a) fresh, single-use, TTL-bounded challenge
        let challenge = try await fetchChallenge(identity: identity)

        // (c) clientDataHash = SHA256( utf8(challenge) + canonical request bytes ).
        //     Binding the challenge AND the request into the signed hash means a
        //     captured assertion can't be replayed against a different request.
        let clientData = Data(challenge.utf8) + requestBytes
        let clientDataHash = Data(SHA256.hash(data: clientData))

        // (d) sign with the attested Secure-Enclave key.
        let assertion: Data
        do {
            assertion = try await attestService.generateAssertion(keyId, clientDataHash: clientDataHash)
        } catch {
            // A key Apple no longer recognizes (device restore / app reinstall) fails
            // here. Treat it as key-lost so the caller can re-register — never pretend
            // the assertion succeeded.
            cachedKeyId = nil
            Self.deleteKeyId()
            throw AppAttestError.keyLost
        }

        return Envelope(
            key_id: keyId,
            assertion_b64: assertion.base64EncodedString(),
            client_data_hash: clientDataHash.base64EncodedString(),
            challenge: challenge
        )
    }

    /// Package D — fund-moving assertion. Biometric-gated per the client contract
    /// (the gate insists a stolen unlocked phone can't silently authorize a transfer).
    func fundMovingAssertion(for requestBytes: Data, identity: String) async throws -> Envelope {
        try await makeAssertion(
            for: requestBytes, identity: identity, requireBiometrics: true,
            biometricReason: "Confirm it's you to authorize this transaction")
    }

    /// Package E — the owner third factor. Produces a Face/Touch-ID-gated device
    /// assertion for an owner-gated action (server owner.py prefers this over SMS OTP).
    /// On biometric failure / unsupported hardware / lost key this THROWS — it NEVER
    /// silently downgrades. The caller surfaces the failure and lets the user EXPLICITLY
    /// choose the SMS-OTP fallback (`MTRXAPIClient.requestPhoneOTP` / `verifyPhoneOTP`).
    func ownerDeviceAssertion(for requestBytes: Data, identity: String) async throws -> Envelope {
        try await makeAssertion(
            for: requestBytes, identity: identity, requireBiometrics: true,
            biometricReason: "Confirm it's you to authorize this owner action")
    }

    // MARK: - Reset

    /// Drop the local key binding (sign-out / account reset). A fresh `registerIfNeeded`
    /// will mint and attest a new key.
    func reset() {
        cachedKeyId = nil
        Self.deleteKeyId()
    }

    // MARK: - Internals

    private func fetchChallenge(identity: String) async throws -> String {
        do {
            return try await MTRXAPIClient.shared.fetchAttestChallenge(identity: identity)
        } catch {
            throw AppAttestError.challengeUnavailable(error.localizedDescription)
        }
    }

    // Keychain storage of the keyId — device-only, not synced, not biometric.
    private static func storeKeyId(_ keyId: String) {
        try? KeychainManager.shared.store(
            key: keyIdKeychainKey, data: Data(keyId.utf8),
            biometricProtection: false, iCloudSync: false)
    }

    private static func loadKeyId() -> String? {
        guard let data = try? KeychainManager.shared.retrieve(key: keyIdKeychainKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeyId() {
        try? KeychainManager.shared.delete(key: keyIdKeychainKey)
    }
}
