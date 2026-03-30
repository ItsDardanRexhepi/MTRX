//
//  TransactionModel.swift
//  MTRX
//
//  SwiftData transaction history model for blockchain transaction persistence.
//

import Foundation
import SwiftData

// MARK: - Transaction Status

/// Lifecycle states for a blockchain transaction.
enum TransactionStatus: String, Codable, CaseIterable {
    case pending
    case submitted
    case confirmed
    case failed
    case reverted
    case dropped
    case replaced

    /// Whether the transaction has reached a terminal state.
    var isTerminal: Bool {
        switch self {
        case .confirmed, .failed, .reverted, .dropped:
            return true
        case .pending, .submitted, .replaced:
            return false
        }
    }

    /// Human-readable display string.
    var displayName: String {
        switch self {
        case .pending:    return "Pending"
        case .submitted:  return "Submitted"
        case .confirmed:  return "Confirmed"
        case .failed:     return "Failed"
        case .reverted:   return "Reverted"
        case .dropped:    return "Dropped"
        case .replaced:   return "Replaced"
        }
    }
}

// MARK: - Transaction Direction

/// Indicates whether the user sent or received value.
enum TransactionDirection: String, Codable {
    case incoming
    case outgoing
    case selfTransfer
    case contractInteraction
}

// MARK: - TransactionRecord Model

@Model
final class TransactionRecord {
    // MARK: - Primary Properties

    @Attribute(.unique) var id: UUID
    var hash: String
    var from: String
    var to: String
    var value: String
    var gasUsed: String
    var gasPrice: String
    var status: String
    var timestamp: Date
    var chainId: Int
    var blockNumber: Int64
    var component: String

    // MARK: - Extended Properties

    var nonce: Int64
    var inputData: Data?
    var errorMessage: String?
    var confirmations: Int
    var direction: String
    var tokenSymbol: String?
    var tokenAmount: String?
    var feeInWei: String?

    // MARK: - Relationship

    var user: UserProfile?

    // MARK: - Computed Properties

    var transactionStatus: TransactionStatus {
        get { TransactionStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    var transactionDirection: TransactionDirection {
        get { TransactionDirection(rawValue: direction) ?? .outgoing }
        set { direction = newValue.rawValue }
    }

    /// Returns the value as a Decimal for arithmetic operations.
    var decimalValue: Decimal {
        Decimal(string: value) ?? .zero
    }

    /// Whether the transaction is still in-flight.
    var isPending: Bool {
        transactionStatus == .pending || transactionStatus == .submitted
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        hash: String,
        from: String,
        to: String,
        value: String,
        gasUsed: String = "0",
        gasPrice: String = "0",
        status: TransactionStatus = .pending,
        timestamp: Date = Date(),
        chainId: Int = 1,
        blockNumber: Int64 = 0,
        component: String,
        nonce: Int64 = 0,
        direction: TransactionDirection = .outgoing
    ) {
        self.id = id
        self.hash = hash
        self.from = from
        self.to = to
        self.value = value
        self.gasUsed = gasUsed
        self.gasPrice = gasPrice
        self.status = status.rawValue
        self.timestamp = timestamp
        self.chainId = chainId
        self.blockNumber = blockNumber
        self.component = component
        self.nonce = nonce
        self.inputData = nil
        self.errorMessage = nil
        self.confirmations = 0
        self.direction = direction.rawValue
        self.tokenSymbol = nil
        self.tokenAmount = nil
        self.feeInWei = nil
    }

    // MARK: - Methods

    /// Updates the confirmation count and promotes status if threshold met.
    func updateConfirmations(_ count: Int, requiredConfirmations: Int = 12) {
        confirmations = count
        if count >= requiredConfirmations && transactionStatus == .submitted {
            transactionStatus = .confirmed
        }
    }

    /// Marks the transaction as failed with an error message.
    func markFailed(error: String) {
        transactionStatus = .failed
        errorMessage = error
    }

    /// Calculates the total fee in Wei.
    func calculateFee() -> String {
        guard let gas = Decimal(string: gasUsed),
              let price = Decimal(string: gasPrice) else {
            return "0"
        }
        return "\(gas * price)"
    }
}

// MARK: - Fetch Descriptors

extension TransactionRecord {
    /// Fetch descriptor for pending transactions on a given chain.
    static func pendingTransactions(chainId: Int) -> FetchDescriptor<TransactionRecord> {
        let pending = TransactionStatus.pending.rawValue
        let submitted = TransactionStatus.submitted.rawValue
        let predicate = #Predicate<TransactionRecord> { record in
            record.chainId == chainId &&
            (record.status == pending || record.status == submitted)
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        return descriptor
    }

    /// Fetch descriptor for transaction history by component.
    static func history(forComponent component: String, limit: Int = 50) -> FetchDescriptor<TransactionRecord> {
        let predicate = #Predicate<TransactionRecord> { record in
            record.component == component
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        descriptor.fetchLimit = limit
        return descriptor
    }
}
