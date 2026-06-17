// IPManager.swift
// MTRX Blockchain - Components - Intellectual Property (C15)
//
// IP registration with blockchain timestamping, royalty enforcement,
// 5% fee per 90-day period, qualifying transaction types.

import Foundation
import Combine

// MARK: - Protocols

protocol IPManagerDelegate: AnyObject {
    func ipManager(_ manager: IPManager, assetRegistered asset: IPAsset)
    func ipManager(_ manager: IPManager, royaltyCollected royalty: RoyaltyEvent)
    func ipManager(_ manager: IPManager, feeCharged fee: IPFeeEvent)
}

// MARK: - Data Models

enum IPType: String, Codable, CaseIterable {
    case patent, trademark, copyright, tradeSecret, design, software, music, artwork, literature
}

enum IPStatus: String, Codable {
    case pending, registered, disputed, revoked, expired
}

/// Qualifying transaction types that trigger royalty enforcement.
enum QualifyingTransactionType: String, Codable, CaseIterable {
    case sale
    case license
    case sublicense
    case commercialUse
    case derivative
    case syndication
}

struct IPAsset: Identifiable, Codable {
    let id: String
    let ownerAddress: String
    let title: String
    let description: String
    let type: IPType
    let contentHash: String           // SHA-256 of the original work
    let blockchainTimestamp: Date      // immutable proof of existence
    let registrationTxHash: String?
    var status: IPStatus
    let royaltyBasisPoints: UInt      // e.g. 500 = 5%
    var totalRoyaltiesEarned: Double
    var qualifyingTypes: [QualifyingTransactionType]
}

struct RoyaltyEvent: Identifiable, Codable {
    let id: String
    let assetId: String
    let payerAddress: String
    let amount: Double
    let transactionType: QualifyingTransactionType
    let txHash: String?
    let timestamp: Date
}

struct IPFeeEvent: Identifiable, Codable {
    let id: String
    let assetId: String
    let feeAmount: Double
    let periodStart: Date
    let periodEnd: Date              // +90 days
    let chargedAt: Date
}

enum IPError: Error, LocalizedError {
    case assetNotFound(String)
    case alreadyRegistered
    case invalidContentHash
    case royaltyEnforcementFailed(String)
    case feePeriodNotElapsed
    case assetRevoked
    case nonQualifyingTransaction
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .assetNotFound(let id): return "IP asset not found: \(id)"
        case .alreadyRegistered: return "Content hash already registered on chain."
        case .invalidContentHash: return "Content hash is invalid."
        case .royaltyEnforcementFailed(let r): return "Royalty enforcement failed: \(r)"
        case .feePeriodNotElapsed: return "90-day fee period has not yet elapsed."
        case .assetRevoked: return "IP asset has been revoked."
        case .nonQualifyingTransaction: return "Transaction type does not qualify for royalty."
        case .notConfigured: return "IP registry not configured (PendingCredentials.Components.ip)."
        }
    }
}

// MARK: - IPManager

final class IPManager: ObservableObject {

    static let shared = IPManager()

    /// Platform fee: 5% per 90-day period
    static let platformFeePercent: Double = 0.05
    static let feePeriodDays: Int = 90

    weak var delegate: IPManagerDelegate?

    @Published private(set) var assets: [IPAsset] = []
    @Published private(set) var royalties: [RoyaltyEvent] = []
    @Published private(set) var fees: [IPFeeEvent] = []
    @Published private(set) var isLoading = false

    private var assetStore: [String: IPAsset] = [:]
    private var contentHashIndex: Set<String> = []
    private var lastFeeDate: [String: Date] = [:]   // assetId -> last fee charge date

    // MARK: - Registration with Blockchain Timestamping

    /// Register an IP asset. The blockchain timestamp serves as immutable proof of existence.
    func registerIPAsset(owner: String, title: String, description: String, type: IPType, contentHash: String, royaltyBasisPoints: UInt = 500, qualifyingTypes: [QualifyingTransactionType] = QualifyingTransactionType.allCases) async throws -> IPAsset {
        guard contentHash.count == 64 else {
            throw IPError.invalidContentHash
        }
        guard !contentHashIndex.contains(contentHash) else {
            throw IPError.alreadyRegistered
        }

        let asset = IPAsset(
            id: UUID().uuidString,
            ownerAddress: owner,
            title: title,
            description: description,
            type: type,
            contentHash: contentHash,
            blockchainTimestamp: Date(),
            registrationTxHash: nil,
            status: .registered,
            royaltyBasisPoints: royaltyBasisPoints,
            totalRoyaltiesEarned: 0,
            qualifyingTypes: qualifyingTypes
        )

        contentHashIndex.insert(contentHash)
        assetStore[asset.id] = asset
        lastFeeDate[asset.id] = Date()

        await MainActor.run { assets.append(asset) }
        delegate?.ipManager(self, assetRegistered: asset)
        return asset
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `registerIP(address owner, bytes32 contentHash, uint256 royaltyBps)`.
    static func encodeRegisterIP(owner: String, contentHash: Data, royaltyBps: UInt64) -> Data {
        var hashWord = Data(repeating: 0, count: 32)
        let head = contentHash.prefix(32)
        hashWord.replaceSubrange(0..<head.count, with: head)
        var out = ABIEncoder.functionSelector("registerIP(address,bytes32,uint256)")
        out.append(ABIEncoder.encodeAddress(owner))
        out.append(hashWord)
        out.append(ABIEncoder.encodeUInt256(royaltyBps))
        return out
    }

    /// Register an IP asset on-chain through the real submit pipeline: enclave-signed
    /// UserOp → server paymaster → bundler. Registry address deferred to
    /// PendingCredentials (nil until set → throws, never a fake registration).
    @MainActor
    func registerIPOnChain(
        owner: String,
        contentHash: Data,
        royaltyBps: UInt64 = 500,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.ip)
    ) async throws -> WalletTransactionService.Submission {
        guard let registry = contract else { throw IPError.notConfigured }
        return try await service.submitCall(
            to: registry,
            value: 0,
            data: Self.encodeRegisterIP(owner: owner, contentHash: contentHash, royaltyBps: royaltyBps),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Royalty Enforcement

    /// Enforce royalty collection on a qualifying transaction.
    func collectRoyalty(assetId: String, payerAddress: String, transactionAmount: Double, transactionType: QualifyingTransactionType) async throws -> RoyaltyEvent {
        guard var asset = assetStore[assetId] else {
            throw IPError.assetNotFound(assetId)
        }
        guard asset.status == .registered else {
            throw IPError.assetRevoked
        }
        guard asset.qualifyingTypes.contains(transactionType) else {
            throw IPError.nonQualifyingTransaction
        }

        let royaltyAmount = transactionAmount * (Double(asset.royaltyBasisPoints) / 10_000.0)

        let event = RoyaltyEvent(
            id: UUID().uuidString,
            assetId: assetId,
            payerAddress: payerAddress,
            amount: royaltyAmount,
            transactionType: transactionType,
            txHash: nil,
            timestamp: Date()
        )

        asset.totalRoyaltiesEarned += royaltyAmount
        assetStore[assetId] = asset

        await MainActor.run {
            royalties.append(event)
            if let idx = assets.firstIndex(where: { $0.id == assetId }) {
                assets[idx] = asset
            }
        }
        delegate?.ipManager(self, royaltyCollected: event)
        return event
    }

    // MARK: - 5% Fee per 90-Day Period

    /// Charge the platform fee (5%) based on royalties earned in the last 90 days.
    func chargePeriodFee(assetId: String) async throws -> IPFeeEvent {
        guard let asset = assetStore[assetId] else {
            throw IPError.assetNotFound(assetId)
        }

        let lastCharged = lastFeeDate[assetId] ?? asset.blockchainTimestamp
        let periodEnd = Calendar.current.date(byAdding: .day, value: Self.feePeriodDays, to: lastCharged)!

        guard Date() >= periodEnd else {
            throw IPError.feePeriodNotElapsed
        }

        // Sum royalties in this 90-day window
        let periodRoyalties = royalties.filter {
            $0.assetId == assetId && $0.timestamp >= lastCharged && $0.timestamp <= periodEnd
        }
        let totalRoyalties = periodRoyalties.reduce(0.0) { $0 + $1.amount }
        let feeAmount = totalRoyalties * Self.platformFeePercent

        let feeEvent = IPFeeEvent(
            id: UUID().uuidString,
            assetId: assetId,
            feeAmount: feeAmount,
            periodStart: lastCharged,
            periodEnd: periodEnd,
            chargedAt: Date()
        )

        lastFeeDate[assetId] = periodEnd

        await MainActor.run { fees.append(feeEvent) }
        delegate?.ipManager(self, feeCharged: feeEvent)
        return feeEvent
    }

    // MARK: - Queries

    func verifyTimestamp(assetId: String) -> Date? {
        assetStore[assetId]?.blockchainTimestamp
    }

    func lookupByContentHash(_ hash: String) -> IPAsset? {
        assetStore.values.first { $0.contentHash == hash }
    }

    func getAssetsForOwner(_ address: String) -> [IPAsset] {
        assetStore.values.filter { $0.ownerAddress == address }
    }

    func getRoyalties(assetId: String) -> [RoyaltyEvent] {
        royalties.filter { $0.assetId == assetId }
    }

    func revokeAsset(assetId: String) async throws {
        guard var asset = assetStore[assetId] else {
            throw IPError.assetNotFound(assetId)
        }
        asset.status = .revoked
        assetStore[assetId] = asset
        await MainActor.run {
            if let idx = assets.firstIndex(where: { $0.id == assetId }) {
                assets[idx] = asset
            }
        }
    }
}
