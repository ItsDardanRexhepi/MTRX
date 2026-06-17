// NFTService.swift
// MTRX — NFT operations via 0pnMatrx gateway

import Foundation

// MARK: - Models

struct NFTAsset: Codable, Identifiable {
    var id: String { "\(tokenId)_\(contract)" }
    let tokenId: String
    let contract: String
    let name: String
    let description: String
    let imageURL: String?
    let collectionName: String
    let floorPrice: Double?
    let traits: [SvcNFTTrait]

    private enum CodingKeys: String, CodingKey {
        case tokenId, contract, name, description, imageURL, collectionName, floorPrice, traits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tokenId = try container.decode(String.self, forKey: .tokenId)
        self.contract = try container.decode(String.self, forKey: .contract)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = (try? container.decode(String.self, forKey: .description)) ?? ""
        self.imageURL = try? container.decode(String.self, forKey: .imageURL)
        self.collectionName = (try? container.decode(String.self, forKey: .collectionName)) ?? ""
        self.floorPrice = try? container.decode(Double.self, forKey: .floorPrice)
        self.traits = (try? container.decode([SvcNFTTrait].self, forKey: .traits)) ?? []
    }
}

struct SvcNFTTrait: Codable, Identifiable {
    let id: UUID
    let traitType: String
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.traitType = try container.decode(String.self, forKey: .traitType)
        self.value = try container.decode(String.self, forKey: .value)
    }

    private enum CodingKeys: String, CodingKey {
        case id, traitType, value
    }
}

struct SvcNFTMetadata: Codable {
    let name: String
    let description: String
    let attributes: [SvcNFTAttribute]
    let royaltyPercent: Double
}

struct SvcNFTAttribute: Codable {
    let key: String
    let value: String
}

struct NFTMintResult: Codable {
    let tokenId: String
    let contract: String
    let txHash: String
}

struct SvcNFTListingResult: Codable {
    let listingId: String
    let txHash: String
}

// MARK: - NFTService

@MainActor
final class NFTService {
    static let shared = NFTService()
    private let client = MTRXAPIClient.shared

    private init() {}

    // MARK: - List User NFTs

    func getUserNFTs(address: String) async throws -> [NFTAsset] {
        let nfts: [NFTAsset] = try await client.get(
            path: "/api/v1/nft/list",
            queryItems: [URLQueryItem(name: "address", value: address)]
        )
        return nfts
    }

    // MARK: - Mint NFT (multipart upload)

    func mintNFT(metadata: SvcNFTMetadata, imageData: Data) async throws -> NFTMintResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        let baseURL = client.baseURL
        guard let url = URL(string: baseURL + "/api/v1/nft/mint") else {
            throw MTRXAPIError.invalidURL("/api/v1/nft/mint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if client.isAuthenticated, let token = client.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        // Add metadata as JSON field
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let metadataJSON = try encoder.encode(metadata)

        body.appendMultipartField(
            boundary: boundary,
            name: "metadata",
            value: String(data: metadataJSON, encoding: .utf8) ?? "{}"
        )

        // Add image data
        body.appendMultipartFile(
            boundary: boundary,
            name: "image",
            filename: "nft_image.png",
            mimeType: "image/png",
            data: imageData
        )

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await client.urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MTRXAPIError.unknown("Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MTRXAPIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(NFTMintResult.self, from: data)
        return result
    }

    // MARK: - Transfer NFT

    func transferNFT(tokenId: String, contract: String, to: String) async throws -> SvcTransactionResult {
        struct TransferRequest: Encodable {
            let tokenId: String
            let contract: String
            let to: String
        }
        let result: SvcTransactionResult = try await client.post(
            path: "/api/v1/nft/transfer",
            body: TransferRequest(tokenId: tokenId, contract: contract, to: to)
        )
        return result
    }

    // MARK: - List NFT for Sale

    func listNFTForSale(tokenId: String, contract: String, price: String) async throws -> SvcNFTListingResult {
        struct ListForSaleRequest: Encodable {
            let tokenId: String
            let contract: String
            let price: String
        }
        let result: SvcNFTListingResult = try await client.post(
            path: "/api/v1/nft/list-for-sale",
            body: ListForSaleRequest(tokenId: tokenId, contract: contract, price: price)
        )
        return result
    }

    // MARK: - NFT Details

    func getNFTDetails(tokenId: String, contract: String) async throws -> NFTAsset {
        let asset: NFTAsset = try await client.get(
            path: "/api/v1/nft/details",
            queryItems: [
                URLQueryItem(name: "tokenId", value: tokenId),
                URLQueryItem(name: "contract", value: contract),
            ]
        )
        return asset
    }
}

// MARK: - Data Multipart Helpers

private extension Data {
    mutating func appendMultipartField(boundary: String, name: String, value: String) {
        let fieldData = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        append(fieldData.data(using: .utf8)!)
    }

    mutating func appendMultipartFile(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        var header = "--\(boundary)\r\n"
        header += "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        header += "Content-Type: \(mimeType)\r\n\r\n"
        append(header.data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
