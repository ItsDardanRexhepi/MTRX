// BiometricAuth.swift
// MTRX — Core/Wallet
//
// LocalAuthentication Face ID / Touch ID wrapper. One async call,
// honest availability reporting, passcode fallback by policy.

import Foundation
import LocalAuthentication

final class BiometricAuth {

    static let shared = BiometricAuth()

    enum AuthError: Error, LocalizedError {
        case unavailable(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let why): return "Biometrics unavailable: \(why)"
            case .failed(let why): return "Authentication failed: \(why)"
            }
        }
    }

    /// The biometry this device offers right now.
    var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    /// Whether Face ID / Touch ID can be evaluated right now.
    var canUseBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Authenticate the device owner. Tries biometrics first; when
    /// `allowPasscodeFallback` is true the system passcode sheet is the
    /// backstop, so the flow never dead-ends on a failed face scan.
    @discardableResult
    func authenticate(
        reason: String = "Unlock your MTRX wallet",
        allowPasscodeFallback: Bool = true
    ) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        let policy: LAPolicy = allowPasscodeFallback
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            throw AuthError.unavailable(error?.localizedDescription ?? "not enrolled")
        }

        do {
            return try await context.evaluatePolicy(policy, localizedReason: reason)
        } catch {
            throw AuthError.failed(error.localizedDescription)
        }
    }

    /// Authenticate the device owner and RETURN the authenticated `LAContext`,
    /// so the caller can thread it into the Secure Enclave for the signature that
    /// immediately follows (P3.2, decision #2). The enclave reuses this
    /// authentication instead of prompting a second time — one Face ID per Send,
    /// not two. `reuseWindow` keeps the authentication valid just long enough to
    /// cover the following signature; it is NOT a standing unlock.
    ///
    /// Throws on cancel / failure / unavailable — so a caller that gets a context
    /// back is holding a successfully-authenticated one; there is no "maybe".
    func authenticatedContext(
        reason: String,
        allowPasscodeFallback: Bool = true,
        reuseWindow: TimeInterval = 10
    ) async throws -> LAContext {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.touchIDAuthenticationAllowableReuseDuration = reuseWindow

        let policy: LAPolicy = allowPasscodeFallback
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            throw AuthError.unavailable(error?.localizedDescription ?? "not enrolled")
        }

        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: reason)
            guard ok else { throw AuthError.failed("not confirmed") }
            return context
        } catch let authError as AuthError {
            throw authError
        } catch {
            throw AuthError.failed(error.localizedDescription)
        }
    }
}
