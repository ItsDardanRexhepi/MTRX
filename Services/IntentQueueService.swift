// IntentQueueService.swift
// MTRX — Offline Intelligence Architecture, Component 1
//
// Persistent, crash-safe queue for PendingIntent. All mutations are
// actor-isolated, so every status transition is atomic in-process:
// fetch → guard → mutate → save happens as one uninterruptible unit
// from the perspective of every other caller.
//
// Dispatch idempotency: an intent can begin dispatch exactly once per
// attempt. `beginDispatch` succeeds only from `queued`, flipping the
// row to `executing` and stamping the attempt under the same actor
// turn. A second drain racing the first sees `executing` and gets nil.
// The envelope's one-time nonce gives the gateway its own replay
// rejection on top of this local guard.

import Foundation
import SwiftData

// MARK: - Errors

enum IntentQueueError: Error, LocalizedError {
    case intentNotFound(UUID)
    case illegalTransition(from: PendingIntentStatus, to: PendingIntentStatus)
    case storeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .intentNotFound(let id):
            return "No pending intent with id \(id.uuidString)."
        case .illegalTransition(let from, let to):
            return "Illegal intent transition \(from.rawValue) → \(to.rawValue)."
        case .storeUnavailable(let detail):
            return "Intent store unavailable: \(detail)"
        }
    }
}

// MARK: - Queue Service

actor IntentQueueService {

    // MARK: Shared instance

    static let shared = IntentQueueService()

    // MARK: Store

    private let container: ModelContainer
    private let context: ModelContext

    /// Production store lives in Application Support; tests pass
    /// `inMemory: true` for hermetic runs.
    init(inMemory: Bool = false) {
        do {
            let schema = Schema([PendingIntent.self])
            let configuration: ModelConfiguration
            if inMemory {
                configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            } else {
                let appSupport = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let dir = appSupport.appendingPathComponent("MTRX", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                configuration = ModelConfiguration(
                    schema: schema,
                    url: dir.appendingPathComponent("IntentQueue.store")
                )
            }
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Last resort: in-memory container so capture still works for
            // the session instead of crashing. Intents won't survive
            // relaunch in this degraded mode.
            let schema = Schema([PendingIntent.self])
            // swiftlint:disable:next force_try
            container = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    // MARK: - Enqueue

    /// Insert a new intent. `encryptedPayload` MUST already be sealed by
    /// PayloadCrypto — this service never sees or stores plaintext.
    @discardableResult
    func enqueue(
        intentType: PendingIntentType,
        sensitivity: PendingIntentSensitivity,
        encryptedPayload: Data,
        preparedPlan: String,
        priority: Int = 0,
        expiresAt: Date? = nil
    ) throws -> UUID {
        let intent = PendingIntent(
            intentType: intentType,
            sensitivity: sensitivity,
            encryptedPayload: encryptedPayload,
            preparedPlan: preparedPlan,
            priority: priority,
            expiresAt: expiresAt
        )
        context.insert(intent)
        try context.save()
        return intent.id
    }

    // MARK: - Fetch

    /// All intents ready to dispatch, highest priority first, FIFO within
    /// a priority band. Excludes everything not in `queued`.
    func fetchDispatchable() throws -> [QueuedIntentSnapshot] {
        let queuedRaw = PendingIntentStatus.queued.rawValue
        var descriptor = FetchDescriptor<PendingIntent>(
            predicate: #Predicate { $0.statusRaw == queuedRaw }
        )
        descriptor.sortBy = [
            SortDescriptor(\.priority, order: .reverse),
            SortDescriptor(\.createdAt, order: .forward),
        ]
        return try context.fetch(descriptor).map(QueuedIntentSnapshot.init)
    }

    /// Every non-terminal intent (for the queue UI).
    func fetchActive() throws -> [QueuedIntentSnapshot] {
        let terminal = PendingIntentStatus.allCases.filter(\.isTerminal).map(\.rawValue)
        var descriptor = FetchDescriptor<PendingIntent>(
            predicate: #Predicate { !terminal.contains($0.statusRaw) }
        )
        descriptor.sortBy = [
            SortDescriptor(\.priority, order: .reverse),
            SortDescriptor(\.createdAt, order: .forward),
        ]
        return try context.fetch(descriptor).map(QueuedIntentSnapshot.init)
    }

    func snapshot(id: UUID) throws -> QueuedIntentSnapshot {
        QueuedIntentSnapshot(try fetch(id))
    }

    // MARK: - Atomic transitions

    /// Legal lifecycle moves. Anything else throws `illegalTransition`.
    private static let legalTransitions: [PendingIntentStatus: Set<PendingIntentStatus>] = [
        .queued: [.executing, .awaitingConfirmation, .expired, .cancelled],
        .awaitingConfirmation: [.queued, .cancelled, .expired],
        .executing: [.completed, .failed],
        .failed: [.queued, .cancelled, .expired],
        .completed: [],
        .expired: [],
        .cancelled: [],
    ]

    /// Validated state transition. Atomic: guard + mutate + save under one
    /// actor turn.
    func transition(_ id: UUID, to newStatus: PendingIntentStatus) throws {
        let intent = try fetch(id)
        guard Self.legalTransitions[intent.status, default: []].contains(newStatus) else {
            throw IntentQueueError.illegalTransition(from: intent.status, to: newStatus)
        }
        intent.status = newStatus
        try context.save()
    }

    // MARK: - Dispatch idempotency guard

    /// Claim an intent for dispatch. Returns the sealed envelope ONLY if
    /// the intent is still `queued` and unexpired; flips it to `executing`
    /// and stamps the attempt in the same atomic unit. A concurrent drain
    /// calling this for the same id receives nil — exactly one dispatch.
    func beginDispatch(_ id: UUID) throws -> DispatchClaim? {
        let intent = try fetch(id)

        guard intent.status == .queued else { return nil }
        if intent.isExpired() {
            intent.status = .expired
            try context.save()
            return nil
        }

        intent.status = .executing
        intent.attemptCount += 1
        intent.lastAttemptAt = Date()
        try context.save()

        return DispatchClaim(
            id: intent.id,
            nonce: intent.nonce,
            encryptedPayload: intent.encryptedPayload,
            attemptNumber: intent.attemptCount
        )
    }

    /// Record a successful gateway dispatch.
    func completeDispatch(_ id: UUID, result: Data?) throws {
        let intent = try fetch(id)
        guard intent.status == .executing else {
            throw IntentQueueError.illegalTransition(from: intent.status, to: .completed)
        }
        intent.status = .completed
        intent.resultPayload = result
        try context.save()
    }

    /// Record a failed attempt. `requeue: true` puts it back in line for
    /// the next drain; `false` parks it as failed for manual retry.
    func failDispatch(_ id: UUID, requeue: Bool, detail: Data? = nil) throws {
        let intent = try fetch(id)
        guard intent.status == .executing else {
            throw IntentQueueError.illegalTransition(from: intent.status, to: .failed)
        }
        intent.status = .failed
        intent.resultPayload = detail
        if requeue, !intent.isExpired() {
            intent.status = .queued
        }
        try context.save()
    }

    // MARK: - Relay audit

    /// Append a hop record to the intent's relay audit trail.
    func recordHop(_ id: UUID, transport: String, outcome: String, detail: String? = nil) throws {
        let intent = try fetch(id)
        var hops = (try? JSONDecoder().decode([RelayHopRecord].self, from: intent.hopHistory)) ?? []
        hops.append(RelayHopRecord(timestamp: Date(), transport: transport, outcome: outcome, detail: detail))
        intent.hopHistory = (try? JSONEncoder().encode(hops)) ?? intent.hopHistory
        try context.save()
    }

    // MARK: - Expiry sweep

    /// Expire every overdue, non-terminal intent. Returns the ids that
    /// expired in this sweep so the caller can notify the user — expired
    /// intents never die silently.
    @discardableResult
    func sweepExpired(asOf date: Date = Date()) throws -> [UUID] {
        let terminal = PendingIntentStatus.allCases.filter(\.isTerminal).map(\.rawValue)
        let descriptor = FetchDescriptor<PendingIntent>(
            predicate: #Predicate { !terminal.contains($0.statusRaw) }
        )
        let candidates = try context.fetch(descriptor)
        var expired: [UUID] = []
        for intent in candidates where intent.isExpired(asOf: date) {
            intent.status = .expired
            expired.append(intent.id)
        }
        if !expired.isEmpty { try context.save() }
        return expired
    }

    // MARK: - Cancellation

    func cancel(_ id: UUID) throws {
        try transition(id, to: .cancelled)
    }

    // MARK: - Private

    private func fetch(_ id: UUID) throws -> PendingIntent {
        var descriptor = FetchDescriptor<PendingIntent>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let intent = try context.fetch(descriptor).first else {
            throw IntentQueueError.intentNotFound(id)
        }
        return intent
    }
}

// MARK: - Value Snapshots
//
// SwiftData @Model instances are not Sendable; everything that crosses
// the actor boundary is copied into these plain value types.

/// Read-only view of a queued intent, safe to pass across actors/views.
struct QueuedIntentSnapshot: Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let intentType: PendingIntentType
    let sensitivity: PendingIntentSensitivity
    let status: PendingIntentStatus
    let preparedPlan: String
    let priority: Int
    let expiresAt: Date?
    let attemptCount: Int
    let lastAttemptAt: Date?

    init(_ intent: PendingIntent) {
        id = intent.id
        createdAt = intent.createdAt
        intentType = intent.intentType
        sensitivity = intent.sensitivity
        status = intent.status
        preparedPlan = intent.preparedPlan
        priority = intent.priority
        expiresAt = intent.expiresAt
        attemptCount = intent.attemptCount
        lastAttemptAt = intent.lastAttemptAt
    }
}

/// Exactly-once dispatch ticket handed to the BridgeExecutor.
struct DispatchClaim: Sendable {
    let id: UUID
    let nonce: UUID
    let encryptedPayload: Data
    let attemptNumber: Int
}
