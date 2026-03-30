// AgenticPayments.swift
// MTRX Blockchain - Components - Agentic Payments
//
// AI agent payment channels: autonomous payment authorization, limits, audit

import Foundation

// MARK: - Protocols

protocol AgenticPaymentsDelegate: AnyObject {
    func payments(_ manager: AgenticPayments, didAuthorize paymentId: String, amount: UInt64)
    func payments(_ manager: AgenticPayments, didReject paymentId: String, reason: String)
    func payments(_ manager: AgenticPayments, limitWarning agentDID: String, usedPercent: Double)
}

// MARK: - Data Models

struct PaymentChannel {
    let channelId: String
    let agentDID: String
    let ownerAddress: String
    let depositAmount: UInt64
    let spentAmount: UInt64
    let dailyLimit: UInt64
    let perTransactionLimit: UInt64
    let allowedRecipients: [String]?
    let allowedTokens: [String]
    let expiresAt: Date?
    let isActive: Bool

    var remainingDeposit: UInt64 { depositAmount > spentAmount ? depositAmount - spentAmount : 0 }
}

struct AgentPayment {
    let paymentId: String
    let channelId: String
    let agentDID: String
    let recipient: String
    let amount: UInt64
    let token: String
    let purpose: String
    let status: PaymentStatus
    let authorizedAt: Date?
    let executedAt: Date?
    let transactionHash: String?
}

enum PaymentStatus: String {
    case pending, authorized, executed, rejected, failed, refunded
}

struct PaymentAuditEntry {
    let entryId: String
    let paymentId: String
    let agentDID: String
    let action: String
    let amount: UInt64
    let timestamp: Date
    let details: [String: String]
}

struct SpendingReport {
    let agentDID: String
    let period: String
    let totalSpent: UInt64
    let transactionCount: Int
    let averageAmount: Double
    let largestPayment: UInt64
    let topRecipients: [(String, UInt64)]
}

enum AgenticPaymentError: Error, LocalizedError {
    case channelNotFound
    case insufficientFunds
    case dailyLimitExceeded
    case perTransactionLimitExceeded
    case recipientNotAllowed
    case tokenNotAllowed
    case channelExpired
    case channelInactive
    case authorizationFailed
    case auditRequired

    var errorDescription: String? {
        switch self {
        case .channelNotFound: return "Payment channel not found."
        case .insufficientFunds: return "Insufficient funds in channel."
        case .dailyLimitExceeded: return "Daily spending limit exceeded."
        case .perTransactionLimitExceeded: return "Per-transaction limit exceeded."
        case .recipientNotAllowed: return "Recipient not in allowlist."
        case .tokenNotAllowed: return "Token not allowed for this channel."
        case .channelExpired: return "Payment channel has expired."
        case .channelInactive: return "Payment channel is inactive."
        case .authorizationFailed: return "Payment authorization failed."
        case .auditRequired: return "Audit review required before proceeding."
        }
    }
}

// MARK: - AgenticPayments

final class AgenticPayments {

    // MARK: - Properties

    weak var delegate: AgenticPaymentsDelegate?

    private let erc4337Manager: ERC4337Manager
    private let agentIdentity: AgentIdentity
    private var channels: [String: PaymentChannel] = [:]
    private var payments: [String: AgentPayment] = [:]
    private var auditLog: [PaymentAuditEntry] = []
    private var dailySpending: [String: UInt64] = [:] // agentDID -> today's total
    private let processingQueue = DispatchQueue(label: "com.mtrx.agentic.payments", qos: .userInitiated)

    // MARK: - Initialization

    init(erc4337Manager: ERC4337Manager, agentIdentity: AgentIdentity) {
        self.erc4337Manager = erc4337Manager
        self.agentIdentity = agentIdentity
    }

    // MARK: - Channel Management

    /// Open a new payment channel for an agent
    func openChannel(agentDID: String, ownerAddress: String, depositAmount: UInt64, dailyLimit: UInt64, perTransactionLimit: UInt64, allowedRecipients: [String]?, allowedTokens: [String], expiration: Date?, completion: @escaping (Result<PaymentChannel, AgenticPaymentError>) -> Void) {
        let channel = PaymentChannel(
            channelId: UUID().uuidString, agentDID: agentDID, ownerAddress: ownerAddress,
            depositAmount: depositAmount, spentAmount: 0, dailyLimit: dailyLimit,
            perTransactionLimit: perTransactionLimit, allowedRecipients: allowedRecipients,
            allowedTokens: allowedTokens, expiresAt: expiration, isActive: true
        )
        channels[channel.channelId] = channel
        // TODO: Deploy payment channel contract via ERC-4337
        completion(.success(channel))
    }

    /// Close a payment channel and refund remaining balance
    func closeChannel(channelId: String, completion: @escaping (Result<UInt64, AgenticPaymentError>) -> Void) {
        guard let channel = channels[channelId] else {
            completion(.failure(.channelNotFound))
            return
        }
        // TODO: Close on-chain channel, refund remaining to owner
        channels.removeValue(forKey: channelId)
        completion(.success(channel.remainingDeposit))
    }

    // MARK: - Payment Authorization

    /// Authorize a payment from an agent
    func authorizePayment(agentDID: String, recipient: String, amount: UInt64, token: String, purpose: String, completion: @escaping (Result<AgentPayment, AgenticPaymentError>) -> Void) {
        // Find active channel
        guard let channel = channels.values.first(where: { $0.agentDID == agentDID && $0.isActive }) else {
            completion(.failure(.channelNotFound))
            return
        }

        // Validate limits
        if let error = validatePayment(channel: channel, recipient: recipient, amount: amount, token: token) {
            delegate?.payments(self, didReject: "", reason: error.localizedDescription)
            completion(.failure(error))
            return
        }

        // Validate agent capability
        let capResult = agentIdentity.validateAction(agentDID: agentDID, scope: .payments, value: amount)
        switch capResult {
        case .failure: completion(.failure(.authorizationFailed)); return
        case .success: break
        }

        let payment = AgentPayment(
            paymentId: UUID().uuidString, channelId: channel.channelId,
            agentDID: agentDID, recipient: recipient, amount: amount,
            token: token, purpose: purpose, status: .authorized,
            authorizedAt: Date(), executedAt: nil, transactionHash: nil
        )
        payments[payment.paymentId] = payment
        logAuditEntry(paymentId: payment.paymentId, agentDID: agentDID, action: "authorized", amount: amount)

        delegate?.payments(self, didAuthorize: payment.paymentId, amount: amount)
        completion(.success(payment))
    }

    /// Execute an authorized payment
    func executePayment(paymentId: String, completion: @escaping (Result<AgentPayment, AgenticPaymentError>) -> Void) {
        guard var payment = payments[paymentId], payment.status == .authorized else {
            completion(.failure(.authorizationFailed))
            return
        }
        // TODO: Execute transfer via ERC-4337
        payment = AgentPayment(
            paymentId: payment.paymentId, channelId: payment.channelId,
            agentDID: payment.agentDID, recipient: payment.recipient,
            amount: payment.amount, token: payment.token, purpose: payment.purpose,
            status: .executed, authorizedAt: payment.authorizedAt,
            executedAt: Date(), transactionHash: nil
        )
        payments[paymentId] = payment
        dailySpending[payment.agentDID, default: 0] += payment.amount
        logAuditEntry(paymentId: paymentId, agentDID: payment.agentDID, action: "executed", amount: payment.amount)
        completion(.success(payment))
    }

    // MARK: - Audit

    func getAuditLog(agentDID: String) -> [PaymentAuditEntry] {
        return auditLog.filter { $0.agentDID == agentDID }
    }

    func getSpendingReport(agentDID: String) -> SpendingReport {
        let agentPayments = payments.values.filter { $0.agentDID == agentDID && $0.status == .executed }
        let total = agentPayments.reduce(UInt64(0)) { $0 + $1.amount }
        return SpendingReport(
            agentDID: agentDID, period: "daily", totalSpent: total,
            transactionCount: agentPayments.count,
            averageAmount: agentPayments.isEmpty ? 0 : Double(total) / Double(agentPayments.count),
            largestPayment: agentPayments.map { $0.amount }.max() ?? 0,
            topRecipients: []
        )
    }

    func resetDailyLimits() { dailySpending.removeAll() }

    // MARK: - Private

    private func validatePayment(channel: PaymentChannel, recipient: String, amount: UInt64, token: String) -> AgenticPaymentError? {
        if let exp = channel.expiresAt, Date() > exp { return .channelExpired }
        if amount > channel.remainingDeposit { return .insufficientFunds }
        if amount > channel.perTransactionLimit { return .perTransactionLimitExceeded }
        let todaySpent = dailySpending[channel.agentDID] ?? 0
        if todaySpent + amount > channel.dailyLimit { return .dailyLimitExceeded }
        if let allowed = channel.allowedRecipients, !allowed.contains(recipient) { return .recipientNotAllowed }
        if !channel.allowedTokens.contains(token) { return .tokenNotAllowed }
        return nil
    }

    private func logAuditEntry(paymentId: String, agentDID: String, action: String, amount: UInt64) {
        let entry = PaymentAuditEntry(
            entryId: UUID().uuidString, paymentId: paymentId,
            agentDID: agentDID, action: action, amount: amount,
            timestamp: Date(), details: [:]
        )
        auditLog.append(entry)
    }
}
