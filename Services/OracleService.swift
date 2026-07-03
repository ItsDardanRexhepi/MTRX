import Foundation

// MARK: - Models

struct OracleFeed: Codable, Identifiable {
    var id: String { feedId }
    let feedId: String
    let name: String
    let pair: String
    let currentValue: Double
    let lastUpdated: Date
    let decimals: Int
    let contractAddress: String
}

struct OracleDataPoint: Codable {
    let timestamp: Date
    let value: Double
    let roundId: String?
}

// MARK: - Service

@MainActor
final class OracleService {

    static let shared = OracleService()
    private let api = MTRXAPIClient.shared

    private init() {}

    // P2 missing-routes: the gateway exposes only /api/v1/oracle/price/{pair}
    // today — the feed catalog + subscription routes below don't exist yet
    // (see LOOP_P2_MISSING_ROUTES.md). Paths are namespaced correctly so they
    // light up when P2 registers them; until then they 404 and the view falls
    // back to demo data (no fabricated feeds).

    func getAvailableFeeds() async throws -> [OracleFeed] {
        try await api.get(path: "/api/v1/oracle/feeds")
    }

    func getUserFeeds(address: String) async throws -> [OracleFeed] {
        try await api.get(path: "/api/v1/oracle/feeds", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func subscribeFeed(feedId: String) async throws {
        let _: SvcTransactionResult = try await api.post(path: "/api/v1/oracle/feeds/\(feedId)/subscribe", body: nil as String?)
    }

    func unsubscribeFeed(feedId: String) async throws {
        let _: SvcTransactionResult = try await api.post(path: "/api/v1/oracle/feeds/\(feedId)/unsubscribe", body: nil as String?)
    }

    func getFeedHistory(feedId: String, days: Int) async throws -> [OracleDataPoint] {
        try await api.get(path: "/api/v1/oracle/feeds/\(feedId)/history", queryItems: [
            URLQueryItem(name: "days", value: String(days))
        ])
    }
}
