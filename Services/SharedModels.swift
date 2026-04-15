// SharedModels.swift
// MTRX — Shared Codable models used across multiple service files.

import Foundation

// MARK: - TransactionResult

/// Represents the result of an on-chain transaction returned by the gateway.
struct TransactionResult: Codable, Identifiable {
    let id: String
    let txHash: String
    let status: String
    let timestamp: Date

    init(id: String? = nil, txHash: String, status: String, timestamp: Date) {
        self.id = id ?? txHash
        self.txHash = txHash
        self.status = status
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.txHash = try container.decode(String.self, forKey: .txHash)
        self.status = try container.decode(String.self, forKey: .status)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? txHash
    }

    private enum CodingKeys: String, CodingKey {
        case id, txHash, status, timestamp
    }
}
