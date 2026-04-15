//
//  SwiftDataStore.swift
//  MTRX
//
//  Local persistence manager — single source of truth for on-device SwiftData
//  containers, migrations, and background-context coordination.
//

import Foundation
import SwiftData

// MARK: - Store Configuration

/// Defines which SwiftData schema version is current and how to migrate.
enum StoreSchemaVersion: Int, CaseIterable {
    case v1 = 1
    case v2 = 2

    static var current: StoreSchemaVersion { .v2 }
}

// MARK: - SwiftData Store

/// Centralized local persistence manager.
///
/// Owns the `ModelContainer` and vends contexts for reads, writes, and
/// background operations. All SwiftData access in the app flows through
/// this singleton so schema changes, migrations, and error handling are
/// consistent.
@MainActor
final class SwiftDataStore: ObservableObject {

    // MARK: - Shared Instance

    static let shared = SwiftDataStore()

    // MARK: - Published State

    @Published private(set) var isReady = false
    @Published private(set) var lastError: String?
    @Published private(set) var recordCounts: RecordCounts = .zero

    // MARK: - Container

    private(set) var container: ModelContainer?

    /// All model types managed by this store.
    private static let managedModels: [any PersistentModel.Type] = [
        UserProfile.self,
        TransactionRecord.self,
        ContractRecord.self,
        TrinityMemoryRecord.self
    ]

    // MARK: - Initialization

    private init() {
        setupContainer()
    }

    /// Creates the ModelContainer with the app group store URL and current
    /// schema version.
    private func setupContainer() {
        do {
            let schema = Schema(Self.managedModels)

            let config = ModelConfiguration(
                "MTRX",
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier("group.com.opnmatrx.mtrx")
            )

            container = try ModelContainer(for: schema, configurations: [config])
            isReady = true
            lastError = nil

            Task { await refreshCounts() }
        } catch {
            isReady = false
            lastError = error.localizedDescription
        }
    }

    // MARK: - Context Access

    /// Returns the main-actor context for UI-driven reads and writes.
    var mainContext: ModelContext? {
        container?.mainContext
    }

    /// Creates a detached background context for bulk imports or expensive
    /// queries that should not block the main actor.
    func backgroundContext() -> ModelContext? {
        guard let container else { return nil }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    // MARK: - CRUD Helpers

    /// Inserts a model and saves immediately.
    func insert<T: PersistentModel>(_ model: T) throws {
        guard let ctx = mainContext else { throw DataStoreError.notReady }
        ctx.insert(model)
        try ctx.save()
        Task { await refreshCounts() }
    }

    /// Deletes a model and saves immediately.
    func delete<T: PersistentModel>(_ model: T) throws {
        guard let ctx = mainContext else { throw DataStoreError.notReady }
        ctx.delete(model)
        try ctx.save()
        Task { await refreshCounts() }
    }

    /// Fetches models matching a descriptor on the main context.
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        guard let ctx = mainContext else { throw DataStoreError.notReady }
        return try ctx.fetch(descriptor)
    }

    /// Saves any pending changes on the main context.
    func save() throws {
        guard let ctx = mainContext else { throw DataStoreError.notReady }
        try ctx.save()
    }

    // MARK: - Batch Operations

    /// Performs a batch insert on a background context and merges changes.
    func batchInsert<T: PersistentModel>(_ models: [T]) async throws {
        guard let ctx = backgroundContext() else { throw DataStoreError.notReady }
        for model in models {
            ctx.insert(model)
        }
        try ctx.save()
        await refreshCounts()
    }

    /// Deletes all records of a given type.  **Destructive** — intended for
    /// developer tools and account-reset flows only.
    func deleteAll<T: PersistentModel>(ofType type: T.Type) async throws {
        guard let ctx = backgroundContext() else { throw DataStoreError.notReady }
        let descriptor = FetchDescriptor<T>()
        let records = try ctx.fetch(descriptor)
        for record in records {
            ctx.delete(record)
        }
        try ctx.save()
        await refreshCounts()
    }

    // MARK: - Trinity Memory Convenience

    /// Returns the top-N highest-confidence active Trinity memories for
    /// context assembly.
    func trinityContext(limit: Int = 20) throws -> [TrinityMemoryRecord] {
        try fetch(TrinityMemoryRecord.recentContext(limit: limit))
    }

    /// Prunes Trinity memories whose effective confidence has dropped below
    /// their category threshold.
    func pruneTrinityMemories() async throws {
        guard let ctx = backgroundContext() else { throw DataStoreError.notReady }
        let candidates = try ctx.fetch(TrinityMemoryRecord.pruningCandidates())
        for memory in candidates where memory.shouldPrune {
            memory.deactivate()
        }
        try ctx.save()
    }

    // MARK: - Diagnostics

    struct RecordCounts: Equatable {
        var users: Int
        var transactions: Int
        var contracts: Int
        var trinityMemories: Int

        static let zero = RecordCounts(users: 0, transactions: 0, contracts: 0, trinityMemories: 0)

        var total: Int { users + transactions + contracts + trinityMemories }
    }

    /// Refreshes lightweight record counts for diagnostics display.
    func refreshCounts() async {
        guard let ctx = mainContext else { return }
        do {
            let users = try ctx.fetchCount(FetchDescriptor<UserProfile>())
            let txns = try ctx.fetchCount(FetchDescriptor<TransactionRecord>())
            let contracts = try ctx.fetchCount(FetchDescriptor<ContractRecord>())
            let memories = try ctx.fetchCount(FetchDescriptor<TrinityMemoryRecord>())
            recordCounts = RecordCounts(
                users: users,
                transactions: txns,
                contracts: contracts,
                trinityMemories: memories
            )
        } catch {
            // Non-fatal — counts are diagnostic only
        }
    }

    /// Returns approximate on-disk size of the store in bytes.
    func storeSize() -> Int64 {
        guard let url = container?.configurations.first?.url else { return 0 }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    // MARK: - Reset

    /// Destroys all local data. Used during sign-out and account deletion.
    func resetAllData() async throws {
        guard let ctx = backgroundContext() else { throw DataStoreError.notReady }

        let users = try ctx.fetch(FetchDescriptor<UserProfile>())
        users.forEach { ctx.delete($0) }

        let txns = try ctx.fetch(FetchDescriptor<TransactionRecord>())
        txns.forEach { ctx.delete($0) }

        let contracts = try ctx.fetch(FetchDescriptor<ContractRecord>())
        contracts.forEach { ctx.delete($0) }

        let memories = try ctx.fetch(FetchDescriptor<TrinityMemoryRecord>())
        memories.forEach { ctx.delete($0) }

        try ctx.save()
        await refreshCounts()
    }
}

// MARK: - Store Error

enum DataStoreError: LocalizedError {
    case notReady
    case migrationFailed(String)
    case corruptedData

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "The data store has not finished initializing."
        case .migrationFailed(let detail):
            return "Data migration failed: \(detail)"
        case .corruptedData:
            return "The local database appears corrupted. A reset may be required."
        }
    }
}
