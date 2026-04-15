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
        @unknown default:
            break
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLaunch = true

    var body: some View {
        ZStack {
            if showLaunch {
                LaunchView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showLaunch = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            } else {
                Group {
                    if appState.isAuthenticated {
                        MainTabView()
                    } else {
                        OnboardingView()
                    }
                }
                .transition(.opacity)
                .animation(Motion.springDefault, value: appState.isAuthenticated)
            }
        }
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
        .onChange(of: selectedTab) { _, _ in
            MtrxHaptics.selection()
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

// MARK: - App State

class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentDestination: NavigationDestination?
    @Published var currentUserID: String = ""
    @Published var displayName: String = DemoDataProvider.ensName
    @Published var walletAddress: String = DemoDataProvider.walletAddress
    @Published var joinDate: Date = Date()
    @Published var notificationCount: Int = 0

    func navigate(to destination: NavigationDestination) {
        currentDestination = destination
    }

    func signIn(userID: String, displayName: String, walletAddress: String) {
        self.currentUserID = userID
        self.displayName = displayName
        self.walletAddress = walletAddress
        self.joinDate = Date()
        self.isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        currentUserID = ""
        displayName = ""
        walletAddress = ""
    }

    func refreshOnForeground() { }
    func prepareForBackground() { }
    func scheduleBackgroundTasks() { }
}

// MARK: - Wallet Manager

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

    var totalPortfolioValue: Double {
        tokens.reduce(0) { $0 + $1.valueUSD }
    }

    var portfolioChange24h: Double { 2.34 }
    var portfolioChangeAbsolute: Double { 127.45 }

    func reconnectIfNeeded() { }
    func persistState() { }

    func refreshOnForeground() {
        needsRefresh = true
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

    var valueUSD: Double { balance * priceUSD }

    static let sampleData: [AppTokenBalance] = [
        AppTokenBalance(symbol: "ETH", name: "Ethereum", balance: 2.4531, priceUSD: 3245.67, change24h: 3.12, iconColor: .blue),
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
