import Foundation
import Combine

/// Morpheus intervention system — appears only at pivotal moments.
/// Never casual. Never tries to be liked. Says exactly what needs to be said and stops.
@MainActor
final class MorpheusInterventions: ObservableObject {
    static let shared = MorpheusInterventions()

    @Published private(set) var activeIntervention: MorpheusIntervention?
    @Published private(set) var isPresenting = false

    // Track which categories each user has seen (Trigger 1: first use)
    private var firstUseShown: [String: Set<CapabilityCategory>] = [:]
    private let firstUseKey = "mtrx_morpheus_first_use"

    private init() {
        loadFirstUseState()
    }

    // MARK: - Trigger Types

    enum TriggerType {
        case firstCapabilityUse(CapabilityCategory)
        case irreversibleAction(ActionDescription)
        case significantEvent(EventDescription)
        case onDemand(query: String)
        case maliciousAccess(userID: String)
    }

    enum CapabilityCategory: String, CaseIterable, Codable {
        case smartContract = "smart_contract"
        case defiLoan = "defi_loan"
        case nft = "nft"
        case dao = "dao"
        case staking = "staking"
        case insurance = "insurance"
        case securities = "securities"
        case identity = "identity"
        case governance = "governance"
        case marketplace = "marketplace"
    }

    struct ActionDescription {
        let title: String
        let details: String
        let isPermanent: Bool
        let estimatedValue: String?
    }

    struct EventDescription {
        let title: String
        let details: String
        let significance: String
    }

    // MARK: - Intervention evaluation

    func evaluate(trigger: TriggerType, userID: String) -> MorpheusIntervention? {
        switch trigger {

        case .firstCapabilityUse(let category):
            // TRIGGER 1: First time using a major capability
            guard !hasSeenFirstUse(userID: userID, category: category) else {
                return nil
            }
            markFirstUseSeen(userID: userID, category: category)
            return MorpheusIntervention(
                type: .firstUse,
                message: firstUseMessage(for: category),
                requiresConfirmation: false,
                autoDismiss: false
            )

        case .irreversibleAction(let action):
            // TRIGGER 2: Before every irreversible action
            return MorpheusIntervention(
                type: .irreversibleWarning,
                message: irreversibleMessage(for: action),
                requiresConfirmation: true,
                autoDismiss: false
            )

        case .significantEvent(let event):
            // TRIGGER 3: When something significant happens
            return MorpheusIntervention(
                type: .significantMoment,
                message: significantEventMessage(for: event),
                requiresConfirmation: false,
                autoDismiss: false
            )

        case .onDemand(let query):
            // TRIGGER 4: User requests Morpheus knowledge
            return MorpheusIntervention(
                type: .knowledge,
                message: "Reviewing: \(query)",
                requiresConfirmation: false,
                autoDismiss: false
            )

        case .maliciousAccess(let userID):
            // SCENARIO 2: Malicious Neo access attempt
            return MorpheusIntervention(
                type: .securityBreach,
                message: "You attempted to access a restricted system layer. This is your only warning. Any further attempt will result in permanent removal from MTRX. There is no appeal process.",
                requiresConfirmation: false,
                autoDismiss: true,
                autoDismissDelay: 10.0
            )
        }
    }

    func present(_ intervention: MorpheusIntervention) {
        activeIntervention = intervention
        isPresenting = true

        if intervention.autoDismiss {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(intervention.autoDismissDelay * 1_000_000_000))
                dismiss()
            }
        }
    }

    func dismiss() {
        isPresenting = false
        activeIntervention = nil
    }

    func confirmAction() -> Bool {
        guard let intervention = activeIntervention, intervention.requiresConfirmation else {
            return false
        }
        dismiss()
        return true
    }

    // MARK: - Message generators

    private func firstUseMessage(for category: CapabilityCategory) -> String {
        switch category {
        case .smartContract:
            return "You are about to create your first smart contract. A smart contract is a set of rules written into code that execute automatically. Once deployed, these rules cannot be changed. Take a moment to understand what you are agreeing to before you proceed."
        case .defiLoan:
            return "You are about to interact with decentralized lending for the first time. You will be borrowing or lending real assets with terms enforced by code. If conditions change — and they can change quickly — your position may be liquidated automatically. Understand the terms before you continue."
        case .nft:
            return "You are about to create a digital asset with permanent on-chain provenance. Once minted, the record of its creation and your authorship becomes part of the permanent public ledger. This cannot be erased."
        case .dao:
            return "You are about to form or join a decentralized organization. A DAO operates through collective voting with rules enforced by smart contracts. Decisions made through this structure are binding and executed automatically."
        case .staking:
            return "You are about to stake assets. Staking locks your assets for a period of time in exchange for rewards. During the lock period, you will not be able to move or sell these assets. Understand the lock duration and conditions before proceeding."
        case .insurance:
            return "You are about to set up parametric insurance. This type of insurance pays out automatically when predefined conditions are met — no claims process, no human review. The conditions and payout amounts are fixed at creation."
        case .securities:
            return "You are about to interact with tokenized securities. These are regulated financial instruments. Compliance requirements apply based on your jurisdiction. Verify your eligibility before proceeding."
        case .identity:
            return "You are about to create a decentralized identity. This identity will be anchored on-chain and can be used to verify who you are across services. The credentials you issue become part of your permanent digital record."
        case .governance:
            return "You are about to participate in on-chain governance. Your vote will be recorded permanently and will directly influence the outcome of this proposal. Votes cannot be changed after submission."
        case .marketplace:
            return "You are about to list or purchase an asset on the decentralized marketplace. Transactions on the marketplace are final. Ensure you have reviewed the asset details and terms before completing the transaction."
        }
    }

    private func irreversibleMessage(for action: ActionDescription) -> String {
        var msg = "You are about to \(action.title). Once executed, this action is permanent and cannot be altered."
        if let value = action.estimatedValue {
            msg += " The estimated value involved is \(value)."
        }
        msg += " Here is what you have agreed to:\n\n\(action.details)\n\nConfirm to proceed."
        return msg
    }

    private func significantEventMessage(for event: EventDescription) -> String {
        return "\(event.title)\n\n\(event.details)\n\n\(event.significance)"
    }

    // MARK: - First use tracking

    private func hasSeenFirstUse(userID: String, category: CapabilityCategory) -> Bool {
        firstUseShown[userID]?.contains(category) ?? false
    }

    private func markFirstUseSeen(userID: String, category: CapabilityCategory) {
        if firstUseShown[userID] == nil {
            firstUseShown[userID] = []
        }
        firstUseShown[userID]?.insert(category)
        saveFirstUseState()
    }

    private func loadFirstUseState() {
        guard let data = UserDefaults.standard.data(forKey: firstUseKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        for (userID, categories) in decoded {
            firstUseShown[userID] = Set(categories.compactMap { CapabilityCategory(rawValue: $0) })
        }
    }

    private func saveFirstUseState() {
        var encoded: [String: [String]] = [:]
        for (userID, categories) in firstUseShown {
            encoded[userID] = categories.map(\.rawValue)
        }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: firstUseKey)
        }
    }
}

// MARK: - Intervention model

struct MorpheusIntervention: Identifiable {
    let id = UUID()
    let type: InterventionType
    let message: String
    let requiresConfirmation: Bool
    let autoDismiss: Bool
    let autoDismissDelay: TimeInterval

    init(type: InterventionType, message: String, requiresConfirmation: Bool,
         autoDismiss: Bool, autoDismissDelay: TimeInterval = 0) {
        self.type = type
        self.message = message
        self.requiresConfirmation = requiresConfirmation
        self.autoDismiss = autoDismiss
        self.autoDismissDelay = autoDismissDelay
    }

    enum InterventionType {
        case firstUse
        case irreversibleWarning
        case significantMoment
        case knowledge
        case securityBreach
    }
}
