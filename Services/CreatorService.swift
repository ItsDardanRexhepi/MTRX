import Foundation

// MARK: - Models

struct CreatorTokenParams: Codable {
    let name: String
    let symbol: String
    let initialPrice: Double
    let bondingCurveType: String
}

struct CreatorToken: Codable, Identifiable {
    var id: String { tokenAddress }
    let tokenAddress: String
    let name: String
    let symbol: String
    let currentPrice: Double
    let holders: Int
    let volume24h: Double
    let creatorAddress: String
}

// MARK: - Service

@MainActor
final class CreatorService {

    static let shared = CreatorService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func launchCreatorToken(params: CreatorTokenParams) async throws -> CreatorToken {
        try await api.post("/creator/tokens", body: params)
    }

    func getCreatorTokens(address: String) async throws -> [CreatorToken] {
        try await api.get("/creator/tokens", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func buyCreatorToken(tokenAddress: String, amount: String) async throws -> TransactionResult {
        try await api.post("/creator/tokens/\(tokenAddress)/buy", body: ["amount": amount])
    }

    func sellCreatorToken(tokenAddress: String, amount: String) async throws -> TransactionResult {
        try await api.post("/creator/tokens/\(tokenAddress)/sell", body: ["amount": amount])
    }
}
