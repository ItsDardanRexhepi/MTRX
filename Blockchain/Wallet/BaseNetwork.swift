// BaseNetwork.swift
// MTRX Blockchain - Wallet
//
// Base L2 mainnet connection and network configuration

import Foundation

// MARK: - Protocols

protocol NetworkProvider {
    func sendRPCRequest(_ request: JSONRPCRequest, completion: @escaping (Result<JSONRPCResponse, NetworkError>) -> Void)
    func subscribe(to event: String, completion: @escaping (Result<Data, NetworkError>) -> Void) -> String
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

enum NetworkError: Error, LocalizedError {
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
        static let primary = URL(string: "https://mainnet.base.org")!
        static let fallback = URL(string: "https://base.llamarpc.com")!
        static let websocket = URL(string: "wss://base.publicnode.com")!
        static let bundler = URL(string: "https://bundler.base.org")!

        let custom: URL?

        init(custom: URL? = nil) {
            self.custom = custom
        }

        var activeHTTP: URL {
            return custom ?? RPCEndpoints.primary
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

    // MARK: - Initialization

    init(endpoints: RPCEndpoints = RPCEndpoints()) {
        self.endpoints = endpoints
    }

    // MARK: - Connection Management

    /// Connect to Base network
    func connect(completion: @escaping (Result<Void, NetworkError>) -> Void) {
        connectionState = .connecting

        // Verify chain ID
        getChainId { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let chainId):
                guard chainId == BaseNetwork.chainId else {
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
        // TODO: Close WebSocket connection
    }

    // MARK: - RPC Methods

    /// Get the current chain ID
    func getChainId(completion: @escaping (Result<UInt64, NetworkError>) -> Void) {
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
    func getBlockNumber(completion: @escaping (Result<UInt64, NetworkError>) -> Void) {
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
    func getBalance(address: String, completion: @escaping (Result<UInt64, NetworkError>) -> Void) {
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
    func getGasPrice(completion: @escaping (Result<UInt64, NetworkError>) -> Void) {
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
    func sendRawTransaction(signedTx: String, completion: @escaping (Result<String, NetworkError>) -> Void) {
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
    func ethCall(to: String, data: String, completion: @escaping (Result<String, NetworkError>) -> Void) {
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
    func getTransactionReceipt(txHash: String, completion: @escaping (Result<JSONRPCResponse, NetworkError>) -> Void) {
        let request = buildRequest(method: "eth_getTransactionReceipt", params: [.string(txHash)])
        sendRequest(request, completion: completion)
    }

    /// Get contract code at address
    func getCode(address: String, completion: @escaping (Result<String, NetworkError>) -> Void) {
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

    /// Subscribe to new block headers
    func subscribeToNewBlocks(handler: @escaping (BlockInfo) -> Void) -> String {
        let subscriptionId = UUID().uuidString
        // TODO: Send eth_subscribe via WebSocket for newHeads
        return subscriptionId
    }

    /// Subscribe to pending transactions for an address
    func subscribeToPendingTransactions(address: String, handler: @escaping (String) -> Void) -> String {
        let subscriptionId = UUID().uuidString
        // TODO: Send eth_subscribe via WebSocket for pendingTransactions
        return subscriptionId
    }

    /// Unsubscribe from a WebSocket subscription
    func unsubscribe(subscriptionId: String) {
        subscriptions.removeValue(forKey: subscriptionId)
        // TODO: Send eth_unsubscribe via WebSocket
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

    private func sendRequest(_ request: JSONRPCRequest, retryCount: Int = 0, completion: @escaping (Result<JSONRPCResponse, NetworkError>) -> Void) {
        networkQueue.async { [weak self] in
            guard let self = self else { return }

            // TODO: Serialize request to JSON
            // Send via URLSession to endpoints.activeHTTP
            // Parse response
            // On failure, retry with fallback endpoint

            self.lastSuccessfulRequest = Date()
            self.consecutiveFailures = 0

            let mockResponse = JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: nil, error: nil)
            completion(.success(mockResponse))
        }
    }

    private func connectWebSocket() {
        // TODO: Establish WebSocket connection to endpoints.websocket
        // Handle reconnection on disconnect
    }

    private func startBlockPolling() {
        // TODO: Poll for new blocks at regular intervals as fallback
        // Update latestBlockNumber
    }
}
