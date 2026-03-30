import WatchKit
import WatchConnectivity
import UserNotifications

/// Apple Watch companion app lifecycle manager
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private let connectivitySession = WCSession.default

    func applicationDidFinishLaunching() {
        if WCSession.isSupported() {
            connectivitySession.delegate = self
            connectivitySession.activate()
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .haptic]) { _, _ in }
    }

    func applicationDidBecomeActive() {
        requestLatestPortfolio()
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {}

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refresh as WKApplicationRefreshBackgroundTask:
                requestLatestPortfolio()
                scheduleNextRefresh()
                refresh.setTaskCompletedWithSnapshot(false)
            case let snapshot as WKSnapshotRefreshBackgroundTask:
                snapshot.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: .distantFuture, userInfo: nil)
            case let connectivity as WKWatchConnectivityRefreshBackgroundTask:
                connectivity.setTaskCompletedWithSnapshot(false)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    private func requestLatestPortfolio() {
        guard connectivitySession.isReachable else { return }
        connectivitySession.sendMessage(["request": "portfolio"], replyHandler: nil)
    }

    private func scheduleNextRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: 15 * 60),
            userInfo: nil
        ) { _ in }
    }
}

extension WatchAppDelegate: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        NotificationCenter.default.post(name: .watchDataReceived, object: message)
    }
}

extension Notification.Name {
    static let watchDataReceived = Notification.Name("watchDataReceived")
}
