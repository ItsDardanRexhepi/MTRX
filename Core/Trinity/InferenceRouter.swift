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

    #if canImport(FoundationModels)
    /// A lightweight session kept for the app's lifetime so the SHARED on-device
    /// model (`SystemLanguageModel.default`) stays loaded after a launch
    /// prewarm. Type-erased because `LanguageModelSession` is iOS 26+.
    private static var _launchWarmer: Any?
    #endif

    /// Warm the shared on-device model at APP LAUNCH so the very first chat
    /// isn't a cold start. Non-blocking (`prewarm()` is a hint that warms in the
    /// background), availability-gated, and idempotent — it loads the shared
    /// model once via a minimal throwaway session. It creates NO persona
    /// conversation session, so Trinity/Neo/Morpheus separation is untouched;
    /// the per-conversation sessions later reuse the already-loaded model.
    static func prewarmAtLaunch() {
        #if canImport(FoundationModels)
        guard isAvailable else { return }
        if #available(iOS 26.0, macOS 26.0, *) {
            let warmer = (_launchWarmer as? LanguageModelSession) ?? LanguageModelSession()
            _launchWarmer = warmer
            warmer.prewarm()
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

            // The agents never leave the user with a SPURIOUS refusal: when a
            // reply sounds like "I can't / don't know" push the same session
            // once more — tools included — for a real answer. But an honest,
            // reasoned limitation (honest-pending tools, Apple Music/WeatherKit
            // not connected, a location clarification) is a CORRECT refusal and
            // must stand, never be retried away. One retry bounds the latency.
            if Self.soundsLikeRefusal(reply), !Self.isHonestRefusal(reply) {
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

            // No-refusal guarantee — but only for a SPURIOUS model refusal. An
            // honest, reasoned limitation (the honest-pending tools, Apple Music
            // not connected, a location clarification) is a CORRECT refusal and
            // must stand — never retried away. Skipping those also avoids a
            // wasted second generation. The remaining genuine retries STREAM
            // (sanitizingPartial) instead of paying a blocking second full pass.
            if Self.soundsLikeRefusal(reply), !Self.isHonestRefusal(reply) {
                let retry = try await activeEngine.streamRespond(
                    to: """
                    Answer my question directly this time. Use your tools — \
                    search the web with different, simpler terms, check live \
                    prices or weather — or reason it out from what you know. \
                    Give me your best answer, not a statement that you can't.
                    """,
                    context: context,
                    onPartial: sanitizingPartial
                )
                let retried = Self.sanitize(retry)
                if !retried.isEmpty { reply = retried }
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

    /// True when a reply is an HONEST, reasoned limitation that must STAND — a
    /// genuine "I can't do X yet because <real reason>": the honest-pending tools
    /// (moveFunds / deployContract — backend not connected), Apple Music not
    /// connected, WeatherKit/location unavailable, subscriptions not set up, or a
    /// location clarification. These are CORRECT refusals and must never be
    /// retried away or masked. They're distinguished from a content-free model
    /// refusal by carrying a concrete reason — so if any reason is present we err
    /// safe and let the refusal stand (we'd rather skip a retry than mask honesty).
    private static func isHonestRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        let honestReasons = [
            "isn't connected", "is not connected", "not connected",
            "backend", "on-chain", "on chain", "network isn't",
            "once the network", "once it's connected", "once connected",
            "won't pretend", "won't fake", "wouldn't be real",
            "apple music", "weatherkit", "your location",
            "which city", "can't see your location", "location services",
            "not set up", "set up in app store", "app store connect",
            "not available yet", "isn't enabled", "is not enabled",
            "not enabled", "face id", "secure approval", "demo data",
            "sample data", "sample balances", "isn't live yet",
        ]
        return honestReasons.contains { lower.contains($0) }
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

// MARK: - Local-first reasoning router (Part 3)
//
// Trinity reasons ON-DEVICE by default and escalates to the cloud (Anthropic via
// the gateway) ONLY when a request genuinely exceeds on-device capability. Apple
// Foundation Models is strong at conversation, everyday Q&A, short reasoning, and
// tool-calls — fully offline; it is weaker on long / multi-step / expert-depth /
// large-context requests, which escalate. Escalation never happens in privacy mode.

/// Where a reasoning request should be handled.
enum ReasoningRoute: Equatable {
    /// Apple Foundation Models handles it locally (the default).
    case onDevice
    /// Escalate to the cloud gateway (Anthropic) — the task exceeds local capability.
    case escalateToCloud
    /// No reasoning source reachable — Trinity fails honestly (never scripted).
    case honestlyUnavailable
}

/// The on-device reasoning seam. Abstracts Apple Foundation Models so the router
/// depends on a protocol, not the concrete engine. (This is the OfflineReasoning-
/// Provider the local-first architecture calls for; the on-device path was
/// previously only the concrete `FoundationModelsEngine`.)
protocol OfflineReasoningProvider {
    /// True when on-device reasoning can run right now (iOS 26+ Apple Intelligence).
    var isAvailable: Bool { get }
    /// Reason fully on-device, streaming partials; nil if unavailable or it failed.
    func reason(prompt: String, context: String?,
                onPartial: @escaping @MainActor (String) -> Void) async -> String?
}

/// Foundation Models implementation of the on-device seam (wraps `InferenceRouter`).
struct FoundationModelsReasoningProvider: OfflineReasoningProvider {
    let router: InferenceRouter
    var persona: InferenceRouter.Persona = .trinity
    var isAvailable: Bool { router.isOnDeviceAvailable }
    func reason(prompt: String, context: String?,
                onPartial: @escaping @MainActor (String) -> Void) async -> String? {
        await router.generateOnDeviceStreaming(prompt: prompt, context: context,
                                               persona: persona, onPartial: onPartial)
    }
}

/// Decides, per request, whether Trinity reasons on-device or escalates to the
/// cloud. LOCAL-FIRST: on-device is the default; the cloud is used ONLY when the
/// request exceeds on-device capability.
///
/// EXACT DECISION CRITERIA (evaluated in this order):
///   1. Privacy mode ON  → never leave the device: `.onDevice` if available, else
///      `.honestlyUnavailable`. The cloud is never used in privacy mode.
///   2. Request EXCEEDS local capability → `.escalateToCloud` when the cloud is
///      reachable (else best-effort `.onDevice`, else `.honestlyUnavailable`).
///      "Exceeds local" is true when ANY of:
///        • the caller forces the cloud (developer toggle), OR
///        • the prompt is long — more than `localCharBudget` characters (a proxy
///          for large context the small on-device model handles poorly), OR
///        • the prompt carries a deep/multi-step/expert signal
///          (`deepReasoningMarkers`, e.g. "step by step", "prove", "in depth",
///          "write an essay", "research").
///   3. Otherwise → `.onDevice` if available (the default), else `.escalateToCloud`
///      if the cloud is reachable, else `.honestlyUnavailable`.
///
/// Deterministic app actions ("open X", "post Y", "set theme") are handled upstream
/// by the app-intent handlers BEFORE reasoning is routed, so they never reach this
/// router. Network-needing actions produced while offline are queued for replay via
/// the offline intent queue — that is execution, separate from reasoning routing.
struct ReasoningRouter {
    /// Above this many characters a prompt is treated as large-context the small
    /// on-device model handles poorly → escalate (outside privacy mode). ~600 chars
    /// ≈ a few dense paragraphs; on-device excels below this.
    var localCharBudget = 600

    /// Signals a request wants deep / multi-step / expert / long-form reasoning.
    static let deepReasoningMarkers: [String] = [
        "step by step", "step-by-step", "prove", "derive", "in depth", "in-depth",
        "comprehensive", "thorough", "analyze in detail", "explain in detail",
        "write an essay", "write a report", "long-form", "research",
    ]

    func route(prompt: String,
               onDeviceAvailable: Bool,
               cloudReachable: Bool,
               privacyMode: Bool,
               forceCloud: Bool) -> ReasoningRoute {
        // 1 — Privacy mode never leaves the device.
        if privacyMode {
            return onDeviceAvailable ? .onDevice : .honestlyUnavailable
        }
        // 2 — Does the request exceed on-device capability?
        let lower = prompt.lowercased()
        let exceedsLocal = forceCloud
            || prompt.count > localCharBudget
            || Self.deepReasoningMarkers.contains { lower.contains($0) }
        if exceedsLocal {
            if cloudReachable { return .escalateToCloud }
            if onDeviceAvailable { return .onDevice }       // best-effort beats nothing
            return .honestlyUnavailable
        }
        // 3 — Default: local-first.
        if onDeviceAvailable { return .onDevice }
        if cloudReachable { return .escalateToCloud }
        return .honestlyUnavailable
    }
}

extension InferenceRouter {
    /// The on-device reasoning seam for a persona (Part 3). App Intents and the
    /// chat path reason through this instead of touching the engine directly.
    func offlineProvider(persona: Persona = .trinity) -> OfflineReasoningProvider {
        FoundationModelsReasoningProvider(router: self, persona: persona)
    }
}
