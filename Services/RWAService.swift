import Foundation

// MARK: - Models

struct RWAAssetListing: Codable, Identifiable {
    var id: String { assetId }
    let assetId: String
    let name: String
    let category: String
    let apy: Double
    let minimumInvestment: Double
    let liquidity: String
    let riskRating: String
    let totalValue: Double
}

struct RWAHolding: Codable, Identifiable {
    var id: String { holdingId }
    let holdingId: String
    let assetName: String
    let category: String
    let tokenBalance: Double
    let usdValue: Double
    let pendingYield: Double
}

// MARK: - Service

@MainActor
final class RWAService {

    static let shared = RWAService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getRWAAssets() async throws -> [RWAAssetListing] {
        try await api.get(path: "/rwa/assets", queryItems: nil)
    }

    func getUserHoldings(address: String) async throws -> [RWAHolding] {
        try await api.get(path: "/rwa/holdings", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func purchaseRWA(assetId: String, amount: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/rwa/assets/\(assetId)/purchase", body: ["amount": amount])
    }

    func claimYield(holdingId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/rwa/holdings/\(holdingId)/claim-yield", body: nil as String?)
    }
}
