import UIKit
import UserNotifications
import UserNotificationsUI

/// Rich notification for insurance payout confirmation with amount and transaction link
class InsuranceNotificationViewController: UIViewController, UNNotificationContentExtension {
    private let titleLabel = UILabel()
    private let amountLabel = UILabel()
    private let txLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let stack = UIStackView(arrangedSubviews: [titleLabel, amountLabel, txLabel])
        stack.axis = .vertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        titleLabel.font = .boldSystemFont(ofSize: 16); titleLabel.textColor = .systemGreen
        amountLabel.font = .monospacedDigitSystemFont(ofSize: 32, weight: .bold); amountLabel.textAlignment = .center
        txLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular); txLabel.textColor = .secondaryLabel; txLabel.textAlignment = .center
    }

    func didReceive(_ notification: UNNotification) {
        let info = notification.request.content.userInfo
        titleLabel.text = "Insurance Payout Confirmed"
        amountLabel.text = info["amount"] as? String ?? ""
        txLabel.text = "tx: \(info["txHash"] as? String ?? "")"
    }

    func didReceive(_ response: UNNotificationResponse, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        completion(response.actionIdentifier == "VIEW_TX" ? .dismissAndForwardAction : .dismiss)
    }
}

enum InsuranceNotificationSetup {
    static func register() {
        let viewTx = UNNotificationAction(identifier: "VIEW_TX", title: "View Transaction", options: .foreground)
        let category = UNNotificationCategory(identifier: "INSURANCE_PAYOUT", actions: [viewTx], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
