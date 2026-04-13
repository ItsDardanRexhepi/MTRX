//
//  FoundationModelsEngine.swift
//  MTRX — Trinity
//
//  Apple Foundation Models on-device inference engine (iOS 26+).
//  All processing runs locally via the Neural Engine. No data leaves the device.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Structured Output Types

/// Structured intent classification output generated on-device.
@available(iOS 26, macOS 26, *)
@Generable
struct ClassifiedIntent {
    /// The intent category: query, action, conversation, alertResponse, portfolio, or settings
    var category: String
    /// Confidence score between 0.0 and 1.0
    var confidence: Double
    /// Brief one-sentence summary of the user's intent
    var summary: String
}

/// Structured response with suggested follow-up actions.
@available(iOS 26, macOS 26, *)
@Generable
struct StructuredResponse {
    /// The response text to display to the user
    var text: String
    /// Comma-separated labels for suggested follow-up actions
    var suggestedActions: String
    /// Whether this response requires explicit user confirmation before proceeding
    var requiresConfirmation: Bool
}

/// Structured entity extraction from user messages.
@available(iOS 26, macOS 26, *)
@Generable
struct ExtractedEntities {
    /// Dollar or crypto amount mentioned, empty string if none
    var amount: String
    /// Asset symbol mentioned (ETH, BTC, USDC, etc.), empty string if none
    var asset: String
    /// Wallet address or ENS name mentioned, empty string if none
    var recipient: String
    /// The primary action verb (send, swap, bridge, etc.), empty string if none
    var action: String
}

#endif

// MARK: - Foundation Models Engine

/// On-device language model inference using Apple Foundation Models.
///
/// Wraps `SystemLanguageModel` and `LanguageModelSession` to provide
/// Trinity with fast, private on-device language understanding and generation.
/// Available on iOS 26+ devices with Apple Intelligence support.
///
/// When Foundation Models is unavailable (older iOS, unsupported hardware),
/// the `InferenceRouter` falls back to the gateway API or local templates.
@available(iOS 26, macOS 26, *)
final class FoundationModelsEngine {

    // MARK: - Properties

    /// Type-erased session storage for lazy initialization.
    private var _session: Any?

    /// The active conversation session with Trinity's system instructions.
    private var session: Any {
        get {
            if let s = _session { return s }
            #if canImport(FoundationModels)
            let s = LanguageModelSession(instructions: Self.systemInstructions)
            _session = s
            return s
            #else
            fatalError("FoundationModelsEngine requires FoundationModels framework")
            #endif
        }
        set { _session = newValue }
    }

    /// Trinity's system instructions for the on-device model.
    static let systemInstructions = """
        You are Trinity, the primary AI assistant for MTRX — a decentralized \
        super-app built on Base (Ethereum L2). You help users manage portfolios, \
        execute transactions, explore DeFi, handle NFTs, participate in governance, \
        and navigate the full Web3 ecosystem. Respond naturally, concisely, and \
        with awareness of the user's context. Always prioritize clarity and safety. \
        Never fabricate transaction hashes, wallet addresses, or price data.
        """

    // MARK: - Availability

    /// Whether the on-device language model is available on this device.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    // MARK: - Text Generation

    /// Generate a text response to the user's prompt using the persistent session.
    /// The session retains conversation context across calls.
    /// - Parameter prompt: The user's message or assembled prompt.
    /// - Returns: The model's text response.
    func respond(to prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        guard let modelSession = session as? LanguageModelSession else {
            throw FoundationModelsError.sessionUnavailable
        }
        let response = try await modelSession.respond(to: prompt)
        return response.content
        #else
        throw FoundationModelsError.frameworkUnavailable
        #endif
    }

    /// Generate a text response with custom system instructions.
    /// Creates a one-off session that does not affect the persistent session's context.
    /// - Parameters:
    ///   - prompt: The user's message.
    ///   - instructions: Custom system instructions for this generation.
    /// - Returns: The model's text response.
    func respond(to prompt: String, instructions: String) async throws -> String {
        #if canImport(FoundationModels)
        let customSession = LanguageModelSession(instructions: instructions)
        let response = try await customSession.respond(to: prompt)
        return response.content
        #else
        throw FoundationModelsError.frameworkUnavailable
        #endif
    }

    // MARK: - Structured Generation

    /// Classify user intent using structured output generation.
    /// - Parameter message: The raw user message to classify.
    /// - Returns: The classified intent with category, confidence, and summary.
    func classifyIntent(message: String) async throws -> ClassifiedIntent {
        #if canImport(FoundationModels)
        let classifierSession = LanguageModelSession(instructions: """
            You are an intent classifier for a blockchain super-app. Classify user \
            messages into exactly one category. Categories: query (information requests), \
            action (transaction or operation requests), conversation (general chat), \
            alertResponse (responding to a system alert), portfolio (portfolio queries \
            or actions), settings (configuration changes). Be precise with confidence \
            scores — use 0.9+ only when the intent is unambiguous.
            """)

        let prompt = "Classify this user message: \"\(message)\""
        return try await classifierSession.respond(to: prompt, generating: ClassifiedIntent.self)
        #else
        throw FoundationModelsError.frameworkUnavailable
        #endif
    }

    /// Extract structured entities from a user message.
    /// - Parameter message: The raw user message.
    /// - Returns: Extracted entities (amounts, assets, recipients, actions).
    func extractEntities(message: String) async throws -> ExtractedEntities {
        #if canImport(FoundationModels)
        let extractorSession = LanguageModelSession(instructions: """
            You are an entity extractor for a blockchain super-app. Extract structured \
            data from user messages. For amounts, include the number and currency symbol. \
            For assets, use the standard ticker symbol (ETH, BTC, USDC, etc.). For \
            recipients, extract wallet addresses (0x...) or ENS names (.eth). For actions, \
            extract the primary verb (send, swap, bridge, stake, mint, etc.). Use empty \
            strings when an entity type is not present in the message.
            """)

        let prompt = "Extract entities from: \"\(message)\""
        return try await extractorSession.respond(to: prompt, generating: ExtractedEntities.self)
        #else
        throw FoundationModelsError.frameworkUnavailable
        #endif
    }

    /// Generate a structured response with suggested actions.
    /// - Parameter prompt: The assembled prompt including context and intent.
    /// - Returns: A structured response with text, actions, and confirmation flag.
    func generateStructured(prompt: String) async throws -> StructuredResponse {
        #if canImport(FoundationModels)
        guard let modelSession = session as? LanguageModelSession else {
            throw FoundationModelsError.sessionUnavailable
        }
        return try await modelSession.respond(to: prompt, generating: StructuredResponse.self)
        #else
        throw FoundationModelsError.frameworkUnavailable
        #endif
    }

    // MARK: - Session Management

    /// Reset the conversation session, clearing all accumulated context.
    /// Call this when starting a new conversation or switching users.
    func resetSession() {
        #if canImport(FoundationModels)
        _session = LanguageModelSession(instructions: Self.systemInstructions)
        #endif
    }
}

// MARK: - Errors

/// Errors specific to the Foundation Models inference engine.
enum FoundationModelsError: Error, LocalizedError {
    case frameworkUnavailable
    case sessionUnavailable
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .frameworkUnavailable:
            return "Foundation Models framework is not available on this device"
        case .sessionUnavailable:
            return "Language model session could not be created"
        case .generationFailed(let reason):
            return "On-device generation failed: \(reason)"
        }
    }
}
