//
//  ExtensionVetting.swift
//  MTRX
//
//  Three-layer vetting pipeline: automated static analysis, manual code review flag,
//  and runtime behavior monitoring for extension safety verification.
//

import Foundation
import Combine

// MARK: - Vetting Stage

enum VettingStage: String, Codable, CaseIterable {
    case notStarted
    case staticAnalysis
    case manualReview
    case runtimeMonitoring
    case completed

    var displayName: String {
        switch self {
        case .notStarted:         return "Not Started"
        case .staticAnalysis:     return "Static Analysis"
        case .manualReview:       return "Manual Code Review"
        case .runtimeMonitoring:  return "Runtime Monitoring"
        case .completed:          return "Completed"
        }
    }

    var stageNumber: Int {
        switch self {
        case .notStarted:         return 0
        case .staticAnalysis:     return 1
        case .manualReview:       return 2
        case .runtimeMonitoring:  return 3
        case .completed:          return 4
        }
    }
}

// MARK: - Vetting Result

enum VettingResult: String, Codable {
    case passed
    case passedWithWarnings
    case failed
    case needsManualReview
    case pending
}

// MARK: - Static Analysis Finding

struct StaticAnalysisFinding: Identifiable, Codable, Equatable {
    let id: UUID
    let rule: StaticAnalysisRule
    let severity: FindingSeverity
    let file: String
    let line: Int?
    let description: String
    let suggestion: String?

    enum StaticAnalysisRule: String, Codable, CaseIterable {
        case privateKeyAccess
        case unsafeNetworkCall
        case fileSystemEscape
        case obfuscatedCode
        case dynamicCodeExecution
        case excessivePermissions
        case hardcodedSecrets
        case unsafeDeserialization
        case privacyViolation
        case cryptoMisuse
        case memoryUnsafe
        case deprecatedAPI
    }

    enum FindingSeverity: String, Codable, Comparable {
        case info
        case low
        case medium
        case high
        case critical

        static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool {
            let order: [FindingSeverity] = [.info, .low, .medium, .high, .critical]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }
}

// MARK: - Manual Review Report

struct ManualReviewReport: Codable, Equatable {
    let reviewerId: String
    let reviewDate: Date
    let verdict: VettingResult
    let comments: String
    let flaggedIssues: [String]
    let approvedCapabilities: [ExtensionCapability]
    let deniedCapabilities: [ExtensionCapability]
    let requiresFollowUp: Bool
}

// MARK: - Runtime Behavior Record

struct RuntimeBehaviorRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let extensionId: String
    let timestamp: Date
    let behavior: BehaviorType
    let detail: String
    let isAnomaly: Bool

    enum BehaviorType: String, Codable, CaseIterable {
        case networkRequest
        case fileAccess
        case dataAccess
        case apiCall
        case memorySpike
        case cpuSpike
        case crashOrError
        case permissionEscalation
    }
}

// MARK: - Vetting Report

struct VettingReport: Codable, Identifiable {
    let id: UUID
    let extensionId: String
    let startedAt: Date
    let completedAt: Date?
    let currentStage: VettingStage
    let overallResult: VettingResult

    let staticAnalysisFindings: [StaticAnalysisFinding]
    let staticAnalysisResult: VettingResult
    let manualReview: ManualReviewReport?
    let runtimeBehaviorRecords: [RuntimeBehaviorRecord]
    let runtimeResult: VettingResult

    var criticalFindingCount: Int {
        staticAnalysisFindings.filter { $0.severity >= .high }.count
    }

    var anomalyCount: Int {
        runtimeBehaviorRecords.filter(\.isAnomaly).count
    }
}

// MARK: - Extension Vetting Pipeline

/// Three-layer vetting pipeline for extension safety verification.
final class ExtensionVetting: ObservableObject {

    // MARK: - Published State

    @Published private(set) var activeVettings: [String: VettingReport] = [:]
    @Published private(set) var completedVettings: [String: VettingReport] = [:]

    // MARK: - Publishers

    let stageCompleted = PassthroughSubject<(String, VettingStage, VettingResult), Never>()
    let vettingCompleted = PassthroughSubject<VettingReport, Never>()
    let anomalyDetected = PassthroughSubject<RuntimeBehaviorRecord, Never>()

    // MARK: - Configuration

    private let autoRejectOnCriticalFindings: Bool
    private let maxRuntimeMonitoringDays: Int
    private let anomalyThreshold: Int

    // MARK: - State

    private var runtimeMonitors: [String: AnyCancellable] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        autoRejectOnCriticalFindings: Bool = true,
        maxRuntimeMonitoringDays: Int = 30,
        anomalyThreshold: Int = 5
    ) {
        self.autoRejectOnCriticalFindings = autoRejectOnCriticalFindings
        self.maxRuntimeMonitoringDays = maxRuntimeMonitoringDays
        self.anomalyThreshold = anomalyThreshold
    }

    // MARK: - Pipeline Entry

    /// Starts the full vetting pipeline for an extension.
    func startVetting(extensionId: String, bundlePath: URL) async -> VettingReport {
        let report = VettingReport(
            id: UUID(),
            extensionId: extensionId,
            startedAt: Date(),
            completedAt: nil,
            currentStage: .staticAnalysis,
            overallResult: .pending,
            staticAnalysisFindings: [],
            staticAnalysisResult: .pending,
            manualReview: nil,
            runtimeBehaviorRecords: [],
            runtimeResult: .pending
        )

        await MainActor.run {
            activeVettings[extensionId] = report
        }

        // Stage 1: Static Analysis
        let staticResult = await performStaticAnalysis(extensionId: extensionId, bundlePath: bundlePath)
        stageCompleted.send((extensionId, .staticAnalysis, staticResult.result))

        if autoRejectOnCriticalFindings && staticResult.findings.contains(where: { $0.severity == .critical }) {
            return finalizeReport(extensionId: extensionId, result: .failed, findings: staticResult.findings)
        }

        // Stage 2: Flag for Manual Review (if needed)
        let needsManualReview = staticResult.findings.contains(where: { $0.severity >= .medium })
        if needsManualReview {
            await flagForManualReview(extensionId: extensionId, findings: staticResult.findings)
            stageCompleted.send((extensionId, .manualReview, .needsManualReview))
        }

        // Stage 3: Runtime Monitoring
        startRuntimeMonitoring(extensionId: extensionId)
        stageCompleted.send((extensionId, .runtimeMonitoring, .pending))

        // Return current state (runtime monitoring continues asynchronously)
        return activeVettings[extensionId] ?? report
    }

    // MARK: - Stage 1: Static Analysis

    private func performStaticAnalysis(
        extensionId: String,
        bundlePath: URL
    ) async -> (findings: [StaticAnalysisFinding], result: VettingResult) {
        var findings: [StaticAnalysisFinding] = []

        // Check for private key access patterns
        findings.append(contentsOf: scanForPrivateKeyAccess(bundlePath: bundlePath))

        // Check for unsafe network calls
        findings.append(contentsOf: scanForUnsafeNetworkCalls(bundlePath: bundlePath))

        // Check for filesystem escape attempts
        findings.append(contentsOf: scanForFilesystemEscape(bundlePath: bundlePath))

        // Check for obfuscated code
        findings.append(contentsOf: scanForObfuscatedCode(bundlePath: bundlePath))

        // Check for dynamic code execution
        findings.append(contentsOf: scanForDynamicExecution(bundlePath: bundlePath))

        // Check for hardcoded secrets
        findings.append(contentsOf: scanForHardcodedSecrets(bundlePath: bundlePath))

        // Determine result
        let result: VettingResult
        if findings.contains(where: { $0.severity == .critical }) {
            result = .failed
        } else if findings.contains(where: { $0.severity >= .medium }) {
            result = .needsManualReview
        } else if findings.isEmpty {
            result = .passed
        } else {
            result = .passedWithWarnings
        }

        return (findings, result)
    }

    // MARK: - Static Analysis Scanners

    private func scanForPrivateKeyAccess(bundlePath: URL) -> [StaticAnalysisFinding] {
        // Placeholder: Scans source for patterns like keychain access to private keys,
        // seed phrase manipulation, or signing key extraction.
        return []
    }

    private func scanForUnsafeNetworkCalls(bundlePath: URL) -> [StaticAnalysisFinding] {
        // Placeholder: Detects raw HTTP (non-HTTPS), undeclared endpoints,
        // or data exfiltration patterns.
        return []
    }

    private func scanForFilesystemEscape(bundlePath: URL) -> [StaticAnalysisFinding] {
        // Placeholder: Detects path traversal (../), symlink attacks,
        // or access to paths outside sandbox.
        return []
    }

    private func scanForObfuscatedCode(bundlePath: URL) -> [StaticAnalysisFinding] {
        // Placeholder: Detects base64-encoded executable strings,
        // eval-like patterns, or entropy analysis for obfuscation.
        return []
    }

    private func scanForDynamicExecution(bundlePath: URL) -> [StaticAnalysisFinding] {
        // Placeholder: Detects NSClassFromString, dlopen, or runtime method swizzling.
        return []
    }

    private func scanForHardcodedSecrets(bundlePath: URL) -> [StaticAnalysisFinding] {
        // Placeholder: Scans for API keys, tokens, or credentials in source code.
        return []
    }

    // MARK: - Stage 2: Manual Review

    private func flagForManualReview(
        extensionId: String,
        findings: [StaticAnalysisFinding]
    ) async {
        // Placeholder: Creates a review ticket in the internal review system,
        // attaches static analysis findings, and notifies the review team.
    }

    /// Submits a manual review report (called by human reviewer).
    func submitManualReview(extensionId: String, report: ManualReviewReport) {
        // Update the vetting report with manual review results
        stageCompleted.send((extensionId, .manualReview, report.verdict))

        if report.verdict == .failed {
            _ = finalizeReport(extensionId: extensionId, result: .failed, findings: [])
        }
    }

    // MARK: - Stage 3: Runtime Monitoring

    private func startRuntimeMonitoring(extensionId: String) {
        let monitor = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.collectRuntimeBehavior(extensionId: extensionId)
            }
        runtimeMonitors[extensionId] = monitor
    }

    private func collectRuntimeBehavior(extensionId: String) {
        // Placeholder: Collects runtime behavior metrics from the sandbox,
        // including network requests, file access patterns, API usage,
        // and resource consumption anomalies.
    }

    /// Records a runtime behavior observation.
    func recordBehavior(_ record: RuntimeBehaviorRecord) {
        if record.isAnomaly {
            anomalyDetected.send(record)

            // Check if anomaly threshold is exceeded
            let anomalies = activeVettings[record.extensionId]?.runtimeBehaviorRecords
                .filter(\.isAnomaly).count ?? 0
            if anomalies >= anomalyThreshold {
                _ = finalizeReport(extensionId: record.extensionId, result: .failed, findings: [])
            }
        }
    }

    /// Stops runtime monitoring for an extension.
    func stopRuntimeMonitoring(extensionId: String) {
        runtimeMonitors[extensionId]?.cancel()
        runtimeMonitors.removeValue(forKey: extensionId)
    }

    // MARK: - Finalization

    private func finalizeReport(
        extensionId: String,
        result: VettingResult,
        findings: [StaticAnalysisFinding]
    ) -> VettingReport {
        let existing = activeVettings[extensionId]
        let report = VettingReport(
            id: existing?.id ?? UUID(),
            extensionId: extensionId,
            startedAt: existing?.startedAt ?? Date(),
            completedAt: Date(),
            currentStage: .completed,
            overallResult: result,
            staticAnalysisFindings: findings.isEmpty ? (existing?.staticAnalysisFindings ?? []) : findings,
            staticAnalysisResult: existing?.staticAnalysisResult ?? result,
            manualReview: existing?.manualReview,
            runtimeBehaviorRecords: existing?.runtimeBehaviorRecords ?? [],
            runtimeResult: existing?.runtimeResult ?? result
        )

        activeVettings.removeValue(forKey: extensionId)
        completedVettings[extensionId] = report
        stopRuntimeMonitoring(extensionId: extensionId)
        vettingCompleted.send(report)

        return report
    }

    // MARK: - Query

    /// Returns the current vetting status for an extension.
    func vettingStatus(for extensionId: String) -> (stage: VettingStage, result: VettingResult)? {
        if let active = activeVettings[extensionId] {
            return (active.currentStage, active.overallResult)
        }
        if let completed = completedVettings[extensionId] {
            return (completed.currentStage, completed.overallResult)
        }
        return nil
    }

    /// Returns whether an extension has passed all vetting stages.
    func isFullyVetted(extensionId: String) -> Bool {
        guard let report = completedVettings[extensionId] else { return false }
        return report.overallResult == .passed || report.overallResult == .passedWithWarnings
    }
}
