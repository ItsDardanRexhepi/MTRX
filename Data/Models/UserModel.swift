//
//  UserModel.swift
//  MTRX
//
//  SwiftData user persistence model with wallet, preferences, and Trinity personalization.
//

import Foundation
import SwiftData

// MARK: - User Preferences

/// Codable structure for user-configurable preferences.
struct UserPreferences: Codable, Equatable {
    var defaultChainId: Int
    var gasStrategy: GasStrategy
    var notificationsEnabled: Bool
    var biometricAuthEnabled: Bool
    var defaultCurrency: String
    var slippageTolerance: Double
    var trinityVoiceEnabled: Bool
    var trinityProactiveMode: Bool
    var theme: AppTheme

    enum GasStrategy: String, Codable, CaseIterable {
        case slow
        case standard
        case fast
        case custom
    }

    enum AppTheme: String, Codable, CaseIterable {
        case system
        case light
        case dark
    }

    static var defaults: UserPreferences {
        UserPreferences(
            defaultChainId: 1,
            gasStrategy: .standard,
            notificationsEnabled: true,
            biometricAuthEnabled: true,
            defaultCurrency: "USD",
            slippageTolerance: 0.005,
            trinityVoiceEnabled: true,
            trinityProactiveMode: true,
            theme: .system
        )
    }
}

// MARK: - Trinity Personalization

/// Codable structure capturing Trinity AI personalization state.
struct TrinityPersonalization: Codable, Equatable {
    var communicationStyle: CommunicationStyle
    var expertiseLevel: ExpertiseLevel
    var proactiveAlertThreshold: Double
    var learnedPatterns: [String]
    var preferredComponents: [String]
    var contextWindowSize: Int

    enum CommunicationStyle: String, Codable, CaseIterable {
        case concise
        case detailed
        case conversational
        case technical
    }

    enum ExpertiseLevel: String, Codable, CaseIterable {
        case beginner
        case intermediate
        case advanced
        case expert
    }

    static var defaults: TrinityPersonalization {
        TrinityPersonalization(
            communicationStyle: .conversational,
            expertiseLevel: .intermediate,
            proactiveAlertThreshold: 0.7,
            learnedPatterns: [],
            preferredComponents: [],
            contextWindowSize: 10
        )
    }
}

// MARK: - UserProfile Model

@Model
final class UserProfile {
    // MARK: - Primary Properties

    @Attribute(.unique) var id: UUID
    var walletAddress: String
    var displayName: String
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Encoded Properties

    var preferencesData: Data
    var trinityPersonalizationData: Data

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \TransactionRecord.user)
    var transactions: [TransactionRecord]

    @Relationship(deleteRule: .cascade, inverse: \ContractRecord.user)
    var contracts: [ContractRecord]

    // MARK: - Computed Accessors

    var preferences: UserPreferences {
        get {
            (try? JSONDecoder().decode(UserPreferences.self, from: preferencesData))
                ?? .defaults
        }
        set {
            preferencesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var trinityPersonalization: TrinityPersonalization {
        get {
            (try? JSONDecoder().decode(TrinityPersonalization.self, from: trinityPersonalizationData))
                ?? .defaults
        }
        set {
            trinityPersonalizationData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        walletAddress: String,
        displayName: String,
        preferences: UserPreferences = .defaults,
        trinityPersonalization: TrinityPersonalization = .defaults
    ) {
        self.id = id
        self.walletAddress = walletAddress
        self.displayName = displayName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.preferencesData = (try? JSONEncoder().encode(preferences)) ?? Data()
        self.trinityPersonalizationData = (try? JSONEncoder().encode(trinityPersonalization)) ?? Data()
        self.transactions = []
        self.contracts = []
    }

    // MARK: - Methods

    /// Updates the last-modified timestamp.
    func touch() {
        updatedAt = Date()
    }

    /// Returns the count of transactions matching a given status.
    func transactionCount(withStatus status: TransactionStatus) -> Int {
        transactions.filter { $0.status == status.rawValue }.count
    }

    /// Returns contracts filtered by component type.
    func contracts(forComponent component: String) -> [ContractRecord] {
        contracts.filter { $0.component == component }
    }
}
