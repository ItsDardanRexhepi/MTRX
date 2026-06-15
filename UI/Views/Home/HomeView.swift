// HomeView.swift
// MTRX — Home tab.
//
// The welcome screen: greets the user, puts their agents one tap away,
// and surfaces the most-used actions immediately. Chats open full-screen
// over the dashboard and slide back down to it.

import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var chatStore = ConversationStore.shared
    @ObservedObject private var dailyFlow = DailyFlow.shared
    @ObservedObject private var socialFeed = SocialViewModel.shared
    @State private var feedScrollIndex: Int?
    @State private var feedTimer: Timer?
    /// The Home feed is fully interactive — these drive the detail and
    /// profile windows opened from a feed card.
    @State private var homeDetailPost: SocialPostDisplay?
    @State private var homeProfileAuthor: SocialPostDisplay?

    @State private var presentedChat: ChatLaunch?
    @State private var appeared = false
    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var askedForName = false
    @State private var presentedService: HomeService?
    @State private var showDailyFlow = false
    @State private var flowDestination: DailyFlow.Goal?
    @State private var showPortfolio = false

    /// What to open the chat with: an agent and an optional prefill.
    struct ChatLaunch: Identifiable {
        let id = UUID()
        let agent: AgentAccessControl.ActiveAgent
        var prompt: String?
    }

    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .trinityGlow)

            // Sized so the whole dashboard — greeting through Services —
            // fits one screen above the dock. Even 20pt section rhythm.
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    greetingHeader
                        .mtrxStaggeredAppearance(index: 0, isVisible: appeared)

                    // While the ask bar is focused, the rest of the page
                    // gently recedes so the bar is what you're working in —
                    // but everything stays tappable underneath.
                    Group {
                        portfolioSnapshot
                            .mtrxStaggeredAppearance(index: 1, isVisible: appeared)

                        quickActionsSection
                            .mtrxStaggeredAppearance(index: 2, isVisible: appeared)

                        homeFeedSection
                            .mtrxStaggeredAppearance(index: 3, isVisible: appeared)
                    }
                    .opacity(askFocused ? 0.42 : 1)
                    .blur(radius: askFocused ? 1.5 : 0)
                    .animation(.easeInOut(duration: 0.4), value: askFocused)
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.sm)
                // The floating dock already reserves its own safe-area inset,
                // so only a small breath is needed here — no dead space.
                .padding(.bottom, Spacing.md)
                // In edit mode, tapping empty space exits jiggle — no need
                // to reach for Done.
                .background {
                    if editingActions {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { exitEditMode() }
                    } else if askFocused {
                        // Tap any empty (unclickable) area to leave the search
                        // bar and drop the keyboard. Quick actions and the
                        // portfolio stay tappable — their own taps are
                        // consumed before reaching this catcher.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { askFocused = false }
                    }
                }
            }
            // Any scroll drops the keyboard instantly — the easiest way out.
            .scrollDismissesKeyboard(.immediately)

            // The inline chat that grows from the search bar.
            if homeChatOpen {
                // Softly blur the dashboard so focus lands on the chat —
                // toned down ~20% so the dashboard reads through a touch more.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.8)
                    .overlay(Color.black.opacity(0.14))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { closeHomeChat() }
                    .zIndex(40)
                homeChatPanel
                    // A contained scale-from-top + fade — GPU-cheap and
                    // perfectly smooth at 120Hz (no cross-view geometry to
                    // recompute every frame).
                    .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                    .zIndex(50)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mtrxOpenService)) { note in
            if let raw = note.userInfo?["service"] as? String,
               let service = HomeService(rawValue: raw) {
                presentedService = service
            }
        }
        .onAppear {
            withAnimation(Motion.springDefault.delay(0.1)) {
                appeared = true
            }
            // One-time: adopt the new quick-action order (Pay, Shop, Invest,
            // Play, Earn, Events) even for existing installs.
            if !quickActionsMigratedV2 {
                quickActionsRaw = "pay,shop,invest,play,earn,events"
                quickActionsMigratedV2 = true
            }
            // Apple only shares the name on the first-ever sign-in, so
            // when it's missing, ask once — then it persists for good.
            if appState.displayName.isEmpty && !askedForName {
                askedForName = true
                nameDraft = ""
                showNameEditor = true
            }
        }
        .fullScreenCover(item: $presentedChat) { launch in
            AgentConversationView(
                userID: appState.currentUserID,
                initialAgent: launch.agent,
                initialPrompt: launch.prompt,
                isModal: true
            )
            .environmentObject(appState)
            .environmentObject(walletManager)
        }
        // The Home feed is fully interactive — open a post or a profile in place.
        .sheet(item: $homeDetailPost) { post in
            PostDetailSheet(postID: post.id)
                .environmentObject(appState)
        }
        .sheet(item: $homeProfileAuthor) { post in
            UserProfileSheet(author: post)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showDailyFlow, onDismiss: {
            // Navigate only after the sheet has fully closed — switching
            // tabs mid-dismissal cancels the dismissal.
            guard let destination = flowDestination else { return }
            flowDestination = nil
            switch destination {
            case .agent:
                presentedChat = ChatLaunch(agent: .trinity)
            case .social:
                NotificationCenter.default.post(name: .mtrxSwitchTab, object: nil, userInfo: ["index": 3])
            case .explore:
                NotificationCenter.default.post(name: .mtrxSwitchTab, object: nil, userInfo: ["index": 0])
            }
        }) {
            DailyFlowSheet(
                onAgent: {
                    flowDestination = .agent
                    showDailyFlow = false
                },
                onSocial: {
                    flowDestination = .social
                    showDailyFlow = false
                },
                onExplore: {
                    flowDestination = .explore
                    showDailyFlow = false
                }
            )
            .presentationDetents([.height(500)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $presentedService) { service in
            NavigationStack {
                service.destination
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { presentedService = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPortfolio) {
            // The portfolio opens like a banking app: balance, moves,
            // holdings, and activity — everything happens in here.
            PortfolioSheet()
                .environmentObject(walletManager)
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Greeting and date share one eyebrow line — the dashboard
            // below needs the vertical room more than the calendar does.
            // The live transport indicator rides at the trailing edge.
            Text("\(timeGreeting) · \(Date().formatted(.dateTime.weekday(.wide).month(.wide).day().year()))")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.trinityPrimary.opacity(0.85))
                .textCase(.uppercase)
                .kerning(1.2)

            HStack(spacing: Spacing.sm) {
                // The name edits itself — tap it, no pencil needed. Its
                // colors drift slowly and endlessly, a gentle living sheen.
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let shift = CGFloat(sin(t * 0.25)) * 0.5
                    Text(firstName)
                        .font(.mtrxLargeTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.labelPrimary, Color.trinityPrimary, Color(red: 0.72, green: 0.78, blue: 0.99), Color.labelPrimary],
                                startPoint: UnitPoint(x: -0.5 + shift, y: 0.5),
                                endPoint: UnitPoint(x: 1.0 + shift, y: 0.5)
                            )
                        )
                }
                .onTapGesture {
                    MtrxHaptics.impact(.light)
                    nameDraft = appState.displayName
                    showNameEditor = true
                }

                // Daily flow ring — the open loop of the day.
                Button {
                    MtrxHaptics.impact(.light)
                    showDailyFlow = true
                } label: {
                    ZStack {
                        MtrxProgressRing(
                            progress: max(dailyFlow.progress, 0.04),
                            size: 30, lineWidth: 3.5,
                            color: dailyFlow.isComplete ? .statusSuccess : .trinityPrimary,
                            showLabel: false
                        )
                        if dailyFlow.isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.statusSuccess)
                        } else {
                            Text("\(dailyFlow.completed.count)/3")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.labelPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)

                // The ask bar and the orb are one element: a single glass
                // pill wearing the orb's iridescent skin. Tap to open the
                // chat; the bar hides while the chat is open (its space is
                // held so the row doesn't reflow).
                homeAskOrb
                    .opacity(homeChatOpen ? 0 : 1)
            }
            .alert("Your Name", isPresented: $showNameEditor) {
                TextField("Name", text: $nameDraft)
                Button("Save") { appState.updateDisplayName(nameDraft) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Shown in your greeting and on your posts.")
            }

            // A calm, reassuring beat before any numbers — people stay
            // where they feel things are under control.
            Text(reassuranceLine)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.trinityPrimary.opacity(0.75))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Soft signature glow rising behind the greeting — a radial
            // gradient, not a live blur, so scrolling never pays for it.
            RadialGradient(
                colors: [Color.trinityPrimary.opacity(0.14), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 170
            )
            .frame(width: 340, height: 340)
            // Centered on the user's name, bleeding to the top-left edge.
            .offset(x: -70, y: -112),
            alignment: .topLeading
        )
    }

    private var timeGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Welcome back"
        }
    }

    private var firstName: String {
        let name = appState.displayName
        if let first = name.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }
        return name.isEmpty ? "Welcome" : name
    }

    /// The Home ask bar — type a command or talk to Trinity, right here.
    @State private var askText = ""
    @FocusState private var askFocused: Bool
    /// The inline chat that grows out of the search bar — no full-screen
    /// Trinity unless the user taps to extend into it.
    /// The home chat is driven by the real Trinity view model, so she has
    /// her full capabilities right here — navigation, actions, live answers.
    @StateObject private var homeChatVM = AgentConversationViewModel()
    @State private var homeChatSetup = false
    @State private var homeChatOpen = false
    @State private var homeChatDrag: CGFloat = 0
    /// The in-chat input is its own field so typing here never leaks back
    /// into the top search bar.
    @State private var homeChatInput = ""
    @FocusState private var homeChatFocused: Bool

    /// Transparent liquid-glass field that extends from the orb. The
    /// placeholder shows only while empty (standard search-bar behavior);
    /// submitting hands the text to Trinity to action or answer.
    /// The orb's pastel palette — the bar flows through these colors.
    private static let askFlowColors: [Color] = [
        Color(red: 0.60, green: 0.92, blue: 0.96),
        Color(red: 0.78, green: 0.80, blue: 0.99),
        Color(red: 0.99, green: 0.82, blue: 0.93),
        Color(red: 0.99, green: 0.94, blue: 0.80),
        Color(red: 0.70, green: 0.97, blue: 0.88),
        Color(red: 0.60, green: 0.92, blue: 0.96),
    ]

    private var homeAskOrb: some View {
        HStack(spacing: 8) {
            TextField("What're we building?", text: $askText)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelPrimary)
                .focused($askFocused)
                .submitLabel(.go)
                .onSubmit(runHomeAsk)
                .tint(Color.trinityPrimary)
                .padding(.leading, 6)
            // The orb lives at the end of the field — tap to open the
            // full agent space.
            Button {
                MtrxHaptics.impact(.medium)
                presentedChat = ChatLaunch(agent: .trinity)
            } label: {
                GlassOrb(size: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 11)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(askBarFlow)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(.white.opacity(askFocused ? 0.22 : 0.12), lineWidth: 1)
        )
        // Pops out a touch and lifts when you start typing — silky, no jolt.
        .scaleEffect(askFocused ? 1.045 : 1.0)
        // A quiet resting shadow gives the pill depth; the colored glow
        // blooms only on focus.
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
        .shadow(color: Color(red: 0.62, green: 0.78, blue: 0.98).opacity(askFocused ? 0.45 : 0.0),
                radius: askFocused ? 18 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: askFocused)
        // Tapping the bar opens the chat right away — it unfurls from here.
        .onChange(of: askFocused) { _, focused in
            if focused && !homeChatOpen { openHomeChatFromBar() }
        }
        .zIndex(2)
    }

    /// The continuously flowing iridescent fill — frame-driven by a
    /// TimelineView so it eases endlessly with zero spring jitter.
    private var askBarFlow: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // A slow sine sweep gives the gradient its ebb and flow; a
            // gentle continuous hue drift keeps the color alive.
            let sweep = CGFloat(sin(t * 0.45)) * 0.55
            let hue = (t * 9).truncatingRemainder(dividingBy: 360)
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: Self.askFlowColors,
                            startPoint: UnitPoint(x: -0.4 + sweep, y: 0.5),
                            endPoint: UnitPoint(x: 1.4 + sweep, y: 0.5)
                        )
                    )
                    .hueRotation(.degrees(hue))
                    .opacity(askFocused ? 0.40 : 0.26)
                    .blendMode(.screen)
            }
        }
    }

    /// Submitting the bar (or the in-chat input) runs the command right here
    /// in Home — it only opens the full Trinity space if the user asks.
    private func ensureHomeChatSetup() {
        guard !homeChatSetup else { return }
        // The Home pop-up chat is ephemeral — never saved, fresh every open.
        homeChatVM.ephemeral = true
        homeChatVM.setup(userID: appState.currentUserID, walletManager: walletManager)
        homeChatSetup = true
    }

    /// Submitting the top search bar opens the inline chat (its own field).
    private func runHomeAsk() {
        let text = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        askText = ""
        askFocused = false
        submitHomeChat(text)
    }

    /// Sending from inside the chat uses the chat's own input.
    private func sendHomeChat() {
        let text = homeChatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        homeChatInput = ""
        submitHomeChat(text)
    }

    /// Tapping the search bar unfurls the chat immediately and hands focus
    /// to the chat's own input — no separate window, just the bar opening up.
    private func openHomeChatFromBar() {
        ensureHomeChatSetup()
        // Always a fresh chat — the pop-up never remembers the last one.
        homeChatVM.startNewConversation(agent: .trinity, announce: false)
        withAnimation(.smooth(duration: 0.42)) { homeChatOpen = true }
        DispatchQueue.main.async {
            askFocused = false
            homeChatFocused = true
        }
    }

    /// Routes the message through the real Trinity model — full capabilities,
    /// live answers, navigation, and actions, right here in Home.
    private func submitHomeChat(_ text: String) {
        ensureHomeChatSetup()
        if !homeChatOpen {
            // Opening fresh from the search bar — clean slate every time.
            homeChatVM.startNewConversation(agent: .trinity, announce: false)
            withAnimation(.smooth(duration: 0.42)) { homeChatOpen = true }
        }
        homeChatVM.inputText = text
        homeChatVM.sendMessage()
    }

    private func extendToTrinity() {
        let context = homeChatVM.messages
            .map { ($0.role == .user ? "Me: " : "Trinity: ") + $0.text }
            .joined(separator: "\n")
        let hadChat = !homeChatVM.messages.isEmpty
        closeHomeChat()
        presentedChat = ChatLaunch(agent: .trinity, prompt: hadChat ? context : nil)
    }

    private func closeHomeChat() {
        homeChatFocused = false
        homeChatInput = ""
        homeChatVM.dismissRequested = false
        withAnimation(.smooth(duration: 0.4)) {
            homeChatOpen = false
            homeChatDrag = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if !homeChatOpen {
                // Fresh conversation next time it opens.
                homeChatVM.startNewConversation(agent: .trinity, announce: false)
            }
        }
    }

    // MARK: - Inline Home Chat — an extension of the search bar itself.

    /// The same iridescent flowing fill as the search pill, in a rounded
    /// card — so the chat reads as the search bar growing open.
    private var chatCardFlow: some View {
        // Just the flowing colors over a soft tint — the real glass comes
        // from .mtrxLiquidGlass applied on top, so the card refracts the
        // dashboard behind it while keeping these colors alive.
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let sweep = CGFloat(sin(t * 0.45)) * 0.55
            let hue = (t * 9).truncatingRemainder(dividingBy: 360)
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: Self.askFlowColors,
                            startPoint: UnitPoint(x: -0.4 + sweep, y: 0.5),
                            endPoint: UnitPoint(x: 1.4 + sweep, y: 0.5)
                        )
                    )
                    .hueRotation(.degrees(hue))
                    // Color toned down ~10% so it's calmer than the search pill.
                    .opacity(0.20)
                    .blendMode(.screen)
            }
        }
    }

    /// The card grows out of the search bar: anchored just under it, it
    /// expands left (full width) and down to just above the keyboard, wearing
    /// the bar's own design. Trinity answers here with her full capabilities.
    private var homeChatPanel: some View {
        GeometryReader { geo in
        // Space available above the keyboard (geo is keyboard-aware here).
        let usable = geo.size.height - 28
        // The card may grow until just shy of the keyboard, never past it.
        let cap = max(240, usable - 6)
        // The start window the user already tuned (~2/3 of the space). The
        // card grows downward from here as the message lengthens, never past
        // the cap — at which point the input scrolls within itself.
        let base = min(cap, max(240, usable * 0.675))
        // While composing a fresh message (no transcript yet), the card grows
        // by one line's height for each wrapped line of the message beyond the
        // first — estimated from the text so there is no layout feedback — and
        // extends toward the keyboard, capping there so the input then scrolls.
        let composing = homeChatVM.messages.isEmpty
        let lineHeight: CGFloat = 19
        let charsPerLine = 34.0
        let lineCount = homeChatInput
            .components(separatedBy: "\n")
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / charsPerLine))) }
        let grown = base + CGFloat(max(0, lineCount - 1)) * lineHeight
        let cardHeight = composing ? min(cap, grown) : base
        VStack(spacing: 0) {
            // The card lifts so its top-right notch reaches up to the search
            // Starts ~1/4" higher, up into where the search bar sits (which
            // is hidden while the chat is open).
            Color.clear.frame(height: 28)

            VStack(spacing: Spacing.sm) {
                // Header — tapping Trinity's name opens the full Trinity space
                // (replacing the old "Open in Trinity" button); X closes.
                HStack(spacing: Spacing.sm) {
                    Button { extendToTrinity() } label: {
                        HStack(spacing: Spacing.sm) {
                            GlassOrb(size: 24, tint: agentGlassTint(homeChatVM.activeAgent))
                            Text(AgentConversationViewModel.displayName(of: homeChatVM.activeAgent))
                                .font(.mtrxCalloutBold)
                                .foregroundStyle(Color.labelPrimary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { closeHomeChat() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .buttonStyle(.plain)
                }

                // Conversation — the real Trinity transcript. Fills the card.
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: Spacing.sm) {
                            ForEach(homeChatVM.messages) { msg in
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    HStack {
                                        if msg.role == .user { Spacer(minLength: 36) }
                                        Text(msg.text)
                                            .font(.mtrxCallout)
                                            .foregroundStyle(msg.role == .user ? .white : Color.labelPrimary)
                                            .padding(.horizontal, Spacing.md)
                                            .padding(.vertical, Spacing.sm)
                                            .background(msg.role == .user ? Color.trinityPrimary : Color.black.opacity(0.35))
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                            .textSelection(.enabled)
                                        if msg.role != .user { Spacer(minLength: 36) }
                                    }

                                    // Trinity's actionable chips on her latest
                                    // reply — full capability right here in Home.
                                    if msg.id == homeChatVM.messages.last?.id,
                                       msg.role == .agent,
                                       !msg.suggestedActions.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: Spacing.sm) {
                                                ForEach(msg.suggestedActions) { action in
                                                    Button {
                                                        MtrxHaptics.impact(.medium)
                                                        homeChatVM.handleSuggestedAction(action.action)
                                                    } label: {
                                                        Text(action.title)
                                                            .font(.mtrxCaptionBold)
                                                            .foregroundStyle(Color.accentPrimary)
                                                            .padding(.horizontal, Spacing.md)
                                                            .padding(.vertical, Spacing.sm)
                                                            .background(Capsule().fill(Color.accentPrimary.opacity(0.15)))
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
                                }
                                .id(msg.id)
                            }
                            if homeChatVM.isTyping {
                                HStack {
                                    TypingIndicator(agent: .trinity)
                                    Spacer(minLength: 36)
                                }
                                .id("homeTyping")
                            }
                        }
                        .padding(.vertical, 2)
                        // Report the transcript's true height so the card can
                    }
                    // The transcript fills the bubble and scrolls within it —
                    // newest message pinned to the bottom, just above the input
                    // — so it never overruns the keyboard.
                    .frame(maxHeight: .infinity)
                    .defaultScrollAnchor(.bottom)
                    // A centered greeting fills the empty chat until the user
                    // starts typing — the same prompt every time it opens.
                    .overlay {
                        if homeChatVM.messages.isEmpty && homeChatInput.isEmpty {
                            Text("What're we building?")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.labelSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Spacing.lg)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: homeChatInput.isEmpty)
                    .onChange(of: homeChatVM.messages.count) {
                        if let last = homeChatVM.messages.last {
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: homeChatVM.isTyping) {
                        if homeChatVM.isTyping {
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("homeTyping", anchor: .bottom) }
                        }
                    }
                }

                // Input — the search pill, restated inside the chat.
                HStack(spacing: 8) {
                    TextField("Message Trinity…", text: $homeChatInput, axis: .vertical)
                        // Empty transcript → the input may grow tall enough to
                        // push the card all the way to the keyboard before it
                        // scrolls; once messages exist, keep it modest so the
                        // transcript stays visible.
                        .lineLimit(1...(homeChatVM.messages.isEmpty ? 16 : 6))
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelPrimary)
                        .focused($homeChatFocused)
                        .tint(Color.trinityPrimary)
                        .padding(.leading, 6)
                    Button { sendHomeChat() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(homeChatInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color.labelQuaternary : Color.trinityPrimary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(homeChatInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.leading, 11)
                .padding(.trailing, 5)
                .padding(.vertical, 5)
                .background(askBarFlow)
                // A rounded-rectangle "squircle" — like an iMessage bubble —
                // rather than a full stadium/oval, so a tall multi-line message
                // reads as a message field, not a pill.
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
            }
            .padding(Spacing.md)
            // The card extends toward the keyboard as the message grows, then
            // caps there — at which point the input scrolls within itself.
            .frame(height: cardHeight, alignment: .top)
            .animation(.smooth(duration: 0.24), value: cardHeight)
            .background(chatCardFlow)
            // Clean liquid-glass card — translucent, blurred, app-signature.
            .mtrxLiquidGlass(cornerRadius: 30)
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.bottom, Spacing.xs)
            .offset(y: max(0, homeChatDrag))
            .gesture(
                DragGesture()
                    .onChanged { v in if v.translation.height > 0 { homeChatDrag = v.translation.height } }
                    .onEnded { v in
                        if v.translation.height > 90 { closeHomeChat() }
                        else { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { homeChatDrag = 0 } }
                    }
            )
        }
        .onChange(of: homeChatVM.dismissRequested) {
            // Trinity navigated the app for the user → close the home chat.
            if homeChatVM.dismissRequested { closeHomeChat() }
        }
        }
    }


    // MARK: - Quick Actions (editable, jiggle-mode)

    /// The user's chosen quick actions, persisted and reorderable. Long-
    /// press any tile (or tap Edit) to enter jiggle mode: remove with the
    /// red badge, add from the picker. Their home screen, their choices.
    @AppStorage("com.mtrx.home.quickActions") private var quickActionsRaw =
        "pay,shop,invest,play,earn,events"
    /// One-time reset so existing installs pick up the new default order.
    @AppStorage("com.mtrx.home.quickActions.v2") private var quickActionsMigratedV2 = false
    @State private var editingActions = false
    @State private var jiggle = false
    @State private var showActionPicker = false
    @State private var draggingAction: HomeAction?

    /// Hard cap — the home screen always holds at most six quick actions.
    static let maxQuickActions = 6

    private var chosenActions: [HomeAction] {
        Array(quickActionsRaw.split(separator: ",").compactMap { HomeAction(rawValue: String($0)) }.prefix(Self.maxQuickActions))
    }
    private func setActions(_ list: [HomeAction]) {
        quickActionsRaw = list.prefix(Self.maxQuickActions).map(\.rawValue).joined(separator: ",")
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.ms) {
            HStack {
                sectionTitle("Quick actions")
                Spacer()
                Button {
                    MtrxHaptics.impact(.light)
                    withAnimation(Motion.springSnappy) { editingActions.toggle() }
                    startJiggle(editingActions)
                } label: {
                    Text(editingActions ? "Done" : "Edit")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.trinityPrimary)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
                ForEach(chosenActions) { action in
                    actionTile(action)
                }
                if editingActions && chosenActions.count < Self.maxQuickActions {
                    addActionTile
                }
            }
            // Press and hold anywhere in the Quick actions area to enter
            // edit mode — no need to reach for the Edit button.
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.45) {
                if !editingActions {
                    MtrxHaptics.impact(.medium)
                    withAnimation(Motion.springSnappy) { editingActions = true }
                    startJiggle(true)
                }
            }
        }
        .sheet(isPresented: $showActionPicker) {
            QuickActionPicker(chosen: chosenActions) { added in
                setActions(chosenActions + [added])
                showActionPicker = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    private func exitEditMode() {
        guard editingActions else { return }
        MtrxHaptics.impact(.light)
        withAnimation(Motion.springSnappy) { editingActions = false }
        startJiggle(false)
    }

    private func startJiggle(_ on: Bool) {
        if on {
            jiggle = false
            // Slow, gentle sway — a soft breathing tilt, not a buzz.
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                jiggle = true
            }
        } else {
            // A repeatForever animation does NOT stop when you simply assign a
            // new value with withAnimation — it keeps oscillating. Killing it
            // in a transaction that disables animation truly cancels it so the
            // tiles settle flat the moment you leave edit mode.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { jiggle = false }
        }
    }

    private func actionTile(_ action: HomeAction) -> some View {
        // A plain styled view (not a Button) so tap and press-and-hold can
        // coexist: a quick tap opens the action, a hold enters edit mode.
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle().fill(action.color.opacity(0.14)).frame(width: 30, height: 30)
                Image(systemName: action.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(action.color)
            }
            Text(action.title)
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.ms)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(action.color.opacity(0.04))
        .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                .stroke(action.color.opacity(0.22), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
        // Hold to edit — recognized first, so it wins over the tap.
        .onLongPressGesture(minimumDuration: 0.45) {
            if !editingActions {
                MtrxHaptics.impact(.medium)
                withAnimation(Motion.springSnappy) { editingActions = true }
                startJiggle(true)
            }
        }
        .onTapGesture {
            guard !editingActions else { return }
            MtrxHaptics.impact(.light)
            open(action)
        }
        .overlay(alignment: .topLeading) {
            if editingActions {
                Button {
                    MtrxHaptics.impact(.light)
                    setActions(chosenActions.filter { $0 != action })
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, Color.statusError)
                        .background(Circle().fill(Color.backgroundPrimary).frame(width: 14, height: 14))
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
            }
        }
        .modifier(JiggleEffect(active: editingActions))
        // In edit mode the tiles are draggable to any of the six slots.
        .modifier(QuickActionDragReorder(
            action: action,
            enabled: editingActions,
            current: chosenActions,
            dragging: $draggingAction,
            commit: { setActions($0) }
        ))
    }

    private var addActionTile: some View {
        Button {
            MtrxHaptics.impact(.light)
            showActionPicker = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.trinityPrimary)
                    .frame(width: 30, height: 30)
                Text("Add")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.ms)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.trinityPrimary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .modifier(JiggleEffect(active: editingActions))
    }

    private func open(_ action: HomeAction) {
        if let prompt = action.prompt {
            presentedChat = ChatLaunch(agent: .trinity, prompt: prompt)
        } else if let service = action.service {
            presentedService = service
        }
    }

    // MARK: - Portfolio Snapshot

    private var portfolioSnapshot: some View {
        VStack(alignment: .leading, spacing: Spacing.ms) {
            sectionTitle("Portfolio")

            Button {
                MtrxHaptics.impact(.light)
                showPortfolio = true
            } label: {
                portfolioCardLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var portfolioCardLabel: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        walletManager.totalPortfolioValue,
                        format: .currency(code: "USD").precision(.fractionLength(2))
                    )
                    .font(.mtrxTitle1)
                    .foregroundStyle(Color.labelPrimary)

                    Spacer()

                    HStack(spacing: 3) {
                        Image(systemName: walletManager.portfolioChange24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(format: "%.2f%%", abs(walletManager.portfolioChange24h)))
                            .font(.mtrxCaptionBold)
                    }
                    .foregroundStyle(walletManager.portfolioChange24h >= 0 ? Color.statusSuccess : Color.statusError)
                }

                Divider().overlay(Color.labelQuaternary.opacity(0.3))

                HStack(spacing: Spacing.md) {
                    ForEach(walletManager.tokens.prefix(3), id: \.symbol) { token in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.symbol)
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                            Text(String(format: "%.3f", token.balance))
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelPrimary)
                        }
                        if token.symbol != walletManager.tokens.prefix(3).last?.symbol {
                            Spacer()
                        }
                    }
                }
            }
            .padding(Spacing.ms)
            .background(Color.trinityPrimary.opacity(0.035))
            .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.trinityPrimary.opacity(0.35), Color.trinityPrimary.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.trinityPrimary.opacity(0.08), radius: 14, y: 6)
    }

    // MARK: - Home Feed Window

    /// The social feed, living on Home: one post at a time in a paged
    /// window — swipe through chronologically, like and repost right
    /// here, and it's the same feed the Social tab shows.
    private var feedPosts: [SocialPostDisplay] {
        Array(socialFeed.posts.sorted { $0.timestamp > $1.timestamp }.prefix(5))
    }

    private var homeFeedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.ms) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Your feed")
                Spacer()
                Button {
                    MtrxHaptics.selection()
                    NotificationCenter.default.post(name: .mtrxSwitchTab, object: nil, userInfo: ["index": 3])
                } label: {
                    HStack(spacing: 3) {
                        Text("Open Social")
                            .font(.mtrxCaption1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.trinityPrimary.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            if feedPosts.isEmpty {
                Text("Your feed is warming up.")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                // A snapping, endlessly looping carousel: each card is exactly
                // the content width and snaps cleanly to one card at rest —
                // no wide channel. Clones front and back wrap it both ways,
                // and it auto-advances every 2 seconds.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(loopFeed.indices, id: \.self) { i in
                            feedCard(loopFeed[i])
                                .containerRelativeFrame(.horizontal)
                                .id(i)
                        }
                    }
                    .scrollTargetLayout()
                }
                .frame(height: 196)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $feedScrollIndex)
                .onAppear {
                    feedScrollIndex = feedPosts.count > 1 ? 1 : 0
                    startFeedRotation()
                }
                .onDisappear { stopFeedRotation() }
                .onChange(of: feedScrollIndex) { _, new in
                    guard let new, feedPosts.count > 1 else { return }
                    let n = feedPosts.count
                    // Wait for the scroll to fully settle on the clone before
                    // jumping to the identical real card — jumping mid-animation
                    // is what caused the stutter. The clone looks identical, so
                    // the swap is invisible.
                    if new == 0 || new == n + 1 {
                        let target = (new == 0) ? n : 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                            if feedScrollIndex == new { jumpFeed(to: target) }
                        }
                    }
                }
                // A new post landing up front restarts the loop cleanly.
                .onChange(of: feedPosts.count) { _, _ in
                    if feedPosts.count > 1 { jumpFeed(to: 1) }
                }

                // Quiet position dots — track the real index.
                HStack(spacing: 5) {
                    ForEach(0..<feedPosts.count, id: \.self) { index in
                        Capsule()
                            .fill(index == realFeedIndex ? Color.trinityPrimary : Color.labelQuaternary.opacity(0.5))
                            .frame(width: index == realFeedIndex ? 14 : 5, height: 5)
                            .animation(Motion.springSnappy, value: realFeedIndex)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
    }

    /// The feed padded with wrap-around clones for seamless looping.
    private var loopFeed: [SocialPostDisplay] {
        let posts = feedPosts
        guard posts.count > 1 else { return posts }
        return [posts[posts.count - 1]] + posts + [posts[0]]
    }

    /// The real post index the carousel is currently showing.
    private var realFeedIndex: Int {
        let n = feedPosts.count
        guard n > 1 else { return 0 }
        let idx = feedScrollIndex ?? 1
        return ((idx - 1) % n + n) % n
    }

    private func jumpFeed(to index: Int) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { feedScrollIndex = index }
    }

    /// Advance one post every two seconds; the clone-jump keeps it endless.
    private func startFeedRotation() {
        stopFeedRotation()
        guard feedPosts.count > 1 else { return }
        feedTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: true) { _ in
            Task { @MainActor in
                // Don't advance while the user is mid-wrap on a clone.
                let n = feedPosts.count
                let idx = feedScrollIndex ?? 1
                guard idx >= 1 && idx <= n else { return }
                withAnimation(.easeInOut(duration: 0.65)) {
                    feedScrollIndex = idx + 1
                }
            }
        }
    }

    private func stopFeedRotation() {
        feedTimer?.invalidate()
        feedTimer = nil
    }

    private func feedCard(_ post: SocialPostDisplay) -> some View {
        PostCardView(
            post: post,
            onLike: { socialFeed.toggleLike(postId: post.id) },
            onRepost: { socialFeed.toggleRepost(postId: post.id) },
            onComment: { homeDetailPost = post },
            onVotePoll: { socialFeed.voteOnPoll(postId: post.id, optionID: $0) },
            // Tapping the card opens the full, interactive post in place.
            onOpen: { homeDetailPost = post },
            onAvatarTap: { homeProfileAuthor = post }
        )
        .lineLimit(3)
        .padding(Spacing.ms)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // A fixed height so the card can never balloon to its full content
        // height; the clip keeps any longer content (polls, media) from
        // bleeding out past the card's rounded edge.
        .frame(height: 196, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
        .background(Color.trinityPrimary.opacity(0.03))
        .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Helpers

    /// Picks by time of day so the app feels alive, not canned.
    private var reassuranceLine: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Everything's ready — markets are live."
        case 12..<17: return "All systems running smoothly."
        case 17..<22: return "Your agents kept watch all day."
        default: return "Markets never sleep — your agents don't either."
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.mtrxHeadline)
            .foregroundStyle(Color.labelPrimary)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(WalletManager())
}

// MARK: - Home Services

/// The mini-app launcher: each case opens a full MTRX service.
// MARK: - Home Quick Action (editable)

/// One pickable quick action on Home — either the special Deploy flow
/// (handed to Trinity) or any of the app's services.
enum HomeAction: String, CaseIterable, Identifiable {
    case deploy
    case pay, invest, earn, shop, insure, play, events, identity, storage, bridge

    var id: String { rawValue }

    /// The underlying service, or nil for the special Deploy action.
    var service: HomeService? {
        switch self {
        case .deploy:   return nil
        case .pay:      return .pay
        case .invest:   return .invest
        case .earn:     return .defi
        case .shop:     return .shop
        case .insure:   return .insure
        case .play:     return .game
        case .events:   return .events
        case .identity: return .domains
        case .storage:  return .storage
        case .bridge:   return .bridge
        }
    }

    /// Prompt for Trinity (Deploy only).
    var prompt: String? {
        self == .deploy ? "Deploy a smart contract called " : nil
    }

    var title: String {
        self == .deploy ? "Deploy Contract" : (service?.title ?? rawValue.capitalized)
    }
    var icon: String {
        self == .deploy ? "doc.badge.gearshape.fill" : (service?.icon ?? "square.grid.2x2")
    }
    var color: Color {
        self == .deploy ? .accentTertiary : (service?.color ?? .trinityPrimary)
    }
}

// MARK: - Quick Action Picker

/// The add-action sheet: every action not already on the home screen,
/// one tap to add.
struct QuickActionPicker: View {
    let chosen: [HomeAction]
    let onAdd: (HomeAction) -> Void
    @Environment(\.dismiss) private var dismiss

    private var available: [HomeAction] {
        HomeAction.allCases.filter { !chosen.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                    ForEach(available) { action in
                        Button {
                            MtrxHaptics.impact(.light)
                            onAdd(action)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                ZStack {
                                    Circle().fill(action.color.opacity(0.14)).frame(width: 32, height: 32)
                                    Image(systemName: action.icon)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(action.color)
                                }
                                Text(action.title)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.labelPrimary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.trinityPrimary)
                            }
                            .padding(Spacing.ms)
                            .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.contentPadding)

                if available.isEmpty {
                    Text("Every action is already on your home screen.")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                        .padding(Spacing.xl)
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Add Quick Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

enum HomeService: String, CaseIterable, Identifiable {
    case pay, invest, defi, shop, insure, game, events, domains, storage, bridge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pay: return "Pay"
        case .invest: return "Invest"
        case .defi: return "Earn"
        case .shop: return "Shop"
        case .insure: return "Insure"
        case .game: return "Play"
        case .events: return "Events"
        case .domains: return "Identity"
        case .storage: return "Storage"
        case .bridge: return "Bridge"
        }
    }

    var icon: String {
        switch self {
        case .pay: return "bolt.circle.fill"
        case .invest: return "chart.line.uptrend.xyaxis.circle.fill"
        case .defi: return "percent"
        case .shop: return "bag.fill"
        case .insure: return "umbrella.fill"
        case .game: return "gamecontroller.fill"
        case .events: return "calendar"
        case .domains: return "person.crop.circle.badge.checkmark"
        case .storage: return "externaldrive.fill"
        case .bridge: return "arrow.left.arrow.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pay: return .trinityPrimary
        case .invest: return .statusSuccess
        case .defi: return .purple
        case .shop: return .pink
        case .insure: return .statusInfo
        case .game: return .orange
        case .events: return .yellow
        case .domains: return .accentPrimary
        case .storage: return .green
        case .bridge: return .blue
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .pay: StablecoinView()
        case .invest: TradingView()
        case .defi: YieldView()
        case .shop: MarketplaceView()
        case .insure: RWAView()
        case .game: GamingView()
        case .events: EventsView()
        case .domains: DomainView()
        case .storage: StorageView()
        case .bridge: BridgeView()
        }
    }
}

// MARK: - Daily Flow

/// The open loop that closes itself as the day is lived: talk to an
/// agent, touch your social world, explore something new. Day-keyed,
/// persisted, resets at midnight.
@MainActor
final class DailyFlow: ObservableObject {

    static let shared = DailyFlow()

    enum Goal: String, CaseIterable {
        case agent
        case social
        case explore

        var label: String {
            switch self {
            case .agent: return "Talk to an agent"
            case .social: return "Check your world"
            case .explore: return "Explore something new"
            }
        }
    }

    @Published private(set) var completed: Set<String> = []

    private let storageKey = "com.mtrx.dailyflow"
    private var todayKey: String {
        Date().formatted(.iso8601.year().month().day())
    }

    private init() {
        reload()
    }

    func mark(_ goal: Goal) {
        reload()
        guard !completed.contains(goal.rawValue) else { return }
        completed.insert(goal.rawValue)
        persist()
        // Let the user know they just checked one off, with the running tally.
        let count = completed.count
        NotificationCenter.default.post(name: .mtrxDailyFlowProgress, object: nil, userInfo: [
            "label": goal.label,
            "count": count,
            "complete": count >= Goal.allCases.count
        ])
    }

    var progress: Double {
        Double(completed.count) / Double(Goal.allCases.count)
    }

    var isComplete: Bool { completed.count >= Goal.allCases.count }

    private func reload() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: storageKey + ".day") != todayKey {
            completed = []
            persist()
        } else {
            completed = Set(defaults.stringArray(forKey: storageKey + ".done") ?? [])
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(todayKey, forKey: storageKey + ".day")
        defaults.set(Array(completed), forKey: storageKey + ".done")
    }
}

// MARK: - Portfolio Sheet (the bank inside the app)

/// The portfolio opens like a banking app: balance up top, a row of
/// money moves, holdings, and recent activity — and every move (pay,
/// swap, stake, earn, invest) happens right here, never leaving it.
struct PortfolioSheet: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var activeMove: PortfolioMove?

    enum PortfolioMove: String, Identifiable, Hashable {
        case pay, swap, stake, earn, invest
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        balanceHeader
                        moveRow
                        holdingsSection
                        activitySection
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
            .navigationDestination(item: $activeMove) { move in
                switch move {
                case .pay:
                    MoneyMoveForm(mode: .pay) { activeMove = nil }
                case .swap:
                    MoneyMoveForm(mode: .swap) { activeMove = nil }
                case .stake:
                    MoneyMoveForm(mode: .stake) { activeMove = nil }
                case .earn:
                    YieldView()
                case .invest:
                    TradingView()
                }
            }
        }
    }

    // The number that matters, stated calmly.
    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Total balance")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(
                    walletManager.totalPortfolioValue,
                    format: .currency(code: "USD").precision(.fractionLength(2))
                )
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.labelPrimary)

                HStack(spacing: 3) {
                    Image(systemName: walletManager.portfolioChange24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%.2f%%", abs(walletManager.portfolioChange24h)))
                        .font(.mtrxCaptionBold)
                }
                .foregroundStyle(walletManager.portfolioChange24h >= 0 ? Color.statusSuccess : Color.statusError)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((walletManager.portfolioChange24h >= 0 ? Color.statusSuccess : Color.statusError).opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .padding(.top, Spacing.sm)
    }

    // The banking-app row: five round doors, evenly spread.
    private var moveRow: some View {
        HStack(spacing: 0) {
            moveButton(.pay, "Pay", icon: "arrow.up", color: .accentPrimary)
            moveButton(.swap, "Swap", icon: "arrow.triangle.2.circlepath", color: .trinityPrimary)
            moveButton(.stake, "Stake", icon: "lock.fill", color: .statusSuccess)
            moveButton(.earn, "Earn", icon: "percent", color: .purple)
            moveButton(.invest, "Invest", icon: "chart.line.uptrend.xyaxis", color: .statusInfo)
        }
    }

    private func moveButton(_ move: PortfolioMove, _ title: String, icon: String, color: Color) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            activeMove = move
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 54, height: 54)
                    .background(.ultraThinMaterial)
                    .background(color.opacity(0.10))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(color.opacity(0.30), lineWidth: 1))

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Holdings")
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)

            VStack(spacing: Spacing.xs) {
                ForEach(walletManager.tokens.filter { $0.balance > 0 }, id: \.symbol) { token in
                    HStack(spacing: Spacing.ms) {
                        Text(String(token.symbol.prefix(1)))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.trinityPrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.trinityPrimary.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.symbol)
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelPrimary)
                            Text(String(format: "%.4f", token.balance))
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                        }

                        Spacer()

                        Text(token.balance * token.priceUSD, format: .currency(code: "USD").precision(.fractionLength(2)))
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    .padding(Spacing.ms)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent activity")
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)

            if walletManager.transactions.isEmpty {
                Text("Your moves will show up here.")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
                    .padding(.vertical, Spacing.sm)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(walletManager.transactions.prefix(5)) { tx in
                        HStack(spacing: Spacing.ms) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.title)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.labelPrimary)
                                Text(tx.subtitle)
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(tx.amount)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(tx.amount.hasPrefix("+") ? Color.statusSuccess : Color.labelPrimary)
                                Text(tx.timestamp, style: .time)
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelQuaternary)
                            }
                        }
                        .padding(Spacing.ms)
                        .background(Color.surfaceOverlay.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                    }
                }
            }
        }
    }
}

// MARK: - Money Move Form

/// One clean form for pay / swap / stake — amount, the few details the
/// move needs, one confirm button, and a success beat. All in-place.
struct MoneyMoveForm: View {
    enum Mode { case pay, swap, stake }

    let mode: Mode
    let onDone: () -> Void

    @EnvironmentObject var walletManager: WalletManager
    @State private var amountText = ""
    @State private var recipient = ""
    @State private var fromToken = "ETH"
    @State private var toToken = "USDC"
    @State private var stakeToken = "ETH"
    @State private var errorMessage: String?
    @State private var succeeded = false
    @FocusState private var amountFocused: Bool

    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .primary)

            if succeeded {
                successView
            } else {
                formView
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { amountFocused = true }
    }

    private var title: String {
        switch mode {
        case .pay: return "Send money"
        case .swap: return "Swap"
        case .stake: return "Stake"
        }
    }

    private var formView: some View {
        VStack(spacing: Spacing.lg) {
            // The amount is the hero — big, centered, focused.
            VStack(spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if mode == .pay { Text("$").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Color.labelSecondary) }
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.labelPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                    if mode != .pay {
                        Text(mode == .swap ? fromToken : stakeToken)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                Text(availableLine)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.xl)

            // The few details the move actually needs.
            VStack(spacing: Spacing.sm) {
                switch mode {
                case .pay:
                    TextField("To — name, @handle, or address", text: $recipient)
                        .font(.mtrxBody)
                        .padding(Spacing.ms)
                        .background(Color.surfaceOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                case .swap:
                    tokenPicker("From", selection: $fromToken)
                    tokenPicker("To", selection: $toToken)
                case .stake:
                    tokenPicker("Token", selection: $stakeToken)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            if let errorMessage {
                Text(errorMessage)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.statusError)
            }

            Spacer()

            Button {
                confirm()
            } label: {
                Text(confirmLabel)
                    .font(.mtrxCalloutBold)
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(canConfirm ? Color.accentPrimary : Color.labelQuaternary)
                    .clipShape(Capsule())
            }
            .disabled(!canConfirm)
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    private var successView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.statusSuccess)
                .symbolRenderingMode(.hierarchical)

            Text(successLine)
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .multilineTextAlignment(.center)

            Text("Reflected in your balance instantly.")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
        }
        .padding(Spacing.contentPadding)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private var availableLine: String {
        switch mode {
        case .pay:
            let cash = walletManager.tokens.first { $0.symbol == "USDC" }?.balance ?? 0
            return String(format: "Cash available: $%.2f", cash)
        case .swap:
            let bal = walletManager.tokens.first { $0.symbol == fromToken }?.balance ?? 0
            return String(format: "Available: %.4f %@", bal, fromToken)
        case .stake:
            let bal = walletManager.tokens.first { $0.symbol == stakeToken }?.balance ?? 0
            return String(format: "Available: %.4f %@ · 8.7%% APY", bal, stakeToken)
        }
    }

    private var confirmLabel: String {
        switch mode {
        case .pay: return "Send"
        case .swap: return "Swap \(fromToken) → \(toToken)"
        case .stake: return "Stake \(stakeToken)"
        }
    }

    private var successLine: String {
        switch mode {
        case .pay: return "Sent $\(amountText) to \(recipient)"
        case .swap: return "Swapped \(amountText) \(fromToken) → \(toToken)"
        case .stake: return "Staked \(amountText) \(stakeToken)"
        }
    }

    private var canConfirm: Bool {
        guard let amount = Double(amountText), amount > 0 else { return false }
        if mode == .pay && recipient.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if mode == .swap && fromToken == toToken { return false }
        return true
    }

    private func confirm() {
        guard let amount = Double(amountText) else { return }
        amountFocused = false
        let ok: Bool
        switch mode {
        case .pay:
            ok = walletManager.demoSendFiat(amount: amount, currency: "USD", recipient: recipient)
        case .swap:
            ok = walletManager.demoSwap(amount: amount, from: fromToken, to: toToken) != nil
        case .stake:
            ok = walletManager.demoStake(amount: amount, tokenSymbol: stakeToken)
        }
        if ok {
            MtrxHaptics.success()
            withAnimation(Motion.springDefault) { succeeded = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { onDone() }
        } else {
            MtrxHaptics.error()
            withAnimation(Motion.springSnappy) {
                errorMessage = "Not enough balance for that move."
            }
        }
    }

    private func tokenPicker(_ label: String, selection: Binding<String>) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(label)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 44, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(walletManager.tokens.filter { $0.balance > 0 || $0.symbol == selection.wrappedValue }, id: \.symbol) { token in
                        Button {
                            MtrxHaptics.selection()
                            selection.wrappedValue = token.symbol
                        } label: {
                            Text(token.symbol)
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(selection.wrappedValue == token.symbol ? Color.backgroundPrimary : Color.labelPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selection.wrappedValue == token.symbol ? Color.accentPrimary : Color.surfaceOverlay)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Spacing.ms)
        .background(Color.surfaceOverlay.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Tab Switching

// MARK: - Inline Home Chat Message

struct HomeChatMsg: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

// MARK: - Quick Action Drag-to-Reorder

/// Applied to each quick-action tile: in edit mode it becomes draggable and
/// a drop target so the six tiles can be rearranged into any order.
struct QuickActionDragReorder: ViewModifier {
    let action: HomeAction
    let enabled: Bool
    let current: [HomeAction]
    @Binding var dragging: HomeAction?
    let commit: ([HomeAction]) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    dragging = action
                    return NSItemProvider(object: action.rawValue as NSString)
                }
                .onDrop(of: [.plainText], delegate: QuickActionDropDelegate(
                    item: action, current: current, dragging: $dragging, commit: commit
                ))
        } else {
            content
        }
    }
}

struct QuickActionDropDelegate: DropDelegate {
    let item: HomeAction
    let current: [HomeAction]
    @Binding var dragging: HomeAction?
    let commit: ([HomeAction]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = current.firstIndex(of: dragging),
              let to = current.firstIndex(of: item) else { return }
        var updated = current
        updated.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { commit(updated) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        MtrxHaptics.impact(.light)
        return true
    }
}

extension Notification.Name {
    /// Posted with userInfo ["index": Int] to switch the root tab bar.
    static let mtrxSwitchTab = Notification.Name("com.mtrx.switchTab")
    /// Posted with userInfo ["service": String] to open a Home service.
    static let mtrxOpenService = Notification.Name("com.mtrx.openService")
    /// Posted with userInfo ["index": Int] when the user taps the dock tab
    /// they're already on — each tab resets to its initial page.
    static let mtrxPopToRoot = Notification.Name("com.mtrx.popToRoot")
    /// Posted with ["label": String, "count": Int, "complete": Bool] each time
    /// the user checks off one of the three daily-flow actions.
    static let mtrxDailyFlowProgress = Notification.Name("com.mtrx.dailyFlowProgress")
    /// Posted with ["id": String] to jump the Social feed to a specific post
    /// (e.g. tapping a card in the Home feed carousel).
    static let mtrxOpenPost = Notification.Name("com.mtrx.openPost")
}

// MARK: - Daily Flow Sheet

/// The ring, opened up: shows the three goals of the day, which are
/// done, and jumps straight into whichever one is still open.
struct DailyFlowSheet: View {
    @ObservedObject private var dailyFlow = DailyFlow.shared
    @Environment(\.dismiss) private var dismiss

    let onAgent: () -> Void
    let onSocial: () -> Void
    let onExplore: () -> Void

    private var accent: Color { dailyFlow.isComplete ? .statusSuccess : .trinityPrimary }

    var body: some View {
        ZStack {
            // The app's black field with a soft accent aura rising behind
            // the hero ring.
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [accent.opacity(0.22), .clear],
                center: .init(x: 0.5, y: 0.30),
                startRadius: 4, endRadius: 360
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Hero ring — large, with a gradient stroke that glows.
                    VStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .stroke(accent.opacity(0.14), lineWidth: 11)
                                .frame(width: 132, height: 132)
                            Circle()
                                .trim(from: 0, to: max(dailyFlow.progress, 0.04))
                                .stroke(
                                    AngularGradient(
                                        colors: [accent, accent.opacity(0.55), accent],
                                        center: .center
                                    ),
                                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 132, height: 132)
                                .shadow(color: accent.opacity(0.5), radius: 12)
                                .animation(Motion.springDefault, value: dailyFlow.progress)

                            VStack(spacing: 2) {
                                if dailyFlow.isComplete {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 38, weight: .bold))
                                        .foregroundStyle(Color.statusSuccess)
                                } else {
                                    Text("\(dailyFlow.completed.count)")
                                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Color.labelPrimary)
                                    + Text(" / 3")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.labelTertiary)
                                }
                            }
                        }
                        .padding(.top, Spacing.lg)

                        Text(dailyFlow.isComplete ? "In flow" : "Daily Flow")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.labelPrimary)

                        Text(dailyFlow.isComplete
                             ? "All three done — beautifully done."
                             : "Three small moves a day keep everything in motion.")
                            .font(.mtrxBody)
                            .foregroundStyle(Color.labelSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                    }

                    // Goal cards — glass, spacious, app-consistent.
                    VStack(spacing: Spacing.md) {
                        goalCard(.agent, icon: "bubble.left.and.bubble.right.fill",
                                 subtitle: "Ask Trinity anything", action: onAgent)
                        goalCard(.social, icon: "globe",
                                 subtitle: "See what your world is up to", action: onSocial)
                        goalCard(.explore, icon: "safari.fill",
                                 subtitle: "Discover something new", action: onExplore)
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    Text("Resets at midnight")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                        .padding(.bottom, Spacing.xl)
                }
            }
        }
    }

    private func goalCard(_ goal: DailyFlow.Goal, icon: String, subtitle: String, action: @escaping () -> Void) -> some View {
        let done = dailyFlow.completed.contains(goal.rawValue)
        let tint: Color = done ? .statusSuccess : .trinityPrimary
        return Button {
            MtrxHaptics.impact(.light)
            action()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.label)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text(done ? "Done for today" : subtitle)
                        .font(.mtrxCaption1)
                        .foregroundStyle(done ? Color.statusSuccess : Color.labelSecondary)
                }

                Spacer()

                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.statusSuccess)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.lg)
            .opacity(done ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }
}

/// A jiggle that is *guaranteed* to stop: the sway is driven by a
/// TimelineView that only exists while `active`. The moment edit mode ends
/// the rotation source is gone entirely, so the tiles settle flat — no
/// lingering repeatForever animation.
private struct JiggleEffect: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                content.rotationEffect(.degrees(sin(t * 6.3) * 0.8))
            }
        } else {
            content
        }
    }
}


