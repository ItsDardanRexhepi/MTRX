// AgentConversationView.swift
// MTRX
//
// Home tab — Trinity AI conversation interface.
// Handles Trinity, Morpheus, and Neo interactions with full design system.

import SwiftUI

// MARK: - Agent Conversation View

struct AgentConversationView: View {
    @StateObject private var viewModel = AgentConversationViewModel()
    @ObservedObject private var accessControl = AgentAccessControl.shared
    @ObservedObject private var morpheus = MorpheusInterventions.shared
    @EnvironmentObject private var walletManager: WalletManager
    @FocusState private var isInputFocused: Bool

    let userID: String

    /// Open straight into this agent's chat (Home screen agent cards).
    var initialAgent: AgentAccessControl.ActiveAgent?
    /// Pre-fill the input bar (Home screen quick actions).
    var initialPrompt: String?
    /// Presented modally → show a dismiss chevron in the header.
    var isModal: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @State private var showAgentIdentity = false
    @State private var showSearch = false
    @State private var showChats = false
    @State private var dismissDrag: CGFloat = 0
    @State private var greeting = ""
    @State private var idleTimer: Timer?

    /// Rotating openers — a different one almost every time, like the
    /// modern assistants. Each agent has its own voice. Shown centered
    /// until the user starts typing.
    private static func greetingPool(for agent: AgentAccessControl.ActiveAgent) -> [String] {
        switch agent {
        case .morpheus:
            return [
                "I'm watching. What's on your mind?",
                "Tell me what you're weighing.",
                "I'm here to keep you safe. What's up?",
                "Steady. What do you need to think through?",
                "What are we protecting today?",
            ]
        case .neo:
            return [
                "Systems are green. What do you need?",
                "Owner. Where do we start?",
                "Full view's up. What's the move?",
                "I'm online. What are we coordinating?",
                "Ready. What's the priority?",
            ]
        default:
            return [
                "What are we building today?",
                "Good to see you. Where to?",
                "I'm here. What do you need?",
                "Ready when you are.",
                "What's on your mind?",
                "Let's make something happen.",
                "How can I help right now?",
                "Pick up where we left off?",
            ]
        }
    }

    private static func greeting(for agent: AgentAccessControl.ActiveAgent) -> String {
        greetingPool(for: agent).randomElement() ?? "How can I help?"
    }

    /// The centered greeting shows until the first user message exists.
    private var showCenteredGreeting: Bool {
        viewModel.messages.allSatisfy { $0.role != .user } && !viewModel.isTyping && dismissDrag == 0
    }

    var body: some View {
        ZStack {
            // The agent's orb, expanded to fill the entire room — a living
            // wash of its colors that breathes exactly like the orb and
            // re-tints whenever you switch agents. There's no center orb
            // anymore: the whole screen *is* the agent.
            agentWallpaper
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.85), value: viewModel.activeAgent)

            VStack(spacing: 0) {
                // The agent space wears its own header; the tab-style
                // header remains for any non-modal embedding.
                if isModal {
                    agentSpaceHeader
                } else {
                    agentHeader
                }

                // Offline indicator
                if viewModel.isOffline {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12, weight: .medium))
                        Text("Running locally")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, Spacing.md)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Spacing.ms) {
                            // First boot card
                            if viewModel.showFirstBoot {
                                firstBootMessage
                                    .padding(.top, Spacing.xl)
                                    .padding(.bottom, Spacing.md)
                                    .transition(.mtrxSlideUp)
                            }

                            ForEach(viewModel.messages) { message in
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    MessageBubble(message: message)

                                    // Actionable suggestion chips — only on the
                                    // most recent agent message, so stale
                                    // confirmations can't be tapped.
                                    if message.id == viewModel.messages.last?.id,
                                       message.role == .agent,
                                       !message.suggestedActions.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: Spacing.sm) {
                                                ForEach(message.suggestedActions) { action in
                                                    Button {
                                                        MtrxHaptics.impact(.medium)
                                                        viewModel.handleSuggestedAction(action.action)
                                                    } label: {
                                                        Text(action.title)
                                                            .font(.mtrxCaptionBold)
                                                            .foregroundStyle(
                                                                action.action == "demo_cancel"
                                                                    ? Color.labelSecondary
                                                                    : Color.accentPrimary
                                                            )
                                                            .padding(.horizontal, Spacing.md)
                                                            .padding(.vertical, Spacing.sm)
                                                            .background(
                                                                Capsule().fill(
                                                                    action.action == "demo_cancel"
                                                                        ? Color.backgroundTertiary
                                                                        : Color.accentPrimary.opacity(0.12)
                                                                )
                                                            )
                                                            .overlay(
                                                                Capsule().stroke(
                                                                    action.action == "demo_cancel"
                                                                        ? Color.clear
                                                                        : Color.accentPrimary.opacity(0.35),
                                                                    lineWidth: 1
                                                                )
                                                            )
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.leading, Spacing.xl)
                                        }
                                        .transition(.mtrxSlideUp)
                                    }
                                }
                                .id(message.id)
                            }

                            if viewModel.isTyping {
                                TypingIndicator(agent: viewModel.activeAgent)
                                    // Clearance so the bubble always lands
                                    // above the chips bar, never under it.
                                    .padding(.bottom, Spacing.xs)
                                    .id("typingIndicator")
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.md)
                        .opacity(showCenteredGreeting ? 0 : 1)
                        .animation(.easeInOut(duration: 0.25), value: showCenteredGreeting)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.messages.count) {
                        scrollToBottom(proxy: proxy)
                        resetIdleTimer()
                    }
                    .onChange(of: viewModel.inputText) { resetIdleTimer() }
                    .onChange(of: viewModel.isTyping) {
                        if viewModel.isTyping {
                            scrollToBottom(proxy: proxy, anchor: .bottom)
                        }
                    }
                    // A centered greeting before the conversation begins —
                    // like every modern assistant. It fades the moment the
                    // user starts typing or sends their first message.
                    .overlay {
                        if showCenteredGreeting {
                            // No orb — the room itself is the agent. Just the
                            // greeting, centered in the screen.
                            Text(greeting)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.labelPrimary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Spacing.xl)
                                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                                .allowsHitTesting(false)
                        }
                    }
                }

                // Input band — one continuous material band that bleeds past the
                // bottom edge, so the keyboard's rounded corners never expose dark
                // notches at the seam.
                VStack(spacing: 0) {
                    AppleWeatherAttributionView()
                    inputBar
                }
                .background {
                    // The band fades up from solid to clear so it melts into
                    // the wallpaper at the top edge — no hard seam — while
                    // still being opaque enough below that messages never
                    // ghost through the chips and input.
                    ZStack {
                        LinearGradient(
                            colors: [.clear, Color.backgroundPrimary.opacity(0.92), Color.backgroundPrimary],
                            startPoint: .top, endPoint: .bottom
                        )
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .mask(
                                LinearGradient(
                                    colors: [.clear, .black, .black],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    }
                    .padding(.top, -22)
                    .padding(.bottom, -40)
                    .ignoresSafeArea(edges: .bottom)
                }
            }

            // Morpheus overlay
            if morpheus.isPresenting, let intervention = morpheus.activeIntervention {
                MorpheusOverlay(intervention: intervention)
                    .transition(.opacity.animation(Motion.springDefault))
            }

            // Scenario 2 ban overlay
            if let ban = accessControl.banEvent {
                BanOverlay(event: ban)
                    .transition(.opacity.animation(Motion.springDefault))
            }

            // Scenario 2 community alert
            if let alert = accessControl.scenarioTwoAlert {
                CommunityAlertOverlay(alert: alert)
                    .transition(.mtrxSlideUp)
            }
        }
        .offset(y: isModal ? dismissDrag : 0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard isModal else { return }
                    // A downward drag from the upper area peels the room away.
                    if value.startLocation.y < 340,
                       value.translation.height > 0,
                       value.translation.height > abs(value.translation.width) {
                        dismissDrag = value.translation.height
                    } else if dismissDrag != 0 {
                        withAnimation(Motion.springSnappy) { dismissDrag = 0 }
                    }
                }
                .onEnded { value in
                    guard isModal else { return }
                    let w = value.translation.width
                    let h = value.translation.height
                    // Swipe left/right anywhere (below the switcher) to move
                    // between agents.
                    if abs(w) > 60, abs(w) > abs(h) * 1.4, value.startLocation.y > 130 {
                        cycleAgent(forward: w < 0)
                        withAnimation(Motion.springSnappy) { dismissDrag = 0 }
                        return
                    }
                    // Swipe down from the upper area to exit the room.
                    if value.startLocation.y < 340, h > 120, h > abs(w) {
                        dismiss()
                    } else {
                        withAnimation(Motion.springSnappy) { dismissDrag = 0 }
                    }
                }
        )
        .onChange(of: viewModel.activeAgent) { _, newAgent in
            // Swapping agents in the header re-voices the splash greeting
            // while it's still the one on screen.
            if showCenteredGreeting {
                greeting = Self.greeting(for: newAgent)
            }
        }
        .onChange(of: viewModel.dismissRequested) {
            // The agent has navigated the app — slide the chat away and
            // let the floating orb take over.
            if viewModel.dismissRequested {
                viewModel.dismissRequested = false
                dismiss()
            }
        }
        .onAppear {
            viewModel.setup(userID: userID, walletManager: walletManager)
            if let initialAgent {
                viewModel.openAgentChat(initialAgent)
            }
            // Greeting takes the voice of whoever's actually in the room.
            greeting = Self.greeting(for: initialAgent ?? viewModel.activeAgent)
            if let initialPrompt, viewModel.inputText.isEmpty {
                viewModel.inputText = initialPrompt
                isInputFocused = true
            }
            withAnimation(Motion.springDefault.delay(0.2)) {
                appeared = true
            }
            resetIdleTimer()
        }
        .onDisappear { idleTimer?.invalidate() }
        .sheet(isPresented: $showAgentIdentity) {
            AgentIdentityView()
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .sheet(isPresented: $showChats) {
            ChatHistorySheet(
                currentID: viewModel.conversationID,
                allowNeo: AgentAccessControl.shared.userType(for: userID) == .owner,
                onSelect: { viewModel.openConversation($0) },
                onNew: { viewModel.startNewConversation(agent: $0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Voice", isPresented: Binding(
            get: { viewModel.voiceError != nil },
            set: { if !$0 { viewModel.voiceError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.voiceError = nil }
        } message: {
            Text(viewModel.voiceError ?? "")
        }
    }

    // MARK: - Agent Space Header
    //
    // One floating glass capsule is the entire identity AND switcher:
    // the active agent shows as an expanded orb with its name; the
    // others wait as quiet orbs one tap away. The highlight slides
    // between agents with a shared-element morph.

    @Namespace private var agentSegmentNS
    /// The capsule's measured size — maps finger position to agents
    /// while sliding across the switcher.
    @State private var switcherSize: CGSize = .zero

    private var availableAgents: [AgentAccessControl.ActiveAgent] {
        AgentAccessControl.shared.userType(for: userID) == .owner
            ? [.trinity, .morpheus, .neo]
            : [.trinity, .morpheus]
    }

    /// Move to the next/previous agent — driven by a left/right screen swipe.
    private func cycleAgent(forward: Bool) {
        let agents = availableAgents
        guard agents.count > 1,
              let i = agents.firstIndex(of: viewModel.activeAgent) else { return }
        let next = forward ? (i + 1) % agents.count
                           : (i - 1 + agents.count) % agents.count
        MtrxHaptics.selection()
        withAnimation(Motion.springSnappy) { viewModel.openAgentChat(agents[next]) }
    }

    private var agentSpaceHeader: some View {
        // ZStack layout: the capsule centers itself and the chrome
        // buttons pin to the padded edges — neither can ever push the
        // other off-screen, whatever the capsule's width.
        ZStack {
            switcherCapsule
                .frame(maxWidth: .infinity)

            HStack {
                chromeButton("chevron.down", label: "Close conversation") { dismiss() }
                Spacer()
                chromeButton("square.and.pencil", label: "Chat history") { showChats = true }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private func chromeButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var switcherCapsule: some View {
        HStack(spacing: 3) {
            ForEach(availableAgents, id: \.self) { agent in
                agentSegment(agent)
            }
        }
        .padding(4)
        .mtrxLiquidGlass(in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { switcherSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in switcherSize = newSize }
            }
        )
        // The dock interaction: while your finger slides across the
        // capsule, a liquid-glass lens rides under it and the agents
        // switch live as you cross them. Tapping still works.
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    // Slide between agents with nothing riding under the
                    // finger — the morphing pill is the only feedback.
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let agents = availableAgents
                    guard switcherSize.width > 0, !agents.isEmpty else { return }
                    let zone = switcherSize.width / CGFloat(agents.count)
                    let index = min(max(Int(value.location.x / zone), 0), agents.count - 1)
                    if agents[index] != viewModel.activeAgent {
                        MtrxHaptics.selection()
                        withAnimation(Motion.springSnappy) {
                            viewModel.openAgentChat(agents[index])
                        }
                    }
                }
        )
    }

    private func agentSegment(_ agent: AgentAccessControl.ActiveAgent) -> some View {
        let isActive = viewModel.activeAgent == agent
        let colors = orbPalette(agent)

        return Button {
            guard !isActive else { return }
            MtrxHaptics.impact(.medium)
            withAnimation(Motion.springSnappy) {
                viewModel.openAgentChat(agent)
            }
        } label: {
            HStack(spacing: 6) {
                // Inactive agents show their little glass bubble. The
                // SELECTED agent shows only its name + status dot — no
                // bubble in the active pill.
                if isActive {
                    Text(AgentConversationViewModel.displayName(of: agent))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Circle()
                        .fill(Color.statusSuccess)
                        .frame(width: 5, height: 5)
                } else {
                    GlassOrb(size: 20, tint: bubblePalette(agent))
                }
            }
            .padding(.horizontal, isActive ? 14 : 7)
            .padding(.vertical, 6)
            .background {
                if isActive {
                    Capsule()
                        .fill(colors.0.opacity(0.15))
                        .overlay(Capsule().stroke(colors.0.opacity(0.32), lineWidth: 1))
                        .matchedGeometryEffect(id: "activeAgentSegment", in: agentSegmentNS)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Orb color pairs — kept for the active-pill tint, softened to the
    /// bubble language.
    private func orbPalette(_ agent: AgentAccessControl.ActiveAgent) -> (Color, Color) {
        switch agent {
        case .trinity: return (Color(red: 0.62, green: 0.88, blue: 0.92), Color(red: 0.72, green: 0.78, blue: 0.98))
        case .morpheus: return (Color(red: 0.98, green: 0.72, blue: 0.74), Color(red: 0.99, green: 0.85, blue: 0.72))
        case .neo: return (Color(red: 0.68, green: 0.92, blue: 0.74), Color(red: 0.92, green: 0.97, blue: 0.72))
        }
    }

    /// Pastel bubble films, one per agent — the same soap-bubble light
    /// as the floating orb, each in its own gentle key.
    private func bubblePalette(_ agent: AgentAccessControl.ActiveAgent) -> [Color] {
        switch agent {
        case .trinity:
            return [
                Color(red: 0.62, green: 0.90, blue: 0.92),
                Color(red: 0.72, green: 0.78, blue: 0.98),
                Color(red: 0.85, green: 0.92, blue: 0.99),
                Color(red: 0.62, green: 0.90, blue: 0.92),
            ]
        case .morpheus:
            return [
                Color(red: 0.99, green: 0.74, blue: 0.76),
                Color(red: 0.99, green: 0.86, blue: 0.72),
                Color(red: 0.96, green: 0.78, blue: 0.94),
                Color(red: 0.99, green: 0.74, blue: 0.76),
            ]
        case .neo:
            return [
                Color(red: 0.68, green: 0.93, blue: 0.76),
                Color(red: 0.90, green: 0.97, blue: 0.70),
                Color(red: 0.64, green: 0.92, blue: 0.88),
                Color(red: 0.68, green: 0.93, blue: 0.76),
            ]
        }
    }

    // NOTE: leaving the chat does NOT dock the orb. She docks only when
    // she navigates the app for the user (see navigate(to:)) — and from
    // that moment persists, through popups and full chats alike, until
    // deliberately flung off-screen.

    // MARK: - Idle Timeout

    /// After two minutes of no activity, the current chat is filed into the
    /// histories and a fresh one opens — so each return starts clean.
    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in
            Task { @MainActor in
                guard viewModel.messages.contains(where: { $0.role == .user }) else { return }
                let agent = viewModel.activeAgent
                viewModel.startNewConversation(agent: agent)
                greeting = Self.greeting(for: agent)
            }
        }
    }

    // MARK: - Scroll Helper

    private func scrollToBottom(proxy: ScrollViewProxy, anchor: UnitPoint = .bottom) {
        if let last = viewModel.messages.last {
            withAnimation(Motion.springSnappy) {
                proxy.scrollTo(viewModel.isTyping ? AnyHashable("typingIndicator") : AnyHashable(last.id), anchor: anchor)
            }
        }
    }

    // MARK: - Agent Header

    private var agentHeader: some View {
        HStack(spacing: Spacing.ms) {
            // Dismiss chevron when presented from the Home screen.
            if isModal {
                Button {
                    MtrxHaptics.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .frame(width: 30, height: 30)
                        .accessibilityLabel("Close")
                }
                .buttonStyle(.plain)
            }

            // Agent avatar — gradient circle with initial.
            // Long-press opens the AgentIdentityView sheet.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: agentGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)

                Text(agentInitial)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .mtrxGlow(color: agentGradientColors.first ?? .accentPrimary, radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(agentName)
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)

                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(viewModel.isTyping ? Color.accentTertiary : Color.statusSuccess)
                        .frame(width: 6, height: 6)

                    Text(agentStatus)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            Spacer()

            // Chats button — saved history + new chats per agent
            Button {
                MtrxHaptics.impact(.light)
                showChats = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .accessibilityLabel("Chat history")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            // Search button — opens SearchView sheet
            Button {
                MtrxHaptics.impact(.light)
                showSearch = true
            } label: {
                Image(systemName: Symbols.search)
                    .accessibilityLabel("Search")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            // Crypto markets never close.
            MtrxBadge(text: "Markets Live", style: .success)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.ms)
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            MtrxHaptics.impact(.medium)
            showAgentIdentity = true
        }
    }

    // The room's accents follow the bubble: each agent's pastel lead
    // colors the aurora, the focus ring, and the send button.
    private var agentGradientColors: [Color] {
        switch viewModel.activeAgent {
        case .trinity:
            return [Color(red: 0.62, green: 0.90, blue: 0.92), Color(red: 0.72, green: 0.78, blue: 0.98)]
        case .morpheus:
            return [Color(red: 0.99, green: 0.74, blue: 0.76), Color(red: 0.99, green: 0.86, blue: 0.72)]
        case .neo:
            return [Color(red: 0.68, green: 0.93, blue: 0.76), Color(red: 0.90, green: 0.97, blue: 0.70)]
        }
    }

    /// The active agent's signature color — used for focus rings and
    /// the send button so the whole bar quietly matches who's listening.
    private var agentAccent: Color {
        agentGradientColors.first ?? .accentPrimary
    }

    /// The full-screen agent wallpaper: the orb's own colors, expanded to
    /// fill the room and breathing on the same slow pulse. Re-tints per
    /// agent. It sinks to deep black at the very bottom so the input band
    /// blends in with no hard seam.
    private var agentWallpaper: some View {
        let palette = agentGlassTint(viewModel.activeAgent)
        let c0 = palette.first ?? .accentPrimary
        let c1 = palette.count > 1 ? palette[1] : c0
        let c2 = palette.count > 2 ? palette[2] : c1
        return TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathe = (sin(t * 0.8) + 1) / 2          // 0…1, slow breath
            let drift = CGFloat(sin(t * 0.3))
            ZStack {
                Color.backgroundPrimary
                RadialGradient(
                    colors: [c0.opacity(0.40 + 0.16 * breathe), c1.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.5 + 0.05 * drift, y: 0.40),
                    startRadius: 0,
                    endRadius: 340 + 90 * breathe
                )
                RadialGradient(
                    colors: [c2.opacity(0.18 + 0.12 * breathe), .clear],
                    center: UnitPoint(x: 0.32 - 0.06 * drift, y: 0.74),
                    startRadius: 0,
                    endRadius: 320
                )
                .blendMode(.screen)
                // Smooth, gradual sink to black top and bottom — no abrupt
                // break where the header or input band meet the wallpaper.
                LinearGradient(
                    colors: [
                        Color.backgroundPrimary.opacity(0.55),
                        .clear, .clear,
                        Color.backgroundPrimary.opacity(0.9),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }

    private var agentInitial: String {
        switch viewModel.activeAgent {
        case .trinity: return "T"
        case .morpheus: return "M"
        case .neo: return "N"
        }
    }

    private var agentName: String {
        switch viewModel.activeAgent {
        case .trinity: return "Trinity"
        case .morpheus: return "Morpheus"
        case .neo: return "Neo"
        }
    }

    private var agentStatus: String {
        if viewModel.isTyping { return "typing..." }
        return "online"
    }

    private func agentDotColor(for name: String?) -> Color {
        switch name {
        case "Morpheus": return Color(red: 0.99, green: 0.74, blue: 0.76)
        case "Neo": return Color(red: 0.68, green: 0.93, blue: 0.76)
        default: return Color(red: 0.62, green: 0.90, blue: 0.92)
        }
    }

    // MARK: - First Boot Message

    private var firstBootMessage: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: Symbols.trinityActive)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.trinityPrimary)

                    Spacer()
                }

                Text("Hi, my name is Trinity")
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)

                Text("Welcome to the world of MTRX, I'll be by your side the entire time if you need me")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            // Text field — addressed to whoever is in the room.
            TextField("Ask \(agentName)...", text: $viewModel.inputText, axis: .vertical)
                .font(.mtrxBody)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, Spacing.ms)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous)
                        .fill(Color.surfaceOverlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous)
                        .stroke(
                            isInputFocused ? agentAccent.opacity(0.45) : Color.clear,
                            lineWidth: 1
                        )
                        .animation(.easeOut(duration: 0.18), value: isInputFocused)
                )

            // Send button
            Button {
                MtrxHaptics.impact(.light)
                viewModel.sendMessage()
            } label: {
                Image(systemName: Symbols.send)
                    .accessibilityLabel("Send message")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.labelTertiary
                            : agentAccent
                    )
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: AgentMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 56) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.xs) {
                // Agent name label with colored dot
                if !isUser {
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(agentDotColor)
                            .frame(width: 8, height: 8)

                        Text(message.agentName ?? "Trinity")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(agentDotColor)
                    }
                    .padding(.leading, Spacing.xs)
                }

                // Bubble — agents speak markdown (bold, lists); render it
                // instead of showing literal asterisks.
                Text(formattedText)
                    .font(.mtrxBody)
                    .foregroundStyle(isUser ? .white : Color.labelPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(bubbleShape)
                    .overlay(
                        bubbleShape.stroke(
                            isUser ? Color.clear : agentDotColor.opacity(0.16),
                            lineWidth: 1
                        )
                    )

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelQuaternary)
                    .padding(.horizontal, Spacing.xs)
            }

            if !isUser { Spacer(minLength: 56) }
        }
    }

    /// Inline markdown (bold, italics, code) parsed per line so list
    /// dashes and line breaks survive; plain text passes through untouched.
    private var formattedText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: message.text, options: options))
            ?? AttributedString(message.text)
    }

    private var bubbleBackground: some View {
        Group {
            if isUser {
                LinearGradient(
                    colors: [Color.accentPrimary, Color.accentPrimary.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.surfaceCard.overlay(agentDotColor.opacity(0.045))
            }
        }
    }

    private var bubbleShape: some Shape {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    // Pastel keys matching each agent's bubble — soft, never alarming.
    private var agentDotColor: Color {
        switch message.agentName {
        case "Morpheus": return Color(red: 0.99, green: 0.74, blue: 0.76)
        case "Neo": return Color(red: 0.68, green: 0.93, blue: 0.76)
        default: return Color(red: 0.62, green: 0.90, blue: 0.92)
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    let agent: AgentAccessControl.ActiveAgent

    @State private var dotPhases: [Bool] = [false, false, false]

    private var dotColor: Color {
        switch agent {
        case .trinity: return .trinityPrimary
        case .morpheus: return .statusError
        case .neo: return .statusSuccess
        }
    }

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotPhases[i] ? 1.0 : 0.5)
                        .opacity(dotPhases[i] ? 1.0 : 0.35)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()
        }
        .onAppear {
            startPulse()
        }
    }

    private func startPulse() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.15)
            ) {
                dotPhases[i] = true
            }
        }
    }
}

// MARK: - Morpheus Overlay

struct MorpheusOverlay: View {
    let intervention: MorpheusIntervention
    @ObservedObject private var morpheus = MorpheusInterventions.shared
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    if !intervention.requiresConfirmation && !intervention.autoDismiss {
                        morpheus.dismiss()
                    }
                }

            VStack(spacing: Spacing.lg) {
                // Morpheus avatar
                ZStack {
                    Circle()
                        .fill(Color.statusError.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.statusError, Color.statusError.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Text("M")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .mtrxGlow(color: .statusError, radius: 10)

                Text("Morpheus")
                    .font(.mtrxTitle3)
                    .foregroundStyle(.white)

                Text(intervention.message)
                    .font(.mtrxBody)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.md)

                if intervention.requiresConfirmation {
                    HStack(spacing: Spacing.md) {
                        Button("Cancel") {
                            MtrxHaptics.impact(.light)
                            morpheus.dismiss()
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .ghost))

                        Button("I understand. Proceed.") {
                            MtrxHaptics.warning()
                            _ = morpheus.confirmAction()
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .destructive))
                    }
                    .padding(.top, Spacing.sm)
                } else if !intervention.autoDismiss {
                    Button("Continue") {
                        MtrxHaptics.impact(.light)
                        morpheus.dismiss()
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary))
                    .padding(.top, Spacing.sm)
                }
            }
            .padding(Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.xxl, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.xxl, style: .continuous)
                            .stroke(Color.statusError.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(Spacing.lg)
            .mtrxScaleIn(isVisible: appeared)
        }
        .onAppear {
            withAnimation(Motion.springDefault) {
                appeared = true
            }
        }
    }
}

// MARK: - Ban Overlay (Scenario 2)

struct BanOverlay: View {
    let event: BanEvent
    @State private var remainingSeconds: Int = 10
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.statusError)
                    .mtrxGlow(color: .statusError, radius: 12)

                Text("Access Permanently Revoked")
                    .font(.mtrxTitle2)
                    .foregroundStyle(.white)

                Text("Your access to MTRX has been permanently revoked due to unauthorized activity.")
                    .font(.mtrxBody)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                Text("This message will disappear in \(remainingSeconds) seconds.")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
                    .padding(.top, Spacing.sm)
            }
            .mtrxScaleIn(isVisible: appeared)
        }
        .onAppear {
            withAnimation(Motion.springDefault) {
                appeared = true
            }
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                remainingSeconds -= 1
                if remainingSeconds <= 0 { timer.invalidate() }
            }
        }
    }
}

// MARK: - Community Alert Overlay (Scenario 2 broadcast)

struct CommunityAlertOverlay: View {
    let alert: ScenarioTwoAlert
    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: Spacing.ms) {
                ZStack {
                    Circle()
                        .fill(Color.statusError)
                        .frame(width: 28, height: 28)

                    Text("M")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Text("A user has been permanently removed from MTRX.")
                    .font(.mtrxSubheadline)
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                    .fill(Color.statusError.opacity(0.9))
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, 100)
            .mtrxFadeInFromBottom(isVisible: appeared)
        }
        .onAppear {
            withAnimation(Motion.springDefault) {
                appeared = true
            }
        }
    }
}

// MARK: - Apple Weather attribution (WeatherKit compliance)

/// Apple REQUIRES the Apple Weather mark + a link to its legal attribution page
/// wherever WeatherKit data is surfaced. This footer appears in the agent chat
/// once Trinity has provided weather this session (see WeatherKitAttribution).
struct AppleWeatherAttributionView: View {
    @State private var attribution = WeatherKitAttribution.shared

    var body: some View {
        if attribution.isActive {
            HStack(spacing: 5) {
                Image(systemName: "applelogo")
                    .font(.system(size: 9, weight: .medium))
                Text("Weather")
                    .font(.system(size: 10, weight: .semibold))
                if let url = attribution.legalPageURL {
                    Text("·").font(.system(size: 10)).foregroundStyle(Color.labelQuaternary)
                    Link("Other data sources", destination: url)
                        .font(.system(size: 10))
                        .tint(Color.labelTertiary)
                }
            }
            .foregroundStyle(Color.labelTertiary)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Weather data provided by Apple Weather")
        }
    }
}
