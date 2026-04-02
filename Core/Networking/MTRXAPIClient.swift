// MTRXAPIClient.swift
// Central networking layer for the MTRX iOS app.
// Connects to the MTRX Runtime FastAPI backend (30 blockchain components + Phase 3 subsystems).

import Foundation

// MARK: - API Error

enum MTRXAPIError: LocalizedError, Equatable {
    case invalidURL(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case networkUnavailable
    case networkError(URLError)
    case httpError(statusCode: Int, body: String)
    case unauthorized
    case forbidden
    case notFound(String)
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(String)
    case timeout
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid URL: \(path)"
        case .encodingFailed(let detail):
            return "Failed to encode request body: \(detail)"
        case .decodingFailed(let detail):
            return "Failed to decode response: \(detail)"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .unauthorized:
            return "Authentication required. Please sign in."
        case .forbidden:
            return "You do not have permission for this action."
        case .notFound(let resource):
            return "Not found: \(resource)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds))s."
            }
            return "Rate limited. Please try again later."
        case .serverError(let detail):
            return "Server error: \(detail)"
        case .timeout:
            return "Request timed out."
        case .cancelled:
            return "Request was cancelled."
        case .unknown(let detail):
            return "Unknown error: \(detail)"
        }
    }

    static func == (lhs: MTRXAPIError, rhs: MTRXAPIError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - Generic API Response Wrapper

struct APIResponse<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
    let error: String?
    let message: String?
    let meta: ResponseMeta?

    struct ResponseMeta: Decodable {
        let page: Int?
        let perPage: Int?
        let total: Int?
        let txHash: String?
    }
}

// MARK: - Auth Models

struct AppleAuthRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let fullName: String?
    let email: String?
}

struct AuthResponse: Decodable {
    let token: String
    let userId: String
    let walletAddress: String
    let expiresAt: Date?
    let isNewUser: Bool?
}

// MARK: - Agent Chat Models

struct AgentChatRequest: Encodable {
    let message: String
    let agent: String
    let conversationId: String?
    let context: [String: AnyCodableValue]?
}

struct AgentChatResponse: Decodable {
    let text: String
    let agent: String
    let suggestedActions: [SuggestedAction]?
    let metadata: [String: AnyCodableValue]?
    let conversationId: String?
    let toolCalls: [ToolCallResult]?

    struct SuggestedAction: Decodable {
        let label: String
        let action: String
        let params: [String: AnyCodableValue]?
    }

    struct ToolCallResult: Decodable {
        let tool: String
        let result: AnyCodableValue?
        let success: Bool?
    }
}

// MARK: - Portfolio Models

struct PortfolioResponse: Decodable {
    let tokens: [TokenBalance]
    let nfts: [NFTAsset]
    let defiPositions: [DeFiPosition]
    let totalValueUSD: Double

    struct TokenBalance: Decodable, Identifiable {
        let id: String?
        let symbol: String
        let name: String
        let balance: Double
        let valueUSD: Double
        let contractAddress: String?
    }

    struct NFTAsset: Decodable, Identifiable {
        let id: String?
        let tokenId: String
        let collection: String
        let name: String
        let imageUrl: String?
        let contractAddress: String?
    }

    struct DeFiPosition: Decodable, Identifiable {
        let id: String?
        let protocol_: String?
        let type: String
        let asset: String
        let amount: Double
        let valueUSD: Double
        let apy: Double?

        private enum CodingKeys: String, CodingKey {
            case id
            case protocol_ = "protocol"
            case type, asset, amount, valueUSD, apy
        }
    }
}

// MARK: - Component-Specific Request/Response Models

// C1 - Contracts
struct ContractConvertRequest: Encodable {
    let sourceCode: String
    let sourceLanguage: String
    let targetLanguage: String
}

// C2 - DeFi
struct DeFiLendRequest: Encodable {
    let asset: String
    let amount: Double
    let durationDays: Int
}

struct DeFiBorrowRequest: Encodable {
    let collateralAsset: String
    let collateralAmount: Double
    let borrowAsset: String
    let borrowAmount: Double
}

struct DeFiPoolResponse: Decodable {
    let poolId: String
    let asset: String
    let totalLiquidity: Double
    let apy: Double
    let utilizationRate: Double
}

// C3 - NFT
struct NFTMintRequest: Encodable {
    let name: String
    let description: String
    let imageUri: String
    let attributes: [String: AnyCodableValue]?
    let recipient: String?
}

// C13 - Insurance
struct InsurancePolicyRequest: Encodable {
    let policyType: String
    let coverageAmount: Double
    let premium: Double
    let durationDays: Int
    let conditions: [String: AnyCodableValue]
}

struct InsuranceClaimRequest: Encodable {
    let policyId: String
    let description: String
    let evidence: [String: AnyCodableValue]
}

// C14 - Gaming
struct GameSubmitRequest: Encodable {
    let developer: String
    let name: String
    let metadataUri: String
}

// C19 - Governance
struct ProposalCreateRequest: Encodable {
    let title: String
    let description: String
    let actions: [[String: AnyCodableValue]]?
    let votingDurationHours: Int?
}

struct VoteRequest: Encodable {
    let proposalId: String
    let support: Bool
    let reason: String?
}

// C22 - Fundraising
struct CampaignCreateRequest: Encodable {
    let title: String
    let description: String
    let goalAmount: Double
    let durationDays: Int
    let milestones: [[String: AnyCodableValue]]?
}

struct ContributeRequest: Encodable {
    let campaignId: String
    let amount: Double
}

// C24 - Marketplace
struct ListingCreateRequest: Encodable {
    let assetType: String
    let assetId: String
    let price: Double
    let currency: String
    let description: String?
}

// C28 - Social
struct PostCreateRequest: Encodable {
    let content: String
    let attachments: [String]?
    let visibility: String?
}

// C29 - Privacy
struct PrivacyProofRequest: Encodable {
    let proofType: String
    let claims: [String: AnyCodableValue]
}

// C30 - Disputes
struct DisputeCreateRequest: Encodable {
    let contractId: String
    let description: String
    let evidence: [String: AnyCodableValue]
}

// MARK: - Transaction Result (common across components)

struct TransactionResult: Decodable {
    let txHash: String?
    let status: String
    let blockNumber: Int?
    let gasUsed: Int?
}

// MARK: - AnyCodableValue

enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

// MARK: - Network Status

enum NetworkStatus: Equatable {
    case connected
    case disconnected
    case degraded(String)
}

// MARK: - HTTP Method

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - MTRXAPIClient

final class MTRXAPIClient: @unchecked Sendable {
    static let shared = MTRXAPIClient()

    // MARK: - Configuration

    let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private let lock = NSLock()
    private var _authToken: String?
    private var _networkStatus: NetworkStatus = .disconnected

    var authToken: String? {
        get { lock.withLock { _authToken } }
        set { lock.withLock { _authToken = newValue } }
    }

    var networkStatus: NetworkStatus {
        get { lock.withLock { _networkStatus } }
        set { lock.withLock { _networkStatus = newValue } }
    }

    var isAuthenticated: Bool { authToken != nil }

    // Retry configuration
    private let maxRetries: Int = 3
    private let baseRetryDelay: TimeInterval = 0.5

    // MARK: - Init

    init(baseURL: String? = nil) {
        self.baseURL = baseURL
            ?? ProcessInfo.processInfo.environment["MTRX_RUNTIME_URL"]
            ?? "http://localhost:8000"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "User-Agent": "MTRX-iOS/1.0",
        ]
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: string) {
                return date
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(string)")
        }
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Token Persistence

    func storeToken(_ token: String) {
        authToken = token
        // Store in Keychain for persistence across launches
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mtrx.api-token",
            kSecAttrAccount as String: "jwt",
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func loadStoredToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mtrx.api-token",
            kSecAttrAccount as String: "jwt",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) {
            authToken = token
        }
    }

    func clearToken() {
        authToken = nil
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mtrx.api-token",
            kSecAttrAccount as String: "jwt",
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Core HTTP Layer

    private func buildRequest(
        method: HTTPMethod,
        path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw MTRXAPIError.invalidURL(path)
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw MTRXAPIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authenticated, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw MTRXAPIError.encodingFailed(error.localizedDescription)
            }
        }

        return request
    }

    private func execute<T: Decodable>(
        _ request: URLRequest,
        attempt: Int = 0
    ) async throws -> T {
        #if DEBUG
        logRequest(request)
        #endif

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                if attempt < maxRetries {
                    let delay = retryDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await execute(request, attempt: attempt + 1)
                }
                throw MTRXAPIError.timeout
            case .cancelled:
                throw MTRXAPIError.cancelled
            case .notConnectedToInternet, .networkConnectionLost:
                networkStatus = .disconnected
                throw MTRXAPIError.networkUnavailable
            default:
                throw MTRXAPIError.networkError(error)
            }
        } catch is CancellationError {
            throw MTRXAPIError.cancelled
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MTRXAPIError.unknown("Invalid HTTP response object")
        }

        #if DEBUG
        logResponse(httpResponse, data: data)
        #endif

        // Update network status on success
        networkStatus = .connected

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            clearToken()
            throw MTRXAPIError.unauthorized
        case 403:
            throw MTRXAPIError.forbidden
        case 404:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MTRXAPIError.notFound(body)
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            if attempt < maxRetries {
                let delay = retryAfter ?? retryDelay(attempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await execute(request, attempt: attempt + 1)
            }
            throw MTRXAPIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            if attempt < maxRetries {
                let delay = retryDelay(attempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await execute(request, attempt: attempt + 1)
            }
            let body = String(data: data, encoding: .utf8) ?? "Internal server error"
            throw MTRXAPIError.serverError(body)
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unexpected status"
            throw MTRXAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        do {
            let decoded = try decoder.decode(T.self, from: data)
            return decoded
        } catch {
            throw MTRXAPIError.decodingFailed("\(T.self): \(error.localizedDescription)")
        }
    }

    private func retryDelay(attempt: Int) -> TimeInterval {
        let jitter = Double.random(in: 0...0.3)
        return baseRetryDelay * pow(2.0, Double(attempt)) + jitter
    }

    // MARK: - Convenience HTTP Verbs

    func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let request = try buildRequest(method: .get, path: path, queryItems: queryItems, authenticated: authenticated)
        return try await execute(request)
    }

    func post<Body: Encodable, T: Decodable>(
        path: String,
        body: Body,
        authenticated: Bool = true
    ) async throws -> T {
        let request = try buildRequest(method: .post, path: path, body: body, authenticated: authenticated)
        return try await execute(request)
    }

    func put<Body: Encodable, T: Decodable>(
        path: String,
        body: Body,
        authenticated: Bool = true
    ) async throws -> T {
        let request = try buildRequest(method: .put, path: path, body: body, authenticated: authenticated)
        return try await execute(request)
    }

    func patch<Body: Encodable, T: Decodable>(
        path: String,
        body: Body,
        authenticated: Bool = true
    ) async throws -> T {
        let request = try buildRequest(method: .patch, path: path, body: body, authenticated: authenticated)
        return try await execute(request)
    }

    func delete<T: Decodable>(
        path: String,
        authenticated: Bool = true
    ) async throws -> T {
        let request = try buildRequest(method: .delete, path: path, authenticated: authenticated)
        return try await execute(request)
    }

    // Fire-and-forget POST (returns raw dict)
    func postRaw<Body: Encodable>(
        path: String,
        body: Body,
        authenticated: Bool = true
    ) async throws -> [String: AnyCodableValue] {
        let request = try buildRequest(method: .post, path: path, body: body, authenticated: authenticated)
        return try await execute(request)
    }

    // MARK: - Debug Logging

    #if DEBUG
    private func logRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        print("[MTRX-API] --> \(method) \(url)")
        if let body = request.httpBody, body.count < 4096,
           let str = String(data: body, encoding: .utf8) {
            print("[MTRX-API]     Body: \(str)")
        }
    }

    private func logResponse(_ response: HTTPURLResponse, data: Data) {
        let status = response.statusCode
        let url = response.url?.absoluteString ?? "?"
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .memory)
        print("[MTRX-API] <-- \(status) \(url) (\(size))")
        if status >= 400, let body = String(data: data, encoding: .utf8)?.prefix(1024) {
            print("[MTRX-API]     Error body: \(body)")
        }
    }
    #endif

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Auth Endpoints
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func authenticateWithApple(
        identityToken: String,
        authorizationCode: String,
        fullName: String? = nil,
        email: String? = nil
    ) async throws -> AuthResponse {
        let body = AppleAuthRequest(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName,
            email: email
        )
        let response: AuthResponse = try await post(path: "/api/v1/auth/apple", body: body, authenticated: false)
        storeToken(response.token)
        return response
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Health & Status
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    struct HealthResponse: Decodable {
        let status: String
        let blockchainComponents: Int?
        let phase3Subsystems: Int?
        let openclawParityFeatures: Int?
        let network: String?
    }

    func health() async throws -> HealthResponse {
        try await get(path: "/health", authenticated: false)
    }

    /// Lightweight connectivity check. Updates `networkStatus`.
    func checkHealth() async -> Bool {
        do {
            let result: HealthResponse = try await health()
            networkStatus = result.status == "healthy" ? .connected : .degraded(result.status)
            return true
        } catch {
            networkStatus = .disconnected
            return false
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Agent Chat
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func sendAgentMessage(
        _ message: String,
        agent: String,
        conversationId: String? = nil,
        context: [String: AnyCodableValue]? = nil
    ) async throws -> AgentChatResponse {
        let body = AgentChatRequest(
            message: message,
            agent: agent,
            conversationId: conversationId,
            context: context
        )
        return try await post(path: "/api/v1/agents/chat", body: body)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Portfolio
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func getPortfolio() async throws -> PortfolioResponse {
        try await get(path: "/api/v1/portfolio")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C1: Contract Conversion
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func convertContract(_ request: ContractConvertRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/contracts/convert", body: request)
    }

    func getContract(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/contracts/\(id)")
    }

    func listContracts() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/contracts")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C2: DeFi Lending
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func defiLend(_ request: DeFiLendRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/defi/lend", body: request)
    }

    func defiBorrow(_ request: DeFiBorrowRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/defi/borrow", body: request)
    }

    func defiRepay(loanId: String, amount: Double) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/defi/repay", body: ["loan_id": loanId, "amount": amount] as [String: Any])
    }

    func defiListPools() async throws -> [DeFiPoolResponse] {
        try await get(path: "/api/v1/defi/pools")
    }

    func defiGetPool(id: String) async throws -> DeFiPoolResponse {
        try await get(path: "/api/v1/defi/pools/\(id)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C3: NFT
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func mintNFT(_ request: NFTMintRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/nft/mint", body: request)
    }

    func getNFT(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/nft/\(id)")
    }

    func listNFTs() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/nft")
    }

    func transferNFT(tokenId: String, to: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/nft/transfer", body: ["token_id": tokenId, "to": to])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C4: RWA Tokenization
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func tokenizeAsset(assetType: String, metadata: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/rwa/tokenize", body: ["asset_type": AnyCodableValue.string(assetType), "metadata": AnyCodableValue.dictionary(metadata)])
    }

    func getRWAAsset(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/rwa/\(id)")
    }

    func listRWAAssets() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/rwa")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C5: Identity (DID)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createDID() async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/identity/create", body: EmptyBody())
    }

    func resolveDID(did: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/identity/\(did)")
    }

    func listCredentials() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/identity/credentials")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C6: DAO Management
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createDAO(name: String, config: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/dao/create", body: ["name": AnyCodableValue.string(name), "config": AnyCodableValue.dictionary(config)])
    }

    func getDAO(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/dao/\(id)")
    }

    func listDAOs() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/dao")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C7: Stablecoin
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func getStablecoinBalance() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/stablecoin/balance")
    }

    func stablecoinTransfer(to: String, amount: Double, currency: String = "USDC") async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/stablecoin/transfer", body: ["to": to, "amount": "\(amount)", "currency": currency])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C8: Attestation (EAS)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createAttestation(schema: String, data: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/attestation/create", body: ["schema": AnyCodableValue.string(schema), "data": AnyCodableValue.dictionary(data)])
    }

    func getAttestation(uid: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/attestation/\(uid)")
    }

    func verifyAttestation(uid: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/attestation/verify/\(uid)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C9: Agent Identity
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func registerAgent(name: String, capabilities: [String]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/agent-identity/register", body: ["name": name, "capabilities": capabilities.joined(separator: ",")])
    }

    func getAgentIdentity(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/agent-identity/\(id)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C10: Agentic Payments
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createPaymentAuthorization(agent: String, limit: Double, currency: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/agentic-payments/authorize", body: ["agent": agent, "limit": "\(limit)", "currency": currency])
    }

    func listAgenticPayments() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/agentic-payments")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C11: Oracles
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func getOraclePrice(feed: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/oracles/price/\(feed)")
    }

    func listOracleFeeds() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/oracles/feeds")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C12: Supply Chain
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createShipment(data: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/supply-chain/shipment", body: data)
    }

    func trackShipment(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/supply-chain/shipment/\(id)")
    }

    func listShipments() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/supply-chain/shipments")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C13: Insurance
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createInsurancePolicy(_ request: InsurancePolicyRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/insurance/policy/create", body: request)
    }

    func getInsurancePolicy(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/insurance/policy/\(id)")
    }

    func fileInsuranceClaim(_ request: InsuranceClaimRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/insurance/claim", body: request)
    }

    func getInsuranceClaim(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/insurance/claim/\(id)")
    }

    func listInsurancePolicies() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/insurance/policies")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C14: Gaming
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func submitGame(_ request: GameSubmitRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/gaming/submit", body: request)
    }

    func getGame(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/gaming/\(id)")
    }

    func listGames() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/gaming")
    }

    func getGameAssets(gameId: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/gaming/\(gameId)/assets")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C15: IP Rights & Royalties
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func registerIP(metadata: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/ip/register", body: metadata)
    }

    func getIP(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/ip/\(id)")
    }

    func listIPAssets() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/ip")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C16: Staking
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func stake(asset: String, amount: Double, duration: Int? = nil) async throws -> [String: AnyCodableValue] {
        var body: [String: String] = ["asset": asset, "amount": "\(amount)"]
        if let duration { body["duration_days"] = "\(duration)" }
        return try await postRaw(path: "/api/v1/staking/stake", body: body)
    }

    func unstake(stakeId: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/staking/unstake", body: ["stake_id": stakeId])
    }

    func getStakingPositions() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/staking/positions")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C17: Payments
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func sendPayment(to: String, amount: Double, currency: String, memo: String? = nil) async throws -> [String: AnyCodableValue] {
        var body: [String: String] = ["to": to, "amount": "\(amount)", "currency": currency]
        if let memo { body["memo"] = memo }
        return try await postRaw(path: "/api/v1/payments/send", body: body)
    }

    func getPayment(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/payments/\(id)")
    }

    func listPayments() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/payments")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C18: Securities
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func issueSecurity(data: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/securities/issue", body: data)
    }

    func getSecurity(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/securities/\(id)")
    }

    func listSecurities() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/securities")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C19: Governance
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createProposal(_ request: ProposalCreateRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/governance/proposals", body: request)
    }

    func getProposal(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/governance/proposals/\(id)")
    }

    func listProposals() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/governance/proposals")
    }

    func vote(_ request: VoteRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/governance/vote", body: request)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C20: Dashboard
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func getDashboard() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/dashboard")
    }

    func getDashboardMetrics() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/dashboard/metrics")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C21: DEX
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func dexSwap(fromToken: String, toToken: String, amount: Double, slippage: Double = 0.5) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/dex/swap", body: [
            "from_token": fromToken, "to_token": toToken,
            "amount": "\(amount)", "slippage": "\(slippage)",
        ])
    }

    func dexQuote(fromToken: String, toToken: String, amount: Double) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/dex/quote", queryItems: [
            URLQueryItem(name: "from_token", value: fromToken),
            URLQueryItem(name: "to_token", value: toToken),
            URLQueryItem(name: "amount", value: "\(amount)"),
        ])
    }

    func dexListPools() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/dex/pools")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C22: Fundraising
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createCampaign(_ request: CampaignCreateRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/fundraising/campaigns", body: request)
    }

    func getCampaign(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/fundraising/campaigns/\(id)")
    }

    func listCampaigns() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/fundraising/campaigns")
    }

    func contributeToCampaign(_ request: ContributeRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/fundraising/contribute", body: request)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C23: Loyalty
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func getLoyaltyBalance() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/loyalty/balance")
    }

    func redeemLoyaltyPoints(amount: Int, rewardId: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/loyalty/redeem", body: ["amount": "\(amount)", "reward_id": rewardId])
    }

    func listLoyaltyRewards() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/loyalty/rewards")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C24: Marketplace
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createListing(_ request: ListingCreateRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/marketplace/listings", body: request)
    }

    func getListing(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/marketplace/listings/\(id)")
    }

    func listMarketplaceListings(query: String? = nil) async throws -> [String: AnyCodableValue] {
        var items: [URLQueryItem]?
        if let query { items = [URLQueryItem(name: "q", value: query)] }
        return try await get(path: "/api/v1/marketplace/listings", queryItems: items)
    }

    func purchaseListing(id: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/marketplace/listings/\(id)/purchase", body: EmptyBody())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C25: Cashback
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func getCashbackBalance() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/cashback/balance")
    }

    func listCashbackTransactions() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/cashback/transactions")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C26: Brand Rewards
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func listBrandRewards() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/brand-rewards")
    }

    func claimBrandReward(id: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/brand-rewards/\(id)/claim", body: EmptyBody())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C27: Subscriptions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func listSubscriptions() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/subscriptions")
    }

    func createSubscription(planId: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/subscriptions/create", body: ["plan_id": planId])
    }

    func cancelSubscription(id: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/subscriptions/\(id)/cancel", body: EmptyBody())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C28: Social
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createPost(_ request: PostCreateRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/social/posts", body: request)
    }

    func getPost(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/social/posts/\(id)")
    }

    func listFeed() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/social/feed")
    }

    func followUser(userId: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/social/follow", body: ["user_id": userId])
    }

    func getProfile(userId: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/social/profile/\(userId)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C29: Privacy
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func generatePrivacyProof(_ request: PrivacyProofRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/privacy/proof", body: request)
    }

    func verifyPrivacyProof(proofId: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/privacy/proof/\(proofId)/verify")
    }

    func getPrivacySettings() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/privacy/settings")
    }

    func updatePrivacySettings(settings: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/privacy/settings", body: settings)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C30: Disputes
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createDispute(_ request: DisputeCreateRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/disputes/create", body: request)
    }

    func getDispute(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/disputes/\(id)")
    }

    func listDisputes() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/disputes")
    }

    func submitDisputeEvidence(disputeId: String, evidence: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/disputes/\(disputeId)/evidence", body: evidence)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Phase 3: Memory
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func getMemory() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/memory")
    }

    func storeMemory(content: String, importance: Double? = nil) async throws -> [String: AnyCodableValue] {
        var body: [String: String] = ["content": content]
        if let importance { body["importance"] = "\(importance)" }
        return try await postRaw(path: "/api/v1/memory/store", body: body)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Phase 3: Goals
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func listGoals() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/goals")
    }

    func createGoal(title: String, description: String, targetDate: String? = nil) async throws -> [String: AnyCodableValue] {
        var body: [String: String] = ["title": title, "description": description]
        if let targetDate { body["target_date"] = targetDate }
        return try await postRaw(path: "/api/v1/goals", body: body)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Phase 3: Documents (RAG)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func searchDocuments(query: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/documents/search", queryItems: [
            URLQueryItem(name: "q", value: query),
        ])
    }

    func uploadDocument(name: String, content: String, mimeType: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/documents/upload", body: [
            "name": name, "content": content, "mime_type": mimeType,
        ])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Phase 3: Automation
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func listAutomations() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/automation")
    }

    func createAutomation(trigger: String, action: String, config: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/automation", body: [
            "trigger": AnyCodableValue.string(trigger),
            "action": AnyCodableValue.string(action),
            "config": AnyCodableValue.dictionary(config),
        ])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Phase 3: Code Execution
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func executeCode(language: String, code: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/execution/run", body: [
            "language": language, "code": code,
        ])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Phase 3: Check-Ins
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func listCheckIns() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/checkins")
    }

    func acknowledgeCheckIn(id: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/checkins/\(id)/acknowledge", body: EmptyBody())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Phase 3: Models
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func listModels() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/models")
    }

    func getModel(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/models/\(id)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Phase 3: Migration
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func startMigration(source: String, config: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/migration/start", body: [
            "source": AnyCodableValue.string(source),
            "config": AnyCodableValue.dictionary(config),
        ])
    }

    func getMigrationStatus(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/migration/\(id)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - OpenClaw Parity: Tasks
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func listTasks() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/tasks")
    }

    func createTask(prompt: String, channel: String? = nil) async throws -> [String: AnyCodableValue] {
        var body: [String: String] = ["prompt": prompt]
        if let channel { body["channel"] = channel }
        return try await postRaw(path: "/api/v1/tasks", body: body)
    }

    func getTask(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/tasks/\(id)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - OpenClaw Parity: Channels
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func listChannels() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/channels")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - OpenClaw Parity: Skills
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func listSkills() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/skills")
    }

    func installSkill(skillId: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/skills/install", body: ["skill_id": skillId])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - OpenClaw Parity: Doctor (Diagnostics)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func runDiagnostics() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/doctor/check")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Wallet (Aggregate)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func getWalletBalance() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/wallet/balance")
    }

    func getWalletTransactions(page: Int = 1, perPage: Int = 20) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/wallet/transactions", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ])
    }

    func walletSend(to: String, amount: Double, asset: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/wallet/send", body: [
            "to": to, "amount": "\(amount)", "asset": asset,
        ])
    }
}

// MARK: - AnyEncodable (type-erased Encodable wrapper)

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - EmptyBody

private struct EmptyBody: Encodable {}
