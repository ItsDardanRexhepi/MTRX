//
//  CollateralPublisher.swift
//  MTRX
//
//  Collateral ratio monitoring stream for DeFi positions.
//  Emits warnings at thresholds and triggers Morpheus alerts for critical levels.
//

import Foundation
import Combine

// MARK: - Collateral Position

struct CollateralPosition: Equatable, Identifiable {
    let id: String
    let protocolName: String
    let chainId: Int
    let collateralAssets: [CollateralAsset]
    let borrowedAssets: [BorrowedAsset]
    let collateralValueUSD: Decimal
    let borrowedValueUSD: Decimal
    let healthFactor: Double
    let liquidationThreshold: Double
    let currentLTV: Double
    let maxLTV: Double
    let lastUpdated: Date

    /// Distance to liquidation as a percentage.
    var liquidationDistance: Double {
        guard liquidationThreshold > 0 else { return 0 }
        return ((liquidationThreshold - currentLTV) / liquidationThreshold) * 100
    }

    /// Whether this position is at risk of liquidation.
    var isAtRisk: Bool {
        healthFactor < 1.3
    }
}

struct CollateralAsset: Equatable {
    let symbol: String
    let amount: Decimal
    let valueUSD: Decimal
    let liquidationPenalty: Double
    let isVolatile: Bool
}

struct BorrowedAsset: Equatable {
    let symbol: String
    let amount: Decimal
    let valueUSD: Decimal
    let borrowRate: Double
    let isStable: Bool
}

// MARK: - Collateral Alert

struct CollateralAlert: Identifiable, Equatable {
    let id: UUID
    let positionId: String
    let level: AlertLevel
    let healthFactor: Double
    let message: String
    let suggestedAction: SuggestedAction
    let timestamp: Date

    enum AlertLevel: String, Comparable {
        case healthy
        case caution
        case warning
        case danger
        case critical

        static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
            let order: [AlertLevel] = [.healthy, .caution, .warning, .danger, .critical]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }

        var emoji: String {
            switch self {
            case .healthy:  return "green"
            case .caution:  return "yellow"
            case .warning:  return "orange"
            case .danger:   return "red"
            case .critical: return "darkred"
            }
        }
    }

    enum SuggestedAction: String {
        case none
        case addCollateral
        case repayDebt
        case closePosition
        case emergencyExit
    }
}

// MARK: - Collateral Thresholds

struct CollateralThresholds {
    let caution: Double
    let warning: Double
    let danger: Double
    let critical: Double
    let morpheusTrigger: Double

    static var defaults: CollateralThresholds {
        CollateralThresholds(
            caution: 2.0,
            warning: 1.5,
            danger: 1.2,
            critical: 1.1,
            morpheusTrigger: 1.15
        )
    }

    /// Returns the alert level for a given health factor.
    func alertLevel(for healthFactor: Double) -> CollateralAlert.AlertLevel {
        switch healthFactor {
        case ..<critical:  return .critical
        case ..<danger:    return .danger
        case ..<warning:   return .warning
        case ..<caution:   return .caution
        default:           return .healthy
        }
    }
}

// MARK: - Morpheus Trigger

/// Represents a trigger event for the Morpheus emergency system.
struct CollateralMorpheusTrigger: Equatable {
    let positionId: String
    let protocolName: String
    let healthFactor: Double
    let estimatedTimeToLiquidation: TimeInterval?
    let recommendedAction: CollateralAlert.SuggestedAction
    let timestamp: Date
}

// MARK: - Collateral Publisher

/// Monitors DeFi collateral positions and emits real-time health updates.
final class CollateralPublisher: ObservableObject {

    // MARK: - Publishers

    /// All monitored collateral positions, updated in real time.
    let positions = CurrentValueSubject<[CollateralPosition], Never>([])

    /// Alerts emitted when health factors cross thresholds.
    let alerts = PassthroughSubject<CollateralAlert, Never>()

    /// Morpheus emergency triggers for critically unhealthy positions.
    let morpheusTriggers = PassthroughSubject<CollateralMorpheusTrigger, Never>()

    /// Aggregate health score across all positions (0.0 = critical, 1.0 = healthy).
    let aggregateHealth = CurrentValueSubject<Double, Never>(1.0)

    // MARK: - Published State

    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var criticalPositionCount: Int = 0
    @Published private(set) var lastCheckTimestamp: Date?

    // MARK: - Configuration

    private let thresholds: CollateralThresholds
    private let pollInterval: TimeInterval
    private let fastPollInterval: TimeInterval

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var monitorTimer: AnyCancellable?
    private var previousAlertLevels: [String: CollateralAlert.AlertLevel] = [:]
    private var monitoredProtocols: Set<String> = []

    // MARK: - Dependencies

    private let oraclePublisher: OraclePublisher?
    private let blockchainPublisher: BlockchainPublisher?

    // MARK: - Initialization

    init(
        oraclePublisher: OraclePublisher? = nil,
        blockchainPublisher: BlockchainPublisher? = nil,
        thresholds: CollateralThresholds = .defaults,
        pollInterval: TimeInterval = 15.0,
        fastPollInterval: TimeInterval = 5.0
    ) {
        self.oraclePublisher = oraclePublisher
        self.blockchainPublisher = blockchainPublisher
        self.thresholds = thresholds
        self.pollInterval = pollInterval
        self.fastPollInterval = fastPollInterval

        setupBindings()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Lifecycle

    /// Starts monitoring all registered collateral positions.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        checkPositions()
        monitorTimer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkPositions()
            }
    }

    /// Stops all monitoring.
    func stopMonitoring() {
        isMonitoring = false
        monitorTimer?.cancel()
        monitorTimer = nil
    }

    /// Registers a protocol for monitoring.
    func addProtocol(_ protocolName: String) {
        monitoredProtocols.insert(protocolName)
        if isMonitoring {
            checkPositions()
        }
    }

    /// Removes a protocol from monitoring.
    func removeProtocol(_ protocolName: String) {
        monitoredProtocols.remove(protocolName)
    }

    // MARK: - Position Checking

    /// Forces an immediate check of all positions.
    func checkPositions() {
        Task { @MainActor in
            let updatedPositions = await fetchAllPositions()
            positions.send(updatedPositions)
            lastCheckTimestamp = Date()

            evaluateHealthFactors(updatedPositions)
            updateAggregateHealth(updatedPositions)

            let criticalCount = updatedPositions.filter { $0.healthFactor < thresholds.critical }.count
            criticalPositionCount = criticalCount

            // Switch to fast polling if any position is in danger
            if updatedPositions.contains(where: { $0.healthFactor < thresholds.danger }) {
                switchToFastPolling()
            } else {
                switchToNormalPolling()
            }
        }
    }

    // MARK: - Private: Data Fetching

    private func fetchAllPositions() async -> [CollateralPosition] {
        // Placeholder: Queries on-chain collateral data from lending protocols
        // (Aave, Compound, MakerDAO, etc.) for all monitored wallets.
        return []
    }

    // MARK: - Private: Health Evaluation

    private func evaluateHealthFactors(_ positions: [CollateralPosition]) {
        for position in positions {
            let currentLevel = thresholds.alertLevel(for: position.healthFactor)
            let previousLevel = previousAlertLevels[position.id] ?? .healthy

            // Only alert on transitions to worse states
            if currentLevel > previousLevel {
                let alert = buildAlert(for: position, level: currentLevel)
                alerts.send(alert)

                // Trigger Morpheus for critical positions
                if position.healthFactor <= thresholds.morpheusTrigger {
                    let trigger = CollateralMorpheusTrigger(
                        positionId: position.id,
                        protocolName: position.protocolName,
                        healthFactor: position.healthFactor,
                        estimatedTimeToLiquidation: estimateTimeToLiquidation(position),
                        recommendedAction: recommendAction(for: position),
                        timestamp: Date()
                    )
                    morpheusTriggers.send(trigger)
                }
            }

            previousAlertLevels[position.id] = currentLevel
        }
    }

    private func buildAlert(for position: CollateralPosition, level: CollateralAlert.AlertLevel) -> CollateralAlert {
        CollateralAlert(
            id: UUID(),
            positionId: position.id,
            level: level,
            healthFactor: position.healthFactor,
            message: "\(position.protocolName) health factor: \(String(format: "%.2f", position.healthFactor))",
            suggestedAction: recommendAction(for: position),
            timestamp: Date()
        )
    }

    private func recommendAction(for position: CollateralPosition) -> CollateralAlert.SuggestedAction {
        switch position.healthFactor {
        case ..<thresholds.critical:  return .emergencyExit
        case ..<thresholds.danger:    return .closePosition
        case ..<thresholds.warning:   return .repayDebt
        case ..<thresholds.caution:   return .addCollateral
        default:                       return .none
        }
    }

    private func estimateTimeToLiquidation(_ position: CollateralPosition) -> TimeInterval? {
        // Placeholder: Estimates time to liquidation based on price velocity
        // and borrowing rate accrual.
        return nil
    }

    // MARK: - Private: Aggregate Health

    private func updateAggregateHealth(_ positions: [CollateralPosition]) {
        guard !positions.isEmpty else {
            aggregateHealth.send(1.0)
            return
        }

        let minHealth = positions.map(\.healthFactor).min() ?? 1.0
        let normalized = min(1.0, max(0.0, (minHealth - 1.0) / (thresholds.caution - 1.0)))
        aggregateHealth.send(normalized)
    }

    // MARK: - Private: Polling Rate

    private func switchToFastPolling() {
        guard monitorTimer != nil else { return }
        monitorTimer?.cancel()
        monitorTimer = Timer.publish(every: fastPollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkPositions()
            }
    }

    private func switchToNormalPolling() {
        guard monitorTimer != nil else { return }
        monitorTimer?.cancel()
        monitorTimer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkPositions()
            }
    }

    // MARK: - Private: Bindings

    private func setupBindings() {
        // React to price feed changes that could affect collateral ratios
        oraclePublisher?.priceFeeds
            .filter { [weak self] _ in self?.isMonitoring == true }
            .throttle(for: .seconds(5), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.checkPositions()
            }
            .store(in: &cancellables)

        // React to new blocks for position state changes
        blockchainPublisher?.newBlocks
            .filter { [weak self] _ in self?.isMonitoring == true }
            .sink { [weak self] _ in
                self?.checkPositions()
            }
            .store(in: &cancellables)
    }
}
