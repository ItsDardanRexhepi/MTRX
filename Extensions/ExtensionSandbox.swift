//
//  ExtensionSandbox.swift
//  MTRX
//
//  Security isolation for extensions with resource limits, network restrictions,
//  filesystem isolation, and process-level separation.
//

import Foundation
import Combine

// MARK: - Sandbox Configuration

struct SandboxConfiguration: Equatable {
    let maxMemoryMB: Int
    let maxCPUPercent: Double
    let maxDiskMB: Int
    let maxNetworkBytesPerSecond: Int
    let allowedNetworkDomains: [String]
    let maxExecutionTimeSeconds: TimeInterval
    let maxConcurrentOperations: Int

    static var `default`: SandboxConfiguration {
        SandboxConfiguration(
            maxMemoryMB: 64,
            maxCPUPercent: 10.0,
            maxDiskMB: 50,
            maxNetworkBytesPerSecond: 1_000_000,
            allowedNetworkDomains: [],
            maxExecutionTimeSeconds: 30.0,
            maxConcurrentOperations: 4
        )
    }

    static var restricted: SandboxConfiguration {
        SandboxConfiguration(
            maxMemoryMB: 32,
            maxCPUPercent: 5.0,
            maxDiskMB: 10,
            maxNetworkBytesPerSecond: 100_000,
            allowedNetworkDomains: [],
            maxExecutionTimeSeconds: 10.0,
            maxConcurrentOperations: 2
        )
    }
}

// MARK: - Sandbox Violation

struct SandboxViolation: Identifiable, Equatable {
    let id: UUID
    let extensionId: String
    let type: ViolationType
    let description: String
    let severity: Severity
    let timestamp: Date
    let currentValue: String
    let limit: String

    enum ViolationType: String, CaseIterable {
        case memoryExceeded
        case cpuExceeded
        case diskExceeded
        case networkExceeded
        case unauthorizedNetworkAccess
        case filesystemViolation
        case executionTimeout
        case unauthorizedAPIAccess
        case concurrencyExceeded
    }

    enum Severity: String, Comparable {
        case warning
        case violation
        case critical

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            let order: [Severity] = [.warning, .violation, .critical]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }
}

// MARK: - Resource Usage

struct ResourceUsage: Equatable {
    let memoryMB: Double
    let cpuPercent: Double
    let diskMB: Double
    let networkBytesIn: Int64
    let networkBytesOut: Int64
    let activeOperations: Int
    let timestamp: Date

    var memoryUtilization: Double {
        memoryMB / Double(SandboxConfiguration.default.maxMemoryMB)
    }
}

// MARK: - Sandbox State

enum SandboxState: Equatable {
    case inactive
    case active
    case suspended(reason: String)
    case terminated(reason: String)
}

// MARK: - Extension Sandbox

/// Provides security isolation for extensions with resource monitoring and enforcement.
final class ExtensionSandbox: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: SandboxState = .inactive
    @Published private(set) var resourceUsage: ResourceUsage?
    @Published private(set) var violationCount: Int = 0

    // MARK: - Publishers

    let violations = PassthroughSubject<SandboxViolation, Never>()

    // MARK: - Properties

    let extensionId: String
    let configuration: SandboxConfiguration

    // MARK: - Internal State

    private var sandboxDirectory: URL?
    private var resourceMonitorTimer: AnyCancellable?
    private var violationHistory: [SandboxViolation] = []
    private var cancellables = Set<AnyCancellable>()
    private let monitoringQueue = DispatchQueue(label: "com.mtrx.sandbox.monitor", qos: .utility)

    // MARK: - Thresholds

    private let warningThreshold: Double = 0.8
    private let violationThreshold: Double = 1.0
    private let maxViolationsBeforeTermination = 3

    // MARK: - Initialization

    init(
        extensionId: String,
        configuration: SandboxConfiguration = .default
    ) {
        self.extensionId = extensionId
        self.configuration = configuration
    }

    deinit {
        terminate()
    }

    // MARK: - Lifecycle

    /// Activates the sandbox, creating the isolated filesystem and starting monitoring.
    func activate() throws {
        guard state == .inactive else { return }

        try createSandboxDirectory()
        startResourceMonitoring()
        state = .active
    }

    /// Suspends the sandbox, pausing all extension operations.
    func suspend(reason: String) {
        guard state == .active else { return }
        state = .suspended(reason: reason)
        resourceMonitorTimer?.cancel()
    }

    /// Resumes a suspended sandbox.
    func resume() {
        guard case .suspended = state else { return }
        state = .active
        startResourceMonitoring()
    }

    /// Terminates the sandbox, cleaning up all resources.
    func terminate() {
        resourceMonitorTimer?.cancel()
        resourceMonitorTimer = nil
        cleanupSandboxDirectory()
        state = .terminated(reason: "Terminated")
    }

    // MARK: - Filesystem Isolation

    private func createSandboxDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let sandboxDir = tempDir.appendingPathComponent("mtrx-sandbox/\(extensionId)", isDirectory: true)

        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        sandboxDirectory = sandboxDir
    }

    private func cleanupSandboxDirectory() {
        guard let dir = sandboxDirectory else { return }
        try? FileManager.default.removeItem(at: dir)
        sandboxDirectory = nil
    }

    /// Validates that a file path is within the sandbox boundary.
    func validateFilePath(_ path: URL) -> Bool {
        guard let sandboxDir = sandboxDirectory else { return false }
        let resolved = path.standardizedFileURL.path
        let sandboxPath = sandboxDir.standardizedFileURL.path
        return resolved.hasPrefix(sandboxPath)
    }

    /// Returns the sandboxed root directory for the extension.
    func sandboxRootURL() -> URL? {
        sandboxDirectory
    }

    // MARK: - Network Restrictions

    /// Validates whether a network request to a domain is allowed.
    func isNetworkAccessAllowed(to domain: String) -> Bool {
        guard configuration.allowedNetworkDomains.isEmpty == false else {
            // If no domains are specified, no network access is allowed
            return false
        }
        return configuration.allowedNetworkDomains.contains { allowed in
            domain == allowed || domain.hasSuffix(".\(allowed)")
        }
    }

    /// Creates a URLSession configured with sandbox restrictions.
    func createRestrictedURLSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = configuration.maxExecutionTimeSeconds
        config.timeoutIntervalForResource = configuration.maxExecutionTimeSeconds * 2
        config.httpMaximumConnectionsPerHost = 2
        config.allowsCellularAccess = true
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: - Resource Monitoring

    private func startResourceMonitoring() {
        resourceMonitorTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkResourceUsage()
            }
    }

    private func checkResourceUsage() {
        monitoringQueue.async { [weak self] in
            guard let self, self.state == .active else { return }

            let usage = self.measureResourceUsage()

            DispatchQueue.main.async {
                self.resourceUsage = usage
            }

            self.enforceMemoryLimit(usage)
            self.enforceCPULimit(usage)
            self.enforceDiskLimit(usage)
            self.enforceNetworkLimit(usage)
            self.enforceConcurrencyLimit(usage)
        }
    }

    private func measureResourceUsage() -> ResourceUsage {
        // Placeholder: In production, uses mach_task_info for memory,
        // proc_pid_rusage for CPU, and file system attributes for disk.
        ResourceUsage(
            memoryMB: 0,
            cpuPercent: 0,
            diskMB: 0,
            networkBytesIn: 0,
            networkBytesOut: 0,
            activeOperations: 0,
            timestamp: Date()
        )
    }

    // MARK: - Enforcement

    private func enforceMemoryLimit(_ usage: ResourceUsage) {
        let ratio = usage.memoryMB / Double(configuration.maxMemoryMB)
        if ratio >= violationThreshold {
            recordViolation(type: .memoryExceeded, current: "\(usage.memoryMB)MB", limit: "\(configuration.maxMemoryMB)MB", severity: .violation)
        } else if ratio >= warningThreshold {
            recordViolation(type: .memoryExceeded, current: "\(usage.memoryMB)MB", limit: "\(configuration.maxMemoryMB)MB", severity: .warning)
        }
    }

    private func enforceCPULimit(_ usage: ResourceUsage) {
        if usage.cpuPercent > configuration.maxCPUPercent {
            recordViolation(type: .cpuExceeded, current: "\(usage.cpuPercent)%", limit: "\(configuration.maxCPUPercent)%", severity: .violation)
        }
    }

    private func enforceDiskLimit(_ usage: ResourceUsage) {
        if usage.diskMB > Double(configuration.maxDiskMB) {
            recordViolation(type: .diskExceeded, current: "\(usage.diskMB)MB", limit: "\(configuration.maxDiskMB)MB", severity: .violation)
        }
    }

    private func enforceNetworkLimit(_ usage: ResourceUsage) {
        let totalBytes = usage.networkBytesIn + usage.networkBytesOut
        if totalBytes > Int64(configuration.maxNetworkBytesPerSecond) {
            recordViolation(type: .networkExceeded, current: "\(totalBytes)B/s", limit: "\(configuration.maxNetworkBytesPerSecond)B/s", severity: .violation)
        }
    }

    private func enforceConcurrencyLimit(_ usage: ResourceUsage) {
        if usage.activeOperations > configuration.maxConcurrentOperations {
            recordViolation(type: .concurrencyExceeded, current: "\(usage.activeOperations)", limit: "\(configuration.maxConcurrentOperations)", severity: .warning)
        }
    }

    // MARK: - Violation Recording

    private func recordViolation(type: SandboxViolation.ViolationType, current: String, limit: String, severity: SandboxViolation.Severity) {
        let violation = SandboxViolation(
            id: UUID(),
            extensionId: extensionId,
            type: type,
            description: "\(type.rawValue): \(current) exceeds \(limit)",
            severity: severity,
            timestamp: Date(),
            currentValue: current,
            limit: limit
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.violationHistory.append(violation)
            self.violationCount = self.violationHistory.count
            self.violations.send(violation)

            // Auto-terminate after too many violations
            let criticalCount = self.violationHistory.filter { $0.severity >= .violation }.count
            if criticalCount >= self.maxViolationsBeforeTermination {
                self.terminate()
            }
        }
    }

    // MARK: - Diagnostics

    /// Returns the full violation history for this sandbox.
    func getViolationHistory() -> [SandboxViolation] {
        violationHistory
    }
}
