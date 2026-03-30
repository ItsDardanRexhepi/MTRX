//
//  HealthPublisher.swift
//  MTRX
//
//  HealthKit real-time stream bridging HKObserverQuery to Combine publishers.
//

import Foundation
import Combine
import HealthKit

// MARK: - Heart Rate Sample

struct HeartRateSample: Equatable {
    let bpm: Double
    let timestamp: Date
    let motionContext: HeartRateMotionContext
    let source: String

    enum HeartRateMotionContext: String {
        case sedentary
        case active
        case unknown
    }
}

// MARK: - HRV Sample

struct HRVSample: Equatable {
    let sdnn: Double
    let timestamp: Date
    let source: String
}

// MARK: - Sleep State

struct SleepStateData: Equatable {
    let stage: SleepStage
    let startDate: Date
    let endDate: Date?
    let source: String

    enum SleepStage: String, CaseIterable {
        case awake
        case remSleep
        case coreOrLightSleep
        case deepSleep
        case unknown
    }
}

// MARK: - Activity Data

struct ActivityData: Equatable {
    let activeEnergyBurned: Double
    let exerciseMinutes: Double
    let standHours: Int
    let stepCount: Int
    let distanceWalkingRunning: Double
    let timestamp: Date
}

// MARK: - Health Authorization Status

struct HealthAuthorizationStatus {
    let heartRate: HKAuthorizationStatus
    let hrv: HKAuthorizationStatus
    let sleep: HKAuthorizationStatus
    let activity: HKAuthorizationStatus

    var isFullyAuthorized: Bool {
        [heartRate, hrv, sleep, activity].allSatisfy { $0 == .sharingAuthorized }
    }
}

// MARK: - Health Publisher

/// Bridges HealthKit observer queries to Combine publishers for real-time health data streaming.
final class HealthPublisher: ObservableObject {

    // MARK: - Publishers

    /// Emits real-time heart rate samples.
    let heartRate = PassthroughSubject<HeartRateSample, Never>()

    /// Emits heart rate variability (SDNN) samples.
    let hrv = PassthroughSubject<HRVSample, Never>()

    /// Emits sleep state transitions.
    let sleepState = PassthroughSubject<SleepStateData, Never>()

    /// Emits aggregated activity data updates.
    let activity = CurrentValueSubject<ActivityData?, Never>(nil)

    /// Whether HealthKit data is being actively observed.
    @Published private(set) var isObserving: Bool = false

    /// Current authorization status.
    @Published private(set) var authorizationStatus: HealthAuthorizationStatus?

    // MARK: - HealthKit Store

    private let healthStore: HKHealthStore
    private let isHealthDataAvailable: Bool

    // MARK: - Observer Queries

    private var heartRateObserverQuery: HKObserverQuery?
    private var hrvObserverQuery: HKObserverQuery?
    private var sleepObserverQuery: HKObserverQuery?
    private var activityObserverQuery: HKObserverQuery?

    // MARK: - Anchored Queries

    private var heartRateAnchor: HKQueryAnchor?
    private var hrvAnchor: HKQueryAnchor?
    private var sleepAnchor: HKQueryAnchor?

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Sample Types

    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
    private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
    private let standTimeType = HKQuantityType.quantityType(forIdentifier: .appleStandTime)!
    private let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

    // MARK: - Read Types Set

    private var readTypes: Set<HKObjectType> {
        [heartRateType, hrvType, sleepType, activeEnergyType, exerciseTimeType, stepCountType]
    }

    // MARK: - Initialization

    init() {
        self.isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        self.healthStore = HKHealthStore()
    }

    // MARK: - Authorization

    /// Requests HealthKit authorization for required data types.
    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthPublisherError.healthDataUnavailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        await updateAuthorizationStatus()
    }

    /// Refreshes the cached authorization status.
    @MainActor
    private func updateAuthorizationStatus() {
        authorizationStatus = HealthAuthorizationStatus(
            heartRate: healthStore.authorizationStatus(for: heartRateType),
            hrv: healthStore.authorizationStatus(for: hrvType),
            sleep: healthStore.authorizationStatus(for: sleepType),
            activity: healthStore.authorizationStatus(for: activeEnergyType)
        )
    }

    // MARK: - Start / Stop Observing

    /// Begins observing all health data types and emitting through publishers.
    func startObserving() {
        guard isHealthDataAvailable, !isObserving else { return }
        isObserving = true

        startHeartRateObserver()
        startHRVObserver()
        startSleepObserver()
        startActivityObserver()
    }

    /// Stops all observer queries and anchored queries.
    func stopObserving() {
        isObserving = false

        if let query = heartRateObserverQuery { healthStore.stop(query) }
        if let query = hrvObserverQuery { healthStore.stop(query) }
        if let query = sleepObserverQuery { healthStore.stop(query) }
        if let query = activityObserverQuery { healthStore.stop(query) }

        heartRateObserverQuery = nil
        hrvObserverQuery = nil
        sleepObserverQuery = nil
        activityObserverQuery = nil
    }

    // MARK: - Private: Heart Rate Observer

    private func startHeartRateObserver() {
        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            self?.fetchLatestHeartRate()
            completionHandler()
        }
        heartRateObserverQuery = query
        healthStore.execute(query)
    }

    private func fetchLatestHeartRate() {
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: heartRateAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.heartRateAnchor = newAnchor
            guard let quantitySamples = samples as? [HKQuantitySample] else { return }

            for sample in quantitySamples {
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                let heartRateSample = HeartRateSample(
                    bpm: bpm,
                    timestamp: sample.startDate,
                    motionContext: .unknown,
                    source: sample.sourceRevision.source.name
                )
                DispatchQueue.main.async {
                    self?.heartRate.send(heartRateSample)
                }
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Private: HRV Observer

    private func startHRVObserver() {
        let query = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            self?.fetchLatestHRV()
            completionHandler()
        }
        hrvObserverQuery = query
        healthStore.execute(query)
    }

    private func fetchLatestHRV() {
        let query = HKAnchoredObjectQuery(
            type: hrvType,
            predicate: nil,
            anchor: hrvAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.hrvAnchor = newAnchor
            guard let quantitySamples = samples as? [HKQuantitySample] else { return }

            for sample in quantitySamples {
                let sdnn = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                let hrvSample = HRVSample(
                    sdnn: sdnn,
                    timestamp: sample.startDate,
                    source: sample.sourceRevision.source.name
                )
                DispatchQueue.main.async {
                    self?.hrv.send(hrvSample)
                }
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Private: Sleep Observer

    private func startSleepObserver() {
        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            self?.fetchLatestSleep()
            completionHandler()
        }
        sleepObserverQuery = query
        healthStore.execute(query)
    }

    private func fetchLatestSleep() {
        let query = HKAnchoredObjectQuery(
            type: sleepType,
            predicate: nil,
            anchor: sleepAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.sleepAnchor = newAnchor
            guard let categorySamples = samples as? [HKCategorySample] else { return }

            for sample in categorySamples {
                let stage: SleepStateData.SleepStage = {
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.awake.rawValue:        return .awake
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:    return .remSleep
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:   return .coreOrLightSleep
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:   return .deepSleep
                    default: return .unknown
                    }
                }()

                let sleepData = SleepStateData(
                    stage: stage,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    source: sample.sourceRevision.source.name
                )
                DispatchQueue.main.async {
                    self?.sleepState.send(sleepData)
                }
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Private: Activity Observer

    private func startActivityObserver() {
        // Activity is polled every 60 seconds from the activity summary
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchActivitySummary()
            }
            .store(in: &cancellables)
    }

    private func fetchActivitySummary() {
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: Date())

        let predicate = HKQuery.predicateForActivitySummary(with: components)
        let query = HKActivitySummaryQuery(predicate: predicate) { [weak self] _, summaries, _ in
            guard let summary = summaries?.first else { return }

            let activityData = ActivityData(
                activeEnergyBurned: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                standHours: Int(summary.appleStandHours.doubleValue(for: .count())),
                stepCount: 0,
                distanceWalkingRunning: 0,
                timestamp: Date()
            )
            DispatchQueue.main.async {
                self?.activity.send(activityData)
            }
        }
        healthStore.execute(query)
    }
}

// MARK: - Errors

enum HealthPublisherError: Error, LocalizedError {
    case healthDataUnavailable
    case authorizationDenied
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "HealthKit is not available on this device."
        case .authorizationDenied:
            return "HealthKit authorization was denied."
        case .queryFailed(let reason):
            return "HealthKit query failed: \(reason)"
        }
    }
}
