// LendingService.swift
// MTRX — DeFi lending operations via 0pnMatrx gateway

import Foundation

// MARK: - Models

struct LendingMarket: Codable, Identifiable {
    let id: UUID
    let token: String
    let symbol: String
    let supplyAPY: Double
    let borrowAPR: Double
    let totalSupply: Double
    let totalBorrow: Double
    let utilizationRate: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.token = try container.decode(String.self, forKey: .token)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.supplyAPY = (try? container.decode(Double.self, forKey: .supplyAPY)) ?? 0
        self.borrowAPR = (try? container.decode(Double.self, forKey: .borrowAPR)) ?? 0
        self.totalSupply = (try? container.decode(Double.self, forKey: .totalSupply)) ?? 0
        self.totalBorrow = (try? container.decode(Double.self, forKey: .totalBorrow)) ?? 0
        self.utilizationRate = (try? container.decode(Double.self, forKey: .utilizationRate)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, token, symbol, supplyAPY, borrowAPR, totalSupply, totalBorrow, utilizationRate
    }
}

struct LendingPositions: Codable {
    let supplied: [SupplyPosition]
    let borrowed: [BorrowPosition]
    let healthFactor: Double
    let netAPY: Double
}

struct SupplyPosition: Codable, Identifiable {
    let id: UUID
    let token: String
    let symbol: String
    let amount: Double
    let valueUSD: Double
    let apy: Double
    let earnedInterest: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.token = try container.decode(String.self, forKey: .token)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.amount = try container.decode(Double.self, forKey: .amount)
        self.valueUSD = (try? container.decode(Double.self, forKey: .valueUSD)) ?? 0
        self.apy = (try? container.decode(Double.self, forKey: .apy)) ?? 0
        self.earnedInterest = (try? container.decode(Double.self, forKey: .earnedInterest)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, token, symbol, amount, valueUSD, apy, earnedInterest
    }
}

struct BorrowPosition: Codable, Identifiable {
    let id: UUID
    let token: String
    let symbol: String
    let amount: Double
    let valueUSD: Double
    let apr: Double
    let accruedInterest: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.token = try container.decode(String.self, forKey: .token)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.amount = try container.decode(Double.self, forKey: .amount)
        self.valueUSD = (try? container.decode(Double.self, forKey: .valueUSD)) ?? 0
        self.apr = (try? container.decode(Double.self, forKey: .apr)) ?? 0
        self.accruedInterest = (try? container.decode(Double.self, forKey: .accruedInterest)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, token, symbol, amount, valueUSD, apr, accruedInterest
    }
}

// MARK: - LendingService

@MainActor
final class LendingService {
    static let shared = LendingService()
    private let client = MTRXAPIClient.shared

    private init() {}

    // MARK: - Markets

    func getLendingMarkets() async throws -> [LendingMarket] {
        let markets: [LendingMarket] = try await client.get(
            path: "/api/v1/defi/lending/markets"
        )
        return markets
    }

    // MARK: - User Positions

    func getUserPositions(address: String) async throws -> LendingPositions {
        let positions: LendingPositions = try await client.get(
            path: "/api/v1/defi/lending/positions",
            queryItems: [URLQueryItem(name: "address", value: address)]
        )
        return positions
    }

    // MARK: - Supply

    func supply(token: String, amount: String) async throws -> TransactionResult {
        struct SupplyRequest: Encodable {
            let token: String
            let amount: String
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/lending/supply",
            body: SupplyRequest(token: token, amount: amount)
        )
        return result
    }

    // MARK: - Withdraw

    func withdraw(token: String, amount: String) async throws -> TransactionResult {
        struct WithdrawRequest: Encodable {
            let token: String
            let amount: String
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/lending/withdraw",
            body: WithdrawRequest(token: token, amount: amount)
        )
        return result
    }

    // MARK: - Borrow

    func borrow(token: String, amount: String) async throws -> TransactionResult {
        struct BorrowRequest: Encodable {
            let token: String
            let amount: String
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/lending/borrow",
            body: BorrowRequest(token: token, amount: amount)
        )
        return result
    }

    // MARK: - Repay

    func repay(token: String, amount: String) async throws -> TransactionResult {
        struct RepayRequest: Encodable {
            let token: String
            let amount: String
        }
        let result: TransactionResult = try await client.post(
            path: "/api/v1/defi/lending/repay",
            body: RepayRequest(token: token, amount: amount)
        )
        return result
    }
}
