//
//  MTRXPackager.swift
//  MTRX
//
//  Mobile conversion layer bridging the 30-component Python runtime to the iOS app.
//  Handles type conversion, request packaging, response unpacking, transaction
//  serialization, context assembly, batch operations, offline queuing, and event streams.
//
//  Depends on MTRXAPIClient.shared for HTTP transport. This layer is purely
//  concerned with TYPE CONVERSION and ORCHESTRATION.
//

import Foundation
import Combine

// MARK: - Component Descriptor

/// Describes a single runtime component's API surface.
struct ComponentDescriptor: Sendable {
    let id: Int
    let name: String
    let path: String
    let category: ComponentFamily

    /// Full versioned API path.
    var versionedPath: String { "/api/v1\(path)" }

    /// Convenience for sub-resource paths.
    func subpath(_ resource: String) -> String {
        "\(versionedPath)/\(resource)"
    }
}

// MARK: - Component Family

enum ComponentFamily: String, Sendable, CaseIterable {
    case contracts
    case defi
    case identity
    case governance
    case marketplace
    case social
    case agents
    case analytics
    case rewards
    case compliance
}

// MARK: - Component Request

/// Wraps any Encodable payload with its target component and HTTP semantics.
struct ComponentRequest: Sendable {
    let componentId: Int
    let method: HTTPMethod
    let subpath: String?
    let body: (any Encodable & Sendable)?
    let queryItems: [URLQueryItem]?
    let idempotencyKey: String?

    init(
        componentId: Int,
        method: HTTPMethod = .post,
        subpath: String? = nil,
        body: (any Encodable & Sendable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        idempotencyKey: String? = nil
    ) {
        self.componentId = componentId
        self.method = method
        self.subpath = subpath
        self.body = body
        self.queryItems = queryItems
        self.idempotencyKey = idempotencyKey
    }
}

// MARK: - Packager Error

enum PackagerError: LocalizedError {
    case unknownComponent(Int)
    case encodingFailed(String)
    case decodingFailed(String)
    case invalidResponse(String)
    case batchPartialFailure(successes: Int, failures: Int)
    case offlineQueueFull(limit: Int)
    case conflictDetected(resource: String)
    case eventStreamDisconnected
    case serializationError(String)

    var errorDescription: String? {
        switch self {
        case .unknownComponent(let id):
            return "Unknown component ID: \(id)"
        case .encodingFailed(let detail):
            return "Packager encoding failed: \(detail)"
        case .decodingFailed(let detail):
            return "Packager decoding failed: \(detail)"
        case .invalidResponse(let detail):
            return "Invalid response structure: \(detail)"
        case .batchPartialFailure(let s, let f):
            return "Batch: \(s) succeeded, \(f) failed"
        case .offlineQueueFull(let limit):
            return "Offline queue at capacity (\(limit))"
        case .conflictDetected(let resource):
            return "Conflict on resource: \(resource)"
        case .eventStreamDisconnected:
            return "Event stream disconnected"
        case .serializationError(let detail):
            return "Serialization error: \(detail)"
        }
    }
}

// MARK: - Pagination Info

struct PaginationInfo: Sendable, Codable {
    let page: Int
    let perPage: Int
    let total: Int
    let totalPages: Int

    var hasNextPage: Bool { page < totalPages }
    var hasPreviousPage: Bool { page > 1 }
}

// MARK: - Unpacked Response

/// Generic response container preserving pagination and metadata alongside the decoded payload.
struct UnpackedResponse<T: Decodable>: Sendable where T: Sendable {
    let data: T
    let pagination: PaginationInfo?
    let txHash: String?
    let serverTimestamp: Date?
}

// MARK: - Transaction Packaging Types

struct UserOperationPackage: Codable, Sendable {
    let sender: String
    let nonce: String
    let initCode: String
    let callData: String
    let callGasLimit: String
    let verificationGasLimit: String
    let preVerificationGas: String
    let maxFeePerGas: String
    let maxPriorityFeePerGas: String
    let paymasterAndData: String
    let signature: String
}

struct ContractDeploymentPackage: Codable, Sendable {
    let templateId: String
    let constructorArgs: [String: AnyCodableValue]
    let salt: String?
    let chainId: Int
    let factoryAddress: String?
    let initCode: String?
}

struct TokenTransferPackage: Codable, Sendable {
    let tokenAddress: String
    let from: String
    let to: String
    let amount: String
    let decimals: Int
    let isNative: Bool
    let memo: String?
}

struct GasEstimationPackage: Codable, Sendable {
    let from: String
    let to: String
    let value: String
    let data: String
    let chainId: Int
}

struct GasEstimationResult: Codable, Sendable {
    let gasLimit: String
    let maxFeePerGas: String
    let maxPriorityFeePerGas: String
    let estimatedCostWei: String
    let estimatedCostUSD: Double
}

// MARK: - Context Packaging Types

struct PackagedDeviceInfo: Codable, Sendable {
    let model: String
    let osVersion: String
    let locale: String
    let timezone: String
    let appVersion: String
    let buildNumber: String
    let screenScale: Double
}

struct PackagedWalletState: Codable, Sendable {
    let isConnected: Bool
    let address: String?
    let balanceWei: String?
    let chainId: Int?
    let hasSmartAccount: Bool
}

struct PackagedSessionInfo: Codable, Sendable {
    let sessionId: String
    let startedAt: Date
    let durationSeconds: Int
    let actionsTaken: Int
    let lastComponent: Int?
    let screenPath: String?
}

struct PackagedUserContext: Codable, Sendable {
    let device: PackagedDeviceInfo
    let wallet: PackagedWalletState
    let session: PackagedSessionInfo
    let timestamp: Date
}

// MARK: - Batch Types

struct BatchRequestEnvelope: Codable, Sendable {
    let requests: [BatchItem]
    let sequential: Bool
    let abortOnFailure: Bool

    struct BatchItem: Codable, Sendable {
        let id: String
        let method: String
        let path: String
        let body: AnyCodableValue?
    }
}

struct BatchResponseEnvelope: Codable, Sendable {
    let results: [BatchItemResult]
    let totalDurationMs: Int?

    struct BatchItemResult: Codable, Sendable {
        let id: String
        let status: Int
        let body: AnyCodableValue?
        let error: String?
    }
}

// MARK: - Offline Queue Types

struct QueuedOperation: Codable, Identifiable, Sendable {
    let id: UUID
    let componentId: Int
    let method: String
    let path: String
    let bodyData: Data?
    let createdAt: Date
    let idempotencyKey: String
    let priority: QueuePriority
    var retryCount: Int
    let maxRetries: Int
    let expiresAt: Date?

    enum QueuePriority: Int, Codable, Comparable, Sendable {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3

        static func < (lhs: QueuePriority, rhs: QueuePriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var isExpired: Bool {
        if let expiresAt { return Date() > expiresAt }
        return false
    }

    var canRetry: Bool { retryCount < maxRetries && !isExpired }
}

// MARK: - Event Stream Types

enum ComponentEvent: Sendable {
    case transactionConfirmed(txHash: String, componentId: Int)
    case transactionFailed(txHash: String, error: String)
    case priceUpdate(asset: String, price: Double, change24h: Double)
    case proposalUpdate(proposalId: String, status: String)
    case attestationIssued(attestationId: String)
    case nftTransfer(tokenId: String, from: String, to: String)
    case loanHealthUpdate(loanId: String, healthFactor: Double)
    case stakingReward(validatorId: String, amount: Double)
    case socialNotification(type: String, from: String, content: String)
    case disputeUpdate(disputeId: String, status: String)
    case gasUpdate(slow: UInt64, standard: UInt64, fast: UInt64)
    case raw(component: Int, type: String, payload: [String: AnyCodableValue])
}

struct SSEMessage: Sendable {
    let event: String?
    let data: String
    let id: String?
    let retry: Int?
}

// MARK: - MTRXPackager

final class MTRXPackager: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = MTRXPackager()

    // MARK: - Private State

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let registry: [Int: ComponentDescriptor]

    private let lock = NSLock()
    private var _offlineQueue: [QueuedOperation] = []
    private var _eventSubscriptions: [Int: Set<UUID>] = [:]
    private var _sessionActions: Int = 0
    private var _sessionStart: Date = Date()
    private var _sessionId: String = UUID().uuidString
    private var _lastComponentUsed: Int? = nil

    private let offlineQueueLimit = 500
    private let offlineQueueKey = "com.mtrx.packager.offlineQueue"
    private let eventSubject = PassthroughSubject<ComponentEvent, Never>()
    private var eventStreamTask: Task<Void, Never>?
    private var connectivityTask: Task<Void, Never>?

    // MARK: - Public Publishers

    /// Stream of all component events across the system.
    var eventPublisher: AnyPublisher<ComponentEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    /// Filtered event publisher for a specific component.
    func events(for componentId: Int) -> AnyPublisher<ComponentEvent, Never> {
        eventSubject
            .filter { event in
                switch event {
                case .transactionConfirmed(_, let cid), .transactionFailed(_, _):
                    if case .transactionConfirmed(_, let cid) = event { return cid == componentId }
                    return true
                case .raw(let cid, _, _):
                    return cid == componentId
                default:
                    return true
                }
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Init

    private init() {
        // Build encoder with snake_case to match Python runtime
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        self.encoder = enc

        // Build decoder matching API client conventions
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .custom { decoder in
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
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
        }
        self.decoder = dec

        // Build component registry
        self.registry = Self.buildRegistry()

        // Restore offline queue from disk
        loadOfflineQueue()
    }

    // MARK: - Component Registry

    private static func buildRegistry() -> [Int: ComponentDescriptor] {
        let components: [(Int, String, String, ComponentFamily)] = [
            (1,  "Contract Conversion",  "/contracts",          .contracts),
            (2,  "DeFi Lending",         "/defi",               .defi),
            (3,  "NFT",                  "/nfts",               .contracts),
            (4,  "RWA Tokenization",     "/rwa",                .contracts),
            (5,  "Identity",             "/identity",           .identity),
            (6,  "DAO",                  "/dao",                .governance),
            (7,  "Stablecoin",           "/stablecoins",        .defi),
            (8,  "Attestation",          "/attestations",       .identity),
            (9,  "Agent Identity",       "/agents/identity",    .agents),
            (10, "Agentic Payments",     "/agents/payments",    .agents),
            (11, "Oracle",               "/oracle",             .analytics),
            (12, "Supply Chain",         "/supply-chain",       .contracts),
            (13, "Insurance",            "/insurance",          .defi),
            (14, "Gaming",              "/gaming",              .marketplace),
            (15, "IP Rights",            "/ip",                 .contracts),
            (16, "Staking",              "/staking",            .defi),
            (17, "Payments",             "/payments",           .defi),
            (18, "Securities",           "/securities",         .compliance),
            (19, "Governance",           "/governance",         .governance),
            (20, "Dashboard",            "/dashboard",          .analytics),
            (21, "DEX",                  "/dex",                .defi),
            (22, "Fundraising",          "/fundraising",        .marketplace),
            (23, "Loyalty",              "/loyalty",            .rewards),
            (24, "Marketplace",          "/marketplace",        .marketplace),
            (25, "Cashback",             "/cashback",           .rewards),
            (26, "Brand Rewards",        "/brand-rewards",      .rewards),
            (27, "Subscriptions",        "/subscriptions",      .marketplace),
            (28, "Social",               "/social",             .social),
            (29, "Privacy",              "/privacy",            .compliance),
            (30, "Disputes",             "/disputes",           .compliance),
        ]

        var map: [Int: ComponentDescriptor] = [:]
        map.reserveCapacity(components.count)
        for (id, name, path, family) in components {
            map[id] = ComponentDescriptor(id: id, name: name, path: path, category: family)
        }
        return map
    }

    /// Look up a component descriptor by ID.
    func component(_ id: Int) -> ComponentDescriptor? {
        registry[id]
    }

    /// All registered component descriptors.
    var allComponents: [ComponentDescriptor] {
        registry.values.sorted { $0.id < $1.id }
    }

    /// Components filtered by family.
    func components(in family: ComponentFamily) -> [ComponentDescriptor] {
        registry.values.filter { $0.category == family }.sorted { $0.id < $1.id }
    }

    // MARK: - Request Packaging

    /// Package a Swift Encodable into a URLRequest targeting the specified component.
    /// Adds auth headers, content type, API version, and snake-case key encoding.
    func package<T: Encodable>(
        _ request: T,
        for componentId: Int,
        method: HTTPMethod = .post,
        subpath: String? = nil,
        queryItems: [URLQueryItem]? = nil,
        idempotencyKey: String? = nil
    ) throws -> URLRequest {
        guard let descriptor = registry[componentId] else {
            throw PackagerError.unknownComponent(componentId)
        }

        let apiClient = MTRXAPIClient.shared
        var path = descriptor.versionedPath
        if let subpath {
            path += "/\(subpath)"
        }

        guard var components = URLComponents(string: apiClient.baseURL + path) else {
            throw PackagerError.encodingFailed("Invalid URL for path: \(path)")
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw PackagerError.encodingFailed("Cannot construct URL from components")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        // Standard headers
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("1.0", forHTTPHeaderField: "X-MTRX-API-Version")
        urlRequest.setValue("ios", forHTTPHeaderField: "X-MTRX-Platform")
        urlRequest.setValue(String(componentId), forHTTPHeaderField: "X-MTRX-Component")

        // Auth
        if let token = apiClient.authToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Idempotency
        if let key = idempotencyKey {
            urlRequest.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }

        // Encode body with snake_case keys
        if method != .get && method != .delete {
            do {
                urlRequest.httpBody = try encoder.encode(request)
            } catch {
                throw PackagerError.encodingFailed(error.localizedDescription)
            }
        }

        // Track session usage
        recordComponentUsage(componentId)

        return urlRequest
    }

    /// Package a ComponentRequest into a URLRequest.
    func package(_ request: ComponentRequest) throws -> URLRequest {
        if let body = request.body {
            return try package(
                AnyEncodableWrapper(body),
                for: request.componentId,
                method: request.method,
                subpath: request.subpath,
                queryItems: request.queryItems,
                idempotencyKey: request.idempotencyKey
            )
        } else {
            return try package(
                EmptyBody(),
                for: request.componentId,
                method: request.method,
                subpath: request.subpath,
                queryItems: request.queryItems,
                idempotencyKey: request.idempotencyKey
            )
        }
    }

    // MARK: - Response Unpacking

    /// Unpack raw API response data into a typed Swift object.
    /// Handles the APIResponse wrapper, extracts pagination, and provides clear errors.
    func unpack<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        // Try direct decode first (for simple responses)
        if let result = try? decoder.decode(type, from: data) {
            return result
        }

        // Try wrapped APIResponse format
        do {
            let wrapped = try decoder.decode(APIResponse<T>.self, from: data)
            if let errorMsg = wrapped.error, wrapped.success == false {
                throw PackagerError.invalidResponse(errorMsg)
            }
            if let payload = wrapped.data {
                return payload
            }
            throw PackagerError.decodingFailed(
                "Response wrapper contained no data for type \(String(describing: T.self))"
            )
        } catch let error as PackagerError {
            throw error
        } catch {
            throw PackagerError.decodingFailed(
                "Cannot decode \(String(describing: T.self)): \(error.localizedDescription)"
            )
        }
    }

    /// Unpack with full metadata including pagination and transaction hash.
    func unpackWithMeta<T: Decodable & Sendable>(
        _ data: Data,
        as type: T.Type
    ) throws -> UnpackedResponse<T> {
        let wrapped: APIResponse<T>
        do {
            wrapped = try decoder.decode(APIResponse<T>.self, from: data)
        } catch {
            // Fall back to direct decode without metadata
            let directResult = try unpack(data, as: type)
            return UnpackedResponse(
                data: directResult,
                pagination: nil,
                txHash: nil,
                serverTimestamp: nil
            )
        }

        if let errorMsg = wrapped.error, wrapped.success == false {
            throw PackagerError.invalidResponse(errorMsg)
        }

        guard let payload = wrapped.data else {
            throw PackagerError.decodingFailed("No data in API response wrapper")
        }

        var pagination: PaginationInfo? = nil
        if let meta = wrapped.meta, let page = meta.page, let perPage = meta.perPage, let total = meta.total {
            let totalPages = max(1, Int(ceil(Double(total) / Double(perPage))))
            pagination = PaginationInfo(
                page: page,
                perPage: perPage,
                total: total,
                totalPages: totalPages
            )
        }

        return UnpackedResponse(
            data: payload,
            pagination: pagination,
            txHash: wrapped.meta?.txHash,
            serverTimestamp: nil
        )
    }

    /// Unpack an array response with pagination support.
    func unpackList<T: Decodable & Sendable>(
        _ data: Data,
        as type: T.Type
    ) throws -> UnpackedResponse<[T]> {
        return try unpackWithMeta(data, as: [T].self)
    }

    // MARK: - Transaction Packaging

    /// Package a UserOperation for ERC-4337 submission.
    func packageUserOperation(
        sender: String,
        nonce: UInt64,
        callData: Data,
        callGasLimit: UInt64 = 200_000,
        verificationGasLimit: UInt64 = 100_000,
        preVerificationGas: UInt64 = 50_000,
        maxFeePerGas: UInt64,
        maxPriorityFeePerGas: UInt64,
        paymasterData: Data? = nil,
        signature: Data = Data()
    ) throws -> URLRequest {
        let op = UserOperationPackage(
            sender: sender,
            nonce: "0x\(String(nonce, radix: 16))",
            initCode: "0x",
            callData: "0x\(callData.map { String(format: "%02x", $0) }.joined())",
            callGasLimit: "0x\(String(callGasLimit, radix: 16))",
            verificationGasLimit: "0x\(String(verificationGasLimit, radix: 16))",
            preVerificationGas: "0x\(String(preVerificationGas, radix: 16))",
            maxFeePerGas: "0x\(String(maxFeePerGas, radix: 16))",
            maxPriorityFeePerGas: "0x\(String(maxPriorityFeePerGas, radix: 16))",
            paymasterAndData: paymasterData.map { "0x\($0.map { String(format: "%02x", $0) }.joined())" } ?? "0x",
            signature: signature.isEmpty ? "0x" : "0x\(signature.map { String(format: "%02x", $0) }.joined())"
        )

        // UserOperations go through the wallet infrastructure, component 1
        return try package(op, for: 1, subpath: "user-operations")
    }

    /// Package contract deployment parameters for the runtime.
    func packageContractDeployment(
        templateId: String,
        constructorArgs: [String: AnyCodableValue],
        chainId: Int = 8453,
        salt: String? = nil,
        factoryAddress: String? = nil
    ) throws -> URLRequest {
        let deployment = ContractDeploymentPackage(
            templateId: templateId,
            constructorArgs: constructorArgs,
            salt: salt,
            chainId: chainId,
            factoryAddress: factoryAddress,
            initCode: nil
        )
        return try package(deployment, for: 1, subpath: "deploy")
    }

    /// Package a token transfer (ERC-20 or native ETH).
    func packageTokenTransfer(
        tokenAddress: String,
        from: String,
        to: String,
        amount: String,
        decimals: Int = 18,
        isNative: Bool = false,
        memo: String? = nil
    ) throws -> URLRequest {
        let transfer = TokenTransferPackage(
            tokenAddress: tokenAddress,
            from: from,
            to: to,
            amount: amount,
            decimals: decimals,
            isNative: isNative,
            memo: memo
        )
        return try package(transfer, for: 17, subpath: "transfer")
    }

    /// Package gas estimation parameters and return the request.
    func packageGasEstimation(
        from: String,
        to: String,
        value: String = "0",
        data callData: String = "0x",
        chainId: Int = 8453
    ) throws -> URLRequest {
        let estimation = GasEstimationPackage(
            from: from,
            to: to,
            value: value,
            data: callData,
            chainId: chainId
        )
        return try package(estimation, for: 1, method: .post, subpath: "estimate-gas")
    }

    /// Unpack a gas estimation response.
    func unpackGasEstimation(_ data: Data) throws -> GasEstimationResult {
        return try unpack(data, as: GasEstimationResult.self)
    }

    // MARK: - Context Packaging

    /// Build a complete packaged device info snapshot.
    func packageDeviceInfo() -> PackagedDeviceInfo {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }

        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        let osString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

        return PackagedDeviceInfo(
            model: machine,
            osVersion: osString,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            appVersion: appVersion,
            buildNumber: buildNumber,
            screenScale: 3.0 // Default; actual scale set by UI layer
        )
    }

    /// Build a wallet state snapshot from current blockchain bridge state.
    func packageWalletState(
        isConnected: Bool,
        address: String? = nil,
        balanceWei: String? = nil,
        chainId: Int? = nil,
        hasSmartAccount: Bool = false
    ) -> PackagedWalletState {
        PackagedWalletState(
            isConnected: isConnected,
            address: address,
            balanceWei: balanceWei,
            chainId: chainId,
            hasSmartAccount: hasSmartAccount
        )
    }

    /// Build a session info snapshot capturing current session metrics.
    func packageSessionInfo() -> PackagedSessionInfo {
        let (sessionId, start, actions, lastComponent) = lock.withLock {
            (_sessionId, _sessionStart, _sessionActions, _lastComponentUsed)
        }
        let duration = Int(Date().timeIntervalSince(start))

        return PackagedSessionInfo(
            sessionId: sessionId,
            startedAt: start,
            durationSeconds: duration,
            actionsTaken: actions,
            lastComponent: lastComponent,
            screenPath: nil
        )
    }

    /// Assemble a complete user context package for Trinity agent conversations.
    func packageUserContext(
        walletConnected: Bool,
        walletAddress: String? = nil,
        balanceWei: String? = nil,
        chainId: Int? = nil,
        hasSmartAccount: Bool = false
    ) -> PackagedUserContext {
        PackagedUserContext(
            device: packageDeviceInfo(),
            wallet: packageWalletState(
                isConnected: walletConnected,
                address: walletAddress,
                balanceWei: balanceWei,
                chainId: chainId,
                hasSmartAccount: hasSmartAccount
            ),
            session: packageSessionInfo(),
            timestamp: Date()
        )
    }

    /// Encode the user context as a JSON dictionary for injection into agent messages.
    func packageUserContextAsJSON(
        walletConnected: Bool,
        walletAddress: String? = nil,
        balanceWei: String? = nil,
        chainId: Int? = nil,
        hasSmartAccount: Bool = false
    ) throws -> [String: AnyCodableValue] {
        let context = packageUserContext(
            walletConnected: walletConnected,
            walletAddress: walletAddress,
            balanceWei: balanceWei,
            chainId: chainId,
            hasSmartAccount: hasSmartAccount
        )
        let data = try encoder.encode(context)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PackagerError.serializationError("Context did not encode to a JSON object")
        }
        return dict.mapValues { AnyCodableValue.from($0) }
    }

    /// Record that a component was used (for session tracking).
    private func recordComponentUsage(_ componentId: Int) {
        lock.withLock {
            _sessionActions += 1
            _lastComponentUsed = componentId
        }
    }

    /// Reset session tracking (call on new app session).
    func resetSession() {
        lock.withLock {
            _sessionId = UUID().uuidString
            _sessionStart = Date()
            _sessionActions = 0
            _lastComponentUsed = nil
        }
    }

    // MARK: - Batch Operations

    /// Package multiple component requests into a single batch HTTP request.
    func batchPackage(
        _ requests: [ComponentRequest],
        sequential: Bool = false,
        abortOnFailure: Bool = false
    ) throws -> URLRequest {
        var batchItems: [BatchRequestEnvelope.BatchItem] = []

        for request in requests {
            guard let descriptor = registry[request.componentId] else {
                throw PackagerError.unknownComponent(request.componentId)
            }

            var path = descriptor.versionedPath
            if let subpath = request.subpath {
                path += "/\(subpath)"
            }

            var bodyValue: AnyCodableValue? = nil
            if let body = request.body {
                let data = try encoder.encode(AnyEncodableWrapper(body))
                if let jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    bodyValue = .dictionary(jsonObj.mapValues { AnyCodableValue.from($0) })
                }
            }

            let item = BatchRequestEnvelope.BatchItem(
                id: request.idempotencyKey ?? UUID().uuidString,
                method: request.method.rawValue,
                path: path,
                body: bodyValue
            )
            batchItems.append(item)
        }

        let envelope = BatchRequestEnvelope(
            requests: batchItems,
            sequential: sequential,
            abortOnFailure: abortOnFailure
        )

        let apiClient = MTRXAPIClient.shared
        guard let url = URL(string: apiClient.baseURL + "/api/v1/batch") else {
            throw PackagerError.encodingFailed("Invalid batch endpoint URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("1.0", forHTTPHeaderField: "X-MTRX-API-Version")
        urlRequest.setValue("ios", forHTTPHeaderField: "X-MTRX-Platform")
        urlRequest.setValue("batch", forHTTPHeaderField: "X-MTRX-Component")

        if let token = apiClient.authToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try encoder.encode(envelope)

        return urlRequest
    }

    /// Unpack a batch response, returning individual results keyed by their request ID.
    func unpackBatch(_ data: Data) throws -> BatchResponseEnvelope {
        return try unpack(data, as: BatchResponseEnvelope.self)
    }

    /// Unpack a specific item from a batch response into a typed result.
    func unpackBatchItem<T: Decodable>(
        _ batchResult: BatchResponseEnvelope.BatchItemResult,
        as type: T.Type
    ) throws -> T {
        guard batchResult.status >= 200 && batchResult.status < 300 else {
            throw PackagerError.invalidResponse(
                batchResult.error ?? "Batch item failed with status \(batchResult.status)"
            )
        }
        guard let body = batchResult.body else {
            throw PackagerError.decodingFailed("Batch item has no body")
        }
        let bodyData = try encoder.encode(body)
        return try decoder.decode(type, from: bodyData)
    }

    // MARK: - Offline Queue

    /// Enqueue an operation to be executed when connectivity returns.
    func enqueue(_ request: ComponentRequest, priority: QueuedOperation.QueuePriority = .normal) throws {
        guard let descriptor = registry[request.componentId] else {
            throw PackagerError.unknownComponent(request.componentId)
        }

        var bodyData: Data? = nil
        if let body = request.body {
            bodyData = try encoder.encode(AnyEncodableWrapper(body))
        }

        var path = descriptor.versionedPath
        if let sub = request.subpath {
            path += "/\(sub)"
        }

        let operation = QueuedOperation(
            id: UUID(),
            componentId: request.componentId,
            method: request.method.rawValue,
            path: path,
            bodyData: bodyData,
            createdAt: Date(),
            idempotencyKey: request.idempotencyKey ?? UUID().uuidString,
            priority: priority,
            retryCount: 0,
            maxRetries: 5,
            expiresAt: Calendar.current.date(byAdding: .hour, value: 24, to: Date())
        )

        try lock.withLock {
            guard _offlineQueue.count < offlineQueueLimit else {
                throw PackagerError.offlineQueueFull(limit: offlineQueueLimit)
            }
            _offlineQueue.append(operation)
        }

        persistOfflineQueue()
    }

    /// The current offline queue, sorted by priority (highest first) then creation date.
    var pendingOperations: [QueuedOperation] {
        lock.withLock {
            _offlineQueue
                .filter { !$0.isExpired }
                .sorted { lhs, rhs in
                    if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                    return lhs.createdAt < rhs.createdAt
                }
        }
    }

    /// Number of pending operations.
    var pendingCount: Int {
        lock.withLock { _offlineQueue.count }
    }

    /// Remove a specific operation from the queue.
    func dequeue(_ operationId: UUID) {
        lock.withLock {
            _offlineQueue.removeAll { $0.id == operationId }
        }
        persistOfflineQueue()
    }

    /// Drain the offline queue, building URLRequests for each operation.
    /// Returns operations paired with their constructed requests, removing them from the queue.
    func drainQueue() throws -> [(operation: QueuedOperation, request: URLRequest)] {
        let operations = pendingOperations

        var results: [(QueuedOperation, URLRequest)] = []

        for op in operations {
            let apiClient = MTRXAPIClient.shared
            guard let url = URL(string: apiClient.baseURL + op.path) else { continue }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = op.method
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.setValue("1.0", forHTTPHeaderField: "X-MTRX-API-Version")
            urlRequest.setValue("ios", forHTTPHeaderField: "X-MTRX-Platform")
            urlRequest.setValue(op.idempotencyKey, forHTTPHeaderField: "Idempotency-Key")

            if let token = apiClient.authToken {
                urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            urlRequest.httpBody = op.bodyData
            results.append((op, urlRequest))
        }

        // Remove drained operations
        let drainedIds = Set(operations.map(\.id))
        lock.withLock {
            _offlineQueue.removeAll { drainedIds.contains($0.id) }
        }
        persistOfflineQueue()

        return results
    }

    /// Mark an operation as failed, incrementing its retry count.
    /// If retriable, it stays in the queue; otherwise it is removed.
    func markFailed(_ operationId: UUID) {
        lock.withLock {
            guard let index = _offlineQueue.firstIndex(where: { $0.id == operationId }) else { return }
            _offlineQueue[index].retryCount += 1
            if !_offlineQueue[index].canRetry {
                _offlineQueue.remove(at: index)
            }
        }
        persistOfflineQueue()
    }

    /// Resolve a conflict by choosing the newer or older version.
    func resolveConflict(
        operationId: UUID,
        keepLocal: Bool
    ) {
        if keepLocal {
            // Re-enqueue with high priority to overwrite server state
            lock.withLock {
                if let index = _offlineQueue.firstIndex(where: { $0.id == operationId }) {
                    var op = _offlineQueue[index]
                    op = QueuedOperation(
                        id: op.id,
                        componentId: op.componentId,
                        method: "PUT",
                        path: op.path,
                        bodyData: op.bodyData,
                        createdAt: op.createdAt,
                        idempotencyKey: UUID().uuidString,
                        priority: .high,
                        retryCount: 0,
                        maxRetries: op.maxRetries,
                        expiresAt: op.expiresAt
                    )
                    _offlineQueue[index] = op
                }
            }
        } else {
            dequeue(operationId)
        }
        persistOfflineQueue()
    }

    /// Remove all expired operations from the queue.
    func purgeExpired() {
        lock.withLock {
            _offlineQueue.removeAll { $0.isExpired }
        }
        persistOfflineQueue()
    }

    /// Clear the entire offline queue.
    func clearQueue() {
        lock.withLock {
            _offlineQueue.removeAll()
        }
        persistOfflineQueue()
    }

    // MARK: - Offline Queue Persistence

    private func persistOfflineQueue() {
        let queue = lock.withLock { _offlineQueue }
        guard let data = try? encoder.encode(queue) else { return }
        UserDefaults.standard.set(data, forKey: offlineQueueKey)
    }

    private func loadOfflineQueue() {
        guard let data = UserDefaults.standard.data(forKey: offlineQueueKey),
              let queue = try? decoder.decode([QueuedOperation].self, from: data) else {
            return
        }
        lock.withLock {
            _offlineQueue = queue.filter { !$0.isExpired }
        }
    }

    // MARK: - Event Stream

    /// Start listening to the runtime's Server-Sent Events stream.
    func startEventStream() {
        stopEventStream()

        eventStreamTask = Task { [weak self] in
            guard let self else { return }
            let apiClient = MTRXAPIClient.shared
            guard let url = URL(string: apiClient.baseURL + "/api/v1/events/stream") else { return }

            while !Task.isCancelled {
                do {
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                    if let token = apiClient.authToken {
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    request.timeoutInterval = 0 // Keep alive indefinitely

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        // Backoff and retry
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        continue
                    }

                    var buffer = ""
                    var currentEvent: String? = nil
                    var currentId: String? = nil

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        if line.isEmpty {
                            // End of message: parse and emit
                            if !buffer.isEmpty {
                                let message = SSEMessage(
                                    event: currentEvent,
                                    data: buffer,
                                    id: currentId,
                                    retry: nil
                                )
                                self.handleSSEMessage(message)
                                buffer = ""
                                currentEvent = nil
                                currentId = nil
                            }
                            continue
                        }

                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if !buffer.isEmpty { buffer += "\n" }
                            buffer += data
                        } else if line.hasPrefix("id:") {
                            currentId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                        }
                    }
                } catch is CancellationError {
                    break
                } catch {
                    // Reconnect after delay
                    if !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                }
            }
        }
    }

    /// Stop listening to the event stream.
    func stopEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
    }

    /// Parse an SSE message and emit the appropriate ComponentEvent.
    private func handleSSEMessage(_ message: SSEMessage) {
        guard let jsonData = message.data.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }

        let eventType = message.event ?? (payload["type"] as? String) ?? "unknown"
        let componentId = payload["component_id"] as? Int

        let event: ComponentEvent

        switch eventType {
        case "transaction.confirmed":
            guard let txHash = payload["tx_hash"] as? String else { return }
            event = .transactionConfirmed(txHash: txHash, componentId: componentId ?? 0)

            // Auto-drain offline queue on confirmed connectivity
            drainQueueOnConnectivity()

        case "transaction.failed":
            guard let txHash = payload["tx_hash"] as? String else { return }
            let error = payload["error"] as? String ?? "Unknown error"
            event = .transactionFailed(txHash: txHash, error: error)

        case "price.update":
            guard let asset = payload["asset"] as? String,
                  let price = payload["price"] as? Double else { return }
            let change = payload["change_24h"] as? Double ?? 0
            event = .priceUpdate(asset: asset, price: price, change24h: change)

        case "proposal.update":
            guard let proposalId = payload["proposal_id"] as? String,
                  let status = payload["status"] as? String else { return }
            event = .proposalUpdate(proposalId: proposalId, status: status)

        case "attestation.issued":
            guard let attestationId = payload["attestation_id"] as? String else { return }
            event = .attestationIssued(attestationId: attestationId)

        case "nft.transfer":
            guard let tokenId = payload["token_id"] as? String,
                  let from = payload["from"] as? String,
                  let to = payload["to"] as? String else { return }
            event = .nftTransfer(tokenId: tokenId, from: from, to: to)

        case "loan.health":
            guard let loanId = payload["loan_id"] as? String,
                  let hf = payload["health_factor"] as? Double else { return }
            event = .loanHealthUpdate(loanId: loanId, healthFactor: hf)

        case "staking.reward":
            guard let validatorId = payload["validator_id"] as? String,
                  let amount = payload["amount"] as? Double else { return }
            event = .stakingReward(validatorId: validatorId, amount: amount)

        case "social.notification":
            guard let type = payload["notification_type"] as? String,
                  let from = payload["from"] as? String,
                  let content = payload["content"] as? String else { return }
            event = .socialNotification(type: type, from: from, content: content)

        case "dispute.update":
            guard let disputeId = payload["dispute_id"] as? String,
                  let status = payload["status"] as? String else { return }
            event = .disputeUpdate(disputeId: disputeId, status: status)

        case "gas.update":
            guard let slow = payload["slow"] as? UInt64,
                  let standard = payload["standard"] as? UInt64,
                  let fast = payload["fast"] as? UInt64 else { return }
            event = .gasUpdate(slow: slow, standard: standard, fast: fast)

        default:
            let codablePayload = payload.mapValues { AnyCodableValue.from($0) }
            event = .raw(
                component: componentId ?? 0,
                type: eventType,
                payload: codablePayload
            )
        }

        eventSubject.send(event)
    }

    /// Attempt to drain the offline queue when we detect connectivity.
    private func drainQueueOnConnectivity() {
        guard pendingCount > 0 else { return }
        connectivityTask?.cancel()
        connectivityTask = Task { [weak self] in
            guard let self else { return }
            do {
                let operations = try self.drainQueue()
                for (op, request) in operations {
                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                            if http.statusCode == 409 {
                                // Conflict: re-enqueue for manual resolution
                                try? self.enqueue(
                                    ComponentRequest(
                                        componentId: op.componentId,
                                        method: HTTPMethod(rawValue: op.method) ?? .post,
                                        body: op.bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }.map { AnyEncodableWrapper($0) },
                                        idempotencyKey: op.idempotencyKey
                                    ),
                                    priority: .high
                                )
                            } else {
                                self.markFailed(op.id)
                            }
                        }
                    } catch {
                        self.markFailed(op.id)
                    }
                }
            } catch {
                // Queue drain failed; will retry on next event
            }
        }
    }

    // MARK: - Convenience Builders

    /// Build a GET request for a component's list endpoint with pagination.
    func buildListRequest(
        componentId: Int,
        page: Int = 1,
        perPage: Int = 20,
        filters: [String: String]? = nil
    ) throws -> URLRequest {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if let filters {
            for (key, value) in filters.sorted(by: { $0.key < $1.key }) {
                queryItems.append(URLQueryItem(name: key, value: value))
            }
        }

        return try package(
            EmptyBody(),
            for: componentId,
            method: .get,
            queryItems: queryItems
        )
    }

    /// Build a GET request for a specific resource within a component.
    func buildDetailRequest(componentId: Int, resourceId: String) throws -> URLRequest {
        return try package(
            EmptyBody(),
            for: componentId,
            method: .get,
            subpath: resourceId
        )
    }

    /// Build a DELETE request for a specific resource.
    func buildDeleteRequest(componentId: Int, resourceId: String) throws -> URLRequest {
        return try package(
            EmptyBody(),
            for: componentId,
            method: .delete,
            subpath: resourceId
        )
    }
}

// MARK: - AnyEncodableWrapper

/// Type-erased Encodable wrapper for heterogeneous body types.
private struct AnyEncodableWrapper: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        self._encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - EmptyBody

/// Placeholder body for GET/DELETE requests that still need to pass through the generic pipeline.
private struct EmptyBody: Encodable {}

// MARK: - AnyCodableValue Extension

extension AnyCodableValue {
    /// Convert an arbitrary Foundation object to AnyCodableValue.
    static func from(_ value: Any) -> AnyCodableValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let dict as [String: Any]:
            return .dictionary(dict.mapValues { AnyCodableValue.from($0) })
        case let array as [Any]:
            return .array(array.map { AnyCodableValue.from($0) })
        default:
            return .null
        }
    }
}
