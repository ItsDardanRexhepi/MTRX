// OracleComponent.swift
// MTRX Blockchain - Components - Oracle
//
// Price feed oracle integration: Chainlink, custom feeds, TWAP

import Foundation

// MARK: - Protocols

protocol OracleComponentDelegate: AnyObject {
    func oracle(_ component: OracleComponent, didUpdatePrice feed: PriceFeed)
    func oracle(_ component: OracleComponent, priceDeviation feed: PriceFeed, deviationPercent: Double)
    func oracle(_ component: OracleComponent, feedStale feedId: String)
}

// MARK: - Data Models

struct PriceFeed {
    let feedId: String
    let pair: String // e.g., "ETH/USD"
    let price: Double
    let decimals: Int
    let source: OracleSource
    let updatedAt: Date
    let roundId: UInt64
    let confidence: Double
}

enum OracleSource: String {
    case chainlink, uniswapTWAP, custom, aggregated
}

struct TWAPConfig {
    let pair: String
    let poolAddress: String
    let period: TimeInterval // e.g., 1800 for 30-min TWAP
    let cardinality: Int
}

struct OracleFeedConfig {
    let feedId: String
    let pair: String
    let contractAddress: String
    let source: OracleSource
    let heartbeatSeconds: TimeInterval
    let deviationThreshold: Double
    let isActive: Bool
}

enum OracleError: Error, LocalizedError {
    case feedNotFound(pair: String)
    case stalePrice(lastUpdate: Date)
    case priceDeviationTooHigh
    case roundIncomplete
    case noSourcesAvailable
    case aggregationFailed

    var errorDescription: String? {
        switch self {
        case .feedNotFound(let p): return "Price feed not found: \(p)"
        case .stalePrice(let d): return "Stale price. Last update: \(d)"
        case .priceDeviationTooHigh: return "Price deviation exceeds threshold."
        case .roundIncomplete: return "Oracle round is incomplete."
        case .noSourcesAvailable: return "No oracle sources available."
        case .aggregationFailed: return "Price aggregation failed."
        }
    }
}

// MARK: - OracleComponent

final class OracleComponent {

    // MARK: - Properties

    weak var delegate: OracleComponentDelegate?

    private let network: BaseNetwork
    private var feedConfigs: [String: OracleFeedConfig] = [:]
    private var latestPrices: [String: PriceFeed] = [:]
    private var twapConfigs: [String: TWAPConfig] = [:]
    private let stalenessThreshold: TimeInterval = 3600 // 1 hour
    private let processingQueue = DispatchQueue(label: "com.mtrx.oracle", qos: .userInitiated)

    // MARK: - Chainlink Feed Addresses on Base

    static let chainlinkFeeds: [String: String] = [
        "ETH/USD": "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70",
        "BTC/USD": "0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E",
        "USDC/USD": "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B"
    ]

    // MARK: - Initialization

    init(network: BaseNetwork) {
        self.network = network
        registerDefaultFeeds()
    }

    // MARK: - Price Retrieval

    /// Get the latest price for a pair
    func getPrice(pair: String, completion: @escaping (Result<PriceFeed, OracleError>) -> Void) {
        if let cached = latestPrices[pair], !isPriceStale(cached) {
            completion(.success(cached))
            return
        }
        fetchPrice(pair: pair, completion: completion)
    }

    /// Get prices for multiple pairs
    func getPrices(pairs: [String], completion: @escaping (Result<[PriceFeed], OracleError>) -> Void) {
        let group = DispatchGroup()
        var results: [PriceFeed] = []
        var firstError: OracleError?

        for pair in pairs {
            group.enter()
            getPrice(pair: pair) { result in
                switch result {
                case .success(let feed): results.append(feed)
                case .failure(let error): if firstError == nil { firstError = error }
                }
                group.leave()
            }
        }

        group.notify(queue: processingQueue) {
            if let error = firstError, results.isEmpty {
                completion(.failure(error))
            } else {
                completion(.success(results))
            }
        }
    }

    // MARK: - TWAP

    /// Get TWAP price for a pair
    func getTWAP(pair: String, period: TimeInterval, completion: @escaping (Result<Double, OracleError>) -> Void) {
        guard let config = twapConfigs[pair] else {
            completion(.failure(.feedNotFound(pair: pair)))
            return
        }
        // TODO: Query Uniswap V3 pool for TWAP observation
        _ = config
        completion(.failure(.noSourcesAvailable))
    }

    /// Configure a TWAP feed
    func configureTWAP(_ config: TWAPConfig) {
        twapConfigs[config.pair] = config
    }

    // MARK: - Aggregation

    /// Get aggregated price from multiple sources
    func getAggregatedPrice(pair: String, completion: @escaping (Result<PriceFeed, OracleError>) -> Void) {
        // TODO: Fetch from all configured sources, compute median
        getPrice(pair: pair, completion: completion)
    }

    // MARK: - Feed Management

    func registerFeed(_ config: OracleFeedConfig) { feedConfigs[config.pair] = config }
    func removeFeed(pair: String) { feedConfigs.removeValue(forKey: pair) }
    func getRegisteredFeeds() -> [OracleFeedConfig] { return Array(feedConfigs.values) }

    // MARK: - Monitoring

    /// Check all feeds for staleness
    func checkFeedHealth() -> [String] {
        var staleFeeds: [String] = []
        for (pair, price) in latestPrices {
            if isPriceStale(price) {
                staleFeeds.append(pair)
                delegate?.oracle(self, feedStale: pair)
            }
        }
        return staleFeeds
    }

    // MARK: - Private

    private func registerDefaultFeeds() {
        for (pair, address) in OracleComponent.chainlinkFeeds {
            let config = OracleFeedConfig(
                feedId: pair, pair: pair, contractAddress: address,
                source: .chainlink, heartbeatSeconds: 3600,
                deviationThreshold: 0.5, isActive: true
            )
            feedConfigs[pair] = config
        }
    }

    private func fetchPrice(pair: String, completion: @escaping (Result<PriceFeed, OracleError>) -> Void) {
        guard let config = feedConfigs[pair] else {
            completion(.failure(.feedNotFound(pair: pair)))
            return
        }
        // TODO: Call latestRoundData() on Chainlink feed contract
        _ = config
        completion(.failure(.noSourcesAvailable))
    }

    private func isPriceStale(_ feed: PriceFeed) -> Bool {
        return Date().timeIntervalSince(feed.updatedAt) > stalenessThreshold
    }
}
