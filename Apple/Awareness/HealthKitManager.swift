// HealthKitManager.swift
// MTRX Apple Integration — Awareness
// Apple Watch health data: heart rate, HRV, sleep, activity

import HealthKit
import Foundation

// MARK: - HealthKit Manager

final class HealthKitManager {

    // MARK: - Shared Instance

    static let shared = HealthKitManager()

    // MARK: - Properties

    private let healthStore = HKHealthStore()
    private var activeObservers: [HKObserverQuery] = []
    private var anchoredQueries: [String: HKQueryAnchor] = [:]

    // MARK: - Health Data Types

    struct HealthSnapshot {
        let heartRate: Double?
        let heartRateVariability: Double?
        let restingHeartRate: Double?
        let stressLevel: StressLevel
        let sleepAnalysis: SleepSummary?
        let activitySummary: ActivitySummary?
        let timestamp: Date
    }

    enum StressLevel: String {
        case low, moderate, high, veryHigh
    }

    struct SleepSummary {
        let totalSleepHours: Double
        let deepSleepHours: Double
        let remSleepHours: Double
        let awakenings: Int
        let sleepQualityScore: Double
    }

    struct ActivitySummary {
        let activeCalories: Double
        let exerciseMinutes: Double
        let standHours: Int
        let stepCount: Int
        let distance: Double
    }

    // MARK: - Read/Write Types

    private var readTypes: Set<HKObjectType> {
        let types: [HKObjectType?] = [
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime),
            HKQuantityType.quantityType(forIdentifier: .appleStandTime),
            HKQuantityType.quantityType(forIdentifier: .stepCount),
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.activitySummaryType()
        ]
        return Set(types.compactMap { $0 })
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Current Snapshot

    func currentSnapshot() async throws -> HealthSnapshot {
        async let heartRate = fetchLatestQuantity(.heartRate, unit: HKUnit(from: "count/min"))
        async let hrv = fetchLatestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let restingHR = fetchLatestQuantity(.restingHeartRate, unit: HKUnit(from: "count/min"))
        async let sleep = fetchSleepSummary()
        async let activity = fetchActivitySummary()

        let hr = try? await heartRate
        let hrvValue = try? await hrv
        let restHR = try? await restingHR
        let sleepData = try? await sleep
        let activityData = try? await activity

        let stressLevel = calculateStressLevel(heartRate: hr, hrv: hrvValue, sleep: sleepData)

        return HealthSnapshot(
            heartRate: hr,
            heartRateVariability: hrvValue,
            restingHeartRate: restHR,
            stressLevel: stressLevel,
            sleepAnalysis: sleepData,
            activitySummary: activityData,
            timestamp: Date()
        )
    }

    // MARK: - Quantity Fetching

    private func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.typeUnavailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .hour, value: -1, to: Date()), end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(throwing: HealthKitError.noData)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Sleep Analysis

    private func fetchSleepSummary() async throws -> SleepSummary {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.typeUnavailable
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -1, to: startOfDay), end: Date(), options: .strictEndDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let categorySamples = (samples as? [HKCategorySample]) ?? []
                var totalSleep: TimeInterval = 0
                var deepSleep: TimeInterval = 0
                var remSleep: TimeInterval = 0
                var awakenings = 0

                for sample in categorySamples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                    case .asleepDeep:
                        deepSleep += duration
                        totalSleep += duration
                    case .asleepREM:
                        remSleep += duration
                        totalSleep += duration
                    case .asleepCore:
                        totalSleep += duration
                    case .awake:
                        awakenings += 1
                    default:
                        break
                    }
                }

                let totalHours = totalSleep / 3600
                let qualityScore = min(1.0, (totalHours / 8.0) * (1.0 - Double(awakenings) * 0.05))

                continuation.resume(returning: SleepSummary(
                    totalSleepHours: totalHours,
                    deepSleepHours: deepSleep / 3600,
                    remSleepHours: remSleep / 3600,
                    awakenings: awakenings,
                    sleepQualityScore: max(0, qualityScore)
                ))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Activity Summary

    private func fetchActivitySummary() async throws -> ActivitySummary {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictEndDate)

        async let calories = fetchSum(.activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        async let exercise = fetchSum(.appleExerciseTime, unit: .minute(), predicate: predicate)
        async let steps = fetchSum(.stepCount, unit: .count(), predicate: predicate)
        async let distance = fetchSum(.distanceWalkingRunning, unit: .meter(), predicate: predicate)

        return ActivitySummary(
            activeCalories: (try? await calories) ?? 0,
            exerciseMinutes: (try? await exercise) ?? 0,
            standHours: 0,
            stepCount: Int((try? await steps) ?? 0),
            distance: (try? await distance) ?? 0
        )
    }

    private func fetchSum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async throws -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.typeUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let sum = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Background Observation

    func startObserving(onChange: @escaping (HKQuantityTypeIdentifier) -> Void) {
        let typesToObserve: [HKQuantityTypeIdentifier] = [.heartRate, .heartRateVariabilitySDNN, .stepCount]

        for identifier in typesToObserve {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, _ in
                onChange(identifier)
                completionHandler()
            }
            healthStore.execute(query)
            activeObservers.append(query)
        }
    }

    func stopObserving() {
        for query in activeObservers {
            healthStore.stop(query)
        }
        activeObservers.removeAll()
    }

    // MARK: - Stress Calculation

    private func calculateStressLevel(heartRate: Double?, hrv: Double?, sleep: SleepSummary?) -> StressLevel {
        var stressScore = 0.0

        if let hr = heartRate {
            if hr > 100 { stressScore += 0.3 }
            else if hr > 80 { stressScore += 0.15 }
        }

        if let hrvValue = hrv {
            if hrvValue < 20 { stressScore += 0.4 }
            else if hrvValue < 40 { stressScore += 0.2 }
        }

        if let sleep = sleep, sleep.totalSleepHours < 6 {
            stressScore += 0.3
        }

        switch stressScore {
        case ..<0.2: return .low
        case 0.2..<0.4: return .moderate
        case 0.4..<0.7: return .high
        default: return .veryHigh
        }
    }
}

// MARK: - HealthKit Error

enum HealthKitError: LocalizedError {
    case notAvailable
    case typeUnavailable
    case noData
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "HealthKit is not available on this device"
        case .typeUnavailable: return "Requested health data type is unavailable"
        case .noData: return "No health data found"
        case .notAuthorized: return "HealthKit access not authorized"
        }
    }
}
