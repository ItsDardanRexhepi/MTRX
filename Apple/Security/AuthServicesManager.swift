// AuthServicesManager.swift
// MTRX Apple Integration — Security
// Sign in with Apple + Private Email Relay via AuthenticationServices

import AuthenticationServices
import Foundation
import UIKit

// MARK: - Auth Services Manager

final class AuthServicesManager: NSObject {

    // MARK: - Shared Instance

    static let shared = AuthServicesManager()

    // MARK: - Properties

    private var authContinuation: CheckedContinuation<AppleSignInResult, Error>?

    // MARK: - Sign In with Apple

    /// Initiates Sign in with Apple flow and returns the credential result.
    func signInWithApple() async throws -> AppleSignInResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Credential State

    /// Checks the current credential state for a given user identifier.
    func checkCredentialState(userId: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        return try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { state, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: state)
            }
        }
    }

    /// Monitors credential revocation and triggers wallet lock if needed.
    func observeCredentialRevocation(onRevoked: @escaping (String) -> Void) {
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { _ in
            if let userId = UserDefaults.standard.string(forKey: "com.mtrx.appleUserId") {
                onRevoked(userId)
            }
        }
    }

    // MARK: - Private Email Relay

    /// Sends an email via Apple's Private Email Relay to protect user identity.
    func sendRelayEmail(to relayAddress: String, subject: String, body: String) async throws {
        guard relayAddress.hasSuffix("@privaterelay.appleid.com") else {
            throw AuthServicesError.invalidRelayAddress
        }

        try await MTRXEmailRelayAPI.shared.send(
            to: relayAddress,
            subject: subject,
            body: body
        )
    }

    // MARK: - Passkey Support

    /// Creates a passkey registration request for passwordless authentication.
    @available(iOS 16.0, *)
    func createPasskeyRegistration(challenge: Data, userId: Data, userName: String) -> ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "mtrx.app")
        return provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: userName,
            userID: userId
        )
    }

    /// Creates a passkey assertion request for login.
    @available(iOS 16.0, *)
    func createPasskeyAssertion(challenge: Data) -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "mtrx.app")
        return provider.createCredentialAssertionRequest(challenge: challenge)
    }

    // MARK: - Existing Credentials

    /// Performs silent credential lookup for existing accounts.
    func performExistingAccountSetup() async throws -> AppleSignInResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation

            let appleIDRequest = ASAuthorizationAppleIDProvider().createRequest()
            let passwordRequest = ASAuthorizationPasswordProvider().createRequest()

            let controller = ASAuthorizationController(authorizationRequests: [appleIDRequest, passwordRequest])
            controller.delegate = self
            controller.performRequests()
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

// MARK: - Presentation Context

extension AuthServicesManager: ASAuthorizationControllerPresentationContextProviding {
    /// Anchor the Apple sign-in sheet to the app's key window. Without
    /// this, presentation is unreliable on device.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return keyWindow ?? ASPresentationAnchor()
    }
}

extension AuthServicesManager: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch authorization.credential {
        case let credential as ASAuthorizationAppleIDCredential:
            let result = AppleSignInResult(
                userId: credential.user,
                email: credential.email,
                fullName: credential.fullName,
                identityToken: credential.identityToken,
                authorizationCode: credential.authorizationCode,
                realUserStatus: credential.realUserStatus,
                isPrivateRelay: credential.email?.hasSuffix("@privaterelay.appleid.com") ?? false
            )

            UserDefaults.standard.set(credential.user, forKey: "com.mtrx.appleUserId")
            authContinuation?.resume(returning: result)

        case let credential as ASPasswordCredential:
            let result = AppleSignInResult(
                userId: credential.user,
                email: nil,
                fullName: nil,
                identityToken: nil,
                authorizationCode: nil,
                realUserStatus: .unsupported,
                isPrivateRelay: false
            )
            authContinuation?.resume(returning: result)

        default:
            authContinuation?.resume(throwing: AuthServicesError.unknownCredentialType)
        }

        authContinuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        authContinuation?.resume(throwing: AuthServicesError.authorizationFailed(error.localizedDescription))
        authContinuation = nil
    }
}

// MARK: - Apple Sign In Result

struct AppleSignInResult {
    let userId: String
    let email: String?
    let fullName: PersonNameComponents?
    let identityToken: Data?
    let authorizationCode: Data?
    let realUserStatus: ASUserDetectionStatus
    let isPrivateRelay: Bool

    var identityTokenString: String? {
        guard let token = identityToken else { return nil }
        return String(data: token, encoding: .utf8)
    }

    var authorizationCodeString: String? {
        guard let code = authorizationCode else { return nil }
        return String(data: code, encoding: .utf8)
    }

    init(userId: String, email: String?, fullName: PersonNameComponents?, identityToken: Data?, authorizationCode: Data?, realUserStatus: ASUserDetectionStatus, isPrivateRelay: Bool) {
        self.userId = userId
        self.email = email
        self.fullName = fullName
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.realUserStatus = realUserStatus
        self.isPrivateRelay = isPrivateRelay
    }
}

// MARK: - Email Relay API

final class MTRXEmailRelayAPI {
    static let shared = MTRXEmailRelayAPI()

    func send(to address: String, subject: String, body: String) async throws {
        // Server-side email relay through Apple's infrastructure
    }
}

// MARK: - Auth Services Error

enum AuthServicesError: LocalizedError {
    case authorizationFailed(String)
    case credentialRevoked
    case unknownCredentialType
    case invalidRelayAddress
    case passkeyUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let reason): return "Apple Sign In failed: \(reason)"
        case .credentialRevoked: return "Apple ID credential has been revoked"
        case .unknownCredentialType: return "Unknown credential type received"
        case .invalidRelayAddress: return "Invalid Private Email Relay address"
        case .passkeyUnavailable: return "Passkeys are not available on this device"
        }
    }
}
