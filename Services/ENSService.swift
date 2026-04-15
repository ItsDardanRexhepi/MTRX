import Foundation

// MARK: - Models

struct ENSSearchResult: Codable {
    let name: String
    let isAvailable: Bool
    let price1Year: Double
    let price5Year: Double
}

struct ENSDomain: Codable, Identifiable {
    var id: String { name }
    let name: String
    let owner: String
    let expiresAt: Date
    let isPrimary: Bool
}

// MARK: - Service

@MainActor
final class ENSService {

    static let shared = ENSService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func searchName(query: String) async throws -> ENSSearchResult {
        try await api.get("/ens/search", queryItems: [
            URLQueryItem(name: "query", value: query)
        ])
    }

    func registerName(name: String, years: Int) async throws -> TransactionResult {
        struct RegisterBody: Codable {
            let name: String
            let years: Int
        }
        let body = RegisterBody(name: name, years: years)
        return try await api.post("/ens/register", body: body)
    }

    func getUserDomains(address: String) async throws -> [ENSDomain] {
        try await api.get("/ens/domains", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func setPrimaryName(name: String) async throws -> TransactionResult {
        struct SetPrimaryBody: Codable {
            let name: String
        }
        let body = SetPrimaryBody(name: name)
        return try await api.post("/ens/primary", body: body)
    }

    func resolveName(_ name: String) async throws -> String? {
        struct ResolveResponse: Codable {
            let address: String?
        }
        let response: ResolveResponse = try await api.get("/ens/resolve", queryItems: [
            URLQueryItem(name: "name", value: name)
        ])
        return response.address
    }

    func lookupAddress(_ address: String) async throws -> String? {
        struct LookupResponse: Codable {
            let name: String?
        }
        let response: LookupResponse = try await api.get("/ens/lookup", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
        return response.name
    }
}
