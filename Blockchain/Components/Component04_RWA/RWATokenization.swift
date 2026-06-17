// RWATokenization.swift
// MTRX Blockchain - Components - RWA
//
// Real world asset tokenization: property, commodity, receivables

import Foundation

// MARK: - Protocols

protocol RWATokenizationDelegate: AnyObject {
    func rwa(_ manager: RWATokenization, didTokenize assetId: String)
    func rwa(_ manager: RWATokenization, didFailWithError error: RWAError)
}

// MARK: - Data Models

enum RWAAssetType: String, Codable {
    case realEstate, commodity, receivable, equipment, vehicle, artwork, collectible
}

struct RWAAsset {
    let assetId: String
    let assetType: RWAAssetType
    let name: String
    let description: String
    let valuationUSD: Double
    let tokenAddress: String?
    let totalShares: UInt64
    let availableShares: UInt64
    let documents: [AssetDocument]
    let appraisalDate: Date
    let status: TokenizationStatus
}

struct AssetDocument {
    let documentId: String
    let name: String
    let documentType: String // deed, appraisal, insurance, legal
    let ipfsHash: String
    let attestationUID: String?
}

enum TokenizationStatus: String {
    case draft, underReview, approved, tokenized, trading, redeemed
}

struct ShareholderPosition {
    let holder: String
    let assetId: String
    let shares: UInt64
    let purchasePrice: Double
    let acquiredAt: Date
}

enum RWAError: Error, LocalizedError {
    case assetNotFound
    case valuationExpired
    case insufficientShares
    case complianceFailed(reason: String)
    case documentMissing(docType: String)
    case tokenizationFailed
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .assetNotFound: return "RWA asset not found."
        case .valuationExpired: return "Asset valuation has expired."
        case .insufficientShares: return "Insufficient shares available."
        case .complianceFailed(let r): return "Compliance check failed: \(r)"
        case .documentMissing(let t): return "Required document missing: \(t)"
        case .tokenizationFailed: return "Asset tokenization failed."
        case .notConfigured: return "RWA contract not configured (PendingCredentials.Components.rwa)."
        }
    }
}

// MARK: - RWATokenization

final class RWATokenization {

    // MARK: - Properties

    weak var delegate: RWATokenizationDelegate?

    private let erc4337Manager: ERC4337Manager
    private let easManager: EASManager
    private var assets: [String: RWAAsset] = [:]
    private var positions: [String: [ShareholderPosition]] = [:]
    private let processingQueue = DispatchQueue(label: "com.mtrx.rwa", qos: .userInitiated)

    // MARK: - Initialization

    init(erc4337Manager: ERC4337Manager, easManager: EASManager) {
        self.erc4337Manager = erc4337Manager
        self.easManager = easManager
    }

    // MARK: - Asset Registration

    /// Register a new real world asset for tokenization
    func registerAsset(name: String, assetType: RWAAssetType, valuationUSD: Double, totalShares: UInt64, documents: [AssetDocument], completion: @escaping (Result<RWAAsset, RWAError>) -> Void) {
        processingQueue.async { [weak self] in
            // Validate required documents
            let requiredDocs = self?.requiredDocuments(for: assetType) ?? []
            for docType in requiredDocs {
                guard documents.contains(where: { $0.documentType == docType }) else {
                    completion(.failure(.documentMissing(docType: docType)))
                    return
                }
            }

            let asset = RWAAsset(
                assetId: UUID().uuidString, assetType: assetType, name: name,
                description: "", valuationUSD: valuationUSD, tokenAddress: nil,
                totalShares: totalShares, availableShares: totalShares,
                documents: documents, appraisalDate: Date(), status: .draft
            )
            self?.assets[asset.assetId] = asset
            completion(.success(asset))
        }
    }

    /// Tokenize a registered asset on-chain
    func tokenizeAsset(assetId: String, completion: @escaping (Result<RWAAsset, RWAError>) -> Void) {
        guard let asset = assets[assetId] else {
            completion(.failure(.assetNotFound))
            return
        }
        // TODO: Deploy ERC-1155 token contract, create attestation for asset provenance
        _ = asset
        delegate?.rwa(self, didTokenize: assetId)
        completion(.failure(.tokenizationFailed))
    }

    // MARK: - Trading

    /// Purchase shares of a tokenized asset
    func purchaseShares(assetId: String, buyer: String, shares: UInt64, completion: @escaping (Result<ShareholderPosition, RWAError>) -> Void) {
        guard let asset = assets[assetId], asset.availableShares >= shares else {
            completion(.failure(.insufficientShares))
            return
        }
        // TODO: Execute share transfer via ERC-4337
        completion(.failure(.tokenizationFailed))
    }

    /// Transfer shares between holders
    func transferShares(assetId: String, from: String, to: String, shares: UInt64, completion: @escaping (Result<Void, RWAError>) -> Void) {
        // TODO: Compliance check, execute transfer
        completion(.failure(.complianceFailed(reason: "Not implemented")))
    }

    // MARK: - On-chain execution (via the submit pipeline)
    //
    // SECURITIES NOTE: tokenized real-world-asset shares are securities-adjacent.
    // This path is USER-SIGNED SELF-CUSTODY only — the user signs the share
    // purchase with their own Secure Enclave key through the pipeline; the app
    // never holds funds or executes custodially. (The 6 named regulated
    // components stay display-only; RWA is wired self-custody and gated by
    // FeatureFlags.mvpMode upstream.)

    /// ABI-encode `purchaseShares(uint256 assetId, uint256 shares)`.
    static func encodePurchaseShares(assetId: UInt64, shares: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("purchaseShares(uint256,uint256)")
        data.append(ABIEncoder.encodeUInt256(assetId))
        data.append(ABIEncoder.encodeUInt256(shares))
        return data
    }

    /// Purchase shares on-chain through the real submit pipeline: enclave-signed
    /// UserOp → server paymaster → bundler. `paymentWei` is the share price sent
    /// with the call. Contract address deferred to PendingCredentials (nil until
    /// set → throws, never a fake purchase). Static: needs no instance state.
    @MainActor
    static func purchaseSharesOnChain(
        assetId: UInt64,
        shares: UInt64,
        paymentWei: UInt64 = 0,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.rwa)
    ) async throws -> WalletTransactionService.Submission {
        guard let rwa = contract else { throw RWAError.notConfigured }
        return try await service.submitCall(
            to: rwa,
            value: paymentWei,
            data: encodePurchaseShares(assetId: assetId, shares: shares),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Query

    func getAsset(id: String) -> RWAAsset? { return assets[id] }
    func getPositions(for holder: String) -> [ShareholderPosition] {
        return positions.values.flatMap { $0 }.filter { $0.holder == holder }
    }

    // MARK: - Private

    private func requiredDocuments(for type: RWAAssetType) -> [String] {
        switch type {
        case .realEstate: return ["deed", "appraisal", "insurance", "legal"]
        case .commodity: return ["certificate", "appraisal"]
        case .receivable: return ["invoice", "legal"]
        default: return ["appraisal"]
        }
    }
}
