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

struct SvcBridgeTransaction: Codable, Identifiable {
    var id: String { txId }
    let txId: String
    let fromChain: String
    let toChain: String
    let token: String
    let amount: String
    let status: SvcBridgeStatus
    let sourceTxHash: String?
    let destinationTxHash: String?
    let createdAt: Date
}

enum SvcBridgeStatus: String, Codable {
    case pending
    case confirming
    case arrived
    case failed
}

// MARK: - Service

@MainActor
final class BridgeGatewayService {

    static let shared = BridgeGatewayService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getBridgeRoutes(fromChain: String, toChain: String, token: String, amount: String) async throws -> [BridgeRoute] {
        try await api.get(path: "/bridge/routes", queryItems: [
            URLQueryItem(name: "fromChain", value: fromChain),
            URLQueryItem(name: "toChain", value: toChain),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "amount", value: amount)
        ])
    }

    func executeBridge(route: BridgeRoute) async throws -> SvcBridgeTransaction {
        try await api.post(path: "/bridge/execute", body: route)
    }

    func getBridgeStatus(txId: String) async throws -> SvcBridgeTransaction {
        try await api.get(path: "/bridge/status/\(txId)")
    }
}
