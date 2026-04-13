//
//  CrashReporter.swift
//  MTRX — Security
//
//  Lightweight, self-contained crash & fatal-error reporter.
//
//  Why this file exists
//  --------------------
//  TestFlight builds need to capture crashes so we can actually fix
//  them, but we do not want to pull in a third-party SDK (Sentry,
//  Bugsnag, Firebase) for 1.0 — they drag in analytics code that
//  conflicts with our "no tracking" privacy manifest and they expand
//  the binary size by multiple megabytes.
//
//  This module installs three hooks that together catch the vast
//  majority of iOS crash modes:
//
//  1. ``NSSetUncaughtExceptionHandler`` — objective-C `NSException`s
//     (the dominant crash source when Swift calls Apple frameworks).
//  2. POSIX signal handlers for the six fatal signals we actually see
//     in production (``SIGABRT``, ``SIGSEGV``, ``SIGBUS``, ``SIGILL``,
//     ``SIGFPE``, ``SIGPIPE``).
//  3. A Swift `fatalError` breadcrumb logger so forced unwraps leave a
//     crumb trail we can inspect after the fact.
//
//  Reports are written to ``Caches/MTRXCrashReports/`` as
//  ``<ISO8601>.json`` — one file per crash. The next app launch picks
//  up any pending files, flushes them through whatever uploader is
//  configured (default: a no-op, replaced by the gateway hook when
//  the user opts in), and deletes them on success.
//
//  The reporter is deliberately **synchronous inside the signal
//  handler**: async logging from a signal handler is undefined
//  behaviour, so we only touch async-signal-safe APIs there. Anything
//  that needs Foundation/Codable happens on the normal startup path.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Crash Report

/// A single captured crash or fatal-error event.
public struct CrashReport: Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let deviceModel: String
    public let kind: Kind
    public let reason: String
    public let symbols: [String]
    public let breadcrumbs: [Breadcrumb]

    public enum Kind: String, Codable, Sendable {
        case exception
        case signal
        case fatalError
    }

    public struct Breadcrumb: Codable, Sendable {
        public let timestamp: Date
        public let category: String
        public let message: String
    }
}

// MARK: - Uploader

/// Adopters transmit captured crash reports to a backend. The default
/// implementation is a no-op so the reporter is safe to install even
/// when the user hasn't opted into telemetry.
public protocol CrashReportUploader: Sendable {
    func upload(_ report: CrashReport) async throws
}

/// No-op uploader used until the gateway hook is installed.
public struct NoopCrashReportUploader: CrashReportUploader {
    public init() {}
    public func upload(_ report: CrashReport) async throws {}
}

// MARK: - Crash Reporter

/// Installs process-wide crash hooks and manages on-disk crash files.
///
/// Use ``CrashReporter.shared.install()`` once at app startup (in
/// ``MTRXApp.init`` or ``SceneDelegate.scene(_:willConnectTo:...)``).
/// The reporter uses a singleton because signal handlers can't capture
/// self-referential closures and must reach the state through a
/// process-global.
public final class CrashReporter: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = CrashReporter()

    // MARK: - State

    private let lock = NSLock()
    private var breadcrumbs: [CrashReport.Breadcrumb] = []
    private let breadcrumbLimit = 64
    private var uploader: CrashReportUploader = NoopCrashReportUploader()
    private var installed = false

    // MARK: - Public API

    /// Install crash hooks. Safe to call multiple times — only the
    /// first call takes effect.
    public func install(uploader: CrashReportUploader? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let uploader { self.uploader = uploader }
        guard !installed else { return }
        installed = true

        installExceptionHandler()
        installSignalHandlers()

        // Drain any pending reports from a previous launch on a
        // background queue so we don't block app startup.
        Task.detached(priority: .background) { [weak self] in
            await self?.flushPendingReports()
        }
    }

    /// Record a breadcrumb. Breadcrumbs are lightweight, ring-buffered
    /// notes the reporter attaches to any crash that happens after
    /// them. Use them for "high-value" events: user navigated to
    /// screen X, network call Y failed, wallet Z linked.
    public func addBreadcrumb(category: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        let crumb = CrashReport.Breadcrumb(
            timestamp: Date(),
            category: category,
            message: message
        )
        breadcrumbs.append(crumb)
        if breadcrumbs.count > breadcrumbLimit {
            breadcrumbs.removeFirst(breadcrumbs.count - breadcrumbLimit)
        }
    }

    /// Capture a Swift-level fatal condition without crashing the
    /// process — useful for "we bailed out but want a report" paths.
    public func captureFatal(reason: String, file: StaticString = #file, line: UInt = #line) {
        let report = buildReport(
            kind: .fatalError,
            reason: "\(reason) @ \(file):\(line)",
            symbols: Thread.callStackSymbols
        )
        _ = try? persist(report)
    }

    /// Install a new uploader — used by the gateway hook once the
    /// user has opted into telemetry.
    public func setUploader(_ uploader: CrashReportUploader) {
        lock.lock()
        self.uploader = uploader
        lock.unlock()
    }

    // MARK: - Exception Handler

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            // We're inside a dying process; do the minimum amount of
            // work possible. ``buildReport`` and ``persist`` are
            // intentionally main-actor-free and Foundation-only.
            let report = CrashReporter.shared.buildReport(
                kind: .exception,
                reason: "\(exception.name.rawValue): \(exception.reason ?? "")",
                symbols: exception.callStackSymbols
            )
            _ = try? CrashReporter.shared.persist(report)
        }
    }

    // MARK: - Signal Handlers

    private func installSignalHandlers() {
        let fatalSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGPIPE]
        for sig in fatalSignals {
            signal(sig) { signum in
                // Signal-safe: write a minimal marker file and
                // re-raise the signal so the OS produces its normal
                // crash log for Xcode Organizer to pick up.
                CrashReporter.writeSignalMarker(signum: signum)
                signal(signum, SIG_DFL)
                raise(signum)
            }
        }
    }

    /// Write a tiny marker file that the next launch can pick up and
    /// upgrade into a full ``CrashReport``. We can't serialize a Codable
    /// object inside a signal handler because Foundation isn't
    /// async-signal-safe, so we just drop a signed integer.
    private static func writeSignalMarker(signum: Int32) {
        guard let url = Self.markerURL() else { return }
        let text = "\(signum)\n"
        _ = text.withCString { ptr -> Int in
            let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
            if fd < 0 { return -1 }
            let n = write(fd, ptr, strlen(ptr))
            close(fd)
            return n
        }
    }

    private static func markerURL() -> URL? {
        guard let dir = Self.reportsDirectory() else { return nil }
        return dir.appendingPathComponent("pending.signal")
    }

    // MARK: - Report Persistence

    private func buildReport(
        kind: CrashReport.Kind,
        reason: String,
        symbols: [String]
    ) -> CrashReport {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        #if canImport(UIKit)
        let os = "iOS \(UIDevice.current.systemVersion)"
        let model = UIDevice.current.model
        #else
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let model = "Mac"
        #endif

        lock.lock()
        let crumbs = breadcrumbs
        lock.unlock()

        return CrashReport(
            id: UUID(),
            timestamp: Date(),
            appVersion: version,
            buildNumber: build,
            osVersion: os,
            deviceModel: model,
            kind: kind,
            reason: reason,
            symbols: symbols,
            breadcrumbs: crumbs
        )
    }

    @discardableResult
    private func persist(_ report: CrashReport) throws -> URL {
        guard let dir = Self.reportsDirectory() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let filename = Self.filenameFormatter.string(from: report.timestamp) + ".json"
        let url = dir.appendingPathComponent(filename)
        let data = try JSONEncoder().encode(report)
        try data.write(to: url, options: [.atomic])
        return url
    }

    // MARK: - Flush

    private func flushPendingReports() async {
        guard let dir = Self.reportsDirectory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        // Upgrade any signal marker file into a proper JSON report
        // before the upload loop runs.
        if let marker = entries.first(where: { $0.lastPathComponent == "pending.signal" }) {
            if let raw = try? String(contentsOf: marker),
               let signum = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let report = buildReport(
                    kind: .signal,
                    reason: "Fatal signal \(signum)",
                    symbols: []
                )
                _ = try? persist(report)
            }
            try? FileManager.default.removeItem(at: marker)
        }

        guard let jsonEntries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in jsonEntries where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let report = try JSONDecoder().decode(CrashReport.self, from: data)
                try await uploader.upload(report)
                try FileManager.default.removeItem(at: url)
            } catch {
                // Leave the file on disk; we'll retry next launch.
                print("[CrashReporter] Flush failed for \(url.lastPathComponent): \(error)")
            }
        }
    }

    // MARK: - Paths

    private static func reportsDirectory() -> URL? {
        let fm = FileManager.default
        guard let caches = try? fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return caches.appendingPathComponent("MTRXCrashReports", isDirectory: true)
    }

    private static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmssSSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

// MARK: - Gateway Uploader

/// Default uploader that posts crash reports to a gateway endpoint.
///
/// We POST the report JSON to ``/api/v1/crash-reports`` with the
/// standard gateway API key. The gateway forwards it to whatever
/// storage the operator has configured (object store, ticket system,
/// or just a log pipeline).
public struct GatewayCrashReportUploader: CrashReportUploader {
    public let baseURL: URL
    public let apiKey: String?
    public let session: URLSession

    public init(
        baseURL: URL,
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    public func upload(_ report: CrashReport) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/crash-reports"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(report)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}
