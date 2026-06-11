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

    /// What to open the chat with: an agent and an optional prefill.
    struct ChatLaunch: Identifiable {
        let id = UUID()
        let agent: AgentAccessControl.ActiveAgent
        var prompt: String?
    }

    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .trinityGlow)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    greetingHeader
                        .mtrxStaggeredAppearance(index: 0, isVisible: appeared)

                    portfolioSnapshot
                        .mtrxStaggeredAppearance(index: 1, isVisible: appeared)

                    agentOrbSection
                        .mtrxStaggeredAppearance(index: 2, isVisible: appeared)

                    quickActionsSection
                        .mtrxStaggeredAppearance(index: 3, isVisible: appeared)

                    servicesSection
                        .mtrxStaggeredAppearance(index: 4, isVisible: appeared)
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, 96)
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
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(timeGreeting)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.trinityPrimary.opacity(0.85))
                .textCase(.uppercase)
                .kerning(1.6)

            HStack(spacing: Spacing.sm) {
                Text(firstName)
                    .font(.mtrxLargeTitle)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.labelPrimary, Color.trinityPrimary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Button {
                    nameDraft = appState.displayName
                    showNameEditor = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)

                Spacer()

                // A real open loop: fills as the day is actually
                // lived — agent, social, exploration — and resets at
                // midnight. Unfinished loops pull people back.
                VStack(spacing: 2) {
                    ZStack {
                        MtrxProgressRing(
                            progress: max(dailyFlow.progress, 0.04),
                            size: 38,
                            lineWidth: 4,
                            color: dailyFlow.isComplete ? .statusSuccess : .trinityPrimary,
                            showLabel: false
                        )
                        if dailyFlow.isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.statusSuccess)
                        } else {
                            Text("\(dailyFlow.completed.count)/3")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.labelPrimary)
                        }
                    }
                    .mtrxGlow(color: dailyFlow.isComplete ? .statusSuccess : .clear, radius: 5)

                    Text(dailyFlow.isComplete ? "In flow" : "Daily flow")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(dailyFlow.isComplete ? Color.statusSuccess : Color.labelTertiary)
                }
            }
            .alert("Your Name", isPresented: $showNameEditor) {
                TextField("Name", text: $nameDraft)
                Button("Save") { appState.updateDisplayName(nameDraft) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Shown in your greeting and on your posts.")
            }

            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelTertiary)

            // A calm, reassuring beat before any numbers — people stay
            // where they feel things are under control.
            Text(reassuranceLine)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.trinityPrimary.opacity(0.75))
                .padding(.top, 2)
        }
        .padding(.top, Spacing.md)
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

    // MARK: - Agents (the orb gateway)

    /// One tap into the agent space — a glowing 3D orb, in the spirit
    /// of Apple's Siri light. Opens straight into Trinity; Morpheus and
    /// Neo are one bubble away inside.
    @State private var orbPulse = false

    private var agentOrbSection: some View {
        Button {
            MtrxHaptics.impact(.medium)
            presentedChat = ChatLaunch(agent: .trinity)
        } label: {
            HStack(spacing: Spacing.md) {
                // Layered gradient sphere with breathing glow.
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.trinityPrimary, .purple, .statusError, .orange, .statusSuccess, .trinityPrimary],
                                center: .center
                            )
                        )
                        .frame(width: 64, height: 64)
                        .blur(radius: 10)
                        .opacity(orbPulse ? 0.95 : 0.55)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.95), .trinityPrimary, .trinitySecondary.opacity(0.8)],
                                center: .init(x: 0.35, y: 0.3),
                                startRadius: 2,
                                endRadius: 36
                            )
                        )
                        .frame(width: 54, height: 54)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.35), lineWidth: 1)
                        )
                        .scaleEffect(orbPulse ? 1.04 : 0.97)
                }
                .drawingGroup()
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                        orbPulse = true
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Agents")
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)

                    Text(agentOrbSubtitle)
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.trinityPrimary.opacity(0.8))
            }
            .padding(Spacing.ms)
            .background(.ultraThinMaterial)
            .background(Color.trinityPrimary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.trinityPrimary.opacity(0.5), Color.purple.opacity(0.2), Color.trinityPrimary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.trinityPrimary.opacity(0.12), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var agentOrbSubtitle: String {
        if let preview = lastMessagePreview(for: .trinity) {
            return preview
        }
        let owner = AgentAccessControl.shared.userType(for: appState.currentUserID) == .owner
        return owner ? "Trinity · Morpheus · Neo" : "Trinity · Morpheus"
    }

    private func lastMessagePreview(for agent: AgentAccessControl.ActiveAgent) -> String? {
        guard let last = chatStore.mostRecent(agent: agent)?.messages.last else { return nil }
        let prefix = last.role == .user ? "You: " : ""
        let flattened = last.text.replacingOccurrences(of: "\n", with: " ")
        return prefix + flattened
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.ms) {
            sectionTitle("Quick actions")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.ms) {
                quickAction("Send Money", icon: "arrow.up.circle.fill", color: .accentPrimary, prompt: "Send $")
                quickAction("Swap", icon: "arrow.triangle.2.circlepath.circle.fill", color: .trinityPrimary, prompt: "Swap 1 ETH to USDC")
                quickAction("Stake", icon: "lock.circle.fill", color: .statusSuccess, prompt: "Stake 0.5 ETH")
                quickAction("Deploy Contract", icon: "doc.badge.gearshape.fill", color: .accentTertiary, prompt: "Deploy a smart contract called ")
                quickAction("Check Balance", icon: "chart.pie.fill", color: .statusInfo, prompt: "What's my balance?")
                quickAction("Market Check", icon: "chart.line.uptrend.xyaxis.circle.fill", color: .trinitySecondary, prompt: "What's bitcoin at right now?")
            }
        }
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
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
            .padding(Spacing.ms)
            .frame(maxWidth: .infinity, minHeight: 58)
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
    }

    // MARK: - Services (the super-app layer)

    /// One life, one app: every MTRX service is a tap from Home —
    /// pay, invest, shop, insure, play, meet, store — no other apps
    /// needed through the day.
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.ms) {
            sectionTitle("Services")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(HomeService.allCases) { service in
                        Button {
                            MtrxHaptics.impact(.light)
                            presentedService = service
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: service.icon)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(service.color)
                                    .frame(width: 52, height: 52)
                                    .background(.ultraThinMaterial)
                                    .background(service.color.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(service.color.opacity(0.25), lineWidth: 1)
                                    )

                                Text(service.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.labelSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
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
