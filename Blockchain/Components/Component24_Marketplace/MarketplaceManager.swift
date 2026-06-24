// MarketplaceManager.swift
// MTRX Blockchain - Components - Marketplace (C24)
//
// 5% NeoSafe / 95% seller, compliance filter, appeal escalated to the platform owner.

import Foundation
import Combine

// MARK: - Protocols

protocol MarketplaceDelegate: AnyObject {
    func marketplace(_ manager: MarketplaceManager, listingCreated listing: MarketListing)
    func marketplace(_ manager: MarketplaceManager, saleCompleted sale: MarketSale)
    func marketplace(_ manager: MarketplaceManager, listingFlagged listing: MarketListing, reason: String)
    func marketplace(_ manager: MarketplaceManager, appealFiled appeal: MarketAppeal)
}

// MARK: - Data Models

enum ListingCategory: String, Codable, CaseIterable {
    case physicalGoods, digitalGoods, services, nfts, tokens, realEstate, vehicles, other
}

enum ListingStatus: String, Codable {
    case active, sold, cancelled, flagged, removed, underReview
}

enum ComplianceFlag: String, Codable {
    case prohibited, restricted, requiresVerification, sanctioned, counterfeit, fraud
}

struct MarketListing: Identifiable, Codable {
    let id: String
    let sellerAddress: String
    let title: String
    let description: String
    let category: ListingCategory
    let price: Double
    let currency: String
    let createdAt: Date
    var status: ListingStatus
    var complianceFlags: [ComplianceFlag]
    let metadataURI: String?
}

struct MarketSale: Identifiable, Codable {
    let id: String
    let listingId: String
    let sellerAddress: String
    let buyerAddress: String
    let salePrice: Double
    let sellerProceeds: Double     // 95%
    let platformFee: Double        // 5% NeoSafe
    let timestamp: Date
    let txHash: String?
}

struct MarketAppeal: Identifiable, Codable {
    let id: String
    let listingId: String
    let appellantAddress: String
    let reason: String
    var status: AppealStatus
    let filedAt: Date
    /// Appeals are escalated to the platform owner for review.
    let escalationChannel: String  // e.g. "owner-review"
}

enum AppealStatus: String, Codable {
    case filed, underReview, approved, rejected
}

enum MarketplaceError: Error, LocalizedError {
    case listingNotFound(String)
    case listingNotActive
    case complianceViolation([ComplianceFlag])
    case sellerCannotBuy
    case appealAlreadyFiled
    case insufficientPayment
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .listingNotFound(let id): return "Listing not found: \(id)"
        case .listingNotActive: return "Listing is not active."
        case .complianceViolation(let flags): return "Compliance violation: \(flags.map(\.rawValue).joined(separator: ", "))"
        case .sellerCannotBuy: return "Seller cannot buy their own listing."
        case .appealAlreadyFiled: return "Appeal already filed for this listing."
        case .insufficientPayment: return "Payment amount is insufficient."
        case .notConfigured: return "Marketplace contract not configured (PendingCredentials.Components.marketplace)."
        }
    }
}

// MARK: - MarketplaceManager

final class MarketplaceManager: ObservableObject {

    static let shared = MarketplaceManager()

    /// Fee split: 5% to NeoSafe platform, 95% to seller.
    static let platformFeePercent: Double = 0.05
    static let sellerSharePercent: Double = 0.95

    /// Appeals are escalated to the platform owner for review (stored locally; no channel wired yet).
    static let appealChannel = "owner-review"

    weak var delegate: MarketplaceDelegate?

    @Published private(set) var listings: [MarketListing] = []
    @Published private(set) var sales: [MarketSale] = []
    @Published private(set) var appeals: [MarketAppeal] = []
    @Published private(set) var isLoading = false

    private var listingStore: [String: MarketListing] = [:]
    private var appealStore: [String: MarketAppeal] = [:]

    /// Blocked terms for compliance filter. Extend as needed.
    private let prohibitedTerms: Set<String> = [
        "counterfeit", "illegal", "stolen", "prohibited", "sanctioned"
    ]

    // MARK: - Listing Creation with Compliance Filter

    func createListing(seller: String, title: String, description: String, category: ListingCategory, price: Double, currency: String, metadataURI: String? = nil) async throws -> MarketListing {
        let flags = runComplianceFilter(title: title, description: description)

        var listing = MarketListing(
            id: UUID().uuidString,
            sellerAddress: seller,
            title: title,
            description: description,
            category: category,
            price: price,
            currency: currency,
            createdAt: Date(),
            status: flags.isEmpty ? .active : .flagged,
            complianceFlags: flags,
            metadataURI: metadataURI
        )

        if !flags.isEmpty {
            listing.status = .flagged
            delegate?.marketplace(self, listingFlagged: listing, reason: "Compliance filter: \(flags.map(\.rawValue).joined(separator: ", "))")
        }

        listingStore[listing.id] = listing
        await MainActor.run { listings.append(listing) }
        delegate?.marketplace(self, listingCreated: listing)
        return listing
    }

    // MARK: - Purchase (5% NeoSafe / 95% Seller)

    func purchase(listingId: String, buyerAddress: String, paymentAmount: Double) async throws -> MarketSale {
        guard var listing = listingStore[listingId] else {
            throw MarketplaceError.listingNotFound(listingId)
        }
        guard listing.status == .active else {
            throw MarketplaceError.listingNotActive
        }
        guard listing.sellerAddress != buyerAddress else {
            throw MarketplaceError.sellerCannotBuy
        }
        guard paymentAmount >= listing.price else {
            throw MarketplaceError.insufficientPayment
        }

        let platformFee = listing.price * Self.platformFeePercent
        let sellerProceeds = listing.price * Self.sellerSharePercent

        listing.status = .sold
        listingStore[listingId] = listing

        let sale = MarketSale(
            id: UUID().uuidString,
            listingId: listingId,
            sellerAddress: listing.sellerAddress,
            buyerAddress: buyerAddress,
            salePrice: listing.price,
            sellerProceeds: sellerProceeds,
            platformFee: platformFee,
            timestamp: Date(),
            txHash: nil
        )

        await MainActor.run { sales.append(sale) }
        await updateListingInPublished(listing)
        delegate?.marketplace(self, saleCompleted: sale)
        return sale
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `purchase(uint256 listingId)`.
    static func encodePurchase(listingId: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("purchase(uint256)")
        data.append(ABIEncoder.encodeUInt256(listingId))
        return data
    }

    /// Buy a listing on-chain through the real submit pipeline: enclave-signed
    /// UserOp → server paymaster → bundler. `paymentWei` is the price sent with
    /// the call (user-signed self-custody). Contract address deferred to
    /// PendingCredentials (nil until set → throws, never a fake purchase).
    @MainActor
    func purchaseOnChain(
        listingId: UInt64,
        paymentWei: UInt64 = 0,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.marketplace)
    ) async throws -> WalletTransactionService.Submission {
        guard let marketplace = contract else { throw MarketplaceError.notConfigured }
        return try await service.submitCall(
            to: marketplace,
            value: paymentWei,
            data: Self.encodePurchase(listingId: listingId),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Compliance Filter

    /// Simple content filter. Returns compliance flags if violations detected.
    func runComplianceFilter(title: String, description: String) -> [ComplianceFlag] {
        var flags: [ComplianceFlag] = []
        let content = (title + " " + description).lowercased()

        for term in prohibitedTerms {
            if content.contains(term) {
                flags.append(.prohibited)
                break
            }
        }

        return flags
    }

    /// Flag a listing for compliance violation.
    func flagListing(listingId: String, flags: [ComplianceFlag]) async throws {
        guard var listing = listingStore[listingId] else {
            throw MarketplaceError.listingNotFound(listingId)
        }
        listing.status = .flagged
        listing.complianceFlags = flags
        listingStore[listingId] = listing
        await updateListingInPublished(listing)
        delegate?.marketplace(self, listingFlagged: listing, reason: flags.map(\.rawValue).joined(separator: ", "))
    }

    /// Remove a flagged listing.
    func removeListing(listingId: String) async throws {
        guard var listing = listingStore[listingId] else {
            throw MarketplaceError.listingNotFound(listingId)
        }
        listing.status = .removed
        listingStore[listingId] = listing
        await updateListingInPublished(listing)
    }

    // MARK: - Appeals (escalated to the platform owner)

    func fileAppeal(listingId: String, appellantAddress: String, reason: String) async throws -> MarketAppeal {
        guard listingStore[listingId] != nil else {
            throw MarketplaceError.listingNotFound(listingId)
        }
        if appealStore.values.contains(where: { $0.listingId == listingId && $0.status == .filed }) {
            throw MarketplaceError.appealAlreadyFiled
        }

        let appeal = MarketAppeal(
            id: UUID().uuidString,
            listingId: listingId,
            appellantAddress: appellantAddress,
            reason: reason,
            status: .filed,
            filedAt: Date(),
            escalationChannel: Self.appealChannel
        )

        appealStore[appeal.id] = appeal
        await MainActor.run { appeals.append(appeal) }
        delegate?.marketplace(self, appealFiled: appeal)
        return appeal
    }

    func resolveAppeal(appealId: String, approved: Bool) async throws {
        guard var appeal = appealStore[appealId] else { return }
        appeal.status = approved ? .approved : .rejected
        appealStore[appealId] = appeal

        if approved, var listing = listingStore[appeal.listingId] {
            listing.status = .active
            listing.complianceFlags = []
            listingStore[listing.id] = listing
            await updateListingInPublished(listing)
        }

        await MainActor.run {
            if let idx = appeals.firstIndex(where: { $0.id == appealId }) {
                appeals[idx] = appeal
            }
        }
    }

    // MARK: - Queries

    func getActiveListings(category: ListingCategory? = nil) -> [MarketListing] {
        listingStore.values.filter { listing in
            listing.status == .active && (category == nil || listing.category == category)
        }
    }

    func getSales(sellerAddress: String) -> [MarketSale] {
        sales.filter { $0.sellerAddress == sellerAddress }
    }

    // MARK: - Private

    @MainActor
    private func updateListingInPublished(_ listing: MarketListing) {
        if let idx = listings.firstIndex(where: { $0.id == listing.id }) {
            listings[idx] = listing
        }
    }
}
