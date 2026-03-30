// SupplyChainManager.swift
// MTRX Blockchain - Components - Supply Chain
//
// On-chain supply chain tracking: provenance, checkpoints, IoT sensor attestation

import Foundation
import Combine

// MARK: - Protocols

protocol SupplyChainDelegate: AnyObject {
    func supplyChain(_ manager: SupplyChainManager, didUpdateShipment shipment: Shipment)
    func supplyChain(_ manager: SupplyChainManager, checkpointReached checkpoint: SupplyCheckpoint)
    func supplyChain(_ manager: SupplyChainManager, anomalyDetected anomaly: SupplyAnomaly)
}

// MARK: - Data Models

struct Shipment: Identifiable, Codable {
    let id: String
    let originAddress: String
    let destinationAddress: String
    let assetTokenId: String
    let createdAt: Date
    var status: ShipmentStatus
    var checkpoints: [SupplyCheckpoint]
    var sensorReadings: [SensorReading]
    var estimatedArrival: Date?
    var carrier: String?
    var contractAddress: String?
}

enum ShipmentStatus: String, Codable {
    case created, inTransit, atCheckpoint, delayed, delivered, disputed
}

struct SupplyCheckpoint: Identifiable, Codable {
    let id: String
    let shipmentId: String
    let location: GeoCoordinate
    let timestamp: Date
    let attestationHash: String
    let verifiedBy: String
    let notes: String?
}

struct GeoCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

struct SensorReading: Identifiable, Codable {
    let id: String
    let sensorType: SensorType
    let value: Double
    let unit: String
    let timestamp: Date
    let deviceId: String
}

enum SensorType: String, Codable {
    case temperature, humidity, pressure, shock, light, gps
}

struct SupplyAnomaly: Identifiable {
    let id: String
    let shipmentId: String
    let type: AnomalyType
    let severity: Double
    let detectedAt: Date
    let reading: SensorReading?
}

enum AnomalyType: String {
    case temperatureExcursion, humidityBreach, shockDetected
    case routeDeviation, delayExceeded, tamperAlert
}

enum SupplyChainError: Error, LocalizedError {
    case shipmentNotFound(String)
    case invalidCheckpoint
    case attestationFailed
    case sensorDataCorrupt
    case contractCallFailed(String)

    var errorDescription: String? {
        switch self {
        case .shipmentNotFound(let id): return "Shipment not found: \(id)"
        case .invalidCheckpoint: return "Invalid checkpoint data."
        case .attestationFailed: return "Checkpoint attestation failed."
        case .sensorDataCorrupt: return "Sensor data integrity check failed."
        case .contractCallFailed(let r): return "Contract call failed: \(r)"
        }
    }
}

// MARK: - SupplyChainManager

final class SupplyChainManager: ObservableObject {

    static let shared = SupplyChainManager()

    weak var delegate: SupplyChainDelegate?

    @Published private(set) var activeShipments: [Shipment] = []
    @Published private(set) var recentCheckpoints: [SupplyCheckpoint] = []

    private var shipmentStore: [String: Shipment] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let processingQueue = DispatchQueue(label: "com.mtrx.supplychain", qos: .userInitiated)

    // MARK: - Shipment Lifecycle

    func createShipment(origin: String, destination: String, assetTokenId: String, carrier: String?) async throws -> Shipment {
        let shipment = Shipment(
            id: UUID().uuidString,
            originAddress: origin,
            destinationAddress: destination,
            assetTokenId: assetTokenId,
            createdAt: Date(),
            status: .created,
            checkpoints: [],
            sensorReadings: [],
            estimatedArrival: nil,
            carrier: carrier,
            contractAddress: nil
        )
        shipmentStore[shipment.id] = shipment
        await MainActor.run { activeShipments.append(shipment) }
        return shipment
    }

    func getShipment(id: String) -> Shipment? {
        shipmentStore[id]
    }

    func updateStatus(shipmentId: String, status: ShipmentStatus) async throws {
        guard var shipment = shipmentStore[shipmentId] else {
            throw SupplyChainError.shipmentNotFound(shipmentId)
        }
        shipment.status = status
        shipmentStore[shipmentId] = shipment
        delegate?.supplyChain(self, didUpdateShipment: shipment)
        await MainActor.run {
            if let idx = activeShipments.firstIndex(where: { $0.id == shipmentId }) {
                activeShipments[idx] = shipment
            }
        }
    }

    // MARK: - Checkpoints

    func recordCheckpoint(shipmentId: String, latitude: Double, longitude: Double, verifiedBy: String, notes: String? = nil) async throws -> SupplyCheckpoint {
        guard var shipment = shipmentStore[shipmentId] else {
            throw SupplyChainError.shipmentNotFound(shipmentId)
        }

        let attestationHash = generateAttestationHash(shipmentId: shipmentId, lat: latitude, lon: longitude, timestamp: Date())

        let checkpoint = SupplyCheckpoint(
            id: UUID().uuidString,
            shipmentId: shipmentId,
            location: GeoCoordinate(latitude: latitude, longitude: longitude),
            timestamp: Date(),
            attestationHash: attestationHash,
            verifiedBy: verifiedBy,
            notes: notes
        )

        shipment.checkpoints.append(checkpoint)
        shipment.status = .atCheckpoint
        shipmentStore[shipmentId] = shipment

        delegate?.supplyChain(self, checkpointReached: checkpoint)
        await MainActor.run { recentCheckpoints.insert(checkpoint, at: 0) }
        return checkpoint
    }

    // MARK: - Sensor Data

    func recordSensorReading(shipmentId: String, reading: SensorReading) async throws {
        guard var shipment = shipmentStore[shipmentId] else {
            throw SupplyChainError.shipmentNotFound(shipmentId)
        }
        shipment.sensorReadings.append(reading)
        shipmentStore[shipmentId] = shipment

        if let anomaly = detectAnomaly(shipment: shipment, reading: reading) {
            delegate?.supplyChain(self, anomalyDetected: anomaly)
        }
    }

    // MARK: - Provenance

    func getProvenance(assetTokenId: String) -> [SupplyCheckpoint] {
        shipmentStore.values
            .filter { $0.assetTokenId == assetTokenId }
            .flatMap { $0.checkpoints }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private

    private func generateAttestationHash(shipmentId: String, lat: Double, lon: Double, timestamp: Date) -> String {
        let input = "\(shipmentId):\(lat):\(lon):\(timestamp.timeIntervalSince1970)"
        return input.data(using: .utf8)?.base64EncodedString() ?? ""
    }

    private func detectAnomaly(shipment: Shipment, reading: SensorReading) -> SupplyAnomaly? {
        switch reading.sensorType {
        case .temperature where reading.value > 40 || reading.value < -20:
            return SupplyAnomaly(id: UUID().uuidString, shipmentId: shipment.id, type: .temperatureExcursion, severity: 0.8, detectedAt: Date(), reading: reading)
        case .humidity where reading.value > 90:
            return SupplyAnomaly(id: UUID().uuidString, shipmentId: shipment.id, type: .humidityBreach, severity: 0.6, detectedAt: Date(), reading: reading)
        case .shock where reading.value > 5.0:
            return SupplyAnomaly(id: UUID().uuidString, shipmentId: shipment.id, type: .shockDetected, severity: 0.9, detectedAt: Date(), reading: reading)
        default:
            return nil
        }
    }
}
