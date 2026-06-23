// MTRXApp.swift
// MTRX
//
// App entry point — launch screen, authentication gate, five-tab navigation.

import SwiftUI

// MARK: - App Entry Point

@main
struct MTRXApp: App {

    // MARK: - App Delegate Adapter

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - State

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @StateObject private var walletManager = WalletManager()
    @StateObject private var trinityEngine = TrinityEngine()
    @ObservedObject private var agentAccessControl = AgentAccessControl.shared
    @ObservedObject private var morpheusInterventions = MorpheusInterventions.shared

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(walletManager)
                .environmentObject(trinityEngine)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }

        switch components.host {
        case "marketplace":
            appState.navigate(to: .marketplace(id: components.queryItems?.first(where: { $0.name == "id" })?.value))
        case "contract":
            appState.navigate(to: .contract(id: components.queryItems?.first(where: { $0.name == "id" })?.value))
        case "fundraiser":
            appState.navigate(to: .fundraiser(id: components.queryItems?.first(where: { $0.name == "id" })?.value))
        case "wallet":
            appState.navigate(to: .wallet)
        default:
            break
        }
    }

    // MARK: - Scene Phase Handling

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            appState.refreshOnForeground()
            walletManager.reconnectIfNeeded()
        case .inactive:
            appState.prepareForBackground()
        case .background:
            appState.scheduleBackgroundTasks()
            walletManager.persistState()
            // Stop any in-flight game screen recording on backgrounding so the
            // recorder + timer don't outlive a visible game.
            Task { await ReplayKitManager.shared.cancelIfRecording() }
        @unknown default:
            break
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock = AppLock.shared
    @State private var showLaunch = true
    // Auto-present Face ID only on launch and on return-from-background — NOT on
    // every .active, since dismissing the Face ID sheet itself returns the app to
    // .active and would otherwise re-prompt in a loop (and block the lock
    // screen's manual retry). Re-armed when we genuinely background.
    @State private var armedForAuth = true

    /// True while content must stay hidden behind the portal: a signed-in
    /// session with the lock enabled and not yet unlocked.
    private var portalLocked: Bool {
        appState.isAuthenticated && appLock.isEnabled && appLock.isLocked
    }

    var body: some View {
        ZStack {
            Group {
                if appState.isAuthenticated {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .animation(Motion.springDefault, value: appState.isAuthenticated)

            // The portal IS the lock surface — there is no separate lock screen.
            // It holds (covering all content) while the app is locked, and the
            // portal→Home dissolve fires ONLY when authentication genuinely
            // succeeds (appLock.isLocked → false in authenticate()'s success
            // branch). A failed/cancelled scan leaves the portal in place; a tap
            // on the orb re-presents Face ID. There is no path past it without a
            // real success.
            if showLaunch {
                LaunchView(
                    ready: !portalLocked,
                    onRetry: { Task { await appLock.authenticate() } },
                    lockHint: (portalLocked && appLock.lastError != nil && !appLock.isAuthenticating)
                        ? "Tap to unlock" : nil
                ) {
                    showLaunch = false
                }
                .zIndex(30)
            }
        }
        // Probe the gateway on launch so the app knows whether the backend is
        // live (updates the API client's networkStatus; demo data until then).
        .task { _ = await MTRXAPIClient.shared.checkHealth() }
        // Whenever the lock engages (background re-lock, or re-enabling it in
        // Settings while in the foreground), bring the portal back; if we're
        // already active (foreground re-enable), present Face ID right away.
        .onChange(of: appLock.isLocked) { _, locked in
            if locked {
                showLaunch = true
                if scenePhase == .active { Task { await appLock.authenticate() } }
            }
        }
        // A new authenticated session (sign-out → sign-in) starts locked behind
        // the portal; we're already .active here, so trigger Face ID directly.
        .onChange(of: appState.isAuthenticated) { _, authed in
            guard authed, appLock.isEnabled else { return }
            appLock.lock()
            showLaunch = true
            Task { await appLock.authenticate() }
        }
        // Present Face ID only once the scene is actually .active — the fix for
        // the old launch-time hang (presenting during the launch/scene transition
        // got the prompt cancelled by the system). Re-lock + bring the portal
        // back on background; .inactive is transient (the Face ID sheet itself,
        // Control Center) so we deliberately do NOT lock on it.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard appState.isAuthenticated, appLock.isEnabled else { return }
            switch phase {
            case .active:
                // Auto-present only on launch / return-from-background. A failed
                // or cancelled scan rests on the portal with its tap-to-retry
                // rather than immediately re-prompting in a loop.
                if appLock.isLocked && armedForAuth {
                    armedForAuth = false
                    Task { await appLock.authenticate() }
                }
            case .background:
                appLock.lock()
                armedForAuth = true
                showLaunch = true   // a returning app shows portal → Face ID
            default:
                break
            }
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var walletManager: WalletManager
    @State private var selectedTab: AppTab = .home
    @ObservedObject private var presence = AgentPresence.shared
    @State private var miniAgent: AgentReopen?
    @State private var expandedAgent: AgentReopen?
    @State private var dailyFlowToast: String?
    @State private var dailyFlowToastComplete = false

    /// Tapping the tab you're already on resets that tab to its initial
    /// page (NavigationStacks pop automatically; sub-tab state resets via
    /// the broadcast).
    private var tabBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    NotificationCenter.default.post(name: .mtrxPopToRoot, object: nil,
                                                    userInfo: ["index": newValue.rawValue])
                } else {
                    selectedTab = newValue
                }
            }
        )
    }

    var body: some View {
        TabView(selection: tabBinding) {
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: Symbols.discover)
                }
                .tag(AppTab.discover)

            BuildView()
                .tabItem {
                    Label("Build", systemImage: Symbols.build)
                }
                .tag(AppTab.build)

            HomeView()
                .tabItem {
                    Label("Home", systemImage: Symbols.home)
                }
                .tag(AppTab.home)

            SocialView()
                .tabItem {
                    Label("Social", systemImage: Symbols.social)
                }
                .tag(AppTab.social)

            AccountView()
                .tabItem {
                    Label("Account", systemImage: Symbols.account)
                }
                .tag(AppTab.account)
        }
        // NOTE: no .animation() on the TabView itself — animating the
        // whole tab container swallows NavigationLink pushes inside
        // tabs. The tint still shifts green→cyan per selected tab.
        .tint(tabTint)
        .task {
            // Warm Trinity's on-device model at launch so the very first chat
            // isn't a cold start. Non-blocking + availability-gated; no-op when
            // Apple Intelligence isn't present. The chat-open prewarm still warms
            // the conversation session, but the expensive shared-model load is
            // already done here.
            FoundationModelsEngine.prewarmAtLaunch()

            // Optimistically restore the last verified tier so FeatureGate
            // honors it from the first frame after a relaunch…
            if let raw = UserDefaults.standard.string(forKey: StoreKitManager.tierDefaultsKey),
               let tier = SubscriptionTier(rawValue: raw) {
                FeatureGate.shared.updateTier(tier)
            }
            // …then verify against StoreKit out-of-band so launch never blocks
            // on the store. Real entitlements are authoritative: this confirms
            // an active subscription/trial or downgrades to free if none.
            Task {
                await StoreKitManager.shared.loadProducts()
                await StoreKitManager.shared.refreshEntitlements()
            }
            // Sync wallet prices to the live feed so every screen and
            // every agent quote agree.
            await walletManager.refreshLivePrices()
            // Overlay the live portfolio from the gateway (falls back to demo).
            await walletManager.loadPortfolio()
            // Mirror whatever the app ended up showing (live or demo) to the
            // Home Screen widgets — covers the demo-fallback path too.
            walletManager.publishWidgetSnapshots()
        }
        .onChange(of: selectedTab) { _, _ in
            MtrxHaptics.selection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mtrxSwitchTab)) { note in
            if let index = note.userInfo?["index"] as? Int,
               let tab = AppTab(rawValue: index) {
                selectedTab = tab
            }
        }
        // A small banner each time a daily-flow action is checked off.
        .onReceive(NotificationCenter.default.publisher(for: .mtrxDailyFlowProgress)) { note in
            guard let label = note.userInfo?["label"] as? String,
                  let count = note.userInfo?["count"] as? Int else { return }
            let complete = (note.userInfo?["complete"] as? Bool) ?? false
            dailyFlowToastComplete = complete
            withAnimation(Motion.springDefault) {
                dailyFlowToast = complete ? "Daily Flow complete — all 3 done! 🎉"
                                          : "\(label) ✓ · \(count)/3 today"
            }
            MtrxHaptics.success()
            let shown = dailyFlowToast
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                if dailyFlowToast == shown {
                    withAnimation(Motion.springDefault) { dailyFlowToast = nil }
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast = dailyFlowToast {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: dailyFlowToastComplete ? "checkmark.seal.fill" : "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(dailyFlowToastComplete ? Color.statusSuccess : Color.trinityPrimary)
                    Text(toast)
                        .font(.mtrxCalloutBold)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(.ultraThinMaterial)
                .background(Color.backgroundPrimary.opacity(0.7))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                .padding(.top, Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        // The docked agent: after she navigates the app for the user she
        // stays as a floating orb — drag her anywhere on screen, tap and
        // the popup chat grows out of the orb itself, and only a swipe
        // fully off the screen sends her away.
        .overlay {
            GeometryReader { geo in
                ZStack {
                    if let launch = miniAgent {
                        // Tap anywhere outside to fold her back into the orb.
                        Color.black.opacity(0.22)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(Motion.springSnappy) { miniAgent = nil }
                            }
                            .transition(.opacity)

                        VStack {
                            Spacer()
                            MiniAgentChat(
                                agent: launch.agent,
                                onExpand: {
                                    miniAgent = nil
                                    expandedAgent = AgentReopen(agent: launch.agent)
                                },
                                onClose: {
                                    withAnimation(Motion.springSnappy) { miniAgent = nil }
                                }
                            )
                            .frame(height: 460)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        }
                        .transition(
                            .scale(scale: 0.06, anchor: popupAnchor(in: geo.size))
                            .combined(with: .opacity)
                        )
                    } else if let agent = presence.docked {
                        FloatingAgentOrb(agent: agent) {
                            withAnimation(Motion.springDefault) {
                                miniAgent = AgentReopen(agent: agent)
                            }
                        }
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(Motion.springDefault, value: presence.docked)
        .fullScreenCover(item: $expandedAgent) { launch in
            AgentConversationView(
                userID: appState.currentUserID,
                initialAgent: launch.agent,
                isModal: true
            )
            .environmentObject(appState)
            .environmentObject(walletManager)
        }
    }
}

// MARK: - Mini Agent Chat (the popup)

/// The popup the orb opens: a quick word with the agent right where
/// you are — last few messages, an input bar, and an expand button if
/// the conversation deserves the full room. The orb stays docked.
struct MiniAgentChat: View {
    let agent: AgentAccessControl.ActiveAgent
    let onExpand: () -> Void
    var onClose: () -> Void = {}

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var walletManager: WalletManager
    @StateObject private var viewModel = AgentConversationViewModel()
    @FocusState private var inputFocused: Bool
    @State private var drift = false

    /// The agent's pastel lead — used for the send button and accents.
    private var tint: Color {
        agentBubblePalette(agent).first ?? .trinityPrimary
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact header — the agent's own little glass orb leads it.
            HStack(spacing: Spacing.sm) {
                GlassOrb(size: 22, tint: agentGlassTint(agent))

                Text(AgentConversationViewModel.displayName(of: agent))
                    .font(.mtrxCalloutBold)
                    .foregroundStyle(Color.labelPrimary)
                Text("online")
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)

                Spacer()

                Button {
                    MtrxHaptics.impact(.light)
                    onExpand()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)

                Button {
                    MtrxHaptics.impact(.light)
                    onClose()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)

            // The last stretch of conversation.
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Spacing.ms) {
                        ForEach(viewModel.messages.suffix(12)) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if viewModel.isTyping {
                            TypingIndicator(agent: viewModel.activeAgent)
                                .id("miniTyping")
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.vertical, Spacing.xs)
                }
                .onChange(of: viewModel.messages.count) {
                    if let last = viewModel.messages.last {
                        withAnimation(Motion.springSnappy) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isTyping) {
                    if viewModel.isTyping {
                        withAnimation(Motion.springSnappy) {
                            proxy.scrollTo("miniTyping", anchor: .bottom)
                        }
                    }
                }
            }

            // Input bar.
            HStack(spacing: Spacing.sm) {
                TextField("Ask \(AgentConversationViewModel.displayName(of: agent))...", text: $viewModel.inputText, axis: .vertical)
                    .font(.mtrxBody)
                    .lineLimit(1...3)
                    .focused($inputFocused)
                    .padding(.horizontal, Spacing.ms)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous))

                Button {
                    MtrxHaptics.impact(.light)
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.labelTertiary
                                : tint
                        )
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
        // The window wears the orb's skin: liquid glass, a film of the
        // agent's pastels around the edge, and a soft glow of light —
        // one continuous material from bubble to chat.
        .background(
            LinearGradient(
                colors: [tint.opacity(0.08), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .mtrxLiquidGlass(cornerRadius: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: agentBubblePalette(agent).map { $0.opacity(0.45) },
                        center: .center
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .white.opacity(0.14), radius: 18)
        .shadow(color: .black.opacity(0.30), radius: 24, y: 10)
        .onAppear {
            viewModel.setup(userID: appState.currentUserID, walletManager: walletManager)
            viewModel.openAgentChat(agent)
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                drift = true
            }
        }
        .onChange(of: viewModel.dismissRequested) {
            // She navigated somewhere new from the popup — fold it away;
            // the orb stays docked wherever it was.
            if viewModel.dismissRequested {
                viewModel.dismissRequested = false
                onClose()
            }
        }
    }
}

// MARK: - Agent Presence (the floating orb)

/// Keeps an agent "around" after she navigates the app for the user —
/// a floating orb that persists across tabs until swiped away.
@MainActor
final class AgentPresence: ObservableObject {
    static let shared = AgentPresence()
    @Published var docked: AgentAccessControl.ActiveAgent?
    /// Where the orb floats — shared so the popup can grow out of it.
    @Published var position: CGPoint?

    func dock(_ agent: AgentAccessControl.ActiveAgent) { docked = agent }
    func clear() { docked = nil }
}

/// Each agent's pastel film — the same soap-bubble light in their key.
func agentBubblePalette(_ agent: AgentAccessControl.ActiveAgent) -> [Color] {
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

struct AgentReopen: Identifiable {
    let id = UUID()
    let agent: AgentAccessControl.ActiveAgent
}

struct FloatingAgentOrb: View {
    let agent: AgentAccessControl.ActiveAgent
    let onTap: () -> Void

    /// Position lives in AgentPresence so the popup knows where to grow
    /// from when the orb is tapped.
    @ObservedObject private var presence = AgentPresence.shared

    private var position: CGPoint? {
        get { presence.position }
        nonmutating set { presence.position = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            // She arrives mid-right — clear of the dock, the compose
            // button, and everything else that lives in the corners.
            let current = position ?? CGPoint(x: geo.size.width - 44, y: geo.size.height * 0.40)

            // Transparent liquid glass with a drifting iridescent
            // refraction — reflective and clear, the app's signature orb.
            GlassOrb(size: 54, tint: agentGlassTint(agent))
                .shadow(color: .white.opacity(0.18), radius: 12)
                .shadow(color: Color(red: 0.72, green: 0.78, blue: 0.98).opacity(0.22), radius: 24)
                .position(current)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            position = value.location
                        }
                        .onEnded { value in
                            let size = geo.size
                            let end = value.predictedEndLocation
                            let at = value.location
                            // Only leaving the screen sends her away —
                            // dragged past an edge, or flung toward one.
                            let draggedOff = at.x < 10 || at.x > size.width - 10
                                || at.y < 10 || at.y > size.height - 10
                            let flungOff = end.x < -40 || end.x > size.width + 40
                                || end.y < -40 || end.y > size.height + 40
                            if draggedOff || flungOff {
                                MtrxHaptics.impact(.light)
                                withAnimation(Motion.springSnappy) {
                                    AgentPresence.shared.clear()
                                }
                            } else {
                                // She stays exactly where she was put,
                                // nudged just enough to stay reachable.
                                withAnimation(Motion.springSnappy) {
                                    position = CGPoint(
                                        x: min(max(at.x, 38), size.width - 38),
                                        y: min(max(at.y, 80), size.height - 130)
                                    )
                                }
                            }
                        }
                )
                .onTapGesture {
                    // Opening the popup never undocks her — minimize
                    // folds the chat right back into this orb.
                    MtrxHaptics.impact(.light)
                    onTap()
                }
        }
    }
}

// MARK: - Navigation Destination

enum NavigationDestination: Hashable {
    case marketplace(id: String?)
    case contract(id: String?)
    case fundraiser(id: String?)
    case wallet
    case settings
    case governance
    case tokenDetail(symbol: String)
    case nftDetail(id: String)
    case transactionDetail(hash: String)
    case messaging
    case notifications
    case search
    case subscription
    case privacy
    case staking
    case dao
    case fundraiserList
    case insurance
}

// MARK: - App Tab

enum AppTab: Int, CaseIterable {
    case discover
    case build
    case home
    case social
    case account
}

extension MainTabView {
    /// Where the popup grows from: the orb's spot on screen, expressed
    /// as an anchor inside the popup's resting area — so the window
    /// visually unfolds out of the bubble itself.
    func popupAnchor(in size: CGSize) -> UnitPoint {
        let orb = AgentPresence.shared.position
            ?? CGPoint(x: size.width - 44, y: size.height * 0.40)
        let panelTop = max(size.height - 460 - 80, 0)
        let x = min(max(orb.x / max(size.width, 1), 0.05), 0.95)
        let y = min(max((orb.y - panelTop) / 460, 0.0), 1.0)
        return UnitPoint(x: x, y: y)
    }

    /// The selected-tab accent slides along a green→cyan gradient as
    /// the user moves left→right through the tabs: Discover sits at the
    /// green end, Account at the cyan end, with a smooth blend between.
    var tabTint: Color {
        let green = (r: 0.20, g: 0.78, b: 0.35)
        let cyan = (r: 0.13, g: 0.83, b: 0.93)
        let t = Double(selectedTab.rawValue) / Double(AppTab.allCases.count - 1)
        return Color(
            red: green.r + (cyan.r - green.r) * t,
            green: green.g + (cyan.g - green.g) * t,
            blue: green.b + (cyan.b - green.b) * t
        )
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentDestination: NavigationDestination?
    @Published var currentUserID: String = ""
    /// The user's real name. Empty until Apple provides it (first-ever
    /// sign-in only) or the user sets it themselves — never a fake
    /// placeholder, so the UI can greet honestly.
    @Published var displayName: String = ""
    @Published var walletAddress: String = DemoDataProvider.walletAddress
    @Published var joinDate: Date = Date()
    @Published var notificationCount: Int = 0
    /// Phase 4-A / W2: set at launch when the persisted signing key is missing/invalidated or not
    /// biometric-gated — the wallet needs a Tier-A reset (the step-5 recovery UI surfaces this).
    /// `nil` = signer OK, or no wallet, or cloud-identity-only.
    @Published var walletSignerResetReason: String?

    private enum Keys {
        static let onboardingComplete = "com.mtrx.onboardingComplete"
        static let appleUserId = "com.mtrx.appleUserId"
        static let displayName = "com.mtrx.userDisplayName"
        static let email = "com.mtrx.userEmail"
        static let walletAddress = "com.mtrx.walletAddress"
        static let joinDate = "com.mtrx.joinDate"
    }

    init() {
        restorePersistedSession()
    }

    /// Restore the demo account created via Sign in with Apple, so the
    /// user lands on Home — not onboarding — on every later launch.
    private func restorePersistedSession() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Keys.onboardingComplete),
              let userId = defaults.string(forKey: Keys.appleUserId),
              !userId.isEmpty else { return }

        currentUserID = userId
        if let name = defaults.string(forKey: Keys.displayName), !name.isEmpty {
            displayName = name
        }
        if let address = defaults.string(forKey: Keys.walletAddress), !address.isEmpty {
            walletAddress = address
        }
        if let joined = defaults.object(forKey: Keys.joinDate) as? Date {
            joinDate = joined
        }
        isAuthenticated = true

        // Restore the backend session token (JWT in the Keychain) so API calls
        // are authenticated across launches.
        MTRXAPIClient.shared.loadStoredToken()

        // Phase 4-A / W2–W3: restore + re-validate the wallet's signing key (the canonical signer).
        restoreWalletSigner()
    }

    /// Restore the wallet's signing key at launch (W2) and bind it as the canonical signer (W3),
    /// re-validating the key is present AND biometric-gated before trusting the persisted pointer.
    /// Captures a reset reason if the key is gone/invalidated/ungated so recovery (step 5) can route
    /// the user — never silently trusts a tampered/stale record for value-signing.
    private func restoreWalletSigner() {
        switch WalletCreation().restoreActiveWallet() {
        case .needsReset(let reason):
            walletSignerResetReason = reason
        case .restored, .identityOnly, .noWallet:
            walletSignerResetReason = nil
        }
    }

    func navigate(to destination: NavigationDestination) {
        currentDestination = destination
    }

    func signIn(userID: String, displayName: String, walletAddress: String) {
        self.currentUserID = userID
        if !displayName.isEmpty { self.displayName = displayName }
        self.walletAddress = walletAddress
        self.joinDate = Date()
        self.isAuthenticated = true

        // Persist the demo account so it survives relaunch.
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Keys.onboardingComplete)
        defaults.set(userID, forKey: Keys.appleUserId)
        if !displayName.isEmpty { defaults.set(displayName, forKey: Keys.displayName) }
        defaults.set(walletAddress, forKey: Keys.walletAddress)
        defaults.set(joinDate, forKey: Keys.joinDate)
    }

    /// User-set display name — persists like the Apple-provided one.
    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        UserDefaults.standard.set(trimmed, forKey: Keys.displayName)
    }

    func signOut() {
        isAuthenticated = false
        currentUserID = ""
        displayName = ""
        walletAddress = ""

        // Sign-out is a LOCAL wipe — it does NOT delete the account. The
        // account stays tied to the user's Apple ID; signing in with Apple
        // again (on this or any other device) brings it right back from the
        // backend. We just make sure nothing is left on this phone.
        AppState.wipeLocalData()
    }

    /// Permanently delete the account — required by App Store Guideline
    /// 5.1.1(v) for apps that support account creation. Unlike `signOut()`,
    /// this destroys the account, not just the local session: it requests
    /// server-side deletion + Sign in with Apple token revocation (handled
    /// by the backend), wipes every local trace, and returns to onboarding.
    func deleteAccount() {
        // Best-effort server-side deletion — fire-and-forget so the UI never
        // blocks on the network (the gateway may not be reachable yet).
        Task.detached {
            try? await MTRXAPIClient.shared.deleteAccount()
        }

        // Destroy the device Secure Enclave signing key for this account — a
        // real key deletion, so no signing material survives account deletion.
        let walletKeyTag = "wallet." + (currentUserID.isEmpty ? "local" : currentUserID)
        SecureEnclaveManager.shared.deleteKey(tag: walletKeyTag)

        isAuthenticated = false
        currentUserID = ""
        displayName = ""
        walletAddress = ""

        // Mark onboarding incomplete so the app returns to the welcome screen,
        // then wipe every local trace (defaults, token, files).
        UserDefaults.standard.set(false, forKey: Keys.onboardingComplete)
        AppState.wipeLocalData()
    }

    /// Remove every trace of the session from this device: all app
    /// preferences, the backend session token, and locally stored files
    /// (agent conversations, social media, avatars). The account itself lives
    /// on the backend, tied to Sign in with Apple, and is never touched here.
    static func wipeLocalData() {
        // 1. Every app preference — profile, settings, wallet cache, flags.
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // 2. The backend session token (JWT in the Keychain).
        MTRXAPIClient.shared.clearToken()
        // 3. Locally stored files — agent conversations, social media, avatars.
        let mtrxDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTRX", isDirectory: true)
        try? FileManager.default.removeItem(at: mtrxDir)
    }

    func refreshOnForeground() { }
    func prepareForBackground() { }
    func scheduleBackgroundTasks() { }
}

// MARK: - Wallet Manager

/// A bank or external crypto wallet the user has linked. Demo-safe: it
/// stores a nickname, a masked detail, and a balance — never raw bank
/// numbers or private keys.
struct LinkedAccount: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case bank, crypto
        var label: String { self == .bank ? "Bank" : "Crypto wallet" }
        var icon: String { self == .bank ? "building.columns.fill" : "wallet.pass.fill" }
    }
    var id: UUID = UUID()
    var kind: Kind
    var name: String
    var detail: String
    var balanceUSD: Double
}

class WalletManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var balance: Decimal = Decimal(DemoDataProvider.ethBalance * DemoDataProvider.ethPrice)
    @Published var walletAddress: String = DemoDataProvider.walletAddress
    @Published var ensName: String = DemoDataProvider.ensName
    @Published var tokens: [AppTokenBalance] = AppTokenBalance.sampleData
    @Published var nfts: [NFTItem] = NFTItem.sampleData
    @Published var transactions: [TransactionItem] = TransactionItem.sampleData
    @Published var defiPositions: [DeFiPositionItem] = DeFiPositionItem.sampleData
    @Published var needsRefresh: Bool = false

    /// Banks and external crypto wallets the user has linked. Their balances
    /// fold into the total portfolio so it reflects everywhere (Home,
    /// Account, agent context).
    @Published var linkedAccounts: [LinkedAccount] = WalletManager.loadLinkedAccounts() {
        didSet { WalletManager.saveLinkedAccounts(linkedAccounts) }
    }

    var linkedAccountsValue: Double { linkedAccounts.reduce(0) { $0 + $1.balanceUSD } }

    var totalPortfolioValue: Double {
        tokens.reduce(0) { $0 + $1.valueUSD } + linkedAccountsValue
    }

    func addLinkedAccount(_ account: LinkedAccount) { linkedAccounts.append(account) }
    func removeLinkedAccount(_ id: UUID) { linkedAccounts.removeAll { $0.id == id } }

    private static let linkedKey = "com.mtrx.wallet.linkedAccounts"
    static func loadLinkedAccounts() -> [LinkedAccount] {
        guard let data = UserDefaults.standard.data(forKey: linkedKey),
              let list = try? JSONDecoder().decode([LinkedAccount].self, from: data) else { return [] }
        return list
    }
    static func saveLinkedAccounts(_ list: [LinkedAccount]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: linkedKey)
        }
    }

    var portfolioChange24h: Double { 2.34 }
    var portfolioChangeAbsolute: Double { 127.45 }

    /// Publish the current portfolio + DeFi positions to the App Group so the
    /// Home Screen widgets reflect exactly what the app shows — live state when
    /// the backend is wired, demo state otherwise. It mirrors `tokens` /
    /// `defiPositions` verbatim and never invents widget-only numbers.
    @MainActor
    func publishWidgetSnapshots() {
        let isUp = portfolioChange24h >= 0

        let topTokens = tokens
            .sorted { $0.valueUSD > $1.valueUSD }
            .prefix(3)
            .map { t in
                WidgetPortfolioSnapshot.Token(
                    symbol: t.symbol,
                    value: t.valueUSD.formatted(.currency(code: "USD")),
                    change: String(format: "%@%.1f%%", t.change24h >= 0 ? "+" : "", t.change24h),
                    isUp: t.change24h >= 0
                )
            }

        WidgetSharedStore.save(WidgetPortfolioSnapshot(
            updatedAt: Date(),
            totalValue: totalPortfolioValue.formatted(.currency(code: "USD")),
            change24h: (isUp ? "+" : "-") + abs(portfolioChangeAbsolute).formatted(.currency(code: "USD")),
            changePercent: String(format: "%@%.2f%%", isUp ? "+" : "", portfolioChange24h),
            isPositive: isUp,
            tokens: Array(topTokens)
        ))

        let positionsTotal = defiPositions.reduce(0) { $0 + $1.value }
        WidgetSharedStore.save(WidgetPositionsSnapshot(
            updatedAt: Date(),
            totalValue: positionsTotal.formatted(.currency(code: "USD")),
            positions: defiPositions.map { p in
                WidgetPositionsSnapshot.Position(
                    name: p.protocol_,
                    healthFactor: p.healthFactor ?? 0,
                    value: p.value.formatted(.currency(code: "USD")),
                    apy: String(format: "%.1f%%", p.apy)
                )
            }
        ))
    }

    func reconnectIfNeeded() { }
    func persistState() { }

    func refreshOnForeground() {
        needsRefresh = true
    }

    // MARK: - Demo Actions (Trinity-executed)
    //
    // These mutate the shared wallet state so an action performed in the
    // Trinity conversation is immediately visible in the Account → Wallet
    // tab: balances move, a new transaction appears at the top of history.

    func token(_ symbol: String) -> AppTokenBalance? {
        tokens.first { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }
    }

    private func setBalance(_ symbol: String, to newBalance: Double) {
        tokens = tokens.map { t in
            guard t.symbol.caseInsensitiveCompare(symbol) == .orderedSame else { return t }
            return AppTokenBalance(
                symbol: t.symbol, name: t.name,
                balance: max(0, newBalance),
                priceUSD: t.priceUSD, change24h: t.change24h, iconColor: t.iconColor,
                isNative: t.isNative   // preserve the structural native flag across remaps
            )
        }
        if symbol.caseInsensitiveCompare("ETH") == .orderedSame, let eth = token("ETH") {
            balance = Decimal(eth.balance * eth.priceUSD)
        }
    }

    /// Send `amount` of `tokenSymbol` to `recipient`. Returns false when
    /// the token is unknown or the balance is insufficient.
    @discardableResult
    func demoSend(amount: Double, tokenSymbol: String, recipient: String) -> Bool {
        guard let t = token(tokenSymbol), t.balance >= amount else { return false }
        setBalance(t.symbol, to: t.balance - amount)
        transactions.insert(TransactionItem(
            type: .send,
            title: "Sent \(t.symbol)",
            subtitle: "To \(recipient)",
            amount: String(format: "-%.4f %@", amount, t.symbol),
            timestamp: Date(),
            status: .confirmed
        ), at: 0)
        return true
    }

    /// Send fiat (`USD`/`EUR`/`GBP`/`CAD`) to a recipient. The user just
    /// sends money; settlement rides the stablecoin rail underneath
    /// (USDC ≈ cash balance), which is invisible to them. Returns false
    /// when the cash balance can't cover the amount.
    @discardableResult
    func demoSendFiat(amount: Double, currency: String, recipient: String) -> Bool {
        let rate: Double = ["USD": 1.0, "EUR": 1.08, "GBP": 1.27, "CAD": 0.73][currency] ?? 1.0
        let usdAmount = amount * rate
        guard let cash = token("USDC"), cash.balance >= usdAmount else { return false }
        setBalance("USDC", to: cash.balance - usdAmount)

        let symbol: String = ["EUR": "€", "GBP": "£", "CAD": "C$"][currency] ?? "$"
        transactions.insert(TransactionItem(
            type: .send,
            title: "Sent \(symbol)\(String(format: "%.2f", amount))",
            subtitle: "To \(recipient) · instant transfer",
            amount: String(format: "-$%.2f", usdAmount),
            timestamp: Date(),
            status: .confirmed
        ), at: 0)
        return true
    }

    /// Swap `amount` of `from` into `to` at spot prices.
    /// Returns the received amount, or nil on failure.
    @discardableResult
    func demoSwap(amount: Double, from: String, to: String) -> Double? {
        guard let f = token(from), let t = token(to),
              f.balance >= amount, f.priceUSD > 0, t.priceUSD > 0 else { return nil }
        let received = amount * f.priceUSD / t.priceUSD
        setBalance(f.symbol, to: f.balance - amount)
        setBalance(t.symbol, to: t.balance + received)
        transactions.insert(TransactionItem(
            type: .swap,
            title: "Swapped \(f.symbol) → \(t.symbol)",
            subtitle: "Via MTRX router",
            amount: String(format: "+%.4f %@", received, t.symbol),
            timestamp: Date(),
            status: .confirmed
        ), at: 0)
        return received
    }

    /// Stake `amount` of `tokenSymbol` into the MTRX staking position.
    @discardableResult
    func demoStake(amount: Double, tokenSymbol: String) -> Bool {
        guard let t = token(tokenSymbol), t.balance >= amount else { return false }
        let usd = amount * t.priceUSD
        setBalance(t.symbol, to: t.balance - amount)

        if let idx = defiPositions.firstIndex(where: { $0.protocol_ == "MTRX Staking" }) {
            let p = defiPositions[idx]
            defiPositions[idx] = DeFiPositionItem(
                protocol_: p.protocol_, type: p.type,
                value: p.value + usd, apy: p.apy,
                healthFactor: p.healthFactor, icon: p.icon
            )
        } else {
            defiPositions.append(DeFiPositionItem(
                protocol_: "MTRX Staking", type: "Staking",
                value: usd, apy: 8.7, healthFactor: nil, icon: "lock.circle"
            ))
        }
        transactions.insert(TransactionItem(
            type: .stake,
            title: "Staked \(t.symbol)",
            subtitle: "MTRX Staking — 8.7% APY",
            amount: String(format: "-%.4f %@", amount, t.symbol),
            timestamp: Date(),
            status: .confirmed
        ), at: 0)
        return true
    }

    // MARK: - Live Prices
    //
    // Seed prices are an offline fallback; on launch the wallet syncs to
    // the same live feed Trinity quotes (CoinGecko), so the numbers she
    // says out loud and the numbers on every screen always agree.

    private static let coingeckoIDs: [String: String] = [
        "ETH": "ethereum", "USDC": "usd-coin", "WBTC": "wrapped-bitcoin",
        "LINK": "chainlink", "UNI": "uniswap", "AAVE": "aave",
    ]

    func refreshLivePrices() async {
        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        comps.queryItems = [
            URLQueryItem(name: "ids", value: Self.coingeckoIDs.values.joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "include_24hr_change", value: "true"),
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]]
        else { return }

        await MainActor.run {
            tokens = tokens.map { t in
                guard let id = Self.coingeckoIDs[t.symbol.uppercased()],
                      let entry = parsed[id],
                      let price = entry["usd"] else { return t }
                return AppTokenBalance(
                    symbol: t.symbol, name: t.name, balance: t.balance,
                    priceUSD: price,
                    change24h: entry["usd_24h_change"] ?? t.change24h,
                    iconColor: t.iconColor,
                    isNative: t.isNative   // preserve the structural native flag across remaps
                )
            }
            if let eth = token("ETH") {
                balance = Decimal(eth.balance * eth.priceUSD)
            }
            publishWidgetSnapshots()
        }
    }

    /// Pull the live portfolio from the gateway and replace the demo holdings.
    /// Silently keeps the current (sample) data if the backend isn't reachable,
    /// so the screen never goes blank.
    @MainActor
    func loadPortfolio() async {
        guard let p = try? await MTRXAPIClient.shared.getPortfolio() else { return }
        if !p.tokens.isEmpty {
            tokens = p.tokens.map { t in
                AppTokenBalance(
                    symbol: t.symbol, name: t.name, balance: t.balance,
                    priceUSD: t.balance > 0 ? t.valueUSD / t.balance : 0,
                    change24h: 0,
                    iconColor: WalletManager.tokenColor(for: t.symbol),
                    // Data-layer native determination (Base's native asset is ETH). The
                    // SEND keys off this structural flag, never a symbol check at send time;
                    // real contract metadata (contractAddress == nil) is a later hardening.
                    isNative: t.symbol.caseInsensitiveCompare("ETH") == .orderedSame
                )
            }
        }
        if !p.defiPositions.isEmpty {
            defiPositions = p.defiPositions.map { d in
                DeFiPositionItem(
                    protocol_: d.protocol_ ?? "—", type: d.type, value: d.valueUSD,
                    apy: d.apy ?? 0, healthFactor: nil, icon: "building.columns"
                )
            }
        }
        if !p.nfts.isEmpty {
            nfts = p.nfts.map { n in
                NFTItem(name: n.name, collection: n.collection, floorPrice: 0,
                        rarity: "", gradientColors: [.accentPrimary, .blue])
            }
        }
    }

    static func tokenColor(for symbol: String) -> Color {
        switch symbol.uppercased() {
        case "ETH":          return .blue
        case "USDC", "USDT": return .green
        case "MTRX":         return .accentPrimary
        case "WBTC", "BTC":  return .orange
        case "LINK":         return .blue
        case "UNI":          return .pink
        default:             return .accentPrimary
        }
    }

    /// Deploy a (demo) smart contract: records the deployment in the
    /// activity feed and returns the new contract address.
    @discardableResult
    func demoDeployContract(name: String) -> String {
        // Deterministic, content-derived demo address (no chain configured) — not
        // a random UUID and not a real deployed contract.
        let address = DemoArtifacts.address(seed: "deploy|\(name)")
        transactions.insert(TransactionItem(
            type: .contract,
            title: "Deployed \(name)",
            subtitle: "Glasswing audit passed · MTRX network",
            amount: String(address.prefix(10)) + "…",
            timestamp: Date(),
            status: .confirmed
        ), at: 0)
        return address
    }
}

// MARK: - Trinity Engine

class TrinityEngine: ObservableObject {
    @Published var isProcessing: Bool = false
}

// MARK: - Sample Data Models

struct AppTokenBalance: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let balance: Double
    let priceUSD: Double
    let change24h: Double
    let iconColor: Color
    /// True ONLY for the chain's native asset (ETH on Base). A STRUCTURAL flag — the
    /// real signed send path keys off this, not the symbol string, so a token can't be
    /// treated as native by spoofing its symbol "ETH". Set authoritatively from token
    /// metadata (here, on the curated sample list); defaults to false (= a token).
    var isNative: Bool = false

    var valueUSD: Double { balance * priceUSD }

    static let sampleData: [AppTokenBalance] = [
        AppTokenBalance(symbol: "ETH", name: "Ethereum", balance: 2.4531, priceUSD: 3245.67, change24h: 3.12, iconColor: .blue, isNative: true),
        AppTokenBalance(symbol: "USDC", name: "USD Coin", balance: 1250.00, priceUSD: 1.00, change24h: 0.01, iconColor: .green),
        AppTokenBalance(symbol: "MTRX", name: "Matrix Token", balance: 50000, priceUSD: 0.0234, change24h: 12.45, iconColor: .accentPrimary),
        AppTokenBalance(symbol: "WBTC", name: "Wrapped Bitcoin", balance: 0.0521, priceUSD: 67890.12, change24h: -1.23, iconColor: .orange),
        AppTokenBalance(symbol: "LINK", name: "Chainlink", balance: 125.5, priceUSD: 14.56, change24h: 5.67, iconColor: .blue),
        AppTokenBalance(symbol: "UNI", name: "Uniswap", balance: 89.2, priceUSD: 7.82, change24h: -0.45, iconColor: .pink),
    ]
}

struct NFTItem: Identifiable {
    let id = UUID()
    let name: String
    let collection: String
    let floorPrice: Double
    let rarity: String
    let gradientColors: [Color]

    static let sampleData: [NFTItem] = [
        NFTItem(name: "Genesis Pass #0042", collection: "MTRX Genesis", floorPrice: 0.85, rarity: "Legendary", gradientColors: [.accentPrimary, .blue]),
        NFTItem(name: "Protocol Badge #128", collection: "MTRX Badges", floorPrice: 0.12, rarity: "Rare", gradientColors: [.purple, .pink]),
        NFTItem(name: "DAO Founder #7", collection: "Governance NFTs", floorPrice: 2.1, rarity: "Epic", gradientColors: [.orange, .red]),
    ]
}

struct TransactionItem: Identifiable {
    let id = UUID()
    let type: TxType
    let title: String
    let subtitle: String
    let amount: String
    let timestamp: Date
    let status: TxStatus

    enum TxType { case send, receive, swap, stake, contract, approve }
    enum TxStatus { case confirmed, pending, failed }

    var icon: String {
        switch type {
        case .send: return Symbols.send
        case .receive: return Symbols.receive
        case .swap: return Symbols.swap
        case .stake: return Symbols.stake
        case .contract: return Symbols.contract
        case .approve: return Symbols.verified
        }
    }

    var iconColor: Color {
        switch type {
        case .send: return .statusError
        case .receive: return .statusSuccess
        case .swap: return .statusInfo
        case .stake: return .accentPrimary
        case .contract: return .accentTertiary
        case .approve: return .statusSuccess
        }
    }

    static let sampleData: [TransactionItem] = [
        TransactionItem(type: .receive, title: "Received ETH", subtitle: "From 0x1a2b...3c4d", amount: "+0.5 ETH", timestamp: Date().addingTimeInterval(-3600), status: .confirmed),
        TransactionItem(type: .swap, title: "Swap ETH → USDC", subtitle: "Via Uniswap V3", amount: "1,250 USDC", timestamp: Date().addingTimeInterval(-7200), status: .confirmed),
        TransactionItem(type: .stake, title: "Staked MTRX", subtitle: "90-day lock", amount: "10,000 MTRX", timestamp: Date().addingTimeInterval(-86400), status: .confirmed),
        TransactionItem(type: .contract, title: "Deploy Contract", subtitle: "Escrow Agreement", amount: "-0.003 ETH", timestamp: Date().addingTimeInterval(-172800), status: .confirmed),
        TransactionItem(type: .send, title: "Sent USDC", subtitle: "To 0x9f8e...7d6c", amount: "-500 USDC", timestamp: Date().addingTimeInterval(-259200), status: .confirmed),
        TransactionItem(type: .approve, title: "Token Approval", subtitle: "USDC on Uniswap", amount: "Unlimited", timestamp: Date().addingTimeInterval(-345600), status: .confirmed),
    ]
}

struct DeFiPositionItem: Identifiable {
    let id = UUID()
    let protocol_: String
    let type: String
    let value: Double
    let apy: Double
    let healthFactor: Double?
    let icon: String

    static let sampleData: [DeFiPositionItem] = [
        DeFiPositionItem(protocol_: "Aave V3", type: "Lending", value: 2500.00, apy: 4.2, healthFactor: 2.8, icon: "building.columns"),
        DeFiPositionItem(protocol_: "Uniswap V3", type: "Liquidity", value: 1800.50, apy: 12.5, healthFactor: nil, icon: "arrow.left.arrow.right"),
        DeFiPositionItem(protocol_: "MTRX Staking", type: "Staking", value: 1170.00, apy: 8.7, healthFactor: nil, icon: "lock.circle"),
    ]
}

// MARK: - Placeholder Views

// OnboardingView is defined in UI/Views/Onboarding/OnboardingView.swift
