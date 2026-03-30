//
//  ExtensionRegistry.swift
//  MTRX
//
//  Registry of approved developer extensions with version tracking,
//  update mechanism, and developer verification.
//

import Foundation
import Combine

// MARK: - Registered Extension

struct RegisteredExtension: Codable, Identifiable, Equatable {
    let id: String
    let manifest: ExtensionManifest
    let developerInfo: DeveloperInfo
    let approvalStatus: ApprovalStatus
    let approvedAt: Date?
    let lastReviewedAt: Date
    let installedVersion: String
    let latestAvailableVersion: String?
    let installCount: Int
    let rating: Double?
    let checksumSHA256: String

    var isUpdateAvailable: Bool {
        guard let latest = latestAvailableVersion else { return false }
        return latest.compare(installedVersion, options: .numeric) == .orderedDescending
    }
}

// MARK: - Developer Info

struct DeveloperInfo: Codable, Equatable {
    let id: String
    let name: String
    let email: String
    let website: URL?
    let verificationStatus: VerificationStatus
    let registeredAt: Date
    let publishedExtensionCount: Int

    enum VerificationStatus: String, Codable, CaseIterable {
        case unverified
        case emailVerified
        case identityVerified
        case trustedPartner

        var trustLevel: Int {
            switch self {
            case .unverified:        return 0
            case .emailVerified:     return 1
            case .identityVerified:  return 2
            case .trustedPartner:    return 3
            }
        }
    }
}

// MARK: - Approval Status

enum ApprovalStatus: String, Codable, CaseIterable {
    case pending
    case inReview
    case approved
    case conditionallyApproved
    case rejected
    case suspended
    case revoked

    var isAllowed: Bool {
        self == .approved || self == .conditionallyApproved
    }
}

// MARK: - Update Check Result

struct UpdateCheckResult: Equatable {
    let extensionId: String
    let currentVersion: String
    let availableVersion: String
    let releaseNotes: String?
    let isSecurityUpdate: Bool
    let checksumSHA256: String
}

// MARK: - Extension Registry

/// Manages the catalog of approved, vetted extensions available for MTRX.
final class ExtensionRegistry: ObservableObject {

    // MARK: - Published State

    @Published private(set) var registeredExtensions: [String: RegisteredExtension] = [:]
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastRefreshDate: Date?

    // MARK: - Publishers

    let updateAvailable = PassthroughSubject<UpdateCheckResult, Never>()
    let extensionStatusChanged = PassthroughSubject<(String, ApprovalStatus), Never>()

    // MARK: - Configuration

    private let registryEndpoint: URL
    private let refreshInterval: TimeInterval
    private let autoUpdateSecurityPatches: Bool

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: AnyCancellable?
    private let registryQueue = DispatchQueue(label: "com.mtrx.extension-registry", qos: .utility)

    // MARK: - Initialization

    init(
        registryEndpoint: URL = URL(string: "https://extensions.mtrx.app/api/v1/registry")!,
        refreshInterval: TimeInterval = 3600,
        autoUpdateSecurityPatches: Bool = true
    ) {
        self.registryEndpoint = registryEndpoint
        self.refreshInterval = refreshInterval
        self.autoUpdateSecurityPatches = autoUpdateSecurityPatches
    }

    // MARK: - Lifecycle

    /// Starts periodic refresh of the extension registry.
    func startRefreshing() {
        refresh()
        refreshTimer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    /// Stops automatic refreshes.
    func stopRefreshing() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    // MARK: - Registration

    /// Registers a new extension in the local registry.
    func register(_ extension_: RegisteredExtension) {
        registeredExtensions[extension_.id] = extension_
    }

    /// Removes an extension from the local registry.
    func unregister(extensionId: String) {
        registeredExtensions.removeValue(forKey: extensionId)
    }

    // MARK: - Query

    /// Checks whether an extension is approved and allowed to run.
    func isApproved(extensionId: String) -> Bool {
        registeredExtensions[extensionId]?.approvalStatus.isAllowed ?? false
    }

    /// Returns all extensions in a given category.
    func extensions(inCategory category: ExtensionManifest.ExtensionCategory) -> [RegisteredExtension] {
        registeredExtensions.values.filter { $0.manifest.category == category }
    }

    /// Returns extensions by a specific developer.
    func extensions(byDeveloper developerId: String) -> [RegisteredExtension] {
        registeredExtensions.values.filter { $0.developerInfo.id == developerId }
    }

    /// Returns extensions that have updates available.
    func extensionsWithUpdates() -> [RegisteredExtension] {
        registeredExtensions.values.filter(\.isUpdateAvailable)
    }

    // MARK: - Developer Verification

    /// Verifies a developer's identity and signing certificate.
    func verifyDeveloper(developerId: String) async throws -> DeveloperInfo.VerificationStatus {
        // Placeholder: Queries the registry API to verify developer credentials,
        // checks signing certificate chain, and returns updated verification status.
        return .emailVerified
    }

    // MARK: - Update Mechanism

    /// Checks for updates for all registered extensions.
    func checkForUpdates() async {
        for (id, ext) in registeredExtensions {
            if let update = await checkUpdate(for: ext) {
                if autoUpdateSecurityPatches && update.isSecurityUpdate {
                    await applyUpdate(extensionId: id, update: update)
                } else {
                    updateAvailable.send(update)
                }
            }
        }
    }

    /// Checks for an update for a single extension.
    private func checkUpdate(for ext: RegisteredExtension) async -> UpdateCheckResult? {
        // Placeholder: Queries the registry API for the latest version.
        return nil
    }

    /// Applies an extension update.
    func applyUpdate(extensionId: String, update: UpdateCheckResult) async {
        guard var ext = registeredExtensions[extensionId] else { return }
        // Placeholder: Downloads the new version, verifies checksum,
        // swaps the extension bundle, and updates the registry entry.
    }

    // MARK: - Integrity Verification

    /// Verifies the integrity of an installed extension against its registered checksum.
    func verifyIntegrity(extensionId: String) -> Bool {
        guard let ext = registeredExtensions[extensionId] else { return false }
        // Placeholder: Computes SHA-256 of the installed extension bundle
        // and compares against ext.checksumSHA256.
        return true
    }

    // MARK: - Refresh

    /// Fetches the latest registry data from the server.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        // Placeholder: Fetches the latest approved extensions list from the API.
        // Updates local registry with new entries, status changes, and removals.

        Task { @MainActor in
            isRefreshing = false
            lastRefreshDate = Date()
        }
    }

    // MARK: - Revocation

    /// Immediately revokes an extension, stopping it if running.
    func revoke(extensionId: String, reason: String) {
        guard var ext = registeredExtensions[extensionId] else { return }
        // Update status to revoked
        extensionStatusChanged.send((extensionId, .revoked))
    }
}
