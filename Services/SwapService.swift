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
        struct QuoteRequest: Encodable {
            let fromToken: String
            let toToken: String
            let amount: String
        }
        let quote: SwapQuote = try await client.post(
            path: "/api/v1/swap/quote",
            body: QuoteRequest(fromToken: fromToken, toToken: toToken, amount: amount)
        )
        return quote
    }

    // MARK: - Execute Swap

    func executeSwap(quote: SwapQuote) async throws -> SvcTransactionResult {
        struct SwapExecuteRequest: Encodable {
            let quoteId: String
            let fromToken: String
            let toToken: String
            let fromAmount: String
            let toAmount: String
            let route: String
        }
        let result: SvcTransactionResult = try await client.post(
            path: "/api/v1/swap/execute",
            body: SwapExecuteRequest(
                quoteId: quote.id.uuidString,
                fromToken: quote.fromToken,
                toToken: quote.toToken,
                fromAmount: quote.fromAmount,
                toAmount: quote.toAmount,
                route: quote.route
            )
        )
        return result
    }
}
