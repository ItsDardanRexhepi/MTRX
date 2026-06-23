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
        self.text = text
        self.role = role
        self.agentName = agentName
        self.timestamp = Date()
        self.suggestedActions = suggestedActions
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
        messages = announce
            ? [AgentMessage(text: Self.openingLine(for: agent), role: .agent, agentName: Self.displayName(of: agent))]
            : []
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
        messages = convo.messages
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

    private static func openingLine(for agent: AgentAccessControl.ActiveAgent) -> String {
        switch agent {
        case .trinity: return "New conversation — what do you need?"
        case .morpheus: return "You have my attention. Speak."
        case .neo: return "Channel open. Report."
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

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // The user actually talked to an agent — that completes the goal.
        DailyFlow.shared.mark(.agent)

        // Add user message
        messages.append(AgentMessage(text: text, role: .user))
        inputText = ""

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
            if !intercepted {
                // Stream the on-device reply into a single live bubble so the
                // agent starts answering the instant the first token lands,
                // instead of after the whole reply is generated.
                let streamMsg = AgentMessage(text: "", role: .agent, agentName: agentName)
                let streamID = streamMsg.id
                var didStream = false
                let onDevice = await inference.generateOnDeviceStreaming(
                    prompt: text,
                    context: contextLine,
                    persona: persona,
                    onPartial: { [weak self] partial in
                        guard let self, !partial.isEmpty else { return }
                        if !didStream {
                            didStream = true
                            self.isTyping = false
                            self.messages.append(streamMsg)
                        }
                        if let idx = self.messages.firstIndex(where: { $0.id == streamID }) {
                            self.messages[idx].text = partial
                        }
                    }
                )
                if let onDevice {
                    if didStream, let idx = messages.firstIndex(where: { $0.id == streamID }) {
                        messages[idx].text = onDevice
                    } else {
                        messages.append(AgentMessage(text: onDevice, role: .agent, agentName: agentName))
                    }
                    isTyping = false
                    return
                }
                // On-device unavailable/failed → drop any partial bubble and
                // fall through to the gateway.
                if didStream { messages.removeAll { $0.id == streamID } }
            }

            // 2 — Gateway (when Apple Intelligence isn't available)
            do {
                let apiResponse = try await MTRXAPIClient.shared.sendAgentMessage(
                    agent: agentName.lowercased(),
                    message: text,
                    context: temporal + "\n" + conversationContext + (langProfile.mirrorInstruction.isEmpty ? "" : "\n" + langProfile.mirrorInstruction),
                    conversationHistory: buildHistoryPayload()
                )

                messages.append(AgentMessage(
                    text: apiResponse.text,
                    role: .agent,
                    agentName: agentName,
                    suggestedActions: (apiResponse.suggestedActions ?? []).map { SuggestedAction(title: $0.label, description: $0.label, action: $0.action) }
                ))
                isTyping = false
            } catch {
                // 3 — Local template fallback (ENGLISH-ONLY). The scripted responses are
                // English; a non-English message must NOT get a fake English reply here. The
                // API LLM above is the multilingual (mirroring) path — when it's unreachable
                // and the user wrote in another language, fail honestly instead of answering
                // in the wrong language. (Tier-2 extended-language support lands in V2+.)
                isOffline = true
                if !langProfile.isEnglish {
                    messages.append(AgentMessage(
                        text: "I can chat with you in \(langProfile.displayName) when I'm connected, but my offline responses are English-only right now. Please try again once you're back online.",
                        role: .agent,
                        agentName: agentName
                    ))
                    isTyping = false
                    return
                }
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

    /// ENGLISH-ONLY scripted fallback — used only when BOTH the on-device model and the API
    /// gateway are unavailable. Non-English input is never answered here: `processWithAgent`
    /// routes it to the API LLM (which mirrors the user's language) and, when that's
    /// unreachable, returns an honest "offline responses are English-only" message instead of
    /// a wrong-language reply. Do not add non-English branches here — multilingual lives on the
    /// model paths, not the scripted templates.
    private func generateResponse(text: String, agent: AgentAccessControl.ActiveAgent, temporal: String, intercepted: Bool) -> String {
        if intercepted {
            // Scenario 1: Trinity warmly redirects without revealing the interception
            return "I can help you with that. Let me understand exactly what you need so I can assist you in the best way possible. Could you tell me more about what you're looking to accomplish?"
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

    // MARK: - Trinity Responses

    private func trinityResponse(for text: String) -> String {
        let lower = text.lowercased()

        // --- Payments ---
        if lower.contains("send") || lower.contains("transfer") {
            return "I can help you send assets securely. Here's what I need:\n\n1. **Amount** — How much would you like to send?\n2. **Asset** — Which token or currency?\n3. **Recipient** — Wallet address, ENS name, or MTRX username\n\nI'll show you the estimated network fees and ask for your confirmation before executing. Your transaction will be signed locally and never leaves your device until you approve."
        }
        if lower.contains("receive") {
            return "To receive assets, you can share your wallet address or QR code. Here are your options:\n\n- **Copy Address** — I can display your wallet address for any supported network\n- **QR Code** — Generate a scannable code with an optional amount pre-filled\n- **Payment Link** — Create a shareable link that anyone can use to send you funds\n\nWhich network would you like to receive on?"
        }
        if lower.contains("swap") {
            return "I'll find you the best swap rate across all available DEXs and aggregators. Here's how it works:\n\n1. Tell me what you want to swap (e.g., \"swap 1 ETH to USDC\")\n2. I'll fetch quotes from multiple sources and show you the best rate\n3. You'll see the exact output amount, slippage, and fees before confirming\n4. The swap executes atomically — it either fully completes or reverts\n\nWhat would you like to swap?"
        }
        if lower.contains("bridge") {
            return "I can bridge your assets between chains. Supported routes include Ethereum, Polygon, Arbitrum, Optimism, Base, Avalanche, and Solana.\n\nI'll compare bridge protocols to find the best combination of:\n- **Speed** — Some bridges complete in minutes, others take longer\n- **Cost** — Gas fees on source and destination chains\n- **Security** — Only using audited, battle-tested bridges\n\nWhat asset and which chains are you bridging between?"
        }

        // --- DeFi ---
        if lower.contains("loan") || lower.contains("borrow") {
            return "I can help you take out a DeFi loan. Here's what you need to know:\n\n- **Collateral**: You'll need to deposit collateral worth more than your loan (typically 150%+ ratio)\n- **Interest Rates**: I'll scan Aave, Compound, Maker, and other protocols for the best rates\n- **Liquidation Risk**: I'll calculate your liquidation price and set up alerts\n- **Health Factor**: I'll monitor your position and warn you if it drops below safe levels\n\nWhat asset would you like to borrow, and what collateral do you have available?"
        }
        if lower.contains("lend") || lower.contains("supply") || lower.contains("deposit") {
            return "Lending your assets is a great way to earn passive yield. Here's the current landscape:\n\n- **Aave**: Variable and stable rate options across multiple assets\n- **Compound**: Governance-token incentivized lending\n- **Maker**: DAI savings rate for stablecoin holders\n\nI'll show you the current APY for your asset, estimated earnings over different time periods, and protocol risk ratings. Which asset would you like to lend?"
        }
        if lower.contains("yield") || lower.contains("farm") || lower.contains("liquidity") {
            return "I can find the best yield opportunities for you. Options include:\n\n1. **Lending** — Earn interest by supplying assets to lending protocols (lower risk)\n2. **Liquidity Provision** — Provide liquidity to DEX pools and earn trading fees + rewards (moderate risk, impermanent loss possible)\n3. **Yield Farming** — Stake LP tokens to earn additional reward tokens (higher risk, higher reward)\n4. **Staking** — Lock tokens to earn network rewards (varies by protocol)\n\nI'll calculate risk-adjusted returns and factor in gas costs. What's your risk tolerance and how much capital are you looking to deploy?"
        }

        // --- NFTs ---
        if lower.contains("mint") {
            return "I can help you mint an NFT. Here's the process:\n\n1. **Upload Media** — Image, video, audio, or 3D model (IPFS-pinned for permanence)\n2. **Metadata** — Name, description, properties/traits, and unlockable content\n3. **Collection** — Add to an existing collection or create a new one\n4. **Royalties** — Set your creator royalty percentage (typically 2.5-10%)\n5. **Supply** — Unique 1/1 or editions (multiple copies)\n\nGas fees will be estimated before you confirm. Would you like to start minting?"
        }
        if lower.contains("nft") && (lower.contains("buy") || lower.contains("purchase")) {
            return "I can help you buy NFTs from the MTRX marketplace or connected markets. I'll show you:\n\n- **Floor Price** — The lowest available price in the collection\n- **Recent Sales** — What similar items have sold for\n- **Rarity Score** — How rare the traits are compared to the collection\n- **Ownership History** — Previous owners and sale prices\n- **Authenticity** — Verification that it's from the official collection\n\nPaste a link or tell me which collection you're interested in."
        }
        if lower.contains("nft") && (lower.contains("sell") || lower.contains("list")) {
            return "I'll help you list your NFT for sale. You have several options:\n\n- **Fixed Price** — Set a buy-it-now price\n- **English Auction** — Bidding starts low, highest bidder wins\n- **Dutch Auction** — Price starts high and decreases over time\n- **Private Sale** — Sell directly to a specific buyer\n\nI'll suggest a price based on recent comparable sales and collection floor. Which NFT would you like to list?"
        }
        if lower.contains("nft") && lower.contains("transfer") {
            return "I can transfer your NFT to another wallet. I'll need:\n\n- **NFT** — Which NFT to transfer (name, token ID, or select from your collection)\n- **Recipient** — Wallet address or ENS name\n\nNote: This is an irreversible action. I'll show you the exact NFT and recipient for confirmation before executing the transfer."
        }
        if lower.contains("collection") && lower.contains("nft") {
            return "I can help you explore NFT collections. I'll show you:\n\n- **Trending Collections** — Top movers by volume and floor price changes\n- **Your Collections** — NFTs you own, organized by collection\n- **Analytics** — Floor price history, holder distribution, and whale movements\n- **Upcoming Mints** — New collections launching soon\n\nWould you like to browse trending collections or check your own?"
        }

        // --- Smart Contracts ---
        if lower.contains("contract") && (lower.contains("create") || lower.contains("write")) {
            return "I can help you create a smart contract. MTRX offers audited templates for common use cases:\n\n- **ERC-20 Token** — Create a custom fungible token\n- **ERC-721 NFT** — Launch an NFT collection with customizable minting\n- **Multisig Wallet** — Require multiple signatures for transactions\n- **Escrow** — Hold funds until conditions are met\n- **Vesting** — Time-locked token distribution\n- **DAO** — Governance with voting and treasury management\n- **Staking** — Let users stake your token for rewards\n\nAll templates are audited. I can also help you write custom logic. Which type interests you?"
        }
        if lower.contains("deploy") {
            return "I'll walk you through deploying your smart contract. Before deployment, I'll:\n\n1. **Glasswing Security Audit** — Full 12-point vulnerability scan (reentrancy, overflow, access control, and more)\n2. **Risk Assessment** — Ultron evaluates strategic risk before any deployment proceeds\n3. **Gas Estimation** — Calculate deployment cost on your target network\n4. **Testnet First** — Deploy to a testnet so you can verify behavior\n5. **Constructor Args** — Help you set the right initialization parameters\n\n⚠️ Critical vulnerabilities will block deployment automatically. This is a permanent, irreversible action on the blockchain. Which network would you like to deploy to?"
        }
        if lower.contains("escrow") {
            return "I can set up an escrow contract for you. Here's how it works:\n\n1. **Parties** — Define the buyer, seller, and optional arbiter\n2. **Conditions** — Set the release conditions (time-based, approval-based, or milestone-based)\n3. **Amount** — Specify the escrowed amount and token\n4. **Dispute Resolution** — Define what happens if there's a disagreement\n\nFunds are held securely on-chain and only released when conditions are met. Would you like to create one?"
        }
        if lower.contains("template") && lower.contains("contract") {
            return "Here are the available smart contract templates, all security-audited:\n\n- **Token (ERC-20)** — Customizable supply, decimals, minting/burning\n- **NFT Collection (ERC-721)** — Metadata, royalties, allowlists\n- **Multisig** — 2-of-3, 3-of-5, or custom threshold\n- **Escrow** — Two-party or arbitrated\n- **Vesting** — Linear, cliff, or custom schedule\n- **Staking Pool** — Flexible or locked staking with rewards\n- **DAO Governor** — Proposal, voting, and execution\n- **Marketplace** — List, bid, and trade assets\n\nWhich template would you like to use? I'll customize it to your needs."
        }

        // --- Insurance ---
        if lower.contains("insurance") || lower.contains("coverage") || lower.contains("insure") {
            return "MTRX offers several types of decentralized insurance:\n\n1. **Smart Contract Cover** — Protection against exploits and bugs in DeFi protocols\n2. **Parametric Insurance** — Automatic payouts based on verifiable events (weather, flight delays, earthquakes)\n3. **DeFi Position Insurance** — Cover against impermanent loss or unexpected liquidation\n4. **Renters Insurance** — Decentralized property coverage with instant claims\n5. **Travel Insurance** — Flight delay/cancellation coverage with automatic payouts\n\nPremiums are calculated based on risk models and paid in crypto. Claims are processed on-chain for transparency. What type of coverage do you need?"
        }
        if lower.contains("claim") && lower.contains("insurance") {
            return "To file an insurance claim, I'll need:\n\n1. **Policy ID** — Your active insurance policy identifier\n2. **Event Details** — What happened and when\n3. **Evidence** — Transaction hashes, screenshots, or oracle data supporting the claim\n\nFor parametric policies, claims are often processed automatically when oracle data confirms the triggering event. Let me pull up your active policies."
        }

        // --- Gaming ---
        if lower.contains("play") || lower.contains("game") || lower.contains("gaming") {
            return "Welcome to MTRX Gaming! Here's what's available:\n\n- **Active Games** — Browse and join play-to-earn games\n- **Tournaments** — Compete for prize pools in scheduled events\n- **Game Assets** — View and manage your in-game NFTs and items\n- **Leaderboards** — Check rankings across all games\n- **Rewards** — Claim earned tokens and NFTs\n\nAll in-game assets are NFTs you truly own — trade, sell, or use them across compatible games. Would you like to browse games or check your gaming profile?"
        }
        if lower.contains("tournament") {
            return "Here are the tournament options:\n\n- **Upcoming** — Browse tournaments you can register for\n- **Active** — Check your current tournament status and standings\n- **Completed** — View past results and claim prizes\n- **Create** — Set up a custom tournament (requires staking the prize pool)\n\nEntry fees and prizes are handled on-chain with automatic distribution. Would you like to see available tournaments?"
        }
        if lower.contains("leaderboard") {
            return "I can show you leaderboards for:\n\n- **Global Rankings** — Top players across all MTRX games\n- **Game-Specific** — Rankings within individual games\n- **Tournament** — Current standings in active competitions\n- **Earnings** — Top earners by play-to-earn rewards\n\nWhich leaderboard would you like to see?"
        }

        // --- Marketplace ---
        if lower.contains("marketplace") || lower.contains("market") {
            return "The MTRX Marketplace supports a wide range of assets:\n\n- **Digital Assets** — NFTs, tokens, digital collectibles, and domain names\n- **Real World Assets (RWA)** — Tokenized property, commodities, art, and securities\n- **Services** — Smart contract templates, audits, and development services\n\nYou can browse by category, search for specific items, or list your own assets. All trades use on-chain escrow for safety. What are you looking for?"
        }
        if lower.contains("property") || lower.contains("real estate") || lower.contains("rwa") {
            return "MTRX supports tokenized Real World Assets (RWA). Here's what's available:\n\n- **Fractional Property** — Own a share of real estate properties\n- **Commodities** — Tokenized gold, silver, and other commodities\n- **Art & Collectibles** — Verified physical items with digital twins\n- **Revenue-Sharing** — Invest in assets that distribute real yield\n\nAll RWAs are backed by legal structures and verified custodians. Would you like to browse available properties?"
        }

        // --- Fundraising ---
        if lower.contains("fundrais") || lower.contains("campaign") || lower.contains("crowdfund") {
            return "MTRX Fundraising uses milestone-based smart contracts for transparency:\n\n1. **Create Campaign** — Set your funding goal, timeline, and milestones\n2. **Milestone Releases** — Funds are released as you hit verified milestones\n3. **Donor Protection** — Contributors can vote on milestone approval\n4. **Transparency** — All funds and movements visible on-chain\n\nWould you like to create a new campaign or browse existing ones?"
        }
        if lower.contains("donate") || lower.contains("contribute") {
            return "I can help you contribute to a fundraising campaign. I'll show you:\n\n- **Campaign Details** — Goal, progress, timeline, and team\n- **Milestone Status** — Which milestones have been completed\n- **Fund Usage** — How previous funds were allocated\n- **Tax Documentation** — Downloadable receipts for eligible donations\n\nPaste a campaign link or search by category to find campaigns to support."
        }

        // --- Governance ---
        if lower.contains("vote") {
            return "I can help you participate in governance voting. Here's what's available:\n\n- **Active Proposals** — View proposals currently open for voting\n- **Your Voting Power** — Check your token-weighted voting power\n- **Proposal Analysis** — I'll summarize proposals and their implications\n- **Vote History** — Review your past voting record\n\nI can also explain complex proposals in plain language before you vote. Which DAO or protocol would you like to participate in?"
        }
        if lower.contains("propos") {
            return "I can help you create a governance proposal. Here's the process:\n\n1. **Draft** — Write your proposal with a clear title, description, and requested action\n2. **Discussion** — Share it for community feedback before formal submission\n3. **Submission** — Submit on-chain (may require a minimum token threshold)\n4. **Voting Period** — Community votes during the designated window\n5. **Execution** — If passed, the proposal executes automatically via the DAO contract\n\nWhat would you like to propose?"
        }
        if lower.contains("delegate") {
            return "Delegating your voting power lets someone else vote on your behalf. Here's how:\n\n- **Choose a Delegate** — I'll show you active delegates with their voting history and platform\n- **Partial Delegation** — Delegate all or part of your voting power\n- **Revoke Anytime** — You can reclaim your voting power at any time\n- **Self-Delegate** — Delegate to yourself to activate direct voting\n\nWhich governance token would you like to delegate?"
        }
        if lower.contains("dao") || lower.contains("organization") {
            return "I can help you interact with or create a DAO:\n\n- **Join a DAO** — Browse active DAOs and their requirements\n- **Create a DAO** — Set up governance structure, treasury, and voting rules\n- **Manage Treasury** — View and propose treasury allocations\n- **Member Roles** — Configure permissions and responsibilities\n\nDAOs on MTRX use audited Governor contracts with customizable voting parameters. What would you like to do?"
        }

        // --- Social ---
        if lower.contains("post") || lower.contains("share") {
            return "I can help you create a social post on MTRX:\n\n- **Public Post** — Share with the entire MTRX community\n- **Token-Gated** — Only visible to holders of specific tokens\n- **Portfolio Share** — Share your portfolio performance (with privacy controls)\n- **Transaction Share** — Share a notable transaction or trade\n\nAll posts are signed with your DID for authenticity. What would you like to share?"
        }
        if lower.contains("message") || lower.contains("chat") || lower.contains("dm") {
            return "MTRX messaging is end-to-end encrypted and decentralized:\n\n- **Direct Messages** — Send encrypted messages to any MTRX user\n- **Group Chats** — Create or join group conversations\n- **Token-Gated Channels** — Access exclusive communities\n- **Attachments** — Send files, images, and transaction requests\n\nMessages are stored encrypted on IPFS — only you and your recipients can read them. Who would you like to message?"
        }
        if lower.contains("encrypt") && lower.contains("message") {
            return "All MTRX messages are encrypted by default using your wallet's keys. Additional privacy features:\n\n- **Disappearing Messages** — Set auto-delete timers\n- **Forward Protection** — Prevent message forwarding\n- **Anonymous Mode** — Send messages without revealing your identity\n- **Key Rotation** — Automatic key rotation for enhanced security\n\nYour privacy is protected by cryptography, not trust."
        }

        // --- Staking ---
        if lower.contains("stake") || lower.contains("staking") {
            return "Staking allows you to earn rewards by securing the network. Here's what I can help with:\n\n1. **Choose a Validator** — I'll show you validators ranked by performance, uptime, and commission\n2. **Stake Amount** — Decide how much to stake (you can stake partially)\n3. **Lock Period** — Some networks have unbonding periods (typically 7-28 days)\n4. **Rewards** — Current APY and estimated earnings displayed upfront\n5. **Auto-Compound** — Option to automatically restake rewards\n\nHow much would you like to stake and on which network?"
        }
        if lower.contains("unstake") {
            return "I'll help you unstake your tokens. Important details:\n\n- **Unbonding Period** — Your tokens will be locked during the unstaking period (varies by network)\n- **Pending Rewards** — Any unclaimed rewards will be collected automatically\n- **Partial Unstake** — You can unstake a portion while keeping the rest staked\n\nOnce I initiate the unstaking, I'll set up a reminder for when your tokens become available. How much would you like to unstake?"
        }
        if lower.contains("validator") {
            return "Here's how I evaluate validators for you:\n\n- **Uptime** — Historical availability percentage\n- **Commission** — Fee charged on your rewards (lower is better for you)\n- **Total Stake** — How much is delegated (avoid over-concentrated validators)\n- **Governance Participation** — Active validators who vote on proposals\n- **Track Record** — Slashing history and time active\n\nI recommend diversifying across 2-3 validators to reduce risk. Shall I show you the top performers?"
        }
        if lower.contains("reward") && lower.contains("stak") {
            return "I'll pull up your staking rewards summary:\n\n- **Accumulated Rewards** — Total rewards earned to date\n- **Pending Rewards** — Unclaimed rewards ready to collect\n- **APY** — Current annual percentage yield\n- **Projected Earnings** — Estimated rewards over the next 30/90/365 days\n- **Reward History** — Complete log of past reward distributions\n\nWould you like to claim your pending rewards or see the detailed breakdown?"
        }

        // --- Portfolio ---
        if lower.contains("balance") || lower.contains("portfolio") || lower.contains("holdings") {
            return "Let me pull up your portfolio. I'll show you:\n\n- **Total Value** — Combined value across all wallets and chains\n- **Asset Breakdown** — Each holding with current value and 24h change\n- **Allocation Chart** — Visual breakdown of your portfolio distribution\n- **DeFi Positions** — Active lending, borrowing, LP, and staking positions\n- **NFT Holdings** — Your NFT collection with estimated floor values\n\nI'll also flag any positions that need attention, like low health factors or expiring positions."
        }
        if lower.contains("performance") || lower.contains("pnl") || lower.contains("profit") || lower.contains("loss") {
            return "I'll generate your portfolio performance report:\n\n- **Total Return** — Overall profit/loss since inception\n- **Period Returns** — 24h, 7d, 30d, 90d, and YTD performance\n- **Best/Worst Performers** — Your top and bottom assets by return\n- **Benchmark Comparison** — How you compare to BTC, ETH, and market indices\n- **Risk Metrics** — Volatility, Sharpe ratio, and max drawdown\n\nWould you like the full report or a specific time period?"
        }
        if lower.contains("history") || lower.contains("transaction") {
            return "I'll pull your transaction history. I can filter by:\n\n- **Time Period** — Today, this week, this month, or custom range\n- **Type** — Sends, receives, swaps, contract interactions, approvals\n- **Asset** — Specific token or NFT\n- **Network** — Filter by blockchain\n- **Status** — Pending, confirmed, or failed\n\nI'll also calculate gas spent and show the current value vs. transaction-time value. What would you like to see?"
        }

        // --- Identity ---
        if lower.contains("identity") || lower.contains("did") || lower.contains("credential") || lower.contains("verify") {
            return "MTRX uses Decentralized Identity (DID) for self-sovereign verification:\n\n- **Create DID** — Set up your decentralized identifier anchored to your wallet\n- **Verifiable Credentials** — Issue or receive tamper-proof credentials\n- **Selective Disclosure** — Prove attributes (age, residency, etc.) without revealing personal data\n- **Cross-Platform** — Use your DID across any compatible platform\n- **Credential Wallet** — Manage all your credentials in one place\n\nYour identity data stays under your control — no central authority can revoke or modify it. What would you like to do?"
        }

        // --- Privacy ---
        if lower.contains("privacy") || lower.contains("zero-knowledge") || lower.contains("zk") || lower.contains("private") {
            return "MTRX privacy features powered by zero-knowledge cryptography:\n\n- **Private Transfers** — Send tokens without revealing the amount on-chain\n- **Proof of Funds** — Prove you have sufficient balance without showing your total\n- **Commitment Schemes** — Submit sealed bids or votes that are revealed later\n- **Compliance Proofs** — Prove regulatory compliance without exposing personal data\n- **Private Voting** — Vote on governance proposals without revealing your choice until tally\n\nAll privacy features use battle-tested ZK circuits. Which feature interests you?"
        }

        // --- Security & Audit ---
        if lower.contains("audit") || lower.contains("vulnerability") || lower.contains("security scan") || lower.contains("glasswing") {
            return "Every smart contract on MTRX is scanned by the Glasswing security audit layer before deployment. Here's what it checks:\n\n- **Reentrancy (SWC-107)** — Detects state changes after external calls\n- **Unchecked Returns (SWC-104)** — Finds ignored low-level call results\n- **tx.origin Auth (SWC-115)** — Flags phishable authentication patterns\n- **Selfdestruct (SWC-106)** — Warns about destructible contracts\n- **Integer Overflow (SWC-101)** — Catches unsafe arithmetic\n- **Access Control (AC-001)** — Verifies proper permission guards\n- **Front-Running (FR-001)** — Identifies MEV-vulnerable patterns\n- **Floating Pragma (SWC-103)** — Enforces pinned compiler versions\n\nCritical findings block deployment automatically. Would you like to audit a contract or view a past audit report?"
        }
        if lower.contains("security") && !lower.contains("security token") {
            return "MTRX security is powered by the Glasswing audit layer integrated across the entire protocol stack:\n\n- **Pre-Deployment Scanning** — 12-point vulnerability analysis on every contract\n- **Morpheus Enforcement** — Critical findings automatically block unsafe deployments\n- **Continuous Monitoring** — Friday protocol watches for security anomalies in real-time\n- **HiveMind Coordination** — Security intelligence shared across all agent instances\n- **Vision Pattern Detection** — AI-powered detection of emerging threat patterns\n\nSecurity isn't an add-on — it's woven into every layer of the platform. What would you like to know more about?"
        }
        if lower.contains("exploit") || lower.contains("hack") || lower.contains("reentrancy") || lower.contains("overflow") {
            return "I take security threats seriously. Here's how MTRX protects against common exploits:\n\n- **Reentrancy Attacks** — Glasswing detects state-after-call patterns and blocks deployment\n- **Integer Overflow** — Arithmetic operations are checked for safe math usage\n- **Front-Running** — MEV-vulnerable operations are flagged for review\n- **Delegatecall Injection** — Dangerous proxy patterns are identified\n- **Timestamp Manipulation** — Block.timestamp dependencies are flagged\n- **Access Control Gaps** — Missing onlyOwner/role guards are caught\n\nAll findings are classified by severity (Critical, High, Medium, Low, Info). Critical and High findings must be resolved before deployment proceeds."
        }

        // --- Managed Agents ---
        if lower.contains("agent") && (lower.contains("manage") || lower.contains("orchestrat") || lower.contains("coordinat")) {
            return "MTRX uses a managed agent architecture with intelligent orchestration:\n\n- **Neo** — The coordinator agent with full system access, delegates tasks to specialized agents\n- **Trinity** — User-facing assistant handling all consumer interactions\n- **Morpheus** — Guardian agent that monitors for risky operations and intervenes when needed\n\nAgents share a common environment but maintain isolated context. Communication flows through typed events — each agent sees only what it needs. The HiveMind protocol enables collective intelligence across all agent instances.\n\nWould you like to learn more about how the agents work together?"
        }

        // --- General fallback ---
        if lower.contains("help") || lower.contains("what can you do") {
            return "I'm Trinity, your AI assistant for everything on MTRX. Here's what I can help with:\n\n**Financial**\n- Send, receive, swap, and bridge assets\n- DeFi: lending, borrowing, yield farming, liquidity\n- Staking and validator management\n- Portfolio tracking and analytics\n\n**Digital Assets**\n- NFTs: mint, buy, sell, transfer, collections\n- Smart contracts: create, deploy, manage\n- Marketplace: buy, sell, auction\n\n**Services**\n- Insurance: smart contract, parametric, renters, travel\n- Fundraising: create campaigns, donate, track milestones\n- Gaming: play, tournaments, leaderboards\n\n**Community**\n- Governance: vote, propose, delegate, DAOs\n- Social: posts, encrypted messaging, communities\n- Identity: DIDs, verifiable credentials\n- Privacy: zero-knowledge proofs and private transactions\n\nJust tell me what you need!"
        }
        if lower.contains("hello") || lower.contains("hi ") || lower.contains("hey") || lower == "hi" {
            return "Hello! I'm Trinity, your AI assistant for MTRX. I can help you manage your assets, explore DeFi, handle NFTs, participate in governance, and much more. What would you like to do today?"
        }
        if lower.contains("thank") {
            return "You're welcome! I'm always here whenever you need help. Is there anything else I can assist you with?"
        }

        return "I'm here to help you with anything on MTRX — from managing your portfolio and executing transactions to exploring DeFi, NFTs, governance, insurance, gaming, and more. What would you like to do?"
    }

    // MARK: - Morpheus Responses

    private func morpheusResponse(for text: String) -> String {
        let lower = text.lowercased()

        if lower.contains("deploy") || lower.contains("contract") {
            return "You are about to deploy a smart contract to a public blockchain. This action is permanent and irreversible.\n\nThe Glasswing security audit will run automatically before deployment:\n- **12 vulnerability checks** covering reentrancy, overflow, access control, and more\n- **Critical findings block deployment** — no exceptions\n- **Audit report attached** to every deployed contract for transparency\n\nAdditionally:\n- The contract code will be visible to everyone\n- Any bugs or vulnerabilities cannot be patched after deployment\n- Gas fees for deployment are non-refundable\n\nDo you wish to proceed? The audit results will determine whether deployment can continue."
        }
        if lower.contains("loan") || lower.contains("borrow") || lower.contains("lend") {
            return "You are entering a DeFi lending/borrowing position. Consider carefully:\n\n- **Liquidation Risk** — If your collateral value drops below the threshold, your position will be liquidated automatically with no appeal\n- **Variable Rates** — Interest rates can change dramatically based on utilization\n- **Smart Contract Risk** — Your funds are held in a smart contract that could have undiscovered vulnerabilities\n- **No Recourse** — There is no customer support or dispute resolution in DeFi\n\nAre you fully prepared for these risks?"
        }
        if lower.contains("irreversible") || lower.contains("permanent") || lower.contains("can't be undone") {
            return "This action cannot be reversed once executed. The blockchain does not have an undo button.\n\nTake a moment to verify:\n- Is the recipient address correct? One wrong character means permanent loss.\n- Is the amount correct? There are no refunds.\n- Are you on the right network? Cross-chain recovery may be impossible.\n\nOnly proceed if you have verified every detail."
        }
        if lower.contains("safe") || lower.contains("risk") || lower.contains("dangerous") {
            return "Let me assess the risk profile of what you're considering:\n\n- **Smart Contract Risk** — Has the contract been audited? By whom? When?\n- **Counterparty Risk** — Who is on the other side of this transaction?\n- **Market Risk** — Could price movements adversely affect your position?\n- **Regulatory Risk** — Are there compliance considerations?\n\nI exist to make sure you understand the full picture before making irreversible decisions."
        }

        return "Consider carefully what you are asking. Every action on the blockchain has consequences, and many are permanent. I'm here to ensure you understand the full implications before proceeding. What specifically would you like me to evaluate?"
    }

    // MARK: - Neo Responses

    private func neoResponse(for text: String) -> String {
        let lower = text.lowercased()

        if lower.contains("status") || lower.contains("system") {
            return "System Status Report _(illustrative — demo environment)_:\n\n- **Runtime**: All nodes operational\n- **Consensus**: Healthy\n- **API Gateway**: Responsive\n- **Smart Contract Engine**: 0 pending deployments\n- **Oracle Network**: All feeds active\n- **Security**: No anomalies detected\n- **Memory**: Trinity memory store healthy\n- **Morpheus**: Monitoring active, 0 interventions pending\n\nAll systems nominal. What would you like to inspect?"
        }
        if lower.contains("deploy") || lower.contains("update") || lower.contains("upgrade") {
            return "Ready for deployment operation. Orchestrated pipeline status:\n\n1. Code compilation — standing by\n2. Glasswing security audit — 12-point vulnerability scan queued\n3. Ultron risk assessment — strategic analysis prepared\n4. Testnet validation — prepared\n5. Morpheus gate — final safety check before mainnet\n6. Mainnet deployment — awaiting your authorization\n\nAll agents coordinated via HiveMind. Provide the deployment target and I will execute. Full audit trail will be maintained."
        }
        if lower.contains("analytics") || lower.contains("metrics") || lower.contains("data") {
            return "Analytics dashboard available. Current metrics:\n\n- **Daily Active Users**: Tracking\n- **Transaction Volume**: Monitoring across all chains\n- **Gas Optimization**: Running continuous analysis\n- **Protocol Revenue**: Aggregating from all sources\n- **Error Rate**: < 0.01% across all endpoints\n\nWhich metric set would you like to drill into?"
        }
        if lower.contains("config") || lower.contains("setting") || lower.contains("parameter") {
            return "System configuration access granted. Available operations:\n\n- **Runtime Parameters** — Adjust gas limits, timeout values, retry policies\n- **Agent Configuration** — Modify Trinity/Morpheus behavior parameters\n- **Network Settings** — RPC endpoints, chain priorities, fallback nodes\n- **Security Policies** — Rate limits, access controls, encryption settings\n\nSpecify the parameter you wish to modify."
        }

        return "Processing. All systems operational. Full backend access available. What operation do you need executed?"
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
