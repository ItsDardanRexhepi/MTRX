import Foundation

// MARK: - Models

struct Attestation: Codable, Identifiable {
    var id: String { uid }
    let uid: String
    let schema: String
    let attester: String
    let recipient: String
    let data: [String: String]
    let timestamp: Date
    let isRevoked: Bool
}

struct AttestationResult: Codable {
    let uid: String
    let txHash: String
    let attestation: Attestation?
}

// MARK: - Service

@MainActor
final class AttestationService {

    static let shared = AttestationService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getAttestationsForAddress(address: String) async throws -> [Attestation] {
        try await api.get("/attestations", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func createAttestation(schema: String, recipient: String, data: [String: String]) async throws -> AttestationResult {
        struct CreateBody: Codable {
            let schema: String
            let recipient: String
            let data: [String: String]
        }
        let body = CreateBody(schema: schema, recipient: recipient, data: data)
        return try await api.post("/attestations", body: body)
    }

    func verifyAttestation(uid: String) async throws -> Attestation {
        try await api.get("/attestations/\(uid)")
    }
}
