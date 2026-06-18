//
//  MetricsCollector.swift
//  MTRX — Diagnostics
//
//  Subscribes to MetricKit and persists real performance + crash/hang
//  diagnostic payloads LOCALLY, mirroring CrashReporter's privacy-first,
//  server-less design. There is NO upload here — payloads are written to
//  Caches/MTRXDiagnostics/ as JSON and an optional uploader hook is left
//  pluggable for a future opt-in, exactly like CrashReporter.
//
//  Honesty note: this is infrastructure, not UI, and it fabricates nothing.
//  iOS delivers MXMetricPayload/MXDiagnosticPayload at most about once per
//  day, and only on a real device (never the Simulator), so there is no
//  instant test signal — files appear when the OS actually delivers them.
//

import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

// MARK: - Local sink

/// Adopters receive the raw JSON of a delivered payload. The default writes it
/// to disk; a gateway sink could be plugged in later if the user opts in.
public protocol DiagnosticsSink: Sendable {
    func store(_ json: Data, kind: String, timestamp: Date)
}

/// Default sink: timestamped JSON files under Caches/MTRXDiagnostics/.
public struct LocalDiagnosticsSink: DiagnosticsSink {
    public init() {}

    /// Keep at most this many diagnostic files so the directory can't grow
    /// unbounded (there is no upload that would otherwise drain it).
    static let retentionCap = 30

    public func store(_ json: Data, kind: String, timestamp: Date) {
        guard let dir = Self.directory() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(Self.stamp(timestamp))-\(kind).json"
        try? json.write(to: dir.appendingPathComponent(name), options: .atomic)
        Self.pruneOldest(in: dir, keeping: Self.retentionCap)
    }

    /// Delete the oldest JSON files beyond `keeping` (timestamped names sort
    /// chronologically, so lexicographic order is chronological order).
    static func pruneOldest(in dir: URL, keeping: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let jsons = files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard jsons.count > keeping else { return }
        for url in jsons.prefix(jsons.count - keeping) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func directory() -> URL? {
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return caches.appendingPathComponent("MTRXDiagnostics", isDirectory: true)
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}

// MARK: - Collector

/// Process-global MetricKit subscriber. Register once at launch via
/// `MetricsCollector.shared.install()` (AppDelegate.didFinishLaunching).
public final class MetricsCollector: NSObject, @unchecked Sendable {

    public static let shared = MetricsCollector()

    private let lock = NSLock()
    private var installed = false
    private var sink: DiagnosticsSink = LocalDiagnosticsSink()

    private override init() { super.init() }

    /// Subscribe to MetricKit. Safe to call multiple times — only the first
    /// call takes effect. Pass a custom sink to redirect storage (e.g. a future
    /// opt-in uploader); the default keeps everything local.
    public func install(sink: DiagnosticsSink? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard !installed else { return }   // only the first call takes effect
        if let sink { self.sink = sink }
        installed = true
#if canImport(MetricKit)
        // MXMetricManager exists on the Simulator but never delivers payloads;
        // subscribing there is harmless (no fabricated data is produced).
        MXMetricManager.shared.add(self)
#endif
    }

    /// Number of diagnostic files captured so far (for honest in-app inspection
    /// if ever surfaced). Returns 0 when none have been delivered yet.
    public func storedReportCount() -> Int {
        guard let dir = LocalDiagnosticsSink.directory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return 0 }
        return files.filter { $0.pathExtension == "json" }.count
    }

    fileprivate func persist(_ json: Data, kind: String) {
        // MetricKit delivers on a background queue; read `sink` under the same
        // lock that install() writes it with, so a later sink swap can't race.
        lock.lock(); let s = sink; lock.unlock()
        s.store(json, kind: kind, timestamp: Date())
    }
}

#if canImport(MetricKit)
extension MetricsCollector: MXMetricManagerSubscriber {
    /// Periodic performance metrics (battery, launch time, hang rate, memory…).
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            persist(payload.jsonRepresentation(), kind: "metric")
        }
    }

    /// Crash, hang, disk-write, and CPU-exception diagnostics (iOS 14+).
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            persist(payload.jsonRepresentation(), kind: "diagnostic")
        }
    }
}
#endif
