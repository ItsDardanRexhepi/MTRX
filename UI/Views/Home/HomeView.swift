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

    @State private var presentedChat: ChatLaunch?
    @State private var appeared = false
    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var askedForName = false
    @State private var presentedService: HomeService?
    @State private var showDailyFlow = false
    @State private var flowDestination: DailyFlow.Goal?
    @State private var showPortfolio = false
    @State private var portfolioPrompt: String?

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
                VStack(alignment: .leading, spacing: Spacing.ml) {
                    greetingHeader
                        .mtrxStaggeredAppearance(index: 0, isVisible: appeared)

                    portfolioSnapshot
                        .mtrxStaggeredAppearance(index: 1, isVisible: appeared)

                    quickActionsSection
                        .mtrxStaggeredAppearance(index: 2, isVisible: appeared)
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, 96)
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
        .sheet(isPresented: $showPortfolio, onDismiss: {
            // Money moves open the agent chat — but only after the
            // sheet has fully closed, so presentations never collide.
            if let prompt = portfolioPrompt {
                portfolioPrompt = nil
                presentedChat = ChatLaunch(agent: .trinity, prompt: prompt)
            }
        }) {
            PortfolioActionsSheet { prompt in
                portfolioPrompt = prompt
                showPortfolio = false
            }
            .environmentObject(walletManager)
            .presentationDetents([.height(540), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Greeting and date share one eyebrow line — the dashboard
            // below needs the vertical room more than the calendar does.
            Text("\(timeGreeting) · \(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.trinityPrimary.opacity(0.85))
                .textCase(.uppercase)
                .kerning(1.2)

            HStack(spacing: Spacing.sm) {
                // The name edits itself — tap it, no pencil needed.
                Text(firstName)
                    .font(.mtrxLargeTitle)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.labelPrimary, Color.trinityPrimary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .onTapGesture {
                        MtrxHaptics.impact(.light)
                        nameDraft = appState.displayName
                        showNameEditor = true
                    }

                // Daily flow lives where the pencil was — a real open
                // loop that fills as the day is lived. Tap for the goals.
                Button {
                    MtrxHaptics.impact(.light)
                    showDailyFlow = true
                } label: {
                    ZStack {
                        MtrxProgressRing(
                            progress: max(dailyFlow.progress, 0.04),
                            size: 34,
                            lineWidth: 3.5,
                            color: dailyFlow.isComplete ? .statusSuccess : .trinityPrimary,
                            showLabel: false
                        )
                        if dailyFlow.isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.statusSuccess)
                        } else {
                            Text("\(dailyFlow.completed.count)/3")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.labelPrimary)
                        }
                    }
                    .mtrxGlow(color: dailyFlow.isComplete ? .statusSuccess : .clear, radius: 5)
                }
                .buttonStyle(.plain)

                Spacer()

                // The agent orb, top right — one tap into the agent space.
                Button {
                    MtrxHaptics.impact(.medium)
                    presentedChat = ChatLaunch(agent: .trinity)
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.trinityPrimary, .purple, .statusError, .orange, .statusSuccess, .trinityPrimary],
                                    center: .center
                                )
                            )
                            .frame(width: 62, height: 62)
                            .mask(
                                RadialGradient(
                                    colors: [.white, .white.opacity(0)],
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: 31
                                )
                            )
                            .opacity(orbPulse ? 0.95 : 0.55)

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white.opacity(0.95), .trinityPrimary, .trinitySecondary.opacity(0.8)],
                                    center: .init(x: 0.35, y: 0.3),
                                    startRadius: 2,
                                    endRadius: 30
                                )
                            )
                            .frame(width: 46, height: 46)
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                            .scaleEffect(orbPulse ? 1.04 : 0.97)
                    }
                    .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                        orbPulse = true
                    }
                }
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

    /// Drives the breathing of the header orb.
    @State private var orbPulse = false

    // MARK: - Quick Actions

    /// The services ARE the quick actions now: money moves live inside
    /// the tappable Portfolio card, markets live at the top of Invest,
    /// and everything else in the app is one tap from here.
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.ms) {
            sectionTitle("Quick actions")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
                quickAction("Deploy Contract", icon: "doc.badge.gearshape.fill", color: .accentTertiary, prompt: "Deploy a smart contract called ")
                ForEach(HomeService.allCases) { service in
                    serviceAction(service)
                }
            }
        }
    }

    private func serviceAction(_ service: HomeService) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            presentedService = service
        } label: {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(service.color.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: service.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(service.color)
                }

                Text(service.title)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.ms)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.ultraThinMaterial)
            .background(service.color.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                    .stroke(service.color.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func quickAction(_ title: String, icon: String, color: Color, prompt: String) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            presentedChat = ChatLaunch(agent: .trinity, prompt: prompt)
        } label: {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.ms)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.ultraThinMaterial)
            .background(color.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
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
            .padding(Spacing.md)
            .background(.ultraThinMaterial)
            .background(Color.trinityPrimary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
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

// MARK: - Portfolio Actions Sheet

/// The portfolio, opened up: full holdings plus the money moves —
/// send, swap, stake — one tap each, straight into the agent.
struct PortfolioActionsSheet: View {
    @EnvironmentObject var walletManager: WalletManager
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.ml) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Portfolio")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)

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
            }

            VStack(spacing: Spacing.xs) {
                ForEach(walletManager.tokens.filter { $0.balance > 0 }, id: \.symbol) { token in
                    HStack {
                        Text(token.symbol)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text(String(format: "%.4f", token.balance))
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, Spacing.ms)
                    .background(Color.surfaceOverlay.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.xs, style: .continuous))
                }
            }

            VStack(spacing: Spacing.sm) {
                portfolioMove("Send Money", icon: "arrow.up.circle.fill", color: .accentPrimary, prompt: "Send $")
                portfolioMove("Swap", icon: "arrow.triangle.2.circlepath.circle.fill", color: .trinityPrimary, prompt: "Swap 1 ETH to USDC")
                portfolioMove("Stake", icon: "lock.circle.fill", color: .statusSuccess, prompt: "Stake 0.5 ETH")
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.contentPadding)
        .padding(.top, Spacing.sm)
    }

    private func portfolioMove(_ title: String, icon: String, color: Color, prompt: String) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            onAction(prompt)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.14))
                    .clipShape(Circle())

                Text(title)
                    .font(.mtrxCalloutBold)
                    .foregroundStyle(Color.labelPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.labelTertiary)
            }
            .padding(Spacing.ms)
            .background(Color.surfaceOverlay)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
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
                     ? "All three done — you lived the whole day in one app."
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
