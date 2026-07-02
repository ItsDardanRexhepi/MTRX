// SwapService.swift
// MTRX — Token swap operations via 0pnMatrx gateway

import Foundation

// MARK: - Models

struct SwapQuote: Codable, Identifiable {
    let id: UUID
    let fromToken: String
    let toToken: String
    let fromAmount: String
    let toAmount: String
    let priceImpact: Double
    let route: String
    let gasEstimateUSD: Double
    let validUntil: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.fromToken = try container.decode(String.self, forKey: .fromToken)
        self.toToken = try container.decode(String.self, forKey: .toToken)
        self.fromAmount = try container.decode(String.self, forKey: .fromAmount)
        self.toAmount = try container.decode(String.self, forKey: .toAmount)
        self.priceImpact = (try? container.decode(Double.self, forKey: .priceImpact)) ?? 0
        self.route = (try? container.decode(String.self, forKey: .route)) ?? "auto"
        self.gasEstimateUSD = (try? container.decode(Double.self, forKey: .gasEstimateUSD)) ?? 0
        self.validUntil = (try? container.decode(Date.self, forKey: .validUntil)) ?? Date().addingTimeInterval(60)
    }

    private enum CodingKeys: String, CodingKey {
        case id, fromToken, toToken, fromAmount, toAmount, priceImpact, route, gasEstimateUSD, validUntil
    }
}

// MARK: - SwapService

@MainActor
final class SwapService {
    static let shared = SwapService()
    private let client = MTRXAPIClient.shared

    private init() {}

    // MARK: - Quote

    func getQuote(fromToken: String, toToken: String, amount: String) async throws -> SwapQuote {
        // Gateway contract: POST /api/v1/defi/swap/route {token_in, token_out,
        // amount}; result arrives in the {status,data} envelope. A shape
        // mismatch throws and the UI keeps its honest fallback.
        struct QuoteRequest: Encodable {
            let tokenIn: String
            let tokenOut: String
            let amount: String
        }
        let quote: SwapQuote = try await client.postEnveloped(
            path: "/api/v1/defi/swap/route",
            body: QuoteRequest(tokenIn: fromToken, tokenOut: toToken, amount: amount)
        )
        return quote
    }

    // MARK: - Execute Swap (post-deploy wiring unit)

    /// Gateway contract: POST /api/v1/defi/swap/execute {wallet, route_id} —
    /// route_id is the SERVER-issued id from the route response, never a
    /// client-invented UUID. Execution stays unreachable from the UI until the
    /// post-deploy wiring unit lands (Confirm Swap shows an honest notice).
    func executeSwap(routeId: String) async throws -> SvcTransactionResult {
        struct SwapExecuteRequest: Encodable {
            let wallet: String
            let routeId: String
        }
        let wallet = await client.walletPathIdentity()
        return try await client.postEnveloped(
            path: "/api/v1/defi/swap/execute",
            body: SwapExecuteRequest(wallet: wallet, routeId: routeId)
        )
    }
}
