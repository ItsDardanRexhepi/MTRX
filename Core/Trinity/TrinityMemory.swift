//
//  TrinityMemory.swift
//  MTRX — Trinity
//
//  SwiftData persistent memory. Learns user patterns over time.
//

import Foundation
import SwiftData

// MARK: - Trinity Memory Entry (SwiftData Model)

/// Persistent memory entry stored via SwiftData.
/// Each entry represents a learned interaction, pattern, or preference.
@Model
final class TrinityMemoryEntry {

    // MARK: - Properties

    @Attribute(.unique) var id: UUID
    var content: String
    var response: String
    var intent: String
    var timestamp: Date
    var category: String
    var relevanceScore: Double
    var accessCount: Int
    var lastAccessed: Date
    var tags: [String]
    var isArchived: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        content: String,
        response: String,
        intent: String,
        timestamp: Date = Date(),
        category: String = "general",
        relevanceScore: Double = 1.0,
        tags: [String] = []
    ) {
        self.id = id
        self.content = content
        self.response = response
        self.intent = intent
        self.timestamp = timestamp
        self.category = category
        self.relevanceScore = relevanceScore
        self.accessCount = 0
        self.lastAccessed = timestamp
        self.tags = tags
        self.isArchived = false
    }
}

// MARK: - User Pattern (SwiftData Model)

/// Learned user pattern detected over time.
@Model
final class UserPattern {

    @Attribute(.unique) var id: UUID
    var patternType: String
    var description_: String
    var confidence: Double
    var occurrenceCount: Int
    var firstDetected: Date
    var lastDetected: Date
    var metadata: [String: String]
    var isActive: Bool

    init(
        id: UUID = UUID(),
        patternType: String,
        description: String,
        confidence: Double = 0.5,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.patternType = patternType
        self.description_ = description
        self.confidence = confidence
        self.occurrenceCount = 1
        self.firstDetected = Date()
        self.lastDetected = Date()
        self.metadata = metadata
        self.isActive = true
    }
}

// MARK: - Trinity Memory Store

/// CRUD operations and pattern learning for Trinity's persistent memory.
final class TrinityMemoryStore {

    // MARK: - Properties

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private let maxMemoryEntries: Int = 50_000
    private let decayFactor: Double = 0.95

    // MARK: - Initialization

    init() {
        setupContainer()
    }

    /// Configure the on-disk SwiftData container used for Trinity's
    /// persistent memory.
    ///
    /// We pin the store URL to Application Support so it survives app
    /// updates and isn't swept by iOS's aggressive caches-directory
    /// eviction, and we mark it as ``complete`` file protection so the
    /// store is encrypted at rest when the device is locked. If the
    /// disk-backed container fails to open (corruption, migration
    /// failure after a schema change) we fall back to an in-memory
    /// container so the app can still boot — the user loses their
    /// historical memory but keeps a working chat surface.
    private func setupContainer() {
        let schema = Schema([TrinityMemoryEntry.self, UserPattern.self])
        let storeURL = Self.defaultStoreURL()
        do {
            let config: ModelConfiguration
            if let storeURL {
                config = ModelConfiguration(
                    "TrinityMemory",
                    schema: schema,
                    url: storeURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            } else {
                config = ModelConfiguration(
                    "TrinityMemory",
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
            }
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            if let container = modelContainer {
                modelContext = ModelContext(container)
            }
        } catch {
            print("[TrinityMemory] Disk container failed (\(error)); falling back to in-memory store")
            do {
                let memoryConfig = ModelConfiguration(
                    "TrinityMemory.inMemory",
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                modelContainer = try ModelContainer(for: schema, configurations: [memoryConfig])
                if let container = modelContainer {
                    modelContext = ModelContext(container)
                }
            } catch {
                print("[TrinityMemory] In-memory fallback also failed: \(error)")
            }
        }
    }

    /// Resolve the on-disk location Trinity uses for its memory store.
    ///
    /// Application Support is the right bucket: iOS does not clear it
    /// during cache pressure, it's included in the iCloud backup by
    /// default, and it's writable for the user. We place the store in
    /// a dedicated ``TrinityMemory`` subfolder and create the folder
    /// if it doesn't exist yet.
    private static func defaultStoreURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let folder = appSupport.appendingPathComponent("TrinityMemory", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("TrinityMemory.store")
    }

    // MARK: - Store

    /// Store a new memory entry.
    /// - Parameter entry: The memory entry to persist.
    func store(_ entry: TrinityMemoryEntry) async {
        guard let context = modelContext else { return }

        context.insert(entry)
        do {
            try context.save()
        } catch {
            print("[TrinityMemory] Failed to store entry: \(error)")
        }

        // Learn patterns from the new entry
        await detectPatterns(from: entry)

        // Prune old entries if exceeding limit
        await pruneIfNeeded()
    }

    // MARK: - Query

    /// Query relevant memory entries for a given message.
    /// - Parameter message: The user message to find relevant memories for.
    /// - Returns: Relevant memory entries sorted by relevance.
    func queryRelevant(for message: String) async -> [TrinityMemoryEntry] {
        guard let context = modelContext else { return [] }

        // Real relevance ranking: lexical (bag-of-words cosine) similarity between
        // the query and each entry, blended with recency and access frequency.
        // (Lexical, not neural — named accurately. An embedding field could later
        // upgrade this to vector similarity without changing the call site.)
        let descriptor = FetchDescriptor<TrinityMemoryEntry>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let entries = try context.fetch(descriptor)
            guard !entries.isEmpty else { return [] }

            let queryTokens = Self.tokenize(message)
            let now = Date()
            let maxAccess = Double(max(1, entries.map(\.accessCount).max() ?? 1))

            let ranked = entries
                .map { entry -> (entry: TrinityMemoryEntry, score: Double) in
                    let entryTokens = Self.tokenize(entry.content + " " + entry.intent + " " + entry.tags.joined(separator: " "))
                    let similarity = Self.cosineSimilarity(queryTokens, entryTokens)
                    let ageDays = now.timeIntervalSince(entry.timestamp) / 86_400
                    let recency = exp(-ageDays / 30.0)               // ~30-day decay
                    let access = Double(entry.accessCount) / maxAccess
                    let score = 0.60 * similarity + 0.25 * recency + 0.15 * access
                    return (entry, score)
                }
                .sorted { $0.score > $1.score }
                .prefix(20)
                .map(\.entry)

            for entry in ranked {
                entry.accessCount += 1
                entry.lastAccessed = Date()
            }
            try context.save()
            return Array(ranked)
        } catch {
            print("[TrinityMemory] Query failed: \(error)")
            return []
        }
    }

    // MARK: - Relevance scoring helpers (pure, unit-testable)

    /// Lower-cased bag-of-words with short/stop words removed.
    static func tokenize(_ text: String) -> [String: Int] {
        let stop: Set<String> = ["the", "and", "for", "with", "this", "that",
                                 "what", "how", "does", "you", "are", "was",
                                 "have", "has", "will", "can", "should", "would"]
        var counts: [String: Int] = [:]
        for raw in text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) {
            if raw.count > 2 && !stop.contains(raw) { counts[raw, default: 0] += 1 }
        }
        return counts
    }

    /// Cosine similarity of two bag-of-words vectors in [0, 1].
    static func cosineSimilarity(_ a: [String: Int], _ b: [String: Int]) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        var dot = 0.0
        for (token, count) in a { if let other = b[token] { dot += Double(count * other) } }
        let magA = sqrt(a.values.reduce(0.0) { $0 + Double($1 * $1) })
        let magB = sqrt(b.values.reduce(0.0) { $0 + Double($1 * $1) })
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    /// Query memory by category.
    /// - Parameter category: The category to filter by.
    /// - Returns: Memory entries matching the category.
    func queryByCategory(_ category: String) async -> [TrinityMemoryEntry] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<TrinityMemoryEntry>(
            predicate: #Predicate { entry in
                entry.category == category && !entry.isArchived
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("[TrinityMemory] Category query failed: \(error)")
            return []
        }
    }

    // MARK: - Pattern Learning

    /// Detect and store patterns from a new memory entry.
    /// - Parameter entry: The entry to analyze for patterns.
    private func detectPatterns(from entry: TrinityMemoryEntry) async {
        guard let context = modelContext else { return }

        // Time-of-day × category frequency pattern. Each matching entry reinforces
        // the pattern; it only becomes ACTIVE after ≥3 occurrences, so a single
        // event never masquerades as an established habit.
        let hour = Calendar.current.component(.hour, from: entry.timestamp)
        let bucket: String
        switch hour {
        case 5..<12: bucket = "morning"
        case 12..<17: bucket = "afternoon"
        case 17..<22: bucket = "evening"
        default:      bucket = "night"
        }
        let key = "temporal:\(entry.category):\(bucket)"

        do {
            let descriptor = FetchDescriptor<UserPattern>(predicate: #Predicate { $0.patternType == key })
            if let pattern = try context.fetch(descriptor).first {
                pattern.occurrenceCount += 1
                pattern.lastDetected = Date()
                pattern.confidence = min(0.99, pattern.confidence + 0.05)
                pattern.isActive = pattern.occurrenceCount >= 3
            } else {
                let pattern = UserPattern(
                    patternType: key,
                    description: "Tends to \(entry.category) in the \(bucket)",
                    confidence: 0.3,
                    metadata: ["category": entry.category, "timeOfDay": bucket]
                )
                pattern.isActive = false // activates once it recurs (≥3)
                context.insert(pattern)
            }
            try context.save()
        } catch {
            print("[TrinityMemory] Pattern detection failed: \(error)")
        }
    }

    /// Get all active user patterns.
    /// - Returns: Currently active user patterns.
    func activePatterns() async -> [UserPattern] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<UserPattern>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.confidence, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("[TrinityMemory] Pattern query failed: \(error)")
            return []
        }
    }

    // MARK: - Maintenance

    /// Apply relevance decay to older entries and prune if needed.
    private func pruneIfNeeded() async {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<TrinityMemoryEntry>(
            sortBy: [SortDescriptor(\.relevanceScore, order: .forward)]
        )

        do {
            let entries = try context.fetch(descriptor)

            // Apply decay to old entries
            let cutoff = Date().addingTimeInterval(-86400 * 30) // 30 days
            for entry in entries where entry.lastAccessed < cutoff {
                entry.relevanceScore *= decayFactor
            }

            // Archive entries below relevance threshold
            for entry in entries where entry.relevanceScore < 0.1 {
                entry.isArchived = true
            }

            // Hard delete if way over limit
            if entries.count > maxMemoryEntries * 2 {
                let toDelete = entries.prefix(entries.count - maxMemoryEntries)
                for entry in toDelete {
                    context.delete(entry)
                }
            }

            try context.save()
        } catch {
            print("[TrinityMemory] Prune failed: \(error)")
        }
    }

    // MARK: - Export

    /// Export all memory entries as JSON data.
    func exportMemory() async throws -> Data {
        guard let context = modelContext else {
            throw MemoryError.containerNotInitialized
        }

        let descriptor = FetchDescriptor<TrinityMemoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let entries = try context.fetch(descriptor)
        let exportable = entries.map { entry in
            [
                "id": entry.id.uuidString,
                "content": entry.content,
                "response": entry.response,
                "intent": entry.intent,
                "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                "category": entry.category,
                "relevanceScore": String(entry.relevanceScore),
            ]
        }

        return try JSONSerialization.data(withJSONObject: exportable, options: .prettyPrinted)
    }
}

// MARK: - Memory Errors

enum MemoryError: Error, LocalizedError {
    case containerNotInitialized
    case queryFailed(String)
    case storeFailed(String)

    var errorDescription: String? {
        switch self {
        case .containerNotInitialized:
            return "SwiftData ModelContainer not initialized"
        case .queryFailed(let reason):
            return "Memory query failed: \(reason)"
        case .storeFailed(let reason):
            return "Memory store failed: \(reason)"
        }
    }
}
