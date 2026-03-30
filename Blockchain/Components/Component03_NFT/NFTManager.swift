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

    /// Deploy a new NFT collection contract
    func createCollection(name: String, symbol: String, standard: NFTStandard, maxSupply: UInt64?, baseURI: String, royaltyBPS: UInt16, completion: @escaping (Result<NFTCollection, NFTError>) -> Void) {
        // TODO: Deploy ERC-721 or ERC-1155 contract via ERC-4337
        completion(.failure(.mintFailed(reason: "Not implemented")))
    }

    /// Fetch collection details
    func getCollection(address: String) -> Result<NFTCollection, NFTError> {
        guard let collection = collections[address] else { return .failure(.collectionNotFound) }
        return .success(collection)
    }

    // MARK: - Minting

    /// Mint a new NFT
    func mint(collectionAddress: String, to: String, metadata: NFTMetadata, amount: UInt64 = 1, completion: @escaping (Result<NFTToken, NFTError>) -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.collections[collectionAddress] != nil else {
                completion(.failure(.collectionNotFound))
                return
            }
            // TODO: Upload metadata to IPFS, ABI-encode mint, submit via ERC-4337
            let tokenId = UUID().uuidString
            self.delegate?.nftManager(self, didMint: tokenId, collection: collectionAddress)
            completion(.failure(.mintFailed(reason: "Not implemented")))
        }
    }

    /// Batch mint multiple NFTs
    func batchMint(collectionAddress: String, to: String, metadataList: [NFTMetadata], completion: @escaping (Result<[NFTToken], NFTError>) -> Void) {
        // TODO: Batch mint via ERC-4337 batched UserOperation
        completion(.failure(.mintFailed(reason: "Not implemented")))
    }

    // MARK: - Transfer

    /// Transfer an NFT to another address
    func transfer(tokenId: String, contractAddress: String, to: String, completion: @escaping (Result<Void, NFTError>) -> Void) {
        // TODO: ABI-encode transferFrom/safeTransferFrom, submit via ERC-4337
        delegate?.nftManager(self, didTransfer: tokenId, to: to)
        completion(.failure(.transferFailed))
    }

    // MARK: - Marketplace

    /// List an NFT for sale
    func listForSale(tokenId: String, contractAddress: String, price: UInt64, currency: String, duration: TimeInterval?, completion: @escaping (Result<NFTListing, NFTError>) -> Void) {
        // TODO: Approve marketplace contract, create listing
        completion(.failure(.approvalRequired))
    }

    /// Buy a listed NFT
    func buy(listingId: String, completion: @escaping (Result<NFTToken, NFTError>) -> Void) {
        guard let listing = listings[listingId], listing.isActive else {
            completion(.failure(.tokenNotFound))
            return
        }
        // TODO: Execute purchase via ERC-4337
        completion(.failure(.transferFailed))
    }

    /// Cancel a listing
    func cancelListing(listingId: String, completion: @escaping (Result<Void, NFTError>) -> Void) {
        // TODO: Remove marketplace listing
        listings.removeValue(forKey: listingId)
        completion(.success(()))
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
