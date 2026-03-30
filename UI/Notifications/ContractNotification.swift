import UIKit
import UserNotifications
import UserNotificationsUI

/// Rich notification for contract events — milestone reached, payment received, term triggered
class ContractNotificationViewController: UIViewController, UNNotificationContentExtension {
    private let eventLabel = UILabel()
    private let contractLabel = UILabel()
    private let detailLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let stack = UIStackView(arrangedSubviews: [eventLabel, contractLabel, detailLabel])
        stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        eventLabel.font = .boldSystemFont(ofSize: 16)
        contractLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular); contractLabel.textColor = .secondaryLabel
        detailLabel.font = .systemFont(ofSize: 14); detailLabel.numberOfLines = 0
    }

    func didReceive(_ notification: UNNotification) {
        let info = notification.request.content.userInfo
        eventLabel.text = info["eventType"] as? String ?? "Contract Event"
        contractLabel.text = "Contract: \(info["contractAddress"] as? String ?? "")"
        detailLabel.text = info["detail"] as? String ?? ""
    }

    func didReceive(_ response: UNNotificationResponse, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        if response.actionIdentifier == "VIEW_CONTRACT" { completion(.dismissAndForwardAction) }
        else { completion(.dismiss) }
    }
}

enum ContractNotificationSetup {
    static func register() {
        let view = UNNotificationAction(identifier: "VIEW_CONTRACT", title: "View Contract", options: .foreground)
        let category = UNNotificationCategory(identifier: "CONTRACT_EVENT", actions: [view], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
