// WidgetSharedStore.swift
// MTRX — App ⇄ Widget data bridge
//
// Widgets run out-of-process and cannot read the app's in-memory
// WalletManager. The app publishes a real snapshot of its current state to a
// shared App Group container; the widget timeline providers read it. When no
// snapshot has been published (App Group not yet enabled, or app never
// launched), providers fall back to an honest empty/placeholder state — the
// widget NEVER invents its own numbers.
//
// TARGET MEMBERSHIP: this file must belong to BOTH the app target (publisher)
// and the widget extension target (reader). The App Group below must be
// enabled on both targets' entitlements and registered in the developer
// portal before data actually crosses the process boundary.

import Foundation
import WidgetKit

// MARK: - Snapshots (Codable mirrors of the app's real state)

struct WidgetPortfolioSnapshot: Codable {
    let updatedAt: Date
    let totalValue: String
    let change24h: String
    let changePercent: String
    let isPositive: Bool
    let tokens: [Token]

    struct Token: Codable {
        let symbol: String
        let value: String
        let change: String
        let isUp: Bool
    }
}

struct WidgetPositionsSnapshot: Codable {
    let updatedAt: Date
    let totalValue: String
    let positions: [Position]

    struct Position: Codable {
        let name: String
        let healthFactor: Double
        let value: String
        let apy: String
    }
}

struct WidgetContractsSnapshot: Codable {
    let updatedAt: Date
    let activeCount: Int
    let pendingCount: Int
    let nextDeadline: String?
    let recentActivity: String?
}

struct WidgetPaymentsSnapshot: Codable {
    let updatedAt: Date
    let nextPayment: String?
    let nextPaymentAmount: String?
    let nextPaymentDate: String?
    let subscriptionRenewals: Int
}

// MARK: - Shared Store

enum WidgetSharedStore {

    /// App Group shared between the app and its widget extension.
    /// Enable on both targets + register in the developer portal.
    static let appGroupID = "group.com.opnmatrx.mtrx"

    /// Widget kinds (must match each Widget's `kind`).
    enum Kind {
        static let portfolio = "PortfolioWidget"
        static let positions = "PositionsWidget"
        static let contracts = "ContractsWidget"
        static let payments  = "PaymentsWidget"
    }

    private enum Key {
        static let portfolio = "widget.snapshot.portfolio"
        static let positions = "widget.snapshot.positions"
        static let contracts = "widget.snapshot.contracts"
        static let payments  = "widget.snapshot.payments"
    }

    /// nil if the App Group isn't available yet — callers degrade to honest empty state.
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    // MARK: Generic

    private static func write<T: Encodable>(_ value: T, key: String, reloadKind: String) {
        guard let defaults, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: reloadKind)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let defaults, let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Typed accessors

    static func save(_ s: WidgetPortfolioSnapshot) { write(s, key: Key.portfolio, reloadKind: Kind.portfolio) }
    static func portfolio() -> WidgetPortfolioSnapshot? { read(WidgetPortfolioSnapshot.self, key: Key.portfolio) }

    static func save(_ s: WidgetPositionsSnapshot) { write(s, key: Key.positions, reloadKind: Kind.positions) }
    static func positions() -> WidgetPositionsSnapshot? { read(WidgetPositionsSnapshot.self, key: Key.positions) }

    static func save(_ s: WidgetContractsSnapshot) { write(s, key: Key.contracts, reloadKind: Kind.contracts) }
    static func contracts() -> WidgetContractsSnapshot? { read(WidgetContractsSnapshot.self, key: Key.contracts) }

    static func save(_ s: WidgetPaymentsSnapshot) { write(s, key: Key.payments, reloadKind: Kind.payments) }
    static func payments() -> WidgetPaymentsSnapshot? { read(WidgetPaymentsSnapshot.self, key: Key.payments) }
}
