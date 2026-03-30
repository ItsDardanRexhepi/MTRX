// IntentHandler.swift
// MTRX Apple Integration — SiriKit
// Routes Siri requests to Trinity subsystems

import Intents

// MARK: - Intent Handler Extension

class IntentHandler: INExtension {

    // MARK: - Intent Routing

    override func handler(for intent: INIntent) -> Any {
        switch intent {
        case is INSendPaymentIntent:
            return PaymentIntentHandler()
        case is INSendMessageIntent:
            return MessageIntentHandler()
        case is INCreateTaskListIntent:
            return ListIntentHandler()
        default:
            return self
        }
    }
}

// MARK: - Trinity Intent Router

/// Central router that maps Siri intents to Trinity's internal action system.
/// Each handler is responsible for its own validation, confirmation, and execution.
final class TrinityIntentRouter {

    // MARK: - Shared Instance

    static let shared = TrinityIntentRouter()

    // MARK: - Properties

    private var activeHandlers: [String: Any] = [:]
    private let routingQueue = DispatchQueue(label: "com.mtrx.trinity.intent.routing", qos: .userInitiated)

    // MARK: - Registration

    /// Registers a handler for a given intent identifier.
    func register(handler: Any, for intentIdentifier: String) {
        routingQueue.async { [weak self] in
            self?.activeHandlers[intentIdentifier] = handler
        }
    }

    /// Removes a handler for a given intent identifier.
    func unregister(intentIdentifier: String) {
        routingQueue.async { [weak self] in
            self?.activeHandlers.removeValue(forKey: intentIdentifier)
        }
    }

    // MARK: - Intent Resolution

    /// Resolves the appropriate handler for the given intent type.
    func resolveHandler(for intent: INIntent) -> Any? {
        let identifier = String(describing: type(of: intent))
        return activeHandlers[identifier]
    }

    // MARK: - Vocabulary Donation

    /// Donates Trinity-specific vocabulary to Siri for improved recognition.
    func donateVocabulary() {
        let vocabulary = INVocabulary.shared()

        let cryptoTerms: [String] = [
            "ETH", "Ethereum", "USDC", "Trinity", "Morpheus", "Oracle",
            "DeFi", "staking", "yield farming", "gas fee", "smart contract"
        ]

        let orderStrings = NSOrderedSet(array: cryptoTerms.map { NSString(string: $0) })
        vocabulary.setVocabularyStrings(orderStrings, of: .contactName)
    }
}
