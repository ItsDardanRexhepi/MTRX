import Foundation

// MARK: - Models

struct StablecoinBalance: Codable, Identifiable {
    let id: UUID
    let symbol: String
    let balance: Double
    let usdValue: Double
    let yieldAPY: Double?
    let isDeposited: Bool
}

struct StablecoinPegStatus: Codable, Identifiable {
    let id: UUID
    let symbol: String
    let currentPrice: Double
    let pegDeviation: Double
    let status: String
}

// MARK: - Service

@MainActor
final class StablecoinService {

    static let shared = StablecoinService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getStablecoinBalances(address: String) async throws -> [StablecoinBalance] {
        try await api.get(path: "/stablecoins/balances", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func convertStablecoin(from: String, to: String, amount: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/stablecoins/convert", body: [
            "from": from,
            "to": to,
            "amount": amount
        ])
    }

    func mintDAI(collateralToken: String, collateralAmount: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/stablecoins/mint-dai", body: [
            "collateralToken": collateralToken,
            "collateralAmount": collateralAmount
        ])
    }

    func getPegStatus() async throws -> [StablecoinPegStatus] {
        try await api.get(path: "/stablecoins/peg-status")
    }
}
