// ShortcutsProvider.swift
// MTRX Apple Integration — AppIntents
// Donates shortcuts based on usage patterns

import AppIntents

// MARK: - MTRX Shortcuts Provider

struct MTRXShortcutsProvider: AppShortcutsProvider {

    // MARK: - App Shortcuts

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskTrinityIntent(),
            phrases: [
                "Ask \(.applicationName) a question",
                "Talk to Trinity in \(.applicationName)",
                "Hey \(.applicationName)"
            ],
            shortTitle: "Ask Trinity",
            systemImageName: "brain.head.profile"
        )

        AppShortcut(
            intent: PortfolioSummaryIntent(),
            phrases: [
                "Check my portfolio in \(.applicationName)",
                "Show my \(.applicationName) balance",
                "How is my crypto doing in \(.applicationName)"
            ],
            shortTitle: "Check Portfolio",
            systemImageName: "chart.pie"
        )

        AppShortcut(
            intent: SendPaymentAppIntent(),
            phrases: [
                "Send crypto with \(.applicationName)",
                "Pay with \(.applicationName)",
                "Transfer ETH using \(.applicationName)"
            ],
            shortTitle: "Send Payment",
            systemImageName: "arrow.up.circle"
        )

        AppShortcut(
            intent: CheckGasPriceIntent(),
            phrases: [
                "Check gas price in \(.applicationName)",
                "What's the gas fee on \(.applicationName)"
            ],
            shortTitle: "Gas Price",
            systemImageName: "fuelpump"
        )

        AppShortcut(
            intent: SwapTokensIntent(),
            phrases: [
                "Swap tokens in \(.applicationName)",
                "Exchange crypto with \(.applicationName)"
            ],
            shortTitle: "Swap Tokens",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: TransactionHistoryIntent(),
            phrases: [
                "Show my transactions in \(.applicationName)",
                "Recent activity in \(.applicationName)"
            ],
            shortTitle: "Transaction History",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}

// MARK: - Dynamic Shortcut Donation

final class ShortcutDonationManager {

    // MARK: - Shared Instance

    static let shared = ShortcutDonationManager()

    // MARK: - Properties

    private var usagePatterns: [String: Int] = [:]
    private let donationQueue = DispatchQueue(label: "com.mtrx.shortcut.donation", qos: .utility)

    // MARK: - Usage Tracking

    /// Records a user action for pattern-based shortcut donation.
    func recordAction(_ action: String, parameters: [String: Any] = [:]) {
        donationQueue.async { [weak self] in
            let key = action
            self?.usagePatterns[key, default: 0] += 1
            self?.evaluateDonation(for: action, parameters: parameters)
        }
    }

    // MARK: - Donation Evaluation

    private func evaluateDonation(for action: String, parameters: [String: Any]) {
        guard let count = usagePatterns[action], count >= 3 else { return }

        switch action {
        case "portfolio_check":
            donatePortfolioShortcut()
        case "send_payment":
            if let recipient = parameters["recipient"] as? String,
               let token = parameters["token"] as? String {
                donateFrequentPaymentShortcut(recipient: recipient, token: token)
            }
        case "gas_check":
            donateGasCheckShortcut()
        case "swap":
            if let pair = parameters["pair"] as? String {
                donateSwapShortcut(pair: pair)
            }
        default:
            break
        }
    }

    // MARK: - Shortcut Donations

    private func donatePortfolioShortcut() {
        // Portfolio check is already in static shortcuts
    }

    private func donateFrequentPaymentShortcut(recipient: String, token: String) {
        // Donate a personalized payment shortcut for frequently used recipients
        let intent = SendPaymentAppIntent()
        intent.recipient = recipient
        intent.token = token
    }

    private func donateGasCheckShortcut() {
        // Gas check is already in static shortcuts
    }

    private func donateSwapShortcut(pair: String) {
        let components = pair.split(separator: "/")
        guard components.count == 2 else { return }
        let intent = SwapTokensIntent()
        intent.fromToken = String(components[0])
        intent.toToken = String(components[1])
    }

    // MARK: - Relevance Scoring

    /// Updates shortcut relevance based on time-of-day patterns.
    func updateRelevanceScores() {
        let hour = Calendar.current.component(.hour, from: Date())

        // Morning users tend to check portfolios
        if (6...9).contains(hour) {
            recordAction("portfolio_check")
        }

        // Pre-market gas checks
        if (8...10).contains(hour) {
            recordAction("gas_check")
        }
    }
}
