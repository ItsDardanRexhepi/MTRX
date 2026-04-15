// YieldService.swift
// MTRX — Yield strategy operations via 0pnMatrx gateway

import Foundation

// MARK: - Models

struct YieldOpportunity: Codable, Identifiable {
    var id: String { strategyId }
    let strategyId: String
    let name: String
    let token: String
    let apy: Double
    let riskLevel: String
    let tvl: Double
    let protocolName: String
    let isAutoCompound: Bool

    private enum CodingKeys: String, CodingKey {
        case strategyId, name, token, apy, riskLevel, tvl, protocolName, isAutoCompound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.strategyId = try container.decode(String.self, forKey: .strategyId)
        self.name = try container.decode(String.self, forKey: .name)
        self.token = try container.decode(String.self, forKey: .token)
        self.apy = (try? container.decode(Double.self, forKey: .apy)) ?? 0
        self.riskLevel = (try? container.decode(String.self, forKey: .riskLevel)) ?? "medium"
        self.tvl = (try? container.decode(Double.self, forKey: .tvl)) ?? 0
        self.protocolName = (try? container.decode(String.self, forKey: .protocolName)) ?? ""
        self.isAutoCompound = (try? container.decode(Bool.self, forKey: .isAutoCompound)) ?? false
    }
}

// MARK: - YieldService

@MainActor
final class YieldService {
    static let shared = YieldService()
    private let client = MTRXAPIClient.shared

    private init() {}

    // MARK: - Yield Opportunities

    func getYieldOpportunities() async throws -> [YieldOpportunity] {
        let opportunities: [YieldOpportunity] = try await client.get(
            path: "/api/v1/defi/yield/opportunities"
        )
        return opportunities
    }

    // MARK: - Deposit to Strategy

    func depositToStrategy(strategyId: String, amount: String, token: String) async throws -> TransactionResult {
        struct DepositRequest: Encodable {
            let strategyId: String
            let amount: String
            let token: String
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/yield/deposit",
            body: DepositRequest(strategyId: strategyId, amount: amount, token: token)
        )
        return result
    }

    // MARK: - Withdraw from Strategy

    func withdrawFromStrategy(strategyId: String, amount: String) async throws -> TransactionResult {
        struct WithdrawRequest: Encodable {
            let strategyId: String
            let amount: String
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/yield/withdraw",
            body: WithdrawRequest(strategyId: strategyId, amount: amount)
        )
        return result
    }
}
