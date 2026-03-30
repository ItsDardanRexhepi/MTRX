import WatchConnectivity
import HealthKit

/// Stream HealthKit data from Apple Watch to iPhone for Trinity context-aware responses
final class WatchHealthBridge: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private let session = WCSession.default

    @Published var currentHeartRate: Double = 0
    @Published var activeCalories: Double = 0

    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

    override init() {
        super.init()
        if WCSession.isSupported() { session.delegate = self; session.activate() }
    }

    func startMonitoring() {
        let typesToRead: Set<HKSampleType> = [heartRateType, activeEnergyType]
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] granted, _ in
            guard granted else { return }
            self?.startHeartRateQuery()
            self?.startActiveEnergyQuery()
        }
    }

    private func startHeartRateQuery() {
        let query = HKAnchoredObjectQuery(type: heartRateType, predicate: nil, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            self?.processHeartRate(samples)
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHeartRate(samples)
        }
        healthStore.execute(query)
    }

    private func startActiveEnergyQuery() {
        let query = HKAnchoredObjectQuery(type: activeEnergyType, predicate: nil, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            self?.processActiveEnergy(samples)
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processActiveEnergy(samples)
        }
        healthStore.execute(query)
    }

    private func processHeartRate(_ samples: [HKSample]?) {
        guard let sample = samples?.last as? HKQuantitySample else { return }
        let bpm = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        DispatchQueue.main.async { self.currentHeartRate = bpm }
        sendToPhone(["heartRate": bpm, "timestamp": sample.endDate.timeIntervalSince1970])
    }

    private func processActiveEnergy(_ samples: [HKSample]?) {
        guard let sample = samples?.last as? HKQuantitySample else { return }
        let kcal = sample.quantity.doubleValue(for: .kilocalorie())
        DispatchQueue.main.async { self.activeCalories = kcal }
        sendToPhone(["activeCalories": kcal, "timestamp": sample.endDate.timeIntervalSince1970])
    }

    private func sendToPhone(_ data: [String: Any]) {
        guard session.isReachable else { return }
        session.sendMessage(["healthData": data], replyHandler: nil)
    }
}

extension WatchHealthBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
