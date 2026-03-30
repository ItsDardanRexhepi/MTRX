import SwiftUI
import UserNotifications
import UserNotificationsUI

/// Rich notification for DeFi collateral warning with top-up action
class LiquidationNotificationViewController: UIViewController, UNNotificationContentExtension {
    private let ratioLabel = UILabel()
    private let messageLabel = UILabel()
    private let gaugeView = UIProgressView(progressViewStyle: .default)

    override func viewDidLoad() {
        super.viewDidLoad()
        let stack = UIStackView(arrangedSubviews: [ratioLabel, gaugeView, messageLabel])
        stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        ratioLabel.font = .boldSystemFont(ofSize: 24); ratioLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 14); messageLabel.numberOfLines = 0; messageLabel.textColor = .secondaryLabel
        gaugeView.transform = CGAffineTransform(scaleX: 1, y: 3)
    }

    func didReceive(_ notification: UNNotification) {
        let info = notification.request.content.userInfo
        let ratio = info["collateralRatio"] as? Double ?? 0
        let position = info["positionName"] as? String ?? "DeFi Position"
        ratioLabel.text = String(format: "%.0f%% Collateral", ratio * 100)
        ratioLabel.textColor = ratio > 1.5 ? .systemGreen : ratio > 1.2 ? .systemYellow : .systemRed
        gaugeView.progress = Float(min(ratio / 2.0, 1.0))
        gaugeView.tintColor = ratio > 1.5 ? .systemGreen : ratio > 1.2 ? .systemYellow : .systemRed
        messageLabel.text = "\(position) is approaching liquidation threshold. Tap 'Top Up' to add collateral."
    }

    func didReceive(_ response: UNNotificationResponse, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        if response.actionIdentifier == "TOP_UP" {
            completion(.dismissAndForwardAction)
        } else {
            completion(.dismiss)
        }
    }
}

/// Register notification category with actions
enum LiquidationNotificationSetup {
    static func register() {
        let topUp = UNNotificationAction(identifier: "TOP_UP", title: "Top Up Now", options: .foreground)
        let dismiss = UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: .destructive)
        let category = UNNotificationCategory(identifier: "LIQUIDATION_WARNING", actions: [topUp, dismiss], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
