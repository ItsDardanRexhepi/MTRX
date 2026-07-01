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

    // P2-10: remapped off the colliding /bridge/* namespace (the mobile bridge is
    // /bridge/v1/*) onto the gateway's real cross-chain DeFi routes under /api/v1.
    func getBridgeRoutes(fromChain: String, toChain: String, token: String, amount: String) async throws -> [BridgeRoute] {
        try await api.post(path: "/api/v1/defi/bridge/quote", body: [
            "from_chain": fromChain,
            "to_chain": toChain,
            "token": token,
            "amount": amount,
        ])
    }

    func executeBridge(route: BridgeRoute) async throws -> SvcBridgeTransaction {
        try await api.post(path: "/api/v1/defi/bridge/execute", body: route)
    }

    func getBridgeStatus(txId: String) async throws -> SvcBridgeTransaction {
        // No dedicated bridge-status route exists server-side; poll the generic
        // transaction lookup the app uses elsewhere rather than a fabricated status.
        try await api.get(path: "/api/v1/portfolio/history/\(txId)")
    }
}
