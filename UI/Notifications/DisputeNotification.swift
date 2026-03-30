import UIKit
import UserNotifications
import UserNotificationsUI

/// Rich notification for dispute deadline with evidence submission action
class DisputeNotificationViewController: UIViewController, UNNotificationContentExtension {
    private let titleLabel = UILabel()
    private let deadlineLabel = UILabel()
    private let detailLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let stack = UIStackView(arrangedSubviews: [titleLabel, deadlineLabel, detailLabel])
        stack.axis = .vertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        titleLabel.font = .boldSystemFont(ofSize: 18)
        deadlineLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold); deadlineLabel.textColor = .systemOrange; deadlineLabel.textAlignment = .center
        detailLabel.font = .systemFont(ofSize: 14); detailLabel.numberOfLines = 0; detailLabel.textColor = .secondaryLabel
    }

    func didReceive(_ notification: UNNotification) {
        let info = notification.request.content.userInfo
        titleLabel.text = "Dispute #\(info["disputeId"] as? String ?? "")"
        let hoursLeft = info["hoursRemaining"] as? Int ?? 0
        deadlineLabel.text = "\(hoursLeft)h remaining"
        detailLabel.text = info["context"] as? String ?? "Evidence submission window closing soon."
    }

    func didReceive(_ response: UNNotificationResponse, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        if response.actionIdentifier == "SUBMIT_EVIDENCE" { completion(.dismissAndForwardAction) }
        else { completion(.dismiss) }
    }
}

enum DisputeNotificationSetup {
    static func register() {
        let submit = UNNotificationAction(identifier: "SUBMIT_EVIDENCE", title: "Submit Evidence", options: .foreground)
        let category = UNNotificationCategory(identifier: "DISPUTE_DEADLINE", actions: [submit], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
