// NFTManager.swift
// MTRX Blockchain - Components - NFT
//
// NFT minting, trading, and display: ERC-721/1155 operations

import Foundation

// MARK: - Protocols

protocol NFTManagerDelegate: AnyObject {
    func nftManager(_ manager: NFTManager, didMint tokenId: String, collection: String)
    func nftManager(_ manager: NFTManager, didTransfer tokenId: String, to: String)
    func nftManager(_ manager: NFTManager, didFailWithError error: NFTError)
}

// MARK: - Data Models

enum NFTStandard: String { case erc721, erc1155 }

struct NFTMetadata: Codable {
    let name: String
    let description: String
    let image: String
    let animationURL: String?
    let externalURL: String?
    let attributes: [NFTAttribute]
}

struct NFTAttribute: Codable {
    let traitType: String
    let value: String
    let displayType: String?
}

struct NFTToken {
    let tokenId: String
    let contractAddress: String
    let standard: NFTStandard
    let owner: String
    let metadata: NFTMetadata?
    let amount: UInt64 // 1 for ERC-721, variable for ERC-1155
    let royaltyBPS: UInt16
    let createdAt: Date
}

struct NFTCollection {
    let contractAddress: String
    let name: String
    let symbol: String
    let standard: NFTStandard
    let totalSupply: UInt64
    let maxSupply: UInt64?
    let baseURI: String
    let owner: String
}

struct NFTListing {
    let listingId: String
    let token: NFTToken
    let price: UInt64
    let currency: String
    let seller: String
    let expiresAt: Date?
    let isActive: Bool
}

enum NFTError: Error, LocalizedError {
    case mintFailed(reason: String)
    case transferFailed
    case notOwner
    case collectionNotFound
    case tokenNotFound
    case metadataUploadFailed
    case approvalRequired
    case invalidRoyalty

    var errorDescription: String? {
        switch self {
        case .mintFailed(let r): return "Mint failed: \(r)"
        case .transferFailed: return "NFT transfer failed."
        case .notOwner: return "Caller is not the token owner."
        case .collectionNotFound: return "NFT collection not found."
        case .tokenNotFound: return "Token not found."
        case .metadataUploadFailed: return "Failed to upload metadata."
        case .approvalRequired: return "Token approval required."
        case .invalidRoyalty: return "Invalid royalty configuration."
        }
    }
}

// MARK: - NFTManager

final class NFTManager {

    // MARK: - Properties

    weak var delegate: NFTManagerDelegate?

    private let erc4337Manager: ERC4337Manager
    private var collections: [String: NFTCollection] = [:]
    private var tokens: [String: NFTToken] = [:]
    private var listings: [String: NFTListing] = [:]
    private let processingQueue = DispatchQueue(label: "com.mtrx.nft", qos: .userInitiated)

    // MARK: - Initialization

    init(erc4337Manager: ERC4337Manager) {
        self.erc4337Manager = erc4337Manager
    }

    // MARK: - Collection Management

    /// Deploy a new NFT collection contract.
    ///
    /// Bridges the completion API to the real on-chain `deployCollectionOnChain`
    /// path: enclave-signed UserOp → server paymaster → bundler. `sender` is the
    /// user's smart-account address and `signingKeyTag` their Secure Enclave key
    /// tag; both must be supplied for a real deploy. A live `WalletTransactionService`
    /// is required — when the chain core is unconfigured `WalletTransactionService.init?`
    /// returns nil and we surface a clear "needs config" error rather than faking a
    /// deployment.
    ///
    /// HONEST BOUNDARY: the deployed collection's contract address is only known
    /// after the factory tx is mined (read it from the UserOperation receipt logs
    /// via ERC4337Manager.getOperationReceipt). We never fabricate it here, so this
    /// reports the submission (userOpHash); the address-bearing NFTCollection is
    /// materialised once the receipt is observed. Until then the returned collection
    /// carries the userOpHash as its provisional identifier.
    func createCollection(name: String, symbol: String, standard: NFTStandard, maxSupply: UInt64?, baseURI: String, royaltyBPS: UInt16, sender: String, signingKeyTag: String, completion: @escaping (Result<NFTCollection, NFTError>) -> Void) {
        Task { @MainActor in
            // WalletTransactionService.init? is @MainActor — construct on the main actor.
            guard let service = WalletTransactionService() else {
                completion(.failure(.mintFailed(reason: "On-chain config not set — fill PendingCredentials (chain + NFT factory)")))
                return
            }
            do {
                let submission = try await Self.deployCollectionOnChain(
                    name: name,
                    symbol: symbol,
                    standard: standard,
                    maxSupply: maxSupply ?? 0,
                    baseURI: baseURI,
                    royaltyBPS: royaltyBPS,
                    sender: sender,
                    signingKeyTag: signingKeyTag,
                    service: service
                )
                // Provisional record keyed by the userOpHash. The on-chain contract
                // address is resolved from the receipt (CollectionDeployed log) — not
                // invented. `owner` is the deploying smart account.
                let collection = NFTCollection(
                    contractAddress: submission.userOpHash, // provisional id until receipt resolves the real address
                    name: name,
                    symbol: symbol,
                    standard: standard,
                    totalSupply: 0,
                    maxSupply: maxSupply,
                    baseURI: baseURI,
                    owner: sender
                )
                self.collections[submission.userOpHash] = collection
                completion(.success(collection))
            } catch {
                completion(.failure(.mintFailed(reason: "Collection deploy failed: \(error.localizedDescription)")))
            }
        }
    }

    /// Fetch collection details
    func getCollection(address: String) -> Result<NFTCollection, NFTError> {
        guard let collection = collections[address] else { return .failure(.collectionNotFound) }
        return .success(collection)
    }

    // MARK: - Minting

    /// Mint a new NFT.
    ///
    /// HONEST BOUNDARY — IPFS: metadata is NOT uploaded in-app. The token-URI
    /// (e.g. `ipfs://<cid>`) is an INPUT (`metadataURI`); the caller pins the JSON
    /// to IPFS out of band and passes the resulting URI here. We ABI-encode the
    /// mint and route it through the real submit pipeline via `mintOnChain`.
    ///
    /// `sender` is the user's smart-account address, `signingKeyTag` their Secure
    /// Enclave key tag. When the chain core / NFT contract is unconfigured the
    /// pipeline throws a clear "needs config" error — never a fake mint.
    func mint(collectionAddress: String, to: String, metadataURI: String, amount: UInt64 = 1, sender: String, signingKeyTag: String, completion: @escaping (Result<NFTToken, NFTError>) -> Void) {
        Task { @MainActor in
            // WalletTransactionService.init? is @MainActor — construct it here so the
            // chain-config gate runs on the main actor (nil → clear "needs config").
            guard let service = WalletTransactionService() else {
                completion(.failure(.mintFailed(reason: "On-chain config not set — fill PendingCredentials (chain + NFT contract)")))
                return
            }
            do {
                // Use the collection address as the target contract when provided,
                // otherwise fall back to PendingCredentials.Components.nft inside mintOnChain.
                let contract = collectionAddress.isEmpty
                    ? PendingCredentials.filled(PendingCredentials.Components.nft)
                    : collectionAddress
                let submission = try await self.mintOnChain(
                    to: to,
                    amount: amount,
                    sender: sender,
                    signingKeyTag: signingKeyTag,
                    service: service,
                    contract: contract
                )
                // The minted tokenId is assigned on-chain (read from the receipt's
                // Transfer log) — not invented here. The provisional NFTToken carries
                // the userOpHash as its identifier and the supplied metadata URI.
                let provisionalMetadata = NFTMetadata(
                    name: "", description: "", image: metadataURI,
                    animationURL: nil, externalURL: metadataURI, attributes: []
                )
                let token = NFTToken(
                    tokenId: submission.userOpHash, // provisional until receipt resolves the on-chain tokenId
                    contractAddress: contract ?? collectionAddress,
                    standard: amount > 1 ? .erc1155 : .erc721,
                    owner: to,
                    metadata: provisionalMetadata,
                    amount: amount,
                    royaltyBPS: 0,
                    createdAt: Date()
                )
                self.delegate?.nftManager(self, didMint: submission.userOpHash, collection: collectionAddress)
                completion(.success(token))
            } catch {
                completion(.failure(.mintFailed(reason: error.localizedDescription)))
            }
        }
    }

    /// Batch mint multiple NFTs in a single enclave-signed batched UserOperation.
    ///
    /// HONEST BOUNDARY — IPFS: each entry's token-URI is an INPUT (`metadataURIs`);
    /// nothing is pinned in-app. We encode one `mint(address,uint256)` call per
    /// entry, pack them with `ERC4337Manager.buildBatchUserOperation`, and submit
    /// the batch through the enclave-signing path. NFT contract from
    /// PendingCredentials.Components.nft (nil → clear "needs config" error).
    func batchMint(collectionAddress: String, to: String, metadataURIs: [String], amountEach: UInt64 = 1, sender: String, signingKeyTag: String, completion: @escaping (Result<[NFTToken], NFTError>) -> Void) {
        let contractOpt = collectionAddress.isEmpty
            ? PendingCredentials.filled(PendingCredentials.Components.nft)
            : collectionAddress
        guard let contract = contractOpt else {
            completion(.failure(.mintFailed(reason: "NFT contract not configured (PendingCredentials.Components.nft)")))
            return
        }
        guard !metadataURIs.isEmpty else {
            completion(.failure(.mintFailed(reason: "No metadata URIs supplied for batch mint")))
            return
        }
        Task { @MainActor in
            do {
                // One mint call per requested token, all to the same recipient/contract.
                let calls: [(to: String, value: UInt64, data: Data)] = metadataURIs.map { _ in
                    (to: contract, value: UInt64(0), data: Self.encodeMint(to: to, amount: amountEach))
                }
                let submission = try await self.submitBatchOnChain(
                    calls: calls,
                    sender: sender,
                    signingKeyTag: signingKeyTag
                )
                // tokenIds are assigned on-chain (read from the receipt's Transfer
                // logs) — not invented. Provisional tokens carry the batch userOpHash.
                let tokens: [NFTToken] = metadataURIs.map { uri in
                    NFTToken(
                        tokenId: submission.userOpHash,
                        contractAddress: contract,
                        standard: amountEach > 1 ? .erc1155 : .erc721,
                        owner: to,
                        metadata: NFTMetadata(name: "", description: "", image: uri,
                                              animationURL: nil, externalURL: uri, attributes: []),
                        amount: amountEach,
                        royaltyBPS: 0,
                        createdAt: Date()
                    )
                }
                self.delegate?.nftManager(self, didMint: submission.userOpHash, collection: collectionAddress)
                completion(.success(tokens))
            } catch {
                completion(.failure(.mintFailed(reason: error.localizedDescription)))
            }
        }
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `mint(address to, uint256 amount)`.
    static func encodeMint(to: String, amount: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("mint(address,uint256)")
        data.append(ABIEncoder.encodeAddress(to))
        data.append(ABIEncoder.encodeUInt256(amount))
        return data
    }

    /// Mint on-chain through the real submit pipeline: enclave-signed
    /// UserOperation → server paymaster → bundler. The NFT contract comes from
    /// PendingCredentials (nil until set → throws, never a fake call). `service`
    /// and `contract` are injectable for tests.
    @MainActor
    func mintOnChain(
        to: String,
        amount: UInt64 = 1,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.nft)
    ) async throws -> WalletTransactionService.Submission {
        guard let nftContract = contract else {
            throw NFTError.mintFailed(reason: "NFT contract not configured (PendingCredentials.Components.nft)")
        }
        return try await service.submitCall(
            to: nftContract,
            value: 0,
            data: Self.encodeMint(to: to, amount: amount),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Collection deploy (on-chain, via factory)

    /// ABI-encode the collection-factory deploy call
    /// `deployCollection(string name, string symbol, uint256 maxSupply, string baseURI, uint96 royaltyBPS)`.
    ///
    /// Two `string` args are dynamic. Head layout (5 words):
    ///   [0] offset(name)  [1] offset(symbol)  [2] maxSupply
    ///   [3] royaltyBPS    [4] offset(baseURI)
    /// followed by the three tail-encoded strings in head order (name, symbol, baseURI).
    static func encodeDeployCollection(name: String, symbol: String, maxSupply: UInt64, baseURI: String, royaltyBPS: UInt16) -> Data {
        let nameBytes = ABIEncoder.encodeBytes(Data(name.utf8))     // length-prefixed + padded
        let symbolBytes = ABIEncoder.encodeBytes(Data(symbol.utf8))
        let baseURIBytes = ABIEncoder.encodeBytes(Data(baseURI.utf8))

        let headWords: UInt64 = 5
        let headSize = headWords * 32
        let offName = headSize
        let offSymbol = offName + UInt64(nameBytes.count)
        let offBaseURI = offSymbol + UInt64(symbolBytes.count)

        var out = ABIEncoder.functionSelector("deployCollection(string,string,uint256,string,uint96)")
        out.append(ABIEncoder.encodeOffset(offName))
        out.append(ABIEncoder.encodeOffset(offSymbol))
        out.append(ABIEncoder.encodeUInt256(maxSupply))
        out.append(ABIEncoder.encodeUInt256(UInt64(royaltyBPS)))
        out.append(ABIEncoder.encodeOffset(offBaseURI))
        out.append(nameBytes)
        out.append(symbolBytes)
        out.append(baseURIBytes)
        return out
    }

    /// Deploy a collection on-chain through the real submit pipeline: enclave-signed
    /// UserOp → server paymaster → bundler. The factory address is the configured
    /// NFT component address (PendingCredentials.Components.nft) — nil until set →
    /// throws, never a fake deploy.
    ///
    /// HONEST BOUNDARY: solidity compilation + on-chain bytecode live in the
    /// factory contract, not the app. We submit the deploy *call*; the resulting
    /// collection address is read from the receipt's CollectionDeployed log by the
    /// caller — never fabricated here.
    @MainActor
    static func deployCollectionOnChain(
        name: String,
        symbol: String,
        standard: NFTStandard,
        maxSupply: UInt64,
        baseURI: String,
        royaltyBPS: UInt16,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        factory: String? = PendingCredentials.filled(PendingCredentials.Components.nft)
    ) async throws -> WalletTransactionService.Submission {
        guard let factoryAddress = factory else {
            throw NFTError.mintFailed(reason: "NFT collection factory not configured (PendingCredentials.Components.nft)")
        }
        return try await service.submitCall(
            to: factoryAddress,
            value: 0,
            data: encodeDeployCollection(name: name, symbol: symbol, maxSupply: maxSupply, baseURI: baseURI, royaltyBPS: royaltyBPS),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Transfer (on-chain)

    /// ABI-encode an ERC-721 `transferFrom(address from, address to, uint256 tokenId)`.
    static func encodeTransferERC721(from: String, to: String, tokenId: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("transferFrom(address,address,uint256)")
        data.append(ABIEncoder.encodeAddress(from))
        data.append(ABIEncoder.encodeAddress(to))
        data.append(ABIEncoder.encodeUInt256(tokenId))
        return data
    }

    /// ABI-encode an ERC-1155 `safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes data)`.
    /// Head: from, to, id, amount, offset(data) = 5 words; tail: empty bytes.
    static func encodeTransferERC1155(from: String, to: String, tokenId: UInt64, amount: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("safeTransferFrom(address,address,uint256,uint256,bytes)")
        data.append(ABIEncoder.encodeAddress(from))
        data.append(ABIEncoder.encodeAddress(to))
        data.append(ABIEncoder.encodeUInt256(tokenId))
        data.append(ABIEncoder.encodeUInt256(amount))
        data.append(ABIEncoder.encodeOffset(160)) // 5 head words precede the bytes arg
        data.append(ABIEncoder.encodeBytes(Data())) // empty data
        return data
    }

    /// Transfer an NFT on-chain through the real submit pipeline: enclave-signed
    /// UserOp → server paymaster → bundler. Contract address is the collection
    /// (or PendingCredentials.Components.nft fallback) — nil → throws, never a
    /// fake transfer.
    @MainActor
    func transferOnChain(
        from: String,
        to: String,
        tokenId: UInt64,
        amount: UInt64 = 1,
        standard: NFTStandard,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.nft)
    ) async throws -> WalletTransactionService.Submission {
        guard let nftContract = contract else {
            throw NFTError.mintFailed(reason: "NFT contract not configured (PendingCredentials.Components.nft)")
        }
        let data: Data = standard == .erc1155
            ? Self.encodeTransferERC1155(from: from, to: to, tokenId: tokenId, amount: amount)
            : Self.encodeTransferERC721(from: from, to: to, tokenId: tokenId)
        return try await service.submitCall(
            to: nftContract,
            value: 0,
            data: data,
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Marketplace (on-chain, batched)

    /// ABI-encode ERC-721/1155 `setApprovalForAll(address operator, bool approved)`.
    static func encodeSetApprovalForAll(operator op: String, approved: Bool) -> Data {
        var data = ABIEncoder.functionSelector("setApprovalForAll(address,bool)")
        data.append(ABIEncoder.encodeAddress(op))
        data.append(ABIEncoder.encodeUInt256(approved ? 1 : 0))
        return data
    }

    /// ABI-encode marketplace `createListing(address collection, uint256 tokenId, uint256 price)`.
    static func encodeCreateListing(collection: String, tokenId: UInt64, price: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("createListing(address,uint256,uint256)")
        data.append(ABIEncoder.encodeAddress(collection))
        data.append(ABIEncoder.encodeUInt256(tokenId))
        data.append(ABIEncoder.encodeUInt256(price))
        return data
    }

    /// ABI-encode marketplace `purchase(uint256 listingId)`.
    static func encodePurchaseListing(listingId: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("purchase(uint256)")
        data.append(ABIEncoder.encodeUInt256(listingId))
        return data
    }

    /// ABI-encode marketplace `cancelListing(uint256 listingId)`.
    static func encodeCancelListing(listingId: UInt64) -> Data {
        var data = ABIEncoder.functionSelector("cancelListing(uint256)")
        data.append(ABIEncoder.encodeUInt256(listingId))
        return data
    }

    /// List an NFT for sale on-chain as ONE batched UserOperation:
    ///   call 1 — setApprovalForAll(marketplace, true) on the collection contract
    ///   call 2 — createListing(collection, tokenId, price) on the marketplace
    /// Both NFT and marketplace addresses come from PendingCredentials — either
    /// blank → throws "needs config", never a fake listing.
    @MainActor
    func listForSaleOnChain(
        tokenId: UInt64,
        price: UInt64,
        sender: String,
        signingKeyTag: String,
        collection: String? = PendingCredentials.filled(PendingCredentials.Components.nft),
        marketplace: String? = PendingCredentials.filled(PendingCredentials.Components.marketplace)
    ) async throws -> WalletTransactionService.Submission {
        guard let collectionAddress = collection else {
            throw NFTError.mintFailed(reason: "NFT contract not configured (PendingCredentials.Components.nft)")
        }
        guard let marketplaceAddress = marketplace else {
            throw NFTError.approvalRequired
        }
        let calls: [(to: String, value: UInt64, data: Data)] = [
            (to: collectionAddress, value: 0, data: Self.encodeSetApprovalForAll(operator: marketplaceAddress, approved: true)),
            (to: marketplaceAddress, value: 0, data: Self.encodeCreateListing(collection: collectionAddress, tokenId: tokenId, price: price))
        ]
        return try await submitBatchOnChain(calls: calls, sender: sender, signingKeyTag: signingKeyTag)
    }

    /// Buy a listed NFT on-chain. The marketplace pulls the asset on payment, so a
    /// single `purchase(listingId)` call carrying `paymentWei` is the on-chain action
    /// (kept as a batch for symmetry / future approve+purchase flows). Marketplace
    /// address from PendingCredentials — blank → throws, never a fake purchase.
    @MainActor
    func buyOnChain(
        listingId: UInt64,
        paymentWei: UInt64,
        sender: String,
        signingKeyTag: String,
        marketplace: String? = PendingCredentials.filled(PendingCredentials.Components.marketplace)
    ) async throws -> WalletTransactionService.Submission {
        guard let marketplaceAddress = marketplace else {
            throw NFTError.mintFailed(reason: "Marketplace not configured (PendingCredentials.Components.marketplace)")
        }
        guard let service = WalletTransactionService() else {
            throw NFTError.mintFailed(reason: "On-chain config not set — fill PendingCredentials")
        }
        return try await service.submitCall(
            to: marketplaceAddress,
            value: paymentWei,
            data: Self.encodePurchaseListing(listingId: listingId),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    /// Delist on-chain: `cancelListing(listingId)` on the marketplace.
    @MainActor
    func cancelListingOnChain(
        listingId: UInt64,
        sender: String,
        signingKeyTag: String,
        marketplace: String? = PendingCredentials.filled(PendingCredentials.Components.marketplace)
    ) async throws -> WalletTransactionService.Submission {
        guard let marketplaceAddress = marketplace else {
            throw NFTError.mintFailed(reason: "Marketplace not configured (PendingCredentials.Components.marketplace)")
        }
        guard let service = WalletTransactionService() else {
            throw NFTError.mintFailed(reason: "On-chain config not set — fill PendingCredentials")
        }
        return try await service.submitCall(
            to: marketplaceAddress,
            value: 0,
            data: Self.encodeCancelListing(listingId: listingId),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Batched submit bridge (enclave-signed, non-custodial)

    /// Pack N calls into one `executeBatch(...)` UserOperation via the injected
    /// `erc4337Manager`, then sign it with the user's **Secure Enclave** key and
    /// submit to the bundler. This preserves the non-custodial invariant — signing
    /// happens only in the enclave (ERC4337Manager.signOperation refuses without a
    /// configured key tag); the server never signs the wallet op. Mirrors the
    /// continuation bridge the single-call spine uses internally.
    ///
    /// Requires the chain core to be configured (WalletTransactionService.init?
    /// returns nil otherwise) so the manager reads real entryPoint/paymaster from
    /// PendingCredentials — never hardcoded endpoints.
    @MainActor
    func submitBatchOnChain(
        calls: [(to: String, value: UInt64, data: Data)],
        sender: String,
        signingKeyTag: String
    ) async throws -> WalletTransactionService.Submission {
        // Gate on full chain config — same gate the single-call spine uses.
        guard WalletTransactionService() != nil else {
            throw NFTError.mintFailed(reason: "On-chain config not set — fill PendingCredentials")
        }
        let manager = erc4337Manager
        manager.setAccountAddress(sender)
        manager.configureSigningKey(tag: signingKeyTag)

        // 1. Build the unsigned batched op (real executeBatch calldata).
        let op: UserOperation
        switch manager.buildBatchUserOperation(calls: calls) {
        case .success(let built): op = built
        case .failure(let error): throw NFTError.mintFailed(reason: "Batch build failed: \(error.localizedDescription)")
        }

        // 2. Sign with the Secure Enclave key (refuses without a key tag).
        let signedOp: UserOperation = try await withCheckedThrowingContinuation { continuation in
            manager.signOperation(op) { result in
                switch result {
                case .success(let signed): continuation.resume(returning: signed)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }

        // 3. Submit the signed op to the bundler — returns the real userOpHash.
        let hash: String = try await withCheckedThrowingContinuation { continuation in
            manager.submitOperation(signedOp) { result in
                switch result {
                case .success(let h): continuation.resume(returning: h)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        return WalletTransactionService.Submission(userOpHash: hash, signedOperation: signedOp)
    }

    // MARK: - Transfer

    /// Transfer an NFT to another address.
    ///
    /// Bridges the completion API to `transferOnChain` (enclave-signed UserOp →
    /// paymaster → bundler). `from`/`sender` are the owner's smart account and
    /// `signingKeyTag` their Secure Enclave key tag. The token's numeric on-chain
    /// id is required; a non-numeric `tokenId` (e.g. a provisional userOpHash) is
    /// rejected rather than silently faked. ERC-1155 amount defaults to 1.
    func transfer(tokenId: String, contractAddress: String, from: String, to: String, standard: NFTStandard = .erc721, amount: UInt64 = 1, sender: String, signingKeyTag: String, completion: @escaping (Result<Void, NFTError>) -> Void) {
        guard let numericTokenId = UInt64(tokenId.hasPrefix("0x") ? String(tokenId.dropFirst(2)) : tokenId, radix: tokenId.hasPrefix("0x") ? 16 : 10) else {
            completion(.failure(.tokenNotFound))
            return
        }
        Task { @MainActor in
            // WalletTransactionService.init? is @MainActor — construct on the main actor.
            guard let service = WalletTransactionService() else {
                completion(.failure(.transferFailed))
                return
            }
            do {
                _ = try await self.transferOnChain(
                    from: from,
                    to: to,
                    tokenId: numericTokenId,
                    amount: amount,
                    standard: standard,
                    sender: sender,
                    signingKeyTag: signingKeyTag,
                    service: service,
                    contract: contractAddress.isEmpty ? PendingCredentials.filled(PendingCredentials.Components.nft) : contractAddress
                )
                self.delegate?.nftManager(self, didTransfer: tokenId, to: to)
                completion(.success(()))
            } catch {
                self.delegate?.nftManager(self, didFailWithError: .transferFailed)
                completion(.failure(.transferFailed))
            }
        }
    }

    // MARK: - Marketplace

    /// List an NFT for sale.
    ///
    /// Bridges to `listForSaleOnChain` — a single batched UserOperation of
    /// setApprovalForAll(marketplace,true) + createListing(...). `seller`/`sender`
    /// is the owner's smart account, `signingKeyTag` their enclave key tag. The
    /// marketplace + collection addresses come from PendingCredentials; either
    /// blank → "needs config" error, never a fake listing. The on-chain listingId
    /// is assigned by the marketplace (read from the receipt) — the returned
    /// NFTListing carries the userOpHash as a provisional id.
    func listForSale(tokenId: String, contractAddress: String, price: UInt64, currency: String, duration: TimeInterval?, seller: String, signingKeyTag: String, completion: @escaping (Result<NFTListing, NFTError>) -> Void) {
        guard let numericTokenId = UInt64(tokenId) else {
            completion(.failure(.tokenNotFound))
            return
        }
        Task { @MainActor in
            do {
                let submission = try await self.listForSaleOnChain(
                    tokenId: numericTokenId,
                    price: price,
                    sender: seller,
                    signingKeyTag: signingKeyTag,
                    collection: contractAddress.isEmpty ? PendingCredentials.filled(PendingCredentials.Components.nft) : contractAddress
                )
                // Provisional listing keyed by the userOpHash; the real listingId is
                // resolved from the marketplace ListingCreated log — not invented.
                let token = self.tokens["\(contractAddress):\(tokenId)"]
                let listing = NFTListing(
                    listingId: submission.userOpHash,
                    token: token ?? NFTToken(
                        tokenId: tokenId, contractAddress: contractAddress,
                        standard: .erc721, owner: seller, metadata: nil,
                        amount: 1, royaltyBPS: 0, createdAt: Date()
                    ),
                    price: price,
                    currency: currency,
                    seller: seller,
                    expiresAt: duration.map { Date().addingTimeInterval($0) },
                    isActive: true
                )
                self.listings[submission.userOpHash] = listing
                completion(.success(listing))
            } catch {
                completion(.failure(.approvalRequired))
            }
        }
    }

    /// Buy a listed NFT.
    ///
    /// Bridges to `buyOnChain` — a `purchase(listingId)` call carrying the listing
    /// price as `paymentWei` (user-signed self-custody; the app never holds funds).
    /// Marketplace address from PendingCredentials — blank → "needs config" error,
    /// never a fake purchase. `buyer`/`sender` is the buyer's smart account.
    func buy(listingId: String, buyer: String, signingKeyTag: String, completion: @escaping (Result<NFTToken, NFTError>) -> Void) {
        guard let listing = listings[listingId], listing.isActive else {
            completion(.failure(.tokenNotFound))
            return
        }
        guard let numericListingId = UInt64(listingId) else {
            completion(.failure(.tokenNotFound))
            return
        }
        Task { @MainActor in
            do {
                _ = try await self.buyOnChain(
                    listingId: numericListingId,
                    paymentWei: listing.price,
                    sender: buyer,
                    signingKeyTag: signingKeyTag
                )
                completion(.success(listing.token))
            } catch {
                completion(.failure(.transferFailed))
            }
        }
    }

    /// Cancel (delist) a listing.
    ///
    /// Bridges to `cancelListingOnChain` — `cancelListing(listingId)` on the
    /// marketplace, enclave-signed. Only drops the local record once the on-chain
    /// delist submission succeeds. `seller`/`sender` is the listing owner's account.
    func cancelListing(listingId: String, seller: String, signingKeyTag: String, completion: @escaping (Result<Void, NFTError>) -> Void) {
        guard let numericListingId = UInt64(listingId) else {
            completion(.failure(.tokenNotFound))
            return
        }
        Task { @MainActor in
            do {
                _ = try await self.cancelListingOnChain(
                    listingId: numericListingId,
                    sender: seller,
                    signingKeyTag: signingKeyTag
                )
                self.listings.removeValue(forKey: listingId)
                completion(.success(()))
            } catch {
                completion(.failure(.transferFailed))
            }
        }
    }

    // MARK: - Query

    /// Get all NFTs owned by an address
    func getOwnedTokens(address: String) -> [NFTToken] {
        return tokens.values.filter { $0.owner == address }
    }

    /// Get token metadata
    func getMetadata(tokenId: String, contractAddress: String) -> NFTMetadata? {
        let key = "\(contractAddress):\(tokenId)"
        return tokens[key]?.metadata
    }

    /// Get active listings
    func getActiveListings() -> [NFTListing] {
        return listings.values.filter { $0.isActive }
    }
}
