//
//  DecisionLog.swift
//  MTRX — Omniversal
//
//  Append-only audit trail for all decisions processed through the scoring pipeline.
//

import Foundation

// MARK: - Decision Entry

/// A single entry in the decision audit log.
struct DecisionEntry: Identifiable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let requestDescription: String
    let outcome: String
    let compositeScore: Double
    let gateScores: [String: Double]
    let failedGates: [String]
    let timeSensitivity: String
    let context: [String: String]
    let source: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        requestDescription: String,
        outcome: String,
        compositeScore: Double,
        gateScores: [String: Double],
        failedGates: [String] = [],
        timeSensitivity: String = "medium",
        context: [String: String] = [:],
        source: String = "engine"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.requestDescription = requestDescription
        self.outcome = outcome
        self.compositeScore = compositeScore
        self.gateScores = gateScores
        self.failedGates = failedGates
        self.timeSensitivity = timeSensitivity
        self.context = context
        self.source = source
    }
}

// MARK: - Decision Log (Actor-Isolated)

/// Actor-isolated, append-only audit trail for all decisions.
/// Once written, entries cannot be modified or deleted, ensuring full traceability.
actor DecisionLog {

    // MARK: - Storage

    private var entries: [DecisionEntry] = []
    private let storageURL: URL
    private let maxEntriesInMemory: Int

    // MARK: - Initialization

    init(storageDirectory: URL? = nil, maxEntriesInMemory: Int = 10_000) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = storageDirectory ?? appSupport.appendingPathComponent("MTRX/DecisionLog")

        self.storageURL = directory.appendingPathComponent("decision_log.json")
        self.maxEntriesInMemory = maxEntriesInMemory

        // TODO: Load existing entries from disk on init
    }

    // MARK: - Append-Only Operations

    /// Log a new decision entry. This is append-only; entries cannot be modified.
    /// - Parameter entry: The decision entry to log.
    func log(_ entry: DecisionEntry) {
        entries.append(entry)

        // Persist to disk asynchronously
        Task {
            await persistEntry(entry)
        }

        // Evict oldest in-memory entries if exceeding limit
        if entries.count > maxEntriesInMemory {
            let overflow = entries.count - maxEntriesInMemory
            entries.removeFirst(overflow)
        }
    }

    /// Log a decision from a gate score and outcome.
    /// - Parameters:
    ///   - request: The original decision request.
    ///   - gateScore: The composite gate score.
    ///   - outcome: The determined outcome.
    func log(request: DecisionRequest, gateScore: GateScore, outcome: Outcome) {
        var gateScores: [String: Double] = [:]
        for (gate, evaluation) in gateScore.evaluations {
            gateScores[gate.displayName] = evaluation.score
        }

        let entry = DecisionEntry(
            requestDescription: request.description,
            outcome: outcome.displayName,
            compositeScore: gateScore.compositeScore,
            gateScores: gateScores,
            failedGates: gateScore.failedGates.map { $0.displayName },
            timeSensitivity: request.timeSensitivity.displayName,
            source: request.source
        )

        log(entry)
    }

    // MARK: - Query Operations

    /// Query the decision log history with optional filters.
    /// - Parameters:
    ///   - startDate: Optional start date filter.
    ///   - endDate: Optional end date filter.
    ///   - outcomeFilter: Optional outcome type filter.
    ///   - limit: Maximum number of entries to return.
    /// - Returns: Matching decision entries, most recent first.
    func queryHistory(
        startDate: Date? = nil,
        endDate: Date? = nil,
        outcomeFilter: String? = nil,
        limit: Int = 100
    ) -> [DecisionEntry] {
        var filtered = entries

        if let start = startDate {
            filtered = filtered.filter { $0.timestamp >= start }
        }
        if let end = endDate {
            filtered = filtered.filter { $0.timestamp <= end }
        }
        if let outcome = outcomeFilter {
            filtered = filtered.filter { $0.outcome == outcome }
        }

        return Array(filtered.suffix(limit).reversed())
    }

    /// Query entries that failed specific gates.
    /// - Parameter gateName: The gate display name to filter by.
    /// - Returns: Entries where the specified gate failed.
    func queryFailures(for gateName: String) -> [DecisionEntry] {
        entries.filter { $0.failedGates.contains(gateName) }
    }

    /// Returns the total number of logged decisions.
    var entryCount: Int {
        entries.count
    }

    /// Returns summary statistics for the decision log.
    func statistics() -> DecisionLogStatistics {
        let outcomeDistribution = Dictionary(grouping: entries, by: { $0.outcome })
            .mapValues { $0.count }

        let averageScore = entries.isEmpty ? 0.0 :
            entries.reduce(0.0) { $0 + $1.compositeScore } / Double(entries.count)

        return DecisionLogStatistics(
            totalDecisions: entries.count,
            outcomeDistribution: outcomeDistribution,
            averageCompositeScore: averageScore,
            earliestEntry: entries.first?.timestamp,
            latestEntry: entries.last?.timestamp
        )
    }

    // MARK: - Export

    /// Export the decision log to JSON data.
    /// - Parameter dateRange: Optional date range filter.
    /// - Returns: JSON-encoded data of the log entries.
    func export(dateRange: ClosedRange<Date>? = nil) throws -> Data {
        var entriesToExport = entries
        if let range = dateRange {
            entriesToExport = entries.filter { range.contains($0.timestamp) }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entriesToExport)
    }

    /// Export to a file at the specified URL.
    /// - Parameter url: Destination file URL.
    func exportToFile(at url: URL) throws {
        let data = try export()
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Persistence (Private)

    private func persistEntry(_ entry: DecisionEntry) async {
        // TODO: Implement incremental append to disk storage
        // Should use append-mode file writing for efficiency
        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)

            // TODO: Use file handle for true append-mode writing
            if FileManager.default.fileExists(atPath: storageURL.path) {
                let handle = try FileHandle(forWritingTo: storageURL)
                handle.seekToEndOfFile()
                handle.write(",\n".data(using: .utf8)!)
                handle.write(data)
                handle.closeFile()
            } else {
                try data.write(to: storageURL, options: .atomic)
            }
        } catch {
            // TODO: Handle persistence failures — queue for retry
            print("[DecisionLog] Persistence error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Decision Log Statistics

/// Summary statistics for the decision log.
struct DecisionLogStatistics: Sendable {
    let totalDecisions: Int
    let outcomeDistribution: [String: Int]
    let averageCompositeScore: Double
    let earliestEntry: Date?
    let latestEntry: Date?
}
