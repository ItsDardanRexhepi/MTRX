import Foundation

// MARK: - Models

struct GameApp: Codable, Identifiable {
    var id: String { gameId }
    let gameId: String
    let name: String
    let iconURL: String?
    let assetCount: Int
    let playerCount: Int
}

struct GameAsset: Codable, Identifiable {
    var id: String { assetId }
    let assetId: String
    let gameId: String
    let name: String
    let imageURL: String?
    let rarity: String
    let listingPrice: Double?
}

struct Tournament: Codable, Identifiable {
    var id: String { tournamentId }
    let tournamentId: String
    let gameId: String?
    let name: String
    let prizePool: Double
    let entryFee: Double
    let players: Int
    let startTime: Date
    let status: String
}

struct ListingResult: Codable {
    let listingId: String
    let txHash: String
}

// MARK: - Service

@MainActor
final class GamingService {

    static let shared = GamingService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getConnectedGames(address: String) async throws -> [GameApp] {
        try await api.get("/gaming/games", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getGameAssets(gameId: String, address: String) async throws -> [GameAsset] {
        try await api.get("/gaming/games/\(gameId)/assets", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func buyGameAsset(assetId: String, price: String) async throws -> TransactionResult {
        try await api.post("/gaming/assets/\(assetId)/buy", body: ["price": price])
    }

    func sellGameAsset(assetId: String, price: String) async throws -> ListingResult {
        try await api.post("/gaming/assets/\(assetId)/sell", body: ["price": price])
    }

    func getTournaments() async throws -> [Tournament] {
        try await api.get("/gaming/tournaments", queryItems: nil)
    }

    func enterTournament(tournamentId: String) async throws -> TransactionResult {
        try await api.post("/gaming/tournaments/\(tournamentId)/enter", body: nil as String?)
    }
}
