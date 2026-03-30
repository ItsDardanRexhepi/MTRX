// BluetoothManager.swift
// MTRX Apple Integration — Connectivity
// CoreBluetooth for Ledger hardware wallets + IoT device communication

import CoreBluetooth
import Foundation

// MARK: - Bluetooth Manager

final class BluetoothManager: NSObject, ObservableObject {

    // MARK: - Shared Instance

    static let shared = BluetoothManager()

    // MARK: - Properties

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?

    @Published var state: CBManagerState = .unknown
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isConnected = false
    @Published var connectedDeviceName: String?

    private var scanContinuation: CheckedContinuation<[DiscoveredDevice], Never>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var readContinuation: CheckedContinuation<Data, Error>?

    // MARK: - Known Service UUIDs

    private struct ServiceUUIDs {
        static let ledgerNanoX = CBUUID(string: "13D63400-2C97-0004-0000-4C6564676572")
        static let ledgerService = CBUUID(string: "13D63400-2C97-0004-0001-4C6564676572")
        static let mtrxIoT = CBUUID(string: "MTRX0001-0000-1000-8000-00805F9B34FB")
    }

    private struct CharacteristicUUIDs {
        static let ledgerWrite = CBUUID(string: "13D63400-2C97-0004-0002-4C6564676572")
        static let ledgerNotify = CBUUID(string: "13D63400-2C97-0004-0003-4C6564676572")
    }

    // MARK: - Initialization

    func initialize() {
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scanning

    /// Scans for nearby Bluetooth devices matching MTRX-compatible services.
    func startScanning(timeout: TimeInterval = 10) {
        guard centralManager?.state == .poweredOn else { return }
        discoveredDevices.removeAll()

        centralManager?.scanForPeripherals(
            withServices: [ServiceUUIDs.ledgerNanoX, ServiceUUIDs.mtrxIoT],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.stopScanning()
        }
    }

    /// Stops scanning for peripherals.
    func stopScanning() {
        centralManager?.stopScan()
    }

    // MARK: - Connection

    /// Connects to a discovered peripheral.
    func connect(to device: DiscoveredDevice) async throws {
        guard let peripheral = device.peripheral else {
            throw BluetoothError.deviceNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.connectContinuation = continuation
            centralManager?.connect(peripheral, options: nil)
        }
    }

    /// Disconnects from the connected peripheral.
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
        connectedPeripheral = nil
        targetCharacteristic = nil
        isConnected = false
        connectedDeviceName = nil
    }

    // MARK: - Ledger Communication

    /// Sends an APDU command to a connected Ledger device.
    func sendAPDU(_ apdu: Data) async throws -> Data {
        guard let characteristic = targetCharacteristic, let peripheral = connectedPeripheral else {
            throw BluetoothError.notConnected
        }

        // Write the APDU command
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.writeContinuation = continuation
            peripheral.writeValue(apdu, for: characteristic, type: .withResponse)
        }

        // Read the response
        return try await withCheckedThrowingContinuation { continuation in
            self.readContinuation = continuation
        }
    }

    /// Gets the Ethereum address from a connected Ledger device.
    func getLedgerEthereumAddress(path: String = "44'/60'/0'/0/0") async throws -> String {
        let pathComponents = path.split(separator: "/").compactMap { component -> UInt32? in
            let cleaned = component.replacingOccurrences(of: "'", with: "")
            guard var value = UInt32(cleaned) else { return nil }
            if component.hasSuffix("'") { value |= 0x80000000 }
            return value
        }

        var apdu = Data([0xE0, 0x02, 0x00, 0x00])
        var pathData = Data([UInt8(pathComponents.count)])
        for component in pathComponents {
            var bigEndian = component.bigEndian
            pathData.append(Data(bytes: &bigEndian, count: 4))
        }
        apdu.append(UInt8(pathData.count))
        apdu.append(pathData)

        let response = try await sendAPDU(apdu)
        guard response.count > 2 else {
            throw BluetoothError.invalidResponse
        }

        let addressLength = Int(response[0])
        let addressData = response[1...addressLength]
        return "0x" + addressData.map { String(format: "%02x", $0) }.joined()
    }

    /// Signs a transaction hash on the connected Ledger device.
    func signWithLedger(transactionHash: Data, path: String = "44'/60'/0'/0/0") async throws -> Data {
        var apdu = Data([0xE0, 0x04, 0x00, 0x00])
        apdu.append(UInt8(transactionHash.count))
        apdu.append(transactionHash)

        return try await sendAPDU(apdu)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { self.state = central.state }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: peripheral.name ?? "Unknown Device",
            rssi: RSSI.intValue,
            peripheral: peripheral
        )

        DispatchQueue.main.async {
            if !self.discoveredDevices.contains(where: { $0.id == device.id }) {
                self.discoveredDevices.append(device)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([ServiceUUIDs.ledgerNanoX, ServiceUUIDs.ledgerService])

        DispatchQueue.main.async {
            self.isConnected = true
            self.connectedDeviceName = peripheral.name
        }

        connectContinuation?.resume()
        connectContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectContinuation?.resume(throwing: BluetoothError.connectionFailed(error?.localizedDescription ?? "Unknown"))
        connectContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectedDeviceName = nil
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([CharacteristicUUIDs.ledgerWrite, CharacteristicUUIDs.ledgerNotify], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == CharacteristicUUIDs.ledgerWrite {
                targetCharacteristic = characteristic
            }
            if characteristic.uuid == CharacteristicUUIDs.ledgerNotify {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            writeContinuation?.resume(throwing: error)
        } else {
            writeContinuation?.resume()
        }
        writeContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            readContinuation?.resume(throwing: error)
        } else if let data = characteristic.value {
            readContinuation?.resume(returning: data)
        }
        readContinuation = nil
    }
}

// MARK: - Discovered Device

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    weak var peripheral: CBPeripheral?
}

// MARK: - Bluetooth Error

enum BluetoothError: LocalizedError {
    case notPoweredOn
    case deviceNotFound
    case notConnected
    case connectionFailed(String)
    case invalidResponse
    case communicationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notPoweredOn: return "Bluetooth is not powered on"
        case .deviceNotFound: return "Bluetooth device not found"
        case .notConnected: return "No Bluetooth device connected"
        case .connectionFailed(let reason): return "Bluetooth connection failed: \(reason)"
        case .invalidResponse: return "Invalid response from Bluetooth device"
        case .communicationFailed(let reason): return "Bluetooth communication failed: \(reason)"
        }
    }
}
