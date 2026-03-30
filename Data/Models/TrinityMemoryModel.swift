//
//  TrinityMemoryModel.swift
//  MTRX
//
//  SwiftData model for Trinity AI learned context and memory persistence.
//

import Foundation
import SwiftData

// MARK: - Memory Category

/// Categories of learned context stored by Trinity.
enum MemoryCategory: String, Codable, CaseIterable {
    case preference   // User preferences inferred from behavior
    case pattern      // Repeated usage patterns detected
    case correction   // User corrections to Trinity responses
    case insight      // Derived insights from aggregated data

    var displayName: String {
        switch self {
        case .preference:  return "Preference"
        case .pattern:     return "Pattern"
        case .correction:  return "Correction"
        case .insight:     return "Insight"
        }
    }

    /// Default confidence score for new memories in this category.
    var defaultConfidence: Double {
        switch self {
        case .preference:  return 0.6
        case .pattern:     return 0.5
        case .correction:  return 0.9
        case .insight:     return 0.4
        }
    }

    /// Minimum confidence threshold below which memories are pruned.
    var pruneThreshold: Double {
        switch self {
        case .preference:  return 0.3
        case .pattern:     return 0.2
        case .correction:  return 0.5
        case .insight:     return 0.2
        }
    }
}

// MARK: - Memory Importance

/// Importance level affecting retention and retrieval priority.
enum MemoryImportance: String, Codable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case critical

    static func < (lhs: MemoryImportance, rhs: MemoryImportance) -> Bool {
        let order: [MemoryImportance] = [.low, .medium, .high, .critical]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

// MARK: - Memory Content

/// Structured memory content with metadata.
struct MemoryContent: Codable, Equatable {
    let summary: String
    let details: String?
    let relatedComponents: [String]
    let tags: [String]
    let sourceContext: String?
}

// MARK: - TrinityMemoryRecord Model

@Model
final class TrinityMemoryRecord {
    // MARK: - Primary Properties

    @Attribute(.unique) var id: UUID
    var category: String
    var importance: String
    var confidence: Double
    var learnedAt: Date
    var lastAccessed: Date
    var accessCount: Int
    var isActive: Bool

    // MARK: - Content

    var contentData: Data

    // MARK: - Decay & Relevance

    var decayRate: Double
    var lastReinforcedAt: Date?
    var reinforcementCount: Int

    // MARK: - Computed Accessors

    var memoryCategory: MemoryCategory {
        get { MemoryCategory(rawValue: category) ?? .insight }
        set { category = newValue.rawValue }
    }

    var memoryImportance: MemoryImportance {
        get { MemoryImportance(rawValue: importance) ?? .medium }
        set { importance = newValue.rawValue }
    }

    var content: MemoryContent? {
        get {
            try? JSONDecoder().decode(MemoryContent.self, from: contentData)
        }
        set {
            contentData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// Current effective confidence after time-based decay.
    var effectiveConfidence: Double {
        let daysSinceAccess = Calendar.current.dateComponents(
            [.day], from: lastAccessed, to: Date()
        ).day ?? 0
        let decay = Double(daysSinceAccess) * decayRate
        return max(0.0, confidence - decay)
    }

    /// Whether this memory should be pruned based on effective confidence.
    var shouldPrune: Bool {
        effectiveConfidence < memoryCategory.pruneThreshold && memoryImportance < .high
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        category: MemoryCategory,
        content: MemoryContent,
        confidence: Double? = nil,
        importance: MemoryImportance = .medium
    ) {
        self.id = id
        self.category = category.rawValue
        self.importance = importance.rawValue
        self.confidence = confidence ?? category.defaultConfidence
        self.learnedAt = Date()
        self.lastAccessed = Date()
        self.accessCount = 0
        self.isActive = true
        self.decayRate = 0.01
        self.reinforcementCount = 0
        self.contentData = (try? JSONEncoder().encode(content)) ?? Data()
    }

    // MARK: - Methods

    /// Records an access event, updating recency and count.
    func recordAccess() {
        lastAccessed = Date()
        accessCount += 1
    }

    /// Reinforces this memory, boosting confidence.
    func reinforce(boost: Double = 0.1) {
        confidence = min(1.0, confidence + boost)
        lastReinforcedAt = Date()
        reinforcementCount += 1
        lastAccessed = Date()
    }

    /// Weakens this memory, reducing confidence.
    func weaken(penalty: Double = 0.15) {
        confidence = max(0.0, confidence - penalty)
    }

    /// Deactivates the memory without deleting it.
    func deactivate() {
        isActive = false
    }

    /// Merges another memory's data into this one when duplicates are detected.
    func merge(with other: TrinityMemoryRecord) {
        confidence = max(confidence, other.confidence)
        accessCount += other.accessCount
        reinforcementCount += other.reinforcementCount
        if other.learnedAt < learnedAt {
            // Preserve the earlier learned date
        }
        lastAccessed = max(lastAccessed, other.lastAccessed)
    }
}

// MARK: - Fetch Descriptors

extension TrinityMemoryRecord {
    /// Fetch active memories of a given category, sorted by confidence.
    static func activeMemories(
        category: MemoryCategory,
        limit: Int = 100
    ) -> FetchDescriptor<TrinityMemoryRecord> {
        let categoryRaw = category.rawValue
        let predicate = #Predicate<TrinityMemoryRecord> { record in
            record.category == categoryRaw && record.isActive
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.confidence, order: .reverse)]
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// Fetch memories that are candidates for pruning.
    static func pruningCandidates() -> FetchDescriptor<TrinityMemoryRecord> {
        let predicate = #Predicate<TrinityMemoryRecord> { record in
            record.isActive && record.confidence < 0.3
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.confidence, order: .forward)]
        return descriptor
    }

    /// Fetch most recently accessed memories for context assembly.
    static func recentContext(limit: Int = 20) -> FetchDescriptor<TrinityMemoryRecord> {
        let predicate = #Predicate<TrinityMemoryRecord> { record in
            record.isActive
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.lastAccessed, order: .reverse)]
        descriptor.fetchLimit = limit
        return descriptor
    }
}
