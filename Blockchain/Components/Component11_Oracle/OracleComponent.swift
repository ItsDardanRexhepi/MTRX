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
    let source: ComponentOracleSource
    let updatedAt: Date
    let roundId: UInt64
    let confidence: Double
}

enum ComponentOracleSource: String {
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
    let source: ComponentOracleSource
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
    case notConfigured
    case invalidResponse(reason: String)

    var errorDescription: String? {
        switch self {
        case .feedNotFound(let p): return "Price feed not found: \(p)"
        case .stalePrice(let d): return "Stale price. Last update: \(d)"
        case .priceDeviationTooHigh: return "Price deviation exceeds threshold."
        case .roundIncomplete: return "Oracle round is incomplete."
        case .noSourcesAvailable: return "No oracle sources available."
        case .aggregationFailed: return "Price aggregation failed."
        case .notConfigured: return "Oracle read not configured — set PendingCredentials.Network.rpcURL and the feed/pool address (PendingCredentials.Components.oracle or a registered feed)."
        case .invalidResponse(let r): return "Malformed on-chain response: \(r)"
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

    /// Get TWAP price for a pair.
    ///
    /// Queries a Uniswap V3 pool via a READ-ONLY `eth_call` to
    /// `observe(uint32[])` for two tickCumulative snapshots (`period` seconds ago
    /// and now), derives the time-weighted average tick, and converts it to a
    /// price. The pool address comes from the registered `TWAPConfig`; the RPC
    /// endpoint from `PendingCredentials.Network.rpcURL`. When either is blank the
    /// read fails with `.notConfigured` — it NEVER fabricates a price.
    func getTWAP(pair: String, period: TimeInterval, completion: @escaping (Result<Double, OracleError>) -> Void) {
        guard let config = twapConfigs[pair] else {
            completion(.failure(.feedNotFound(pair: pair)))
            return
        }
        Task {
            do {
                let price = try await self.readTWAP(config: config, period: period)
                completion(.success(price))
            } catch let error as OracleError {
                completion(.failure(error))
            } catch {
                completion(.failure(.noSourcesAvailable))
            }
        }
    }

    /// Async TWAP read against a Uniswap V3 pool. Returns the RAW Uniswap price
    /// `1.0001^avgTick`, which is token1-per-token0 expressed in each token's
    /// smallest units. Converting to a human-readable price requires the two
    /// token decimals (price * 10^(token0Decimals - token1Decimals)); `TWAPConfig`
    /// does not carry decimals, so that scaling is intentionally left to the
    /// caller (the per-pair feed metadata) rather than guessed here.
    func readTWAP(config: TWAPConfig, period: TimeInterval) async throws -> Double {
        guard PendingCredentials.filled(PendingCredentials.Network.rpcURL) != nil else {
            throw OracleError.notConfigured
        }
        guard PendingCredentials.filled(config.poolAddress) != nil else {
            throw OracleError.notConfigured
        }
        // observe(uint32[] secondsAgos) where secondsAgos = [period, 0].
        let secondsAgo = UInt64(max(1, period.rounded()))
        let calldata = Self.encodeObserve(secondsAgos: [secondsAgo, 0])
        let returnHex = try await ethCallRead(to: config.poolAddress, data: calldata)

        // Decode: observe returns (int56[] tickCumulatives, uint160[] secondsPerLiquidityCumulativeX128[]).
        // ABI layout: head = [offset(tickCumulatives), offset(secondsPerLiq)];
        // each dynamic array = [length, elem0, elem1, ...]. We only need the two
        // tickCumulative elements.
        let words = Self.splitWords(returnHex)
        // Need at least: 2 head offsets + (len + 2 elems) for the first array.
        guard words.count >= 5 else {
            throw OracleError.invalidResponse(reason: "observe() returned too few words")
        }
        // First dynamic array starts at word index given by head[0]/32. For the
        // canonical encoding head[0] = 0x40 → word index 2, then [len, e0, e1].
        let tickCumStart = Int(Self.wordToUInt(words[0]) / 32)
        guard tickCumStart + 2 < words.count else {
            throw OracleError.invalidResponse(reason: "tickCumulatives out of range")
        }
        let len = Self.wordToUInt(words[tickCumStart])
        guard len >= 2 else {
            throw OracleError.invalidResponse(reason: "expected 2 tickCumulatives, got \(len)")
        }
        let tickCum0 = Self.wordToInt256(words[tickCumStart + 1]) // older (period ago)
        let tickCum1 = Self.wordToInt256(words[tickCumStart + 2]) // newer (now)

        // Average tick over the window = (cum_now - cum_then) / period.
        let delta = tickCum1 - tickCum0
        let avgTick = Double(delta) / Double(secondsAgo)
        // Uniswap V3: price(token1/token0) in raw units = 1.0001^tick.
        let rawPrice = pow(1.0001, avgTick)
        guard rawPrice.isFinite, rawPrice > 0 else {
            throw OracleError.invalidResponse(reason: "non-finite TWAP price")
        }
        return rawPrice
    }

    /// Configure a TWAP feed
    func configureTWAP(_ config: TWAPConfig) {
        twapConfigs[config.pair] = config
    }

    // MARK: - Aggregation

    /// Get aggregated price from multiple sources (MEDIAN).
    ///
    /// Fetches from every source registered for `pair` — the Chainlink
    /// `latestRoundData` feed and, when configured, the Uniswap V3 TWAP — and
    /// returns the MEDIAN of the values that resolved. Sources that can't run
    /// (blank RPC/feed/pool) are skipped, not faked. If NO source resolves the
    /// call fails with `.notConfigured`/`.noSourcesAvailable` — never a
    /// fabricated price.
    func getAggregatedPrice(pair: String, completion: @escaping (Result<PriceFeed, OracleError>) -> Void) {
        Task {
            do {
                let feed = try await self.aggregatedPrice(pair: pair)
                completion(.success(feed))
            } catch let error as OracleError {
                completion(.failure(error))
            } catch {
                completion(.failure(.aggregationFailed))
            }
        }
    }

    /// Async median aggregation across all sources registered for `pair`.
    func aggregatedPrice(pair: String) async throws -> PriceFeed {
        guard PendingCredentials.filled(PendingCredentials.Network.rpcURL) != nil else {
            throw OracleError.notConfigured
        }

        var prices: [Double] = []
        var sourcesUsed = 0
        var newestRound: UInt64 = 0
        var decimals = 8

        // Source 1: Chainlink latestRoundData (if a feed is registered for the pair).
        if feedConfigs[pair] != nil {
            if let chainlink = try? await latestRoundData(pair: pair) {
                prices.append(chainlink.price)
                decimals = chainlink.decimals
                newestRound = max(newestRound, chainlink.roundId)
                sourcesUsed += 1
            }
        }

        // Source 2: Uniswap V3 TWAP (if a TWAP pool is configured for the pair).
        if let twapConfig = twapConfigs[pair] {
            if let twap = try? await readTWAP(config: twapConfig, period: twapConfig.period) {
                prices.append(twap)
                sourcesUsed += 1
            }
        }

        guard sourcesUsed > 0, !prices.isEmpty else {
            // No source could run — every one was blank/unconfigured.
            throw OracleError.noSourcesAvailable
        }

        let median = Self.median(prices)
        // Confidence: 1.0 with a single source, higher agreement → higher value.
        let confidence = Self.agreementConfidence(prices, median: median)

        let feed = PriceFeed(
            feedId: pair, pair: pair, price: median, decimals: decimals,
            source: .aggregated, updatedAt: Date(), roundId: newestRound,
            confidence: confidence
        )
        latestPrices[pair] = feed
        delegate?.oracle(self, didUpdatePrice: feed)
        return feed
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
        guard feedConfigs[pair] != nil else {
            completion(.failure(.feedNotFound(pair: pair)))
            return
        }
        Task {
            do {
                let feed = try await self.latestRoundData(pair: pair)
                self.latestPrices[pair] = feed
                self.delegate?.oracle(self, didUpdatePrice: feed)
                completion(.success(feed))
            } catch let error as OracleError {
                completion(.failure(error))
            } catch {
                completion(.failure(.noSourcesAvailable))
            }
        }
    }

    // MARK: - On-chain reads (read-only eth_call via the RPC path)
    //
    // All reads here are READ-ONLY (`eth_call`) — no signing, no state change.
    // They route through the component's `BaseNetwork`, which itself returns a
    // clear "RPC URL not set" failure when `PendingCredentials.Network.rpcURL`
    // is blank. We surface that as `.notConfigured` and NEVER fabricate a price,
    // round, or timestamp.

    /// Read Chainlink `latestRoundData()` from the aggregator registered for
    /// `pair` and return a populated `PriceFeed`. The aggregator address is the
    /// registered feed's `contractAddress`; the RPC endpoint comes from
    /// PendingCredentials. Blank RPC → `.notConfigured`; an incomplete round
    /// (updatedAt == 0) → `.roundIncomplete`. Never returns a fabricated price.
    func latestRoundData(pair: String) async throws -> PriceFeed {
        guard let config = feedConfigs[pair] else {
            throw OracleError.feedNotFound(pair: pair)
        }
        guard PendingCredentials.filled(PendingCredentials.Network.rpcURL) != nil else {
            throw OracleError.notConfigured
        }
        guard PendingCredentials.filled(config.contractAddress) != nil else {
            throw OracleError.notConfigured
        }

        // Chainlink AggregatorV3Interface:
        //   latestRoundData() -> (uint80 roundId, int256 answer,
        //                         uint256 startedAt, uint256 updatedAt,
        //                         uint80 answeredInRound)
        let returnHex = try await ethCallRead(
            to: config.contractAddress,
            data: Self.encodeLatestRoundData()
        )
        let words = Self.splitWords(returnHex)
        guard words.count >= 5 else {
            throw OracleError.invalidResponse(reason: "latestRoundData returned too few words")
        }
        let roundId = Self.wordToUInt(words[0])
        let answer = Self.wordToInt256(words[1])           // signed price, `decimals` precision
        let updatedAt = Self.wordToUInt(words[3])
        let answeredInRound = Self.wordToUInt(words[4])

        // Round-completeness checks (Chainlink best practice): a 0 timestamp
        // means the round hasn't been answered; a stale answeredInRound means a
        // carried-over answer.
        guard updatedAt != 0, answeredInRound >= roundId else {
            throw OracleError.roundIncomplete
        }
        guard answer > 0 else {
            throw OracleError.invalidResponse(reason: "non-positive Chainlink answer")
        }

        // Decimals: read on-chain `decimals()` when available, else fall back to
        // the feed config / Chainlink's USD-feed default of 8.
        let decimals = (try? await readFeedDecimals(address: config.contractAddress)) ?? 8
        let price = Double(answer) / pow(10.0, Double(decimals))
        let updatedDate = Date(timeIntervalSince1970: TimeInterval(updatedAt))

        return PriceFeed(
            feedId: config.feedId, pair: pair, price: price, decimals: decimals,
            source: .chainlink, updatedAt: updatedDate, roundId: roundId,
            confidence: 1.0
        )
    }

    /// Read the aggregator's `decimals()` (uint8). Read-only; nil on any failure
    /// so the caller can fall back to the USD-feed default (8).
    private func readFeedDecimals(address: String) async throws -> Int {
        let hex = try await ethCallRead(to: address, data: Self.encodeDecimals())
        let words = Self.splitWords(hex)
        guard let first = words.first else {
            throw OracleError.invalidResponse(reason: "decimals() returned no data")
        }
        return Int(Self.wordToUInt(first))
    }

    /// Wrap `BaseNetwork.ethCall` (completion-based, read-only) in async/await.
    /// Propagates the network layer's "RPC URL not set" as `.notConfigured`.
    private func ethCallRead(to: String, data: Data) async throws -> String {
        let dataHex = "0x" + data.map { String(format: "%02x", $0) }.joined()
        return try await withCheckedThrowingContinuation { continuation in
            network.ethCall(to: to, data: dataHex) { result in
                switch result {
                case .success(let hex):
                    continuation.resume(returning: hex)
                case .failure(let err):
                    // A blank RPC surfaces from BaseNetwork as connectionFailed.
                    if case .connectionFailed = err {
                        continuation.resume(throwing: OracleError.notConfigured)
                    } else {
                        continuation.resume(throwing: OracleError.invalidResponse(reason: err.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - ABI encoding (read selectors)

    /// `latestRoundData()` — no args, 4-byte selector only.
    static func encodeLatestRoundData() -> Data {
        return ABIEncoder.functionSelector("latestRoundData()")
    }

    /// `decimals()` — no args.
    static func encodeDecimals() -> Data {
        return ABIEncoder.functionSelector("decimals()")
    }

    /// Uniswap V3 `observe(uint32[] secondsAgos)`. The single dynamic array arg
    /// sits behind one head word (offset 0x20), then `[length, elem0, elem1...]`.
    static func encodeObserve(secondsAgos: [UInt64]) -> Data {
        var out = ABIEncoder.functionSelector("observe(uint32[])")
        out.append(ABIEncoder.encodeOffset(32))                 // offset to the array
        out.append(ABIEncoder.encodeUInt256(UInt64(secondsAgos.count))) // length
        for s in secondsAgos {
            out.append(ABIEncoder.encodeUInt256(s))             // uint32 right-padded into a word
        }
        return out
    }

    // MARK: - ABI decoding helpers (read results)

    /// Split a `0x`-prefixed hex return blob into 32-byte (64 hex-char) words.
    static func splitWords(_ hex: String) -> [String] {
        var s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        // Tolerate odd-length / partial blobs by trimming to a word boundary.
        let usable = s.count - (s.count % 64)
        if usable < s.count { s = String(s.prefix(usable)) }
        var words: [String] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            let end = s.index(idx, offsetBy: 64)
            words.append(String(s[idx..<end]))
            idx = end
        }
        return words
    }

    /// Interpret a 32-byte word as an unsigned big-endian integer. Values wider
    /// than UInt64 are taken from the low 64 bits (sufficient for roundId,
    /// timestamps, decimals, array lengths/offsets — never for a price answer,
    /// which goes through `wordToInt256`).
    static func wordToUInt(_ word: String) -> UInt64 {
        let low = String(word.suffix(16)) // low 8 bytes
        return UInt64(low, radix: 16) ?? 0
    }

    /// Interpret a 32-byte word as a TWO'S-COMPLEMENT signed integer
    /// (int256/int56/int24). Solidity sign-extends a negative int56/int24 across
    /// the full 256-bit word, so the LOW 64 bits already carry the correct
    /// two's-complement pattern — `Int64(bitPattern:)` recovers the signed value
    /// for both positive and negative inputs. This covers Chainlink answers and
    /// Uniswap tickCumulatives at realistic scales; values whose magnitude
    /// genuinely exceeds 2^63 would overflow this 64-bit view (not reachable for
    /// price feeds / 30-min tickCumulatives, but noted as the honest boundary).
    static func wordToInt256(_ word: String) -> Int64 {
        let low = String(word.suffix(16)) // low 8 bytes of the (sign-extended) word
        let magnitude = UInt64(low, radix: 16) ?? 0
        return Int64(bitPattern: magnitude)
    }

    /// Median of a non-empty list of doubles.
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        guard count > 0 else { return 0 }
        if count % 2 == 1 { return sorted[count / 2] }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
    }

    /// Map the spread of sources around the median into a 0…1 confidence: a
    /// single source is 1.0; tighter agreement → higher confidence.
    static func agreementConfidence(_ values: [Double], median: Double) -> Double {
        guard values.count > 1, median > 0 else { return 1.0 }
        let maxDeviation = values.map { abs($0 - median) / median }.max() ?? 0
        return max(0.0, min(1.0, 1.0 - maxDeviation))
    }

    private func isPriceStale(_ feed: PriceFeed) -> Bool {
        return Date().timeIntervalSince(feed.updatedAt) > stalenessThreshold
    }
}
