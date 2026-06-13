// HyperCompression.swift
// MTRX
//
// Dynamic payload minimizer for ultra-constrained links. Strips verbose
// application payloads down to a tight, fixed-field byte structure that
// fits inside the strict size budgets of constrained carrier paths and
// CoreBluetooth advertising/GATT transfers. All processing is local.

import Foundation

/// A structured local intent — the unit the app queues and transmits
/// when off-grid (a payment, a message, an identity/contract action).
struct LocalIntent: Codable, Identifiable, Equatable {
    enum Kind: UInt8, Codable { case payment = 1, message = 2, contract = 3, identity = 4, insurance = 5 }

    let id: UUID
    let kind: Kind
    /// Short opaque reference (recipient handle, contract name, etc.).
    let reference: String
    /// Integer amount in minor units (cents / wei-scaled), 0 when N/A.
    let amount: UInt32
    /// Free-form micro-note, truncated hard for the constrained budget.
    let note: String
    let createdAt: Date

    init(kind: Kind, reference: String, amount: UInt32 = 0, note: String = "") {
        self.id = UUID()
        self.kind = kind
        self.reference = String(reference.prefix(24))
        self.amount = amount
        self.note = String(note.prefix(48))
        self.createdAt = Date()
    }
}

enum HyperCompression {

    /// Tight bit-packed encoding for constrained / BLE transport.
    /// Layout: [kind:1][amount:4 BE][refLen:1][ref:n][noteLen:1][note:m]
    /// Stays comfortably under the ~100-byte constrained budget.
    static func pack(_ intent: LocalIntent) -> Data {
        var data = Data()
        data.append(intent.kind.rawValue)
        var amount = intent.amount.bigEndian
        withUnsafeBytes(of: &amount) { data.append(contentsOf: $0) }
        let ref = Data(intent.reference.utf8.prefix(40))
        data.append(UInt8(ref.count))
        data.append(ref)
        let note = Data(intent.note.utf8.prefix(48))
        data.append(UInt8(note.count))
        data.append(note)
        return data
    }

    /// Hex string form for raw constrained-link transmission (< 100 bytes).
    static func hexPayload(_ intent: LocalIntent) -> String {
        pack(intent).map { String(format: "%02x", $0) }.joined()
    }

    /// Reverse of `pack` — used by a receiving peer to rebuild the intent.
    static func unpack(_ data: Data) -> (kind: LocalIntent.Kind, amount: UInt32, reference: String, note: String)? {
        var i = data.startIndex
        guard data.count >= 6, let kind = LocalIntent.Kind(rawValue: data[i]) else { return nil }
        i += 1
        let amount = data[i..<i+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        i += 4
        let refLen = Int(data[i]); i += 1
        guard data.count >= i + refLen + 1 else { return nil }
        let ref = String(decoding: data[i..<i+refLen], as: UTF8.self); i += refLen
        let noteLen = Int(data[i]); i += 1
        guard data.count >= i + noteLen else { return nil }
        let note = String(decoding: data[i..<i+noteLen], as: UTF8.self)
        return (kind, amount, ref, note)
    }

    /// How many BLE chunks this intent needs at the given chunk budget.
    static func chunkCount(_ intent: LocalIntent, chunkSize: Int = 20) -> Int {
        max(1, Int(ceil(Double(pack(intent).count) / Double(chunkSize))))
    }
}

/// Strict exponential back-off for constrained sessions — preserves
/// battery and conserves the limited path. Capped so it never stalls.
struct BackoffController {
    private(set) var attempt = 0
    let base: TimeInterval
    let cap: TimeInterval

    init(base: TimeInterval = 1.5, cap: TimeInterval = 120) {
        self.base = base
        self.cap = cap
    }

    mutating func nextDelay() -> TimeInterval {
        let delay = min(cap, base * pow(2, Double(attempt)))
        attempt += 1
        // A little jitter so multiple devices don't sync their retries.
        return delay + Double.random(in: 0...0.4)
    }

    mutating func reset() { attempt = 0 }
}
