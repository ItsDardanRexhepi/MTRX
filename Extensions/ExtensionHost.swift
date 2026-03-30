//
//  ExtensionHost.swift
//  MTRX
//
//  App Extension hosting model. Defines extension lifecycle, data access APIs,
//  and the protocol for third-party extensions within MTRX.
//

import Foundation
import Combine

// MARK: - Extension Lifecycle State

enum ExtensionLifecycleState: String, CaseIterable {
    case unloaded
    case loading
    case ready
    case running
    case suspended
    case terminated
    case errored

    var isActive: Bool {
        self == .ready || self == .running
    }
}

// MARK: - Extension Capability

/// Capabilities that an extension can declare and the host can grant.
enum ExtensionCapability: String, Codable, CaseIterable {
    case readWalletAddress
    case readTransactionHistory
    case readPortfolioData
    case readContractState
    case proposeTransaction
    case readHealthData
    case readTrinityContext
    case displayUI
    case sendNotifications
    case networkAccess
}

// MARK: - Extension Manifest

/// Metadata describing a third-party extension.
struct ExtensionManifest: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let version: String
    let developer: String
    let description: String
    let capabilities: [ExtensionCapability]
    let entryPoint: String
    let minimumHostVersion: String
    let iconName: String?
    let category: ExtensionCategory

    enum ExtensionCategory: String, Codable, CaseIterable {
        case defi
        case analytics
        case social
        case security
        case utility
        case nft
        case governance
    }
}

// MARK: - Extension Data Access Protocol

/// API surface exposed to extensions for reading host data.
protocol ExtensionDataAccess: AnyObject {
    /// Returns the current wallet address, if permitted.
    func walletAddress() async throws -> String?

    /// Returns recent transactions matching a filter.
    func transactions(filter: ExtensionTransactionFilter) async throws -> [ExtensionTransactionDTO]

    /// Returns the current portfolio snapshot.
    func portfolioSnapshot() async throws -> ExtensionPortfolioDTO?

    /// Returns the state of a specific contract.
    func contractState(address: String) async throws -> ExtensionContractDTO?

    /// Proposes a transaction for user approval (does not execute).
    func proposeTransaction(_ proposal: ExtensionTransactionProposal) async throws -> String
}

// MARK: - Extension DTOs

struct ExtensionTransactionFilter: Codable {
    let component: String?
    let status: String?
    let limit: Int
}

struct ExtensionTransactionDTO: Codable, Identifiable {
    let id: String
    let hash: String
    let from: String
    let to: String
    let value: String
    let status: String
    let timestamp: Date
    let component: String
}

struct ExtensionPortfolioDTO: Codable {
    let totalValueUSD: String
    let tokenCount: Int
    let defiPositionCount: Int
    let lastUpdated: Date
}

struct ExtensionContractDTO: Codable {
    let address: String
    let type: String
    let status: String
    let chainId: Int
}

struct ExtensionTransactionProposal: Codable {
    let to: String
    let value: String
    let data: Data?
    let chainId: Int
    let description: String
}

// MARK: - Extension Host Protocol

/// Protocol defining the host environment for MTRX extensions.
protocol ExtensionHostProtocol: AnyObject {
    /// Loads an extension from its manifest.
    func loadExtension(manifest: ExtensionManifest) async throws

    /// Unloads a running extension.
    func unloadExtension(id: String) async throws

    /// Returns the current lifecycle state of an extension.
    func state(of extensionId: String) -> ExtensionLifecycleState

    /// Returns the data access API scoped to an extension's permissions.
    func dataAccess(for extensionId: String) -> ExtensionDataAccess?

    /// Sends a message to a running extension.
    func sendMessage(to extensionId: String, message: ExtensionMessage) async throws

    /// Receives messages from extensions.
    var extensionMessages: AnyPublisher<ExtensionMessage, Never> { get }
}

// MARK: - Extension Message

struct ExtensionMessage: Identifiable, Codable {
    let id: UUID
    let extensionId: String
    let type: MessageType
    let payload: Data
    let timestamp: Date

    enum MessageType: String, Codable {
        case request
        case response
        case event
        case error
    }
}

// MARK: - Extension Host Implementation

/// Concrete host for managing third-party extension lifecycle and data access.
final class ExtensionHost: ObservableObject, ExtensionHostProtocol {

    // MARK: - Published State

    @Published private(set) var loadedExtensions: [String: ExtensionLifecycleState] = [:]
    @Published private(set) var activeExtensionCount: Int = 0

    // MARK: - Publishers

    private let messageSubject = PassthroughSubject<ExtensionMessage, Never>()
    var extensionMessages: AnyPublisher<ExtensionMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    // MARK: - State

    private var manifests: [String: ExtensionManifest] = [:]
    private var dataAccessProviders: [String: ScopedDataAccess] = [:]
    private var sandboxes: [String: ExtensionSandbox] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dependencies

    private let registry: ExtensionRegistry
    private let permissionManager: ExtensionPermissions

    // MARK: - Initialization

    init(registry: ExtensionRegistry, permissionManager: ExtensionPermissions) {
        self.registry = registry
        self.permissionManager = permissionManager
    }

    // MARK: - Lifecycle Management

    func loadExtension(manifest: ExtensionManifest) async throws {
        guard registry.isApproved(extensionId: manifest.id) else {
            throw ExtensionHostError.extensionNotApproved(manifest.id)
        }

        guard loadedExtensions[manifest.id] == nil ||
              loadedExtensions[manifest.id] == .unloaded else {
            throw ExtensionHostError.alreadyLoaded(manifest.id)
        }

        loadedExtensions[manifest.id] = .loading
        manifests[manifest.id] = manifest

        // Create sandboxed environment
        let sandbox = ExtensionSandbox(extensionId: manifest.id)
        sandboxes[manifest.id] = sandbox

        // Create scoped data access
        let grantedCapabilities = permissionManager.grantedCapabilities(for: manifest.id)
        let scopedAccess = ScopedDataAccess(
            extensionId: manifest.id,
            allowedCapabilities: Set(grantedCapabilities)
        )
        dataAccessProviders[manifest.id] = scopedAccess

        loadedExtensions[manifest.id] = .ready
        updateActiveCount()
    }

    func unloadExtension(id: String) async throws {
        guard loadedExtensions[id] != nil else {
            throw ExtensionHostError.notLoaded(id)
        }

        loadedExtensions[id] = .terminated
        sandboxes[id]?.terminate()
        sandboxes.removeValue(forKey: id)
        dataAccessProviders.removeValue(forKey: id)
        manifests.removeValue(forKey: id)
        loadedExtensions.removeValue(forKey: id)
        updateActiveCount()
    }

    func state(of extensionId: String) -> ExtensionLifecycleState {
        loadedExtensions[extensionId] ?? .unloaded
    }

    func dataAccess(for extensionId: String) -> ExtensionDataAccess? {
        dataAccessProviders[extensionId]
    }

    func sendMessage(to extensionId: String, message: ExtensionMessage) async throws {
        guard state(of: extensionId).isActive else {
            throw ExtensionHostError.extensionNotActive(extensionId)
        }
        // Route message to the extension's sandbox process
        messageSubject.send(message)
    }

    // MARK: - Private

    private func updateActiveCount() {
        activeExtensionCount = loadedExtensions.values.filter(\.isActive).count
    }
}

// MARK: - Scoped Data Access

/// Data access implementation scoped to an extension's granted capabilities.
final class ScopedDataAccess: ExtensionDataAccess {
    private let extensionId: String
    private let allowedCapabilities: Set<ExtensionCapability>

    init(extensionId: String, allowedCapabilities: Set<ExtensionCapability>) {
        self.extensionId = extensionId
        self.allowedCapabilities = allowedCapabilities
    }

    func walletAddress() async throws -> String? {
        guard allowedCapabilities.contains(.readWalletAddress) else {
            throw ExtensionHostError.capabilityDenied(.readWalletAddress)
        }
        // Placeholder: Return wallet address from SwiftDataStore
        return nil
    }

    func transactions(filter: ExtensionTransactionFilter) async throws -> [ExtensionTransactionDTO] {
        guard allowedCapabilities.contains(.readTransactionHistory) else {
            throw ExtensionHostError.capabilityDenied(.readTransactionHistory)
        }
        return []
    }

    func portfolioSnapshot() async throws -> ExtensionPortfolioDTO? {
        guard allowedCapabilities.contains(.readPortfolioData) else {
            throw ExtensionHostError.capabilityDenied(.readPortfolioData)
        }
        return nil
    }

    func contractState(address: String) async throws -> ExtensionContractDTO? {
        guard allowedCapabilities.contains(.readContractState) else {
            throw ExtensionHostError.capabilityDenied(.readContractState)
        }
        return nil
    }

    func proposeTransaction(_ proposal: ExtensionTransactionProposal) async throws -> String {
        guard allowedCapabilities.contains(.proposeTransaction) else {
            throw ExtensionHostError.capabilityDenied(.proposeTransaction)
        }
        return UUID().uuidString
    }
}

// MARK: - Errors

enum ExtensionHostError: Error, LocalizedError {
    case extensionNotApproved(String)
    case alreadyLoaded(String)
    case notLoaded(String)
    case extensionNotActive(String)
    case capabilityDenied(ExtensionCapability)
    case sandboxViolation(String)
    case communicationFailed(String)

    var errorDescription: String? {
        switch self {
        case .extensionNotApproved(let id):   return "Extension '\(id)' is not approved."
        case .alreadyLoaded(let id):          return "Extension '\(id)' is already loaded."
        case .notLoaded(let id):              return "Extension '\(id)' is not loaded."
        case .extensionNotActive(let id):     return "Extension '\(id)' is not active."
        case .capabilityDenied(let cap):      return "Capability '\(cap.rawValue)' denied."
        case .sandboxViolation(let detail):   return "Sandbox violation: \(detail)"
        case .communicationFailed(let msg):   return "Communication failed: \(msg)"
        }
    }
}
