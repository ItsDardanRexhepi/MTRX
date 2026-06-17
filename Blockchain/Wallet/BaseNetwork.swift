// BaseNetwork.swift
// MTRX Blockchain - Wallet
//
// Base L2 mainnet connection and network configuration

import Foundation

// MARK: - Protocols

protocol NetworkProvider {
    func sendRPCRequest(_ request: JSONRPCRequest, completion: @escaping (Result<JSONRPCResponse, BlockchainNetworkError>) -> Void)
    func subscribe(to event: String, completion: @escaping (Result<Data, BlockchainNetworkError>) -> Void) -> String
    func unsubscribe(subscriptionId: String)
}

protocol WebSocketDelegate: AnyObject {
    func webSocket(didConnect url: URL)
    func webSocket(didDisconnect error: Error?)
    func webSocket(didReceiveMessage data: Data)
}

// MARK: - Data Models

struct JSONRPCRequest: Codable {
    let jsonrpc: String = "2.0"
    let method: String
    let params: [RPCParam]
    let id: Int

    enum RPCParam: Codable {
        case string(String)
        case int(Int)
        case bool(Bool)
        case dict([String: String])
        case array([String])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let v): try container.encode(v)
            case .int(let v): try container.encode(v)
            case .bool(let v): try container.encode(v)
            case .dict(let v): try container.encode(v)
            case .array(let v): try container.encode(v)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let v = try? container.decode(String.self) { self = .string(v); return }
            if let v = try? container.decode(Int.self) { self = .int(v); return }
            if let v = try? container.decode(Bool.self) { self = .bool(v); return }
            if let v = try? container.decode([String: String].self) { self = .dict(v); return }
            if let v = try? container.decode([String].self) { self = .array(v); return }
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown param type"))
        }
    }
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: Int
    let result: String?
    let error: RPCError?

    struct RPCError: Codable {
        let code: Int
        let message: String
    }
}

struct BlockInfo {
    let number: UInt64
    let hash: String
    let timestamp: Date
    let transactionCount: Int
    let gasUsed: UInt64
    let baseFeePerGas: UInt64
}

enum BlockchainNetworkError: Error, LocalizedError {
    case connectionFailed(reason: String)
    case requestTimeout
    case invalidResponse
    case rpcError(code: Int, message: String)
    case webSocketDisconnected
    case rateLimited
    case invalidChainId

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .requestTimeout: return "RPC request timed out."
        case .invalidResponse: return "Invalid response from RPC endpoint."
        case .rpcError(let code, let message): return "RPC error \(code): \(message)"
        case .webSocketDisconnected: return "WebSocket connection lost."
        case .rateLimited: return "RPC rate limit exceeded."
        case .invalidChainId: return "Connected to wrong chain."
        }
    }
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

// MARK: - BaseNetwork

final class BaseNetwork {

    // MARK: - Constants

    static let chainId: UInt64 = 8453
    static let chainName: String = "Base"
    static let nativeCurrency = NativeCurrency(name: "Ether", symbol: "ETH", decimals: 18)
    static let blockExplorerURL = URL(string: "https://basescan.org")!

    struct NativeCurrency {
        let name: String
        let symbol: String
        let decimals: Int
    }

    // MARK: - RPC Endpoints

    struct RPCEndpoints {
        /// Optional explicit override (used by tests). When nil, the active
        /// endpoints are read from PendingCredentials — no hardcoded URLs.
        let custom: URL?

        init(custom: URL? = nil) {
            self.custom = custom
        }

        /// Active HTTP JSON-RPC endpoint. `nil` until
        /// `PendingCredentials.Network.rpcURL` is filled in — callers then
        /// operate in a no-op/offline mode rather than hitting a hardcoded URL.
        var activeHTTP: URL? {
            if let custom { return custom }
            return PendingCredentials.filled(PendingCredentials.Network.rpcURL).flatMap { URL(string: $0) }
        }

        /// WebSocket endpoint for live subscriptions. `nil` → HTTP polling.
        var websocketURL: URL? {
            PendingCredentials.filled(PendingCredentials.Network.webSocketURL).flatMap { URL(string: $0) }
        }
    }

    // MARK: - Properties

    weak var webSocketDelegate: WebSocketDelegate?

    /// Current connection state
    private(set) var connectionState: ConnectionState = .disconnected

    /// RPC endpoints configuration
    let endpoints: RPCEndpoints

    /// Latest known block number
    private(set) var latestBlockNumber: UInt64 = 0

    /// Current gas price in wei
    private(set) var currentGasPrice: UInt64 = 0

    /// Active WebSocket subscriptions
    private var subscriptions: [String: (Data) -> Void] = [:]

    /// Request ID counter
    private var requestIdCounter: Int = 0

    /// Retry configuration
    private let maxRetries: Int = 3
    private let retryDelaySeconds: Double = 1.0

    /// Connection health monitoring
    private var lastSuccessfulRequest: Date?
    private var consecutiveFailures: Int = 0

    private let networkQueue = DispatchQueue(label: "com.mtrx.base.network", qos: .userInitiated)

    /// URLSession used for JSON-RPC POSTs.
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Live WebSocket transport (nil until connected / when unavailable).
    private var webSocketTask: URLSessionWebSocketTask?
    /// eth_subscribe request id → callback delivering the node's subscription id.
    private var subscribeReplies: [Int: (String) -> Void] = [:]
    /// node subscription id → newHeads handler.
    private var blockHandlers: [String: (BlockInfo) -> Void] = [:]
    /// node subscription id → pending-transaction handler.
    private var pendingTxHandlers: [String: (String) -> Void] = [:]
    /// local subscription id → node subscription id (for unsubscribe).
    private var localToNodeSub: [String: String] = [:]
    /// Polling timer used as the newHeads fallback when no WebSocket is set.
    private var pollTimer: DispatchSourceTimer?
    /// local subscription id → newHeads handler, driven by polling.
    private var pollBlockHandlers: [String: (BlockInfo) -> Void] = [:]

    // MARK: - Initialization

    init(endpoints: RPCEndpoints = RPCEndpoints()) {
        self.endpoints = endpoints
    }

    // MARK: - Connection Management

    /// Connect to Base network
    func connect(completion: @escaping (Result<Void, BlockchainNetworkError>) -> Void) {
        connectionState = .connecting

        // Verify chain ID
        getChainId { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let chainId):
                // Validate against the configured chain id when one is set;
                // with the blank empty we accept whatever the RPC reports.
                let expected = PendingCredentials.Network.chainID
                if expected != 0, chainId != UInt64(expected) {
                    self.connectionState = .disconnected
                    completion(.failure(.invalidChainId))
                    return
                }
                self.connectionState = .connected
                self.startBlockPolling()
                self.connectWebSocket()
                completion(.success(()))

            case .failure(let error):
                self.connectionState = .disconnected
                completion(.failure(error))
            }
        }
    }

    /// Disconnect from Base network
    func disconnect() {
        connectionState = .disconnected
        subscriptions.removeAll()
        blockHandlers.removeAll()
        pendingTxHandlers.removeAll()
        pollBlockHandlers.removeAll()
        localToNodeSub.removeAll()
        subscribeReplies.removeAll()
        pollTimer?.cancel()
        pollTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - RPC Methods

    /// Get the current chain ID
    func getChainId(completion: @escaping (Result<UInt64, BlockchainNetworkError>) -> Void) {
        let request = buildRequest(method: "eth_chainId", params: [])
        sendRequest(request) { result in
            switch result {
            case .success(let response):
                if let hexString = response.result {
                    let chainId = UInt64(hexString.dropFirst(2), radix: 16) ?? 0
                    completion(.success(chainId))
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Get the latest block number
    func getBlockNumber(completion: @escaping (Result<UInt64, BlockchainNetworkError>) -> Void) {
        let request = buildRequest(method: "eth_blockNumber", params: [])
        sendRequest(request) { [weak self] result in
            switch result {
            case .success(let response):
                if let hexString = response.result {
                    let blockNumber = UInt64(hexString.dropFirst(2), radix: 16) ?? 0
                    self?.latestBlockNumber = blockNumber
                    completion(.success(blockNumber))
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Get ETH balance for an address
    func getBalance(address: String, completion: @escaping (Result<UInt64, BlockchainNetworkError>) -> Void) {
        let request = buildRequest(method: "eth_getBalance", params: [.string(address), .string("latest")])
        sendRequest(request) { result in
            switch result {
            case .success(let response):
                if let hexString = response.result {
                    let balance = UInt64(hexString.dropFirst(2), radix: 16) ?? 0
                    completion(.success(balance))
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Get current gas price
    func getGasPrice(completion: @escaping (Result<UInt64, BlockchainNetworkError>) -> Void) {
        let request = buildRequest(method: "eth_gasPrice", params: [])
        sendRequest(request) { [weak self] result in
            switch result {
            case .success(let response):
                if let hexString = response.result {
                    let gasPrice = UInt64(hexString.dropFirst(2), radix: 16) ?? 0
                    self?.currentGasPrice = gasPrice
                    completion(.success(gasPrice))
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Send a raw transaction
    func sendRawTransaction(signedTx: String, completion: @escaping (Result<String, BlockchainNetworkError>) -> Void) {
        let request = buildRequest(method: "eth_sendRawTransaction", params: [.string(signedTx)])
        sendRequest(request) { result in
            switch result {
            case .success(let response):
                if let txHash = response.result {
                    completion(.success(txHash))
                } else if let error = response.error {
                    completion(.failure(.rpcError(code: error.code, message: error.message)))
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Call a contract method (read-only)
    func ethCall(to: String, data: String, completion: @escaping (Result<String, BlockchainNetworkError>) -> Void) {
        let callObject: JSONRPCRequest.RPCParam = .dict(["to": to, "data": data])
        let request = buildRequest(method: "eth_call", params: [callObject, .string("latest")])
        sendRequest(request) { result in
            switch result {
            case .success(let response):
                if let returnData = response.result {
                    completion(.success(returnData))
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Get transaction receipt
    func getTransactionReceipt(txHash: String, completion: @escaping (Result<JSONRPCResponse, BlockchainNetworkError>) -> Void) {
        let request = buildRequest(method: "eth_getTransactionReceipt", params: [.string(txHash)])
        sendRequest(request, completion: completion)
    }

    /// Get contract code at address
    func getCode(address: String, completion: @escaping (Result<String, BlockchainNetworkError>) -> Void) {
        let request = buildRequest(method: "eth_getCode", params: [.string(address), .string("latest")])
        sendRequest(request) { result in
            switch result {
            case .success(let response):
                completion(.success(response.result ?? "0x"))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - WebSocket

    /// Subscribe to new block headers. Uses WebSocket `eth_subscribe newHeads`
    /// when a WebSocket endpoint is configured, otherwise falls back to HTTP
    /// block-number polling (a documented tradeoff: polling delivers the block
    /// number but not the full header fields).
    func subscribeToNewBlocks(handler: @escaping (BlockInfo) -> Void) -> String {
        let localId = UUID().uuidString
        if webSocketTask != nil {
            let reqId = nextRequestId()
            subscribeReplies[reqId] = { [weak self] nodeSubId in
                self?.blockHandlers[nodeSubId] = handler
                self?.localToNodeSub[localId] = nodeSubId
            }
            sendWebSocket(["jsonrpc": "2.0", "id": reqId, "method": "eth_subscribe", "params": ["newHeads"]])
        } else {
            pollBlockHandlers[localId] = handler
            ensurePolling()
        }
        return localId
    }

    /// Subscribe to pending transactions (WebSocket `newPendingTransactions`;
    /// no polling fallback — pending-tx polling is not supported by HTTP RPC).
    func subscribeToPendingTransactions(address: String, handler: @escaping (String) -> Void) -> String {
        let localId = UUID().uuidString
        guard webSocketTask != nil else { return localId }
        let reqId = nextRequestId()
        subscribeReplies[reqId] = { [weak self] nodeSubId in
            self?.pendingTxHandlers[nodeSubId] = handler
            self?.localToNodeSub[localId] = nodeSubId
        }
        sendWebSocket(["jsonrpc": "2.0", "id": reqId, "method": "eth_subscribe", "params": ["newPendingTransactions"]])
        return localId
    }

    /// Unsubscribe from a subscription (WebSocket or polling).
    func unsubscribe(subscriptionId localId: String) {
        pollBlockHandlers.removeValue(forKey: localId)
        if pollBlockHandlers.isEmpty {
            pollTimer?.cancel()
            pollTimer = nil
        }
        if let nodeSub = localToNodeSub.removeValue(forKey: localId) {
            blockHandlers.removeValue(forKey: nodeSub)
            pendingTxHandlers.removeValue(forKey: nodeSub)
            sendWebSocket(["jsonrpc": "2.0", "id": nextRequestId(), "method": "eth_unsubscribe", "params": [nodeSub]])
        }
        subscriptions.removeValue(forKey: localId)
    }

    // MARK: - Block Explorer

    /// Build a block explorer URL for a transaction
    func explorerURL(forTransaction txHash: String) -> URL {
        return BaseNetwork.blockExplorerURL.appendingPathComponent("tx/\(txHash)")
    }

    /// Build a block explorer URL for an address
    func explorerURL(forAddress address: String) -> URL {
        return BaseNetwork.blockExplorerURL.appendingPathComponent("address/\(address)")
    }

    // MARK: - Health Check

    /// Check if the connection is healthy
    func isHealthy() -> Bool {
        guard connectionState == .connected else { return false }
        guard let lastSuccess = lastSuccessfulRequest else { return false }
        return Date().timeIntervalSince(lastSuccess) < 30.0
    }

    // MARK: - Private Helpers

    private func buildRequest(method: String, params: [JSONRPCRequest.RPCParam]) -> JSONRPCRequest {
        requestIdCounter += 1
        return JSONRPCRequest(method: method, params: params, id: requestIdCounter)
    }

    private func sendRequest(_ request: JSONRPCRequest, retryCount: Int = 0, completion: @escaping (Result<JSONRPCResponse, BlockchainNetworkError>) -> Void) {
        guard let url = endpoints.activeHTTP else {
            completion(.failure(.connectionFailed(reason: "RPC URL not set — fill PendingCredentials.Network.rpcURL")))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 30
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            completion(.failure(.invalidResponse))
            return
        }

        // Schedule a retry (with linear backoff) on the network queue.
        let retry: () -> Bool = { [weak self] in
            guard let self = self, retryCount < self.maxRetries else { return false }
            self.networkQueue.asyncAfter(deadline: .now() + self.retryDelaySeconds * Double(retryCount + 1)) {
                self.sendRequest(request, retryCount: retryCount + 1, completion: completion)
            }
            return true
        }

        urlSession.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            if let urlError = error as? URLError {
                let retriable: Set<URLError.Code> = [
                    .timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost,
                ]
                if retriable.contains(urlError.code), retry() { return }
                self.consecutiveFailures += 1
                completion(.failure(urlError.code == .timedOut
                    ? .requestTimeout
                    : .connectionFailed(reason: urlError.localizedDescription)))
                return
            }
            if let error = error {
                self.consecutiveFailures += 1
                completion(.failure(.connectionFailed(reason: error.localizedDescription)))
                return
            }

            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 {
                    if retry() { return }
                    completion(.failure(.rateLimited)); return
                }
                if http.statusCode >= 500 {
                    if retry() { return }
                    completion(.failure(.connectionFailed(reason: "HTTP \(http.statusCode)"))); return
                }
                guard (200..<300).contains(http.statusCode) else {
                    completion(.failure(.connectionFailed(reason: "HTTP \(http.statusCode)"))); return
                }
            }

            guard let data = data else { completion(.failure(.invalidResponse)); return }
            do {
                let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
                self.lastSuccessfulRequest = Date()
                self.consecutiveFailures = 0
                if let rpcErr = decoded.error {
                    completion(.failure(.rpcError(code: rpcErr.code, message: rpcErr.message)))
                } else {
                    completion(.success(decoded))
                }
            } catch {
                completion(.failure(.invalidResponse))
            }
        }.resume()
    }

    private func connectWebSocket() {
        guard let wsURL = endpoints.websocketURL else {
            // No WebSocket configured — newHeads uses HTTP polling on demand.
            return
        }
        let task = urlSession.webSocketTask(with: wsURL)
        webSocketTask = task
        task.resume()
        webSocketDelegate?.webSocket(didConnect: wsURL)
        receiveLoop()
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.webSocketDelegate?.webSocket(didDisconnect: error)
                self.webSocketTask = nil   // drop; polling can take over
            case .success(let message):
                self.handleWebSocketMessage(message)
                self.receiveLoop()
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        webSocketDelegate?.webSocket(didReceiveMessage: data)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

        // eth_subscribe reply: { id, result: "0x<subId>" }
        if let id = obj["id"] as? Int, let subId = obj["result"] as? String, let reply = subscribeReplies[id] {
            subscribeReplies.removeValue(forKey: id)
            reply(subId)
            return
        }
        // eth_subscription notification.
        if obj["method"] as? String == "eth_subscription",
           let params = obj["params"] as? [String: Any],
           let subId = params["subscription"] as? String {
            if let header = params["result"] as? [String: Any], let handler = blockHandlers[subId] {
                if let info = Self.blockInfo(fromHeader: header) { handler(info) }
            } else if let txHash = params["result"] as? String, let handler = pendingTxHandlers[subId] {
                handler(txHash)
            }
        }
    }

    private func sendWebSocket(_ payload: [String: Any]) {
        guard let task = webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else { return }
        task.send(.string(str)) { _ in }
    }

    private func nextRequestId() -> Int {
        requestIdCounter += 1
        return requestIdCounter
    }

    private func ensurePolling() {
        guard pollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: networkQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2.0)   // Base ~2s block time
        timer.setEventHandler { [weak self] in self?.pollTick() }
        pollTimer = timer
        timer.resume()
    }

    private func pollTick() {
        let previous = latestBlockNumber
        getBlockNumber { [weak self] result in
            guard let self = self, case .success(let n) = result,
                  n != previous, !self.pollBlockHandlers.isEmpty else { return }
            // Polling delivers the new block number; full header fields
            // (gasUsed / baseFee / hash) are only available over WebSocket.
            let info = BlockInfo(number: n, hash: "", timestamp: Date(),
                                 transactionCount: 0, gasUsed: 0, baseFeePerGas: self.currentGasPrice)
            for handler in self.pollBlockHandlers.values { handler(info) }
        }
    }

    private static func blockInfo(fromHeader header: [String: Any]) -> BlockInfo? {
        func hex(_ key: String) -> UInt64 {
            guard let s = header[key] as? String else { return 0 }
            return UInt64(s.hasPrefix("0x") ? String(s.dropFirst(2)) : s, radix: 16) ?? 0
        }
        return BlockInfo(
            number: hex("number"),
            hash: header["hash"] as? String ?? "",
            timestamp: Date(timeIntervalSince1970: TimeInterval(hex("timestamp"))),
            transactionCount: 0,
            gasUsed: hex("gasUsed"),
            baseFeePerGas: hex("baseFeePerGas")
        )
    }

    private func startBlockPolling() {
        // Polling is started lazily by newHeads subscribers when no WebSocket
        // is configured (see ensurePolling) — nothing to start eagerly.
    }
}
