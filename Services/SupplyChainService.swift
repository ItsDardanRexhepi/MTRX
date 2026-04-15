import Foundation

// MARK: - Models

struct SupplyChainItem: Codable, Identifiable {
    var id: String { itemId }
    let itemId: String
    let name: String
    let category: String
    let currentOwner: String
    let checkpoints: [SupplyChainCheckpoint]
    let registeredAt: Date
}

struct SupplyChainCheckpoint: Codable, Identifiable {
    var id: String { checkpointId }
    let checkpointId: String
    let location: String
    let status: String
    let handler: String
    let timestamp: Date
    let txHash: String?
}

struct ItemRegistrationParams: Codable {
    let name: String
    let description: String
    let category: String
    let initialLocation: String
}

// MARK: - Service

@MainActor
final class SupplyChainService {

    static let shared = SupplyChainService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func trackItem(itemId: String) async throws -> SupplyChainItem {
        try await api.get("/supply-chain/items/\(itemId)", queryItems: nil)
    }

    func registerItem(params: ItemRegistrationParams) async throws -> SupplyChainItem {
        try await api.post("/supply-chain/items", body: params)
    }

    func addCheckpoint(itemId: String, location: String, status: String, notes: String?) async throws -> TransactionResult {
        var body: [String: String] = [
            "location": location,
            "status": status
        ]
        if let notes { body["notes"] = notes }
        return try await api.post("/supply-chain/items/\(itemId)/checkpoints", body: body)
    }

    func transferOwnership(itemId: String, to: String) async throws -> TransactionResult {
        try await api.post("/supply-chain/items/\(itemId)/transfer", body: ["to": to])
    }
}
