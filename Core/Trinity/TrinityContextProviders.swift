//
//  TrinityContextProviders.swift
//  MTRX — Trinity
//
//  Concrete implementations of the TrinityContext data-provider protocols.
//
//  Every provider degrades GRACEFULLY: if the framework is unavailable, the
//  permission is denied/undetermined, or a query fails, it returns nil (or an
//  empty array) so TrinityContext simply omits that slice of context. No data is
//  ever fabricated.
//
//  DEFERRED CONFIG (see PendingCredentials / final report): these require project
//  capabilities the app target must declare before the OS will grant data —
//    • HealthKit      → HealthKit capability + NSHealthShareUsageDescription
//    • CoreLocation   → NSLocationWhenInUseUsageDescription
//    • WeatherKit     → WeatherKit capability (+ App ID service enabled)
//  Without them the providers still compile and run; they just return nil.
//

import Foundation
import CoreLocation
import Network
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(WeatherKit)
import WeatherKit
#endif

// MARK: - Network reachability

/// Caches the current network interface type from a live NWPathMonitor so device
/// state can report a real value synchronously (never a hardcoded guess).
final class TrinityNetworkMonitor: @unchecked Sendable {

    static let shared = TrinityNetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mtrx.trinity.network")
    private let lock = NSLock()
    private var current: String = "unknown"

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let type: String
            if path.status != .satisfied {
                type = "offline"
            } else if path.usesInterfaceType(.wifi) {
                type = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                type = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = "ethernet"
            } else {
                type = "other"
            }
            self?.lock.lock()
            self?.current = type
            self?.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    var networkType: String {
        lock.lock(); defer { lock.unlock() }
        return current
    }
}

// MARK: - HealthKit

#if canImport(HealthKit)
/// Reads the most recent heart rate, today's step count and last sleep duration
/// from HealthKit. Returns nil when HealthKit is unavailable or unauthorized.
final class HealthKitProvider: HealthDataProvider {

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { set.insert(hr) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { set.insert(steps) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        return set
    }

    func fetchLatest() async -> HealthSnapshot? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        // Real authorization request; if the user declines, queries return no data
        // and we fall through to nil — never a fabricated reading.
        try? await store.requestAuthorization(toShare: [], read: readTypes)

        async let hr = latestHeartRate()
        async let steps = todayStepCount()
        async let sleep = lastSleepHours()

        let heartRate = await hr
        let stepCount = await steps
        let sleepHours = await sleep

        // If every metric is missing (e.g. fully unauthorized), omit health context.
        if heartRate == nil && stepCount == nil && sleepHours == nil { return nil }

        return HealthSnapshot(
            heartRate: heartRate,
            steps: stepCount,
            sleepHours: sleepHours,
            stressLevel: nil, // no first-party stress metric on iOS; left nil, never faked
            lastUpdated: Date()
        )
    }

    private func latestHeartRate() async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil); return
                }
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    private func todayStepCount() async -> Int? {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                guard let sum = stats?.sumQuantity() else { continuation.resume(returning: nil); return }
                continuation.resume(returning: Int(sum.doubleValue(for: .count())))
            }
            store.execute(query)
        }
    }

    private func lastSleepHours() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let lookback = Date().addingTimeInterval(-36 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: lookback, end: Date(), options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let categorySamples = samples as? [HKCategorySample], !categorySamples.isEmpty else {
                    continuation.resume(returning: nil); return
                }
                let asleepValues: Set<Int> = {
                    if #available(iOS 16.0, *) {
                        return [
                            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                        ]
                    } else {
                        return [HKCategoryValueSleepAnalysis.asleep.rawValue]
                    }
                }()
                let asleepSeconds = categorySamples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: asleepSeconds > 0 ? asleepSeconds / 3600.0 : nil)
            }
            store.execute(query)
        }
    }
}
#endif

// MARK: - CoreLocation

/// One-shot current-location fetch with reverse geocoding. Returns nil when
/// location access is denied/undetermined or no fix is obtained.
final class CoreLocationProvider: NSObject, LocationDataProvider, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func fetchCurrent() async -> LocationSnapshot? {
        let status = manager.authorizationStatus
        switch status {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        guard let location = await requestOneShotLocation() else { return nil }

        var locality: String?
        var country: String?
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            locality = placemark.locality
            country = placemark.country
        }

        return LocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            locality: locality,
            country: country,
            isHome: false, // home/work inference requires saved anchors — never guessed
            isWork: false,
            lastUpdated: location.timestamp
        )
    }

    private func requestOneShotLocation() async -> CLLocation? {
        await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

// MARK: - WeatherKit

#if canImport(WeatherKit)
/// Current-conditions via WeatherKit for the device's current location. Returns
/// nil when the entitlement is missing, location is unavailable, or the fetch fails.
@available(iOS 16.0, *)
final class WeatherKitProvider: WeatherDataProvider {

    private let service = WeatherService.shared
    private let locationProvider: CoreLocationProvider

    init(locationProvider: CoreLocationProvider = CoreLocationProvider()) {
        self.locationProvider = locationProvider
    }

    func fetchCurrent() async -> WeatherSnapshot? {
        guard let location = await currentCLLocation() else { return nil }
        guard let weather = try? await service.weather(for: location) else { return nil }

        let current = weather.currentWeather
        var locality: String?
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            locality = placemark.locality
        }

        return WeatherSnapshot(
            temperature: current.temperature.converted(to: .celsius).value,
            condition: current.condition.description,
            humidity: current.humidity,
            location: locality,
            lastUpdated: current.date
        )
    }

    private func currentCLLocation() async -> CLLocation? {
        guard let snapshot = await locationProvider.fetchCurrent() else { return nil }
        return CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
    }
}
#endif

// MARK: - Portfolio (real adapter onto WalletManager)

/// Maps the app's live `WalletManager` holdings into a Trinity PortfolioSnapshot.
/// Values come from the same WalletManager the UI shows (API-backed via
/// MTRXAPIClient.getPortfolio(), with the app's own demo fallback when the
/// backend is unreachable — that fallback is the app's behaviour, not ours).
///
/// The daily change is MEASURED against the last observation this provider made
/// (0 on the first call) — it deliberately does NOT surface WalletManager's
/// hardcoded `portfolioChange24h` placeholder, so nothing here is fabricated.
@MainActor
final class WalletPortfolioProvider: PortfolioDataProvider {

    private weak var wallet: WalletManager?
    private var priorValue: Double?
    private var priorAt: Date?

    init(wallet: WalletManager) {
        self.wallet = wallet
    }

    func fetchSnapshot() async -> PortfolioSnapshot? {
        guard let wallet = wallet else { return nil }
        let tokens = wallet.tokens
        guard !tokens.isEmpty else { return nil }
        let total = wallet.totalPortfolioValue

        let now = Date()
        var dailyChange = 0.0
        var dailyChangePercent = 0.0
        if let priorValue, let priorAt,
           now.timeIntervalSince(priorAt) < 48 * 3600, priorValue > 0 {
            dailyChange = total - priorValue
            dailyChangePercent = (dailyChange / priorValue) * 100.0
        }
        priorValue = total
        priorAt = now

        let holdings = tokens
            .sorted { $0.valueUSD > $1.valueUSD }
            .prefix(5)
            .map { token in
                HoldingSnapshot(
                    symbol: token.symbol,
                    name: token.name,
                    value: token.valueUSD,
                    changePercent: token.change24h,
                    allocation: total > 0 ? token.valueUSD / total : 0
                )
            }

        return PortfolioSnapshot(
            totalValue: total,
            dailyChange: dailyChange,
            dailyChangePercent: dailyChangePercent,
            topHoldings: Array(holdings),
            alerts: [], // no alert source yet — empty, never fabricated
            lastUpdated: now
        )
    }
}

// MARK: - Transactions (real adapter onto the SwiftData record store)

/// Reads recent transactions from the app's real `TransactionRecord` persistence
/// store. This is a genuine adapter, not a stub — it returns exactly what has
/// been persisted. NOTE: nothing populates on-chain history into this store yet
/// (BaseNetwork has no eth_getLogs, and no indexer writes records), so it
/// currently returns an EMPTY list. It starts surfacing real transactions the
/// moment a producer writes TransactionRecords — no fabricated data in between.
@MainActor
final class SwiftDataTransactionProvider: TransactionDataProvider {

    private let store: SwiftDataStore

    init(store: SwiftDataStore) {
        self.store = store
    }

    func fetchRecent(limit: Int) async -> [TransactionSnapshot] {
        var descriptor = FetchDescriptor<TransactionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let records = (try? store.fetch(descriptor)) ?? []

        return records.map { record in
            let asset = record.tokenSymbol ?? "ETH"
            let amount: Double
            if let tokenAmount = record.tokenAmount, let value = Double(tokenAmount) {
                amount = value
            } else {
                // Wei → ETH (1e18) from the stored decimal string.
                amount = NSDecimalNumber(decimal: record.decimalValue / Decimal(1_000_000_000_000_000_000)).doubleValue
            }
            return TransactionSnapshot(
                id: record.id,
                type: record.direction,
                amount: amount,
                asset: asset,
                timestamp: record.timestamp,
                status: record.status
            )
        }
    }
}

// MARK: - System provider factory

extension TrinityContext {

    /// Build a TrinityContext wired to the real system providers (HealthKit,
    /// CoreLocation, WeatherKit) plus any app-data providers passed in. Sensor
    /// providers degrade to nil until their capabilities/Info.plist keys are set,
    /// so this never forces a permission prompt at construction time.
    static func withSystemProviders(
        portfolioProvider: PortfolioDataProvider? = nil,
        transactionProvider: TransactionDataProvider? = nil
    ) -> TrinityContext {
        var health: HealthDataProvider?
        var weather: WeatherDataProvider?
        #if canImport(HealthKit)
        health = HealthKitProvider()
        #endif
        let location = CoreLocationProvider()
        #if canImport(WeatherKit)
        if #available(iOS 16.0, *) { weather = WeatherKitProvider(locationProvider: location) }
        #endif
        return TrinityContext(
            healthProvider: health,
            locationProvider: location,
            weatherProvider: weather,
            portfolioProvider: portfolioProvider,
            transactionProvider: transactionProvider
        )
    }

    /// Full wiring: system sensor providers + the app-data adapters (live
    /// WalletManager holdings + the real TransactionRecord store). Call this from
    /// the Trinity construction site, passing the app's WalletManager, to give
    /// Trinity real portfolio context (transactions stay empty until a producer
    /// populates TransactionRecord — see SwiftDataTransactionProvider).
    @MainActor
    static func withAppProviders(wallet: WalletManager) -> TrinityContext {
        withSystemProviders(
            portfolioProvider: WalletPortfolioProvider(wallet: wallet),
            transactionProvider: SwiftDataTransactionProvider(store: .shared)
        )
    }
}
