// NotificationManager.swift
// MTRX Apple Integration — Presence
// UserNotifications + UserNotificationsUI for rich transaction alerts

import UserNotifications
import Foundation

// MARK: - Notification Manager

final class NotificationManager: NSObject {

    // MARK: - Shared Instance

    static let shared = NotificationManager()

    // MARK: - Properties

    private let center = UNUserNotificationCenter.current()

    // MARK: - Categories

    enum Category: String {
        case transaction = "TRANSACTION"
        case contract = "CONTRACT"
        case liquidation = "LIQUIDATION"
        case governance = "GOVERNANCE"
        case social = "SOCIAL"
        case security = "SECURITY"
        case price = "PRICE_ALERT"
        case insurance = "INSURANCE"
    }

    // MARK: - Actions

    enum Action: String {
        case viewTransaction = "VIEW_TRANSACTION"
        case approve = "APPROVE"
        case reject = "REJECT"
        case reply = "REPLY"
        case dismiss = "DISMISS"
        case viewDetails = "VIEW_DETAILS"
        case vote = "VOTE"
    }

    // MARK: - Authorization

    /// Requests notification authorization with all delivery options.
    func requestAuthorization() async throws -> Bool {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound, .criticalAlert, .providesAppNotificationSettings]
        let granted = try await center.requestAuthorization(options: options)
        if granted {
            await registerCategories()
        }
        return granted
    }

    /// Returns current notification settings.
    func currentSettings() async -> UNNotificationSettings {
        return await center.notificationSettings()
    }

    // MARK: - Category Registration

    private func registerCategories() async {
        let transactionActions = [
            UNNotificationAction(identifier: Action.viewTransaction.rawValue, title: "View", options: .foreground),
            UNNotificationAction(identifier: Action.dismiss.rawValue, title: "Dismiss", options: .destructive)
        ]

        let contractActions = [
            UNNotificationAction(identifier: Action.approve.rawValue, title: "Approve", options: .authenticationRequired),
            UNNotificationAction(identifier: Action.reject.rawValue, title: "Reject", options: [.destructive, .authenticationRequired]),
            UNNotificationAction(identifier: Action.viewDetails.rawValue, title: "Details", options: .foreground)
        ]

        let governanceActions = [
            UNNotificationAction(identifier: Action.vote.rawValue, title: "Vote Now", options: .foreground),
            UNNotificationAction(identifier: Action.viewDetails.rawValue, title: "View Proposal", options: .foreground)
        ]

        let socialActions = [
            UNTextInputNotificationAction(identifier: Action.reply.rawValue, title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Message..."),
            UNNotificationAction(identifier: Action.viewDetails.rawValue, title: "View", options: .foreground)
        ]

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Category.transaction.rawValue, actions: transactionActions, intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.contract.rawValue, actions: contractActions, intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.liquidation.rawValue, actions: transactionActions, intentIdentifiers: [], options: .customDismissAction),
            UNNotificationCategory(identifier: Category.governance.rawValue, actions: governanceActions, intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.social.rawValue, actions: socialActions, intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.security.rawValue, actions: transactionActions, intentIdentifiers: [], options: .customDismissAction),
            UNNotificationCategory(identifier: Category.price.rawValue, actions: transactionActions, intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.insurance.rawValue, actions: contractActions, intentIdentifiers: [])
        ]

        center.setNotificationCategories(categories)
    }

    // MARK: - Schedule Notifications

    /// Schedules a local notification for a transaction event.
    func scheduleTransactionNotification(
        id: String,
        title: String,
        body: String,
        amount: String?,
        chain: String?,
        category: Category = .transaction,
        delay: TimeInterval = 0
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.sound = .default
        content.threadIdentifier = "transaction-\(id)"

        var userInfo: [String: Any] = ["transactionId": id]
        if let amount = amount { userInfo["amount"] = amount }
        if let chain = chain { userInfo["chain"] = chain }
        content.userInfo = userInfo

        let trigger: UNNotificationTrigger?
        if delay > 0 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        } else {
            trigger = nil
        }

        let request = UNNotificationRequest(identifier: "tx-\(id)", content: content, trigger: trigger)
        try await center.add(request)
    }

    /// Schedules a critical alert for liquidation or security events.
    func scheduleCriticalAlert(id: String, title: String, body: String, category: Category) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.relevanceScore = 1.0
        content.userInfo = ["alertId": id, "critical": true]

        let request = UNNotificationRequest(identifier: "critical-\(id)", content: content, trigger: nil)
        try await center.add(request)
    }

    /// Schedules a time-sensitive notification.
    func scheduleTimeSensitive(id: String, title: String, body: String, category: Category) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 0.8

        let request = UNNotificationRequest(identifier: "ts-\(id)", content: content, trigger: nil)
        try await center.add(request)
    }

    // MARK: - Badge Management

    /// Updates the app badge count.
    func updateBadge(count: Int) async throws {
        try await center.setBadgeCount(count)
    }

    // MARK: - Pending/Delivered Management

    /// Removes a pending notification by identifier.
    func removePending(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Removes delivered notifications from notification center.
    func removeDelivered(ids: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Returns all pending notification requests.
    func pendingRequests() async -> [UNNotificationRequest] {
        return await center.pendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .badge, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier

        switch actionId {
        case Action.viewTransaction.rawValue:
            if let txId = userInfo["transactionId"] as? String {
                NotificationCenter.default.post(name: .mtrxNavigateToTransaction, object: nil, userInfo: ["id": txId])
            }
        case Action.approve.rawValue:
            if let txId = userInfo["transactionId"] as? String {
                NotificationCenter.default.post(name: .mtrxApproveTransaction, object: nil, userInfo: ["id": txId])
            }
        case Action.reject.rawValue:
            if let txId = userInfo["transactionId"] as? String {
                NotificationCenter.default.post(name: .mtrxRejectTransaction, object: nil, userInfo: ["id": txId])
            }
        case Action.reply.rawValue:
            if let textResponse = response as? UNTextInputNotificationResponse {
                NotificationCenter.default.post(name: .mtrxReplyToMessage, object: nil, userInfo: ["text": textResponse.userText])
            }
        case Action.vote.rawValue:
            if let proposalId = userInfo["proposalId"] as? String {
                NotificationCenter.default.post(name: .mtrxNavigateToGovernance, object: nil, userInfo: ["id": proposalId])
            }
        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let mtrxNavigateToTransaction = Notification.Name("mtrxNavigateToTransaction")
    static let mtrxApproveTransaction = Notification.Name("mtrxApproveTransaction")
    static let mtrxRejectTransaction = Notification.Name("mtrxRejectTransaction")
    static let mtrxReplyToMessage = Notification.Name("mtrxReplyToMessage")
    static let mtrxNavigateToGovernance = Notification.Name("mtrxNavigateToGovernance")
}
