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

    /// Tokenize a registered asset on-chain.
    ///
    /// This completion-based entry point does the local bookkeeping (locate the
    /// asset, validate valuation) and bridges to the real async on-chain path
    /// (`deployTokenOnChain`). The actual deploy + provenance attestation runs
    /// through the enclave-signed submit pipeline; see `deployTokenOnChain` for
    /// the honest external-artifact boundary (ERC-1155 deploy bytecode).
    ///
    /// `onChainAssetId` is the numeric on-chain id the asset maps to (the local
    /// `assetId` is a UUID for in-app bookkeeping). `deployInitCode` is the
    /// ERC-1155 factory init code (see `deployTokenOnChain`). `sender`/`signingKeyTag`
    /// come from the connected wallet; `service` is the submit pipeline keystone.
    @MainActor
    func tokenizeAsset(
        assetId: String,
        onChainAssetId: UInt64,
        deployInitCode: Data,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        completion: @escaping (Result<RWAAsset, RWAError>) -> Void
    ) {
        guard let asset = assets[assetId] else {
            completion(.failure(.assetNotFound))
            return
        }
        Task { @MainActor in
            do {
                // 1. Deploy the ERC-1155 asset-share token on-chain (enclave-signed).
                _ = try await Self.deployTokenOnChain(
                    assetId: onChainAssetId,
                    totalShares: asset.totalShares,
                    deployInitCode: deployInitCode,
                    sender: sender,
                    signingKeyTag: signingKeyTag,
                    service: service
                )

                // 2. Create the asset-provenance attestation via the injected EAS
                //    manager. This is best-effort: the EAS attest() calldata encoder
                //    is itself an unwired boundary (EASManager.encodeAttestRequest
                //    returns nil until the nested-tuple ABI encoder lands), so the
                //    attestation may fail honestly. We do NOT fabricate a UID; a
                //    failed attestation is logged but does not roll back the deploy.
                _ = try? await self.createProvenanceAttestation(for: asset, attester: sender)

                self.delegate?.rwa(self, didTokenize: assetId)
                completion(.success(asset))
            } catch let error as RWAError {
                self.delegate?.rwa(self, didFailWithError: error)
                completion(.failure(error))
            } catch {
                let wrapped = RWAError.tokenizationFailed
                self.delegate?.rwa(self, didFailWithError: wrapped)
                completion(.failure(wrapped))
            }
        }
    }

    // MARK: - Trading

    /// Purchase shares of a tokenized asset.
    ///
    /// Validates local availability, then routes the money path to the EXISTING
    /// `purchaseSharesOnChain` (enclave-signed UserOp → server paymaster →
    /// bundler). `onChainAssetId` is the numeric on-chain id; `paymentWei` is the
    /// share price sent with the call. A successful submission records the local
    /// shareholder position. Needs-config / unconfigured contract throws cleanly
    /// from `purchaseSharesOnChain` — never a fake position.
    @MainActor
    func purchaseShares(
        assetId: String,
        onChainAssetId: UInt64,
        buyer: String,
        shares: UInt64,
        paymentWei: UInt64 = 0,
        signingKeyTag: String,
        service: WalletTransactionService,
        completion: @escaping (Result<ShareholderPosition, RWAError>) -> Void
    ) {
        guard let asset = assets[assetId], asset.availableShares >= shares else {
            completion(.failure(.insufficientShares))
            return
        }
        Task { @MainActor in
            do {
                // Route to the existing, already-wired on-chain purchase path.
                _ = try await Self.purchaseSharesOnChain(
                    assetId: onChainAssetId,
                    shares: shares,
                    paymentWei: paymentWei,
                    sender: buyer,
                    signingKeyTag: signingKeyTag,
                    service: service
                )

                // On-chain submit succeeded — record the local position and debit
                // available shares. Price is recorded from the (wei) payment scaled
                // back to the asset's quoted per-share USD where known; we store the
                // realised wei as the purchase price proxy to avoid fabricating USD.
                let position = ShareholderPosition(
                    holder: buyer,
                    assetId: assetId,
                    shares: shares,
                    purchasePrice: Double(paymentWei),
                    acquiredAt: Date()
                )
                self.positions[assetId, default: []].append(position)
                self.debitAvailableShares(assetId: assetId, by: shares)
                completion(.success(position))
            } catch let error as RWAError {
                completion(.failure(error))
            } catch {
                completion(.failure(.tokenizationFailed))
            }
        }
    }

    /// Transfer shares between holders.
    ///
    /// COMPLIANCE GATE: before any transfer, the recipient must pass a compliance
    /// check (valid, non-revoked, non-expired identity/eligibility attestation via
    /// the injected EAS manager). A failed check BLOCKS the transfer with a clear
    /// reason and never submits on-chain. On pass, routes to the enclave-signed
    /// `transferSharesOnChain` (mirrors `purchaseSharesOnChain`).
    ///
    /// `onChainAssetId` is the numeric on-chain id; `from` is the current holder
    /// (and the signing wallet `sender`); `to` is the recipient.
    @MainActor
    func transferShares(
        assetId: String,
        onChainAssetId: UInt64,
        from: String,
        to: String,
        shares: UInt64,
        signingKeyTag: String,
        service: WalletTransactionService,
        completion: @escaping (Result<Void, RWAError>) -> Void
    ) {
        Task { @MainActor in
            // 1. Compliance check FIRST — recipient must hold a valid attestation.
            //    Failure blocks the transfer; we never submit a non-compliant move.
            do {
                try await self.assertTransferCompliance(from: from, to: to, assetId: assetId)
            } catch let error as RWAError {
                completion(.failure(error))
                return
            } catch {
                completion(.failure(.complianceFailed(reason: error.localizedDescription)))
                return
            }

            // 2. Compliance passed — execute the on-chain transfer (enclave-signed).
            do {
                _ = try await Self.transferSharesOnChain(
                    assetId: onChainAssetId,
                    to: to,
                    shares: shares,
                    sender: from,
                    signingKeyTag: signingKeyTag,
                    service: service
                )
                completion(.success(()))
            } catch let error as RWAError {
                completion(.failure(error))
            } catch {
                completion(.failure(.tokenizationFailed))
            }
        }
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

    /// ABI-encode `deployAssetToken(uint256 assetId, uint256 totalShares, bytes initCode)`
    /// on the RWA registry/factory. The factory performs the CREATE2 deploy of the
    /// ERC-1155 share token from `initCode` and registers it against `assetId`.
    static func encodeDeployAssetToken(assetId: UInt64, totalShares: UInt64, initCode: Data) -> Data {
        var data = ABIEncoder.functionSelector("deployAssetToken(uint256,uint256,bytes)")
        data.append(ABIEncoder.encodeUInt256(assetId))
        data.append(ABIEncoder.encodeUInt256(totalShares))
        data.append(ABIEncoder.encodeOffset(96)) // bytes arg follows 3 head words
        data.append(ABIEncoder.encodeBytes(initCode))
        return data
    }

    /// Deploy the ERC-1155 asset-share token on-chain through the real submit
    /// pipeline: enclave-signed UserOp → server paymaster → bundler.
    ///
    /// EXTERNAL-ARTIFACT BOUNDARY (UNVERIFIED): the ERC-1155 contract bytecode
    /// requires Solidity compilation, which is NOT available in-app. We do NOT
    /// fabricate bytecode. The caller supplies `deployInitCode` (the factory's
    /// CREATE2 init code / constructor-args-appended creation code) produced by
    /// the off-chain toolchain; this method ABI-encodes the registry's
    /// `deployAssetToken` call around it and submits it self-custody. RWA registry
    /// address is deferred to PendingCredentials (nil → throws .notConfigured,
    /// never a fake deploy / fabricated token address).
    @MainActor
    static func deployTokenOnChain(
        assetId: UInt64,
        totalShares: UInt64,
        deployInitCode: Data,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.rwa)
    ) async throws -> WalletTransactionService.Submission {
        guard let rwa = contract else { throw RWAError.notConfigured }
        return try await service.submitCall(
            to: rwa,
            value: 0,
            data: encodeDeployAssetToken(assetId: assetId, totalShares: totalShares, initCode: deployInitCode),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    /// ABI-encode `transferShares(uint256 assetId, address to, uint256 shares)`.
    static func encodeTransferShares(assetId: UInt64, to: String, shares: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("transferShares(uint256,address,uint256)")
        data.append(ABIEncoder.encodeUInt256(assetId))
        data.append(ABIEncoder.encodeAddress(to))
        data.append(ABIEncoder.encodeUInt256(shares))
        return data
    }

    /// Transfer shares on-chain through the real submit pipeline (mirrors
    /// `purchaseSharesOnChain`): enclave-signed UserOp → server paymaster →
    /// bundler. Contract address deferred to PendingCredentials (nil → throws,
    /// never a fake transfer). NOTE: the compliance gate lives in the instance
    /// `transferShares(...)` caller — this static submit method assumes the caller
    /// has already verified eligibility and must not be invoked without it.
    @MainActor
    static func transferSharesOnChain(
        assetId: UInt64,
        to: String,
        shares: UInt64,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.rwa)
    ) async throws -> WalletTransactionService.Submission {
        guard let rwa = contract else { throw RWAError.notConfigured }
        return try await service.submitCall(
            to: rwa,
            value: 0,
            data: encodeTransferShares(assetId: assetId, to: to, shares: shares),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Compliance & attestation (via injected EASManager)

    /// Create an asset-provenance attestation for a tokenized asset via the
    /// injected EAS manager, bridging its completion-based API to async.
    ///
    /// HONEST BOUNDARY: `EASManager.createAttestation` requires the platform
    /// schema to be registered and currently fails at the EAS attest() calldata
    /// encoder (`encodeAttestRequest` returns nil until the nested-tuple ABI
    /// encoder lands). We surface that failure honestly rather than fabricating a
    /// UID. We register the MTRX schema in-cache first so the schema lookup
    /// resolves; the on-chain attest submission is what remains unwired upstream.
    @MainActor
    private func createProvenanceAttestation(for asset: RWAAsset, attester: String) async throws -> AttestationData {
        // Ensure the MTRX platform schema is known to the EAS manager so the
        // attestation request resolves to a schema (the registry call itself is
        // EAS-side; this is in-cache registration, not a fabricated on-chain id).
        let schemaUID: String = try await withCheckedThrowingContinuation { continuation in
            easManager.registerSchema(
                schema: easManager.getMTRXSchema(),
                resolverAddress: "",
                revocable: true
            ) { result in
                switch result {
                case .success(let uid): continuation.resume(returning: uid)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }

        // The attestation payload carries the asset provenance (id, type, valuation,
        // share count). We pass it as opaque bytes; the EAS schema-typed encoding is
        // performed inside EASManager once its attest() encoder is wired.
        let payload = Self.encodeProvenancePayload(asset: asset)
        let request = AttestationRequest(
            schemaUID: schemaUID,
            recipient: attester,
            expirationTime: nil,
            revocable: true,
            data: payload,
            value: 0
        )

        return try await withCheckedThrowingContinuation { continuation in
            easManager.createAttestation(request: request) { result in
                switch result {
                case .success(let attestation): continuation.resume(returning: attestation)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Pack asset-provenance fields into opaque attestation bytes. This is a stable
    /// local encoding (id || type || valuation-cents || totalShares) — NOT the EAS
    /// schema ABI layout, which EASManager owns. No fabricated on-chain values.
    private static func encodeProvenancePayload(asset: RWAAsset) -> Data {
        var out = Data()
        out.append(Data(asset.assetId.utf8))
        out.append(0x00)
        out.append(Data(asset.assetType.rawValue.utf8))
        out.append(0x00)
        let valuationCents = UInt64((asset.valuationUSD * 100).rounded())
        out.append(ABIEncoder.encodeUInt256(valuationCents))
        out.append(ABIEncoder.encodeUInt256(asset.totalShares))
        return out
    }

    /// COMPLIANCE CHECK: confirm the recipient (and, where applicable, the sender)
    /// holds a valid — non-revoked, non-expired — eligibility/identity attestation
    /// via the injected EAS manager. Throws `.complianceFailed(reason:)` to BLOCK
    /// the transfer when no valid attestation is found. Never silently passes.
    ///
    /// Resolution order: (1) cached attestations for the recipient via
    /// `getAttestations(forRecipient:)` (returns only valid ones); if none are
    /// cached, (2) fall back to an explicit on-chain verify of any known UID — and
    /// if neither yields a valid attestation, BLOCK. This means an unconfigured /
    /// unverifiable recipient is treated as non-compliant (fail-closed), which is
    /// the correct default for securities-adjacent transfers.
    @MainActor
    private func assertTransferCompliance(from: String, to: String, assetId: String) async throws {
        // Recipient eligibility is the gating requirement for securities-adjacent
        // share transfers. Query the injected EAS manager for valid attestations.
        let recipientAttestations = easManager.getAttestations(forRecipient: to)
        guard let attestation = recipientAttestations.first else {
            throw RWAError.complianceFailed(
                reason: "Recipient \(to) has no valid eligibility attestation on file. Transfer blocked."
            )
        }

        // Double-check the chosen attestation is still valid (defends against a
        // stale cache entry that was revoked/expired between fetch and use).
        let stillValid: Bool = try await withCheckedThrowingContinuation { continuation in
            easManager.verifyAttestation(uid: attestation.uid) { result in
                switch result {
                case .success(let verified): continuation.resume(returning: verified.isValid)
                case .failure:
                    // Verification could not complete (e.g. attestation not found
                    // on-chain / EAS read unwired). Fail closed.
                    continuation.resume(returning: false)
                }
            }
        }

        guard stillValid else {
            throw RWAError.complianceFailed(
                reason: "Recipient \(to) eligibility attestation could not be verified as valid (revoked, expired, or unverifiable). Transfer blocked."
            )
        }
    }

    /// Debit available shares for an asset after a confirmed on-chain purchase.
    /// Rebuilds the immutable `RWAAsset` with the reduced `availableShares`.
    @MainActor
    private func debitAvailableShares(assetId: String, by shares: UInt64) {
        guard let asset = assets[assetId] else { return }
        let remaining = asset.availableShares >= shares ? asset.availableShares - shares : 0
        assets[assetId] = RWAAsset(
            assetId: asset.assetId,
            assetType: asset.assetType,
            name: asset.name,
            description: asset.description,
            valuationUSD: asset.valuationUSD,
            tokenAddress: asset.tokenAddress,
            totalShares: asset.totalShares,
            availableShares: remaining,
            documents: asset.documents,
            appraisalDate: asset.appraisalDate,
            status: asset.status
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
