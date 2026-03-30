// SceneDelegate.swift
// MTRX
//
// Scene lifecycle and CarPlay support via CPTemplateApplicationSceneDelegate.

import UIKit
import CarPlay
import SwiftUI

// MARK: - Scene Delegate

class SceneDelegate: UIResponder, UIWindowSceneDelegate, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    var window: UIWindow?
    private var carPlayInterfaceController: CPInterfaceController?
    private var carPlayWindow: CPWindow?

    // MARK: - UIWindowSceneDelegate

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        let rootView = RootView()
            .environmentObject(AppState())
            .environmentObject(WalletManager())
            .environmentObject(TrinityEngine())

        window.rootViewController = UIHostingController(rootView: rootView)
        window.makeKeyAndVisible()

        // Handle any pending URL contexts
        if let urlContext = connectionOptions.urlContexts.first {
            handleIncomingURL(urlContext.url)
        }

        // Handle any pending user activities
        if let userActivity = connectionOptions.userActivities.first {
            handleUserActivity(userActivity)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        UIApplication.shared.applicationIconBadgeNumber = 0
        resumeBlockchainConnections()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        cacheCurrentState()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        scheduleBackgroundRefresh()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        refreshPortfolioData()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleIncomingURL(url)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleUserActivity(userActivity)
    }

    // MARK: - CPTemplateApplicationSceneDelegate (CarPlay)

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        carPlayInterfaceController = interfaceController
        carPlayWindow = window

        let carPlayRootTemplate = buildCarPlayRootTemplate()
        interfaceController.setRootTemplate(carPlayRootTemplate, animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        carPlayInterfaceController = nil
        carPlayWindow = nil
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didSelect navigationAlert: CPNavigationAlert
    ) {
        // Handle CarPlay navigation alert selection
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didSelect maneuver: CPManeuver
    ) {
        // Handle CarPlay maneuver selection
    }

    // MARK: - CarPlay Template Builder

    private func buildCarPlayRootTemplate() -> CPTabBarTemplate {
        let portfolioTab = buildPortfolioTab()
        let alertsTab = buildAlertsTab()
        let trinityTab = buildTrinityTab()

        let tabBar = CPTabBarTemplate(templates: [portfolioTab, alertsTab, trinityTab])
        return tabBar
    }

    private func buildPortfolioTab() -> CPListTemplate {
        let portfolioSection = CPListSection(items: [
            CPListItem(text: "Total Portfolio", detailText: "$0.00"),
            CPListItem(text: "24h Change", detailText: "+0.00%"),
            CPListItem(text: "Active Positions", detailText: "0")
        ])

        let template = CPListTemplate(title: "Portfolio", sections: [portfolioSection])
        template.tabTitle = "Portfolio"
        template.tabSystemItem = .bookmarks
        return template
    }

    private func buildAlertsTab() -> CPListTemplate {
        let alertsSection = CPListSection(items: [
            CPListItem(text: "No active alerts", detailText: "All positions healthy")
        ])

        let template = CPListTemplate(title: "Alerts", sections: [alertsSection])
        template.tabTitle = "Alerts"
        template.tabSystemItem = .more
        return template
    }

    private func buildTrinityTab() -> CPListTemplate {
        let trinitySection = CPListSection(items: [
            CPListItem(text: "Ask Trinity", detailText: "Voice-activated assistant")
        ])

        let template = CPListTemplate(title: "Trinity", sections: [trinitySection])
        template.tabTitle = "Trinity"
        template.tabSystemItem = .search
        return template
    }

    // MARK: - URL & Activity Handling

    private func handleIncomingURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }

        NotificationCenter.default.post(
            name: .didReceiveDeepLink,
            object: nil,
            userInfo: ["url": url, "components": components]
        )
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        handleIncomingURL(url)
    }

    // MARK: - Background & State Management

    private func resumeBlockchainConnections() {
        // Re-establish WebSocket connections to blockchain nodes
    }

    private func cacheCurrentState() {
        // Persist current view state for restoration
    }

    private func scheduleBackgroundRefresh() {
        // Schedule portfolio data refresh
    }

    private func refreshPortfolioData() {
        // Fetch latest portfolio values and positions
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveDeepLink = Notification.Name("com.mtrx.didReceiveDeepLink")
}
