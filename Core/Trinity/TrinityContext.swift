//
//  TrinityContext.swift
//  MTRX — Trinity
//
//  Assembles full user context before every response.
//

import Foundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - User Context

/// Complete snapshot of the user's current context, assembled before every response.
struct UserContext: Sendable {
    let timestamp: Date
    let healthData: HealthSnapshot?
    let location: LocationSnapshot?
    let timeContext: TimeContext
    let weather: WeatherSnapshot?
    let portfolioState: PortfolioSnapshot?
    let recentTransactions: [TransactionSnapshot]
    let deviceState: DeviceState
    let preferences: TrinityUserPreferences

    /// A relevance-scored summary of the most important context items, highest first.
    var highlightedContext: [ContextHighlight] {
        var highlights: [ContextHighlight] = []

        // Portfolio alerts are the most actionable signal.
        if let portfolio = portfolioState {
            for alert in portfolio.alerts {
                let score: Double
                switch alert.severity {
                case .critical: score = 1.0
                case .warning: score = 0.75
                case .info: score = 0.4
                }
                highlights.append(ContextHighlight(category: "portfolio", summary: alert.message, relevanceScore: score))
            }
            if abs(portfolio.dailyChangePercent) >= 5 {
                let sign = portfolio.dailyChangePercent >= 0 ? "+" : ""
                highlights.append(ContextHighlight(
                    category: "portfolio",
                    summary: String(format: "Portfolio %@%.1f%% today", sign, portfolio.dailyChangePercent),
                    relevanceScore: min(1.0, 0.5 + abs(portfolio.dailyChangePercent) / 20.0)
                ))
            }
        }

        // Recent failed transactions warrant attention.
        let failed = recentTransactions.filter { $0.status.lowercased() == "failed" }
        if !failed.isEmpty {
            highlights.append(ContextHighlight(category: "transactions", summary: "\(failed.count) recent transaction(s) failed", relevanceScore: 0.85))
        }

        // Market open during the session is moderately relevant.
        if timeContext.marketStatus == .open {
            highlights.append(ContextHighlight(category: "market", summary: "Market is open", relevanceScore: 0.5))
        }

        // Wellbeing: short sleep is worth surfacing gently.
        if let sleep = healthData?.sleepHours, sleep < 6 {
            highlights.append(ContextHighlight(category: "health", summary: String(format: "Only %.1fh sleep last night", sleep), relevanceScore: 0.6))
        }

        return highlights.sorted { $0.relevanceScore > $1.relevanceScore }
    }
}

// MARK: - Context Snapshots

struct HealthSnapshot: Sendable {
    let heartRate: Double?
    let steps: Int?
    let sleepHours: Double?
    let stressLevel: Double?
    let lastUpdated: Date

    // TODO: Integrate with HealthKit
}

struct LocationSnapshot: Sendable {
    let latitude: Double
    let longitude: Double
    let locality: String?
    let country: String?
    let isHome: Bool
    let isWork: Bool
    let lastUpdated: Date
}

struct TimeContext: Sendable {
    let currentTime: Date
    let timeZone: TimeZone
    let isBusinessHours: Bool
    let isWeekend: Bool
    let dayOfWeek: Int
    let marketStatus: MarketStatus

    enum MarketStatus: String, Sendable {
        case preMarket
        case open
        case afterHours
        case closed
    }
}

struct WeatherSnapshot: Sendable {
    let temperature: Double?
    let condition: String?
    let humidity: Double?
    let location: String?
    let lastUpdated: Date
}

struct PortfolioSnapshot: Sendable {
    let totalValue: Double
    let dailyChange: Double
    let dailyChangePercent: Double
    let topHoldings: [HoldingSnapshot]
    let alerts: [PortfolioAlert]
    let lastUpdated: Date
}

struct HoldingSnapshot: Sendable {
    let symbol: String
    let name: String
    let value: Double
    let changePercent: Double
    let allocation: Double
}

struct PortfolioAlert: Sendable {
    let id: UUID
    let message: String
    let severity: AlertSeverity
    let timestamp: Date

    enum AlertSeverity: String, Sendable {
        case info, warning, critical
    }
}

struct TransactionSnapshot: Sendable {
    let id: UUID
    let type: String
    let amount: Double
    let asset: String
    let timestamp: Date
    let status: String
}

struct DeviceState: Sendable {
    let batteryLevel: Double?
    let isCharging: Bool
    let networkType: String
    let screenBrightness: Double?
}

struct TrinityUserPreferences: Sendable {
    let language: String
    let currency: String
    let riskTolerance: Double
    let notificationsEnabled: Bool
    let voiceEnabled: Bool
}

struct ContextHighlight: Sendable {
    let category: String
    let summary: String
    let relevanceScore: Double
}

// MARK: - Trinity Context

/// Assembles the full user context before every Trinity response.
/// Gathers data from health, location, time, weather, portfolio, and recent transactions.
final class TrinityContext {

    // MARK: - Data Providers

    // TODO: Replace with actual data provider protocols/implementations
    private var healthProvider: HealthDataProvider?
    private var locationProvider: LocationDataProvider?
    private var weatherProvider: WeatherDataProvider?
    private var portfolioProvider: PortfolioDataProvider?
    private var transactionProvider: TransactionDataProvider?

    // MARK: - Caching

    private var cachedContext: UserContext?
    private var cacheTimestamp: Date?
    private let cacheValidityInterval: TimeInterval = 30.0 // 30 seconds

    // MARK: - Initialization

    init(
        healthProvider: HealthDataProvider? = nil,
        locationProvider: LocationDataProvider? = nil,
        weatherProvider: WeatherDataProvider? = nil,
        portfolioProvider: PortfolioDataProvider? = nil,
        transactionProvider: TransactionDataProvider? = nil
    ) {
        self.healthProvider = healthProvider
        self.locationProvider = locationProvider
        self.weatherProvider = weatherProvider
        self.portfolioProvider = portfolioProvider
        self.transactionProvider = transactionProvider
    }

    // MARK: - Context Assembly

    /// Assemble the complete user context.
    /// Fetches data from all providers concurrently and compiles into a single snapshot.
    /// - Returns: A complete `UserContext` snapshot.
    func assembleContext() async -> UserContext {
        // Return cached context if still valid
        if let cached = cachedContext,
           let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < cacheValidityInterval {
            return cached
        }

        // Fetch all data sources concurrently
        async let health = fetchHealthData()
        async let location = fetchLocationData()
        async let weather = fetchWeatherData()
        async let portfolio = fetchPortfolioState()
        async let transactions = fetchRecentTransactions()

        let timeContext = buildTimeContext()
        let deviceState = await fetchDeviceState()
        let preferences = loadTrinityUserPreferences()

        let context = UserContext(
            timestamp: Date(),
            healthData: await health,
            location: await location,
            timeContext: timeContext,
            weather: await weather,
            portfolioState: await portfolio,
            recentTransactions: await transactions,
            deviceState: deviceState,
            preferences: preferences
        )

        // Cache the assembled context
        cachedContext = context
        cacheTimestamp = Date()

        return context
    }

    /// Invalidate the cached context, forcing a fresh assembly on next call.
    func invalidateCache() {
        cachedContext = nil
        cacheTimestamp = nil
    }

    // MARK: - Data Fetching (Private)

    private func fetchHealthData() async -> HealthSnapshot? {
        // TODO: Integrate with HealthKit via healthProvider
        guard let provider = healthProvider else { return nil }
        return await provider.fetchLatest()
    }

    private func fetchLocationData() async -> LocationSnapshot? {
        // TODO: Integrate with CoreLocation via locationProvider
        guard let provider = locationProvider else { return nil }
        return await provider.fetchCurrent()
    }

    private func fetchWeatherData() async -> WeatherSnapshot? {
        // TODO: Integrate with WeatherKit via weatherProvider
        guard let provider = weatherProvider else { return nil }
        return await provider.fetchCurrent()
    }

    private func fetchPortfolioState() async -> PortfolioSnapshot? {
        // TODO: Integrate with portfolio service via portfolioProvider
        guard let provider = portfolioProvider else { return nil }
        return await provider.fetchSnapshot()
    }

    private func fetchRecentTransactions() async -> [TransactionSnapshot] {
        // TODO: Fetch recent transactions via transactionProvider
        guard let provider = transactionProvider else { return [] }
        return await provider.fetchRecent(limit: 20)
    }

    private func buildTimeContext() -> TimeContext {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        let isWeekend = weekday == 1 || weekday == 7

        let marketStatus: TimeContext.MarketStatus
        if isWeekend {
            marketStatus = .closed
        } else if hour < 9 {
            marketStatus = .preMarket
        } else if hour < 16 {
            marketStatus = .open
        } else if hour < 20 {
            marketStatus = .afterHours
        } else {
            marketStatus = .closed
        }

        return TimeContext(
            currentTime: now,
            timeZone: TimeZone.current,
            isBusinessHours: !isWeekend && hour >= 9 && hour < 17,
            isWeekend: isWeekend,
            dayOfWeek: weekday,
            marketStatus: marketStatus
        )
    }

    @MainActor
    private func fetchDeviceState() -> DeviceState {
        #if canImport(UIKit)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        // batteryLevel is -1 when monitoring is unavailable (e.g. Simulator) → nil.
        let level: Double? = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        let charging = device.batteryState == .charging || device.batteryState == .full
        let brightness: Double? = Double(UIScreen.main.brightness)
        #else
        let level: Double? = nil
        let charging = false
        let brightness: Double? = nil
        #endif
        return DeviceState(
            batteryLevel: level,
            isCharging: charging,
            networkType: TrinityNetworkMonitor.shared.networkType,
            screenBrightness: brightness
        )
    }

    private func loadTrinityUserPreferences() -> TrinityUserPreferences {
        let defaults = UserDefaults.standard
        func double(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : fallback
        }
        return TrinityUserPreferences(
            language: defaults.string(forKey: "trinity.language") ?? Locale.current.language.languageCode?.identifier ?? "en",
            currency: defaults.string(forKey: "trinity.currency") ?? Locale.current.currency?.identifier ?? "USD",
            riskTolerance: double("trinity.riskTolerance", 0.5),
            notificationsEnabled: bool("trinity.notificationsEnabled", true),
            voiceEnabled: bool("trinity.voiceEnabled", true)
        )
    }
}

// MARK: - Data Provider Protocols

protocol HealthDataProvider {
    func fetchLatest() async -> HealthSnapshot?
}

protocol LocationDataProvider {
    func fetchCurrent() async -> LocationSnapshot?
}

protocol WeatherDataProvider {
    func fetchCurrent() async -> WeatherSnapshot?
}

protocol PortfolioDataProvider {
    func fetchSnapshot() async -> PortfolioSnapshot?
}

protocol TransactionDataProvider {
    func fetchRecent(limit: Int) async -> [TransactionSnapshot]
}
