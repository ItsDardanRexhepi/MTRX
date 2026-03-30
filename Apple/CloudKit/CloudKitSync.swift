import CloudKit

/// Encrypted cross-device sync via CloudKit — user preferences, Trinity memory backup (user-initiated only)
@MainActor
final class CloudKitSync: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?

    private let container = CKContainer(identifier: "iCloud.com.opnmatrx.mtrx")
    private lazy var privateDB = container.privateCloudDatabase

    // MARK: - Save encrypted data
    func saveEncrypted(key: String, data: Data) async throws {
        isSyncing = true
        defer { isSyncing = false }
        let recordID = CKRecord.ID(recordName: key)
        let record = CKRecord(recordType: "EncryptedSync", recordID: recordID)
        record.encryptedValues["payload"] = data as NSData
        record["updatedAt"] = Date() as NSDate
        try await privateDB.save(record)
        lastSyncDate = Date()
    }

    // MARK: - Fetch encrypted data
    func fetchEncrypted(key: String) async throws -> Data? {
        let recordID = CKRecord.ID(recordName: key)
        let record = try await privateDB.record(for: recordID)
        return record.encryptedValues["payload"] as? Data
    }

    // MARK: - Sync user preferences
    func syncPreferences(_ preferences: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: preferences)
        try await saveEncrypted(key: "user_preferences", data: data)
    }

    func fetchPreferences() async throws -> [String: Any]? {
        guard let data = try await fetchEncrypted(key: "user_preferences") else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Trinity memory backup (user-initiated only)
    func backupTrinityMemory(_ memoryData: Data) async throws {
        try await saveEncrypted(key: "trinity_memory_backup", data: memoryData)
    }

    func restoreTrinityMemory() async throws -> Data? {
        try await fetchEncrypted(key: "trinity_memory_backup")
    }

    // MARK: - Delete all synced data
    func deleteAllSyncedData() async throws {
        let query = CKQuery(recordType: "EncryptedSync", predicate: NSPredicate(value: true))
        let results = try await privateDB.records(matching: query)
        for (id, _) in results.matchResults {
            try await privateDB.deleteRecord(withID: id)
        }
    }
}
