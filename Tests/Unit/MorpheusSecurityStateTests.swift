import XCTest
@testable import MTRX

/// M-STATE: the read-only Morpheus security-state layer. These tests prove the
/// façade READS deterministic state and returns immutable value snapshots, and that
/// invoking it mutates nothing (no side effects, no enforcement). The advisor never
/// enforces; the signing-wall's independence from the advisor is proven separately
/// in SigningWallTests.
@MainActor
final class MorpheusSecurityStateTests: XCTestCase {

    // MARK: Posture (§3a) reflects the real deterministic state

    func testPosture_reflectsDeterministicState() {
        let p = MorpheusSecurityState.posture()
        // The signing wall's single permitted chain is Base Sepolia (compile-time).
        XCTAssertEqual(p.permittedChainID, BaseNetworkConfig.permittedSigningChainID)
        XCTAssertEqual(p.permittedChainID, 84_532)
        // onTestnet is derived purely from configured-vs-permitted chain id.
        XCTAssertEqual(p.onTestnet, UInt64(p.configuredChainID) == p.permittedChainID)
        // Posture mirrors the real config keystone (no fabrication).
        XCTAssertEqual(p.backendConfigured, PendingCredentials.isBackendConfigured)
        XCTAssertEqual(p.chainConfigured, PendingCredentials.isChainConfigured)
        XCTAssertEqual(p.regulatedFeaturesHidden, FeatureFlags.mvpMode)
        // Snapshots the go-live flag's VALUE; OBSERVE (false) by default.
        XCTAssertEqual(p.gatedKeyEnforcementArmed, SecureEnclaveManager.enforceGatedOwnerKeyForValue)
    }

    func testPosture_isAStableImmutableSnapshot() {
        XCTAssertEqual(MorpheusSecurityState.posture(), MorpheusSecurityState.posture())
    }

    // MARK: Wallet (§3b) reads without side effects

    func testWallet_readsWithoutMutatingState() {
        let recordBefore = WalletRecordStore.load()?.keyTag
        let guardiansBefore = GuardianStore.load().count

        let w1 = MorpheusSecurityState.wallet()
        let w2 = MorpheusSecurityState.wallet()

        // Reading is pure: no wallet bound, no guardian added, snapshots stable.
        XCTAssertEqual(WalletRecordStore.load()?.keyTag, recordBefore,
                       "Reading wallet security state must not bind/alter the active wallet")
        XCTAssertEqual(GuardianStore.load().count, guardiansBefore)
        XCTAssertEqual(w1, w2, "Wallet snapshot is a stable immutable value")
        // Field truths mirror the underlying stores (no fabrication).
        XCTAssertEqual(w1.hasActiveWallet, recordBefore != nil)
        XCTAssertEqual(w1.hasLocalSigningKey, MorpheusSecurityState.hasLocalSigningKey(tag: recordBefore))
        XCTAssertEqual(w1.guardianCount, guardiansBefore)
        XCTAssertEqual(w1.requireBiometricForSigning, SecurityPreferences.shared.requireBiometricForSigning)
        // No LOCAL signing key → gated state is unknown (nil), never a fabricated bool.
        if !w1.hasLocalSigningKey { XCTAssertNil(w1.ownerKeyBiometricGated) }
    }

    /// The identity-only cloud restore (a wallet record with an EMPTY key tag) must
    /// report "no local key / gated unknown", never a fabricated "ungated" false —
    /// otherwise Morpheus would advise "reset your ungated key" when the truth is
    /// "recover to establish a key on this device".
    func testIdentityOnlyRestore_isNotNarratedAsAnUngatedKey() {
        // No record at all.
        XCTAssertFalse(MorpheusSecurityState.hasLocalSigningKey(tag: nil))
        XCTAssertNil(MorpheusSecurityState.ownerKeyGated(tag: nil))
        // Identity-only restore: record exists but the key tag is empty.
        XCTAssertFalse(MorpheusSecurityState.hasLocalSigningKey(tag: ""))
        XCTAssertNil(MorpheusSecurityState.ownerKeyGated(tag: ""),
                     "Empty tag is 'unknown/none', not a fabricated 'ungated' false")
        // A real local key tag → there is a local key.
        XCTAssertTrue(MorpheusSecurityState.hasLocalSigningKey(tag: "wallet.someUser"))
    }

    // MARK: Per-action reads (§3c)

    func testRecipientNovelty_isACaseInsensitiveMembershipCheck() {
        let known = ["0xAbC0000000000000000000000000000000000001",
                     "0xdef0000000000000000000000000000000000002"]
        // Real membership, case-insensitive: mixed-case input still matches.
        XCTAssertTrue(MorpheusSecurityState.isAddress(
            "0xABC0000000000000000000000000000000000001", inKnown: known))
        // A different address is NOT a member (proves it's not a constant).
        XCTAssertFalse(MorpheusSecurityState.isAddress(
            "0x0000000000000000000000000000000000000009", inKnown: known))
        // Empty known set → never a member.
        XCTAssertFalse(MorpheusSecurityState.isAddress("0xabc", inKnown: []))
        // Live wrapper returns false in the test env (no contacts loaded) — honest.
        XCTAssertFalse(MorpheusSecurityState.isRecipientInContacts(
            "0x000000000000000000000000000000000000dEaD"))
    }

    func testThresholdCrossings_matchTheUsersOwnSettings() {
        let prefs = SecurityPreferences.shared
        prefs.resetToDefaults()   // extraConfirm $1k, coolingOff $10k/1h, dailySoft $25k
        defer { prefs.resetToDefaults() }

        // Below every threshold → no crossings.
        let low = MorpheusSecurityState.thresholdCrossings(amountUSD: 100, todayOutgoingUSD: 0)
        XCTAssertFalse(low.crossesExtraConfirm)
        XCTAssertFalse(low.crossesCoolingOff)
        XCTAssertNil(low.coolingOffDelaySeconds)
        XCTAssertFalse(low.crossesDailySoft)

        // Above extra-confirm only.
        let mid = MorpheusSecurityState.thresholdCrossings(amountUSD: 5_000, todayOutgoingUSD: 0)
        XCTAssertTrue(mid.crossesExtraConfirm)
        XCTAssertFalse(mid.crossesCoolingOff)

        // Above cooling-off → carries the real configured delay.
        let high = MorpheusSecurityState.thresholdCrossings(amountUSD: 12_000, todayOutgoingUSD: 0)
        XCTAssertTrue(high.crossesCoolingOff)
        XCTAssertEqual(high.coolingOffDelaySeconds, SecurityPreferences.defaultCoolingOffSeconds)

        // Daily soft is cumulative with today's total.
        let daily = MorpheusSecurityState.thresholdCrossings(amountUSD: 5_000, todayOutgoingUSD: 22_000)
        XCTAssertTrue(daily.crossesDailySoft)
    }

    func testThresholdCrossings_atTheBoundaryDoNotCross() {
        let prefs = SecurityPreferences.shared
        prefs.resetToDefaults(); defer { prefs.resetToDefaults() }
        // Exactly AT each threshold does NOT cross (the comparison is strict >).
        let extra = MorpheusSecurityState.thresholdCrossings(amountUSD: 1_000, todayOutgoingUSD: 0)
        XCTAssertFalse(extra.crossesExtraConfirm)
        let cool = MorpheusSecurityState.thresholdCrossings(amountUSD: 10_000, todayOutgoingUSD: 0)
        XCTAssertFalse(cool.crossesCoolingOff)
        XCTAssertNil(cool.coolingOffDelaySeconds)
        // Today's total + amount == $25k exactly is not "over".
        let daily = MorpheusSecurityState.thresholdCrossings(amountUSD: 5_000, todayOutgoingUSD: 20_000)
        XCTAssertFalse(daily.crossesDailySoft)
    }

    func testThresholdCrossings_respectAllDisabledToggles() {
        let prefs = SecurityPreferences.shared
        prefs.resetToDefaults(); defer { prefs.resetToDefaults() }
        prefs.extraConfirmEnabled = false
        prefs.coolingOffEnabled = false
        prefs.dailySoftEnabled = false
        // Disabling each protection is the USER's call — a huge amount crosses nothing.
        let r = MorpheusSecurityState.thresholdCrossings(amountUSD: 100_000, todayOutgoingUSD: 100_000)
        XCTAssertFalse(r.crossesExtraConfirm)
        XCTAssertFalse(r.crossesCoolingOff)
        XCTAssertNil(r.coolingOffDelaySeconds)
        XCTAssertFalse(r.crossesDailySoft)
    }
}
