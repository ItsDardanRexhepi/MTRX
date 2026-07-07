// MTRXAPIClient.swift
// Central networking layer for the MTRX iOS app.
// Connects to the 0pnMatrx gateway (aiohttp) — REST routes under /api/v1 + the
// mobile bridge under /bridge/v1. (Endpoint alignment tracked in ENDPOINT_MAP.md.)

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
    /// The server security gate (Morpheus) declined this action — blocked / frozen /
    /// paused / owner-approval-required. The associated string is the server's
    /// GENERIC, non-leaking message; the app surfaces it as-is and never shows an
    /// internal reason (the server doesn't send one).
    case securityBlocked(String)
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
        case .securityBlocked(let message):
            return message.isEmpty
                ? "This action couldn't be authorized for security reasons. Please try again."
                : message
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

    /// True when this is a server security-gate block — for UX branching (show a
    /// neutral "blocked for security" state rather than a generic network error).
    var isSecurityBlock: Bool {
        if case .securityBlocked = self { return true }
        return false
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

/// Typed contract for the social feed. The backend returns snake_case keys.
struct FeedResponse: Decodable {
    let posts: [FeedPost]

    struct FeedPost: Decodable {
        let id: String
        let displayName: String
        let handle: String
        let avatarInitials: String?
        let body: String
        let timestamp: Date?
        let isVerified: Bool?
        let proofHash: String?
        let governanceTag: String?
        let likeCount: Int?
        let repostCount: Int?
        let commentCount: Int?
    }
}

/// Typed contract for governance proposals (wrapped in `proposals`).
struct ProposalsResponse: Decodable {
    let proposals: [Proposal]
    struct Proposal: Decodable {
        let id: String
        let title: String
        let description: String
        let votesFor: Int
        let votesAgainst: Int
        let quorumProgress: Double?
        let endDate: Date?
        let status: String
        let hasVoted: Bool?
    }
}

/// Typed contract for real-world assets (wrapped in `assets`).
struct RWAAssetsResponse: Decodable {
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let category: String
        let apy: String?
        let minInvestment: String?
        let riskRating: String?
    }
}

/// Typed contract for insurance policies (wrapped in `policies`).
struct InsurancePoliciesResponse: Decodable {
    let policies: [Policy]
    struct Policy: Decodable {
        let coverageName: String
        let amount: String
        let premium: String
        let endDate: String
        let status: String
    }
}

/// Typed contract for loyalty programs + cashback.
struct LoyaltyResponse: Decodable {
    let programs: [Program]
    let cashback: [Cashback]
    struct Program: Decodable {
        let name: String
        let points: Int
        let tierName: String
    }
    struct Cashback: Decodable {
        let source: String
        let amount: String
        let token: String
        let earnedAt: String
        let claimed: Bool
    }
}

/// Typed contract for staking pools + positions.
struct StakingResponse: Decodable {
    let pools: [Pool]
    let positions: [Position]
    struct Pool: Decodable {
        let id: String?
        let token: String
        let symbol: String
        let apy: Double
        let totalStaked: Double
        let minStake: Double
    }
    struct Position: Decodable {
        let id: String?
        let token: String
        let symbol: String
        let stakedAmount: Double
        let rewardsEarned: Double
        let apy: Double
        let unbondingAmount: Double
        let unbondingDaysLeft: Int?
    }
}

/// Typed contract for liquidity pools (wrapped in `pools`).
struct LiquidityPoolsResponse: Decodable {
    let pools: [Pool]
    struct Pool: Decodable {
        let id: String?
        let tokenA: String
        let tokenB: String
        let apr: Double
        let tvl: Double
        let volume24h: Double
        let userShare: Double?
        let earnedFees: Double?
    }
}

/// Typed contract for creator-launched tokens (wrapped in `tokens`).
struct CreatorTokensResponse: Decodable {
    let tokens: [Token]
    struct Token: Decodable {
        let name: String
        let symbol: String
        let currentPrice: String
        let holders: Int
        let volume24h: String
    }
}

/// Typed contract for marketplace listings (wrapped in `listings`).
struct MarketplaceListingsResponse: Decodable {
    let listings: [Listing]
    struct Listing: Decodable {
        let name: String
        let description: String?
        let priceValue: Double
        let category: String?       // "All"/"Property"/"Digital"/"Services"/...
        let sellerName: String?
        let sellerRating: Double?
        let viewCount: Int?
    }
}

/// Typed contract for the NFT gallery (wrapped in `nfts`).
struct NFTGalleryResponse: Decodable {
    let nfts: [NFT]
    struct NFT: Decodable {
        let tokenId: String
        let contract: String?
        let name: String
        let collectionName: String?
        let imageUrl: String?
        let floorPrice: Double?
        let description: String?
    }
}

/// Typed contract for oracle price feeds (wrapped in `feeds`).
struct OracleFeedsResponse: Decodable {
    let feeds: [Feed]
    struct Feed: Decodable {
        let name: String
        let pair: String
        let currentValue: String
        let lastUpdated: String
        let isSubscribed: Bool?
    }
}

/// Typed contract for disputes (wrapped in `disputes`).
struct DisputesResponse: Decodable {
    let disputes: [Dispute]
    struct Dispute: Decodable {
        let counterparty: String
        let description: String?
        let stakeAmount: Double
        let status: String          // pending / active / resolved / rejected
        let votesFor: Int?
        let votesAgainst: Int?
        let deadline: Date?
        let wonByUser: Bool?
        let isJuryCase: Bool?
        let hasVoted: Bool?
        let claimed: Bool?
    }
}

/// Typed contract for a DAO's governance proposals (wrapped in `proposals`).
struct DAOProposalsResponse: Decodable {
    let proposals: [Proposal]
    struct Proposal: Decodable {
        let number: Int
        let title: String
        let description: String?
        let proposer: String
        let status: String          // Active / Passed / Rejected / No Quorum
        let votesFor: Int
        let votesAgainst: Int
        let quorumRequired: Int
        let timeRemaining: String?
    }
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

struct APITransactionResult: Decodable {
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

    /// An explicit base URL injected for tests (MockURLProtocol). When nil, `baseURL`
    /// resolves the CURRENT gateway at call time — see below.
    private let injectedBaseURL: String?

    /// Resolved FRESH on every request: injected override -> the runtime gateway URL set
    /// in Settings (Cloud Trinity) -> env -> the hosted default. Reading it fresh is what
    /// makes the REST path honor a gateway URL entered AFTER launch (the singleton used to
    /// freeze this at init, so a runtime-set gateway never reached REST — the WS path
    /// already reads fresh, so they diverged and the REST fallback hit the wrong host).
    var baseURL: String {
        injectedBaseURL
            ?? PendingCredentials.filled(PendingCredentials.effectiveGatewayURL)
            ?? ProcessInfo.processInfo.environment["MTRX_RUNTIME_URL"]
            ?? "https://api.openmatrix-ai.com"
    }
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Exposes the underlying URLSession so tests (and diagnostic tools) can
    /// observe the real session being used. Production code should stick to
    /// the convenience verbs above rather than reaching into the session.
    var urlSession: URLSession { session }

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

    init(baseURL: String? = nil, session: URLSession? = nil) {
        self.injectedBaseURL = baseURL

        if let session {
            // Tests (and any caller that wants to stub transport) can inject
            // a pre-configured session — typically one whose
            // URLSessionConfiguration has MockURLProtocol in its
            // `protocolClasses` array.
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            // A long multi-part agent reply is generated non-streaming server-side and
            // can take ~40s+ before the first byte returns; a 30s request timeout cut
            // the REST fallback off before it could finish (the long-reply failure).
            // 90s matches the chat WebSocket's silence budget so both paths tolerate a
            // slow generation; the 120s resource cap still bounds a truly dead request.
            config.timeoutIntervalForRequest = 90
            config.timeoutIntervalForResource = 120
            config.waitsForConnectivity = true
            config.httpAdditionalHeaders = [
                "User-Agent": "MTRX-iOS/1.0",
            ]
            self.session = URLSession(configuration: config)
        }

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
        authenticated: Bool = true,
        headers: [String: String]? = nil
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

        if let headers {
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }

        return request
    }

    private func execute<T: Decodable>(
        _ request: URLRequest,
        attempt: Int = 0,
        retryTimeouts: Bool = true
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
                // A caller can opt out of timeout-retries (retryTimeouts: false) to keep a
                // bounded worst case. The chat path does this so a silently-dead gateway
                // fails to an honest error in ~one request window instead of stacking
                // maxRetries×90s on top of the 90s WS budget (a multi-minute hang).
                if retryTimeouts && attempt < maxRetries {
                    let delay = retryDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await execute(request, attempt: attempt + 1, retryTimeouts: retryTimeouts)
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
            // A 403 is the security gate declining the action. Surface the server's
            // GENERIC message (it is already non-leaking) so the UI can show a clear
            // blocked / frozen / paused / owner-approval state — never an internal reason.
            throw MTRXAPIError.securityBlocked(Self.extractErrorMessage(from: data) ?? "")
        case 404:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MTRXAPIError.notFound(body)
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            if attempt < maxRetries {
                let delay = retryAfter ?? retryDelay(attempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await execute(request, attempt: attempt + 1, retryTimeouts: retryTimeouts)
            }
            throw MTRXAPIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            if attempt < maxRetries {
                let delay = retryDelay(attempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await execute(request, attempt: attempt + 1, retryTimeouts: retryTimeouts)
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

    /// Pull a human-readable message out of an error response body (the gateway
    /// returns `{"error": "..."}`; some routes use `{"message": "..."}`). Used to
    /// surface the security gate's generic, non-leaking denial to the user.
    static func extractErrorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (obj["error"] as? String) ?? (obj["message"] as? String)
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
        authenticated: Bool = true,
        retryTimeouts: Bool = true
    ) async throws -> T {
        let request = try buildRequest(method: .post, path: path, body: body, authenticated: authenticated)
        return try await execute(request, retryTimeouts: retryTimeouts)
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
        authenticated: Bool = true,
        headers: [String: String]? = nil
    ) async throws -> [String: AnyCodableValue] {
        let request = try buildRequest(method: .post, path: path, body: body,
                                       authenticated: authenticated, headers: headers)
        return try await execute(request)
    }

    // MARK: - Gateway Envelope + Wallet-Scoped Paths

    /// Gateway service routes wrap results as {"status":"ok","data":<payload>}
    /// (server.py core routes and /api/v1/price/eth-usd return bare JSON).
    struct GatewayEnvelope<T: Decodable>: Decodable {
        let status: String
        let data: T
    }

    /// GET a service route and unwrap its {status,data} envelope. A shape
    /// mismatch throws — callers fall back to their demo state, never to an
    /// invented payload.
    func getEnveloped<T: Decodable>(
        path: String, queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        let envelope: GatewayEnvelope<T> = try await get(path: path, queryItems: queryItems)
        return envelope.data
    }

    /// POST to a service route and unwrap its {status,data} envelope.
    func postEnveloped<Body: Encodable, T: Decodable>(
        path: String, body: Body
    ) async throws -> T {
        let envelope: GatewayEnvelope<T> = try await post(path: path, body: body)
        return envelope.data
    }

    /// Wallet address for wallet-scoped gateway paths ("" when no wallet is
    /// active yet — the resulting request 404s, an honest failure).
    func walletPathIdentity() async -> String {
        await MainActor.run { WalletCore.shared.address ?? "" }
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

    struct DeleteAccountResponse: Decodable {
        let success: Bool?
        let deletedAt: String?
    }

    /// Permanently delete the signed-in user's account and server-side data,
    /// and revoke the Sign in with Apple token. The backend should revoke the
    /// Apple authorization on its side as part of this call. Local data is
    /// wiped separately by `AppState.deleteAccount()`.
    @discardableResult
    func deleteAccount() async throws -> DeleteAccountResponse {
        let response: DeleteAccountResponse = try await delete(path: "/api/v1/auth/account")
        clearToken()
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
        agent: String,
        message: String,
        context: String = "",
        conversationHistory: [[String: String]] = []
    ) async throws -> AgentChatResponse {
        struct BridgeChatBody: Encodable {
            let message: String
            let agent: String
            let session_id: String
            // Carry the per-turn system/language context and recent history through to
            // the gateway so the language directive (and conversation memory) survive on
            // the non-Apple-Intelligence path instead of being silently dropped.
            let context: String?
            let history: [[String: String]]?
        }
        let body = BridgeChatBody(
            message: message,
            agent: agent,
            session_id: bridgeSessionId ?? "default",
            context: context.isEmpty ? nil : context,
            history: conversationHistory.isEmpty ? nil : conversationHistory
        )
        // retryTimeouts:false keeps the chat fallback bounded — a silently-dead gateway
        // fails to an honest error in one ~90s window rather than stacking 3 retries on
        // top of the WS 90s budget (the multi-minute-hang defect the adversarial pass found).
        let result: BridgeResponse<BridgeChatData> = try await post(
            path: "/bridge/v1/chat", body: body, retryTimeouts: false
        )
        guard let data = result.data else {
            throw MTRXAPIError.decodingFailed("No data in bridge response")
        }
        return AgentChatResponse(
            text: data.response,
            agent: data.agent,
            suggestedActions: nil,
            metadata: nil,
            conversationId: data.sessionId,
            toolCalls: nil
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Portfolio
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func getPortfolio() async throws -> PortfolioResponse {
        let wallet = await walletPathIdentity()
        return try await getEnveloped(path: "/api/v1/portfolio/complete/\(wallet)")
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

    /// NOT REMAPPED: the gateway has no lend-side route — /api/v1/defi/loan/create
    /// is borrow-side; representing a lend as a borrow would be wrong. This path
    /// stays unregistered (honest 404 → demo fallback) until a lend route exists.
    func defiLend(_ request: DeFiLendRequest) async throws -> [String: AnyCodableValue] {
        try await post(path: "/api/v1/defi/lend", body: request)
    }

    func defiBorrow(_ request: DeFiBorrowRequest) async throws -> [String: AnyCodableValue] {
        struct Body: Encodable {
            let borrower: String
            let collateralToken: String
            let collateralAmount: Double
            let borrowToken: String
            let borrowAmount: Double
        }
        let borrower = await walletPathIdentity()
        return try await post(path: "/api/v1/defi/loan/create", body: Body(
            borrower: borrower,
            collateralToken: request.collateralAsset,
            collateralAmount: request.collateralAmount,
            borrowToken: request.borrowAsset,
            borrowAmount: request.borrowAmount))
    }

    func defiRepay(loanId: String, amount: Double) async throws -> [String: AnyCodableValue] {
        struct DefiRepayBody: Encodable { let loan_id: String; let amount: Double }
        return try await post(path: "/api/v1/defi/loan/repay", body: DefiRepayBody(loan_id: loanId, amount: amount))
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

    /// The only registered attestation GET is the verify route — a raw-record
    /// read does not exist server-side, so this returns a verification result.
    func getAttestation(uid: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/attestation/verify/\(uid)")
    }

    func verifyAttestation(uid: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/attestation/verify/\(uid)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C9: Agent Identity
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func registerAgent(name: String, capabilities: [String]) async throws -> [String: AnyCodableValue] {
        struct Body: Encodable { let owner: String; let agentType: String; let capabilities: [String] }
        let owner = await walletPathIdentity()
        return try await post(path: "/api/v1/agent/register",
                              body: Body(owner: owner, agentType: name, capabilities: capabilities))
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

    /// ETH/USD uses the dedicated price route (bare JSON — Chainlink primary,
    /// Coinbase fallback, honest 503 when no source). Other pairs go through
    /// the singular oracle service route (enveloped).
    func getOraclePrice(feed: String) async throws -> [String: AnyCodableValue] {
        let pair = feed.lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "_", with: "-")
        if pair == "eth-usd" {
            return try await get(path: "/api/v1/price/eth-usd")
        }
        return try await get(path: "/api/v1/oracle/price/\(pair)")
    }

    func listOracleFeeds() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/oracles/feeds")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C12: Supply Chain
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createShipment(data: [String: AnyCodableValue]) async throws -> [String: AnyCodableValue] {
        struct Body: Encodable { let manufacturer: String; let productData: [String: AnyCodableValue] }
        let manufacturer = await walletPathIdentity()
        return try await postRaw(path: "/api/v1/supply-chain/register",
                                 body: Body(manufacturer: manufacturer, productData: data))
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
        struct Body: Encodable { let developer: String; let gameData: GameSubmitRequest }
        return try await post(path: "/api/v1/gaming/register",
                              body: Body(developer: request.developer, gameData: request))
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
        let wallet = await walletPathIdentity()
        return try await get(path: "/api/v1/portfolio/positions/\(wallet)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C17: Payments
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func sendPayment(to: String, amount: Double, currency: String, memo: String? = nil) async throws -> [String: AnyCodableValue] {
        struct Body: Encodable {
            let payer: String; let payee: String; let amount: Double
            let token: String; let memo: String?
        }
        let payer = await walletPathIdentity()
        // Fund-moving: routes through the App Attest attach path. INERT (identical to a
        // plain postRaw) until PendingCredentials.Security.appAttestEnabled is flipped on.
        return try await postFundMovingAttested(path: "/api/v1/payments/create",
                                                body: Body(payer: payer, payee: to, amount: amount,
                                                           token: currency, memo: memo))
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
        var body = data
        if body["issuer"] == nil {
            body["issuer"] = .string(await walletPathIdentity())
        }
        return try await postRaw(path: "/api/v1/securities/create", body: body)
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
        struct Body: Encodable {
            let proposer: String; let title: String; let description: String
            let actions: [[String: AnyCodableValue]]?
        }
        let proposer = await walletPathIdentity()
        return try await post(path: "/api/v1/governance/proposal/create",
                              body: Body(proposer: proposer, title: request.title,
                                         description: request.description, actions: request.actions))
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
        let wallet = await walletPathIdentity()
        return try await get(path: "/api/v1/dashboard/\(wallet)")
    }

    /// The gateway has no separate metrics route — the per-wallet overview IS
    /// the metrics payload. (The old /dashboard/metrics path silently pattern-
    /// matched /dashboard/{address} with address="metrics", a bogus wallet.)
    func getDashboardMetrics() async throws -> [String: AnyCodableValue] {
        try await getDashboard()
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
        struct Body: Encodable { let tokenIn: String; let tokenOut: String; let amount: Double }
        return try await post(path: "/api/v1/defi/swap/route",
                              body: Body(tokenIn: fromToken, tokenOut: toToken, amount: amount))
    }

    func dexListPools() async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/dex/pools")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C22: Fundraising
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createCampaign(_ request: CampaignCreateRequest) async throws -> [String: AnyCodableValue] {
        struct Body: Encodable {
            let creator: String; let title: String; let description: String
            let goal: Double; let milestones: [[String: AnyCodableValue]]?
        }
        let creator = await walletPathIdentity()
        return try await post(path: "/api/v1/fundraising/campaign/create",
                              body: Body(creator: creator, title: request.title,
                                         description: request.description,
                                         goal: request.goalAmount, milestones: request.milestones))
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
        struct Metadata: Encodable { let assetId: String; let currency: String; let description: String? }
        struct Body: Encodable {
            let seller: String; let itemType: String; let price: Double; let metadata: Metadata
        }
        let seller = await walletPathIdentity()
        return try await post(path: "/api/v1/marketplace/list",
                              body: Body(seller: seller, itemType: request.assetType, price: request.price,
                                         metadata: Metadata(assetId: request.assetId,
                                                            currency: request.currency,
                                                            description: request.description)))
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
        struct Body: Encodable { let listingId: String; let buyer: String }
        let buyer = await walletPathIdentity()
        return try await postRaw(path: "/api/v1/marketplace/buy", body: Body(listingId: id, buyer: buyer))
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
        struct Body: Encodable { let user: String; let planId: String; let paymentToken: String }
        let user = await walletPathIdentity()
        // paymentToken is empty until a payment method exists client-side; the
        // server validates and rejects rather than creating a bogus subscription.
        return try await postRaw(path: "/api/v1/subscriptions/subscribe",
                                 body: Body(user: user, planId: planId, paymentToken: ""))
    }

    func cancelSubscription(id: String) async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/api/v1/subscriptions/\(id)/cancel", body: EmptyBody())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C28: Social
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func createPost(_ request: PostCreateRequest) async throws -> [String: AnyCodableValue] {
        struct Body: Encodable { let author: String; let content: String; let media: [String]? }
        let author = await walletPathIdentity()
        return try await post(path: "/api/v1/social/post",
                              body: Body(author: author, content: request.content,
                                         media: request.attachments))
    }

    func getPost(id: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/api/v1/social/posts/\(id)")
    }

    func listFeed() async throws -> [String: AnyCodableValue] {
        let wallet = await walletPathIdentity()
        return try await get(path: "/api/v1/social/feed/\(wallet)")
    }

    /// Typed social feed — decodes into `FeedResponse`. Used by the Social tab
    /// and the Home feed window. A shape mismatch with the live gateway throws
    /// and the caller falls back to demo — never an invented feed.
    func feed() async throws -> FeedResponse {
        let wallet = await walletPathIdentity()
        return try await getEnveloped(path: "/api/v1/social/feed/\(wallet)")
    }

    /// Typed governance proposals.
    func governanceProposals() async throws -> ProposalsResponse {
        try await get(path: "/api/v1/governance/proposals")
    }

    /// Typed real-world assets.
    func rwaAssets() async throws -> RWAAssetsResponse {
        try await getEnveloped(path: "/api/v1/rwa/listings")
    }

    /// Typed insurance policies.
    func insurancePolicies() async throws -> InsurancePoliciesResponse {
        try await get(path: "/api/v1/insurance/policies")
    }

    /// Typed loyalty programs + cashback.
    func loyalty() async throws -> LoyaltyResponse {
        try await get(path: "/api/v1/loyalty")
    }

    /// Typed staking pools + positions — nearest registered read is the
    /// aggregator's per-wallet positions; a shape mismatch throws (demo fallback).
    func staking() async throws -> StakingResponse {
        let wallet = await walletPathIdentity()
        return try await getEnveloped(path: "/api/v1/portfolio/positions/\(wallet)")
    }

    /// Typed liquidity pools.
    func liquidityPools() async throws -> LiquidityPoolsResponse {
        try await get(path: "/api/v1/dex/pools")
    }

    /// Typed creator-launched tokens.
    func creatorTokens() async throws -> CreatorTokensResponse {
        try await get(path: "/api/v1/creator/tokens")
    }

    /// Typed marketplace listings.
    func marketplaceListings() async throws -> MarketplaceListingsResponse {
        try await get(path: "/api/v1/marketplace/listings")
    }

    /// Typed NFT gallery.
    func nftGallery() async throws -> NFTGalleryResponse {
        try await get(path: "/api/v1/nft")
    }

    /// Typed oracle price feeds.
    func oracleFeeds() async throws -> OracleFeedsResponse {
        try await get(path: "/api/v1/oracles/feeds")
    }

    /// Typed disputes.
    func disputes() async throws -> DisputesResponse {
        try await get(path: "/api/v1/disputes")
    }

    /// Typed DAO governance proposals.
    func daoProposals() async throws -> DAOProposalsResponse {
        try await get(path: "/api/v1/dao/proposals")
    }

    func followUser(userId: String) async throws -> [String: AnyCodableValue] {
        // Core route (bare JSON, no /api/v1 prefix); the server reads the
        // follower from the X-Wallet-Address header and the target from `address`.
        let follower = await walletPathIdentity()
        let headers = follower.isEmpty ? nil : ["X-Wallet-Address": follower]
        return try await postRaw(path: "/social/follow", body: ["address": userId], headers: headers)
    }

    /// Nearest registered profile read: the actor activity route (bare JSON,
    /// {actor, events, count}) — a profile document route does not exist yet.
    func getProfile(userId: String) async throws -> [String: AnyCodableValue] {
        try await get(path: "/social/actor/\(userId)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - C29: Privacy
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func generatePrivacyProof(_ request: PrivacyProofRequest) async throws -> [String: AnyCodableValue] {
        struct Body: Encodable {
            let prover: String; let proofType: String; let claim: [String: AnyCodableValue]
        }
        let prover = await walletPathIdentity()
        return try await post(path: "/api/v1/identity/zk-proof/generate",
                              body: Body(prover: prover, proofType: request.proofType,
                                         claim: request.claims))
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
        struct Body: Encodable {
            let complainant: String
            let respondent: String
            let disputeType: String
            let description: String
            let contractId: String
            let evidence: [String: AnyCodableValue]
        }
        let complainant = await walletPathIdentity()
        // respondent isn't known client-side yet — the server validates and
        // rejects rather than filing an incomplete dispute (honest failure).
        return try await post(path: "/api/v1/dispute/file",
                              body: Body(complainant: complainant, respondent: "",
                                         disputeType: "contract",
                                         description: request.description,
                                         contractId: request.contractId,
                                         evidence: request.evidence))
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

    /// Core memory routes (bare JSON, no /api/v1 prefix), keyed by agent name.
    func getMemory(agent: String = "neo") async throws -> [String: AnyCodableValue] {
        try await postRaw(path: "/memory/read", body: ["agent": agent])
    }

    func storeMemory(content: String, importance: Double? = nil,
                     agent: String = "neo", key: String = "ios-note") async throws -> [String: AnyCodableValue] {
        var body: [String: String] = ["agent": agent, "key": key, "value": content]
        if let importance { body["importance"] = "\(importance)" }
        return try await postRaw(path: "/memory/write", body: body)
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
        let wallet = await walletPathIdentity()
        return try await get(path: "/api/v1/portfolio/complete/\(wallet)")
    }

    func getWalletTransactions(page: Int = 1, perPage: Int = 20) async throws -> [String: AnyCodableValue] {
        // Pagination isn't supported by the aggregator history route yet.
        let wallet = await walletPathIdentity()
        return try await get(path: "/api/v1/portfolio/history/\(wallet)")
    }

    func walletSend(to: String, amount: Double, asset: String) async throws -> [String: AnyCodableValue] {
        struct Body: Encodable {
            let payer: String; let payee: String; let amount: Double; let token: String
        }
        let payer = await walletPathIdentity()
        // Fund-moving: adopts the App Attest attach path like sendPayment
        // (inert until PendingCredentials.Security.appAttestEnabled).
        return try await postFundMovingAttested(path: "/api/v1/payments/create",
                                                body: Body(payer: payer, payee: to,
                                                           amount: amount, token: asset))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 0pnMatrx Bridge
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Session ID for the bridge connection
    private(set) var bridgeSessionId: String?

    /// Create a new bridge session with the 0pnMatrx backend
    func bridgeCreateSession(deviceId: String = "") async throws -> BridgeSessionData {
        let body: [String: String] = [
            "device_id": deviceId,
            "app_version": "1.0.0",
        ]
        let result: BridgeResponse<BridgeSessionData> = try await post(
            path: "/bridge/v1/session/create", body: body
        )
        guard let data = result.data else {
            throw MTRXAPIError.decodingFailed("No session data")
        }
        bridgeSessionId = data.sessionId
        return data
    }

    /// Resume an existing bridge session
    func bridgeResumeSession(_ sessionId: String) async throws -> Bool {
        let body: [String: String] = ["session_id": sessionId]
        let result: BridgeResponse<BridgeResumeData> = try await post(
            path: "/bridge/v1/session/resume", body: body
        )
        if result.data?.resumed == true {
            bridgeSessionId = sessionId
            return true
        }
        return false
    }

    /// Execute a platform action directly (no chat, button-driven)
    func bridgeExecuteAction(
        _ action: String,
        params: [String: AnyCodableValue] = [:]
    ) async throws -> [String: AnyCodableValue] {
        struct BridgeActionBody: Encodable {
            let action: String
            let params: [String: AnyCodableValue]
            let session_id: String
        }
        let body = BridgeActionBody(action: action, params: params, session_id: bridgeSessionId ?? "default")
        return try await postRaw(path: "/bridge/v1/action", body: body)
    }

    /// Link a wallet to the current session
    func bridgeLinkWallet(address: String, network: String = "base-sepolia") async throws {
        let body: [String: String] = [
            "session_id": bridgeSessionId ?? "default",
            "address": address,
            "network": network,
        ]
        let _: BridgeResponse<BridgeLinkData> = try await post(
            path: "/bridge/v1/wallet/link", body: body
        )
    }

    /// Get wallet status
    func bridgeWalletStatus() async throws -> BridgeWalletStatus {
        let result: BridgeResponse<BridgeWalletStatus> = try await get(
            path: "/bridge/v1/wallet/status",
            queryItems: [URLQueryItem(name: "session_id", value: bridgeSessionId ?? "default")]
        )
        return result.data ?? BridgeWalletStatus(linked: false, address: nil, network: nil, balanceEth: nil)
    }

    /// Get app config from the backend
    func bridgeGetConfig() async throws -> BridgeConfigData {
        let result: BridgeResponse<BridgeConfigData> = try await get(
            path: "/bridge/v1/config", authenticated: false
        )
        guard let data = result.data else {
            throw MTRXAPIError.decodingFailed("No config data")
        }
        return data
    }

    /// Get service catalog
    func bridgeGetServices() async throws -> [BridgeService] {
        let result: BridgeResponse<BridgeServicesData> = try await get(
            path: "/bridge/v1/services", authenticated: false
        )
        return result.data?.services ?? []
    }

    /// Get dashboard data for home screen
    func bridgeGetDashboard() async throws -> BridgeDashboardData {
        let result: BridgeResponse<BridgeDashboardData> = try await get(
            path: "/bridge/v1/dashboard",
            queryItems: [URLQueryItem(name: "session_id", value: bridgeSessionId ?? "default")]
        )
        guard let data = result.data else {
            throw MTRXAPIError.decodingFailed("No dashboard data")
        }
        return data
    }

    // MARK: - Component Registry

    /// Get full component registry with UI schemas
    func bridgeGetComponents() async throws -> [BridgeComponent] {
        let result: BridgeResponse<BridgeComponentsData> = try await get(
            path: "/bridge/v1/components", authenticated: false
        )
        return result.data?.components ?? []
    }

    /// Get a single component by ID
    func bridgeGetComponent(id: String) async throws -> BridgeComponent {
        let result: BridgeResponse<BridgeComponent> = try await get(
            path: "/bridge/v1/components/\(id)", authenticated: false
        )
        guard let data = result.data else {
            throw MTRXAPIError.decodingFailed("Component not found: \(id)")
        }
        return data
    }

    /// Get component manifest (lightweight version check)
    func bridgeGetComponentManifest() async throws -> BridgeManifestData {
        let result: BridgeResponse<BridgeManifestData> = try await get(
            path: "/bridge/v1/components/manifest", authenticated: false
        )
        guard let data = result.data else {
            throw MTRXAPIError.decodingFailed("No manifest data")
        }
        return data
    }

    /// Register for push notifications
    func bridgeRegisterPush(token: String) async throws {
        let body: [String: String] = [
            "session_id": bridgeSessionId ?? "default",
            "push_token": token,
        ]
        let _: BridgeResponse<BridgePushData> = try await post(
            path: "/bridge/v1/push/register", body: body
        )
    }

    // MARK: - Capability Catalog (221 capabilities across 21 categories)
    //
    // These endpoints let the app discover every Web3 capability the
    // gateway can perform (not just the 30 legacy component endpoints).
    // Capabilities are the fine-grained unit: each has an id, category,
    // params schema, and a paymaster flag. The backend catalog lives at
    // runtime/capabilities/catalog.py.

    /// List every capability in the registry, optionally filtered by
    /// category ("defi", "nft", "staking", ...), min_tier, or
    /// availability. Returns the full catalog entry for each.
    func listCapabilities(
        category: String? = nil,
        minTier: String? = nil,
        availableOnly: Bool = false
    ) async throws -> CapabilityList {
        var items: [URLQueryItem] = []
        if let category { items.append(URLQueryItem(name: "category", value: category)) }
        if let minTier { items.append(URLQueryItem(name: "min_tier", value: minTier)) }
        if availableOnly { items.append(URLQueryItem(name: "available", value: "1")) }
        return try await get(path: "/api/v1/capabilities", queryItems: items)
    }

    /// List the 21 capability categories (each returns name, icon, count).
    func listCapabilityCategories() async throws -> CapabilityCategoriesResponse {
        try await get(path: "/api/v1/capabilities/categories")
    }

    /// Get the full descriptor for a single capability by id.
    func getCapability(id: String) async throws -> CapabilityDetail {
        try await get(path: "/api/v1/capabilities/\(id)")
    }

    /// Invoke a capability by id with the given params. The backend
    /// resolves the capability to its service+method and dispatches.
    /// Platform-sponsored gas is automatic for `uses_paymaster: true`.
    func invokeCapability(id: String, params: [String: AnyCodableValue] = [:]) async throws -> CapabilityInvokeResponse {
        let body = CapabilityInvokeBody(params: params)
        return try await post(path: "/api/v1/capabilities/\(id)/invoke", body: body)
    }
}

// MARK: - Capability Catalog Models

/// A single capability descriptor as returned by the backend catalog.
struct Capability: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let subcategory: String?
    let description: String?
    let service: String?
    let method: String?
    let action: String?
    let minTier: String?
    let usesPaymaster: Bool?
    let stateModifying: Bool?
    let protocol_: String?
    let available: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, category, subcategory, description
        case service, method, action
        case minTier = "min_tier"
        case usesPaymaster = "uses_paymaster"
        case stateModifying = "state_modifying"
        case protocol_ = "protocol"
        case available
    }
}

/// One of the 21 top-level categories.
struct CapabilityCategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String?
    let count: Int?
}

struct CapabilityList: Decodable {
    let capabilities: [Capability]
    let count: Int
}

struct CapabilityCategoriesResponse: Decodable {
    let categories: [CapabilityCategory]
}

struct CapabilityDetail: Decodable {
    let capability: Capability
}

struct CapabilityInvokeBody: Encodable {
    let params: [String: AnyCodableValue]
}

struct CapabilityInvokeResponse: Decodable {
    let status: String
    let capabilityId: String?
    let action: String?
    let result: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case status
        case capabilityId = "capability_id"
        case action, result
    }
}

// MARK: - Bridge Response Models

struct BridgeResponse<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?
    let timestamp: Double?
}

struct BridgeSessionData: Decodable {
    let sessionId: String
    let greeting: String
}

struct BridgeResumeData: Decodable {
    let sessionId: String
    let resumed: Bool
    let messageCount: Int?
}

struct BridgeChatData: Decodable {
    let response: String
    let agent: String
    let sessionId: String
    let provider: String?
}

struct BridgeLinkData: Decodable {
    let linked: Bool
    let address: String
}

struct BridgeWalletStatus: Decodable {
    let linked: Bool
    let address: String?
    let network: String?
    let balanceEth: String?
}

struct BridgeConfigData: Decodable {
    let platform: String
    let version: String
    let network: String
    let chainId: Int
    let agents: [String]
}

struct BridgeService: Decodable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let category: String
    let actions: [String]
}

struct BridgeServicesData: Decodable {
    let services: [BridgeService]
}

struct BridgeDashboardData: Decodable {
    let wallet: BridgeWalletStatus?
    let servicesAvailable: Int
    let activeSessions: Int
    let suggestions: [String]
}

struct BridgePushData: Decodable {
    let registered: Bool
}

// MARK: - Component Registry Models

struct BridgeComponentField: Decodable {
    let name: String
    let type: String
    let label: String
    let required: Bool
    let placeholder: String?
    let options: [String]?
}

struct BridgeComponentScreen: Decodable {
    let id: String
    let title: String
    let fields: [BridgeComponentField]
}

struct BridgeUIFlow: Decodable {
    let screens: [BridgeComponentScreen]
}

struct BridgeComponent: Decodable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let category: String
    let actions: [String]
    let version: String
    let capabilities: [String]
    let minAppVersion: String
    let uiFlow: BridgeUIFlow?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, description, category, actions, version, capabilities
        case minAppVersion = "min_app_version"
        case uiFlow = "ui_flow"
    }
}

struct BridgeComponentsData: Decodable {
    let components: [BridgeComponent]
}

struct BridgeManifestEntry: Decodable {
    let id: String
    let version: String
    let checksum: String
}

struct BridgeManifestData: Decodable {
    let manifest: [BridgeManifestEntry]
    let manifestVersion: String

    enum CodingKeys: String, CodingKey {
        case manifest
        case manifestVersion = "manifest_version"
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

// MARK: - Security: phone OTP (Phase 2)

struct OTPPhoneBody: Encodable { let phone: String }
struct OTPVerifyBody: Encodable { let phone: String; let code: String }

/// Mirrors the server's raw OTP response bodies (gateway returns 200 with the
/// outcome in the body). All fields optional so partial bodies still decode.
struct OTPSentResponse: Decodable {
    let sent: Bool?
    let reason: String?
    let expires_in: Int?
    let rate_limited: Bool?
}

struct OTPVerifyResponse: Decodable {
    let verified: Bool?
    let reason: String?
    let locked_out: Bool?
}

extension MTRXAPIClient {
    /// Send an SMS one-time code to *phone* (consumer phone connection).
    func requestPhoneOTP(phone: String) async throws -> OTPSentResponse {
        try await post(path: "/security/phone/request",
                       body: OTPPhoneBody(phone: phone), authenticated: false)
    }

    /// Verify the code the user typed. `verified == true` on success.
    func verifyPhoneOTP(phone: String, code: String) async throws -> OTPVerifyResponse {
        try await post(path: "/security/phone/verify",
                       body: OTPVerifyBody(phone: phone, code: code), authenticated: false)
    }
}

// MARK: - Security: App Attest (Package D) + biometric owner factor (Package E)
//
// Client interface to the Morpheus-Security-System App Attest verifier
// (morpheus_security/attest/app_attest.py). Endpoint PATHS follow the existing
// `/security/...` convention used by the phone-OTP routes above; the deployed
// gateway must expose these (the server module defines the verifier methods,
// new_challenge / verify_attestation / verify_assertion — the HTTP wiring is the
// gateway's, so confirm these paths against it before enabling). Snake_case JSON
// keys match the server kwargs exactly.

/// `GET /security/appattest/challenge` → a one-time 32-byte hex challenge.
struct AttestChallengeResponse: Decodable { let challenge: String }

/// `POST /security/appattest/attest` body (server: verify_attestation).
struct AttestVerifyBody: Encodable {
    let key_id: String
    let attestation_obj_b64: String
    let challenge: String
}

/// Raw server reply; fields optional so a partial body still decodes.
struct AttestVerifyResponse: Decodable {
    let verified: Bool?
    let reason: String?
}

/// Normalised attestation result handed back to AppAttestManager.
struct AttestVerifyResult {
    let verified: Bool
    let reason: String?
}

/// Wraps a fund-moving body and appends the App Attest `app_attest` envelope at the
/// SAME top level (the gate reads `context["app_attest"]`). When the envelope is nil
/// (observe mode could not produce one) the body is byte-for-byte the original.
struct AttestedBody<Base: Encodable>: Encodable {
    let base: Base
    let appAttest: AppAttestManager.Envelope?

    private enum CodingKeys: String, CodingKey { case app_attest }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)                       // flatten the original fields
        if let appAttest {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(appAttest, forKey: .app_attest)   // add app_attest alongside
        }
    }
}

extension MTRXAPIClient {

    /// Fetch a one-time App Attest challenge bound to *identity* (server: new_challenge).
    func fetchAttestChallenge(identity: String) async throws -> String {
        let resp: AttestChallengeResponse = try await get(
            path: "/security/appattest/challenge",
            queryItems: identity.isEmpty ? nil : [URLQueryItem(name: "identity", value: identity)],
            authenticated: true)
        return resp.challenge
    }

    /// Register a freshly attested key with the server (server: verify_attestation).
    /// One-time per install; AppAttestManager.registerIfNeeded drives this.
    func verifyAttestation(keyId: String, attestationObjectB64: String,
                           challenge: String) async throws -> AttestVerifyResult {
        let resp: AttestVerifyResponse = try await post(
            path: "/security/appattest/attest",
            body: AttestVerifyBody(key_id: keyId,
                                   attestation_obj_b64: attestationObjectB64,
                                   challenge: challenge))
        return AttestVerifyResult(verified: resp.verified ?? false, reason: resp.reason)
    }

    /// POST a fund-moving request, attaching a biometric-gated App Attest assertion
    /// when the client layer is enabled. Behaviour by flag (PendingCredentials.Security):
    ///   • appAttestEnabled OFF  → identical to `postRaw` (INERT: no challenge fetch, no
    ///                              biometric prompt, no assertion — the default).
    ///   • enabled, enforced OFF → best-effort: attach an assertion if one can be made,
    ///                              otherwise send without (the server observes).
    ///   • enabled, enforced ON  → an assertion is REQUIRED; if one can't be produced
    ///                              the request HARD-FAILS — never sent unattested.
    func postFundMovingAttested<Body: Encodable>(
        path: String, body: Body
    ) async throws -> [String: AnyCodableValue] {
        guard PendingCredentials.Security.appAttestEnabled else {
            return try await postRaw(path: path, body: body)
        }

        let identity = await currentSecurityIdentity()
        let requestBytes = (try? encoder.encode(AnyEncodable(body))) ?? Data()

        var envelope: AppAttestManager.Envelope?
        do {
            envelope = try await AppAttestManager.shared.fundMovingAssertion(
                for: requestBytes, identity: identity)
        } catch {
            // ENFORCE: never dress an unattested request as attested — fail closed.
            if PendingCredentials.Security.appAttestEnforced { throw error }
            // OBSERVE: proceed without; the server records would_block but allows.
            envelope = nil
        }

        // Thread the wallet identity so the server can attribute the action to the
        // right account (the gate reads it; the X-Wallet-Address header is the
        // server's primary identity source). Only on the enabled path — the inert
        // path above adds no header, so default behaviour is byte-for-byte unchanged.
        let headers = identity.isEmpty ? nil : ["X-Wallet-Address": identity]
        return try await postRaw(path: path,
                                 body: AttestedBody(base: body, appAttest: envelope),
                                 headers: headers)
    }

    /// The server-side identity (wallet address) the assertion binds to. Read on the
    /// main actor since WalletCore is @MainActor; empty string when no wallet is active.
    private func currentSecurityIdentity() async -> String {
        await MainActor.run { WalletCore.shared.address ?? "" }
    }

    // ⚠️ ADVISORY ONLY — NOT ENFORCEMENT (Requirement 5, Option B).
    //
    // Best-effort gate consult before a self-custody send. A self-custody on-chain
    // send is built/signed/submitted by the app (which holds the key), so the server
    // gate cannot physically veto it — the app must voluntarily consult and obey. This
    // hook does the minimum: it asks the gate and aborts ONLY on an explicit deny. An
    // absent / unreachable gate (no backend, missing endpoint, network error) PROCEEDS,
    // because the app is not the enforcement boundary and a testnet self-custody send
    // must not be blocked by an advisory layer that isn't deployed.
    //
    // *** This is NOT sufficient to move real money. *** Real pre-funds enforcement
    // requires the Option A server preflight endpoint (a fail-closed, blocking check) —
    // a HARD go-live blocker (R1/R2 tier), see SECURITY_REVIEW_CHECKLIST §14.8. Until
    // that exists, no real-value send may rely on this hook.
    //
    // Returns true = "not explicitly denied" (proceed); false = explicit gate deny (abort).
    func securityPreflightAllowsSend(to: String, valueUSD: Double, chainId: UInt64) async -> Bool {
        // No backend deployed (e.g. testnet today) -> no gate to consult -> proceed.
        guard PendingCredentials.isBackendConfigured else { return true }
        let body: [String: String] = [
            "to": to,
            "value_usd": "\(valueUSD)",
            "chain_id": "\(chainId)",
            "action_type": "transfer",
        ]
        do {
            _ = try await postFundMovingAttested(path: "/api/v1/security/preflight", body: body)
            return true
        } catch let err as MTRXAPIError where err.isSecurityBlock {
            return false   // explicit Morpheus deny -> abort the send
        } catch {
            // Advisory: an absent / unreachable gate must NOT block a self-custody send.
            return true
        }
    }

    /// P4: request a verifying-paymaster gas-sponsorship signature for a UserOperation.
    /// POSTs the userOp fields to `/api/v1/paymaster/sign`; returns the 0x-hex
    /// `paymasterAndData` (paymaster(20) || abi.encode(validUntil,validAfter) || sig(65))
    /// the client splices into the userOp. Returns nil when gas sponsorship isn't
    /// configured (honest: the send proceeds WITHOUT sponsorship, never a fake one) or
    /// the server declines by policy. Matches gateway/paymaster.py + the contract's
    /// digest. The async userOp-build integration (fetch → splice → eth_sendUserOperation)
    /// is the send-path wiring completed in the return pass, once the paymaster contract
    /// is deployed and `isGasSponsorshipConfigured`.
    func requestPaymasterAndData(_ body: [String: AnyCodableValue]) async -> String? {
        guard PendingCredentials.isGasSponsorshipConfigured else { return nil }
        struct PaymasterSignResponse: Decodable { let paymasterAndData: String }
        do {
            let resp: PaymasterSignResponse = try await post(
                path: "/api/v1/paymaster/sign", body: body)
            return resp.paymasterAndData
        } catch {
            // No sponsorship rather than a fabricated one — the send can still proceed
            // paying its own gas.
            return nil
        }
    }
}
