// TransactionIntent.swift
// MTRX Apple Integration — AppIntents
// Execute blockchain transactions via Shortcuts with confirmation dialog

import AppIntents

// MARK: - Execute Transaction Intent

struct ExecuteTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Execute Transaction"
    static var description = IntentDescription("Execute a blockchain transaction with confirmation")

    @Parameter(title: "Transaction Type", default: .transfer)
    var transactionType: TransactionType

    @Parameter(title: "Recipient Address")
    var recipient: String

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Token", default: "ETH")
    var token: String

    @Parameter(title: "Network", default: .ethereum)
    var network: BlockchainNetwork

    static var parameterSummary: some ParameterSummary {
        Summary("Execute \(\.$transactionType): \(\.$amount) \(\.$token) to \(\.$recipient) on \(\.$network)")
    }

    // MARK: - Confirmation Dialog

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Build transaction estimate
        let estimate = try await TransactionEstimator.shared.estimate(
            type: transactionType,
            to: recipient,
            amount: Decimal(amount),
            token: token,
            network: network
        )

        // Request confirmation with full transaction details
        try await requestConfirmation(
            result: .result(
                value: estimate.summary,
                dialog: IntentDialog(stringLiteral: """
                    Confirm transaction:
                    Send \(amount) \(token) to \(shortenAddress(recipient))
                    Network: \(network.rawValue)
                    Estimated Gas: \(estimate.gasEstimateUSD)
                    Total Cost: \(estimate.totalCostUSD)
                    """)
            )
        )

        // Execute after confirmation
        let txHash = try await TransactionExecutor.shared.execute(
            type: transactionType,
            to: recipient,
            amount: Decimal(amount),
            token: token,
            network: network
        )

        return .result(value: "Transaction submitted: \(txHash)")
    }

    private func shortenAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

// MARK: - Approve Token Intent

struct ApproveTokenIntent: AppIntent {
    static var title: LocalizedStringResource = "Approve Token Spending"
    static var description = IntentDescription("Approve a smart contract to spend tokens on your behalf")

    @Parameter(title: "Token")
    var token: String

    @Parameter(title: "Spender Contract")
    var spenderAddress: String

    @Parameter(title: "Amount (0 = unlimited)")
    var amount: Double

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let displayAmount = amount == 0 ? "unlimited" : String(amount)

        try await requestConfirmation(
            result: .result(
                value: "Approve \(displayAmount) \(token)",
                dialog: IntentDialog(stringLiteral: "Approve \(displayAmount) \(token) for contract \(spenderAddress.prefix(10))...?")
            )
        )

        let txHash = try await TransactionExecutor.shared.approve(
            token: token,
            spender: spenderAddress,
            amount: amount == 0 ? nil : Decimal(amount)
        )

        return .result(value: "Approval submitted: \(txHash)")
    }
}

// MARK: - Transaction History Intent

struct TransactionHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Transaction History"
    static var description = IntentDescription("View recent transaction history")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Count", default: 5)
    var count: Int

    @Parameter(title: "Network")
    var network: BlockchainNetwork?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let transactions = try await TransactionHistoryStore.shared.recent(
            count: count,
            network: network
        )

        let summary = transactions.map { tx in
            "\(tx.type.rawValue): \(tx.amount) \(tx.token) → \(tx.recipient.prefix(8))... (\(tx.status))"
        }.joined(separator: "\n")

        return .result(value: summary.isEmpty ? "No recent transactions" : summary)
    }
}

// MARK: - Transaction Type Enum

enum TransactionType: String, AppEnum {
    case transfer = "Transfer"
    case swap = "Swap"
    case stake = "Stake"
    case unstake = "Unstake"
    case contractCall = "Contract Call"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Transaction Type"
    static var caseDisplayRepresentations: [TransactionType: DisplayRepresentation] = [
        .transfer: "Transfer",
        .swap: "Swap",
        .stake: "Stake",
        .unstake: "Unstake",
        .contractCall: "Contract Call"
    ]
}

// MARK: - Transaction Estimate

struct TransactionEstimate {
    let gasEstimateUSD: String
    let totalCostUSD: String
    let summary: String
    let estimatedTime: TimeInterval
}

// MARK: - Transaction Record

struct IntentTransactionRecord {
    let type: TransactionType
    let amount: String
    let token: String
    let recipient: String
    let status: String
    let timestamp: Date
    let txHash: String
}

// MARK: - Service Stubs

final class TransactionEstimator {
    static let shared = TransactionEstimator()

    func estimate(type: TransactionType, to: String, amount: Decimal, token: String, network: BlockchainNetwork) async throws -> TransactionEstimate {
        // Don't fabricate a "$0.00" gas/total estimate for the confirmation dialog — that tells
        // the user the transaction is free. No on-chain network is configured, so fail honestly
        // HERE, before any confirmation is shown, matching TransactionExecutor.execute below.
        throw NSError(domain: "MTRX.Intent", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "On-chain transactions aren't available in this build yet — configure a network first."])
    }
}

final class TransactionExecutor {
    static let shared = TransactionExecutor()

    func execute(type: TransactionType, to: String, amount: Decimal, token: String, network: BlockchainNetwork) async throws -> String {
        // No on-chain network is configured in this build, so we do NOT fabricate
        // a confirmed transaction hash. Fail honestly — Siri reports it couldn't
        // complete rather than claiming a send that never happened.
        throw NSError(domain: "MTRX.Intent", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "On-chain transactions aren't available in this build yet — configure a network first."])
    }

    func approve(token: String, spender: String, amount: Decimal?) async throws -> String {
        throw NSError(domain: "MTRX.Intent", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "On-chain approvals aren't available in this build yet — configure a network first."])
    }
}

final class TransactionHistoryStore {
    static let shared = TransactionHistoryStore()

    func recent(count: Int, network: BlockchainNetwork?) async throws -> [IntentTransactionRecord] {
        return []
    }
}
