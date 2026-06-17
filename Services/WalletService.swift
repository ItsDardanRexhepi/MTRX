// WalletService.swift
// MTRX — Wallet operations via 0pnMatrx gateway

import Foundation

// MARK: - Models

struct WalletCreationResult: Codable, Identifiable {
    let id: UUID
    let walletAddress: String
    let isSmartWallet: Bool
    let chainId: Int
    let recoveryMethod: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.walletAddress = try container.decode(String.self, forKey: .walletAddress)
        self.isSmartWallet = (try? container.decode(Bool.self, forKey: .isSmartWallet)) ?? true
        self.chainId = (try? container.decode(Int.self, forKey: .chainId)) ?? 8453
        self.recoveryMethod = (try? container.decode(String.self, forKey: .recoveryMethod)) ?? "social"
    }

    private enum CodingKeys: String, CodingKey {
        case id, walletAddress, isSmartWallet, chainId, recoveryMethod
    }
}

struct WalletBalance: Codable {
    let address: String
    let ethBalance: Double
    let usdValue: Double
    let tokens: [SvcTokenBalance]
    let lastUpdated: Date
}

struct SvcTokenBalance: Codable, Identifiable {
    let id: UUID
    let name: String
    let symbol: String
    let balance: Double
    let usdValue: Double
    let change24hPercent: Double
    let contractAddress: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.balance = try container.decode(Double.self, forKey: .balance)
        self.usdValue = (try? container.decode(Double.self, forKey: .usdValue)) ?? 0
        self.change24hPercent = (try? container.decode(Double.self, forKey: .change24hPercent)) ?? 0
        self.contractAddress = (try? container.decode(String.self, forKey: .contractAddress)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, balance, usdValue, change24hPercent, contractAddress
    }
}

struct SvcDIDDocument: Codable, Identifiable {
    var id: String { did }
    let did: String
    let controller: String
    let verificationMethods: [VerificationMethod]
    let services: [DIDService]

    private enum CodingKeys: String, CodingKey {
        case did, controller, verificationMethods, services
    }
}

struct VerificationMethod: Codable, Identifiable {
    let id: String
    let type: String
    let controller: String
    let publicKeyMultibase: String
}

struct DIDService: Codable, Identifiable {
    let id: String
    let type: String
    let serviceEndpoint: String
}

// MARK: - WalletService

@MainActor
final class WalletService {
    static let shared = WalletService()
    private let client = MTRXAPIClient.shared

    private static let walletAddressKey = "mtrx.wallet.address"

    private init() {}

    // MARK: - Smart Wallet Creation

    func createSmartWallet() async throws -> WalletCreationResult {
        struct EmptyRequest: Encodable {}
        let result: WalletCreationResult = try await client.post(
            path: "/api/v1/wallet/create",
            body: EmptyRequest()
        )
        saveWalletAddress(result.walletAddress)
        return result
    }

    // MARK: - Local Address Management

    func getWalletAddress() -> String? {
        UserDefaults.standard.string(forKey: Self.walletAddressKey)
    }

    func saveWalletAddress(_ address: String) {
        UserDefaults.standard.set(address, forKey: Self.walletAddressKey)
    }

    // MARK: - ENS Lookup

    func getENSName(for address: String) async -> String? {
        struct ENSResponse: Decodable {
            let name: String?
        }
        do {
            let response: ENSResponse = try await client.get(
                path: "/api/v1/ens/lookup",
                queryItems: [URLQueryItem(name: "address", value: address)]
            )
            return response.name
        } catch {
            return nil
        }
    }

    // MARK: - Balance

    func refreshBalance() async throws -> WalletBalance {
        let balance: WalletBalance = try await client.get(
            path: "/api/v1/wallet/balance"
        )
        return balance
    }

    // MARK: - DID Operations

    func createDID() async throws -> SvcDIDDocument {
        struct EmptyRequest: Encodable {}
        let document: SvcDIDDocument = try await client.post(
            path: "/api/v1/identity/did/create",
            body: EmptyRequest()
        )
        return document
    }

    func resolveDID(address: String) async throws -> SvcDIDDocument? {
        do {
            let document: SvcDIDDocument = try await client.get(
                path: "/api/v1/identity/did/resolve",
                queryItems: [URLQueryItem(name: "address", value: address)]
            )
            return document
        } catch let error as MTRXAPIError {
            if case .notFound = error {
                return nil
            }
            throw error
        }
    }

    func updateDIDAttribute(key: String, value: String) async throws {
        struct DIDUpdateRequest: Encodable {
            let key: String
            let value: String
        }
        let _: [String: AnyCodableValue] = try await client.post(
            path: "/api/v1/identity/did/update",
            body: DIDUpdateRequest(key: key, value: value)
        )
    }
}
