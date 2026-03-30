//
//  PortfolioPublisher.swift
//  MTRX
//
//  Aggregated portfolio value stream with real-time position updates and P&L calculations.
//

import Foundation
import Combine

// MARK: - Token Position

struct TokenPosition: Equatable, Identifiable {
    let id: String
    let symbol: String
    let name: String
    let chainId: Int
    let contractAddress: String
    let balance: Decimal
    let decimals: Int
    let priceUSD: Decimal
    let valueUSD: Decimal
    let allocationPercentage: Double
    let change24h: Double
    let lastUpdated: Date
}

// MARK: - DeFi Position

struct DeFiPosition: Equatable, Identifiable {
    let id: String
    let protocol_: String
    let type: DeFiPositionType
    let chainId: Int
    let suppliedValue: Decimal
    let borrowedValue: Decimal
    let netValue: Decimal
    let apy: Double
    let healthFactor: Double?
    let tokens: [String]
    let lastUpdated: Date

    enum DeFiPositionType: String, Codable, CaseIterable {
        case lending
        case borrowing
        case liquidityProvision
        case staking
        case yield
        case perpetual
        case options
    }
}

// MARK: - NFT Position

struct NFTPosition: Equatable, Identifiable {
    let id: String
    let collectionName: String
    let tokenId: String
    let chainId: Int
    let estimatedValueUSD: Decimal
    let lastSalePrice: Decimal?
    let imageURL: URL?
    let lastUpdated: Date
}

// MARK: - Portfolio Snapshot

struct PortfolioSnapshot: Equatable {
    let totalValueUSD: Decimal
    let tokenPositions: [TokenPosition]
    let defiPositions: [DeFiPosition]
    let nftPositions: [NFTPosition]
    let timestamp: Date

    var tokenValue: Decimal {
        tokenPositions.reduce(.zero) { $0 + $1.valueUSD }
    }

    var defiNetValue: Decimal {
        defiPositions.reduce(.zero) { $0 + $1.netValue }
    }

    var nftEstimatedValue: Decimal {
        nftPositions.reduce(.zero) { $0 + $1.estimatedValueUSD }
    }
}

// MARK: - P&L Data

struct ProfitAndLoss: Equatable {
    let period: PnLPeriod
    let absoluteChange: Decimal
    let percentageChange: Double
    let startValue: Decimal
    let currentValue: Decimal
    let highWaterMark: Decimal
    let lowPoint: Decimal
    let timestamp: Date

    enum PnLPeriod: String, CaseIterable {
        case hour1    = "1H"
        case hour24   = "24H"
        case day7     = "7D"
        case day30    = "30D"
        case ytd      = "YTD"
        case allTime  = "ALL"
    }

    var isProfit: Bool { absoluteChange > 0 }
    var drawdownFromHigh: Double {
        guard highWaterMark > 0 else { return 0 }
        return Double(truncating: ((highWaterMark - currentValue) / highWaterMark) as NSDecimalNumber)
    }
}

// MARK: - Portfolio Alert

struct PortfolioAlert: Identifiable, Equatable {
    let id: UUID
    let type: AlertType
    let message: String
    let severity: AlertSeverity
    let timestamp: Date
    let relatedPositionId: String?

    enum AlertType: String {
        case largeMovement
        case lowBalance
        case healthFactorWarning
        case liquidationRisk
        case impermanentLoss
        case yieldDropped
    }

    enum AlertSeverity: String, Comparable {
        case info
        case warning
        case critical

        static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
            let order: [AlertSeverity] = [.info, .warning, .critical]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }
}

// MARK: - Portfolio Publisher

/// Aggregates portfolio data from multiple sources and emits real-time updates.
final class PortfolioPublisher: ObservableObject {

    // MARK: - Publishers

    /// Current portfolio snapshot with all positions.
    let portfolio = CurrentValueSubject<PortfolioSnapshot?, Never>(nil)

    /// Real-time P&L for all tracked periods.
    let profitAndLoss = CurrentValueSubject<[ProfitAndLoss], Never>([])

    /// Portfolio alerts for significant events.
    let alerts = PassthroughSubject<PortfolioAlert, Never>()

    /// Individual position updates.
    let positionUpdates = PassthroughSubject<TokenPosition, Never>()

    // MARK: - Published State

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var totalValueUSD: Decimal = .zero

    // MARK: - Configuration

    private let walletAddresses: [String]
    private let refreshInterval: TimeInterval
    private let alertThresholds: AlertThresholds

    struct AlertThresholds {
        let largeMovementPercent: Double
        let lowBalanceUSD: Decimal
        let healthFactorWarning: Double
        let healthFactorCritical: Double

        static var defaults: AlertThresholds {
            AlertThresholds(
                largeMovementPercent: 5.0,
                lowBalanceUSD: 100,
                healthFactorWarning: 1.5,
                healthFactorCritical: 1.1
            )
        }
    }

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: AnyCancellable?
    private var previousSnapshot: PortfolioSnapshot?

    // MARK: - Dependencies

    private let oraclePublisher: OraclePublisher?
    private let blockchainPublisher: BlockchainPublisher?

    // MARK: - Initialization

    init(
        walletAddresses: [String],
        oraclePublisher: OraclePublisher? = nil,
        blockchainPublisher: BlockchainPublisher? = nil,
        refreshInterval: TimeInterval = 30.0,
        alertThresholds: AlertThresholds = .defaults
    ) {
        self.walletAddresses = walletAddresses
        self.oraclePublisher = oraclePublisher
        self.blockchainPublisher = blockchainPublisher
        self.refreshInterval = refreshInterval
        self.alertThresholds = alertThresholds

        setupBindings()
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Starts periodic portfolio refreshes and event-driven updates.
    func start() {
        isLoading = true
        refresh()

        refreshTimer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    /// Stops all refresh timers and clears subscriptions.
    func stop() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    /// Forces an immediate portfolio refresh.
    func refresh() {
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            let snapshot = await buildSnapshot()
            let previousValue = previousSnapshot?.totalValueUSD ?? snapshot.totalValueUSD

            portfolio.send(snapshot)
            totalValueUSD = snapshot.totalValueUSD
            lastRefresh = Date()

            checkAlerts(current: snapshot, previousValue: previousValue)
            updatePnL(snapshot: snapshot)

            previousSnapshot = snapshot
        }
    }

    // MARK: - Private: Snapshot Building

    private func buildSnapshot() async -> PortfolioSnapshot {
        async let tokens = fetchTokenPositions()
        async let defi = fetchDeFiPositions()
        async let nfts = fetchNFTPositions()

        let tokenResults = await tokens
        let defiResults = await defi
        let nftResults = await nfts

        let totalValue = tokenResults.reduce(.zero) { $0 + $1.valueUSD }
            + defiResults.reduce(.zero) { $0 + $1.netValue }
            + nftResults.reduce(.zero) { $0 + $1.estimatedValueUSD }

        return PortfolioSnapshot(
            totalValueUSD: totalValue,
            tokenPositions: tokenResults,
            defiPositions: defiResults,
            nftPositions: nftResults,
            timestamp: Date()
        )
    }

    private func fetchTokenPositions() async -> [TokenPosition] {
        // Placeholder: Fetches ERC-20 balances across all tracked wallets and chains.
        // In production, this queries Alchemy/Infura multichain balance APIs.
        return []
    }

    private func fetchDeFiPositions() async -> [DeFiPosition] {
        // Placeholder: Fetches positions from lending, staking, and LP protocols.
        return []
    }

    private func fetchNFTPositions() async -> [NFTPosition] {
        // Placeholder: Fetches owned NFTs with floor price estimates.
        return []
    }

    // MARK: - Private: Bindings

    private func setupBindings() {
        // React to new block events by refreshing positions
        blockchainPublisher?.newBlocks
            .throttle(for: .seconds(15), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        // React to price updates for tracked tokens
        oraclePublisher?.priceFeeds
            .sink { [weak self] priceData in
                self?.handlePriceUpdate(priceData)
            }
            .store(in: &cancellables)
    }

    private func handlePriceUpdate(_ priceData: PriceFeedData) {
        // Update cached position values with new price
        guard var snapshot = portfolio.value else { return }
        // In production, recalculates affected position values
        _ = snapshot
    }

    // MARK: - Private: Alerts

    private func checkAlerts(current: PortfolioSnapshot, previousValue: Decimal) {
        guard previousValue > 0 else { return }

        let changePercent = Double(truncating: ((current.totalValueUSD - previousValue) / previousValue * 100) as NSDecimalNumber)

        if abs(changePercent) >= alertThresholds.largeMovementPercent {
            let alert = PortfolioAlert(
                id: UUID(),
                type: .largeMovement,
                message: "Portfolio moved \(String(format: "%.1f", changePercent))% since last check",
                severity: abs(changePercent) >= 10 ? .critical : .warning,
                timestamp: Date(),
                relatedPositionId: nil
            )
            alerts.send(alert)
        }

        for position in current.defiPositions {
            if let healthFactor = position.healthFactor {
                if healthFactor < alertThresholds.healthFactorCritical {
                    alerts.send(PortfolioAlert(
                        id: UUID(),
                        type: .liquidationRisk,
                        message: "Liquidation risk on \(position.protocol_): health factor \(String(format: "%.2f", healthFactor))",
                        severity: .critical,
                        timestamp: Date(),
                        relatedPositionId: position.id
                    ))
                } else if healthFactor < alertThresholds.healthFactorWarning {
                    alerts.send(PortfolioAlert(
                        id: UUID(),
                        type: .healthFactorWarning,
                        message: "Low health factor on \(position.protocol_): \(String(format: "%.2f", healthFactor))",
                        severity: .warning,
                        timestamp: Date(),
                        relatedPositionId: position.id
                    ))
                }
            }
        }
    }

    // MARK: - Private: P&L

    private func updatePnL(snapshot: PortfolioSnapshot) {
        // Placeholder: Computes P&L across all tracked periods using historical snapshots.
        // In production, this queries a local time-series database of portfolio values.
    }
}
