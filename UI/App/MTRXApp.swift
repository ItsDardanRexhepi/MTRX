// MTRXApp.swift
// MTRX
//
// App entry point with WindowGroup, scene phases, and app delegate adapter.

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
        @unknown default:
            break
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: appState.isAuthenticated)
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
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

            AgentConversationView(userID: appState.currentUserID)
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
        .tint(Color.tabSelected)
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
}

// MARK: - App Tab

enum AppTab: Int, CaseIterable {
    case discover
    case build
    case home
    case social
    case account
}

// MARK: - Placeholder State Objects

class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentDestination: NavigationDestination?
    @Published var currentUserID: String = ""

    func navigate(to destination: NavigationDestination) {
        currentDestination = destination
    }

    func refreshOnForeground() { }
    func prepareForBackground() { }
    func scheduleBackgroundTasks() { }
}

class WalletManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var balance: Decimal = 0

    func reconnectIfNeeded() { }
    func persistState() { }
}

class TrinityEngine: ObservableObject {
    @Published var isProcessing: Bool = false
}

// MARK: - Placeholder Views
// OnboardingView is defined in UI/Views/Onboarding/OnboardingView.swift
