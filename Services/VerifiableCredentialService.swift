import Foundation

// MARK: - Models

struct SvcVerifiableCredential: Codable, Identifiable {
    let id: String
    let type: String
    let issuerDID: String
    let subjectDID: String
    let claims: [String: String]
    let issuanceDate: Date
    let expirationDate: Date?
    let proof: String?
    let status: String
}

struct CredentialVerificationResult: Codable {
    let isValid: Bool
    let issuer: String
    let subject: String
    let expiresAt: Date?
    let revokedAt: Date?
    let reason: String?
}

// MARK: - Service

@MainActor
final class VerifiableCredentialService {

    static let shared = VerifiableCredentialService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getCredentials(address: String) async throws -> [SvcVerifiableCredential] {
        try await api.get(path: "/credentials", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func issueCredential(recipient: String, type: String, claims: [String: String], expiryDate: Date?) async throws -> SvcVerifiableCredential {
        struct IssueBody: Codable {
            let recipient: String
            let type: String
            let claims: [String: String]
            let expiryDate: Date?
        }
        let body = IssueBody(recipient: recipient, type: type, claims: claims, expiryDate: expiryDate)
        return try await api.post(path: "/credentials", body: body)
    }

    func verifyCredential(credentialId: String) async throws -> CredentialVerificationResult {
        try await api.get(path: "/credentials/\(credentialId)/verify")
    }

    func revokeCredential(credentialId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/credentials/\(credentialId)/revoke", body: nil as String?)
    }
}
