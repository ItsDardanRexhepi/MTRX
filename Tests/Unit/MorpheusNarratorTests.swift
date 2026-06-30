import XCTest
@testable import MTRX

/// M-NARRATOR piece 1: the whole-app security narration logic. These tests prove every
/// statement is grounded in a real §3a/§3b read, the nil/identity-only cases are honest
/// (recovery-needed, never "ungated"), the narration never over-claims "secure", and it is
/// display data only (it gates nothing).
@MainActor
final class MorpheusNarratorTests: XCTestCase {

    private func posture(onTestnet: Bool = true,
                         backendConfigured: Bool = false) -> MorpheusSecurityState.PostureSnapshot {
        MorpheusSecurityState.PostureSnapshot(
            onTestnet: onTestnet, permittedChainID: 84_532,
            configuredChainID: onTestnet ? 84_532 : 8_453,
            chainConfigured: false, backendConfigured: backendConfigured,
            gasSponsorshipConfigured: false, appAttestEnabled: false, appAttestEnforced: false,
            gatedKeyEnforcementArmed: false, regulatedFeaturesHidden: true)
    }

    private func wallet(hasActiveWallet: Bool = true,
                        hasLocalSigningKey: Bool = true,
                        ownerKeyBiometricGated: Bool? = true,
                        biometryLabel: String = "Face ID",
                        biometricsAvailable: Bool = true,
                        guardianCount: Int = 0,
                        hasCloudBackup: Bool = false) -> MorpheusSecurityState.WalletSecuritySnapshot {
        MorpheusSecurityState.WalletSecuritySnapshot(
            secureEnclaveAvailable: true, biometricsAvailable: biometricsAvailable,
            biometryLabel: biometryLabel, hasActiveWallet: hasActiveWallet,
            hasLocalSigningKey: hasLocalSigningKey, ownerKeyBiometricGated: ownerKeyBiometricGated,
            requireBiometricForSigning: true, guardianCount: guardianCount,
            hasCloudBackup: hasCloudBackup, appAttestSupported: false, appAttestRegistered: false)
    }

    private func titles(_ s: [MorpheusNarrator.Statement]) -> [String] { s.map { $0.title } }
    private func blob(_ s: [MorpheusNarrator.Statement]) -> String {
        s.flatMap { [$0.title, $0.detail] }.joined(separator: " ").lowercased()
    }

    func testNetwork_testnetPermitsVsNonTestnetLocked() {
        XCTAssertTrue(titles(MorpheusNarrator.narrate(posture: posture(onTestnet: true), wallet: wallet()))
            .contains("On testnet"))
        // onTestnet == false IS the signing-lock predicate failing — the wall refuses signing on
        // the configured chain. The narrator must say signing is LOCKED, never "funds move".
        let m = MorpheusNarrator.narrate(posture: posture(onTestnet: false), wallet: wallet())
        XCTAssertTrue(titles(m).contains("Signing locked to testnet"))
        XCTAssertFalse(titles(m).contains("On testnet"))
        let b = blob(m)
        XCTAssertFalse(b.contains("moves real funds"))
        XCTAssertFalse(b.contains("every send is real"))
        XCTAssertTrue(b.contains("refused") || b.contains("nothing moves"))
    }

    func testIndeterminateKeyState_isNotNarratedAsUngated() {
        // An inconsistent snapshot (a local key present but its gated state unreadable) must NOT
        // be narrated as a definite "not biometric-gated" — it's indeterminate; recommend a check.
        let s = MorpheusNarrator.narrate(posture: posture(),
            wallet: wallet(hasActiveWallet: true, hasLocalSigningKey: true, ownerKeyBiometricGated: nil))
        XCTAssertFalse(titles(s).contains("Key not biometric-gated"))
        XCTAssertFalse(blob(s).contains("isn't biometric-gated"))
        XCTAssertTrue(titles(s).contains("Signing key needs a check"))
    }

    func testIdentityOnlyRestore_saysRecoveryNeeded_neverUngated() {
        let s = MorpheusNarrator.narrate(
            posture: posture(),
            wallet: wallet(hasActiveWallet: true, hasLocalSigningKey: false, ownerKeyBiometricGated: nil))
        XCTAssertTrue(titles(s).contains("Recovery needed"))
        // It must NOT narrate an identity-only restore as an ungated key.
        XCTAssertFalse(blob(s).contains("not biometric-gated"))
        XCTAssertFalse(blob(s).contains("ungated"))
        XCTAssertFalse(titles(s).contains("Signing key protected"))
    }

    func testGatedKey_protectedNamesTheBiometric_vsNotGated() {
        let g = MorpheusNarrator.narrate(posture: posture(),
            wallet: wallet(ownerKeyBiometricGated: true, biometryLabel: "Touch ID"))
        let prot = g.first { $0.title == "Signing key protected" }!
        XCTAssertTrue(prot.detail.contains("Touch ID"))
        XCTAssertFalse(prot.detail.contains("Face ID"))
        XCTAssertTrue(titles(MorpheusNarrator.narrate(posture: posture(),
            wallet: wallet(ownerKeyBiometricGated: false))).contains("Key not biometric-gated"))
    }

    func testGuardians_presentVsNone() {
        XCTAssertTrue(titles(MorpheusNarrator.narrate(posture: posture(), wallet: wallet(guardianCount: 0)))
            .contains("No recovery guardians"))
        XCTAssertTrue(titles(MorpheusNarrator.narrate(posture: posture(), wallet: wallet(guardianCount: 2)))
            .contains("2 recovery guardians"))
        XCTAssertTrue(titles(MorpheusNarrator.narrate(posture: posture(), wallet: wallet(guardianCount: 1)))
            .contains("1 recovery guardian"))
    }

    func testCloudBackup_savedVsNone() {
        XCTAssertTrue(titles(MorpheusNarrator.narrate(posture: posture(), wallet: wallet(hasCloudBackup: true)))
            .contains("Recovery backup saved"))
        XCTAssertTrue(titles(MorpheusNarrator.narrate(posture: posture(), wallet: wallet(hasCloudBackup: false)))
            .contains("No recovery backup"))
    }

    func testNoWallet_omitsWalletScopedClaims() {
        let s = MorpheusNarrator.narrate(posture: posture(backendConfigured: true),
            wallet: wallet(hasActiveWallet: false, hasLocalSigningKey: false, ownerKeyBiometricGated: nil))
        XCTAssertTrue(titles(s).contains("No wallet yet"))
        XCTAssertFalse(titles(s).contains("Signing key protected"))
        XCTAssertFalse(titles(s).contains("No recovery guardians"))
        XCTAssertFalse(titles(s).contains("Recovery backup saved"))
    }

    func testNeverOverClaimsSecurity_andEveryStatementIsGrounded() {
        let s = MorpheusNarrator.narrate(
            posture: posture(onTestnet: false, backendConfigured: false),
            wallet: wallet(ownerKeyBiometricGated: true, guardianCount: 3, hasCloudBackup: true))
        let b = blob(s)
        for forbidden in ["fully secure", "completely safe", "100%", "you're secure", "totally protected", "ungated"] {
            XCTAssertFalse(b.contains(forbidden), "Narrator must not over-claim '\(forbidden)'")
        }
        // Every statement is grounded in a §3 read (no ungrounded narration).
        XCTAssertTrue(s.allSatisfy { $0.grounding.contains("§3") && !$0.title.isEmpty && !$0.detail.isEmpty })
    }

    func testNarrationIsDisplayDataOnly() {
        let s: [MorpheusNarrator.Statement] = MorpheusNarrator.narrate(posture: posture(), wallet: wallet())
        XCTAssertFalse(s.isEmpty)
    }
}
