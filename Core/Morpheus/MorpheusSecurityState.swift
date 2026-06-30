// MorpheusSecurityState.swift
// MTRX — Morpheus security advisor: read-only security-state layer (M-STATE)
//
// The foundation the Morpheus ADVISOR surfaces read from. It OBSERVES the
// deterministic security walls; it cannot touch them. Per MORPHEUS_ADVISOR_SPEC.md:
//
//   • Morpheus advises, never enforces. NOTHING here returns a value consumed by a
//     signing or money-moving decision. If this file (and all of Core/Morpheus)
//     were deleted, the walls — testnet chain lock, biometric Secure-Enclave gate,
//     gated-key refusal, fail-closed send — behave byte-for-byte identically.
//
//   • READ-ONLY. This is a caseless namespace of pure static reads that return
//     IMMUTABLE value snapshots. There is no stored state, no setter, no toggle,
//     and no reference to a live mutable singleton ever escapes — mutable globals
//     (e.g. SecureEnclaveManager.enforceGatedOwnerKeyForValue, SecurityPreferences)
//     are copied BY VALUE into the snapshot, never returned by reference.
//
//   • "Morpheus" here is the CLIENT advisor only. This layer must NEVER import,
//     call, or feed the SERVER security preflight (MTRXAPIClient.securityPreflight-
//     AllowsSend / postFundMovingAttested / the securityBlocked|isSecurityBlock
//     error). Narrating "the security service declined this" must read the send's
//     already-computed failure state, never invoke the preflight. (Spec §6.)
//
// No warning flows and no UI live here — those are later, separate surfaces.

import Foundation
import LocalAuthentication

@MainActor
enum MorpheusSecurityState {

    // MARK: - §3a Global posture

    /// An immutable snapshot of the app's global security posture. Every field is a
    /// value copy of deterministic state; the struct holds no references.
    struct PostureSnapshot: Equatable {
        /// The configured target chain is the one (and only) chain signing is permitted on.
        let onTestnet: Bool
        /// The only chain the signing wall permits (compile-time constant, Base Sepolia).
        let permittedChainID: UInt64
        /// The currently configured chain id.
        let configuredChainID: Int
        let chainConfigured: Bool
        let backendConfigured: Bool
        let gasSponsorshipConfigured: Bool
        let appAttestEnabled: Bool
        let appAttestEnforced: Bool
        /// Snapshot of the go-live gated-key enforcement flag's VALUE (false = OBSERVE).
        let gatedKeyEnforcementArmed: Bool
        /// Regulated finance features hidden for the App Store MVP build.
        let regulatedFeaturesHidden: Bool
    }

    static func posture() -> PostureSnapshot {
        let configured = PendingCredentials.Network.chainID
        let permitted = BaseNetworkConfig.permittedSigningChainID
        return PostureSnapshot(
            onTestnet: UInt64(configured) == permitted,
            permittedChainID: permitted,
            configuredChainID: configured,
            chainConfigured: PendingCredentials.isChainConfigured,
            backendConfigured: PendingCredentials.isBackendConfigured,
            gasSponsorshipConfigured: PendingCredentials.isGasSponsorshipConfigured,
            appAttestEnabled: PendingCredentials.isAppAttestEnabled,
            appAttestEnforced: PendingCredentials.isAppAttestEnforced,
            gatedKeyEnforcementArmed: SecureEnclaveManager.enforceGatedOwnerKeyForValue,
            regulatedFeaturesHidden: FeatureFlags.mvpMode
        )
    }

    // MARK: - §3b Wallet / key security

    /// An immutable snapshot of the active wallet's protective state.
    struct WalletSecuritySnapshot: Equatable {
        let secureEnclaveAvailable: Bool
        let biometricsAvailable: Bool
        /// "Face ID" / "Touch ID" / "biometrics" — for honest narration.
        let biometryLabel: String
        let hasActiveWallet: Bool
        /// Whether there is a real LOCAL signing key on this device. false for an
        /// identity-only cloud restore (a wallet record exists but no local key yet —
        /// recovery is needed), which must NOT be narrated as "an ungated key".
        let hasLocalSigningKey: Bool
        /// Whether the owner key is biometric-gated. nil when there is no LOCAL signing
        /// key (no wallet, or an identity-only restore) — never a fabricated false.
        /// Probed from the REAL access control (non-spoofable).
        let ownerKeyBiometricGated: Bool?
        /// The user's own "require Face ID at signing" preference (value snapshot).
        let requireBiometricForSigning: Bool
        let guardianCount: Int
        let hasCloudBackup: Bool
        let appAttestSupported: Bool
        let appAttestRegistered: Bool
    }

    static func wallet() -> WalletSecuritySnapshot {
        let record = WalletRecordStore.load()
        let tag = record?.keyTag
        let biometry: String
        switch BiometricAuth.shared.biometryType {
        case .faceID: biometry = "Face ID"
        case .touchID: biometry = "Touch ID"
        default:      biometry = "biometrics"
        }
        return WalletSecuritySnapshot(
            secureEnclaveAvailable: SecureEnclaveManager.shared.isSecureEnclaveAvailable,
            biometricsAvailable: BiometricAuth.shared.canUseBiometrics,
            biometryLabel: biometry,
            hasActiveWallet: record != nil,
            hasLocalSigningKey: hasLocalSigningKey(tag: tag),
            ownerKeyBiometricGated: ownerKeyGated(tag: tag),
            requireBiometricForSigning: SecurityPreferences.shared.requireBiometricForSigning,
            guardianCount: GuardianStore.load().count,
            hasCloudBackup: WalletCreation.hasCloudBackup(),
            appAttestSupported: AppAttestManager.shared.isSupported,
            appAttestRegistered: AppAttestManager.shared.hasKey
        )
    }

    /// Whether the active wallet record points to a real LOCAL signing key (a
    /// non-empty key tag). An identity-only cloud restore persists a record with an
    /// EMPTY tag — address known, no local key yet, recovery needed — which must
    /// never be confused with "an ungated key" (that would wrongly suggest a reset).
    static func hasLocalSigningKey(tag: String?) -> Bool { (tag?.isEmpty == false) }

    /// Whether the owner key is biometric-gated. nil when there is no LOCAL signing
    /// key (no wallet, or an identity-only restore) — never a fabricated false. The
    /// probe reads the REAL access control (non-spoofable).
    static func ownerKeyGated(tag: String?) -> Bool? {
        guard let tag, !tag.isEmpty else { return nil }
        return SecureEnclaveManager.shared.isGated(tag: tag)
    }

    // MARK: - §3c Per-action context (only when an action is being composed)

    /// Whether the destination is one of the user's known contacts (membership in
    /// the contact address book). NOTE: this is the only recipient-novelty signal
    /// available today — there is no native-send history to ground "you've sent
    /// here before" (deferred in the spec), so callers must not overstate.
    static func isRecipientInContacts(_ address: String) -> Bool {
        isAddress(address, inKnown: ContactsManager.shared.mtrxContacts.map { $0.walletAddress })
    }

    /// Pure, case-insensitive membership check — exposed so the predicate is testable
    /// without a live Contacts store.
    static func isAddress(_ address: String, inKnown known: [String]) -> Bool {
        let target = address.lowercased()
        return known.contains { $0.lowercased() == target }
    }

    /// Whether moving funds via the active wallet requires Face ID: true ONLY when a
    /// real local owner key exists and is biometric-gated (the enclave then requires
    /// Face ID to sign). false when there is no wallet OR an identity-only restore
    /// (no local key) OR a non-gated key — those are not "this send needs Face ID".
    static func nativeSendRequiresFaceID() -> Bool {
        ownerKeyGated(tag: WalletRecordStore.load()?.keyTag) == true
    }

    /// Which of the user's OWN configured thresholds a transfer crosses. The caller
    /// supplies the USD amount — which is PRICE-FEED-DERIVED (spec §5 price caveat),
    /// so any narration must say "at the current price" — and today's outgoing USD
    /// total. Pure comparison against SecurityPreferences VALUES; the singleton is
    /// never returned by reference.
    struct ThresholdCrossings: Equatable {
        let crossesExtraConfirm: Bool
        let crossesCoolingOff: Bool
        let coolingOffDelaySeconds: TimeInterval?
        let crossesDailySoft: Bool
    }

    static func thresholdCrossings(amountUSD: Double, todayOutgoingUSD: Double) -> ThresholdCrossings {
        let prefs = SecurityPreferences.shared
        let coolingOff = prefs.coolingOffDelay(amountUSD: amountUSD)
        return ThresholdCrossings(
            crossesExtraConfirm: prefs.requiresExtraConfirmation(amountUSD: amountUSD),
            crossesCoolingOff: coolingOff != nil,
            coolingOffDelaySeconds: coolingOff,
            crossesDailySoft: prefs.exceedsDailySoftThreshold(amountUSD: amountUSD, todayTotalUSD: todayOutgoingUSD)
        )
    }
}
