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
        // Gateway route: GET /api/v1/portfolio/complete/{wallet} (full aggregate).
        try await api.get(path: "/api/v1/portfolio/complete/\(address)")
    }

    func getTransactionHistory(address: String, page: Int) async throws -> [PortfolioTransaction] {
        // Gateway route: GET /api/v1/portfolio/history/{wallet}.
        try await api.get(path: "/api/v1/portfolio/history/\(address)", queryItems: [
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    func getPerformanceHistory(address: String, days: Int) async throws -> [SvcPortfolioSnapshot] {
        // P2 missing-route: no /api/v1/portfolio/performance handler yet — see
        // LOOP_P2_MISSING_ROUTES.md. Namespaced correctly so it lights up once
        // the route lands; until then it 404s and the view falls back to demo.
        try await api.get(path: "/api/v1/portfolio/performance/\(address)", queryItems: [
            URLQueryItem(name: "days", value: String(days))
        ])
    }
}
