// AppDelegate.swift
// MTRX
//
// Application lifecycle with push notification registration and background tasks.

import UIKit
import UserNotifications
import BackgroundTasks

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Properties

    private let backgroundTaskIdentifier = "com.mtrx.refresh"
    private let backgroundProcessingIdentifier = "com.mtrx.processing"

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAppearance()
        registerBackgroundTasks()
        // The MVP build has no APNs entitlement and no notification-driven features,
        // so prompting on launch would ask for a permission we can't fulfill. Gated
        // until mvpMode is off (production), when the aps-environment entitlement and
        // real notification flows are in place.
        if !FeatureFlags.mvpMode {
            requestNotificationPermissions(application: application)
        }
        configureAnalytics()
        // Subscribe to MetricKit so iOS delivers real performance + crash/hang
        // diagnostics; stored locally only (see MetricsCollector).
        MetricsCollector.shared.install()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            config.delegateClass = SceneDelegate.self
            return config
        }

        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // Clean up resources for discarded scenes
    }

    // MARK: - Push Notification Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationService.shared.registerDeviceToken(tokenString)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[MTRX] Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - Background URL Sessions

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundSessionManager.shared.handleEventsForBackgroundSession(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }

    // MARK: - Private Configuration

    private func configureAppearance() {
        // Tab bar — pure black background, #666666 unselected. The
        // SELECTED color is deliberately left to SwiftUI's .tint so the
        // green→cyan gradient accent can animate per tab; hardcoding it
        // here would override the tint app-wide.
        let unselectedColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        // The dock sits in the same deep-ocean world as every screen.
        tabBarAppearance.backgroundColor = UIColor(red: 0.035, green: 0.078, blue: 0.110, alpha: 1)

        let normalAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: unselectedColor]

        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = unselectedColor
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes

        tabBarAppearance.inlineLayoutAppearance.normal.iconColor = unselectedColor
        tabBarAppearance.inlineLayoutAppearance.normal.titleTextAttributes = normalAttributes

        tabBarAppearance.compactInlineLayoutAppearance.normal.iconColor = unselectedColor
        tabBarAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes = normalAttributes

        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().unselectedItemTintColor = unselectedColor

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().standardAppearance = navBarAppearance
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundProcessingIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundProcessing(task: task as! BGProcessingTask)
        }
    }

    private func requestNotificationPermissions(application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
            if let error = error {
                print("[MTRX] Notification authorization error: \(error.localizedDescription)")
            }
        }

        registerNotificationCategories(center: center)
    }

    private func registerNotificationCategories(center: UNUserNotificationCenter) {
        // Liquidation warning actions
        let addCollateralAction = UNNotificationAction(
            identifier: "ADD_COLLATERAL",
            title: "Add Collateral",
            options: [.foreground]
        )
        let viewPositionAction = UNNotificationAction(
            identifier: "VIEW_POSITION",
            title: "View Position",
            options: [.foreground]
        )
        let liquidationCategory = UNNotificationCategory(
            identifier: "LIQUIDATION_WARNING",
            actions: [addCollateralAction, viewPositionAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Dispute actions
        let respondAction = UNNotificationAction(
            identifier: "RESPOND_DISPUTE",
            title: "Respond",
            options: [.foreground]
        )
        let disputeCategory = UNNotificationCategory(
            identifier: "DISPUTE_DEADLINE",
            actions: [respondAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Contract event actions
        let viewContractAction = UNNotificationAction(
            identifier: "VIEW_CONTRACT",
            title: "View Contract",
            options: [.foreground]
        )
        let contractCategory = UNNotificationCategory(
            identifier: "CONTRACT_EVENT",
            actions: [viewContractAction],
            intentIdentifiers: [],
            options: []
        )

        // Insurance payout actions
        let claimPayoutAction = UNNotificationAction(
            identifier: "CLAIM_PAYOUT",
            title: "Claim Payout",
            options: [.foreground]
        )
        let insuranceCategory = UNNotificationCategory(
            identifier: "INSURANCE_PAYOUT",
            actions: [claimPayoutAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([
            liquidationCategory,
            disputeCategory,
            contractCategory,
            insuranceCategory
        ])
    }

    private func configureAnalytics() {
        // Privacy-respecting analytics configuration
    }

    // MARK: - Background Task Handlers

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleNextAppRefresh()

        let operation = PortfolioRefreshOperation()

        task.expirationHandler = {
            operation.cancel()
        }

        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        OperationQueue().addOperation(operation)
    }

    private func handleBackgroundProcessing(task: BGProcessingTask) {
        let operation = BlockchainSyncOperation()

        task.expirationHandler = {
            operation.cancel()
        }

        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        OperationQueue().addOperation(operation)
    }

    private func scheduleNextAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        try? BGTaskScheduler.shared.submit(request)
    }
}

// MARK: - Placeholder Services

class NotificationService {
    static let shared = NotificationService()
    func registerDeviceToken(_ token: String) { }
}

class BackgroundSessionManager {
    static let shared = BackgroundSessionManager()
    func handleEventsForBackgroundSession(identifier: String, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

class PortfolioRefreshOperation: Operation { }
class BlockchainSyncOperation: Operation { }
