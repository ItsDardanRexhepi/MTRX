import Foundation

// MARK: - Models

struct RoleAssignment: Codable, Identifiable {
    let id: UUID
    let contract: String
    let role: String
    let grantedBy: String
    let grantedAt: Date
    let expiresAt: Date?
}

struct SvcRoleDefinition: Codable, Identifiable {
    let id: UUID
    let role: String
    let name: String
    let description: String
    let permissions: [String]
}

struct SvcAccessLogEntry: Codable, Identifiable {
    let id: UUID
    let action: String
    let actor: String
    let target: String
    let role: String
    let timestamp: Date
}

// MARK: - Service

@MainActor
final class AccessControlService {

    static let shared = AccessControlService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getUserRoles(address: String) async throws -> [RoleAssignment] {
        try await api.get(path: "/access-control/roles", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func grantRole(contract: String, role: String, to address: String, expiresAt: Date?) async throws -> SvcTransactionResult {
        struct GrantBody: Codable {
            let contract: String
            let role: String
            let to: String
            let expiresAt: Date?
        }
        let body = GrantBody(contract: contract, role: role, to: address, expiresAt: expiresAt)
        return try await api.post(path: "/access-control/roles/grant", body: body)
    }

    func revokeRole(contract: String, role: String, from address: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/access-control/roles/revoke", body: [
            "contract": contract,
            "role": role,
            "from": address
        ])
    }

    func getRoleDefinitions(contract: String) async throws -> [SvcRoleDefinition] {
        try await api.get(path: "/access-control/contracts/\(contract)/roles")
    }

    func getAccessLog(contract: String) async throws -> [SvcAccessLogEntry] {
        try await api.get(path: "/access-control/contracts/\(contract)/log")
    }
}
