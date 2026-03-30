// DashboardManager.swift
// MTRX Blockchain - Components - Dashboard (C20)
//
// Unified dashboard for all 30 components, plain English descriptions,
// APY sourced from C16 canonical calculator, activity-based panel visibility.

import Foundation
import Combine

// MARK: - Protocols

protocol DashboardDelegate: AnyObject {
    func dashboard(_ manager: DashboardManager, panelsUpdated panels: [DashboardPanel])
    func dashboard(_ manager: DashboardManager, alertTriggered alert: DashboardAlert)
}

// MARK: - Data Models

/// Identifies which component a panel belongs to (C1 through C30).
enum ComponentIdentifier: Int, Codable, CaseIterable {
    case contractConversion = 1
    case defiLending = 2
    case nft = 3
    case rwa = 4
    case identity = 5
    case dao = 6
    case stablecoin = 7
    case attestation = 8
    case agentIdentity = 9
    case agenticPayments = 10
    case oracle = 11
    case supplyChain = 12
    case insurance = 13
    case gaming = 14
    case ip = 15
    case staking = 16
    case payments = 17
    case securities = 18
    case governance = 19
    case dashboard = 20
    case dex = 21
    case fundraising = 22
    case loyalty = 23
    case marketplace = 24
    case cashback = 25
    case brandRewards = 26
    case subscriptions = 27
    case social = 28
    case privacy = 29
    case disputeResolution = 30

    /// Plain English name for the panel header.
    var displayName: String {
        switch self {
        case .contractConversion: return "Smart Contracts"
        case .defiLending:        return "Lending & Borrowing"
        case .nft:                return "Digital Collectibles"
        case .rwa:                return "Real-World Assets"
        case .identity:           return "Identity"
        case .dao:                return "Community Organizations"
        case .stablecoin:         return "Stablecoins"
        case .attestation:        return "Attestations"
        case .agentIdentity:      return "AI Agent Identity"
        case .agenticPayments:    return "AI Agent Payments"
        case .oracle:             return "Price Feeds"
        case .supplyChain:        return "Supply Chain"
        case .insurance:          return "Insurance"
        case .gaming:             return "Gaming"
        case .ip:                 return "Intellectual Property"
        case .staking:            return "Staking Rewards"
        case .payments:           return "Payments"
        case .securities:         return "Securities"
        case .governance:         return "Governance & Voting"
        case .dashboard:          return "Dashboard Overview"
        case .dex:                return "Token Exchange"
        case .fundraising:        return "Fundraising"
        case .loyalty:            return "Loyalty Rewards"
        case .marketplace:        return "Marketplace"
        case .cashback:           return "Annual Cashback"
        case .brandRewards:       return "Brand Rewards"
        case .subscriptions:      return "Subscriptions"
        case .social:             return "Social Profiles"
        case .privacy:            return "Privacy Controls"
        case .disputeResolution:  return "Dispute Resolution"
        }
    }
}

/// A panel shown on the unified dashboard.
struct DashboardPanel: Identifiable, Codable {
    let id: String
    let component: ComponentIdentifier
    let title: String               // plain English
    let summary: String             // plain English description
    var isVisible: Bool             // activity-based visibility
    var lastActivityDate: Date?
    var metrics: [DashboardMetric]
}

struct DashboardMetric: Identifiable, Codable {
    let id: String
    let label: String               // plain English
    let value: String
    let trend: MetricTrend?
}

enum MetricTrend: String, Codable {
    case up, down, stable
}

struct DashboardAlert: Identifiable, Codable {
    let id: String
    let component: ComponentIdentifier
    let message: String
    let severity: AlertSeverity
    let timestamp: Date
    var isRead: Bool
}

enum AlertSeverity: String, Codable {
    case info, warning, critical
}

/// Staking APY display sourced from C16.
struct StakingAPYDisplay: Codable {
    let baseAPY: Double
    let effectiveAPY: Double
    let totalStakedETH: Double
    let lastUpdated: Date
}

enum DashboardError: Error, LocalizedError {
    case panelNotFound(ComponentIdentifier)
    case stakingDataUnavailable
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .panelNotFound(let c): return "Panel not found for component \(c.rawValue)."
        case .stakingDataUnavailable: return "Staking APY data is not yet available from C16."
        case .refreshFailed(let r): return "Dashboard refresh failed: \(r)"
        }
    }
}

// MARK: - DashboardManager

final class DashboardManager: ObservableObject {

    static let shared = DashboardManager()

    /// Panels with no activity in this many days are hidden.
    static let inactivityThresholdDays: Int = 30

    weak var delegate: DashboardDelegate?

    @Published private(set) var panels: [DashboardPanel] = []
    @Published private(set) var alerts: [DashboardAlert] = []
    @Published private(set) var stakingAPY: StakingAPYDisplay?
    @Published private(set) var isLoading = false

    private var panelStore: [ComponentIdentifier: DashboardPanel] = [:]
    private let stakingManager: StakingManager

    init(stakingManager: StakingManager = .shared) {
        self.stakingManager = stakingManager
        initializePanels()
    }

    // MARK: - Initialization

    /// Create a panel for each of the 30 components.
    private func initializePanels() {
        for component in ComponentIdentifier.allCases {
            let panel = DashboardPanel(
                id: "panel-\(component.rawValue)",
                component: component,
                title: component.displayName,
                summary: "",
                isVisible: false,
                lastActivityDate: nil,
                metrics: []
            )
            panelStore[component] = panel
        }
        panels = panelStore.values.sorted { $0.component.rawValue < $1.component.rawValue }
    }

    // MARK: - APY from C16 Canonical Calculator

    /// Fetch APY from C16 StakingManager (single source of truth).
    func refreshStakingAPY() async throws {
        guard let snapshot = stakingManager.getCanonicalAPY() else {
            throw DashboardError.stakingDataUnavailable
        }

        let display = StakingAPYDisplay(
            baseAPY: snapshot.baseAPY,
            effectiveAPY: snapshot.effectiveAPY,
            totalStakedETH: snapshot.totalStakedETH,
            lastUpdated: snapshot.calculatedAt
        )

        await MainActor.run { stakingAPY = display }
    }

    // MARK: - Activity-Based Panel Visibility

    /// Record activity for a component. Makes its panel visible.
    func recordActivity(component: ComponentIdentifier, summary: String, metrics: [DashboardMetric] = []) async {
        guard var panel = panelStore[component] else { return }
        panel.isVisible = true
        panel.lastActivityDate = Date()
        panel.summary = summary
        if !metrics.isEmpty { panel.metrics = metrics }
        panelStore[component] = panel
        await rebuildPanelList()
    }

    /// Hide panels with no activity in the threshold window.
    func pruneInactivePanels() async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.inactivityThresholdDays, to: Date())!
        for (key, var panel) in panelStore {
            if let lastActivity = panel.lastActivityDate, lastActivity < cutoff {
                panel.isVisible = false
                panelStore[key] = panel
            }
        }
        await rebuildPanelList()
    }

    /// Manually set panel visibility.
    func setPanelVisibility(component: ComponentIdentifier, visible: Bool) async {
        guard var panel = panelStore[component] else { return }
        panel.isVisible = visible
        panelStore[component] = panel
        await rebuildPanelList()
    }

    // MARK: - Panel Metrics

    func updateMetrics(component: ComponentIdentifier, metrics: [DashboardMetric]) async {
        guard var panel = panelStore[component] else { return }
        panel.metrics = metrics
        panelStore[component] = panel
        await rebuildPanelList()
    }

    // MARK: - Alerts

    func addAlert(component: ComponentIdentifier, message: String, severity: AlertSeverity) async {
        let alert = DashboardAlert(
            id: UUID().uuidString,
            component: component,
            message: message,
            severity: severity,
            timestamp: Date(),
            isRead: false
        )
        await MainActor.run { alerts.append(alert) }
        delegate?.dashboard(self, alertTriggered: alert)
    }

    func markAlertRead(alertId: String) async {
        await MainActor.run {
            if let idx = alerts.firstIndex(where: { $0.id == alertId }) {
                alerts[idx].isRead = true
            }
        }
    }

    // MARK: - Full Refresh

    /// Refresh the entire dashboard: APY, visibility pruning, delegate notification.
    func refreshAll() async {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }

        try? await refreshStakingAPY()
        await pruneInactivePanels()
        delegate?.dashboard(self, panelsUpdated: panels.filter { $0.isVisible })
    }

    // MARK: - Queries

    func visiblePanels() -> [DashboardPanel] {
        panels.filter { $0.isVisible }
    }

    func getPanel(component: ComponentIdentifier) -> DashboardPanel? {
        panelStore[component]
    }

    func unreadAlertCount() -> Int {
        alerts.filter { !$0.isRead }.count
    }

    // MARK: - Private

    @MainActor
    private func rebuildPanelList() {
        panels = panelStore.values.sorted { $0.component.rawValue < $1.component.rawValue }
    }
}
