import Foundation

// MARK: - Models

struct KYCStatus: Codable {
    let verifiedTypes: [String]
    let proofs: [KYCProof]
    let lastUpdated: Date
}

enum KYCVerificationType: String, Codable, CaseIterable {
    case age
    case jurisdiction
    case accreditedInvestor
    case humanProof
    case institutionEmployee
}

struct KYCProof: Codable, Identifiable {
    var id: String { proofId }
    let proofId: String
    let type: String
    let issuedAt: Date
    let expiresAt: Date?
    let sharedWith: [String]
}

struct KYCSession: Codable {
    let sessionId: String
    let verificationType: String
    let status: String
}

struct KYCResult: Codable {
    let proofId: String
    let success: Bool
    let message: String?
}

// MARK: - Service

@MainActor
final class KYCService {

    static let shared = KYCService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getKYCStatus(address: String) async throws -> KYCStatus {
        try await api.get("/kyc/status", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func initiateVerification(type: String) async throws -> KYCSession {
        try await api.post("/kyc/verify", body: ["type": type])
    }

    func submitVerification(sessionId: String, documentData: Data, selfieData: Data) async throws -> KYCResult {
        struct SubmitBody: Codable {
            let sessionId: String
            let documentBase64: String
            let selfieBase64: String
        }
        let body = SubmitBody(
            sessionId: sessionId,
            documentBase64: documentData.base64EncodedString(),
            selfieBase64: selfieData.base64EncodedString()
        )
        return try await api.post("/kyc/verify/\(sessionId)/submit", body: body)
    }

    func shareProof(proofId: String, recipient: String) async throws -> TransactionResult {
        try await api.post("/kyc/proofs/\(proofId)/share", body: ["recipient": recipient])
    }

    func revokeAccess(proofId: String, recipient: String) async throws -> TransactionResult {
        try await api.post("/kyc/proofs/\(proofId)/revoke", body: ["recipient": recipient])
    }
}
