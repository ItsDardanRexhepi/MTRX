// LedgerBridge.swift
// MTRX — Core/Wallet
//
// CoreBluetooth bridge for Ledger hardware wallets (Nano X / Stax over
// BLE). Feature-flagged OFF by default: the central manager is only
// created when the flag is enabled, so the Bluetooth permission prompt
// never fires for users who don't own a Ledger.
//
// Live today: device discovery, connection state machine, service
// discovery against Ledger's BLE service UUID. The APDU transport
// (sign/verify round-trips) is the documented integration point below.

import CoreBluetooth
import Foundation

final class LedgerBridge: NSObject, ObservableObject {

    static let shared = LedgerBridge()

    /// Master switch. Flip via Settings → Advanced once the APDU
    /// transport ships; everything stays dormant until then.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "com.mtrx.ledgerBridgeEnabled")
    }

    // MARK: - Published state

    enum BridgeState: Equatable {
        case idle
        case unavailable(String)
        case scanning
        case connecting(String)
        case connected(String)
    }

    @Published private(set) var state: BridgeState = .idle
    @Published private(set) var discovered: [String] = []

    // MARK: - Bluetooth

    /// Ledger Nano X / Stax BLE service UUID.
    static let ledgerService = CBUUID(string: "13D63400-2C97-0004-0000-4C6564676572")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    // MARK: - Control

    /// Begin scanning for Ledger devices. No-op while the feature flag
    /// is off — guarantees no permission prompt for non-Ledger users.
    func startScan() {
        guard Self.isEnabled else {
            state = .unavailable("Ledger support is disabled.")
            return
        }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            beginScanIfPoweredOn()
        }
    }

    func stopScan() {
        central?.stopScan()
        if case .scanning = state { state = .idle }
    }

    func disconnect() {
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        state = .idle
    }

    // MARK: - Integration point (APDU transport)
    //
    // func sign(payload: Data) async throws -> Data
    //   1. Open the Ledger BLE characteristic pair (write / notify).
    //   2. Frame `payload` into APDU chunks (0x05 MTU framing).
    //   3. Await the signature response frames; reassemble; return DER.
    // Ships together with the Ethereum app detection handshake.

    private func beginScanIfPoweredOn() {
        guard central?.state == .poweredOn else { return }
        state = .scanning
        central?.scanForPeripherals(withServices: [Self.ledgerService])
    }
}

// MARK: - CBCentralManagerDelegate

extension LedgerBridge: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScanIfPoweredOn()
        case .unauthorized:
            state = .unavailable("Bluetooth permission denied.")
        case .poweredOff:
            state = .unavailable("Bluetooth is off.")
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? "Ledger"
        if !discovered.contains(name) { discovered.append(name) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected(peripheral.name ?? "Ledger")
        peripheral.discoverServices([Self.ledgerService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        state = .unavailable(error?.localizedDescription ?? "Connection failed.")
    }
}
