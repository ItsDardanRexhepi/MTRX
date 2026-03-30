// FocusFilterHandler.swift
// MTRX Apple Integration — Awareness
// Trinity adapts behavior based on user's Focus mode

import Intents

// MARK: - Trinity Focus Filter

@available(iOS 16.0, *)
struct TrinityFocusFilter: SetFocusFilterIntent {

    static var title: LocalizedStringResource = "Trinity Focus Mode"
    static var description = IntentDescription("Adjust Trinity's behavior based on your Focus mode")

    // MARK: - Parameters

    @Parameter(title: "Alert Level", default: .normal)
    var alertLevel: TrinityAlertLevel

    @Parameter(title: "Allow Transaction Alerts", default: true)
    var allowTransactionAlerts: Bool

    @Parameter(title: "Allow Price Alerts", default: true)
    var allowPriceAlerts: Bool

    @Parameter(title: "Quiet Mode", default: false)
    var quietMode: Bool

    @Parameter(title: "Persona Override")
    var personaOverride: TrinityFocusPersona?

    // MARK: - Display Representation

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Trinity: \(alertLevel.rawValue)",
            subtitle: quietMode ? "Quiet Mode" : "Active"
        )
    }

    // MARK: - Perform

    func perform() async throws -> some IntentResult {
        let config = FocusConfiguration(
            alertLevel: alertLevel,
            allowTransactionAlerts: allowTransactionAlerts,
            allowPriceAlerts: allowPriceAlerts,
            quietMode: quietMode,
            personaOverride: personaOverride
        )

        FocusFilterStore.shared.applyConfiguration(config)
        return .result()
    }
}

// MARK: - Alert Level Enum

@available(iOS 16.0, *)
enum TrinityAlertLevel: String, AppEnum {
    case critical = "Critical Only"
    case important = "Important"
    case normal = "Normal"
    case all = "All"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Alert Level"
    static var caseDisplayRepresentations: [TrinityAlertLevel: DisplayRepresentation] = [
        .critical: "Critical Only",
        .important: "Important",
        .normal: "Normal",
        .all: "All"
    ]
}

// MARK: - Focus Persona Enum

@available(iOS 16.0, *)
enum TrinityFocusPersona: String, AppEnum {
    case trinity = "Trinity"
    case morpheus = "Morpheus"
    case oracle = "Oracle"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Persona"
    static var caseDisplayRepresentations: [TrinityFocusPersona: DisplayRepresentation] = [
        .trinity: "Trinity",
        .morpheus: "Morpheus",
        .oracle: "Oracle"
    ]
}

// MARK: - Focus Configuration

struct FocusConfiguration {
    let alertLevel: Any // TrinityAlertLevel at runtime
    let allowTransactionAlerts: Bool
    let allowPriceAlerts: Bool
    let quietMode: Bool
    let personaOverride: Any? // TrinityFocusPersona at runtime

    // MARK: - Derived Properties

    var shouldSuppressNonCritical: Bool {
        return quietMode
    }

    var notificationCategories: Set<String> {
        var categories: Set<String> = ["critical"]
        if allowTransactionAlerts { categories.insert("transaction") }
        if allowPriceAlerts { categories.insert("price_alert") }
        if !quietMode {
            categories.insert("portfolio_update")
            categories.insert("defi_opportunity")
        }
        return categories
    }
}

// MARK: - Focus Filter Store

final class FocusFilterStore {
    static let shared = FocusFilterStore()

    private(set) var currentConfiguration: FocusConfiguration?
    private var observers: [(FocusConfiguration) -> Void] = []

    func applyConfiguration(_ config: FocusConfiguration) {
        currentConfiguration = config
        notifyObservers(config)

        // Persist to UserDefaults for cross-process access
        UserDefaults.standard.set(config.quietMode, forKey: "trinity.focus.quietMode")
        UserDefaults.standard.set(config.allowTransactionAlerts, forKey: "trinity.focus.transactionAlerts")
        UserDefaults.standard.set(config.allowPriceAlerts, forKey: "trinity.focus.priceAlerts")
    }

    func observe(_ handler: @escaping (FocusConfiguration) -> Void) {
        observers.append(handler)
    }

    private func notifyObservers(_ config: FocusConfiguration) {
        for observer in observers {
            observer(config)
        }
    }

    /// Checks whether a notification category is allowed under current focus mode.
    func isNotificationAllowed(category: String) -> Bool {
        guard let config = currentConfiguration else { return true }
        return config.notificationCategories.contains(category)
    }
}
