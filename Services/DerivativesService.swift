import Foundation

// MARK: - Models

enum PositionSide: String, Codable {
    case long
    case short
}

struct PerpMarket: Codable, Identifiable {
    var id: String { marketId }
    let marketId: String
    let name: String
    let indexPrice: Double
    let markPrice: Double
    let fundingRate: Double
    let openInterest: Double
}

struct PerpPosition: Codable, Identifiable {
    var id: String { positionId }
    let positionId: String
    let market: String
    let side: PositionSide
    let size: Double
    let entryPrice: Double
    let markPrice: Double
    let unrealizedPnl: Double
    let liquidationPrice: Double
    let leverage: Int
}

// MARK: - Service

@MainActor
final class DerivativesService {

    static let shared = DerivativesService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getMarkets() async throws -> [PerpMarket] {
        try await api.get(path: "/derivatives/markets", queryItems: nil)
    }

    func openPosition(market: String, side: PositionSide, size: String, leverage: Int, tp: String?, sl: String?) async throws -> SvcTransactionResult {
        var body: [String: String] = [
            "market": market,
            "side": side.rawValue,
            "size": size,
            "leverage": String(leverage)
        ]
        if let tp { body["takeProfit"] = tp }
        if let sl { body["stopLoss"] = sl }
        return try await api.post(path: "/derivatives/positions", body: body)
    }

    func closePosition(positionId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/derivatives/positions/\(positionId)/close", body: nil as String?)
    }

    func getUserPositions(address: String) async throws -> [PerpPosition] {
        try await api.get(path: "/derivatives/positions", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }
}
