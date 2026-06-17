// PaymentsManager.swift
// MTRX Blockchain - Components - Payments (C17)
//
// Cross-border payments, fiat/ETH conversion, free under $1k (2 per 48hr),
// 0.5% fee above $1k.

import Foundation
import Combine

// MARK: - Protocols

protocol PaymentsDelegate: AnyObject {
    func payments(_ manager: PaymentsManager, paymentCompleted payment: CrossBorderPayment)
    func payments(_ manager: PaymentsManager, conversionCompleted conversion: FiatETHConversion)
}

// MARK: - Data Models

enum PaymentStatus: String, Codable {
    case pending, processing, completed, failed, refunded
}

enum CurrencyType: String, Codable {
    case fiat, eth, erc20
}

struct CrossBorderPayment: Identifiable, Codable {
    let id: String
    let senderAddress: String
    let recipientAddress: String
    let amount: Double
    let sourceCurrency: String
    let targetCurrency: String
    let feeAmount: Double
    let feeWaived: Bool
    let exchangeRate: Double
    let createdAt: Date
    var status: PaymentStatus
    let txHash: String?
}

struct FiatETHConversion: Identifiable, Codable {
    let id: String
    let userAddress: String
    let fiatAmount: Double
    let fiatCurrency: String
    let ethAmount: Double
    let direction: ConversionDirection
    let exchangeRate: Double
    let fee: Double
    let timestamp: Date
}

enum ConversionDirection: String, Codable {
    case fiatToETH, ethToFiat
}

/// Tracks free-tier usage per sender.
struct FreeTransferTracker: Codable {
    let senderAddress: String
    var transfers: [Date]  // timestamps of free transfers in rolling 48-hr window
}

enum PaymentsError: Error, LocalizedError {
    case freeLimitExceeded
    case conversionFailed(String)
    case invalidAmount
    case paymentFailed(String)
    case unsupportedCurrency(String)

    var errorDescription: String? {
        switch self {
        case .freeLimitExceeded: return "Free transfer limit (2 per 48 hours under $1,000) exceeded."
        case .conversionFailed(let r): return "Conversion failed: \(r)"
        case .invalidAmount: return "Amount must be greater than zero."
        case .paymentFailed(let r): return "Payment failed: \(r)"
        case .unsupportedCurrency(let c): return "Unsupported currency: \(c)"
        }
    }
}

// MARK: - PaymentsManager

final class PaymentsManager: ObservableObject {

    static let shared = PaymentsManager()

    /// Threshold below which payments may be free.
    static let freeThreshold: Double = 1_000.0
    /// Max free transfers per 48-hour rolling window.
    static let maxFreeTransfersPer48h: Int = 2
    /// Fee for payments above $1,000.
    static let feeAboveThreshold: Double = 0.005   // 0.5%
    /// Rolling window in seconds.
    static let rollingWindowSeconds: TimeInterval = 48 * 3600

    weak var delegate: PaymentsDelegate?

    @Published private(set) var payments: [CrossBorderPayment] = []
    @Published private(set) var conversions: [FiatETHConversion] = []
    @Published private(set) var isLoading = false

    private var freeTrackers: [String: FreeTransferTracker] = [:]

    // MARK: - Cross-Border Payment

    /// Send a cross-border payment.
    /// - Free if amount < $1k and sender has not exceeded 2 free transfers in 48 hours.
    /// - 0.5% fee if amount >= $1k.
    func sendPayment(senderAddress: String, recipientAddress: String, amount: Double, sourceCurrency: String, targetCurrency: String, exchangeRate: Double) async throws -> CrossBorderPayment {
        guard amount > 0 else {
            throw PaymentsError.invalidAmount
        }

        let (fee, waived) = try calculateFee(senderAddress: senderAddress, amount: amount)

        let payment = CrossBorderPayment(
            id: UUID().uuidString,
            senderAddress: senderAddress,
            recipientAddress: recipientAddress,
            amount: amount,
            sourceCurrency: sourceCurrency,
            targetCurrency: targetCurrency,
            feeAmount: fee,
            feeWaived: waived,
            exchangeRate: exchangeRate,
            createdAt: Date(),
            status: .completed,
            txHash: nil
        )

        // Record free transfer if applicable
        if waived {
            recordFreeTransfer(senderAddress: senderAddress)
        }

        await MainActor.run { payments.append(payment) }
        delegate?.payments(self, paymentCompleted: payment)
        return payment
    }

    // MARK: - On-chain execution (via the submit pipeline)
    //
    // Only the ON-CHAIN crypto leg is wired here, and it is USER-SIGNED
    // SELF-CUSTODY (the user signs the transfer of their own token with their own
    // enclave key). Any fiat ↔ crypto conversion / cross-border settlement is
    // off-chain and must be performed by a licensed money-services provider — it
    // is intentionally NOT executed in-app.

    /// ABI-encode the ERC-20 `transfer(address recipient, uint256 amount)`.
    static func encodeTransfer(recipient: String, amount: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("transfer(address,uint256)")
        data.append(ABIEncoder.encodeAddress(recipient))
        data.append(ABIEncoder.encodeUInt256(amount))
        return data
    }

    /// Send the on-chain (crypto) leg of a payment through the real submit
    /// pipeline: enclave-signed UserOp → server paymaster → bundler. `token` is
    /// the settlement token contract (deferred to PendingCredentials.Components.payments
    /// or pass an explicit token); nil → throws, never a fake transfer.
    @MainActor
    func sendPaymentOnChain(
        token: String? = PendingCredentials.filled(PendingCredentials.Components.payments),
        recipient: String,
        amount: UInt64,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService
    ) async throws -> WalletTransactionService.Submission {
        guard let tokenAddress = token else {
            throw PaymentsError.paymentFailed("Payments token not configured (PendingCredentials.Components.payments)")
        }
        return try await service.submitCall(
            to: tokenAddress,
            value: 0,
            data: Self.encodeTransfer(recipient: recipient, amount: amount),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Fee Calculation

    /// Calculate the fee for a payment.
    /// Returns (feeAmount, isWaived).
    func calculateFee(senderAddress: String, amount: Double) throws -> (Double, Bool) {
        if amount < Self.freeThreshold {
            let count = freeTransfersInWindow(senderAddress: senderAddress)
            if count < Self.maxFreeTransfersPer48h {
                return (0.0, true)   // free
            }
            // Exceeded free limit, still charge 0.5%
            return (amount * Self.feeAboveThreshold, false)
        }
        // Above threshold: 0.5%
        return (amount * Self.feeAboveThreshold, false)
    }

    /// How many free transfers the sender has used in the rolling 48-hr window.
    func freeTransfersInWindow(senderAddress: String) -> Int {
        guard let tracker = freeTrackers[senderAddress] else { return 0 }
        let cutoff = Date().addingTimeInterval(-Self.rollingWindowSeconds)
        return tracker.transfers.filter { $0 > cutoff }.count
    }

    private func recordFreeTransfer(senderAddress: String) {
        var tracker = freeTrackers[senderAddress] ?? FreeTransferTracker(senderAddress: senderAddress, transfers: [])
        tracker.transfers.append(Date())
        // Prune old entries
        let cutoff = Date().addingTimeInterval(-Self.rollingWindowSeconds)
        tracker.transfers = tracker.transfers.filter { $0 > cutoff }
        freeTrackers[senderAddress] = tracker
    }

    // MARK: - Fiat / ETH Conversion

    func convertFiatToETH(userAddress: String, fiatAmount: Double, fiatCurrency: String, exchangeRate: Double) async throws -> FiatETHConversion {
        guard fiatAmount > 0 else { throw PaymentsError.invalidAmount }

        let ethAmount = fiatAmount / exchangeRate
        let fee = fiatAmount >= Self.freeThreshold ? fiatAmount * Self.feeAboveThreshold : 0

        let conversion = FiatETHConversion(
            id: UUID().uuidString,
            userAddress: userAddress,
            fiatAmount: fiatAmount,
            fiatCurrency: fiatCurrency,
            ethAmount: ethAmount,
            direction: .fiatToETH,
            exchangeRate: exchangeRate,
            fee: fee,
            timestamp: Date()
        )

        await MainActor.run { conversions.append(conversion) }
        delegate?.payments(self, conversionCompleted: conversion)
        return conversion
    }

    func convertETHToFiat(userAddress: String, ethAmount: Double, fiatCurrency: String, exchangeRate: Double) async throws -> FiatETHConversion {
        guard ethAmount > 0 else { throw PaymentsError.invalidAmount }

        let fiatAmount = ethAmount * exchangeRate
        let fee = fiatAmount >= Self.freeThreshold ? fiatAmount * Self.feeAboveThreshold : 0

        let conversion = FiatETHConversion(
            id: UUID().uuidString,
            userAddress: userAddress,
            fiatAmount: fiatAmount,
            fiatCurrency: fiatCurrency,
            ethAmount: ethAmount,
            direction: .ethToFiat,
            exchangeRate: exchangeRate,
            fee: fee,
            timestamp: Date()
        )

        await MainActor.run { conversions.append(conversion) }
        delegate?.payments(self, conversionCompleted: conversion)
        return conversion
    }

    // MARK: - Queries

    func getPayments(for address: String) -> [CrossBorderPayment] {
        payments.filter { $0.senderAddress == address || $0.recipientAddress == address }
    }

    func totalFeesPaid(by address: String) -> Double {
        payments
            .filter { $0.senderAddress == address }
            .reduce(0.0) { $0 + $1.feeAmount }
    }
}
