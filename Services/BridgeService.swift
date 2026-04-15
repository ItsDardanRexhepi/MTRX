import Foundation

// MARK: - Models

struct BridgeRoute: Codable, Identifiable {
    var id: String { routeId }
    let routeId: String
    let fromChain: String
    let toChain: String
    let token: String
    let amount: String
    let estimatedTime: String
    let fee: Double
    let provider: String
}

struct BridgeTransaction: Codable, Identifiable {
    var id: String { txId }
    let txId: String
    let fromChain: String
    let toChain: String
    let token: String
    let amount: String
    let status: BridgeStatus
    let sourceTxHash: String?
    let destinationTxHash: String?
    let createdAt: Date
}

enum BridgeStatus: String, Codable {
    case pending
    case confirming
    case arrived
    case failed
}

// MARK: - Service

@MainActor
final class BridgeService {

    static let shared = BridgeService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getBridgeRoutes(fromChain: String, toChain: String, token: String, amount: String) async throws -> [BridgeRoute] {
        try await api.get("/bridge/routes", queryItems: [
            URLQueryItem(name: "fromChain", value: fromChain),
            URLQueryItem(name: "toChain", value: toChain),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "amount", value: amount)
        ])
    }

    func executeBridge(route: BridgeRoute) async throws -> BridgeTransaction {
        try await api.post("/bridge/execute", body: route)
    }

    func getBridgeStatus(txId: String) async throws -> BridgeTransaction {
        try await api.get("/bridge/status/\(txId)")
    }
}
