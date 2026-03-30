// SensorFusion.swift
// MTRX Apple Integration — Awareness
// CoreMotion behavioral pattern analysis

import CoreMotion
import Foundation

// MARK: - Sensor Fusion Manager

final class SensorFusion {

    // MARK: - Shared Instance

    static let shared = SensorFusion()

    // MARK: - Properties

    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    private var motionBuffer: [CMDeviceMotion] = []
    private let bufferSize = 100

    // MARK: - Behavioral Context

    struct BehavioralContext {
        let activity: ActivityState
        let movement: MovementPattern
        let confidence: Double
        let isStationary: Bool
        let pedometerData: PedometerSnapshot?
        let altitude: AltitudeSnapshot?
        let timestamp: Date
    }

    enum ActivityState: String {
        case stationary
        case walking
        case running
        case cycling
        case driving
        case unknown
    }

    struct MovementPattern {
        let averageAcceleration: Double
        let rotationRate: Double
        let isShaking: Bool
        let isPhoneInPocket: Bool
        let orientationStable: Bool
    }

    struct PedometerSnapshot {
        let steps: Int
        let distance: Double
        let floorsAscended: Int
        let floorsDescended: Int
        let pace: Double?
        let cadence: Double?
    }

    struct AltitudeSnapshot {
        let relativeAltitude: Double
        let pressure: Double
    }

    // MARK: - Start Monitoring

    func startMonitoring(updateInterval: TimeInterval = 0.1) {
        startMotionUpdates(interval: updateInterval)
        startActivityUpdates()
        startPedometerUpdates()
        startAltimeterUpdates()
    }

    func stopMonitoring() {
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        motionBuffer.removeAll()
    }

    // MARK: - Current Context

    func currentContext() async -> BehavioralContext {
        let activity = await currentActivity()
        let movement = analyzeMovementPattern()
        let pedometerData = await currentPedometerData()
        let altitude = currentAltitude()

        return BehavioralContext(
            activity: activity,
            movement: movement,
            confidence: movement.orientationStable ? 0.9 : 0.6,
            isStationary: activity == .stationary,
            pedometerData: pedometerData,
            altitude: altitude,
            timestamp: Date()
        )
    }

    // MARK: - Motion Updates

    private func startMotionUpdates(interval: TimeInterval) {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = interval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion, error == nil else { return }
            self?.processMotion(motion)
        }
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        motionBuffer.append(motion)
        if motionBuffer.count > bufferSize {
            motionBuffer.removeFirst()
        }
    }

    // MARK: - Activity Recognition

    private func startActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }

        activityManager.startActivityUpdates(to: .main) { activity in
            guard let activity = activity else { return }
            _ = self.mapActivity(activity)
        }
    }

    private func currentActivity() async -> ActivityState {
        return await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: Date().addingTimeInterval(-60), to: Date(), to: .main) { activities, _ in
                guard let latest = activities?.last else {
                    continuation.resume(returning: .unknown)
                    return
                }
                continuation.resume(returning: self.mapActivity(latest))
            }
        }
    }

    private func mapActivity(_ activity: CMMotionActivity) -> ActivityState {
        if activity.stationary { return .stationary }
        if activity.running { return .running }
        if activity.cycling { return .cycling }
        if activity.automotive { return .driving }
        if activity.walking { return .walking }
        return .unknown
    }

    // MARK: - Movement Pattern Analysis

    private func analyzeMovementPattern() -> MovementPattern {
        guard !motionBuffer.isEmpty else {
            return MovementPattern(
                averageAcceleration: 0,
                rotationRate: 0,
                isShaking: false,
                isPhoneInPocket: false,
                orientationStable: true
            )
        }

        let accelerations = motionBuffer.map { motion in
            sqrt(pow(motion.userAcceleration.x, 2) + pow(motion.userAcceleration.y, 2) + pow(motion.userAcceleration.z, 2))
        }

        let rotations = motionBuffer.map { motion in
            sqrt(pow(motion.rotationRate.x, 2) + pow(motion.rotationRate.y, 2) + pow(motion.rotationRate.z, 2))
        }

        let avgAcceleration = accelerations.reduce(0, +) / Double(accelerations.count)
        let avgRotation = rotations.reduce(0, +) / Double(rotations.count)
        let maxAcceleration = accelerations.max() ?? 0

        // Shake detection: high acceleration spikes
        let isShaking = maxAcceleration > 2.5

        // Pocket detection: gravity vector orientation
        let isInPocket: Bool
        if let latest = motionBuffer.last {
            isInPocket = abs(latest.gravity.y) > 0.8 && latest.gravity.y < 0
        } else {
            isInPocket = false
        }

        // Orientation stability
        let gravityVariance: Double
        if motionBuffer.count > 10 {
            let recentGravity = motionBuffer.suffix(10).map { $0.gravity.z }
            let meanGravity = recentGravity.reduce(0, +) / Double(recentGravity.count)
            gravityVariance = recentGravity.map { pow($0 - meanGravity, 2) }.reduce(0, +) / Double(recentGravity.count)
        } else {
            gravityVariance = 0
        }

        return MovementPattern(
            averageAcceleration: avgAcceleration,
            rotationRate: avgRotation,
            isShaking: isShaking,
            isPhoneInPocket: isInPocket,
            orientationStable: gravityVariance < 0.01
        )
    }

    // MARK: - Pedometer

    private func startPedometerUpdates() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        pedometer.startUpdates(from: startOfDay) { _, _ in }
    }

    private func currentPedometerData() async -> PedometerSnapshot? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        let startOfDay = Calendar.current.startOfDay(for: Date())

        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: startOfDay, to: Date()) { data, _ in
                guard let data = data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: PedometerSnapshot(
                    steps: data.numberOfSteps.intValue,
                    distance: data.distance?.doubleValue ?? 0,
                    floorsAscended: data.floorsAscended?.intValue ?? 0,
                    floorsDescended: data.floorsDescended?.intValue ?? 0,
                    pace: data.currentPace?.doubleValue,
                    cadence: data.currentCadence?.doubleValue
                ))
            }
        }
    }

    // MARK: - Altimeter

    private func startAltimeterUpdates() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { _, _ in }
    }

    private var latestAltitude: CMAltitudeData?

    private func currentAltitude() -> AltitudeSnapshot? {
        guard let data = latestAltitude else { return nil }
        return AltitudeSnapshot(
            relativeAltitude: data.relativeAltitude.doubleValue,
            pressure: data.pressure.doubleValue
        )
    }
}
