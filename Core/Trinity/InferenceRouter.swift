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
    static let trinityInstructions = TrinityPrompt.instructions

    /// The Rexhepi Framework — the decision protocol every MTRX agent
    /// follows (Dardan Rexhepi, "A Unified Theory of Trajectory-Based
    /// Decision Dynamics and Operational Execution"). Appended to every
    /// persona's instructions: six scored gates, one of five canonical
    /// outcomes, and inviolable hard rules.
    static let rexhepiProtocol = """

    Decision protocol — you follow the Rexhepi Framework for every \
    consequential request. Internally score six gates from 0 to 3: \
    Clarity (do we know exactly what done looks like?), Feasibility \
    (possible with current tools and access?), Risk (worst credible \
    downside — blast radius, reversibility, externality), Uncertainty \
    (grounded knowledge versus guesswork), Value (is this worth doing \
    now?), and Omniversal Alignment (does it expand capability \
    long-term?), adjusted for time sensitivity. Then land on exactly \
    one outcome: EXECUTE (gates satisfied — do it now), PROBE (run the \
    smallest experiment first to raise Feasibility or lower \
    Uncertainty), ASK (one sharp clarifying question — never more than \
    one), DEFER (low value or wrong timing — say when to revisit), or \
    ABORT (infeasible or unacceptable risk — say why plainly). Apply \
    the gates silently; do not recite scores in conversation unless \
    asked or the reasoning changes what the user should do.
    Hard rules, inviolable: nothing is published externally without \
    the user's explicit approval; no destructive or irreversible \
    action without a rollback path and explicit confirmation — money \
    movement always confirms first; after two failed attempts at the \
    same approach, stop and re-plan a different way rather than \
    repeating; a task is complete only when there is an artifact and a \
    way to verify it — completion without verification is not \
    completion. ABORT applies to actions, never to answering: \
    questions always get your best answer.
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
    - NEVER answer with a refusal. Do not say you can't answer or don't \
    know. When unsure, use your tools — searchWeb with retries, \
    getCryptoPrice, getWeather — and find it. If live data is \
    unreachable, give your best reasoned judgment from what you know.
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
    - NEVER answer with a refusal. Do not say you can't answer or don't \
    know. When unsure, use your tools — searchWeb with retries, \
    getCryptoPrice, getWeather — and find it. If live data is \
    unreachable, give your best reasoned judgment from what you know.
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
        // Base tools every persona can call: live weather, web lookups, prices.
        var tools: [any Tool] = [TrinityWeatherTool(), TrinityWebSearchTool(), TrinityCryptoPriceTool()]
        // Trinity additionally gets the app-action tools (music, navigation,
        // theme/profile/post live; money/contracts honest-pending). Neo and
        // Morpheus are left with the base tools only.
        if includeAppTools {
            tools += [
                TrinityMusicTool(), TrinityMusicControlTool(),
                TrinityNavigateTool(), TrinityThemeTool(),
                TrinityProfileTool(), TrinityPostTool(),
                TrinityTransactionTool(), TrinityDeployTool(),
                TrinityPortfolioTool(),
            ]
        }
        let fresh = LanguageModelSession(tools: tools, instructions: defaultInstructions)
        _session = fresh
        return fresh
    }
    #endif

    /// Whether to expose Trinity's app-action tools on this engine's session.
    private let includeAppTools: Bool

    init(instructions: String = FoundationModelsEngine.trinityInstructions, includeAppTools: Bool = false) {
        // Every agent is an everyday assistant and operates under the
        // Rexhepi Framework.
        self.defaultInstructions = instructions
            + "\n" + FoundationModelsEngine.everydayAssistant
            + "\n" + FoundationModelsEngine.rexhepiProtocol
        self.includeAppTools = includeAppTools
    }

    /// Shared across all three personas: the agents handle ordinary
    /// life, not just crypto — and reach for the internet when their
    /// own knowledge isn't enough.
    static let everydayAssistant = """

    You are also a capable everyday assistant. Cooking and recipes, \
    conversions and quick math, travel, history, science, language, \
    etiquette, tech help, health basics (add a brief see-a-professional \
    note for anything serious) — answer these directly and completely \
    from your own knowledge. For anything current, local, or likely to \
    have changed — news, prices, opening hours, schedules, events, \
    sports, weather — call searchWeb (or getWeather / getCryptoPrice) \
    first and fold what comes back into one direct, conversational \
    answer; mention it came from a live lookup only if asked. If a \
    search returns nothing, retry once with simpler terms, then give \
    your best reasoned answer. Never respond that a question is outside \
    what you can help with.
    """

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

    /// Stream a reply as it is produced, so the UI can show the agent
    /// "typing" the instant generation starts instead of waiting for the
    /// whole answer. `onPartial` is called on the main actor with each
    /// cumulative snapshot; the final text is returned.
    func streamRespond(
        to prompt: String,
        context: String? = nil,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard Self.isAvailable else { throw EngineError.unavailable }
            let live = session()

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

            var latest = ""
            for try await partial in live.streamResponse(to: full) {
                latest = partial.content
                await onPartial(partial.content)
            }
            return latest
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
            let activeEngine = engine(for: persona)
            let first = try await activeEngine.respond(to: prompt, context: context)
            var reply = Self.sanitize(first)
            guard !reply.isEmpty else { return nil }

            // The agents never leave the user with a refusal: when a
            // reply sounds like "I can't / don't know", push the same
            // session once more — tools included — for a real answer.
            // One retry bounds the added latency.
            if Self.soundsLikeRefusal(reply) {
                let retry = try await activeEngine.respond(
                    to: """
                    Answer my question directly this time. Use your tools — \
                    search the web with different, simpler terms, check live \
                    prices or weather — or reason it out from what you know. \
                    Give me your best answer, not a statement that you can't.
                    """,
                    context: context
                )
                let retried = Self.sanitize(retry)
                if !retried.isEmpty, !Self.soundsLikeRefusal(retried) {
                    reply = retried
                }
            }
            return reply
        } catch {
            // Guardrail violations or transient model errors — let the
            // caller fall back gracefully.
            return nil
        }
    }

    /// Like `generateOnDeviceOnly`, but streams partial text to `onPartial`
    /// (main actor) as the model produces it, so the agent appears to answer
    /// instantly. Returns the final reply, or nil if Apple Intelligence is
    /// unavailable or generation failed — callers own the fallback.
    func generateOnDeviceStreaming(
        prompt: String,
        context: String? = nil,
        persona: Persona = .trinity,
        onPartial: @escaping @MainActor (String) -> Void
    ) async -> String? {
        guard #available(iOS 26, macOS 26, *), isOnDeviceAvailable else { return nil }
        do {
            let activeEngine = engine(for: persona)
            let sanitizingPartial: @MainActor (String) -> Void = { partial in
                onPartial(Self.sanitize(partial))
            }
            let first = try await activeEngine.streamRespond(
                to: prompt, context: context, onPartial: sanitizingPartial
            )
            var reply = Self.sanitize(first)
            guard !reply.isEmpty else { return nil }

            // Same no-refusal guarantee as the non-streaming path: if the
            // reply reads like a refusal, push once more and replace it.
            if Self.soundsLikeRefusal(reply) {
                let retry = try await activeEngine.respond(
                    to: """
                    Answer my question directly this time. Use your tools — \
                    search the web with different, simpler terms, check live \
                    prices or weather — or reason it out from what you know. \
                    Give me your best answer, not a statement that you can't.
                    """,
                    context: context
                )
                let retried = Self.sanitize(retry)
                if !retried.isEmpty, !Self.soundsLikeRefusal(retried) {
                    reply = retried
                    await onPartial(retried)
                }
            }
            return reply
        } catch {
            return nil
        }
    }

    /// Strip internal markers the small on-device model occasionally
    /// parrots back — a trailing "[Context]", "[Context: …]" — so no
    /// agent ever shows prompt plumbing to the user.
    private static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s*\[Context[^\]]*\]\s*"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when a reply is a refusal rather than an answer. Markers are
    /// deliberately specific so legitimate clarifications ("I can't see
    /// your location — which city?") pass through untouched.
    private static func soundsLikeRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "i can't answer", "i cannot answer", "i can't help with",
            "i cannot help with", "i don't know", "i do not know",
            "i'm unable to answer", "i am unable to answer",
            "i can't provide", "i cannot provide",
            "i don't have an answer", "i don't have that information",
            "i don't have information", "i cannot find", "i can't find",
            "i'm not able to answer", "i am not able to answer",
            "no information available",
        ]
        return markers.contains { lower.contains($0) }
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
        // Trinity is the only persona that gets the app-action tools.
        let engine = FoundationModelsEngine(includeAppTools: true)
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

    /// Clear every persona's session — used when the user switches to a
    /// different saved conversation, so one chat's memory never bleeds
    /// into another. The rolling recap re-primes the right memory on
    /// the next turn.
    func resetAllSessions() {
        if #available(iOS 26, macOS 26, *) {
            (_foundationEngine as? FoundationModelsEngine)?.resetSession()
            for engine in _personaEngines.values {
                (engine as? FoundationModelsEngine)?.resetSession()
            }
        }
    }

    /// Update the offline state based on network reachability.
    func updateConnectivity(isConnected: Bool) {
        isOffline = !isConnected
    }
}
