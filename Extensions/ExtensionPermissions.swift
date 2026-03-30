//
//  ExtensionPermissions.swift
//  MTRX
//
//  Permission model where extensions inherit a subset of host permissions.
//  User-controllable permission grants with granular capability management.
//

import Foundation
import Combine

// MARK: - Permission Grant

struct PermissionGrant: Codable, Equatable, Identifiable {
    let id: UUID
    let extensionId: String
    let capability: ExtensionCapability
    let grantedAt: Date
    let grantedBy: GrantSource
    let expiresAt: Date?
    let isRevocable: Bool

    enum GrantSource: String, Codable {
        case user           // Explicitly granted by user
        case manifest       // Declared in extension manifest and auto-approved
        case inherited      // Inherited from host permissions
        case conditional    // Granted conditionally with restrictions
    }

    var isExpired: Bool {
        guard let expiry = expiresAt else { return false }
        return Date() > expiry
    }

    var isActive: Bool {
        !isExpired
    }
}

// MARK: - Permission Request

struct PermissionRequest: Identifiable, Equatable {
    let id: UUID
    let extensionId: String
    let extensionName: String
    let capability: ExtensionCapability
    let reason: String
    let isRequired: Bool
    let requestedAt: Date

    static func == (lhs: PermissionRequest, rhs: PermissionRequest) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Permission Policy

struct PermissionPolicy: Codable, Equatable {
    let maximumGrantableCapabilities: Set<ExtensionCapability>
    let alwaysDeniedCapabilities: Set<ExtensionCapability>
    let requireUserApprovalForAll: Bool
    let autoGrantForTrustedDevelopers: Bool
    let grantExpirationInterval: TimeInterval?

    static var `default`: PermissionPolicy {
        PermissionPolicy(
            maximumGrantableCapabilities: Set(ExtensionCapability.allCases),
            alwaysDeniedCapabilities: [],
            requireUserApprovalForAll: false,
            autoGrantForTrustedDevelopers: true,
            grantExpirationInterval: nil
        )
    }

    static var strict: PermissionPolicy {
        PermissionPolicy(
            maximumGrantableCapabilities: [.readWalletAddress, .displayUI],
            alwaysDeniedCapabilities: [.proposeTransaction, .readHealthData],
            requireUserApprovalForAll: true,
            autoGrantForTrustedDevelopers: false,
            grantExpirationInterval: 86400 * 7 // 7 days
        )
    }
}

// MARK: - Extension Permissions

/// Manages permission grants for extensions with user-controllable overrides.
final class ExtensionPermissions: ObservableObject {

    // MARK: - Published State

    @Published private(set) var grants: [String: [PermissionGrant]] = [:]
    @Published private(set) var pendingRequests: [PermissionRequest] = []
    @Published var policy: PermissionPolicy = .default

    // MARK: - Publishers

    let permissionGranted = PassthroughSubject<PermissionGrant, Never>()
    let permissionRevoked = PassthroughSubject<(String, ExtensionCapability), Never>()
    let permissionRequested = PassthroughSubject<PermissionRequest, Never>()

    // MARK: - Host Permission Reference

    private var hostPermissions: Set<ExtensionCapability> = Set(ExtensionCapability.allCases)

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(policy: PermissionPolicy = .default) {
        self.policy = policy
    }

    // MARK: - Query

    /// Returns all granted capabilities for an extension.
    func grantedCapabilities(for extensionId: String) -> [ExtensionCapability] {
        grants[extensionId]?
            .filter(\.isActive)
            .map(\.capability) ?? []
    }

    /// Checks whether an extension has a specific capability.
    func hasCapability(_ capability: ExtensionCapability, extensionId: String) -> Bool {
        grantedCapabilities(for: extensionId).contains(capability)
    }

    /// Checks whether a capability can be granted under the current policy.
    func canGrant(_ capability: ExtensionCapability) -> Bool {
        guard hostPermissions.contains(capability) else { return false }
        guard policy.maximumGrantableCapabilities.contains(capability) else { return false }
        guard !policy.alwaysDeniedCapabilities.contains(capability) else { return false }
        return true
    }

    // MARK: - Grant Management

    /// Grants a capability to an extension.
    @discardableResult
    func grant(
        capability: ExtensionCapability,
        to extensionId: String,
        source: PermissionGrant.GrantSource = .user
    ) -> PermissionGrant? {
        guard canGrant(capability) else { return nil }

        let grant = PermissionGrant(
            id: UUID(),
            extensionId: extensionId,
            capability: capability,
            grantedAt: Date(),
            grantedBy: source,
            expiresAt: policy.grantExpirationInterval.map { Date().addingTimeInterval($0) },
            isRevocable: true
        )

        var extensionGrants = grants[extensionId] ?? []
        // Remove existing grant for same capability
        extensionGrants.removeAll { $0.capability == capability }
        extensionGrants.append(grant)
        grants[extensionId] = extensionGrants

        permissionGranted.send(grant)
        return grant
    }

    /// Grants multiple capabilities at once.
    func grantAll(
        capabilities: [ExtensionCapability],
        to extensionId: String,
        source: PermissionGrant.GrantSource = .user
    ) {
        for capability in capabilities {
            grant(capability: capability, to: extensionId, source: source)
        }
    }

    /// Revokes a specific capability from an extension.
    func revoke(capability: ExtensionCapability, from extensionId: String) {
        guard var extensionGrants = grants[extensionId] else { return }

        let grant = extensionGrants.first { $0.capability == capability }
        guard grant?.isRevocable != false else { return }

        extensionGrants.removeAll { $0.capability == capability }
        grants[extensionId] = extensionGrants.isEmpty ? nil : extensionGrants

        permissionRevoked.send((extensionId, capability))
    }

    /// Revokes all capabilities from an extension.
    func revokeAll(from extensionId: String) {
        let capabilities = grantedCapabilities(for: extensionId)
        grants.removeValue(forKey: extensionId)

        for capability in capabilities {
            permissionRevoked.send((extensionId, capability))
        }
    }

    // MARK: - Permission Requests

    /// Creates a permission request for user approval.
    func requestPermission(
        capability: ExtensionCapability,
        for extensionId: String,
        extensionName: String,
        reason: String,
        isRequired: Bool = false
    ) {
        guard canGrant(capability) else { return }
        guard !hasCapability(capability, extensionId: extensionId) else { return }

        let request = PermissionRequest(
            id: UUID(),
            extensionId: extensionId,
            extensionName: extensionName,
            capability: capability,
            reason: reason,
            isRequired: isRequired,
            requestedAt: Date()
        )

        pendingRequests.append(request)
        permissionRequested.send(request)
    }

    /// Approves a pending permission request.
    func approveRequest(_ requestId: UUID) {
        guard let index = pendingRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pendingRequests.remove(at: index)
        grant(capability: request.capability, to: request.extensionId, source: .user)
    }

    /// Denies a pending permission request.
    func denyRequest(_ requestId: UUID) {
        pendingRequests.removeAll { $0.id == requestId }
    }

    // MARK: - Inheritance Resolution

    /// Resolves the effective permissions for an extension based on manifest, policy, and user grants.
    func resolveEffectivePermissions(
        extensionId: String,
        manifestCapabilities: [ExtensionCapability],
        developerTrustLevel: Int
    ) -> [ExtensionCapability] {
        var effective: Set<ExtensionCapability> = []

        // Start with manifest-declared capabilities
        for capability in manifestCapabilities {
            guard canGrant(capability) else { continue }

            if policy.requireUserApprovalForAll {
                // Only include if user has explicitly granted
                if hasCapability(capability, extensionId: extensionId) {
                    effective.insert(capability)
                }
            } else if policy.autoGrantForTrustedDevelopers && developerTrustLevel >= 2 {
                effective.insert(capability)
            } else {
                // Safe capabilities auto-granted, dangerous ones need approval
                if isSafeCapability(capability) {
                    effective.insert(capability)
                } else if hasCapability(capability, extensionId: extensionId) {
                    effective.insert(capability)
                }
            }
        }

        return Array(effective)
    }

    // MARK: - Cleanup

    /// Removes expired grants across all extensions.
    func cleanupExpiredGrants() {
        for (extensionId, extensionGrants) in grants {
            let active = extensionGrants.filter(\.isActive)
            if active.isEmpty {
                grants.removeValue(forKey: extensionId)
            } else {
                grants[extensionId] = active
            }
        }
    }

    // MARK: - Private

    private func isSafeCapability(_ capability: ExtensionCapability) -> Bool {
        switch capability {
        case .readWalletAddress, .displayUI, .readContractState:
            return true
        case .proposeTransaction, .readHealthData, .readTrinityContext,
             .readTransactionHistory, .readPortfolioData, .sendNotifications, .networkAccess:
            return false
        }
    }
}
