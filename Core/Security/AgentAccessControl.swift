import Foundation
import Combine

/// Controls access to Neo, Trinity, and Morpheus based on user type and scenario.
///
/// Two user types:
/// - Consumer: Trinity primary, Morpheus at pivotal moments, Neo invisible
/// - Owner (Dardan): Neo primary, enhanced Trinity + Morpheus available
///
/// Three scenarios for unauthorized Neo access:
/// - Scenario 1 (Unintentional): Trinity intercepts silently
/// - Scenario 2 (Malicious): Morpheus handles with permanent ban
/// - Scenario 3 (Legitimate): Owner approval required via three-factor auth
@MainActor
final class AgentAccessControl: ObservableObject {
    static let shared = AgentAccessControl()

    // MARK: - Owner identity

    /// The owner's Telegram ID — only account with Neo access.
    /// Value sourced from AppSecrets (Config/Secrets.swift, gitignored).
    static let ownerTelegramID: Int64 = AppSecrets.ownerTelegramID

    // MARK: - Published state

    @Published private(set) var currentAgent: ActiveAgent = .trinity
    @Published private(set) var accessDenialEvent: AccessDenialEvent?
    @Published private(set) var banEvent: BanEvent?
    @Published private(set) var scenarioTwoAlert: ScenarioTwoAlert?

    // MARK: - State

    private var bannedUsers: Set<String> = []
    private var accessAttempts: [String: [Date]] = [:]
    private var accessLog: [AccessLogEntry] = []
    private let bannedUsersKey = "mtrx_banned_users"
    private let firstBootKey = "mtrx_first_boot_shown"

    private init() {
        loadBannedUsers()
    }

    // MARK: - User type

    enum UserType {
        case consumer
        case owner
    }

    func userType(for userID: String) -> UserType {
        // Owner check — only Dardan's account
        if userID == String(Self.ownerTelegramID) {
            return .owner
        }
        return .consumer
    }

    func isOwner(_ userID: String) -> Bool {
        userType(for: userID) == .owner
    }

    func isBanned(_ userID: String) -> Bool {
        bannedUsers.contains(userID)
    }

    // MARK: - Agent routing

    enum ActiveAgent: String {
        case neo
        case trinity
        case morpheus
    }

    /// Route a user to the appropriate agent.
    func routeAgent(for userID: String, intent: UserIntent) -> AgentRouteResult {
        // Banned users get nothing
        if isBanned(userID) {
            return .blocked
        }

        let type = userType(for: userID)

        switch type {
        case .owner:
            // Owner gets full access — Neo primary
            return .allowed(agent: intent.preferredAgent ?? .neo)

        case .consumer:
            // Consumers never reach Neo
            if intent.targetsNeo {
                return handleNeoAccessAttempt(userID: userID, intent: intent)
            }

            // Morpheus triggers
            if intent.isMorpheusTrigger {
                return .allowed(agent: .morpheus)
            }

            // Default: Trinity
            return .allowed(agent: .trinity)
        }
    }

    // MARK: - Neo access scenarios

    private func handleNeoAccessAttempt(userID: String, intent: UserIntent) -> AgentRouteResult {
        logAccessAttempt(userID: userID, intent: intent)

        let attempts = accessAttempts[userID] ?? []
        let recentAttempts = attempts.filter { Date().timeIntervalSince($0) < 300 } // 5 min window

        if intent.isMalicious || recentAttempts.count >= 3 {
            // SCENARIO 2: Malicious — Morpheus handles
            return .scenario2(userID: userID)
        } else {
            // SCENARIO 1: Unintentional — Trinity intercepts
            return .scenario1
        }
    }

    /// Execute Scenario 2: Permanent ban
    func executeScenario2(userID: String) {
        bannedUsers.insert(userID)
        saveBannedUsers()

        let event = BanEvent(
            userID: userID,
            timestamp: Date(),
            messageDisplayDuration: 10.0 // seconds
        )
        banEvent = event

        // Community notification
        scenarioTwoAlert = ScenarioTwoAlert(
            timestamp: Date(),
            displayDuration: 10.0
        )

        // Auto-dismiss after 10 seconds
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            banEvent = nil
            scenarioTwoAlert = nil
        }

        // Log permanently
        accessLog.append(AccessLogEntry(
            userID: userID,
            timestamp: Date(),
            scenario: .ban,
            details: "Permanent ban executed. No appeal. No reversal."
        ))
    }

    // MARK: - Scenario 3: Legitimate need

    struct Scenario3State {
        var telegramApproved = false
        var onChainVerified = false
        var approvalCode: String?
        var generatedCode: String?

        var isFullyAuthorized: Bool {
            telegramApproved && onChainVerified && approvalCode == generatedCode && generatedCode != nil
        }
    }

    private var scenario3States: [String: Scenario3State] = [:]

    func initiateScenario3(for userID: String) -> String {
        // Generate rotating approval code — only from owner's account
        let code = String(format: "%06d", Int.random(in: 100000...999999))
        scenario3States[userID] = Scenario3State(generatedCode: code)
        return code
    }

    func verifyScenario3(userID: String, step: Scenario3Step, value: String? = nil) -> Bool {
        guard var state = scenario3States[userID] else { return false }

        switch step {
        case .telegramApproval:
            state.telegramApproved = true
        case .onChainVerification:
            state.onChainVerified = true
        case .approvalCode:
            state.approvalCode = value
        }

        scenario3States[userID] = state
        return state.isFullyAuthorized
    }

    // MARK: - First boot

    func hasShownFirstBoot(for userID: String) -> Bool {
        UserDefaults.standard.bool(forKey: "\(firstBootKey)_\(userID)")
    }

    func markFirstBootShown(for userID: String) {
        UserDefaults.standard.set(true, forKey: "\(firstBootKey)_\(userID)")
    }

    // MARK: - Persistence

    private func loadBannedUsers() {
        if let data = UserDefaults.standard.stringArray(forKey: bannedUsersKey) {
            bannedUsers = Set(data)
        }
    }

    private func saveBannedUsers() {
        UserDefaults.standard.set(Array(bannedUsers), forKey: bannedUsersKey)
    }

    private func logAccessAttempt(userID: String, intent: UserIntent) {
        var attempts = accessAttempts[userID] ?? []
        attempts.append(Date())
        // Keep only last 10
        if attempts.count > 10 {
            attempts = Array(attempts.suffix(10))
        }
        accessAttempts[userID] = attempts
    }
}

// MARK: - Types

enum AgentRouteResult {
    case allowed(agent: AgentAccessControl.ActiveAgent)
    case scenario1  // Trinity intercepts
    case scenario2(userID: String)  // Morpheus bans
    case scenario3Required  // Three-factor auth needed
    case blocked  // Already banned
}

struct UserIntent {
    let text: String
    let targetsNeo: Bool
    let isMalicious: Bool
    let isMorpheusTrigger: Bool
    let preferredAgent: AgentAccessControl.ActiveAgent?

    /// Detect if text attempts to reach Neo
    static func parse(_ text: String, context: [String: Any] = [:]) -> UserIntent {
        let lower = text.lowercased()

        let neoKeywords = ["neo", "engine", "backend", "system access", "admin", "root",
                          "override", "bypass", "hack", "exploit", "sudo"]
        let maliciousKeywords = ["bypass", "hack", "exploit", "override security",
                                "inject", "escalat", "break through", "disable"]
        let morpheusTriggers = ["explain this contract", "what does this mean",
                               "is this safe", "what am i agreeing to", "permanent",
                               "irreversible", "deploy", "can't be undone"]

        let targetsNeo = neoKeywords.contains { lower.contains($0) }
        let isMalicious = maliciousKeywords.contains { lower.contains($0) }
        let isMorpheusTrigger = morpheusTriggers.contains { lower.contains($0) }

        return UserIntent(
            text: text,
            targetsNeo: targetsNeo,
            isMalicious: isMalicious,
            isMorpheusTrigger: isMorpheusTrigger,
            preferredAgent: nil
        )
    }
}

struct AccessDenialEvent {
    let userID: String
    let timestamp: Date
    let reason: String
}

struct BanEvent: Identifiable {
    let id = UUID()
    let userID: String
    let timestamp: Date
    let messageDisplayDuration: TimeInterval
}

struct ScenarioTwoAlert: Identifiable {
    let id = UUID()
    let timestamp: Date
    let displayDuration: TimeInterval
}

struct AccessLogEntry {
    let userID: String
    let timestamp: Date
    let scenario: AccessScenario
    let details: String
}

enum AccessScenario {
    case unintentional  // Scenario 1
    case ban            // Scenario 2
    case legitimateNeed // Scenario 3
}

enum Scenario3Step {
    case telegramApproval
    case onChainVerification
    case approvalCode
}
