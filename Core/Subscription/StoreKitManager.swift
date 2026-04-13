// Core/Subscription/StoreKitManager.swift
// MTRX — StoreKit 2 Integration
//
// Manages auto-renewing subscriptions via StoreKit 2.
// Handles: product loading, purchases, entitlement verification,
// trial detection, and subscription lifecycle.
//
// Product IDs (configured in App Store Connect):
//   com.opnmatrx.mtrx.pro.monthly        — Pro tier, 3-day free trial
//   com.opnmatrx.mtrx.enterprise.monthly — Enterprise tier, 3-day free trial
//
// Both paid tiers offer a 3-day introductory offer (free trial) configured
// as a "Pay as you go" introductory offer in App Store Connect.

import Foundation
import StoreKit
import Observation

// MARK: - Store Error

enum StoreError: LocalizedError {
    case productNotFound
    case purchaseFailed(String)
    case verificationFailed
    case noActiveSubscription

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Subscription product not found."
        case .purchaseFailed(let reason):
            return "Purchase failed: \(reason)"
        case .verificationFailed:
            return "Could not verify your subscription."
        case .noActiveSubscription:
            return "No active subscription found."
        }
    }
}

// MARK: - Subscription Info

/// Snapshot of the user's current subscription state from StoreKit.
struct SubscriptionInfo {
    let tier: SubscriptionTier
    let isActive: Bool
    let isInTrialPeriod: Bool
    let trialEndDate: Date?
    let expirationDate: Date?
    let willAutoRenew: Bool
    let originalTransactionId: String?
}

// MARK: - StoreKit Manager

/// Manages StoreKit 2 auto-renewing subscriptions for MTRX.
@Observable
final class StoreKitManager {

    static let shared = StoreKitManager()

    // MARK: Published State

    /// Available subscription products loaded from App Store.
    private(set) var products: [Product] = []

    /// Whether products have been loaded.
    private(set) var isLoaded: Bool = false

    /// Whether a purchase is in progress.
    private(set) var isPurchasing: Bool = false

    /// The user's current subscription info.
    private(set) var currentSubscription: SubscriptionInfo?

    /// Whether the user is currently in a trial period.
    var isInTrial: Bool {
        currentSubscription?.isInTrialPeriod ?? false
    }

    /// Whether the user has ever used a trial (prevents re-trial).
    private(set) var hasUsedTrial: Bool = false

    /// Whether a trial offer is available for a product.
    func isTrialAvailable(for tier: SubscriptionTier) -> Bool {
        guard tier.hasTrialOffer, !hasUsedTrial else { return false }
        guard let product = product(for: tier) else { return false }
        // StoreKit 2 will show the offer only if user is eligible
        return product.subscription?.introductoryOffer != nil
    }

    // MARK: Product IDs

    private let productIds: Set<String> = [
        "com.opnmatrx.mtrx.pro.monthly",
        "com.opnmatrx.mtrx.enterprise.monthly",
    ]

    // MARK: Transaction Listener

    private var transactionListener: Task<Void, Never>?

    // MARK: Init

    private init() {
        // Start listening for transaction updates
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    /// Load subscription products from the App Store.
    func loadProducts() async throws {
        let storeProducts = try await Product.products(for: productIds)
        // Sort: Pro first, then Enterprise
        products = storeProducts.sorted { ($0.price as NSDecimalNumber).doubleValue < ($1.price as NSDecimalNumber).doubleValue }
        isLoaded = true
    }

    /// Get the Product for a specific tier.
    func product(for tier: SubscriptionTier) -> Product? {
        guard let productId = tier.productId else { return nil }
        return products.first { $0.id == productId }
    }

    // MARK: - Purchase

    /// Purchase a subscription tier. Starts 3-day free trial if eligible.
    @MainActor
    func purchase(_ tier: SubscriptionTier) async throws -> Transaction {
        guard let product = product(for: tier) else {
            throw StoreError.productNotFound
        }

        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlements()
            return transaction

        case .userCancelled:
            throw StoreError.purchaseFailed("User cancelled")

        case .pending:
            throw StoreError.purchaseFailed("Purchase is pending approval")

        @unknown default:
            throw StoreError.purchaseFailed("Unknown purchase result")
        }
    }

    // MARK: - Entitlements

    /// Check current entitlements and update the FeatureGate.
    /// Call this on launch, after sign-in, and after any transaction.
    @MainActor
    func refreshEntitlements() async {
        var foundTier: SubscriptionTier = .free
        var subscriptionInfo: SubscriptionInfo?

        // Check all current entitlements
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if let tier = tierForProductId(transaction.productID) {
                // Determine trial status from subscription status
                let isInTrial = await checkTrialStatus(for: transaction)
                let trialEnd = isInTrial ? trialEndDate(for: transaction) : nil
                let renewalInfo = await getRenewalInfo(for: transaction)

                subscriptionInfo = SubscriptionInfo(
                    tier: tier,
                    isActive: true,
                    isInTrialPeriod: isInTrial,
                    trialEndDate: trialEnd,
                    expirationDate: transaction.expirationDate,
                    willAutoRenew: renewalInfo?.willAutoRenew ?? true,
                    originalTransactionId: String(transaction.originalID)
                )

                if tier > foundTier {
                    foundTier = tier
                }

                if isInTrial {
                    hasUsedTrial = true
                }
            }
        }

        // Update FeatureGate with the found tier
        if let info = subscriptionInfo {
            FeatureGate.shared.updateTier(
                info.tier,
                isTrialActive: info.isInTrialPeriod,
                trialEndDate: info.trialEndDate,
                originalTransactionId: info.originalTransactionId
            )
        } else {
            // No active subscription — fall back to free
            FeatureGate.shared.fallbackToFree()
        }

        currentSubscription = subscriptionInfo
    }

    // MARK: - Trial Detection

    /// Check if a transaction is currently in its trial period.
    private func checkTrialStatus(for transaction: Transaction) async -> Bool {
        // Method 1: Check the offer type on the transaction
        if let offerType = transaction.offerType {
            if offerType == .introductory {
                // Verify the trial hasn't expired yet
                if let expiration = transaction.expirationDate, expiration > Date() {
                    // Check if we're still within the trial window (3 days from purchase)
                    let trialEnd = transaction.purchaseDate.addingTimeInterval(3 * 24 * 3600)
                    if Date() < trialEnd {
                        return true
                    }
                }
            }
        }

        // Method 2: Check renewal info for offer details
        if let renewalInfo = await getRenewalInfo(for: transaction) {
            if renewalInfo.offerType == .introductory {
                return true
            }
        }

        return false
    }

    /// Calculate the trial end date for a transaction.
    private func trialEndDate(for transaction: Transaction) -> Date? {
        // Trial is 3 days from the original purchase date
        return transaction.purchaseDate.addingTimeInterval(3 * 24 * 3600)
    }

    /// Get renewal info for a transaction's subscription.
    private func getRenewalInfo(for transaction: Transaction) async -> Product.SubscriptionInfo.RenewalInfo? {
        guard let productId = SubscriptionTier.pro.productId ?? SubscriptionTier.enterprise.productId else {
            return nil
        }

        // Try to get subscription status
        for await result in Transaction.currentEntitlements {
            guard let tx = try? checkVerified(result),
                  tx.productID == transaction.productID else { continue }

            // Access subscription status through the product
            if let product = product(for: tierForProductId(transaction.productID) ?? .free),
               let subscription = product.subscription {
                let statuses = try? await subscription.status
                if let status = statuses?.first {
                    if case .verified(let renewalInfo) = status.renewalInfo {
                        return renewalInfo
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Restore Purchases

    /// Restore previous purchases (triggers StoreKit to re-sync).
    @MainActor
    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Manage Subscription

    /// Open the subscription management page in Settings.
    func manageSubscription() async {
        guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        do {
            try await AppStore.showManageSubscriptions(in: windowScene)
        } catch {
            // Fallback: open Settings directly
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                await UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Helpers

    /// Verify a StoreKit verification result.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let value):
            return value
        }
    }

    /// Map a product ID to a SubscriptionTier.
    private func tierForProductId(_ productId: String) -> SubscriptionTier? {
        switch productId {
        case "com.opnmatrx.mtrx.pro.monthly":        return .pro
        case "com.opnmatrx.mtrx.enterprise.monthly": return .enterprise
        default:                                 return nil
        }
    }

    /// Listen for transaction updates (renewals, revocations, etc).
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }
}
