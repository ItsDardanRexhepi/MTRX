//
//  ContractModel.swift
//  MTRX
//
//  SwiftData contract persistence model covering all 30 MTRX blockchain components.
//

import Foundation
import SwiftData

// MARK: - Contract Type

/// Enumerates all 30 MTRX blockchain components.
enum ContractType: String, Codable, CaseIterable {
    // Core Infrastructure
    case wallet              // 1. Smart Account Wallet (ERC-4337)
    case gasManager          // 2. Gas Manager / Paymaster
    case bridgeRouter        // 3. Cross-Chain Bridge Router
    case oracleAggregator    // 4. Oracle Aggregator
    case identityRegistry    // 5. Decentralized Identity Registry

    // DeFi Components
    case swapRouter          // 6. DEX Swap Router
    case lendingPool         // 7. Lending Pool
    case yieldVault          // 8. Yield Vault
    case stakingPool         // 9. Staking Pool
    case liquidityManager    // 10. Liquidity Position Manager

    // Derivatives & Advanced
    case perpetualEngine     // 11. Perpetual Futures Engine
    case optionsVault        // 12. Options Vault
    case syntheticMinter     // 13. Synthetic Asset Minter
    case insurancePool       // 14. Insurance Pool
    case flashLoanProvider   // 15. Flash Loan Provider

    // Governance & Social
    case governanceModule    // 16. DAO Governance Module
    case treasuryManager     // 17. Treasury Manager
    case reputationTracker   // 18. Reputation Tracker
    case socialRecovery      // 19. Social Recovery Module
    case multisigVault       // 20. Multisig Vault

    // NFT & Digital Assets
    case nftMarketplace      // 21. NFT Marketplace
    case nftVault            // 22. NFT Collateral Vault
    case tokenLauncher       // 23. Token Launcher
    case vestingManager      // 24. Vesting Schedule Manager
    case royaltyDistributor  // 25. Royalty Distributor

    // Compliance & Privacy
    case kycVerifier         // 26. KYC/AML Verifier
    case privacyMixer        // 27. Privacy Mixer (zk-based)
    case complianceOracle    // 28. Compliance Oracle
    case auditLogger         // 29. On-Chain Audit Logger
    case emergencyBrake      // 30. Emergency Brake / Circuit Breaker

    /// Human-readable component name.
    var displayName: String {
        switch self {
        case .wallet:              return "Smart Account Wallet"
        case .gasManager:          return "Gas Manager"
        case .bridgeRouter:        return "Cross-Chain Bridge"
        case .oracleAggregator:    return "Oracle Aggregator"
        case .identityRegistry:    return "Identity Registry"
        case .swapRouter:          return "DEX Swap Router"
        case .lendingPool:         return "Lending Pool"
        case .yieldVault:          return "Yield Vault"
        case .stakingPool:         return "Staking Pool"
        case .liquidityManager:    return "Liquidity Manager"
        case .perpetualEngine:     return "Perpetual Futures"
        case .optionsVault:        return "Options Vault"
        case .syntheticMinter:     return "Synthetic Minter"
        case .insurancePool:       return "Insurance Pool"
        case .flashLoanProvider:   return "Flash Loan Provider"
        case .governanceModule:    return "Governance"
        case .treasuryManager:     return "Treasury"
        case .reputationTracker:   return "Reputation"
        case .socialRecovery:      return "Social Recovery"
        case .multisigVault:       return "Multisig Vault"
        case .nftMarketplace:      return "NFT Marketplace"
        case .nftVault:            return "NFT Vault"
        case .tokenLauncher:       return "Token Launcher"
        case .vestingManager:      return "Vesting Manager"
        case .royaltyDistributor:  return "Royalty Distributor"
        case .kycVerifier:         return "KYC Verifier"
        case .privacyMixer:        return "Privacy Mixer"
        case .complianceOracle:    return "Compliance Oracle"
        case .auditLogger:         return "Audit Logger"
        case .emergencyBrake:      return "Emergency Brake"
        }
    }

    /// Category grouping for UI display.
    var category: ComponentCategory {
        switch self {
        case .wallet, .gasManager, .bridgeRouter, .oracleAggregator, .identityRegistry:
            return .coreInfrastructure
        case .swapRouter, .lendingPool, .yieldVault, .stakingPool, .liquidityManager:
            return .defi
        case .perpetualEngine, .optionsVault, .syntheticMinter, .insurancePool, .flashLoanProvider:
            return .derivativesAdvanced
        case .governanceModule, .treasuryManager, .reputationTracker, .socialRecovery, .multisigVault:
            return .governanceSocial
        case .nftMarketplace, .nftVault, .tokenLauncher, .vestingManager, .royaltyDistributor:
            return .nftDigitalAssets
        case .kycVerifier, .privacyMixer, .complianceOracle, .auditLogger, .emergencyBrake:
            return .compliancePrivacy
        }
    }
}

// MARK: - Component Category

enum ComponentCategory: String, Codable, CaseIterable {
    case coreInfrastructure
    case defi
    case derivativesAdvanced
    case governanceSocial
    case nftDigitalAssets
    case compliancePrivacy

    var displayName: String {
        switch self {
        case .coreInfrastructure:   return "Core Infrastructure"
        case .defi:                  return "DeFi"
        case .derivativesAdvanced:   return "Derivatives & Advanced"
        case .governanceSocial:      return "Governance & Social"
        case .nftDigitalAssets:      return "NFT & Digital Assets"
        case .compliancePrivacy:     return "Compliance & Privacy"
        }
    }
}

// MARK: - Contract Status

enum ContractStatus: String, Codable, CaseIterable {
    case draft
    case deploying
    case active
    case paused
    case deprecated
    case destroyed
}

// MARK: - Contract Party

struct ContractParty: Codable, Equatable {
    let address: String
    let role: String
    let addedAt: Date
}

// MARK: - ContractRecord Model

@Model
final class ContractRecord {
    // MARK: - Primary Properties

    @Attribute(.unique) var id: UUID
    var address: String
    var contractType: String
    var component: String
    var deployedAt: Date
    var status: String
    var chainId: Int
    var deploymentHash: String?

    // MARK: - Encoded Properties

    var abiData: Data?
    var parametersData: Data?
    var partiesData: Data?

    // MARK: - Metadata

    var version: String
    var compiler: String?
    var isVerified: Bool
    var isProxy: Bool
    var implementationAddress: String?

    // MARK: - Relationship

    var user: UserProfile?

    // MARK: - Computed Accessors

    var type: ContractType {
        get { ContractType(rawValue: contractType) ?? .wallet }
        set { contractType = newValue.rawValue }
    }

    var contractStatus: ContractStatus {
        get { ContractStatus(rawValue: status) ?? .draft }
        set { status = newValue.rawValue }
    }

    var abi: [[String: Any]]? {
        guard let data = abiData else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    var parameters: [String: String] {
        get {
            guard let data = parametersData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            parametersData = try? JSONEncoder().encode(newValue)
        }
    }

    var parties: [ContractParty] {
        get {
            guard let data = partiesData else { return [] }
            return (try? JSONDecoder().decode([ContractParty].self, from: data)) ?? []
        }
        set {
            partiesData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        address: String,
        type: ContractType,
        chainId: Int = 1,
        version: String = "1.0.0"
    ) {
        self.id = id
        self.address = address
        self.contractType = type.rawValue
        self.component = type.rawValue
        self.deployedAt = Date()
        self.status = ContractStatus.draft.rawValue
        self.chainId = chainId
        self.version = version
        self.isVerified = false
        self.isProxy = false
    }

    // MARK: - Methods

    /// Sets the ABI from a JSON array.
    func setABI(_ abi: [[String: Any]]) throws {
        abiData = try JSONSerialization.data(withJSONObject: abi)
    }

    /// Adds a party to the contract.
    func addParty(address: String, role: String) {
        var current = parties
        current.append(ContractParty(address: address, role: role, addedAt: Date()))
        parties = current
    }

    /// Transitions the contract to a new status with validation.
    func transition(to newStatus: ContractStatus) -> Bool {
        let validTransitions: [ContractStatus: Set<ContractStatus>] = [
            .draft:       [.deploying],
            .deploying:   [.active, .draft],
            .active:      [.paused, .deprecated, .destroyed],
            .paused:      [.active, .deprecated, .destroyed],
            .deprecated:  [.destroyed],
            .destroyed:   []
        ]

        guard let allowed = validTransitions[contractStatus],
              allowed.contains(newStatus) else {
            return false
        }
        contractStatus = newStatus
        return true
    }
}

// MARK: - Fetch Descriptors

extension ContractRecord {
    /// Fetch active contracts of a specific type.
    static func activeContracts(ofType type: ContractType) -> FetchDescriptor<ContractRecord> {
        let typeRaw = type.rawValue
        let activeRaw = ContractStatus.active.rawValue
        let predicate = #Predicate<ContractRecord> { record in
            record.contractType == typeRaw && record.status == activeRaw
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.deployedAt, order: .reverse)]
        return descriptor
    }
}
