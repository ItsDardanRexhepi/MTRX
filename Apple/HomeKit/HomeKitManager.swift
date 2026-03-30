import HomeKit

/// HomeKit integration for smart home sensor data on tokenized properties (Component 4 RWA)
@MainActor
final class HomeKitManager: NSObject, ObservableObject {
    @Published var homes: [HMHome] = []
    @Published var sensorReadings: [SensorReading] = []
    private let manager = HMHomeManager()

    struct SensorReading: Identifiable {
        let id = UUID()
        let accessoryName: String
        let characteristic: String
        let value: String
        let timestamp: Date
    }

    override init() {
        super.init()
        manager.delegate = self
    }

    func refreshHomes() {
        homes = manager.homes
    }

    /// Read all sensor data from a specific home for property monitoring
    func readSensors(for home: HMHome) async {
        var readings: [SensorReading] = []
        for accessory in home.accessories {
            for service in accessory.services {
                for characteristic in service.characteristics {
                    if let value = try? await readCharacteristic(characteristic) {
                        readings.append(SensorReading(
                            accessoryName: accessory.name,
                            characteristic: characteristic.localizedDescription,
                            value: value,
                            timestamp: Date()
                        ))
                    }
                }
            }
        }
        sensorReadings = readings
    }

    private func readCharacteristic(_ characteristic: HMCharacteristic) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            characteristic.readValue { error in
                if let error { continuation.resume(throwing: error); return }
                let value = characteristic.value.map { "\($0)" } ?? "N/A"
                continuation.resume(returning: value)
            }
        }
    }
}

extension HomeKitManager: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in homes = manager.homes }
    }
}
