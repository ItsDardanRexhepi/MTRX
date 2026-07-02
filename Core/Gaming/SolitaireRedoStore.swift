// SolitaireRedoStore.swift
// MTRX — Core/Gaming
//
// The $0.99 "5 extra do-overs" Consumable for Solitaire. This is REAL MONEY, so
// it follows the money-seam law exactly:
//   • grant order = purchase → verify → grantRedos → finish. Finishing before
//     granting would lose the purchase, so grant ALWAYS precedes finish().
//   • idempotent on transaction.id — the same transaction is delivered twice
//     (the purchase() return AND the Transaction.updates listener); it is
//     granted at most once.
//   • balance lives in its OWN key, never SubscriptionState.usageCounters
//     (which resets monthly — that would delete paid-for redos).
//   • it is a Consumable, NOT a subscription: it never enters productIds or
//     tierForProductId, so it can never be mistaken for a Pro entitlement.
//   • fail-closed: cancel / pending / unverified / error grant ZERO redos.

import Foundation
import StoreKit

@MainActor
final class SolitaireRedoStore: ObservableObject {

    static let shared = SolitaireRedoStore()

    /// The exact Consumable product id — create this in App Store Connect.
    static let productId = "com.opnmatrx.mtrx.solitaire.redos5"
    static let redosPerPurchase = 5

    private let balanceKey = "com.mtrx.solitaire.purchasedRedoBalance"
    private let processedKey = "com.mtrx.solitaire.processedRedoTxIds"
    private let defaults: UserDefaults

    /// Purchased do-overs available across games (persists; NOT the per-deal
    /// free budget).
    @Published private(set) var balance: Int
    @Published private(set) var product: Product?
    @Published var isPurchasing = false

    /// Injectable defaults so the money logic is unit-testable without StoreKit.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.balance = max(0, defaults.integer(forKey: balanceKey))
    }

    enum RedoPurchaseError: Error { case productUnavailable, cancelled, pending, unverified, failed }

    // MARK: - Idempotent grant / consume (testable core)

    /// Record a grant for a transaction id, exactly once. Returns true only on
    /// the FIRST delivery of that id; a repeat delivery is a no-op. This is what
    /// makes double-delivery (purchase return + updates listener) safe.
    @discardableResult
    func recordGrant(transactionId: UInt64, redos: Int) -> Bool {
        guard redos > 0 else { return false }
        var processed = Set((defaults.array(forKey: processedKey) as? [String]) ?? [])
        let key = String(transactionId)
        guard !processed.contains(key) else { return false }   // already delivered
        processed.insert(key)
        balance += redos
        defaults.set(balance, forKey: balanceKey)
        defaults.set(Array(processed), forKey: processedKey)
        return true
    }

    /// Spend one purchased do-over. Returns true if one was available.
    @discardableResult
    func consumeOne() -> Bool {
        guard balance > 0 else { return false }
        balance -= 1
        defaults.set(balance, forKey: balanceKey)
        return true
    }

    // MARK: - StoreKit

    func loadProduct() async {
        product = try? await Product.products(for: [Self.productId]).first
    }

    /// Grant from a VERIFIED transaction, idempotently. MUST be called before
    /// `transaction.finish()`. Only ever grants for our own consumable id.
    @discardableResult
    func grant(_ transaction: Transaction) -> Bool {
        guard transaction.productID == Self.productId else { return false }
        return recordGrant(transactionId: transaction.id, redos: Self.redosPerPurchase)
    }

    /// Buy 5 do-overs. Fail-closed: any non-success outcome throws and grants
    /// nothing. On success the grant is recorded BEFORE the transaction is
    /// finished.
    func purchase() async throws {
        if product == nil { await loadProduct() }
        guard let product else { throw RedoPurchaseError.productUnavailable }

        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                grant(transaction)            // grant BEFORE finish
                await transaction.finish()
            case .unverified:
                throw RedoPurchaseError.unverified   // fail-closed — no grant, don't finish
            }
        case .userCancelled:
            throw RedoPurchaseError.cancelled
        case .pending:
            throw RedoPurchaseError.pending
        @unknown default:
            throw RedoPurchaseError.failed
        }
    }
}
