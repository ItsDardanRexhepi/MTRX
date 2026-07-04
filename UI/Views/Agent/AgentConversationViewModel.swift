import Foundation
import Combine

/// Message model for agent conversations. Codable so chats persist.
struct AgentMessage: Identifiable, Codable {
    let id: UUID
    /// Mutable so an on-device reply can stream into the same bubble.
    var text: String
    let role: MessageRole
    let agentName: String?
    let timestamp: Date
    let suggestedActions: [SuggestedAction]

    enum MessageRole: String, Codable {
        case user
        case agent
        case system
    }

    init(text: String, role: MessageRole, agentName: String? = nil, suggestedActions: [SuggestedAction] = []) {
        self.id = UUID()
        // Soften agent copy so replies read warmer and less "AI": the user's #1 gripe
        // is em dashes, so swap them for natural punctuation everywhere a reply is shown
        // (covers both the live model and the local canned responses). The user's own
        // message is never altered.
        self.text = (role == .user) ? text : Self.humanizedReply(text)
        self.role = role
        self.agentName = agentName
        self.timestamp = Date()
        self.suggestedActions = suggestedActions
    }

    /// Replace em dashes (with any surrounding spaces) with a comma + space, then tidy up.
    /// Leaves en dashes in numeric ranges (e.g. "2–5") untouched.
    static func humanizedReply(_ s: String) -> String {
        // Convert only em dashes that sit BETWEEN content (e.g. "open — you're") into a
        // comma. Match horizontal spaces only (never newlines) so lists and line breaks
        // survive, and require non-space on both sides so a line-leading dash bullet and
        // code indentation are left untouched.
        var out = s.replacingOccurrences(
            of: #"(?<=\S)[ \t]*—[ \t]*(?=\S)"#, with: ", ", options: .regularExpression)
        out = out.replacingOccurrences(of: ", ,", with: ",")
        out = out.replacingOccurrences(of: " ,", with: ",")
        return out
    }
}

/// The never-vanish delivery state machine for one chat turn, extracted so the
/// honest-failure invariant is unit-testable against the SAME code the app runs.
///
/// Invariant it enforces (verified in TurnMessageDeliveryTests):
///  • A reply can be superseded or turned into an honest error, but it can NEVER be
///    deleted-with-nothing-in-its-place — nothing silently vanishes, for ANY cause
///    (timeout, cutoff, error, empty stream).
///  • Whitespace-only text is treated as empty, so no blank bubble is ever shown.
///  • The turn is bound to the conversation it started in: if the user switches chats
///    or the idle timer resets the thread mid-flight, the reply is committed to its
///    OWN conversation's stored record — never lost, never cross-posted.
@MainActor
final class TurnMessageDelivery {
    static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let agentName: String?
    private let turnConversationID: UUID?
    private let turnSessionID: String
    private let store: ConversationStore
    private let currentID: () -> UUID?
    private let currentSessionID: () -> String
    private let getMessages: () -> [AgentMessage]
    private let setMessages: ([AgentMessage]) -> Void
    private let setTyping: (Bool) -> Void

    private var liveBubbleID: UUID?
    /// Best partial text shown this turn (empty until the first non-blank token).
    private(set) var shownPartial = ""

    init(agentName: String?,
         turnConversationID: UUID?,
         turnSessionID: String,
         store: ConversationStore,
         currentID: @escaping () -> UUID?,
         currentSessionID: @escaping () -> String,
         getMessages: @escaping () -> [AgentMessage],
         setMessages: @escaping ([AgentMessage]) -> Void,
         setTyping: @escaping (Bool) -> Void) {
        self.agentName = agentName
        self.turnConversationID = turnConversationID
        self.turnSessionID = turnSessionID
        self.store = store
        self.currentID = currentID
        self.currentSessionID = currentSessionID
        self.getMessages = getMessages
        self.setMessages = setMessages
        self.setTyping = setTyping
    }

    /// True while the turn's origin thread is still the visible one. Identity is the PAIR
    /// (conversationID, gatewaySessionId): conversationID changes when a saved chat is
    /// opened; gatewaySessionId changes on every new/switched chat — including EPHEMERAL
    /// ones whose conversationID stays nil. Comparing both detects ANY switch, so an
    /// in-flight reply never renders into or cross-posts to the wrong (e.g. new-agent) thread.
    var stillCurrent: Bool {
        currentID() == turnConversationID && currentSessionID() == turnSessionID
    }

    /// Persist the turn's live thread synchronously to its origin record so a completed
    /// reply is durable immediately — it cannot be lost to the 300ms persistence debounce
    /// if the user switches chats right after it lands. No-op for ephemeral (no record).
    private func persistOrigin(_ msgs: [AgentMessage]) {
        guard let convID = turnConversationID else { return }
        store.update(id: convID, messages: msgs)
    }

    /// Commit into the ORIGIN conversation's saved record when the user navigated away.
    /// For a standalone append (the cut-off note) `ensurePartial` first makes sure the
    /// partial the note refers to is actually in the record — a fast swap can beat the
    /// persistence debounce and leave the shown partial unsaved, stranding the note.
    private func commitToOriginStore(_ msg: AgentMessage, replacingLive: Bool, ensurePartial: Bool = false) {
        guard let convID = turnConversationID else { return }   // ephemeral: no record to persist to
        var stored = store.conversation(id: convID)?.messages ?? []
        if replacingLive, let id = liveBubbleID,
           let sidx = stored.firstIndex(where: { $0.id == id }) {
            stored[sidx] = msg
        } else {
            if ensurePartial, !shownPartial.isEmpty, stored.last?.text != shownPartial {
                stored.append(AgentMessage(text: shownPartial, role: .agent, agentName: agentName))
            }
            stored.append(msg)
        }
        store.update(id: convID, messages: stored)
    }

    /// Upsert the single live bubble with a streamed partial. Blank text and swapped
    /// threads are ignored (a partial never renders into the wrong conversation).
    func showLive(_ raw: String) {
        let t = AgentMessage.humanizedReply(raw)
        guard !Self.isBlank(t) else { return }
        shownPartial = t
        guard stillCurrent else { return }
        setTyping(false)
        var msgs = getMessages()
        if let id = liveBubbleID, let idx = msgs.firstIndex(where: { $0.id == id }) {
            msgs[idx].text = t
        } else {
            let m = AgentMessage(text: t, role: .agent, agentName: agentName)
            liveBubbleID = m.id
            msgs.append(m)
        }
        setMessages(msgs)
    }

    /// Deliver the final answer (+ optional actions). Supersedes the live bubble in place
    /// AND persists synchronously, or commits to the origin record if the user navigated
    /// away. Never blank.
    func finishLive(_ raw: String, actions: [SuggestedAction] = []) {
        let t = AgentMessage.humanizedReply(raw)
        guard !Self.isBlank(t) else { return }
        let msg = AgentMessage(text: t, role: .agent, agentName: agentName, suggestedActions: actions)
        if stillCurrent {
            var msgs = getMessages()
            if actions.isEmpty, let id = liveBubbleID,
               let idx = msgs.firstIndex(where: { $0.id == id }) {
                msgs[idx].text = t
            } else {
                if let id = liveBubbleID { msgs.removeAll { $0.id == id } }
                msgs.append(msg)
            }
            setMessages(msgs)
            persistOrigin(msgs)          // durable now — never depend on the debounce
        } else {
            commitToOriginStore(msg, replacingLive: true)
        }
        liveBubbleID = nil
        setTyping(false)
    }

    /// Append a standalone assistant message (e.g. the honest cut-off note) beside
    /// whatever is already there — live thread if current, else the origin record.
    /// Preserves the referenced partial in the record either way.
    func appendAssistant(_ raw: String) {
        let t = AgentMessage.humanizedReply(raw)
        guard !Self.isBlank(t) else { return }
        let msg = AgentMessage(text: t, role: .agent, agentName: agentName)
        if stillCurrent {
            var msgs = getMessages()
            msgs.append(msg)
            setMessages(msgs)
            persistOrigin(msgs)
        } else {
            commitToOriginStore(msg, replacingLive: false, ensurePartial: true)
        }
    }
}

/// ViewModel for the agent conversation interface.
@MainActor
final class AgentConversationViewModel: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var inputText = ""
    @Published var isTyping = false
    /// Set when the agent has navigated the app — the chat slides away.
    @Published var dismissRequested = false
    @Published var activeAgent: AgentAccessControl.ActiveAgent = .trinity
    @Published var showFirstBoot = false
    @Published var isOffline: Bool = false

    /// Gateway /ws streaming session — one per chat thread, regenerated on a
    /// fresh chat so server-side conversation memory tracks the local thread.
    private var gatewaySessionId = UUID().uuidString

    // MARK: - Voice input (V3 — on-device STT, Tier 1)
    @Published var isListening = false
    @Published var voiceError: String?
    private let transcriber = SpeechTranscriber.shared

    /// Armed when the user sends a message by voice; the resulting reply is spoken
    /// back in Trinity's voice. Set per-send in `sendMessage(viaVoice:)` and consumed
    /// in `speakIfEnabled`, so typed messages stay silent — voice in, voice out;
    /// text in, text out.
    private var speakNextReply = false

    /// The single "tap to speak" control for a voice turn. Tap → listen; then speak and
    /// PAUSE (the turn ends on its own) or tap again to end it now — either way the heard
    /// text auto-sends and Trinity speaks her reply aloud. Tap while she's speaking to
    /// barge in and stop her. On-device transcription (SFSpeechRecognizer,
    /// requiresOnDeviceRecognition) for Tier-1 languages; nothing leaves the device.
    func toggleVoiceTurn() {
        // While listening, a tap ENDS the turn gracefully (finish, not cancel) so the
        // recognizer delivers the final transcription → it auto-sends and Trinity speaks
        // the reply. A pause ends the turn the same way (transcriber silence timer), so
        // it's hands-free. (The old cancel path delivered nothing — hence "only dictation".)
        if isListening { transcriber.finishTranscription(); return }
        if isSpeaking { trinityVoice.stop(); isSpeaking = false; return }
        startVoiceInput()
    }

    func startVoiceInput() {
        voiceError = nil
        // Barge-in + clean handoff: stop any in-progress speech before recording, so the
        // session moves .playback → .record and the mic never captures Trinity's own voice.
        trinityVoice.stop()
        isSpeaking = false
        transcriber.requestAuthorization { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.voiceError = "Voice input needs Microphone and Speech Recognition access. Turn both on in Settings → Privacy to talk to Trinity."
                return
            }
            do {
                try self.transcriber.startTranscription(
                    onPartial: { [weak self] partial in
                        DispatchQueue.main.async { self?.inputText = partial }
                    },
                    onFinal: { [weak self] result in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.inputText = result.text
                            self.isListening = false
                            // Voice turn: auto-send the heard text and speak the reply back.
                            let heard = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !heard.isEmpty else { return }
                            self.sendMessage(viaVoice: true)
                        }
                    },
                    onError: { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.isListening = false
                            self?.voiceError = "I couldn't quite catch that — let's try again."
                        }
                    }
                )
                self.isListening = true
            } catch {
                self.isListening = false
                self.voiceError = "Voice input isn't available right now."
            }
        }
    }

    func stopVoiceInput() {
        transcriber.stopTranscription()
        isListening = false
    }

    // MARK: - Voice output (V4 — on-device TTS, Tier 1)
    @Published var isSpeaking = false
    private let trinityVoice = TrinityVoice()

    /// Speak an agent reply when this turn was started by voice (see `speakNextReply`). The
    /// flag is consumed here so exactly one reply per voice turn is spoken and the next typed
    /// reply stays silent. On-device, in the reply's OWN language for Tier-1 languages; for a
    /// language with no on-device voice we stay SILENT (the text reply still shows) rather than
    /// speak it in the wrong voice — honest, not faked. Tier-2 neural TTS is gated behind
    /// ExtendedLanguageGate and wired with credentials later. Money-isolated.
    func speakIfEnabled(_ text: String) {
        let shouldSpeak = speakNextReply
        speakNextReply = false
        guard shouldSpeak else { return }
        let spoken = Self.strippedForSpeech(text)
        guard !spoken.isEmpty else { return }
        let lang = NaturalLanguageProcessor.shared.languageProfile(for: spoken)
        guard lang.tier1Supported else { return }
        // V5 — clean handoff: stop listening before speaking so the session moves .record → .playback
        // without a clash, and we never transcribe Trinity's own voice back into the input.
        if isListening { stopVoiceInput() }
        Task {
            isSpeaking = true
            await trinityVoice.speak(spoken, languageCode: lang.code)
            isSpeaking = false
        }
    }

    /// Strip markdown so TTS doesn't read "asterisk asterisk" etc.
    private static func strippedForSpeech(_ text: String) -> String {
        var s = text
        for token in ["**", "__", "`", "#", "*", "_", ">"] { s = s.replacingOccurrences(of: token, with: "") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let accessControl = AgentAccessControl.shared
    private let morpheus = MorpheusInterventions.shared
    private var userID: String = ""
    private var userType: AgentAccessControl.UserType = .consumer

    /// Shared wallet state — Trinity's demo actions execute against this,
    /// so results are immediately visible in the Account → Wallet tab.
    private weak var walletManager: WalletManager?

    /// Real portfolio adapter over the same WalletManager. Supplies the MEASURED
    /// daily change + per-holding allocation used to ground money answers — so the
    /// live chat no longer relies on WalletManager's hardcoded portfolioChange24h.
    private var portfolioProvider: WalletPortfolioProvider?

    /// Action parsed from the user's message, awaiting their confirmation.
    private var pendingAction: TrinityDemoAction?

    /// Set when the user explicitly picks an agent ("talk to morpheus");
    /// outranks automatic routing until they switch back to Trinity.
    private var manualAgentOverride: AgentAccessControl.ActiveAgent?

    /// On-device conversation brain (Apple Foundation Models on iOS 26+).
    /// One router per conversation so the model session keeps context.
    private let inference = InferenceRouter()

    /// Persistent chat storage — every conversation belongs to one agent.
    private let store = ConversationStore.shared
    private(set) var conversationID: UUID?
    /// When true the conversation is never written to the store and never
    /// restored — used by the Home pop-up chat, which starts fresh every
    /// time and is saved nowhere.
    var ephemeral = false
    private var cancellables = Set<AnyCancellable>()
    private var isConfigured = false

    /// Maximum number of recent messages to include as conversation context for API calls.
    private let maxContextMessages = 10

    @MainActor
    func setup(userID: String, walletManager: WalletManager? = nil) {
        self.userID = userID
        if let walletManager {
            self.walletManager = walletManager
            self.portfolioProvider = WalletPortfolioProvider(wallet: walletManager)
        }
        self.userType = accessControl.userType(for: userID)

        // Preload Apple Intelligence model assets so Trinity's first
        // reply doesn't pay the cold-start cost.
        inference.prewarmOnDevice()

        // Grab a location fix while the app is foregrounded so weather
        // works instantly — and still works later from Siri in the
        // background, where a fresh fix may not be possible.
        TrinityLocationProvider.shared.warmUp()

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

        guard !isConfigured else { return }
        isConfigured = true

        // Resume the most recent saved chat, or open a fresh one. Ephemeral
        // chats (the Home pop-up) never resume — always a clean slate.
        if ephemeral {
            startNewConversation(agent: .trinity, announce: false)
        } else if let recent = store.conversations.first, !recent.messages.isEmpty {
            openConversation(recent)
        } else {
            startNewConversation(agent: .trinity, announce: true)
        }

        // Continuously persist the active conversation as it changes.
        $messages
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] msgs in
                guard let self, let id = self.conversationID else { return }
                self.store.update(id: id, messages: msgs)
            }
            .store(in: &cancellables)
    }

    // MARK: - Conversations

    /// Open a fresh chat bound to `agent`.
    func startNewConversation(agent: AgentAccessControl.ActiveAgent, announce: Bool = true) {
        inference.resetAllSessions()
        if ephemeral {
            // No store record — this chat is saved nowhere. Pin the agent
            // explicitly (even Trinity) so an owner's default-to-Neo routing
            // can't take over — the window is whoever you last asked for.
            conversationID = nil
            manualAgentOverride = agent
        } else {
            let convo = store.create(agent: agent)
            conversationID = convo.id
            manualAgentOverride = (agent == .trinity) ? nil : agent
        }
        activeAgent = agent
        pendingAction = nil
        showFirstBoot = false
        // Start every new chat empty so the user's own first message is the first
        // bubble in the thread. The agent's greeting lives in the centered overlay
        // (which fades the moment they start typing) — never as a pre-seeded agent
        // bubble that would push the user's first line down. `announce` is retained
        // for call-site compatibility but no longer seeds a message.
        _ = announce
        messages = []
        // Fresh chat = fresh gateway streaming session, so the server-side
        // conversation memory on /ws starts clean alongside the local thread.
        gatewaySessionId = UUID().uuidString
    }

    /// Jump straight into an agent's chat (most recent, or fresh) —
    /// used by the Home screen agent cards.
    func openAgentChat(_ agent: AgentAccessControl.ActiveAgent) {
        if let id = conversationID, store.conversation(id: id)?.agent == agent { return }
        if let existing = store.mostRecent(agent: agent) {
            openConversation(existing)
        } else {
            startNewConversation(agent: agent)
        }
    }

    /// Load a saved chat.
    func openConversation(_ convo: AgentChatRecord) {
        inference.resetAllSessions()
        conversationID = convo.id
        manualAgentOverride = (convo.agent == .trinity) ? nil : convo.agent
        activeAgent = convo.agent
        pendingAction = nil
        showFirstBoot = false
        // Older builds seeded an agent "greeting" as the first bubble. Drop any leading
        // non-user messages so the user's own message is always first — the greeting
        // lives in the centred splash now, never in the thread. The cleaned thread is
        // re-persisted on the next change, so the stale greeting heals itself.
        messages = Self.withoutLeadingGreeting(convo.messages)
    }

    /// Strip any leading agent/system messages (a stale seeded greeting) so the first
    /// bubble is the user's. A greeting-only chat opens empty.
    private static func withoutLeadingGreeting(_ msgs: [AgentMessage]) -> [AgentMessage] {
        guard let firstUser = msgs.firstIndex(where: { $0.role == .user }) else { return [] }
        return firstUser == 0 ? msgs : Array(msgs[firstUser...])
    }

    /// "Talk to Morpheus" opens that agent's own chat — the most recent
    /// one, or a fresh one — keeping every agent's history separate.
    private func transferToAgentChat(_ target: AgentAccessControl.ActiveAgent) {
        // Ephemeral windows (the Home pop-up) just switch the agent in place —
        // fresh, saved nowhere — never resuming a stored chat.
        if ephemeral {
            if activeAgent == target {
                messages.append(AgentMessage(
                    text: "You're already speaking with \(Self.displayName(of: target)).",
                    role: .system
                ))
                return
            }
            startNewConversation(agent: target, announce: true)
            return
        }
        if let id = conversationID, store.conversation(id: id)?.agent == target {
            messages.append(AgentMessage(
                text: "You're already speaking with \(Self.displayName(of: target)).",
                role: .system
            ))
            return
        }
        if let existing = store.mostRecent(agent: target) {
            openConversation(existing)
            // Resuming a chat that already has history — greet like a
            // returning conversation, never like a brand-new one.
            messages.append(AgentMessage(
                text: Self.resumeLine(for: target),
                role: .agent,
                agentName: Self.displayName(of: target)
            ))
        } else {
            startNewConversation(agent: target)
        }
    }

    static func displayName(of agent: AgentAccessControl.ActiveAgent) -> String {
        switch agent {
        case .trinity: return "Trinity"
        case .morpheus: return "Morpheus"
        case .neo: return "Neo"
        }
    }

    /// Said when stepping back into an existing chat — picks the thread
    /// up rather than pretending it's new.
    private static func resumeLine(for agent: AgentAccessControl.ActiveAgent) -> String {
        switch agent {
        case .trinity: return "Back with you — where were we?"
        case .morpheus: return "I'm listening again."
        case .neo: return "Channel re-opened."
        }
    }

    // MARK: - Agent Switching

    /// Switch the active agent. Only available to owner users.
    /// - Parameter agent: The agent to switch to.
    func switchAgent(to agent: AgentAccessControl.ActiveAgent) {
        guard userType == .owner else {
            // Consumers cannot switch agents — Trinity handles routing
            messages.append(AgentMessage(
                text: "I'm here to help you directly. What would you like to do?",
                role: .agent,
                agentName: "Trinity"
            ))
            return
        }

        let previousAgent = activeAgent
        activeAgent = agent

        let agentName: String
        switch agent {
        case .trinity: agentName = "Trinity"
        case .morpheus: agentName = "Morpheus"
        case .neo: agentName = "Neo"
        }

        if previousAgent != agent {
            messages.append(AgentMessage(
                text: "Switched to \(agentName). How can I assist you?",
                role: .system
            ))
        }
    }

    // MARK: - Send Message

    func sendMessage(viaVoice: Bool = false) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Voice turns speak the reply back in Trinity's voice; typed turns stay silent.
        speakNextReply = viaVoice

        // The user actually talked to an agent — that completes the goal.
        DailyFlow.shared.mark(.agent)

        // Add user message
        messages.append(AgentMessage(text: text, role: .user))
        inputText = ""
        // A focused multiline TextField can keep showing its text when cleared
        // mid-autocomplete; re-clear on the next runloop so the field reliably empties.
        DispatchQueue.main.async { [weak self] in self?.inputText = "" }

        // Manual agent switching — "talk to morpheus", "bring trinity".
        // Each agent keeps its own separate chat; switching opens theirs.
        if let target = Self.agentSwitchTarget(in: text) {
            if target == .neo && userType != .owner {
                respondAsTrinity("Neo coordinates the platform itself and answers only to the owner. Morpheus and I are here for you — what do you need?")
                return
            }
            transferToAgentChat(target)
            return
        }

        // When Trinity's on-device model (Apple Foundation Models) is
        // available, she runs fully model-driven: the model — with its tools —
        // handles capability questions, app tasks, navigation, music, and
        // actions itself. No scripted intent matching. The scripted handlers
        // below stay as the fallback for Neo/Morpheus and for devices without
        // Apple Intelligence.
        let convoAgent = conversationID.flatMap { store.conversation(id: $0)?.agent } ?? manualAgentOverride ?? activeAgent
        let trinityModelDriven = (convoAgent == .trinity) && inference.isOnDeviceAvailable

        if !trinityModelDriven {
            // A direct "what can you do / help me get around the app" question
            // always gets a real, useful rundown — never a deflection.
            if Self.isCapabilityQuestion(text) {
                respondWithCapabilities()
                return
            }

            // In-app tasks — "make a social post about...", "change my bio
            // to...", "set my theme to violet". The agent does it, right here.
            if handleAppTask(text: text) {
                return
            }

            // App navigation — "open my social feed", "take me to the wallet",
            // "open events". The agent drives the app there, then docks as a
            // floating orb so she stays one tap away until swiped off.
            if let destination = Self.appDestination(in: text) {
                navigate(to: destination)
                return
            }
        }

        // Check access control
        let intent = UserIntent.parse(text)
        let route = accessControl.routeAgent(for: userID, intent: intent)

        switch route {
        case .allowed(let agent):
            // The open conversation's agent owns the room. Routing never
            // reassigns who answers mid-chat — Trinity's chat is always
            // Trinity, no matter what the access router prefers.
            let conversationAgent = conversationID.flatMap { store.conversation(id: $0)?.agent }
            let effective = conversationAgent ?? manualAgentOverride ?? agent
            activeAgent = effective

            // Scripted action engine — now only the FALLBACK for when Trinity's
            // on-device model isn't available. When it is, she's fully
            // model-driven (above) and her tools handle actions instead. The
            // Morpheus Face-ID gate for transfers lives in this scripted path
            // and stays intact for that fallback.
            if effective == .trinity, !inference.isOnDeviceAvailable, handleDemoConversation(text: text) {
                return
            }
            processWithAgent(text: text, agent: effective)

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
            // Owner authorization: Morpheus verifies identity on the
            // spot instead of dead-ending the request.
            activeAgent = .morpheus
            messages.append(AgentMessage(
                text: "This operation requires owner authorization. Verify your identity to continue.",
                role: .agent,
                agentName: "Morpheus"
            ))
            Task { @MainActor in
                let verified = (try? await BiometricAuth().authenticate(
                    reason: "Owner authorization required"
                )) ?? false
                if verified {
                    messages.append(AgentMessage(
                        text: "Owner verified. Proceeding.",
                        role: .agent,
                        agentName: "Morpheus"
                    ))
                    processWithAgent(text: text, agent: .neo)
                } else {
                    activeAgent = .trinity
                    messages.append(AgentMessage(
                        text: "Authorization was not completed. The request is blocked.",
                        role: .agent,
                        agentName: "Morpheus"
                    ))
                }
            }

        case .blocked:
            // Silently ignore banned users
            break
        }
    }

    // MARK: - In-App Tasks

    /// The agent's hands: anything the user could do themselves in the
    /// app, they can just ask for. Returns true when the message was a
    /// task and has been handled.
    private func handleAppTask(text: String) -> Bool {
        let lower = text.lowercased()
        let speaker = conversationID.flatMap { store.conversation(id: $0)?.agent } ?? activeAgent

        // 1 — Publish a social post. Dictated content posts verbatim;
        // "about X" gets written by the agent first, then posted.
        let postVerbs = ["make", "write", "create", "publish", "put up", "post"]
        let mentionsPost = lower.contains("post") || lower.contains("tweet")
        if mentionsPost, postVerbs.contains(where: { lower.contains($0) }) {
            if let dictated = Self.quotedContent(in: text) ?? Self.content(after: ["saying ", "that says "], in: text) {
                publishToFeed(dictated, as: speaker)
                return true
            }
            if let topic = Self.content(after: ["about ", "on "], in: text) {
                composeAndPost(topic: topic, as: speaker)
                return true
            }
            // "Make a social post for me" with no topic — ask once.
            messages.append(AgentMessage(
                text: "Happy to. What should the post say — or give me a topic and I'll write it.",
                role: .agent,
                agentName: Self.displayName(of: speaker)
            ))
            return true
        }

        // 2 — Update bio.
        if lower.contains("bio"), lower.contains("my"),
           ["set", "change", "update", "make"].contains(where: { lower.contains($0) }),
           let newBio = Self.content(after: ["to "], in: text) {
            SocialIdentity.shared.bio = newBio
            confirmTask("Done — your bio now reads \"\(newBio)\".", as: speaker)
            return true
        }

        // 3 — Update username / handle.
        if (lower.contains("username") || lower.contains("handle")), lower.contains("my"),
           ["set", "change", "update", "make"].contains(where: { lower.contains($0) }),
           let newHandle = Self.content(after: ["to "], in: text) {
            let cleaned = newHandle.replacingOccurrences(of: " ", with: "").lowercased()
            SocialIdentity.shared.username = cleaned
            confirmTask("Done — you're \(cleaned.hasPrefix("@") ? cleaned : "@" + cleaned) now.", as: speaker)
            return true
        }

        // 4 — Social theme color.
        if lower.contains("theme"),
           ["set", "change", "update", "switch", "make"].contains(where: { lower.contains($0) }) {
            for preset in SocialTheme.presets {
                let key = preset.name.lowercased()
                if lower.contains(key) || key.split(separator: " ").contains(where: { lower.contains($0) }) {
                    SocialTheme.shared.set(preset.color)
                    confirmTask("Theme switched to \(preset.name).", as: speaker)
                    return true
                }
            }
            let names = SocialTheme.presets.map(\.name).joined(separator: ", ")
            confirmTask("Which color? I can set: \(names).", as: speaker)
            return true
        }

        return false
    }

    /// Text inside straight or smart double quotes, if any. Single
    /// quotes are skipped — apostrophes would false-match.
    private static func quotedContent(in text: String) -> String? {
        for (open, close) in [("\"", "\""), ("\u{201C}", "\u{201D}")] {
            if let start = text.range(of: open),
               let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
                let inner = String(text[start.upperBound..<end.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if inner.count > 2 { return inner }
            }
        }
        return nil
    }

    /// Everything after the first matching marker, cleaned up.
    private static func content(after markers: [String], in text: String) -> String? {
        let lower = text.lowercased()
        for marker in markers {
            if let range = lower.range(of: marker) {
                let tail = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.\u{201C}\u{201D}"))
                if tail.count > 1 { return tail }
            }
        }
        return nil
    }

    private func publishToFeed(_ content: String, as speaker: AgentAccessControl.ActiveAgent) {
        let social = SocialViewModel.shared
        social.composerText = content
        social.composerImageData = nil
        social.composerVideoFileName = nil
        social.composerLink = ""
        social.attachProof = false
        social.publishPost(displayName: UserDefaults.standard.string(forKey: "displayName") ?? "You")
        social.composerText = ""
        DailyFlow.shared.mark(.social)
        confirmTask("Posted to your feed:\n\n\"\(content)\"\n\nIt's live on Social and in your Home feed window.", as: speaker)
    }

    /// Writes the post with the on-device model, then publishes it.
    private func composeAndPost(topic: String, as speaker: AgentAccessControl.ActiveAgent) {
        isTyping = true
        let persona: InferenceRouter.Persona = {
            switch speaker {
            case .trinity: return .trinity
            case .morpheus: return .morpheus
            case .neo: return .neo
            }
        }()
        Task { @MainActor in
            let draft = await inference.generateOnDeviceOnly(
                prompt: "Write a short, natural social media post (under 220 characters) about: \(topic). Reply with ONLY the post text — no quotes, no preamble.",
                context: Self.dateTimeLine(),
                persona: persona
            )
            isTyping = false
            let content = (draft ?? "\(topic) — watch this space.")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            publishToFeed(content, as: speaker)
        }
    }

    private func confirmTask(_ line: String, as speaker: AgentAccessControl.ActiveAgent) {
        messages.append(AgentMessage(
            text: line,
            role: .agent,
            agentName: Self.displayName(of: speaker)
        ))
    }

    // MARK: - App Navigation

    enum AppDestination {
        case tab(Int, String)
        case service(HomeService, String)
    }

    /// Detects "open / show / take me to <somewhere in the app>".
    static func appDestination(in text: String) -> AppDestination? {
        let lower = text.lowercased()
        let verbs = ["open", "show", "go to", "goto", "take me", "bring up", "pull up", "launch", "switch to", "navigate"]
        guard verbs.contains(where: { lower.contains($0) }) else { return nil }

        let services: [(HomeService, [String])] = [
            (.pay, ["pay tab", "payments", "pay service"]),
            (.invest, ["invest", "trading"]),
            (.defi, ["yield", "earn service", "earning"]),
            (.shop, ["shop", "marketplace"]),
            (.insure, ["insurance", "insure"]),
            (.game, ["gaming", "games", "play service"]),
            (.events, ["event"]),
            (.domains, ["identity", "domain"]),
            (.storage, ["storage"]),
            (.bridge, ["bridge"])
        ]
        for (service, keys) in services where keys.contains(where: { lower.contains($0) }) {
            return .service(service, service.title)
        }

        let tabs: [(Int, String, [String])] = [
            (3, "Social", ["social", "feed", "my posts", "stories", "messages"]),
            (1, "Build", ["build", "contract"]),
            (4, "Account", ["account", "wallet", "settings", "subscription"]),
            (0, "Discover", ["discover", "trending"]),
            (2, "Home", ["home", "dashboard"])
        ]
        for (index, name, keys) in tabs where keys.contains(where: { lower.contains($0) }) {
            return .tab(index, name)
        }
        return nil
    }

    /// Confirms in the room's voice, switches the app underneath, docks
    /// the agent as a floating orb, then slides the chat away.
    private func navigate(to destination: AppDestination) {
        let name: String
        switch destination {
        case .tab(_, let n): name = n
        case .service(_, let n): name = n
        }
        let speaker = conversationID.flatMap { store.conversation(id: $0)?.agent } ?? activeAgent
        messages.append(AgentMessage(
            text: "On it — opening \(name). I'll be in the corner if you need me.",
            role: .agent,
            agentName: Self.displayName(of: speaker)
        ))
        AgentPresence.shared.dock(speaker)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            switch destination {
            case .tab(let index, _):
                NotificationCenter.default.post(name: .mtrxSwitchTab, object: nil, userInfo: ["index": index])
            case .service(let service, _):
                NotificationCenter.default.post(name: .mtrxSwitchTab, object: nil, userInfo: ["index": 2])
                NotificationCenter.default.post(name: .mtrxOpenService, object: nil, userInfo: ["service": service.rawValue])
            }
            self?.dismissRequested = true
        }
    }

    // MARK: - Process With Agent

    private func processWithAgent(text: String, agent: AgentAccessControl.ActiveAgent, intercepted: Bool = false) {
        isTyping = true

        // Inject temporal context
        let temporal = TemporalContext.shared.currentPrompt()

        // Check Morpheus triggers for consumer users
        if userType == .consumer {
            checkMorpheusTriggers(text: text)
        }

        let agentName: String
        switch agent {
        case .trinity: agentName = "Trinity"
        case .morpheus: agentName = "Morpheus"
        case .neo: agentName = "Neo"
        }

        // Build conversation context from recent messages
        let conversationContext = buildConversationContext()

        // V0 — multilingual foundation: detect the user's language on-device (shared by text
        // and voice; no data leaves the device). Drives response-language mirroring below via
        // langProfile.mirrorInstruction, and the honest English-only offline fallback.
        let langProfile = NaturalLanguageProcessor.shared.languageProfile(for: text)

        Task {
            // 1 — On-device Apple Intelligence (instant, private, offline).
            // The session keeps its own conversation context across turns.
            // Every turn carries the local date/time; live wallet data is
            // attached ONLY when the message is about money, so the model
            // never drifts into reciting the portfolio.
            var contextLine = Self.dateTimeLine()
            // Real portfolio snapshot (measured change + allocation) from the
            // WalletPortfolioProvider, fetched once per turn on the main actor.
            let portfolioSnapshot = await portfolioProvider?.fetchSnapshot()
            // Every agent sees the same live picture of the user's app
            // world on every turn — portfolio, plan, and daily rhythm.
            contextLine += " " + appAwarenessLine(snapshot: portfolioSnapshot)
            if Self.isFinanceRelated(text) {
                contextLine += " " + liveContextLine(snapshot: portfolioSnapshot)
            }
            // The conversation's own memory rides along on every turn:
            // restored chats keep their context across app relaunches,
            // and switching between saved chats never crosses wires.
            contextLine += Self.transcriptRecap(messages)
            // Mirror the user's language on the on-device model (within its supported set).
            if !langProfile.mirrorInstruction.isEmpty { contextLine += " " + langProfile.mirrorInstruction }
            let persona: InferenceRouter.Persona = {
                switch agent {
                case .trinity: return .trinity
                case .morpheus: return .morpheus
                case .neo: return .neo
                }
            }()
            // Part 3 — local-first routing decision (exact criteria documented on
            // ReasoningRouter). On-device by default; escalate to the cloud ONLY when
            // the task exceeds on-device capability (long / multi-step / expert /
            // large-context / forced). This replaces the implicit "try on-device then
            // fall to gateway" with an explicit, documented local-first decision.
            let reasoningRoute = ReasoningRouter().route(
                prompt: text,
                onDeviceAvailable: inference.isOnDeviceAvailable,
                cloudReachable: PendingCredentials.isBackendConfigured,
                privacyMode: inference.isPrivacyModeEnabled,
                forceCloud: PendingCredentials.forceCloudReasoning
            )
            // V1 — Tier-1 routing: the on-device Apple model runs only for languages it
            // handles well (langProfile.tier1Supported). A non-Tier-1 language skips it and
            // goes straight to the broader gateway, so we never garble output by nudging the
            // on-device model toward a language it can't speak. (Tier-2 extended coverage for
            // languages outside on-device is gated to Enterprise + opt-in in V2.)
            // On-device runs only when the router chose it; `.escalateToCloud` skips
            // straight to the gateway below, and any failure still falls through to the
            // honest no-reasoning-source message (never a scripted answer).
            // The never-vanish delivery state machine for this turn (see TurnMessageDelivery).
            // Bound to the conversation it started in, so a mid-flight chat switch / idle
            // reset commits the reply to its OWN thread instead of losing or cross-posting
            // it. Whitespace-only text is treated as empty (no blank bubble). Every failure
            // path below routes through delivery.finishLive / .appendAssistant, so a reply
            // can be superseded or turned into an honest error but can NEVER silently vanish.
            let delivery = TurnMessageDelivery(
                agentName: agentName,
                turnConversationID: conversationID,
                turnSessionID: gatewaySessionId,
                store: store,
                currentID: { [weak self] in self?.conversationID },
                currentSessionID: { [weak self] in self?.gatewaySessionId ?? "" },
                getMessages: { [weak self] in self?.messages ?? [] },
                setMessages: { [weak self] in self?.messages = $0 },
                setTyping: { [weak self] in self?.isTyping = $0 }
            )

            if !intercepted && langProfile.tier1Supported && reasoningRoute == .onDevice {
                // Stream the on-device reply into the live bubble so the agent starts
                // answering the instant the first token lands.
                let onDevice = await inference.generateOnDeviceStreaming(
                    prompt: text,
                    context: contextLine,
                    persona: persona,
                    onPartial: { partial in
                        guard !partial.isEmpty else { return }
                        delivery.showLive(partial)
                    }
                )
                if let onDevice {
                    delivery.finishLive(onDevice)
                    speakIfEnabled(onDevice)
                    return
                }
                // On-device failed — possibly AFTER streaming a partial (a long answer
                // that exceeded the small model's budget, then threw). Do NOT delete the
                // partial: keep it on screen and show the typing indicator while we
                // escalate to the gateway, which supersedes it with the complete answer.
                if !delivery.shownPartial.isEmpty { isTyping = true }
            }

            // Part 3 — the router's decision is binding on the CLOUD too. Privacy mode
            // and a no-source route (.honestlyUnavailable) must NEVER touch the gateway:
            // if on-device didn't answer, fail honestly rather than sending data
            // off-device. (.escalateToCloud, and a non-privacy .onDevice miss, fall
            // through to the gateway below.)
            if inference.isPrivacyModeEnabled || reasoningRoute == .honestlyUnavailable {
                let honest = Self.noReasoningSourceMessage(
                    isEnglish: langProfile.isEnglish,
                    languageName: langProfile.displayName
                )
                delivery.finishLive(honest)
                speakIfEnabled(honest)
                return
            }

            // V2 — Tier-2 gate: a language outside on-device Tier-1 coverage is Extended Language
            // Support, gated behind Enterprise + the privacy opt-in. When the gate isn't satisfied,
            // show an honest, offer-framed message (never a barrier) instead of a best-effort reply
            // in a language we don't yet support for this user. The real extended cloud service is
            // wired in V3/V4, behind this same ExtendedLanguageGate.
            if !langProfile.tier1Supported && !langProfile.isEnglish && !ExtendedLanguageGate.isEnabled {
                delivery.finishLive(ExtendedLanguageGate.offerMessage(for: langProfile.displayName))
                return
            }

            // 2 — Gateway (when Apple Intelligence isn't available / didn't answer)
            let gatewayContext = temporal + "\n" + conversationContext + (langProfile.mirrorInstruction.isEmpty ? "" : "\n" + langProfile.mirrorInstruction)

            // 2a — WS streaming (Phase 6): render the reply into the SAME live bubble.
            // A stream failure keeps whatever is shown and falls through to REST — a
            // partial is superseded by the finished reply, never deleted.
            if PendingCredentials.isBackendConfigured {
                do {
                    let final = try await GatewayChatStream.stream(
                        message: text,
                        agent: agentName.lowercased(),
                        sessionId: gatewaySessionId,
                        context: gatewayContext,
                        onToken: { partial in
                            guard !partial.isEmpty else { return }
                            delivery.showLive(partial)
                        }
                    )
                    if !TurnMessageDelivery.isBlank(final) {
                        delivery.finishLive(final)
                        speakIfEnabled(final)
                        return
                    }
                    // Empty/whitespace final — treat as a failed stream; keep any shown text, use REST.
                    if !delivery.shownPartial.isEmpty { isTyping = true }
                } catch {
                    // Honest degradation: keep any shown text, log, let REST answer.
                    if !delivery.shownPartial.isEmpty { isTyping = true }
                    print("GatewayChatStream: falling back to REST — \(error)")
                }
            }

            do {
                let apiResponse = try await MTRXAPIClient.shared.sendAgentMessage(
                    agent: agentName.lowercased(),
                    message: text,
                    context: gatewayContext,
                    conversationHistory: buildHistoryPayload()
                )
                let restText = apiResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
                // An empty 200 is a failed reply, not a blank bubble — route it to the
                // honest ending below instead of showing nothing.
                guard !restText.isEmpty else {
                    throw MTRXAPIError.decodingFailed("empty agent response")
                }
                let actions = (apiResponse.suggestedActions ?? []).map {
                    SuggestedAction(title: $0.label, description: $0.label, action: $0.action)
                }
                delivery.finishLive(restText, actions: actions)
                speakIfEnabled(restText)
            } catch {
                // Honest failure — honest-failure law absolute. On-device tried, the
                // cloud brain tried; when NEITHER delivered she says so plainly, never a
                // scripted answer dressed up as reasoning. Crucially: if a partial WAS
                // shown, it is PRESERVED (a cut-off answer beats a vanished one) and an
                // honest note is appended — a message can never silently disappear.
                isOffline = true
                isTyping = false
                if !delivery.shownPartial.isEmpty {
                    // A partial WAS shown — it is already committed (the live bubble if this
                    // is still the visible thread, or the origin conversation's saved record
                    // if the user navigated away). Keep it and add an honest cut-off note
                    // beside it. The partial is never deleted; nothing ever vanishes.
                    let note = Self.cutOffNote(isEnglish: langProfile.isEnglish)
                    delivery.appendAssistant(note)
                    speakIfEnabled(note)
                } else {
                    let honest = Self.noReasoningSourceMessage(
                        isEnglish: langProfile.isEnglish,
                        languageName: langProfile.displayName
                    )
                    delivery.finishLive(honest)
                    speakIfEnabled(honest)
                }
            }
        }
    }

    /// What every agent knows about the app on every turn: portfolio
    /// value, plan, and how the user's day in the app is going.
    private func appAwarenessLine(snapshot: PortfolioSnapshot?) -> String {
        var bits: [String] = []
        if let snapshot {
            // Measured change since the provider's last observation (0 on the first
            // turn) — honest, not the hardcoded portfolioChange24h placeholder.
            bits.append(String(format: "Portfolio $%.2f (%+.2f%% since last check)", snapshot.totalValue, snapshot.dailyChangePercent))
        } else if let wm = walletManager {
            bits.append(String(format: "Portfolio $%.2f", wm.totalPortfolioValue))
        }
        if let tier = UserDefaults.standard.string(forKey: "com.mtrx.subscriptionTier"), !tier.isEmpty {
            bits.append("Plan: \(tier)")
        }
        let flow = DailyFlow.shared
        let done = DailyFlow.Goal.allCases
            .filter { flow.completed.contains($0.rawValue) }
            .map(\.rawValue)
        bits.append("Daily flow \(flow.completed.count)/3" + (done.isEmpty ? "" : " (\(done.joined(separator: ", ")) done)"))
        let name = UserDefaults.standard.string(forKey: "displayName") ?? ""
        if !name.isEmpty { bits.append("User: \(name)") }
        return "App state — " + bits.joined(separator: "; ") + "."
    }

    /// One-line live snapshot of the user's wallet for grounding
    /// on-device responses. Plain English, no addresses.
    private func liveContextLine(snapshot: PortfolioSnapshot?) -> String {
        guard let wm = walletManager else { return "" }
        let total = Self.usdFormatter.string(from: NSNumber(value: wm.totalPortfolioValue)) ?? "$0"
        // Prefer the provider's top holdings with allocation; fall back to a plain list.
        if let snapshot, !snapshot.topHoldings.isEmpty {
            let holdings = snapshot.topHoldings
                .map { h in
                    let value = Self.usdFormatter.string(from: NSNumber(value: h.value)) ?? "$0"
                    return String(format: "%@ %@ (%.0f%%)", value, h.symbol, h.allocation * 100)
                }
                .joined(separator: ", ")
            return "User portfolio: \(total) total — top holdings: \(holdings)."
        }
        let holdings = wm.tokens
            .filter { $0.balance > 0 }
            .map { "\(Self.trim($0.balance)) \($0.symbol)" }
            .joined(separator: ", ")
        return "User portfolio: \(total) total — \(holdings)."
    }

    /// Local date/time line attached to every on-device turn so Trinity
    /// always knows what day and time it is for the user.
    private static func dateTimeLine() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let tz = TimeZone.current.identifier
        return "Now: \(formatter.string(from: Date())) (\(tz))."
    }

    /// Whether a message is about money/wallet topics — the only case
    /// where live portfolio context is attached to the prompt.
    private static func isFinanceRelated(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = [
            "balance", "portfolio", "wallet", "holding", "worth",
            "eth", "usdc", "link", "uni", "aave", "token", "coin", "crypto",
            "send", "transfer", "pay", "swap", "stake", "staking", "unstake",
            "buy", "sell", "trade", "price", "yield", "apy", "defi",
            "nft", "gas", "fee", "money", "fund", "invest", "transaction",
            "$", "dollar", "euro", "pound", "cash", "bucks",
        ]
        return keywords.contains { lower.contains($0) }
    }

    // MARK: - Conversation Context

    /// Build a text summary of recent conversation for API context.
    private func buildConversationContext() -> String {
        let recent = messages.suffix(maxContextMessages)
        guard !recent.isEmpty else { return "" }

        return recent.map { msg in
            let role = msg.role == .user ? "User" : (msg.agentName ?? "Agent")
            return "\(role): \(msg.text)"
        }.joined(separator: "\n")
    }

    /// Build a structured history payload for the API.
    private func buildHistoryPayload() -> [[String: String]] {
        return messages.suffix(maxContextMessages).map { msg in
            [
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.text,
                "agent": msg.agentName ?? ""
            ]
        }
    }

    // MARK: - Demo Action Engine
    //
    // Parses executable intents from natural language, asks for
    // confirmation, then executes against the shared WalletManager so the
    // result is visible app-wide. Runs entirely on-device.

    /// Returns true when the message was handled by the demo engine
    /// (no further processing should occur).
    private func handleDemoConversation(text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1 — A confirmation/cancellation typed in response to a pending action
        if pendingAction != nil {
            let confirms = ["yes", "confirm", "do it", "go ahead", "execute", "send it", "yep", "y"]
            let cancels = ["no", "cancel", "stop", "never mind", "nevermind", "don't", "n"]
            if confirms.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
                executePendingAction()
                return true
            }
            if cancels.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
                cancelPendingAction()
                return true
            }
            // A different message replaces the pending action.
            pendingAction = nil
        }

        // 1.5 — Apple Music control (MusicKit). Trinity can search and play
        // whatever the user asks, plus pause / skip / repeat, when Apple Music
        // is connected. If it isn't, MusicKitManager returns an honest message.
        if let cmd = parseMusicCommand(lower: lower, original: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            handleMusicCommand(cmd)
            return true
        }

        // 2 — Live wallet queries: when Apple Intelligence is available it
        // answers these naturally (the prompt carries live wallet context),
        // so the static summary only serves devices without it.
        if !inference.isOnDeviceAvailable,
           let wm = walletManager,
           lower.contains("balance") || lower.contains("portfolio") || lower.contains("how much do i") {
            respondAsTrinity(livePortfolioSummary(wm))
            return true
        }

        // 3 — Executable action?
        guard let action = parseDemoAction(from: text) else { return false }

        guard let wm = walletManager else { return false }
        pendingAction = action

        // Morpheus appears before consequential moves — crypto or fiat.
        // He takes over the conversation, states the stakes, and demands
        // identity verification (Face ID / passcode) before Trinity may
        // proceed to the normal confirmation.
        let usd = action.usdValue(in: wm)
        var isOutboundTransfer = false
        if case .send = action { isOutboundTransfer = true }
        if case .sendFiat = action { isOutboundTransfer = true }
        if isOutboundTransfer, usd >= 1000 {
            beginMorpheusVerification(for: action, usd: usd, in: wm)
            return true
        }

        presentConfirmation(for: action, in: wm)
        return true
    }

    /// Trinity's standard pre-execution confirmation with action chips.
    private func presentConfirmation(for action: TrinityDemoAction, in wm: WalletManager) {
        respondAsTrinity(
            "Here's what I'm about to do:\n\n\(action.summary(in: wm))\n\nNetwork fees are covered by the platform — you pay no gas. Confirm?",
            actions: [
                SuggestedAction(title: "Confirm & Execute", description: "Execute now", action: "demo_confirm"),
                SuggestedAction(title: "Cancel", description: "Do nothing", action: "demo_cancel"),
            ]
        )
    }

    // MARK: - Morpheus Verification

    /// High-value transfers summon Morpheus into the conversation: he
    /// announces himself, verifies the owner's identity with Face ID
    /// (system passcode as backstop), then hands back to Trinity. A
    /// failed or cancelled verification blocks the transfer outright.
    private func beginMorpheusVerification(for action: TrinityDemoAction, usd: Double, in wm: WalletManager) {
        let amountText = Self.usdFormatter.string(from: NSNumber(value: usd)) ?? String(format: "$%.0f", usd)
        let previousAgent = activeAgent
        activeAgent = .morpheus

        messages.append(AgentMessage(
            text: "I step in when the stakes are real. You are about to move **\(amountText)** — irreversible once executed. Verify your identity to proceed.",
            role: .agent,
            agentName: "Morpheus"
        ))


        isTyping = true
        Task { @MainActor in
            let verified = (try? await BiometricAuth().authenticate(
                reason: "Morpheus: authorize a transfer of \(amountText)"
            )) ?? false
            isTyping = false

            if verified {
                messages.append(AgentMessage(
                    text: "Verification complete. You are who you say you are. Trinity will take it from here.",
                    role: .agent,
                    agentName: "Morpheus"
                ))
                activeAgent = previousAgent
                presentConfirmation(for: action, in: wm)
            } else {
                pendingAction = nil
                activeAgent = previousAgent
                messages.append(AgentMessage(
                    text: "Verification was not completed. The transfer is **blocked** — nothing has moved. If this was you, try again and authenticate when prompted.",
                    role: .agent,
                    agentName: "Morpheus"
                ))
            }
        }
    }

    /// Entry point for tapped suggestion chips.
    func handleSuggestedAction(_ action: String) {
        switch action {
        case "demo_confirm":
            executePendingAction()
        case "demo_cancel":
            cancelPendingAction()
        default:
            // Any other action string is a prompt — submit it as the user.
            inputText = action
            sendMessage()
        }
    }

    private func executePendingAction() {
        guard let action = pendingAction, let wm = walletManager else {
            pendingAction = nil
            return
        }
        pendingAction = nil
        isTyping = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            isTyping = false

            // Deterministic DEMO reference (not a random UUID, not a confirmed
            // on-chain tx). These actions move demo balances only — see wording below.
            let txHash = String(DemoArtifacts.hash(seed: "\(action)").prefix(18))
            switch action {
            case .send(let amount, let token, let recipient):
                if wm.demoSend(amount: amount, tokenSymbol: token, recipient: recipient) {
                    respondAsTrinity(
                        "✅ **Sent (demo).** \(Self.trim(amount)) \(token.uppercased()) moved to \(recipient) in your demo wallet.\n\nDemo reference: `\(txHash)`\nSimulated — not broadcast on-chain · Gas would be covered by MTRX\n\nYour updated demo balance is in Account → Wallet.",
                        actions: [SuggestedAction(title: "Check balance", description: "See updated portfolio", action: "What's my balance?")]
                    )
                } else {
                    respondAsTrinity(insufficientFundsMessage(token: token, in: wm))
                }

            case .sendFiat(let amount, let currency, let recipient):
                let symbol = TrinityDemoAction.fiatSymbol(currency)
                let formatted = String(format: "%@%.2f", symbol, amount)
                if wm.demoSendFiat(amount: amount, currency: currency, recipient: recipient) {
                    respondAsTrinity(
                        "✅ **Sent (demo).** \(formatted) moved to \(recipient) in your demo wallet — instant, no fees.\n\nDemo reference: `\(txHash)` (simulated — not broadcast)\n\nYour demo cash balance just updated in Account → Wallet.",
                        actions: [SuggestedAction(title: "Check balance", description: "See updated portfolio", action: "What's my balance?")]
                    )
                } else {
                    let cash = wm.token("USDC")?.balance ?? 0
                    respondAsTrinity("That's more than your available cash balance — you have \(String(format: "$%.2f", cash)) ready to send. Try a smaller amount.")
                }

            case .swap(let amount, let from, let to):
                if let received = wm.demoSwap(amount: amount, from: from, to: to) {
                    respondAsTrinity(
                        "✅ **Swap complete (demo).** \(Self.trim(amount)) \(from.uppercased()) → \(Self.trim(received)) \(to.uppercased()) at spot rate.\n\nDemo reference: `\(txHash)`\nSimulated — not broadcast on-chain · Gas would be covered by MTRX\n\nBoth demo balances just updated in your wallet.",
                        actions: [SuggestedAction(title: "Check balance", description: "See updated portfolio", action: "What's my balance?")]
                    )
                } else {
                    respondAsTrinity(insufficientFundsMessage(token: from, in: wm))
                }

            case .stake(let amount, let token):
                if wm.demoStake(amount: amount, tokenSymbol: token) {
                    respondAsTrinity(
                        "✅ **Staked (demo).** \(Self.trim(amount)) \(token.uppercased()) is now earning **8.7% APY** in your demo MTRX Staking position.\n\nDemo reference: `\(txHash)`\nSimulated — not broadcast on-chain. Rewards accrue in the demo; you can unstake anytime.\n\nSee the position under Account → Wallet → DeFi.",
                        actions: [SuggestedAction(title: "Check balance", description: "See updated portfolio", action: "What's my balance?")]
                    )
                } else {
                    respondAsTrinity(insufficientFundsMessage(token: token, in: wm))
                }

            case .deploy(let name):
                // Staged pipeline: audit → gate → deploy, then the
                // contract address lands in the transaction history.
                respondAsTrinity("🛡 **Glasswing audit running…** 12-point vulnerability scan on \"\(name)\".")
                try? await Task.sleep(for: .milliseconds(1400))
                let address = wm.demoDeployContract(name: name)
                respondAsTrinity(
                    "✅ **Deployed (demo).** \"\(name)\" is live in your demo environment.\n\n• Glasswing audit: **passed** — 0 critical, 0 high findings\n• Morpheus gate: **cleared**\n• Contract (simulated): `\(address)`\n• Gas would be covered by MTRX\n\nSimulated — not broadcast on-chain. The deployment is recorded in Account → Wallet → Activity.",
                    actions: [SuggestedAction(title: "Deploy another", description: "Start a new deployment", action: "Deploy a contract")]
                )
            }
        }
    }

    private func cancelPendingAction() {
        pendingAction = nil
        respondAsTrinity("Cancelled — nothing was executed. What else can I do for you?")
    }

    // MARK: Demo engine helpers

    private func respondAsTrinity(_ text: String, actions: [SuggestedAction] = []) {
        messages.append(AgentMessage(
            text: text,
            role: .agent,
            agentName: "Trinity",
            suggestedActions: actions
        ))
        speakIfEnabled(text)
    }

    /// True when the user is plainly asking what the agent can do or for
    /// help getting around the app — the question that must never get a
    /// brush-off.
    static func isCapabilityQuestion(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "what can you do", "what do you do", "what can you help",
            "what are you capable", "everything you can do",
            "list of everything", "things you can do", "what can i do",
            "what can you help me with", "show me what you can do",
            "how do i use this", "how does this app work",
            "how does this work", "what are your features",
            "what can this app do", "help me get around",
            "how do i get around", "walk me through"
        ]
        return needles.contains { lower.contains($0) }
    }

    /// A genuinely useful rundown, in the voice of whoever is in the room.
    private func respondWithCapabilities() {
        let text: String
        let name: String
        switch activeAgent {
        case .morpheus:
            name = "Morpheus"
            text = """
            I watch your back in here. I can:

            • Flag risky or irreversible moves before you make them.
            • Verify your identity on high-value transactions.
            • Talk through the safety side of anything you're about to do.

            Sending or swapping is Trinity's job — just say "talk to Trinity." What are you weighing up?
            """
        case .neo:
            name = "Neo"
            text = """
            Full system view, owner. I can:

            • Brief you on Trinity, Morpheus, Oracle, the runtime, and security posture.
            • Coordinate across the agents and surface what needs your attention.
            • Walk you through any part of the platform.

            Execution and money movement route through Trinity with Morpheus gating. What do you want to look at?
            """
        default:
            name = "Trinity"
            text = """
            Happy to — here's the short version of what I can do for you:

            • **Money** — check your balance and portfolio, send, swap or stake crypto, and send plain cash like "send $50 to mom."
            • **Contracts** — deploy and manage smart contracts over in the Build tab.
            • **Social** — post to your feed and update your bio, handle, or theme.
            • **Get around** — open any tab or service for you; just say "open my wallet" or "take me to Discover."
            • **Look things up** — live crypto prices, weather, and anything on the web.
            • **Everyday stuff** — math, conversions, travel, recipes, explanations — ask me anything.

            Want me to start with one of those, or is there something specific you're trying to do?
            """
        }
        messages.append(AgentMessage(text: text, role: .agent, agentName: name))
    }

    // MARK: - Apple Music control

    private enum MusicCommand { case play(String), pause, resume, next, previous }

    /// Detects a music request in natural language. Returns nil for anything
    /// that isn't clearly about music so other intents aren't hijacked.
    private func parseMusicCommand(lower: String, original: String) -> MusicCommand? {
        if lower == "pause" || lower.contains("pause music") || lower.contains("pause the music")
            || lower.contains("stop the music") || lower.contains("stop music") { return .pause }
        if lower == "skip" || lower.contains("next song") || lower.contains("skip song")
            || lower.contains("next track") || lower.contains("skip this") || lower.contains("skip the song") { return .next }
        if lower.contains("previous song") || lower.contains("previous track")
            || lower.contains("go back a song") || lower.contains("last song") || lower.contains("play that again") { return .previous }
        if lower == "resume" || lower.contains("resume music") || lower == "play music"
            || lower == "play" || lower.contains("keep playing") || lower.contains("unpause") { return .resume }

        let triggers = ["play me ", "play some ", "put on ", "queue up ", "play "]
        for t in triggers where lower.hasPrefix(t) {
            if lower.contains(" game") || lower.hasSuffix(" game") || lower.contains("video") { return nil }
            var q = String(original.dropFirst(t.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            for p in ["the song ", "a song ", "song ", "the track ", "track ", "some "] where q.lowercased().hasPrefix(p) {
                q = String(q.dropFirst(p.count)); break
            }
            q = q.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { return .play(q) }
        }
        return nil
    }

    private func handleMusicCommand(_ cmd: MusicCommand) {
        let music = MusicKitManager.shared
        switch cmd {
        case .play(let query):
            Task { @MainActor in
                let outcome = await music.play(query: query)
                respondAsTrinity(outcome.message)
            }
        case .pause:
            if music.isPlaying { music.togglePlayPause(); respondAsTrinity("Paused.") }
            else { respondAsTrinity(music.hasNowPlaying ? "Already paused." : "Nothing's playing right now.") }
        case .resume:
            if music.hasNowPlaying {
                if !music.isPlaying { music.togglePlayPause() }
                respondAsTrinity("Playing.")
            } else {
                respondAsTrinity("Tell me what to play and I'll start it — as long as your Apple Music is connected in the player.")
            }
        case .next:
            if music.hasNowPlaying { music.skipNext(); respondAsTrinity("Skipped ahead.") }
            else { respondAsTrinity("Nothing's playing to skip.") }
        case .previous:
            if music.hasNowPlaying { music.skipPrevious(); respondAsTrinity("Back a track.") }
            else { respondAsTrinity("Nothing's playing.") }
        }
    }

    private func livePortfolioSummary(_ wm: WalletManager) -> String {
        let lines = wm.tokens.map { t in
            "• \(t.symbol): \(Self.trim(t.balance)) (\(Self.usdFormatter.string(from: NSNumber(value: t.valueUSD)) ?? "$0"))"
        }.joined(separator: "\n")
        let total = Self.usdFormatter.string(from: NSNumber(value: wm.totalPortfolioValue)) ?? "$0"
        return "Your portfolio is worth **\(total)** right now, up \(String(format: "%.2f", wm.portfolioChange24h))% today.\n\n\(lines)"
    }

    private func insufficientFundsMessage(token: String, in wm: WalletManager) -> String {
        let held = wm.token(token)?.balance ?? 0
        return "That's more \(token.uppercased()) than you hold — your balance is \(Self.trim(held)) \(token.uppercased()). Try a smaller amount."
    }

    /// Parse executable intents:
    ///   crypto — "send 0.5 eth to alice.eth", "swap 1 eth to usdc", "stake 0.5 eth"
    ///   fiat   — "send $50 to mom", "pay john 20 dollars", "send 30 euros to anna"
    private func parseDemoAction(from text: String) -> TrinityDemoAction? {
        let lower = text.lowercased()
        let knownTokens = "eth|usdc|link|uni|aave"
        let fiatWords = "dollars?|usd|bucks|euros?|eur|pounds?|gbp|cad"

        func match(_ pattern: String) -> [String?]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower))
            else { return nil }
            return (1..<m.numberOfRanges).map { i in
                Range(m.range(at: i), in: lower).map { String(lower[$0]) }
            }
        }

        func fiatCode(_ word: String?) -> String {
            switch word ?? "" {
            case let w where w.hasPrefix("euro") || w == "eur": return "EUR"
            case let w where w.hasPrefix("pound") || w == "gbp": return "GBP"
            case "cad": return "CAD"
            default: return "USD"
            }
        }

        // Fiat MUST parse before crypto — "$50" is money, not 50 ETH.

        // "send $50 to mom" / "transfer $1,200 to alice"
        if let g = match(#"(?:send|transfer|pay)\s+\$\s*([0-9][0-9,]*\.?[0-9]*)\s*(?:to\s+([a-z0-9.\-_ ]+?))?\s*$"#),
           let amount = g[0].flatMap({ Double($0.replacingOccurrences(of: ",", with: "")) }) {
            return .sendFiat(amount: amount, currency: "USD",
                             recipient: cleanRecipient(g[1]) ?? "alice.eth")
        }

        // "send 20 dollars to john" / "send 30 euros to anna"
        if let g = match(#"(?:send|transfer|pay)\s+([0-9][0-9,]*\.?[0-9]*)\s*("# + fiatWords + #")\s*(?:to\s+([a-z0-9.\-_ ]+?))?\s*$"#),
           let amount = g[0].flatMap({ Double($0.replacingOccurrences(of: ",", with: "")) }) {
            return .sendFiat(amount: amount, currency: fiatCode(g[1]),
                             recipient: cleanRecipient(g[2]) ?? "alice.eth")
        }

        // "pay mom $50"
        if let g = match(#"pay\s+([a-z0-9.\-_]+)\s+\$\s*([0-9][0-9,]*\.?[0-9]*)"#),
           let amount = g[1].flatMap({ Double($0.replacingOccurrences(of: ",", with: "")) }) {
            return .sendFiat(amount: amount, currency: "USD",
                             recipient: cleanRecipient(g[0]) ?? "alice.eth")
        }

        if let g = match(#"swap\s+\$?([0-9]*\.?[0-9]+)\s*("# + knownTokens + #")\s+(?:to|for|into)\s+("# + knownTokens + #")"#),
           let amount = g[0].flatMap(Double.init), let from = g[1], let to = g[2] {
            return .swap(amount: amount, from: from, to: to)
        }

        if let g = match(#"stake\s+\$?([0-9]*\.?[0-9]+)\s*("# + knownTokens + #")?"#),
           let amount = g[0].flatMap(Double.init) {
            return .stake(amount: amount, token: g[1] ?? "eth")
        }

        if let g = match(#"(?:send|transfer|pay)\s+([0-9]*\.?[0-9]+)\s*("# + knownTokens + #")?(?:\s+to\s+([a-z0-9.\-_]+))?"#),
           let amount = g[0].flatMap(Double.init) {
            return .send(amount: amount, token: g[1] ?? "eth", recipient: g[2] ?? "alice.eth")
        }

        // "deploy a contract", "deploy my token contract called Vault"
        if lower.contains("deploy"), lower.contains("contract") {
            var name = "MyContract"
            if let g = match(#"(?:called|named)\s+[\"']?([a-z0-9_\- ]+?)[\"']?\s*$"#),
               let captured = g[0]?.trimmingCharacters(in: .whitespaces), !captured.isEmpty {
                name = captured.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            }
            return .deploy(name: name)
        }

        return nil
    }

    /// A compact rolling transcript (everything before the message
    /// being answered) — silent memory for the on-device session.
    static func transcriptRecap(_ messages: [AgentMessage]) -> String {
        var history = messages
        if history.last?.role == .user { history.removeLast() }
        let recent = history.suffix(8).filter { $0.role != .system }
        guard !recent.isEmpty else { return "" }
        let lines = recent.map { m in
            let who = m.role == .user ? "User" : (m.agentName ?? "Agent")
            return "\(who): \(m.text.prefix(110))"
        }.joined(separator: " | ")
        return " Conversation so far (silent memory — use it, never read it back): \(String(lines.prefix(750)))."
    }

    /// Detect explicit requests to change the active agent — an agent is
    /// named AND the message carries a summon/switch verb.
    private static func agentSwitchTarget(in text: String) -> AgentAccessControl.ActiveAgent? {
        let lower = text.lowercased()

        let target: AgentAccessControl.ActiveAgent?
        if lower.contains("morpheus") {
            target = .morpheus
        } else if lower.contains("trinity") {
            target = .trinity
        } else if lower.contains("neo"), !lower.contains("neon") {
            target = .neo
        } else {
            target = nil
        }
        guard let target else { return nil }

        let verbs = [
            "talk to", "talk with", "speak to", "speak with", "switch to",
            "let me talk", "bring", "summon", "wake", "get me",
            "connect me", "put me through", "i want to talk", "can i talk",
            "hand me", "switch me", "give me",
        ]
        guard verbs.contains(where: { lower.contains($0) }) else { return nil }
        return target
    }

    /// Trim trailing politeness from captured recipient names
    /// ("mom please" → "mom").
    private func cleanRecipient(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        for suffix in [" please", " now", " today", " right away"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name.isEmpty ? nil : name
    }

    private static func trim(_ value: Double) -> String {
        let s = String(format: "%.4f", value)
        return s.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    // MARK: - Local Response Generation

    /// Honest "no reasoning source" message — Part 1 (Option A), honest-failure law.
    /// Shown ONLY after every REAL reasoning path has been tried and none was
    /// reachable: the on-device model (Apple Intelligence), then the cloud brain
    /// (gateway). Trinity states the limit plainly and NEVER substitutes a scripted
    /// answer that pretends to reason. The old keyword-matched scripted engine
    /// (generateResponse / trinityResponse / morpheusResponse / neoResponse) was
    /// removed here — it was exactly the fake-reasoning this program eliminates
    /// everywhere else.
    static func noReasoningSourceMessage(isEnglish: Bool, languageName: String) -> String {
        if !isEnglish {
            return "I can reason with you in \(languageName) once I'm connected \u{2014} I just couldn't reach my reasoning right now. Give me a moment and ask again."
        }
        return "I need to connect to reason about that \u{2014} I couldn't reach my on-device model or the cloud just now, so I won't guess at it. Give me a moment and ask me again."
    }

    /// Honest note appended when a reply was cut off mid-stream but the partial is
    /// PRESERVED on screen (never vanished). A cut-off answer plus this note is
    /// always better than a message that silently disappears.
    static func cutOffNote(isEnglish: Bool) -> String {
        if !isEnglish {
            return "\u{26A0}\u{FE0F} That reply got cut off before I could finish \u{2014} the connection dropped mid-answer. Ask me again and I'll pick it back up."
        }
        return "\u{26A0}\u{FE0F} That reply got cut off before I could finish \u{2014} my connection dropped mid-answer. Ask again and I'll complete it."
    }

    // MARK: - Morpheus Trigger Checks

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

// MARK: - Trinity Demo Action

/// An executable intent parsed from conversation, awaiting confirmation.
enum TrinityDemoAction {
    case send(amount: Double, token: String, recipient: String)
    case sendFiat(amount: Double, currency: String, recipient: String)
    case swap(amount: Double, from: String, to: String)
    case stake(amount: Double, token: String)
    case deploy(name: String)

    /// Fixed demo FX rates → USD.
    static let fiatRates: [String: Double] = ["USD": 1.0, "EUR": 1.08, "GBP": 1.27, "CAD": 0.73]

    /// Display symbol per supported fiat currency.
    static func fiatSymbol(_ code: String) -> String {
        switch code {
        case "EUR": return "€"
        case "GBP": return "£"
        case "CAD": return "C$"
        default: return "$"
        }
    }

    /// Approximate USD value of the action at current spot prices.
    func usdValue(in wm: WalletManager) -> Double {
        switch self {
        case .send(let amount, let token, _), .stake(let amount, let token):
            return amount * (wm.token(token)?.priceUSD ?? 0)
        case .sendFiat(let amount, let currency, _):
            return amount * (Self.fiatRates[currency] ?? 1.0)
        case .swap(let amount, let from, _):
            return amount * (wm.token(from)?.priceUSD ?? 0)
        case .deploy:
            return 0
        }
    }

    /// Human confirmation line shown before execution.
    func summary(in wm: WalletManager) -> String {
        let usd = NumberFormatter.localizedString(
            from: NSNumber(value: usdValue(in: wm)), number: .currency
        )
        switch self {
        case .send(let amount, let token, let recipient):
            return "**Send \(amount) \(token.uppercased())** (≈\(usd)) to **\(recipient)**."
        case .sendFiat(let amount, let currency, let recipient):
            let symbol = Self.fiatSymbol(currency)
            let formatted = String(format: "%@%.2f", symbol, amount)
            return "**Send \(formatted)** to **\(recipient)**. Arrives in seconds — no fees."
        case .swap(let amount, let from, let to):
            return "**Swap \(amount) \(from.uppercased())** (≈\(usd)) into **\(to.uppercased())** at spot rate."
        case .stake(let amount, let token):
            return "**Stake \(amount) \(token.uppercased())** (≈\(usd)) at 8.7% APY. Unstake anytime."
        case .deploy(let name):
            return "**Deploy smart contract \"\(name)\"** to the MTRX network. Glasswing runs its 12-point security audit first; Morpheus clears it before mainnet."
        }
    }
}
