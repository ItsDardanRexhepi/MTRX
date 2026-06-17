import Foundation

// MARK: - Models

struct PortfolioSummary: Codable {
    let totalValueUSD: Double
    let change24hPercent: Double
    let change7dPercent: Double
    let tokens: [PortfolioToken]
    let nftCount: Int
    let defiValue: Double
    let stakingValue: Double
}

struct PortfolioToken: Codable, Identifiable {
    let id: UUID
    let name: String
    let symbol: String
    let balance: Double
    let usdValue: Double
    let change24hPercent: Double
}

struct PortfolioTransaction: Codable, Identifiable {
    var id: String { txHash }
    let txHash: String
    let type: String
    let token: String?
    let amount: Double?
    let usdValue: Double?
    let timestamp: Date
    let status: String
    let from: String?
    let to: String?
    let gasUSD: Double?
}

struct SvcPortfolioSnapshot: Codable {
    let date: Date
    let totalValueUSD: Double
}

// MARK: - Service

@MainActor
final class PortfolioService {

    static let shared = PortfolioService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getPortfolioSummary(address: String) async throws -> PortfolioSummary {
        try await api.get(path: "/portfolio/\(address)/summary")
    }

    func getTransactionHistory(address: String, page: Int) async throws -> [PortfolioTransaction] {
        try await api.get(path: "/portfolio/\(address)/transactions", queryItems: [
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    func getPerformanceHistory(address: String, days: Int) async throws -> [SvcPortfolioSnapshot] {
        try await api.get(path: "/portfolio/\(address)/performance", queryItems: [
            URLQueryItem(name: "days", value: String(days))
        ])
    }
}
