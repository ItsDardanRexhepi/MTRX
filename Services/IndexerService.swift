import Foundation

// MARK: - Models

struct Subgraph: Codable, Identifiable {
    var id: String { subgraphId }
    let subgraphId: String
    let name: String
    let description: String
    let protocol_: String?
    let entityTypes: [String]

    private enum CodingKeys: String, CodingKey {
        case subgraphId, name, description
        case protocol_ = "protocol"
        case entityTypes
    }
}

struct QueryResult: Codable {
    let columns: [String]
    let rows: [[String]]
    let executionTime: Double
}

struct SavedQuery: Codable, Identifiable {
    var id: String { queryId }
    let queryId: String
    let name: String
    let subgraphId: String
    let query: String
    let lastRunAt: Date?
}

// MARK: - Service

@MainActor
final class IndexerService {

    static let shared = IndexerService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getSubgraphs() async throws -> [Subgraph] {
        try await api.get(path: "/indexer/subgraphs")
    }

    func runQuery(subgraphId: String, query: String) async throws -> QueryResult {
        try await api.post(path: "/indexer/subgraphs/\(subgraphId)/query", body: ["query": query])
    }

    func translateToQuery(plainEnglish: String, subgraphId: String) async throws -> String {
        struct TranslateResult: Codable {
            let query: String
        }
        let result: TranslateResult = try await api.post(path: "/indexer/subgraphs/\(subgraphId)/translate", body: ["text": plainEnglish])
        return result.query
    }

    func getUserQueries(address: String) async throws -> [SavedQuery] {
        try await api.get(path: "/indexer/queries", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func saveQuery(name: String, subgraphId: String, query: String) async throws -> SavedQuery {
        struct SaveBody: Codable {
            let name: String
            let subgraphId: String
            let query: String
        }
        let body = SaveBody(name: name, subgraphId: subgraphId, query: query)
        return try await api.post(path: "/indexer/queries", body: body)
    }
}
