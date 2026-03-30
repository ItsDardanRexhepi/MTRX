//
//  BlockchainPublisher.swift
//  MTRX
//
//  Real-time blockchain state stream via WebSocket, bridged to Combine publishers.
//

import Foundation
import Combine

// MARK: - Block Data

struct BlockData: Equatable {
    let number: UInt64
    let hash: String
    let timestamp: Date
    let transactionCount: Int
    let gasUsed: UInt64
    let gasLimit: UInt64
    let baseFeePerGas: UInt64?
}

// MARK: - Pending Transaction Data

struct PendingTransactionData: Equatable {
    let hash: String
    let from: String
    let to: String?
    let value: String
    let gasPrice: String
    let nonce: UInt64
    let input: Data
}

// MARK: - Contract Event Data

struct ContractEventData: Equatable, Identifiable {
    let id: String
    let contractAddress: String
    let eventName: String
    let topics: [String]
    let data: Data
    let blockNumber: UInt64
    let transactionHash: String
    let logIndex: Int
}

// MARK: - Gas Price Data

struct GasPriceData: Equatable {
    let slow: UInt64
    let standard: UInt64
    let fast: UInt64
    let instant: UInt64
    let baseFee: UInt64
    let suggestedTip: UInt64
    let timestamp: Date
}

// MARK: - Connection State

enum WebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(String)
}

// MARK: - Blockchain Publisher

/// Provides real-time blockchain data via Combine publishers over WebSocket.
final class BlockchainPublisher: ObservableObject {

    // MARK: - Published Streams

    /// Emits each new block as it is mined.
    let newBlocks = PassthroughSubject<BlockData, Never>()

    /// Emits pending transactions from the mempool.
    let pendingTransactions = PassthroughSubject<PendingTransactionData, Never>()

    /// Emits smart contract events matching subscribed filters.
    let contractEvents = PassthroughSubject<ContractEventData, Never>()

    /// Emits updated gas price estimates.
    let gasPrice = CurrentValueSubject<GasPriceData?, Never>(nil)

    /// Current WebSocket connection state.
    @Published private(set) var connectionState: WebSocketConnectionState = .disconnected

    // MARK: - Configuration

    private let rpcEndpoint: URL
    private let chainId: Int
    private let maxReconnectAttempts: Int
    private let reconnectDelay: TimeInterval

    // MARK: - Internal State

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var cancellables = Set<AnyCancellable>()
    private var reconnectAttempt = 0
    private var subscribedEventFilters: [String: [String]] = [:]
    private var heartbeatTimer: AnyCancellable?
    private var isManualDisconnect = false

    // MARK: - Initialization

    init(
        rpcEndpoint: URL,
        chainId: Int = 1,
        maxReconnectAttempts: Int = 10,
        reconnectDelay: TimeInterval = 2.0
    ) {
        self.rpcEndpoint = rpcEndpoint
        self.chainId = chainId
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelay = reconnectDelay
        self.urlSession = URLSession(configuration: .default)
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Lifecycle

    /// Opens the WebSocket connection and begins receiving blockchain data.
    func connect() {
        guard connectionState == .disconnected ||
              connectionState == .failed("") else { return }

        isManualDisconnect = false
        connectionState = .connecting

        let task = urlSession.webSocketTask(with: rpcEndpoint)
        webSocketTask = task
        task.resume()

        connectionState = .connected
        reconnectAttempt = 0

        subscribeToNewBlocks()
        subscribeToGasPrice()
        startHeartbeat()
        receiveMessages()
    }

    /// Gracefully closes the WebSocket connection.
    func disconnect() {
        isManualDisconnect = true
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    // MARK: - Subscriptions

    /// Subscribes to contract events for a given address and event signature.
    func subscribeToContractEvents(contractAddress: String, eventSignatures: [String]) {
        subscribedEventFilters[contractAddress] = eventSignatures
        guard connectionState == .connected else { return }

        let params: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().hashValue,
            "method": "eth_subscribe",
            "params": ["logs", ["address": contractAddress, "topics": [eventSignatures]]]
        ]
        sendJSON(params)
    }

    /// Unsubscribes from contract events for a given address.
    func unsubscribeFromContractEvents(contractAddress: String) {
        subscribedEventFilters.removeValue(forKey: contractAddress)
    }

    // MARK: - Private: WebSocket Communication

    private func subscribeToNewBlocks() {
        let params: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_subscribe",
            "params": ["newHeads"]
        ]
        sendJSON(params)
    }

    private func subscribeToGasPrice() {
        // Gas price polling via JSON-RPC since eth_gasPrice is not a subscription
        Timer.publish(every: 12.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchGasPrice()
            }
            .store(in: &cancellables)
    }

    private func fetchGasPrice() {
        let params: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "eth_gasPrice",
            "params": []
        ]
        sendJSON(params)
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessages() // Continue listening

            case .failure(let error):
                self.handleConnectionError(error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            parseRPCResponse(json)

        case .data(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            parseRPCResponse(json)

        @unknown default:
            break
        }
    }

    private func parseRPCResponse(_ json: [String: Any]) {
        guard let params = json["params"] as? [String: Any],
              let result = params["result"] as? [String: Any] else {
            return
        }

        if let numberHex = result["number"] as? String {
            let block = parseBlockData(result, numberHex: numberHex)
            DispatchQueue.main.async { [weak self] in
                self?.newBlocks.send(block)
            }
        }

        if let address = result["address"] as? String {
            let event = parseContractEvent(result, address: address)
            DispatchQueue.main.async { [weak self] in
                self?.contractEvents.send(event)
            }
        }
    }

    private func parseBlockData(_ result: [String: Any], numberHex: String) -> BlockData {
        BlockData(
            number: UInt64(numberHex.dropFirst(2), radix: 16) ?? 0,
            hash: result["hash"] as? String ?? "",
            timestamp: Date(),
            transactionCount: (result["transactions"] as? [Any])?.count ?? 0,
            gasUsed: 0,
            gasLimit: 0,
            baseFeePerGas: nil
        )
    }

    private func parseContractEvent(_ result: [String: Any], address: String) -> ContractEventData {
        ContractEventData(
            id: UUID().uuidString,
            contractAddress: address,
            eventName: "",
            topics: result["topics"] as? [String] ?? [],
            data: Data(),
            blockNumber: 0,
            transactionHash: result["transactionHash"] as? String ?? "",
            logIndex: 0
        )
    }

    // MARK: - Private: Reconnection

    private func handleConnectionError(_ error: Error) {
        guard !isManualDisconnect else { return }

        if reconnectAttempt < maxReconnectAttempts {
            reconnectAttempt += 1
            connectionState = .reconnecting(attempt: reconnectAttempt)

            let delay = reconnectDelay * pow(1.5, Double(reconnectAttempt - 1))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.connect()
            }
        } else {
            connectionState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Private: Heartbeat

    private func startHeartbeat() {
        heartbeatTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendPing()
            }
    }

    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if error != nil {
                self?.handleConnectionError(error!)
            }
        }
    }

    // MARK: - Private: Utilities

    private func sendJSON(_ params: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: params),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }
}
