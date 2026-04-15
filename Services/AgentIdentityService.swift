import Foundation

// MARK: - Models

struct AgentIdentityProfile: Codable, Identifiable {
    var id: String { agentId }
    let agentId: String
    let ownerAddress: String
    let name: String
    let capabilities: [String]
    let trustLevel: String
    let interactionCount: Int
    let registeredAt: Date
}

struct AgentInteraction: Codable, Identifiable {
    var id: String { interactionId }
    let interactionId: String
    let action: String
    let target: String
    let timestamp: Date
    let txHash: String?
    let outcome: String
}

// MARK: - Service

@MainActor
final class AgentIdentityService {

    static let shared = AgentIdentityService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getAgentIdentity(address: String) async throws -> AgentIdentityProfile {
        try await api.get("/agents/\(address)")
    }

    func registerCapability(capability: String) async throws -> TransactionResult {
        try await api.post("/agents/capabilities", body: ["capability": capability])
    }

    func getInteractionHistory(agentId: String) async throws -> [AgentInteraction] {
        try await api.get("/agents/\(agentId)/interactions")
    }

    func revokeAgent(agentId: String) async throws -> TransactionResult {
        try await api.post("/agents/\(agentId)/revoke", body: nil as String?)
    }
}
