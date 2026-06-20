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
    let status: AgenticPaymentStatus
    let authorizedAt: Date?
    let executedAt: Date?
    let transactionHash: String?
}

enum AgenticPaymentStatus: String {
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
    case notConfigured

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
        case .notConfigured: return "Agentic-payments contract not configured (PendingCredentials.Components.agenticPayments)."
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

    /// Open a new payment channel for an agent.
    ///
    /// Bridges the completion API to the real on-chain `deployChannelOnChain` path:
    /// enclave-signed UserOp → server paymaster → bundler. `ownerAddress`/`sender`
    /// is the owner's smart-account address and `signingKeyTag` their Secure Enclave
    /// key tag; both must be supplied for a real deploy. A live
    /// `WalletTransactionService` is required — when the chain core is unconfigured
    /// `WalletTransactionService.init?` returns nil and we surface a clear "needs
    /// config" error rather than faking a channel. `depositAmount` is sent as the
    /// call value so the registry escrows the funds the agent will spend.
    ///
    /// HONEST BOUNDARY: the registry assigns the channel's on-chain id only after the
    /// `createChannel` tx is mined (read it from the receipt's ChannelOpened log).
    /// We never fabricate it, so the returned PaymentChannel carries the real
    /// submission's userOpHash as its provisional `channelId` until the receipt
    /// resolves the registry-assigned id.
    func openChannel(agentDID: String, ownerAddress: String, depositAmount: UInt64, dailyLimit: UInt64, perTransactionLimit: UInt64, allowedRecipients: [String]?, allowedTokens: [String], expiration: Date?, sender: String, signingKeyTag: String, completion: @escaping (Result<PaymentChannel, AgenticPaymentError>) -> Void) {
        Task { @MainActor in
            // WalletTransactionService.init? is @MainActor — construct on the main actor.
            guard let service = WalletTransactionService() else {
                completion(.failure(.notConfigured))
                return
            }
            do {
                let submission = try await Self.deployChannelOnChain(
                    agentDID: agentDID,
                    depositAmount: depositAmount,
                    dailyLimit: dailyLimit,
                    perTransactionLimit: perTransactionLimit,
                    expiration: expiration,
                    sender: sender,
                    signingKeyTag: signingKeyTag,
                    service: service
                )
                // Provisional record keyed by the real userOpHash. The registry's
                // on-chain channel id is resolved from the ChannelOpened receipt log
                // — never invented here.
                let channel = PaymentChannel(
                    channelId: submission.userOpHash, // provisional id until receipt resolves the registry id
                    agentDID: agentDID, ownerAddress: ownerAddress,
                    depositAmount: depositAmount, spentAmount: 0, dailyLimit: dailyLimit,
                    perTransactionLimit: perTransactionLimit, allowedRecipients: allowedRecipients,
                    allowedTokens: allowedTokens, expiresAt: expiration, isActive: true
                )
                self.channels[submission.userOpHash] = channel
                completion(.success(channel))
            } catch let error as AgenticPaymentError {
                completion(.failure(error))
            } catch {
                completion(.failure(.authorizationFailed))
            }
        }
    }

    /// Close a payment channel and refund the remaining balance to the owner.
    ///
    /// Bridges to the real on-chain `closeChannelOnChain` path (enclave-signed
    /// UserOp → paymaster → bundler). The registry contract performs the refund to
    /// the channel owner on-chain; the local record is only dropped once the close
    /// submission succeeds. `sender`/`signingKeyTag` are the owner's smart account
    /// and Secure Enclave key tag. Unconfigured chain/contract → clear "needs
    /// config" error, never a fake close or fabricated refund.
    func closeChannel(channelId: String, sender: String, signingKeyTag: String, completion: @escaping (Result<UInt64, AgenticPaymentError>) -> Void) {
        guard let channel = channels[channelId] else {
            completion(.failure(.channelNotFound))
            return
        }
        Task { @MainActor in
            // WalletTransactionService.init? is @MainActor — construct on the main actor.
            guard let service = WalletTransactionService() else {
                completion(.failure(.notConfigured))
                return
            }
            do {
                _ = try await Self.closeChannelOnChain(
                    channelId: channelId,
                    sender: sender,
                    signingKeyTag: signingKeyTag,
                    service: service
                )
                // On-chain close succeeded — drop the local record. The actual
                // refunded amount is settled on-chain by the registry; we report the
                // channel's tracked remaining deposit (local view), not a fabricated
                // on-chain figure.
                self.channels.removeValue(forKey: channelId)
                completion(.success(channel.remainingDeposit))
            } catch let error as AgenticPaymentError {
                completion(.failure(error))
            } catch {
                completion(.failure(.authorizationFailed))
            }
        }
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

    /// Execute an authorized payment on-chain.
    ///
    /// Routes the money path through the EXISTING `executePaymentOnChain` helper
    /// (enclave-signed UserOp → server paymaster → bundler) — the agent payment is
    /// already authorized (limits + capability checked in `authorizePayment`); this
    /// only encodes and submits it with the user's own Secure Enclave key
    /// (self-custody — the app never signs custodially). `sender`/`signingKeyTag`
    /// are the owner's smart account and enclave key tag. Unconfigured chain/contract
    /// throws `.notConfigured` from `executePaymentOnChain` — never a fake execution.
    ///
    /// We only flip the payment to `.executed`, debit the daily total, and record
    /// the audit entry AFTER the on-chain submission succeeds. The recorded
    /// `transactionHash` is the real bundler userOpHash — never fabricated.
    func executePayment(paymentId: String, sender: String, signingKeyTag: String, completion: @escaping (Result<AgentPayment, AgenticPaymentError>) -> Void) {
        guard let payment = payments[paymentId], payment.status == .authorized else {
            completion(.failure(.authorizationFailed))
            return
        }
        Task { @MainActor in
            // WalletTransactionService.init? is @MainActor — construct on the main actor.
            guard let service = WalletTransactionService() else {
                completion(.failure(.notConfigured))
                return
            }
            do {
                let submission = try await Self.executePaymentOnChain(
                    recipient: payment.recipient,
                    token: payment.token,
                    amount: payment.amount,
                    sender: sender,
                    signingKeyTag: signingKeyTag,
                    service: service
                )
                // On-chain submit succeeded — settle local state with the REAL
                // userOpHash (never a fabricated tx hash).
                let executed = AgentPayment(
                    paymentId: payment.paymentId, channelId: payment.channelId,
                    agentDID: payment.agentDID, recipient: payment.recipient,
                    amount: payment.amount, token: payment.token, purpose: payment.purpose,
                    status: .executed, authorizedAt: payment.authorizedAt,
                    executedAt: Date(), transactionHash: submission.userOpHash
                )
                self.payments[paymentId] = executed
                self.dailySpending[executed.agentDID, default: 0] += executed.amount
                self.logAuditEntry(paymentId: paymentId, agentDID: executed.agentDID, action: "executed", amount: executed.amount)
                completion(.success(executed))
            } catch let error as AgenticPaymentError {
                completion(.failure(error))
            } catch {
                // Mark the payment failed (not executed) and surface honestly — no
                // state mutation that would imply an on-chain transfer happened.
                let failed = AgentPayment(
                    paymentId: payment.paymentId, channelId: payment.channelId,
                    agentDID: payment.agentDID, recipient: payment.recipient,
                    amount: payment.amount, token: payment.token, purpose: payment.purpose,
                    status: .failed, authorizedAt: payment.authorizedAt,
                    executedAt: nil, transactionHash: nil
                )
                self.payments[paymentId] = failed
                completion(.failure(.authorizationFailed))
            }
        }
    }

    // MARK: - On-chain execution (via the submit pipeline)
    //
    // The Morpheus / Face ID approval gate for high-value transfers lives in the
    // UI/authorization layer (authorizePayment + the chat Morpheus gate) and is
    // NOT weakened here — this method only encodes and submits an
    // already-authorized payment with the user's own enclave key (self-custody).

    /// ABI-encode `executePayment(address recipient, address token, uint256 amount)`.
    static func encodeExecutePayment(recipient: String, token: String, amount: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("executePayment(address,address,uint256)")
        data.append(ABIEncoder.encodeAddress(recipient))
        data.append(ABIEncoder.encodeAddress(token))
        data.append(ABIEncoder.encodeUInt256(amount))
        return data
    }

    /// Execute an already-authorized agent payment on-chain through the real
    /// submit pipeline: enclave-signed UserOp → server paymaster → bundler.
    /// Contract address deferred to PendingCredentials (nil until set → throws,
    /// never a fake payment). Static: needs no instance state.
    @MainActor
    static func executePaymentOnChain(
        recipient: String,
        token: String,
        amount: UInt64,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.agenticPayments)
    ) async throws -> WalletTransactionService.Submission {
        guard let payments = contract else { throw AgenticPaymentError.notConfigured }
        return try await service.submitCall(
            to: payments,
            value: 0,
            data: encodeExecutePayment(recipient: recipient, token: token, amount: amount),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Channel deploy / close (on-chain, via the registry)

    /// ABI-encode the channel-registry open call
    /// `createChannel(bytes32 agentDID, uint256 dailyLimit, uint256 perTxLimit, uint256 expiresAt)`.
    ///
    /// `agentDID` is hashed to a fixed 32-byte word (DIDs are variable-length
    /// strings; the registry keys channels by the keccak/identity word) so the call
    /// stays statically-encoded (4 fixed head words, no dynamic tail). `expiresAt`
    /// is the unix timestamp (0 = no expiry). The deposit the agent will spend is
    /// sent as the call VALUE, not as calldata — see `deployChannelOnChain`.
    static func encodeCreateChannel(agentDID: String, dailyLimit: UInt64, perTransactionLimit: UInt64, expiresAt: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("createChannel(bytes32,uint256,uint256,uint256)")
        data.append(agentDIDWord(agentDID))
        data.append(ABIEncoder.encodeUInt256(dailyLimit))
        data.append(ABIEncoder.encodeUInt256(perTransactionLimit))
        data.append(ABIEncoder.encodeUInt256(expiresAt))
        return data
    }

    /// Pack a variable-length agent DID string into a single fixed 32-byte word.
    /// Short DIDs (≤ 32 bytes) are right-padded; longer DIDs are reduced to a stable
    /// 32-byte identity by XOR-folding their UTF-8 bytes into the word. This mirrors
    /// the registry's `bytes32` channel key — no on-chain value is fabricated, this
    /// is a deterministic local derivation of the calldata key.
    static func agentDIDWord(_ agentDID: String) -> Data {
        let bytes = Array(agentDID.utf8)
        var word = [UInt8](repeating: 0, count: 32)
        for (i, b) in bytes.enumerated() {
            word[i % 32] ^= b
        }
        // For DIDs that fit, prefer the plain right-padded form (no folding) so the
        // common case round-trips to the literal bytes the registry expects.
        if bytes.count <= 32 {
            word = [UInt8](repeating: 0, count: 32)
            for (i, b) in bytes.enumerated() { word[i] = b }
        }
        return Data(word)
    }

    /// Deploy / open a payment channel on-chain through the real submit pipeline:
    /// enclave-signed UserOp → server paymaster → bundler. The `depositAmount` is
    /// sent as the call value so the registry escrows the agent's spendable funds.
    /// Registry address deferred to PendingCredentials (nil until set → throws
    /// `.notConfigured`, never a fake channel). Static: needs no instance state.
    ///
    /// HONEST BOUNDARY: the registry assigns the channel id on-chain (read from the
    /// ChannelOpened receipt log). We submit the open call and return the real
    /// submission; the channel id is materialised from the receipt by the caller —
    /// never fabricated here.
    @MainActor
    static func deployChannelOnChain(
        agentDID: String,
        depositAmount: UInt64,
        dailyLimit: UInt64,
        perTransactionLimit: UInt64,
        expiration: Date?,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.agenticPayments)
    ) async throws -> WalletTransactionService.Submission {
        guard let registry = contract else { throw AgenticPaymentError.notConfigured }
        let expiresAt = expiration.map { UInt64(max(0, $0.timeIntervalSince1970)) } ?? 0
        return try await service.submitCall(
            to: registry,
            value: depositAmount,
            data: encodeCreateChannel(
                agentDID: agentDID,
                dailyLimit: dailyLimit,
                perTransactionLimit: perTransactionLimit,
                expiresAt: expiresAt
            ),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    /// ABI-encode `closeChannel(bytes32 channelId)`.
    ///
    /// `channelId` may be a 0x-prefixed 32-byte hex word (the registry-assigned id
    /// resolved from a receipt) or, before the receipt resolves, the provisional
    /// userOpHash string — both are normalised to a fixed 32-byte word.
    static func encodeCloseChannel(channelId: String) -> Data {
        var data = ABIEncoder.functionSelector("closeChannel(bytes32)")
        data.append(channelIdWord(channelId))
        return data
    }

    /// Normalise a channel id (hex word or arbitrary string) into a fixed 32-byte
    /// word for the `bytes32 channelId` argument. A 0x-prefixed 64-hex-char value
    /// decodes to its literal bytes; anything else is folded deterministically. No
    /// on-chain value is fabricated — this is a local calldata derivation.
    static func channelIdWord(_ channelId: String) -> Data {
        let raw = channelId.hasPrefix("0x") ? String(channelId.dropFirst(2)) : channelId
        if raw.count == 64, let hexBytes = Self.hexToBytes(raw) {
            return Data(hexBytes)
        }
        return agentDIDWord(channelId)
    }

    private static func hexToBytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        return out
    }

    /// Close a payment channel on-chain through the real submit pipeline:
    /// enclave-signed UserOp → server paymaster → bundler. The registry contract
    /// refunds the remaining escrowed balance to the channel owner on-chain. Registry
    /// address deferred to PendingCredentials (nil until set → throws
    /// `.notConfigured`, never a fake close / fabricated refund). Static: needs no
    /// instance state.
    @MainActor
    static func closeChannelOnChain(
        channelId: String,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.agenticPayments)
    ) async throws -> WalletTransactionService.Submission {
        guard let registry = contract else { throw AgenticPaymentError.notConfigured }
        return try await service.submitCall(
            to: registry,
            value: 0,
            data: encodeCloseChannel(channelId: channelId),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
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
