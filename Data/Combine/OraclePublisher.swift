//
//  OraclePublisher.swift
//  MTRX
//
//  Oracle data stream with throttled Combine publishers for price feeds,
//  attestation updates, and cross-chain data.
//

import Foundation
import Combine

// MARK: - Price Feed Data

struct PriceFeedData: Equatable, Identifiable {
    let id: String
    let pair: String
    let price: Decimal
    let decimals: Int
    let roundId: UInt64
    let updatedAt: Date
    let answeredInRound: UInt64
    let source: OracleSource

    /// Price formatted to the correct decimal places.
    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: price as NSDecimalNumber) ?? "\(price)"
    }
}

// MARK: - Attestation Data

struct PublisherAttestationData: Equatable, Identifiable {
    let id: String
    let attester: String
    let subject: String
    let schema: String
    let data: Data
    let timestamp: Date
    let expirationTime: Date?
    let revoked: Bool
    let chainId: Int
}

// MARK: - Cross-Chain Data

struct CrossChainData: Equatable, Identifiable {
    let id: String
    let sourceChainId: Int
    let destinationChainId: Int
    let messageHash: String
    let payload: Data
    let status: CrossChainMessageStatus
    let timestamp: Date
}

enum CrossChainMessageStatus: String, Codable, Equatable {
    case pending
    case relayed
    case confirmed
    case failed
    case expired
}

// MARK: - Oracle Source

enum OracleSource: String, Codable, Equatable, CaseIterable {
    case chainlink
    case pyth
    case chronicle
    case api3
    case band
    case dia
    case custom
}

// MARK: - Oracle Configuration

struct OracleConfiguration {
    let priceThrottleInterval: TimeInterval
    let attestationThrottleInterval: TimeInterval
    let crossChainPollInterval: TimeInterval
    let staleDataThreshold: TimeInterval
    let maxBufferSize: Int

    static var `default`: OracleConfiguration {
        OracleConfiguration(
            priceThrottleInterval: 1.0,
            attestationThrottleInterval: 5.0,
            crossChainPollInterval: 15.0,
            staleDataThreshold: 300.0,
            maxBufferSize: 100
        )
    }
}

// MARK: - Oracle Publisher

/// Provides throttled Combine publishers for oracle data streams.
final class OraclePublisher: ObservableObject {

    // MARK: - Publishers

    /// Emits price feed updates, throttled to prevent UI overload.
    let priceFeeds: AnyPublisher<PriceFeedData, Never>

    /// Emits attestation updates.
    let attestationUpdates: AnyPublisher<PublisherAttestationData, Never>

    /// Emits cross-chain message data.
    let crossChainData: AnyPublisher<CrossChainData, Never>

    /// Latest known prices keyed by trading pair.
    @Published private(set) var latestPrices: [String: PriceFeedData] = [:]

    /// Whether the oracle connection is active.
    @Published private(set) var isActive: Bool = false

    // MARK: - Internal Subjects

    private let priceFeedSubject = PassthroughSubject<PriceFeedData, Never>()
    private let attestationSubject = PassthroughSubject<PublisherAttestationData, Never>()
    private let crossChainSubject = PassthroughSubject<CrossChainData, Never>()

    // MARK: - Configuration

    private let configuration: OracleConfiguration
    private let rpcEndpoints: [Int: URL]

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var subscribedPairs: Set<String> = []
    private var pollingTimers: [AnyCancellable] = []

    // MARK: - Initialization

    init(
        rpcEndpoints: [Int: URL] = [:],
        configuration: OracleConfiguration = .default
    ) {
        self.rpcEndpoints = rpcEndpoints
        self.configuration = configuration

        // Throttled price feeds
        self.priceFeeds = priceFeedSubject
            .throttle(
                for: .seconds(configuration.priceThrottleInterval),
                scheduler: DispatchQueue.main,
                latest: true
            )
            .eraseToAnyPublisher()

        // Throttled attestation updates
        self.attestationUpdates = attestationSubject
            .throttle(
                for: .seconds(configuration.attestationThrottleInterval),
                scheduler: DispatchQueue.main,
                latest: true
            )
            .eraseToAnyPublisher()

        // Cross-chain data (unthrottled, already polling-based)
        self.crossChainData = crossChainSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()

        setupPriceCaching()
    }

    deinit {
        stopAll()
    }

    // MARK: - Subscription Management

    /// Subscribes to price updates for a trading pair.
    func subscribeToPriceFeed(pair: String, source: OracleSource = .chainlink) {
        guard !subscribedPairs.contains(pair) else { return }
        subscribedPairs.insert(pair)

        // Set up polling for this pair
        let timer = Timer.publish(every: configuration.priceThrottleInterval * 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchPrice(pair: pair, source: source)
            }
        pollingTimers.append(timer)
    }

    /// Unsubscribes from a trading pair.
    func unsubscribeFromPriceFeed(pair: String) {
        subscribedPairs.remove(pair)
    }

    /// Starts monitoring attestation updates for a subject.
    func monitorAttestations(subject: String, schema: String? = nil) {
        let timer = Timer.publish(every: configuration.attestationThrottleInterval * 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchAttestations(subject: subject, schema: schema)
            }
        pollingTimers.append(timer)
    }

    /// Starts monitoring cross-chain messages.
    func monitorCrossChain(sourceChainId: Int, destinationChainId: Int) {
        let timer = Timer.publish(every: configuration.crossChainPollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchCrossChainMessages(
                    sourceChainId: sourceChainId,
                    destinationChainId: destinationChainId
                )
            }
        pollingTimers.append(timer)
    }

    // MARK: - Lifecycle

    /// Activates all oracle subscriptions.
    func start() {
        isActive = true
    }

    /// Deactivates all oracle subscriptions and clears timers.
    func stopAll() {
        isActive = false
        pollingTimers.forEach { $0.cancel() }
        pollingTimers.removeAll()
        subscribedPairs.removeAll()
    }

    // MARK: - Staleness Check

    /// Returns whether the price data for a pair is stale.
    func isPriceStale(pair: String) -> Bool {
        guard let data = latestPrices[pair] else { return true }
        return Date().timeIntervalSince(data.updatedAt) > configuration.staleDataThreshold
    }

    // MARK: - Private: Data Fetching

    private func fetchPrice(pair: String, source: OracleSource) {
        guard isActive else { return }
        // Placeholder: In production, this calls the oracle contract's latestRoundData()
        // and emits through the subject. The actual RPC call would go here.
    }

    private func fetchAttestations(subject: String, schema: String?) {
        guard isActive else { return }
        // Placeholder: Queries EAS or other attestation service.
    }

    private func fetchCrossChainMessages(sourceChainId: Int, destinationChainId: Int) {
        guard isActive else { return }
        // Placeholder: Queries cross-chain messaging protocols (LayerZero, CCIP, etc.)
    }

    // MARK: - Private: Caching

    private func setupPriceCaching() {
        priceFeedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.latestPrices[data.pair] = data
            }
            .store(in: &cancellables)
    }

    // MARK: - Testing Helpers

    /// Injects a price feed update for testing purposes.
    func injectPriceUpdate(_ data: PriceFeedData) {
        priceFeedSubject.send(data)
    }

    /// Injects an attestation update for testing purposes.
    func injectAttestationUpdate(_ data: PublisherAttestationData) {
        attestationSubject.send(data)
    }
}
