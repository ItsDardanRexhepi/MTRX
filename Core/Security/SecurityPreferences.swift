// SecurityPreferences.swift
// MTRX — User-side fund-protection defaults (Phase 4).
//
// Protective DEFAULTS the USER owns and controls. The system never overrides a
// user's choice over their OWN wallet — these exist to protect users who haven't
// set their own. Every one can be raised, lowered, or disabled in
// Settings → Security.
//
// These are UX/safety prompts on the user's own transfers. They are distinct from
// the agent spend limits (server-side, cap autonomous agents) and from the
// Morpheus security gate (server-side enforcement). The non-custodial invariant is
// untouched: only the user's Secure Enclave ever signs.

import Foundation
import Observation

@MainActor
@Observable
final class SecurityPreferences {

    static let shared = SecurityPreferences()

    // MARK: Defaults (spec Phase 4)

    static let defaultExtraConfirmUSD: Double = 1_000      // extra confirmation over $1k
    static let defaultCoolingOffUSD: Double = 10_000       // 1-hour delay over $10k
    static let defaultCoolingOffSeconds: Double = 3_600
    static let defaultDailySoftUSD: Double = 25_000        // extra verification over $25k/day

    // MARK: Extra confirmation (over a threshold)

    var extraConfirmEnabled: Bool { didSet { d.set(extraConfirmEnabled, forKey: "sec.extraConfirm.on") } }
    var extraConfirmThresholdUSD: Double { didSet { d.set(extraConfirmThresholdUSD, forKey: "sec.extraConfirm.usd") } }

    // MARK: Cooling-off / time-delay (gives a window to freeze if it's theft)

    var coolingOffEnabled: Bool { didSet { d.set(coolingOffEnabled, forKey: "sec.coolOff.on") } }
    var coolingOffThresholdUSD: Double { didSet { d.set(coolingOffThresholdUSD, forKey: "sec.coolOff.usd") } }
    var coolingOffDelaySeconds: Double { didSet { d.set(coolingOffDelaySeconds, forKey: "sec.coolOff.secs") } }

    // MARK: Daily soft threshold (extra verification, NOT a hard block — it's the user's money)

    var dailySoftEnabled: Bool { didSet { d.set(dailySoftEnabled, forKey: "sec.dailySoft.on") } }
    var dailySoftThresholdUSD: Double { didSet { d.set(dailySoftThresholdUSD, forKey: "sec.dailySoft.usd") } }

    // MARK: Face ID at the moment of signing (in addition to the app-entry lock)

    var requireBiometricForSigning: Bool { didSet { d.set(requireBiometricForSigning, forKey: "sec.bioSign.on") } }

    private let d = UserDefaults.standard

    private init() {
        // Use a LOCAL reference (not self.d) so the helpers don't capture self
        // before all stored properties are initialized (@Observable requirement).
        let store = UserDefaults.standard
        func dbl(_ key: String, _ def: Double) -> Double {
            store.object(forKey: key) == nil ? def : store.double(forKey: key)
        }
        func bool(_ key: String, _ def: Bool) -> Bool {
            store.object(forKey: key) as? Bool ?? def
        }
        extraConfirmEnabled = bool("sec.extraConfirm.on", true)
        extraConfirmThresholdUSD = dbl("sec.extraConfirm.usd", Self.defaultExtraConfirmUSD)
        coolingOffEnabled = bool("sec.coolOff.on", true)
        coolingOffThresholdUSD = dbl("sec.coolOff.usd", Self.defaultCoolingOffUSD)
        coolingOffDelaySeconds = dbl("sec.coolOff.secs", Self.defaultCoolingOffSeconds)
        dailySoftEnabled = bool("sec.dailySoft.on", true)
        dailySoftThresholdUSD = dbl("sec.dailySoft.usd", Self.defaultDailySoftUSD)
        requireBiometricForSigning = bool("sec.bioSign.on", true)
    }

    // MARK: - Decisions for the transfer flow

    /// Whether a transfer of *amountUSD* needs the extra plain-language confirmation.
    func requiresExtraConfirmation(amountUSD: Double) -> Bool {
        extraConfirmEnabled && amountUSD > extraConfirmThresholdUSD
    }

    /// The cooling-off delay a transfer of *amountUSD* must wait, or nil if none.
    /// A queued transfer can be cancelled during this window (ties to freeze).
    func coolingOffDelay(amountUSD: Double) -> TimeInterval? {
        guard coolingOffEnabled, amountUSD > coolingOffThresholdUSD else { return nil }
        return coolingOffDelaySeconds
    }

    /// Whether adding *amountUSD* to *todayTotalUSD* crosses the daily soft
    /// threshold (extra verification, not a block).
    func exceedsDailySoftThreshold(amountUSD: Double, todayTotalUSD: Double) -> Bool {
        dailySoftEnabled && (todayTotalUSD + amountUSD) > dailySoftThresholdUSD
    }

    /// Reset every protection to its protective default.
    func resetToDefaults() {
        extraConfirmEnabled = true
        extraConfirmThresholdUSD = Self.defaultExtraConfirmUSD
        coolingOffEnabled = true
        coolingOffThresholdUSD = Self.defaultCoolingOffUSD
        coolingOffDelaySeconds = Self.defaultCoolingOffSeconds
        dailySoftEnabled = true
        dailySoftThresholdUSD = Self.defaultDailySoftUSD
        requireBiometricForSigning = true
    }
}
