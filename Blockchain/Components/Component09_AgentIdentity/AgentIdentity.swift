// AgentIdentity.swift
// MTRX Blockchain - Components - Agent Identity
//
// AI agent identity: DID, capability delegation, trust scoring

import Foundation

// MARK: - Protocols

protocol AgentIdentityDelegate: AnyObject {
    func agentIdentity(_ manager: AgentIdentity, didRegister agentDID: String)
    func agentIdentity(_ manager: AgentIdentity, didDelegateCapability capabilityId: String)
    func agentIdentity(_ manager: AgentIdentity, trustScoreUpdated agentDID: String, score: Double)
}

// MARK: - Data Models

struct AgentDID {
    let did: String // did:mtrx:agent:<id>
    let ownerDID: String
    let agentType: AgentType
    let capabilities: [AgentCapability]
    let trustScore: Double
    let registeredAt: Date
    let lastActiveAt: Date
    let isActive: Bool
}

enum AgentType: String, Codable {
    case autonomous, semiAutonomous, supervised, restricted
}

struct AgentCapability {
    let capabilityId: String
    let name: String
    let scope: CapabilityScope
    let maxValuePerAction: UInt64
    let dailyLimit: UInt64
    let expiresAt: Date?
    let delegatedBy: String
    let isRevoked: Bool
}

enum CapabilityScope: String, Codable {
    case payments, trading, attestations, governance, dataAccess, contractExecution, all
}

struct TrustScore {
    let agentDID: String
    let overallScore: Double // 0.0 - 1.0
    let components: TrustComponents
    let lastUpdated: Date
    let totalActions: Int
    let successfulActions: Int
}

struct TrustComponents {
    let reliability: Double
    let accuracy: Double
    let compliance: Double
    let history: Double
    let peerReview: Double
}

struct AgentAction {
    let actionId: String
    let agentDID: String
    let actionType: String
    let capabilityUsed: String
    let success: Bool
    let timestamp: Date
    let valueInvolved: UInt64
}

enum AgentIdentityError: Error, LocalizedError {
    case agentNotFound
    case capabilityDenied
    case capabilityExpired
    case capabilityRevoked
    case trustScoreTooLow(required: Double, current: Double)
    case dailyLimitExceeded
    case ownerAuthRequired

    var errorDescription: String? {
        switch self {
        case .agentNotFound: return "Agent identity not found."
        case .capabilityDenied: return "Agent does not have this capability."
        case .capabilityExpired: return "Capability has expired."
        case .capabilityRevoked: return "Capability has been revoked."
        case .trustScoreTooLow(let req, let cur): return "Trust score too low. Required: \(req), Current: \(cur)"
        case .dailyLimitExceeded: return "Daily action limit exceeded."
        case .ownerAuthRequired: return "Owner authorization required for this action."
        }
    }
}

// MARK: - AgentIdentity

final class AgentIdentity {

    // MARK: - Properties

    weak var delegate: AgentIdentityDelegate?

    private let identityManager: IdentityManager
    private let easManager: EASManager
    private var agents: [String: AgentDID] = [:]
    private var trustScores: [String: TrustScore] = [:]
    private var actionLog: [AgentAction] = []
    private let minimumTrustScore: Double = 0.3
    private let processingQueue = DispatchQueue(label: "com.mtrx.agent.identity", qos: .userInitiated)

    // MARK: - Initialization

    init(identityManager: IdentityManager, easManager: EASManager) {
        self.identityManager = identityManager
        self.easManager = easManager
    }

    // MARK: - Agent Registration

    /// Register a new AI agent identity
    func registerAgent(ownerDID: String, agentType: AgentType, initialCapabilities: [AgentCapability], completion: @escaping (Result<AgentDID, AgentIdentityError>) -> Void) {
        let agentId = UUID().uuidString
        let did = "did:mtrx:agent:\(agentId)"

        let agent = AgentDID(
            did: did, ownerDID: ownerDID, agentType: agentType,
            capabilities: initialCapabilities, trustScore: 0.5,
            registeredAt: Date(), lastActiveAt: Date(), isActive: true
        )
        agents[did] = agent

        let initialTrust = TrustScore(
            agentDID: did, overallScore: 0.5,
            components: TrustComponents(reliability: 0.5, accuracy: 0.5, compliance: 0.5, history: 0.5, peerReview: 0.5),
            lastUpdated: Date(), totalActions: 0, successfulActions: 0
        )
        trustScores[did] = initialTrust

        delegate?.agentIdentity(self, didRegister: did)
        completion(.success(agent))
    }

    // MARK: - Capability Delegation

    /// Delegate a capability to an agent
    func delegateCapability(agentDID: String, capability: AgentCapability, completion: @escaping (Result<Void, AgentIdentityError>) -> Void) {
        guard var agent = agents[agentDID] else {
            completion(.failure(.agentNotFound))
            return
        }
        var caps = agent.capabilities
        caps.append(capability)
        agent = AgentDID(
            did: agent.did, ownerDID: agent.ownerDID, agentType: agent.agentType,
            capabilities: caps, trustScore: agent.trustScore,
            registeredAt: agent.registeredAt, lastActiveAt: Date(), isActive: agent.isActive
        )
        agents[agentDID] = agent
        delegate?.agentIdentity(self, didDelegateCapability: capability.capabilityId)
        completion(.success(()))
    }

    /// Revoke a capability from an agent
    func revokeCapability(agentDID: String, capabilityId: String, completion: @escaping (Result<Void, AgentIdentityError>) -> Void) {
        guard agents[agentDID] != nil else {
            completion(.failure(.agentNotFound))
            return
        }
        // TODO: Mark capability as revoked on-chain
        completion(.success(()))
    }

    /// Check if an agent has a specific capability
    func hasCapability(agentDID: String, scope: CapabilityScope) -> Result<AgentCapability, AgentIdentityError> {
        guard let agent = agents[agentDID] else { return .failure(.agentNotFound) }
        guard let cap = agent.capabilities.first(where: { ($0.scope == scope || $0.scope == .all) && !$0.isRevoked }) else {
            return .failure(.capabilityDenied)
        }
        if let exp = cap.expiresAt, Date() > exp { return .failure(.capabilityExpired) }
        return .success(cap)
    }

    // MARK: - Trust Scoring

    /// Get trust score for an agent
    func getTrustScore(agentDID: String) -> Result<TrustScore, AgentIdentityError> {
        guard let score = trustScores[agentDID] else { return .failure(.agentNotFound) }
        return .success(score)
    }

    /// Record an agent action and update trust score
    func recordAction(_ action: AgentAction) {
        actionLog.append(action)
        updateTrustScore(for: action.agentDID)
    }

    /// Validate that an agent can perform an action
    func validateAction(agentDID: String, scope: CapabilityScope, value: UInt64) -> Result<Bool, AgentIdentityError> {
        guard let score = trustScores[agentDID] else { return .failure(.agentNotFound) }
        guard score.overallScore >= minimumTrustScore else {
            return .failure(.trustScoreTooLow(required: minimumTrustScore, current: score.overallScore))
        }
        let capResult = hasCapability(agentDID: agentDID, scope: scope)
        switch capResult {
        case .failure(let error): return .failure(error)
        case .success(let cap):
            guard value <= cap.maxValuePerAction else { return .failure(.dailyLimitExceeded) }
            return .success(true)
        }
    }

    // MARK: - Query

    func getAgent(did: String) -> AgentDID? { return agents[did] }
    func getAgents(owner: String) -> [AgentDID] { return agents.values.filter { $0.ownerDID == owner } }
    func getActionLog(agentDID: String) -> [AgentAction] { return actionLog.filter { $0.agentDID == agentDID } }

    // MARK: - Private

    private func updateTrustScore(for agentDID: String) {
        let agentActions = actionLog.filter { $0.agentDID == agentDID }
        let total = agentActions.count
        let successful = agentActions.filter { $0.success }.count
        let reliability = total > 0 ? Double(successful) / Double(total) : 0.5
        let score = TrustScore(
            agentDID: agentDID, overallScore: reliability,
            components: TrustComponents(reliability: reliability, accuracy: reliability, compliance: 0.5, history: min(Double(total) / 100.0, 1.0), peerReview: 0.5),
            lastUpdated: Date(), totalActions: total, successfulActions: successful
        )
        trustScores[agentDID] = score
        delegate?.agentIdentity(self, trustScoreUpdated: agentDID, score: reliability)
    }
}
