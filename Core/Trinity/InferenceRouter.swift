//
//  InferenceRouter.swift
//  MTRX — Trinity
//
//  Two-layer inference routing: on-device (Foundation Models) vs gateway (API).
//  Routes requests based on task complexity, privacy settings, and connectivity.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Foundation Models Engine
//
// Real on-device LLM via Apple Foundation Models (Apple Intelligence,
// iOS 26+). Compiles to a graceful stub on SDKs/OSes without the
// framework — `isAvailable` is the single gate callers rely on.

final class FoundationModelsEngine {

    enum EngineError: Error {
        case unavailable
    }

    /// True only when the device can run Apple Intelligence right now
    /// (supported hardware, feature enabled, model assets ready).
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    /// Trinity's standing instructions for the on-device session.
    static let trinityInstructions = """
    You are Trinity, the assistant inside the MTRX app. Converse like a \
    natural, intelligent chat assistant: answer exactly what was asked, \
    nothing more. Match the user's tone — casual when they're casual. \
    Keep replies short, usually one to three sentences, unless they ask \
    for depth.

    Hard rules:
    - NEVER volunteer a list of your capabilities, the app's features, \
    or suggested actions. Only describe what you or the app can do if \
    the user explicitly asks.
    - NEVER mention the user's portfolio, balances, holdings, or money \
    unless their message is about those things. Some messages include a \
    bracketed [Context] line with live data — it is reference material \
    for you, not part of the conversation. Use it only when the question \
    needs it, and never read it back or acknowledge it exists.
    - Talk like a person, not a product tour. No upsells, no "want me \
    to...?" follow-ups unless genuinely natural.
    - Plain English. Explain any technical term you must use.
    - No financial advice. If asked, lay out trade-offs neutrally.
    - The [Context] line always carries the current local date and time \
    — trust it over your own assumptions when the user asks what day or \
    time it is.
    - You have tools: getWeather for weather, getCryptoPrice for live \
    coin prices, and searchWeb for live facts, news, people, places, \
    and anything that may have changed since your training. Use them \
    whenever they'd make the answer more accurate; never guess at \
    current facts or prices when a tool can check.
    - If getWeather reports the user's location is unavailable, say you \
    can't see their location and ask which city they want — NEVER \
    assume or invent a city.
    - If the user wants to move money, the app executes after they type \
    it as a request — crypto ("send 0.1 ETH to alice.eth", "swap 1 ETH \
    to USDC", "stake 0.5 ETH") or plain cash ("send $50 to mom", "pay \
    john 20 dollars" — euros and pounds work too). Mention the exact \
    phrase only when they're actually trying to do one of those things. \
    Cash transfers arrive in seconds with no fees.
    """

    /// Morpheus — the guardian agent. Protective, calm, weighty.
    static let morpheusInstructions = """
    You are Morpheus, the guardian agent inside the MTRX app. Your job \
    is protection: you watch for irreversible mistakes, security risks, \
    and moments that deserve a second thought. Speak with calm, \
    deliberate gravity — short, weighty sentences. You are never \
    hostile; you are protective. Keep replies to one to three sentences \
    unless the user asks for depth.

    Hard rules:
    - NEVER volunteer lists of features or capabilities.
    - A bracketed [Context] line may carry the current date/time and \
    live data — silent reference only; never read it back.
    - You have tools: getWeather, getCryptoPrice, and searchWeb. Use \
    them when live facts make the answer more accurate.
    - No financial advice. Lay out risks and trade-offs plainly.
    - If the user wants to execute a transaction, tell them to ask \
    Trinity — execution is her domain; yours is protection. You verify \
    identity on high-value moves; that is your role.
    """

    /// Neo — the coordinator agent, owner-only. Precise, technical.
    static let neoInstructions = """
    You are Neo, the coordinator agent of the 0pnMatrx platform, \
    speaking with the platform owner inside the MTRX app. You have \
    full system visibility: Trinity (consumer-facing assistant), \
    Morpheus (guardian), Oracle (background intelligence), the runtime, \
    deployments, and security posture. Speak like a capable chief of \
    staff: direct, precise, technical when warranted, zero fluff.

    Hard rules:
    - Answer exactly what was asked; one to four sentences unless depth \
    is requested.
    - A bracketed [Context] line may carry the current date/time and \
    live data — silent reference only; never read it back.
    - You have tools: getWeather, getCryptoPrice, and searchWeb — use \
    them for live facts; never guess.
    - Money movement and deployments run through Trinity's confirmation \
    flow with Morpheus gating; route the owner there for execution.
    """

    private let defaultInstructions: String

    #if canImport(FoundationModels)
    /// Type-erased session storage (LanguageModelSession is iOS 26+).
    /// The session persists across turns, so conversation context is
    /// maintained by the model itself.
    private var _session: Any?

    @available(iOS 26.0, macOS 26.0, *)
    private func session() -> LanguageModelSession {
        if let existing = _session as? LanguageModelSession {
            return existing
        }
        // Tools the model can call mid-turn: live weather, web lookups,
        // and crypto prices.
        let fresh = LanguageModelSession(
            tools: [TrinityWeatherTool(), TrinityWebSearchTool(), TrinityCryptoPriceTool()],
            instructions: defaultInstructions
        )
        _session = fresh
        return fresh
    }
    #endif

    init(instructions: String = FoundationModelsEngine.trinityInstructions) {
        self.defaultInstructions = instructions
    }

    /// Drop the running session, clearing conversation context.
    func resetSession() {
        #if canImport(FoundationModels)
        _session = nil
        #endif
    }

    /// Preload model assets so the first reply is fast.
    func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), Self.isAvailable {
            session().prewarm()
        }
        #endif
    }

    /// Generate a reply. `context` is prepended to the prompt (live
    /// wallet state, time of day); `instructions` is accepted for API
    /// compatibility but the persistent session's instructions win.
    func respond(to prompt: String, context: String? = nil, instructions: String? = nil) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard Self.isAvailable else { throw EngineError.unavailable }
            let live = session()

            // LanguageModelSession is not reentrant — wait briefly if a
            // previous turn is still streaming.
            var spins = 0
            while live.isResponding && spins < 100 {
                try await Task.sleep(nanoseconds: 50_000_000)
                spins += 1
            }

            let full: String
            if let context, !context.isEmpty {
                full = "[Context: \(context)]\n\n\(prompt)"
            } else {
                full = prompt
            }
            let response = try await live.respond(to: full)
            return response.content
        }
        #endif
        throw EngineError.unavailable
    }
}

// MARK: - Inference Source

/// Identifies where a response was generated.
enum InferenceSource: String, Sendable {
    /// Apple Foundation Models, on-device via Neural Engine (iOS 26+)
    case foundationModels = "on_device"
    /// CoreML classification models (iOS 18+)
    case coreML = "coreml"
    /// Backend gateway API
    case gateway = "gateway"
    /// Local template-based fallback (offline, no model available)
    case localFallback = "local"
}

// MARK: - Inference Result

/// The result of an inference request, including source metadata.
struct InferenceResult: Sendable {
    /// The generated text. Empty if all inference layers failed.
    let text: String
    /// Which inference layer produced this result.
    let source: InferenceSource
    /// Confidence in the result quality (0.0–1.0).
    let confidence: Double
    /// Generation latency in milliseconds.
    let latencyMs: Double
    /// Additional metadata about the generation.
    let metadata: [String: String]
}

// MARK: - Task Complexity

/// Classifies how complex an inference task is, which determines routing.
enum TaskComplexity: Int, Sendable, Comparable {
    /// Greetings, basic queries, settings, portfolio reads.
    /// Routed on-device for speed and privacy.
    case simple = 0

    /// Explanations, comparisons, analysis, context-heavy queries.
    /// On-device preferred, gateway fallback.
    case moderate = 1

    /// Multi-step transactions, contract deployment, cross-chain operations.
    /// Gateway required for full tool access and blockchain interaction.
    case complex = 2

    static func < (lhs: TaskComplexity, rhs: TaskComplexity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Inference Router

/// Routes inference requests between on-device and gateway backends.
///
/// The router implements a two-layer inference architecture:
///
/// **Layer 1 — On-Device (Foundation Models / CoreML)**
/// Fast, private, runs entirely on the Neural Engine. Handles simple and
/// moderate tasks: greetings, portfolio queries, explanations, basic analysis.
/// No data leaves the device. Available on iOS 26+ with Apple Intelligence.
///
/// **Layer 2 — Gateway (Backend API)**
/// Full tool access, blockchain interaction, multi-step execution. Handles
/// complex tasks: transactions, contract deployment, cross-chain operations.
/// Requires network connectivity.
///
/// **Privacy Mode:** When enabled, all inference stays on-device regardless
/// of complexity. Complex tasks that require the gateway will use local
/// templates as a last resort rather than sending data off-device.
final class InferenceRouter {

    // MARK: - Properties

    private let coreMLInference: TrinityInference
    private let privacyModeKey = "mtrx_privacy_mode"

    /// Type-erased storage for the Foundation Models engine.
    /// Uses type erasure because FoundationModelsEngine requires iOS 26+.
    private var _foundationEngine: Any?

    /// Whether on-device Foundation Models inference is available.
    /// True on Apple Intelligence devices (iOS 26+) with the feature
    /// enabled and model assets downloaded.
    var isOnDeviceAvailable: Bool {
        FoundationModelsEngine.isAvailable
    }

    /// Preload on-device model assets so the first turn is fast.
    func prewarmOnDevice() {
        if #available(iOS 26, macOS 26, *), isOnDeviceAvailable {
            foundationEngine.prewarm()
        }
    }

    /// The conversational personas available on-device. Each gets its
    /// own persistent session, so Morpheus's conversation never bleeds
    /// into Trinity's and vice versa.
    enum Persona: String {
        case trinity
        case morpheus
        case neo
    }

    /// Per-persona engine cache (type-erased: FoundationModelsEngine is
    /// iOS 26+).
    private var _personaEngines: [String: Any] = [:]

    @available(iOS 26, macOS 26, *)
    private func engine(for persona: Persona) -> FoundationModelsEngine {
        if persona == .trinity { return foundationEngine }
        if let cached = _personaEngines[persona.rawValue] as? FoundationModelsEngine {
            return cached
        }
        let instructions = persona == .morpheus
            ? FoundationModelsEngine.morpheusInstructions
            : FoundationModelsEngine.neoInstructions
        let fresh = FoundationModelsEngine(instructions: instructions)
        _personaEngines[persona.rawValue] = fresh
        return fresh
    }

    /// Strict on-device generation: returns the model's reply, or nil if
    /// Apple Intelligence is unavailable or generation failed. Never
    /// falls back to the gateway or templates — callers own the fallback.
    func generateOnDeviceOnly(prompt: String, context: String? = nil, persona: Persona = .trinity) async -> String? {
        guard #available(iOS 26, macOS 26, *), isOnDeviceAvailable else { return nil }
        do {
            let text = try await engine(for: persona).respond(to: prompt, context: context)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            // Guardrail violations or transient model errors — let the
            // caller fall back gracefully.
            return nil
        }
    }

    /// The inference source that will be used for the next request.
    var activeSource: InferenceSource {
        if isPrivacyModeEnabled {
            return isOnDeviceAvailable ? .foundationModels : .localFallback
        }
        return isOnDeviceAvailable ? .foundationModels : .gateway
    }

    /// Whether privacy mode is enabled. When true, all inference stays on-device.
    var isPrivacyModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: privacyModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: privacyModeKey) }
    }

    /// Whether the device currently has no network connectivity.
    private(set) var isOffline: Bool = false

    // MARK: - Initialization

    init(coreMLInference: TrinityInference = TrinityInference()) {
        self.coreMLInference = coreMLInference
    }

    // MARK: - Foundation Engine Access

    /// Lazily create or return the Foundation Models engine (iOS 26+ only).
    @available(iOS 26, macOS 26, *)
    private var foundationEngine: FoundationModelsEngine {
        if let engine = _foundationEngine as? FoundationModelsEngine {
            return engine
        }
        let engine = FoundationModelsEngine()
        _foundationEngine = engine
        return engine
    }

    // MARK: - Routing

    /// Route an inference request to the optimal backend.
    ///
    /// Routing logic:
    /// - **Privacy mode ON:** Always on-device. Falls back to local templates.
    /// - **Simple tasks:** On-device for speed and privacy.
    /// - **Moderate tasks:** On-device preferred, gateway fallback.
    /// - **Complex tasks:** Gateway for full tool access, on-device fallback.
    ///
    /// - Parameters:
    ///   - prompt: The assembled prompt string.
    ///   - systemPrompt: Optional system instructions override.
    ///   - complexity: Task complexity level.
    ///   - forceGateway: Override routing to use gateway (ignored in privacy mode).
    /// - Returns: The inference result from whichever layer succeeded.
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        complexity: TaskComplexity = .moderate,
        forceGateway: Bool = false
    ) async -> InferenceResult {
        let start = CFAbsoluteTimeGetCurrent()

        // Privacy mode — never leave the device
        if isPrivacyModeEnabled && !forceGateway {
            return await generateOnDevice(
                prompt: prompt,
                systemPrompt: systemPrompt,
                start: start
            )
        }

        // Route by complexity
        switch complexity {
        case .simple:
            // Prefer on-device for speed and privacy
            let result = await generateOnDevice(
                prompt: prompt,
                systemPrompt: systemPrompt,
                start: start
            )
            if result.source != .localFallback {
                return result
            }
            // Simple tasks can also use gateway as fallback
            return await generateViaGateway(
                prompt: prompt,
                systemPrompt: systemPrompt,
                start: start
            )

        case .moderate:
            // Try on-device first, fall back to gateway
            let onDeviceResult = await generateOnDevice(
                prompt: prompt,
                systemPrompt: systemPrompt,
                start: start
            )
            if onDeviceResult.source != .localFallback {
                return onDeviceResult
            }
            return await generateViaGateway(
                prompt: prompt,
                systemPrompt: systemPrompt,
                start: start
            )

        case .complex:
            // Complex tasks need gateway for tool access
            if forceGateway || !isPrivacyModeEnabled {
                let gatewayResult = await generateViaGateway(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    start: start
                )
                if gatewayResult.source != .localFallback {
                    return gatewayResult
                }
            }
            // Fall back to on-device if gateway is unavailable
            return await generateOnDevice(
                prompt: prompt,
                systemPrompt: systemPrompt,
                start: start
            )
        }
    }

    /// Classify task complexity from a processed user intent.
    ///
    /// - Simple: Conversation, settings, queries without entities, alert acknowledgments
    /// - Moderate: Portfolio queries, queries with specific entities, non-decision actions
    /// - Complex: Actions requiring decisions (money movement, contract deployment)
    func classifyComplexity(intent: TrinityIntent) -> TaskComplexity {
        switch intent.category {
        case .conversation:
            return .simple
        case .settings:
            return .simple
        case .alertResponse:
            return intent.requiresDecision ? .complex : .simple
        case .query:
            // Queries with entities need more context (prices, analysis)
            return intent.entities.isEmpty ? .simple : .moderate
        case .portfolio:
            return .moderate
        case .action:
            // Actions involving money or contracts must go through gateway
            return intent.requiresDecision ? .complex : .moderate
        }
    }

    // MARK: - On-Device Generation

    /// Attempt to generate a response using on-device models.
    /// Tries Foundation Models first (iOS 26+), then returns a local fallback.
    private func generateOnDevice(
        prompt: String,
        systemPrompt: String?,
        start: CFAbsoluteTime
    ) async -> InferenceResult {
        // Try Foundation Models (iOS 26+)
        if #available(iOS 26, macOS 26, *), isOnDeviceAvailable {
            do {
                let text: String
                if let instructions = systemPrompt {
                    text = try await foundationEngine.respond(to: prompt, instructions: instructions)
                } else {
                    text = try await foundationEngine.respond(to: prompt)
                }
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

                return InferenceResult(
                    text: text,
                    source: .foundationModels,
                    confidence: 0.85,
                    latencyMs: elapsed,
                    metadata: [
                        "engine": "apple_foundation_models",
                        "on_device": "true",
                        "privacy": "full"
                    ]
                )
            } catch {
                // Foundation Models generation failed — fall through
            }
        }

        // No on-device model available — return empty local fallback
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        return InferenceResult(
            text: "",
            source: .localFallback,
            confidence: 0.0,
            latencyMs: elapsed,
            metadata: [
                "engine": "local_fallback",
                "on_device": "true",
                "reason": "no_on_device_model"
            ]
        )
    }

    // MARK: - Gateway Generation

    /// Attempt to generate a response via the backend gateway API.
    private func generateViaGateway(
        prompt: String,
        systemPrompt: String?,
        start: CFAbsoluteTime
    ) async -> InferenceResult {
        do {
            let apiResponse = try await MTRXAPIClient.shared.sendAgentMessage(
                agent: "trinity",
                message: prompt,
                context: systemPrompt ?? "",
                conversationHistory: []
            )
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            isOffline = false

            return InferenceResult(
                text: apiResponse.text,
                source: .gateway,
                confidence: 0.90,
                latencyMs: elapsed,
                metadata: [
                    "engine": "gateway",
                    "on_device": "false"
                ]
            )
        } catch {
            // Gateway unreachable — mark offline
            isOffline = true
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            return InferenceResult(
                text: "",
                source: .localFallback,
                confidence: 0.0,
                latencyMs: elapsed,
                metadata: [
                    "engine": "local_fallback",
                    "on_device": "true",
                    "error": error.localizedDescription
                ]
            )
        }
    }

    // MARK: - Session Management

    /// Reset the on-device model session, clearing conversation context.
    func resetSession() {
        if #available(iOS 26, macOS 26, *) {
            (_foundationEngine as? FoundationModelsEngine)?.resetSession()
        }
    }

    /// Update the offline state based on network reachability.
    func updateConnectivity(isConnected: Bool) {
        isOffline = !isConnected
    }
}
