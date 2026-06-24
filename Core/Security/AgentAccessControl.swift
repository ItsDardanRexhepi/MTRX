import Foundation
import Combine

/// Controls access to Neo, Trinity, and Morpheus based on user type and scenario.
///
/// ⚠️ UX-ONLY — NOT THE SECURITY BOUNDARY.
/// This app ships to user devices and can be decompiled, so nothing here is a
/// real enforcement gate. The authoritative Morpheus security gate lives
/// server-side (0pnMatrx `runtime/security/morpheus.py`), consulted before every
/// Neo action. This class is the *client* of that gate: it provides instant
/// classification hints and routing for UX (which agent to show, what warning to
/// surface), but every security-relevant decision is decided — and re-decided —
/// on the server. Local state (bans, classifications) is an optimistic mirror
/// that must reconcile with the server; never treat it as binding. (Phase 3
/// wires the real ban authority + on-chain record on the server.)
///
/// Two user types:
/// - Consumer: Trinity primary, Morpheus at pivotal moments, Neo invisible
/// - Owner (Dardan): Neo primary, enhanced Trinity + Morpheus available
///   (owner identity is the Apple ID that created this install; OTP verification — Phase 2)
///
/// Three scenarios for unauthorized Neo access (the *server* makes the binding call):
/// - Scenario 1 (Unintentional): Trinity intercepts silently
/// - Scenario 2 (Malicious): Morpheus handles with permanent ban
/// - Scenario 3 (Legitimate): Owner approval required (OTP-verified owner — Phase 2)
@MainActor
final class AgentAccessControl: ObservableObject {
    static let shared = AgentAccessControl()

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
        // The Apple account that signed in and created this install's
        // demo wallet IS the platform owner on this device.
        if !userID.isEmpty,
           userID == UserDefaults.standard.string(forKey: "com.mtrx.appleUserId") {
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

    /// Execute Scenario 2: Permanent ban.
    ///
    /// UX MIRROR ONLY. The authoritative, permanent ban is recorded server-side
    /// (DB + on-chain) by the Morpheus security gate — Phase 3. This local set
    /// gives instant feedback, but a determined client could clear it; the server
    /// rejects a banned identity at the boundary regardless. Reconcile with the
    /// server ban list; never rely on this as enforcement.
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
        var onChainVerified = false
        var approvalCode: String?
        var generatedCode: String?

        var isFullyAuthorized: Bool {
            onChainVerified && approvalCode == generatedCode && generatedCode != nil
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

        // UX HINT ONLY — fast local keyword heuristics to pick which agent/warning
        // to show immediately. The binding classification (unintentional / malicious
        // / legitimate) is made server-side by the Morpheus gate (Phase 3); never ban
        // or grant on the strength of these client-side keywords alone.
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
    case onChainVerification
    case approvalCode
}
