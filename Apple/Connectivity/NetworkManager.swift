// NetworkManager.swift
// MTRX Apple Integration — Connectivity
// Network framework TLS 1.3 QUIC transport for blockchain RPC

import Network
import Foundation

// MARK: - Network Manager

final class NetworkManager: ObservableObject {

    // MARK: - Shared Instance

    static let shared = NetworkManager()

    // MARK: - Properties

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.mtrx.networkMonitor")
    private var activeConnections: [String: NWConnection] = [:]
    private var webSocketConnection: NWConnection?

    @Published var isConnected = false
    @Published var connectionType: ConnectionType = .unknown
    @Published var isExpensive = false
    @Published var isConstrained = false

    // MARK: - Connection Type

    enum ConnectionType: String {
        case wifi
        case cellular
        case ethernet
        case unknown
    }

    // MARK: - Monitoring

    /// Starts monitoring network path changes.
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained

                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .ethernet
                } else {
                    self?.connectionType = .unknown
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Stops network monitoring.
    func stopMonitoring() {
        monitor.cancel()
    }

    // MARK: - TLS 1.3 Connection

    /// Creates a TLS 1.3 connection to a blockchain RPC endpoint.
    func createSecureConnection(host: String, port: UInt16) throws -> NWConnection {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        sec_protocol_options_set_max_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveInterval = 30
        tcpOptions.connectionTimeout = 15

        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        params.requiredInterfaceType = .wifi
        params.prohibitExpensivePaths = false
        params.prohibitConstrainedPaths = false

        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        activeConnections["\(host):\(port)"] = connection

        return connection
    }

    // MARK: - QUIC Connection

    /// Creates a QUIC connection for low-latency blockchain communication.
    @available(iOS 15.0, *)
    func createQUICConnection(host: String, port: UInt16) throws -> NWConnection {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        let quicOptions = NWProtocolQUIC.Options()
        quicOptions.direction = .bidirectional

        let params = NWParameters(quic: quicOptions)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)

        activeConnections["quic-\(host):\(port)"] = connection
        return connection
    }

    // MARK: - WebSocket Connection

    /// Establishes a WebSocket connection for real-time blockchain event streaming.
    func connectWebSocket(url: URL, onMessage: @escaping (Data) -> Void) {
        let tlsOptions = NWProtocolTLS.Options()
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        let params = NWParameters(tls: tlsOptions)
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let connection = NWConnection(to: .url(url), using: params)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveWebSocketMessage(connection: connection, handler: onMessage)
            case .failed(let error):
                self?.handleConnectionFailure(error)
            default:
                break
            }
        }

        webSocketConnection = connection
        connection.start(queue: DispatchQueue(label: "com.mtrx.websocket"))
    }

    private func receiveWebSocketMessage(connection: NWConnection, handler: @escaping (Data) -> Void) {
        connection.receiveMessage { content, context, isComplete, error in
            if let data = content {
                handler(data)
            }
            if error == nil {
                self.receiveWebSocketMessage(connection: connection, handler: handler)
            }
        }
    }

    /// Sends data through the WebSocket connection.
    func sendWebSocketMessage(_ data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "ws-message", metadata: [metadata])

        webSocketConnection?.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ _ in }))
    }

    /// Sends a JSON-RPC request through WebSocket.
    func sendJSONRPC(method: String, params: [Any], id: Int = 1) throws {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": id
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        sendWebSocketMessage(data)
    }

    // MARK: - Connection Management

    /// Sends data over a specific connection.
    func send(data: Data, on connection: NWConnection, completion: @escaping (Error?) -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in
            completion(error)
        })
    }

    /// Receives data from a specific connection.
    func receive(on connection: NWConnection, completion: @escaping (Result<Data, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
            if let error = error {
                completion(.failure(error))
            } else if let data = data {
                completion(.success(data))
            }
        }
    }

    /// Disconnects all active connections.
    func disconnectAll() {
        activeConnections.values.forEach { $0.cancel() }
        activeConnections.removeAll()
        webSocketConnection?.cancel()
        webSocketConnection = nil
    }

    // MARK: - Error Handling

    private func handleConnectionFailure(_ error: NWError) {
        // Attempt reconnection with exponential backoff
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    // MARK: - Path Evaluation

    /// Evaluates whether the current network path supports a given endpoint.
    func evaluatePath(to host: String, port: UInt16) async -> Bool {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let params = NWParameters.tls
        let connection = NWConnection(to: endpoint, using: params)

        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue(label: "com.mtrx.pathEval"))
        }
    }
}

// MARK: - Network Error

enum NetworkError: LocalizedError {
    case noConnection
    case tlsHandshakeFailed
    case quicUnavailable
    case connectionTimeout
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .noConnection: return "No network connection available"
        case .tlsHandshakeFailed: return "TLS 1.3 handshake failed"
        case .quicUnavailable: return "QUIC transport is not available"
        case .connectionTimeout: return "Connection timed out"
        case .invalidEndpoint: return "Invalid network endpoint"
        }
    }
}
