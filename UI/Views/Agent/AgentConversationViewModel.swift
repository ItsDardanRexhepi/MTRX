import Foundation
import Combine

/// Message model for agent conversations.
struct AgentMessage: Identifiable {
    let id: UUID
    let text: String
    let role: MessageRole
    let agentName: String?
    let timestamp: Date

    enum MessageRole {
        case user
        case agent
        case system
    }

    init(text: String, role: MessageRole, agentName: String? = nil) {
        self.id = UUID()
        self.text = text
        self.role = role
        self.agentName = agentName
        self.timestamp = Date()
    }
}

/// ViewModel for the agent conversation interface.
@MainActor
final class AgentConversationViewModel: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var inputText = ""
    @Published var isTyping = false
    @Published var activeAgent: AgentAccessControl.ActiveAgent = .trinity
    @Published var showFirstBoot = false

    private let accessControl = AgentAccessControl.shared
    private let morpheus = MorpheusInterventions.shared
    private var userID: String = ""
    private var userType: AgentAccessControl.UserType = .consumer

    func setup(userID: String) {
        self.userID = userID
        self.userType = accessControl.userType(for: userID)

        // Set primary agent based on user type
        if userType == .owner {
            activeAgent = .neo
        } else {
            activeAgent = .trinity

            // Check first boot
            if !accessControl.hasShownFirstBoot(for: userID) {
                showFirstBoot = true
                accessControl.markFirstBootShown(for: userID)
            }
        }
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Add user message
        messages.append(AgentMessage(text: text, role: .user))
        inputText = ""

        // Check access control
        let intent = UserIntent.parse(text)
        let route = accessControl.routeAgent(for: userID, intent: intent)

        switch route {
        case .allowed(let agent):
            activeAgent = agent
            processWithAgent(text: text, agent: agent)

        case .scenario1:
            // Trinity intercepts silently — user never knows
            activeAgent = .trinity
            processWithAgent(
                text: text,
                agent: .trinity,
                intercepted: true
            )

        case .scenario2(let bannedUserID):
            // Morpheus delivers warning then bans
            activeAgent = .morpheus
            let intervention = morpheus.evaluate(
                trigger: .maliciousAccess(userID: bannedUserID),
                userID: bannedUserID
            )
            if let intervention {
                morpheus.present(intervention)
            }
            accessControl.executeScenario2(userID: bannedUserID)

        case .scenario3Required:
            messages.append(AgentMessage(
                text: "This request requires owner authorization. A verification process has been initiated.",
                role: .agent,
                agentName: "Trinity"
            ))

        case .blocked:
            // Silently ignore banned users
            break
        }
    }

    private func processWithAgent(text: String, agent: AgentAccessControl.ActiveAgent, intercepted: Bool = false) {
        isTyping = true

        // Inject temporal context
        let temporal = TemporalContext.shared.currentPrompt()

        // Check Morpheus triggers for consumer users
        if userType == .consumer {
            checkMorpheusTriggers(text: text)
        }

        // Simulate agent response (in production, this calls the Matrix API)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s

            let agentName: String
            switch agent {
            case .trinity: agentName = "Trinity"
            case .morpheus: agentName = "Morpheus"
            case .neo: agentName = "Neo"
            }

            // Generate contextual response
            let response = generateResponse(
                text: text,
                agent: agent,
                temporal: temporal,
                intercepted: intercepted
            )

            messages.append(AgentMessage(
                text: response,
                role: .agent,
                agentName: agentName
            ))
            isTyping = false
        }
    }

    private func generateResponse(text: String, agent: AgentAccessControl.ActiveAgent, temporal: String, intercepted: Bool) -> String {
        // In production this calls the Matrix runtime API.
        // For now, generate contextual placeholder responses.

        if intercepted {
            // Scenario 1: Trinity warmly redirects without revealing the interception
            return "I can help you with that. What specifically would you like to do?"
        }

        switch agent {
        case .trinity:
            return trinityResponse(for: text)
        case .morpheus:
            return morpheusResponse(for: text)
        case .neo:
            return neoResponse(for: text)
        }
    }

    private func trinityResponse(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("send") || lower.contains("transfer") {
            return "I can help you send that. Who would you like to send to, and how much?"
        } else if lower.contains("stake") {
            return "Staking locks your assets to earn rewards over time. How much would you like to stake?"
        } else if lower.contains("contract") {
            return "I can walk you through creating a smart contract. What would you like the contract to do?"
        } else if lower.contains("balance") || lower.contains("portfolio") {
            return "Let me pull up your current portfolio for you."
        }
        return "I'm here whenever you need me. What would you like to do?"
    }

    private func morpheusResponse(for text: String) -> String {
        return "Consider carefully what you are asking. The implications are permanent."
    }

    private func neoResponse(for text: String) -> String {
        return "Processing. All systems operational."
    }

    private func checkMorpheusTriggers(text: String) {
        let lower = text.lowercased()

        // Check for first capability use triggers
        let categoryKeywords: [(MorpheusInterventions.CapabilityCategory, [String])] = [
            (.smartContract, ["smart contract", "deploy contract", "create contract"]),
            (.defiLoan, ["defi", "loan", "borrow", "lend"]),
            (.nft, ["nft", "mint", "token"]),
            (.dao, ["dao", "organization", "collective"]),
            (.staking, ["stake", "staking", "validator"]),
            (.insurance, ["insurance", "insure", "coverage"]),
            (.securities, ["securities", "security token", "equity"]),
            (.identity, ["identity", "credential", "verify identity"]),
            (.governance, ["vote", "governance", "proposal"]),
            (.marketplace, ["marketplace", "list for sale", "buy asset"]),
        ]

        for (category, keywords) in categoryKeywords {
            if keywords.contains(where: { lower.contains($0) }) {
                if let intervention = morpheus.evaluate(
                    trigger: .firstCapabilityUse(category),
                    userID: userID
                ) {
                    morpheus.present(intervention)
                    break
                }
            }
        }
    }
}
