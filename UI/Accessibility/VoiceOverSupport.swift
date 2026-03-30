import SwiftUI

/// Full VoiceOver accessibility labels, hints, traits, and custom actions for all views
struct VoiceOverSupport {
    /// Apply portfolio VoiceOver context
    static func portfolioLabel(value: String, change: String, isPositive: Bool) -> Text {
        Text("Portfolio value: \(value). \(isPositive ? "Up" : "Down") \(change) in the last 24 hours.")
    }

    /// Transaction row accessibility
    static func transactionLabel(type: String, amount: String, counterparty: String, status: String) -> String {
        "\(type) of \(amount) \(counterparty.isEmpty ? "" : "with \(counterparty)"). Status: \(status)."
    }

    /// Collateral ratio accessibility
    static func collateralLabel(ratio: Double, position: String) -> String {
        let health = ratio > 1.5 ? "healthy" : ratio > 1.2 ? "warning" : "critical"
        return "\(position). Collateral ratio: \(Int(ratio * 100)) percent. Health status: \(health)."
    }

    /// Contract status accessibility
    static func contractLabel(name: String, status: String, nextDeadline: String?) -> String {
        var label = "\(name). Status: \(status)."
        if let deadline = nextDeadline { label += " Next deadline: \(deadline)." }
        return label
    }
}

/// VoiceOver rotor support for quick navigation through financial data
struct AccessibilityRotorContent {
    static func portfolioRotors(tokens: [String], positions: [String], contracts: [String]) -> some View {
        EmptyView()
            .accessibilityRotor("Tokens") {
                ForEach(tokens, id: \.self) { token in
                    AccessibilityRotorEntry(token, id: token)
                }
            }
            .accessibilityRotor("DeFi Positions") {
                ForEach(positions, id: \.self) { pos in
                    AccessibilityRotorEntry(pos, id: pos)
                }
            }
            .accessibilityRotor("Contracts") {
                ForEach(contracts, id: \.self) { contract in
                    AccessibilityRotorEntry(contract, id: contract)
                }
            }
    }
}

extension View {
    func mtrxAccessibility(label: String, hint: String? = nil, traits: AccessibilityTraits = []) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(traits)
    }
}
