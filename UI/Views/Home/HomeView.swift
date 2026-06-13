// HomeView.swift
// MTRX — Home tab.
//
// The welcome screen: greets the user, puts their agents one tap away,
// and surfaces the most-used actions immediately. Chats open full-screen
// over the dashboard and slide back down to it.

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var chatStore = ConversationStore.shared
    @ObservedObject private var dailyFlow = DailyFlow.shared
    @ObservedObject private var socialFeed = SocialViewModel.shared
    @State private var feedPage = 0

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
                VStack(alignment: .leading, spacing: Spacing.md) {
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
                .padding(.bottom, 96)
                // In edit mode, tapping empty space exits jiggle — no need
                // to reach for Done.
                .background {
                    if editingActions {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { exitEditMode() }
                    }
                }
            }
            // Swipe down on the page to dismiss the keyboard when done.
            .scrollDismissesKeyboard(.interactively)
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
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
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
            Text("\(timeGreeting) · \(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))")
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

                // The ask bar and the orb are one element now: a single
                // glass pill — wearing the orb's own iridescent skin —
                // with the orb living at its trailing end. Type to Trinity.
                homeAskOrb
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
            .offset(x: -60, y: -70),
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

    /// The Home ask bar — type a command or talk to Trinity.
    @State private var askText = ""
    @FocusState private var askFocused: Bool

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
            TextField("What are we doing today", text: $askText)
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
        .shadow(color: Color(red: 0.62, green: 0.78, blue: 0.98).opacity(askFocused ? 0.45 : 0.0),
                radius: askFocused ? 18 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: askFocused)
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

    private func runHomeAsk() {
        let text = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        askFocused = false
        askText = ""
        presentedChat = ChatLaunch(agent: .trinity, prompt: text)
    }


    // MARK: - Quick Actions (editable, jiggle-mode)

    /// The user's chosen quick actions, persisted and reorderable. Long-
    /// press any tile (or tap Edit) to enter jiggle mode: remove with the
    /// red badge, add from the picker. Their home screen, their choices.
    @AppStorage("com.mtrx.home.quickActions") private var quickActionsRaw =
        "deploy,shop,insure,play,events,identity"
    @State private var editingActions = false
    @State private var jiggle = false
    @State private var showActionPicker = false

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
            withAnimation(.easeInOut(duration: 0.25)) { jiggle = false }
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
        .rotationEffect(.degrees(editingActions ? (jiggle ? 0.7 : -0.7) : 0))
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
        .rotationEffect(.degrees(jiggle ? 0.7 : -0.7))
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
                // Looping carousel: a clone of the last post sits before
                // the first and a clone of the first sits after the last,
                // so swiping past either end wraps seamlessly both ways.
                TabView(selection: $feedPage) {
                    ForEach(loopFeed.indices, id: \.self) { i in
                        feedCard(loopFeed[i])
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 204)
                .onAppear {
                    if feedPosts.count > 1 && feedPage == 0 { feedPage = 1 }
                }
                .onChange(of: feedPage) { _, new in
                    let n = feedPosts.count
                    guard n > 1 else { return }
                    if new == 0 { jumpFeed(to: n) }          // before first → real last
                    else if new == n + 1 { jumpFeed(to: 1) } // after last → real first
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
                .offset(y: -5)
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
        return ((feedPage - 1) % n + n) % n
    }

    private func jumpFeed(to index: Int) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { feedPage = index }
    }

    private func feedCard(_ post: SocialPostDisplay) -> some View {
        PostCardView(
            post: post,
            onLike: { socialFeed.toggleLike(postId: post.id) },
            onRepost: { socialFeed.toggleRepost(postId: post.id) }
        )
        .lineLimit(3)
        .padding(Spacing.ms)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

extension Notification.Name {
    /// Posted with userInfo ["index": Int] to switch the root tab bar.
    static let mtrxSwitchTab = Notification.Name("com.mtrx.switchTab")
    /// Posted with userInfo ["service": String] to open a Home service.
    static let mtrxOpenService = Notification.Name("com.mtrx.openService")
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

    var body: some View {
        VStack(spacing: Spacing.ml) {
            // The ring, large and honest.
            VStack(spacing: Spacing.sm) {
                ZStack {
                    MtrxProgressRing(
                        progress: max(dailyFlow.progress, 0.04),
                        size: 72,
                        lineWidth: 7,
                        color: dailyFlow.isComplete ? .statusSuccess : .trinityPrimary,
                        showLabel: false
                    )
                    if dailyFlow.isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.statusSuccess)
                    } else {
                        Text("\(dailyFlow.completed.count)/3")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
                .mtrxGlow(color: dailyFlow.isComplete ? .statusSuccess : .trinityPrimary.opacity(0.5), radius: 8)

                Text(dailyFlow.isComplete ? "In flow" : "Daily flow")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)

                Text(dailyFlow.isComplete
                     ? "All three done for today."
                     : "Three small moves a day keep everything in motion.")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Spacing.lg)

            VStack(spacing: Spacing.sm) {
                goalRow(.agent, icon: "bubble.left.and.bubble.right.fill", action: onAgent)
                goalRow(.social, icon: "globe", action: onSocial)
                goalRow(.explore, icon: "safari.fill", action: onExplore)
            }
            .padding(.horizontal, Spacing.contentPadding)

            Text("Resets at midnight")
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelTertiary)

            Spacer(minLength: 0)
        }
    }

    private func goalRow(_ goal: DailyFlow.Goal, icon: String, action: @escaping () -> Void) -> some View {
        let done = dailyFlow.completed.contains(goal.rawValue)
        return Button {
            MtrxHaptics.impact(.light)
            action()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(done ? Color.statusSuccess : Color.trinityPrimary)
                    .frame(width: 36, height: 36)
                    .background((done ? Color.statusSuccess : Color.trinityPrimary).opacity(0.12))
                    .clipShape(Circle())

                Text(goal.label)
                    .font(.mtrxCalloutBold)
                    .foregroundStyle(Color.labelPrimary)

                Spacer()

                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.statusSuccess)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
            }
            .padding(Spacing.ms)
            .background(Color.surfaceOverlay.opacity(done ? 0.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
