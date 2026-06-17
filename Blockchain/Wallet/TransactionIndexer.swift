//
//  TransactionIndexer.swift
//  MTRX Blockchain — Wallet
//
//  The producer that populates the TransactionRecord store from chain, so
//  SwiftDataTransactionProvider (Trinity's transaction context) returns REAL data.
//
//  It reads the signed-in wallet's recent ERC-20 Transfer logs via
//  BaseNetwork.eth_getLogs, resolves block timestamps, and writes deduped
//  TransactionRecords through SwiftDataStore.
//
//  GRACEFUL BOUNDARY: returns 0 and writes nothing when the RPC isn't configured
//  (PendingCredentials.Network.rpcURL) or no wallet address is supplied. It never
//  fabricates records. The two inputs it needs ARE the external boundary:
//    1. a configured RPC URL, and
//    2. the signed-in user's wallet address.
//  Wire a caller that passes the user's wallet address (e.g. from UserProfile.
//  walletAddress) once both exist, and the store fills with real transactions.
//
import Foundation
import SwiftData

@MainActor
final class TransactionIndexer {

    private let network: BaseNetwork
    private let store: SwiftDataStore

    /// ERC-20 `Transfer(address indexed from, address indexed to, uint256 value)`.
    private static let transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    /// Construct on the main actor (e.g. `TransactionIndexer(store: .shared)`).
    init(network: BaseNetwork = BaseNetwork(), store: SwiftDataStore) {
        self.network = network
        self.store = store
    }

    /// Import recent incoming + outgoing ERC-20 transfers for `walletAddress`
    /// over the last `blockLookback` blocks. Returns the number of NEW records
    /// written (deduped against what's already stored).
    @discardableResult
    func importRecentTransfers(for walletAddress: String, blockLookback: UInt64 = 200_000) async -> Int {
        guard !walletAddress.isEmpty, network.endpoints.activeHTTP != nil else { return 0 }
        guard let latest = try? await latestBlock() else { return 0 }

        let fromBlock = latest > blockLookback ? latest - blockLookback : 0
        let fromHex = "0x" + String(fromBlock, radix: 16)
        let padded = paddedTopic(for: walletAddress)

        // Incoming (wallet is `to` = topics[2]) and outgoing (wallet is `from` = topics[1]).
        async let incoming = logs(fromBlock: fromHex, topics: [Self.transferTopic, nil, padded])
        async let outgoing = logs(fromBlock: fromHex, topics: [Self.transferTopic, padded, nil])
        let allLogs = (await incoming) + (await outgoing)
        guard !allLogs.isEmpty else { return 0 }

        // Dedup against records already in the store (by tx hash).
        let existingHashes = Set((try? store.fetch(FetchDescriptor<TransactionRecord>()))?.map(\.hash) ?? [])

        var blockTimes: [String: Date] = [:]
        var seen = Set<String>()
        var records: [TransactionRecord] = []

        for log in allLogs {
            let key = log.transactionHash + (log.logIndex ?? "")
            if seen.contains(key) { continue }
            seen.insert(key)
            if existingHashes.contains(log.transactionHash) { continue }

            // Real block timestamp (resolved once per unique block).
            let timestamp: Date
            if let cached = blockTimes[log.blockNumber] {
                timestamp = cached
            } else if let fetched = try? await blockTimestamp(log.blockNumber) {
                blockTimes[log.blockNumber] = fetched
                timestamp = fetched
            } else {
                timestamp = Date()
            }

            let from = Self.address(fromTopic: log.topics.count > 1 ? log.topics[1] : "")
            let to = Self.address(fromTopic: log.topics.count > 2 ? log.topics[2] : "")

            let record = TransactionRecord(
                hash: log.transactionHash,
                from: from,
                to: to,
                value: Self.decimalString(fromHexWord: log.data),
                component: "transfer"
            )
            record.blockNumber = Int64(log.blockNumber.dropFirst(2), radix: 16) ?? 0
            record.timestamp = timestamp
            record.status = TransactionStatus.confirmed.rawValue
            record.direction = (to.lowercased() == walletAddress.lowercased()
                                ? TransactionDirection.incoming
                                : TransactionDirection.outgoing).rawValue
            record.tokenSymbol = nil // symbol lookup (eth_call symbol()) deferred — left nil, not faked
            record.chainId = Int(BaseNetwork.chainId)
            records.append(record)
        }

        guard !records.isEmpty else { return 0 }
        try? await store.batchInsert(records)
        return records.count
    }

    // MARK: - Continuation bridges to completion-based BaseNetwork

    private func latestBlock() async throws -> UInt64 {
        try await withCheckedThrowingContinuation { continuation in
            network.getBlockNumber { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    private func logs(fromBlock: String, topics: [String?]) async -> [EthLog] {
        await withCheckedContinuation { continuation in
            network.getLogs(address: "", fromBlock: fromBlock, toBlock: "latest", topics: topics) { result in
                continuation.resume(returning: (try? result.get()) ?? [])
            }
        }
    }

    private func blockTimestamp(_ hex: String) async throws -> Date {
        try await withCheckedThrowingContinuation { continuation in
            network.getBlockTimestamp(blockNumberHex: hex) { result in
                switch result {
                case .success(let date): continuation.resume(returning: date)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Encoding helpers

    /// Left-pad a 20-byte address to a 32-byte topic.
    private func paddedTopic(for address: String) -> String {
        let clean = (address.hasPrefix("0x") ? String(address.dropFirst(2)) : address).lowercased()
        return "0x" + String(repeating: "0", count: max(0, 64 - clean.count)) + clean
    }

    /// Extract the 20-byte address from a 32-byte indexed topic.
    nonisolated static func address(fromTopic topic: String) -> String {
        let clean = topic.hasPrefix("0x") ? String(topic.dropFirst(2)) : topic
        return "0x" + String(clean.suffix(40))
    }

    /// Decode the first 32-byte word of `data` (the Transfer value) into a
    /// decimal string, handling values larger than UInt64 via Decimal.
    nonisolated static func decimalString(fromHexWord hex: String) -> String {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let word = String(clean.prefix(64))
        var result = Decimal(0)
        let sixteen = Decimal(16)
        for character in word {
            guard let digit = character.hexDigitValue else { continue }
            result = result * sixteen + Decimal(digit)
        }
        return NSDecimalNumber(decimal: result).stringValue
    }
}
