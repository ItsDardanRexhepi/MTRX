// PendingIntent.swift
// MTRX — Offline Intelligence Architecture, Component 1
//
// A financial intent captured while offline (or deferred by policy),
// persisted until it can be dispatched to the 0pnMatrx gateway.
//
// Security invariant: `encryptedPayload` is sealed by PayloadCrypto
// BEFORE this model is ever inserted into the store. Plaintext intent
// parameters never touch disk. `preparedPlan` holds Trinity's
// natural-language reasoning snapshot only — never raw parameters,
// addresses, or amounts beyond what the user already saw on screen.

import Foundation
import SwiftData

// MARK: - Enums

/// What kind of action the user asked for.
enum PendingIntentType: String, Codable, Sendable, CaseIterable {
    case transfer
    case swap
    case contractCall
    case attestation
    /// Answered locally, never enqueued. Exists so the capture layer can
    /// classify uniformly before deciding whether a queue entry is needed.
    case informational
}

/// How dangerous it is to execute this intent late.
enum PendingIntentSensitivity: String, Codable, Sendable, CaseIterable {
    /// Execute whenever connectivity returns. Notify on completion.
    case timeInsensitive
    /// Markets move — requires fresh user confirmation if dispatch is
    /// delayed past the policy threshold.
    case priceSensitive
    /// On-chain contract execution — confirm if significantly delayed.
    case contractExecution
}

/// Lifecycle of a queued intent. Terminal states: completed, expired, cancelled.
enum PendingIntentStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case awaitingConfirmation
    case executing
    case completed
    case expired
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .expired, .cancelled: return true
        case .queued, .awaitingConfirmation, .executing, .failed: return false
        }
    }
}

// MARK: - Model

@Model
final class PendingIntent {

    // MARK: Identity

    @Attribute(.unique) var id: UUID
    var createdAt: Date

    /// One-time nonce carried inside the envelope. The gateway rejects
    /// reused nonces (replay protection); the queue uses it together with
    /// the status check as the dispatch idempotency guard.
    var nonce: UUID

    // MARK: Classification
    //
    // Enums are persisted as raw strings so #Predicate filtering stays
    // reliable on iOS 17 SwiftData. Typed accessors are provided below.

    var intentTypeRaw: String
    var sensitivityRaw: String
    var statusRaw: String

    // MARK: Payload

    /// Sealed envelope (PayloadCrypto, Component 5). Never plaintext.
    var encryptedPayload: Data

    /// Trinity's reasoning snapshot at capture time, shown back to the
    /// user when confirming or reviewing the queue.
    var preparedPlan: String

    // MARK: Scheduling

    /// Higher dispatches first. Ties broken by createdAt (oldest first).
    var priority: Int
    var expiresAt: Date?

    // MARK: Dispatch bookkeeping

    var attemptCount: Int
    var lastAttemptAt: Date?

    /// JSON-encoded relay audit trail (which transports were tried, when).
    var hopHistory: Data

    /// Gateway receipt / result payload once completed or failed.
    var resultPayload: Data?

    // MARK: Typed accessors

    var intentType: PendingIntentType {
        get { PendingIntentType(rawValue: intentTypeRaw) ?? .informational }
        set { intentTypeRaw = newValue.rawValue }
    }

    var sensitivity: PendingIntentSensitivity {
        get { PendingIntentSensitivity(rawValue: sensitivityRaw) ?? .timeInsensitive }
        set { sensitivityRaw = newValue.rawValue }
    }

    var status: PendingIntentStatus {
        get { PendingIntentStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    /// Whether the intent has outlived its expiry window.
    func isExpired(asOf date: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return date > expiresAt && !status.isTerminal
    }

    // MARK: Init

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        intentType: PendingIntentType,
        sensitivity: PendingIntentSensitivity,
        encryptedPayload: Data,
        preparedPlan: String,
        priority: Int = 0,
        expiresAt: Date? = nil,
        status: PendingIntentStatus = .queued,
        nonce: UUID = UUID()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.nonce = nonce
        self.intentTypeRaw = intentType.rawValue
        self.sensitivityRaw = sensitivity.rawValue
        self.statusRaw = status.rawValue
        self.encryptedPayload = encryptedPayload
        self.preparedPlan = preparedPlan
        self.priority = priority
        self.expiresAt = expiresAt
        self.attemptCount = 0
        self.lastAttemptAt = nil
        self.hopHistory = Data("[]".utf8)
        self.resultPayload = nil
    }
}

// MARK: - Relay Hop Record

/// One entry in `hopHistory` — a dispatch attempt through a transport.
/// Stored JSON-encoded so the audit survives even if transports change.
struct RelayHopRecord: Codable, Sendable {
    let timestamp: Date
    /// Transport identifier, e.g. "direct_gateway", "find_my".
    let transport: String
    /// "dispatched", "failed", "unavailable"
    let outcome: String
    let detail: String?
}
