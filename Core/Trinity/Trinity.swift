//
//  Trinity.swift
//  MTRX — Trinity
//
//  Primary intelligence layer. Main conversation interface for MTRX.
//

import Foundation
import Combine

// MARK: - Trinity

/// Primary intelligence layer that serves as the main user-facing interface.
/// Coordinates context assembly, memory, inference, and voice to deliver responses.
@MainActor
final class Trinity: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastResponse: TrinityResponse?
    @Published private(set) var conversationHistory: [ConversationTurn] = []
    @Published private(set) var currentState: TrinityState = .idle

    // MARK: - Dependencies

    private let context: TrinityContext
    private let memory: TrinityMemoryStore
    private let inference: TrinityInference
    private let voice: TrinityVoice
    private let scoringEngine: RexhepiEngine
    private let decisionLog: DecisionLog

    private var cancellables = Set<AnyCancellable>()

    // MARK: - State

    enum TrinityState: Sendable {
        case idle
        case listening
        case thinking
        case responding
        case error(String)
    }

    // MARK: - Initialization

    init(
        context: TrinityContext = TrinityContext(),
        memory: TrinityMemoryStore = TrinityMemoryStore(),
        inference: TrinityInference = TrinityInference(),
        voice: TrinityVoice = TrinityVoice(),
        scoringEngine: RexhepiEngine = RexhepiEngine(),
        decisionLog: DecisionLog = DecisionLog()
    ) {
        self.context = context
        self.memory = memory
        self.inference = inference
        self.voice = voice
        self.scoringEngine = scoringEngine
        self.decisionLog = decisionLog

        // TODO: Set up observation pipelines
    }

    // MARK: - Primary Interface

    /// Respond to a user message. This is the main entry point for conversation.
    /// - Parameter message: The user's input message.
    /// - Returns: Trinity's response.
    func respond(to message: String) async throws -> TrinityResponse {
        currentState = .thinking
        isProcessing = true
        defer {
            isProcessing = false
            currentState = .idle
        }

        // 1. Assemble full context
        let userContext = await context.assembleContext()

        // 2. Query memory for relevant history
        let relevantMemory = await memory.queryRelevant(for: message)

        // 3. Process the intent
        let intent = try await processIntent(message: message, context: userContext, memory: relevantMemory)

        // 4. Run through scoring engine if the intent involves a decision
        var outcome: Outcome?
        if intent.requiresDecision {
            let request = DecisionRequest(
                description: intent.description,
                context: intent.decisionContext,
                timeSensitivity: intent.timeSensitivity
            )
            outcome = try await scoringEngine.runPipeline(request)
        }

        // 5. Generate response via inference
        let response = try await think(
            intent: intent,
            context: userContext,
            memory: relevantMemory,
            outcome: outcome
        )

        // 6. Store in memory
        await memory.store(TrinityMemoryEntry(
            content: message,
            response: response.text,
            intent: intent.description,
            timestamp: Date()
        ))

        // 7. Record conversation turn
        let turn = ConversationTurn(
            userMessage: message,
            response: response,
            intent: intent,
            timestamp: Date()
        )
        conversationHistory.append(turn)

        lastResponse = response
        return response
    }

    // MARK: - Intent Processing

    /// Process the user's message to determine intent.
    /// - Parameters:
    ///   - message: The raw user message.
    ///   - context: The assembled user context.
    ///   - memory: Relevant memory entries.
    /// - Returns: The processed intent.
    func processIntent(
        message: String,
        context: UserContext,
        memory: [TrinityMemoryEntry]
    ) async throws -> TrinityIntent {
        // TODO: Implement NLU pipeline for intent classification
        // - Classify intent category (query, action, conversation, alert response)
        // - Extract entities (amounts, dates, asset names, etc.)
        // - Determine if a decision is required
        // - Assess time sensitivity

        let intent = TrinityIntent(
            description: message,
            category: .conversation,
            entities: [:],
            requiresDecision: false,
            timeSensitivity: .medium,
            decisionContext: [:],
            confidence: 0.5
        )

        return intent
    }

    // MARK: - Thinking / Response Generation

    /// Generate a response by combining intent, context, memory, and optional outcome.
    /// - Parameters:
    ///   - intent: The processed user intent.
    ///   - context: The current user context.
    ///   - memory: Relevant memory entries.
    ///   - outcome: Optional scoring engine outcome.
    /// - Returns: The generated response.
    func think(
        intent: TrinityIntent,
        context: UserContext,
        memory: [TrinityMemoryEntry],
        outcome: Outcome?
    ) async throws -> TrinityResponse {
        currentState = .thinking

        // TODO: Implement response generation pipeline
        // - Compose prompt with context, memory, and intent
        // - Run through inference engine
        // - Post-process response
        // - Apply personality and tone

        let responseText = "I understand your request. Let me process this for you."

        let response = TrinityResponse(
            text: responseText,
            confidence: intent.confidence,
            suggestedActions: [],
            outcome: outcome,
            metadata: [:]
        )

        currentState = .responding
        return response
    }

    // MARK: - Voice Output

    /// Speak the response using Trinity's voice.
    /// - Parameter response: The response to speak.
    func speak(_ response: TrinityResponse) async {
        await voice.speak(response.text)
    }
}

// MARK: - Trinity Response

/// A response generated by Trinity.
struct TrinityResponse: Sendable {
    let text: String
    let confidence: Double
    let suggestedActions: [SuggestedAction]
    let outcome: Outcome?
    let metadata: [String: String]
}

// MARK: - Suggested Action

struct SuggestedAction: Identifiable, Sendable {
    let id: UUID
    let title: String
    let description: String
    let action: String

    init(id: UUID = UUID(), title: String, description: String, action: String) {
        self.id = id
        self.title = title
        self.description = description
        self.action = action
    }
}

// MARK: - Trinity Intent

/// Represents the processed intent from a user message.
struct TrinityIntent: Sendable {
    let description: String
    let category: IntentCategory
    let entities: [String: String]
    let requiresDecision: Bool
    let timeSensitivity: TimeSensitivity
    let decisionContext: [String: Any]
    let confidence: Double
}

// MARK: - Intent Category

enum IntentCategory: String, Sendable, CaseIterable {
    case query          // User is asking for information
    case action         // User wants to perform an action
    case conversation   // General conversation
    case alertResponse  // User responding to a Morpheus alert
    case portfolio      // Portfolio-related query or action
    case settings       // Settings or configuration change
}

// MARK: - Conversation Turn

/// A single turn in the conversation history.
struct ConversationTurn: Identifiable, Sendable {
    let id: UUID = UUID()
    let userMessage: String
    let response: TrinityResponse
    let intent: TrinityIntent
    let timestamp: Date
}
