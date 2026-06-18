// AppLock.swift
// MTRX — App
//
// A real, secure app-entry lock. Content stays hidden behind the portal until a
// GENUINELY successful Face ID / Touch ID (or device-passcode fallback). A failed
// or cancelled authentication NEVER unlocks. `isLocked` is cleared in exactly one
// function — authenticate() — and only in two honest cases: a real success, or a
// device with NO passcode at all (no OS security boundary exists for the lock to
// enforce, so an unbreakable lock would brick access while protecting nothing).
//
// This is IN ADDITION to the per-transaction Morpheus / wallet Face ID gates,
// not a replacement for them.

import SwiftUI
import Observation

@MainActor
@Observable
final class AppLock {

    static let shared = AppLock()

    // The same key the Settings "Biometric Lock" toggle binds to, so that
    // toggle genuinely gates this lock.
    private let enabledKey = "mtrx_biometric"

    /// Whether the app-lock is on. Default ON for a wallet. Persisted across
    /// launches; toggling it actually gates the lock (see RootView).
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    /// True while the lock screen must cover all content. Deliberately NOT
    /// persisted — every cold launch starts locked (when enabled).
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var lastError: String?

    private init() {
        let enabled = (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? true
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    /// Present Face ID / Touch ID with device-passcode fallback. The ONLY path
    /// that unlocks is a real `true` result; a throw (failure/cancel/unavailable)
    /// leaves the app locked and surfaces an honest message.
    func authenticate() async {
        guard isEnabled, isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        lastError = nil
        do {
            // Passcode fallback so the user is never permanently locked out if
            // Face ID isn't enrolled / repeatedly fails.
            let success = try await BiometricAuth.shared.authenticate(
                reason: "Unlock MTRX",
                allowPasscodeFallback: true)
            isAuthenticating = false
            if success {
                isLocked = false            // ← unlock: a genuine success
            } else {
                lastError = "Authentication didn't succeed. Try again."
            }
        } catch let error as BiometricAuth.AuthError {
            isAuthenticating = false
            if case .unavailable = error {
                // No biometrics AND no device passcode → there is no OS security
                // boundary for the lock to enforce. Keeping it locked forever
                // would brick the user out while protecting nothing, so we pass
                // through honestly. On ANY device with a passcode,
                // .deviceOwnerAuthentication evaluates and this branch is never
                // reached — so security is never weakened on real devices.
                isLocked = false
            } else {
                // A genuine failure / cancellation — stay locked.
                lastError = error.errorDescription ?? "Couldn't authenticate. Try again."
            }
        } catch {
            // Any other failure / cancellation — stay locked.
            isAuthenticating = false
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't authenticate. Try again, or use your device passcode."
        }
    }

    /// Re-engage the lock (called when the app backgrounds, and at the start of
    /// each authenticated session). No-op when the lock is disabled.
    func lock() {
        guard isEnabled else { return }
        isLocked = true
        lastError = nil
    }

    /// Flip the setting and apply it immediately. Enabling re-locks; disabling
    /// leaves `isLocked` untouched (the `isEnabled` gate hides the portal) so
    /// that authenticate() stays the only function that ever clears `isLocked`.
    func setEnabled(_ on: Bool) {
        isEnabled = on
        if on { isLocked = true }
        lastError = nil
    }
}

