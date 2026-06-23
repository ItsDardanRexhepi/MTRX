// PortfolioIntent.swift
// MTRX Apple Integration — AppIntents
// Check portfolio via Shortcuts

import AppIntents

// MARK: - Portfolio Summary Intent

struct PortfolioSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Portfolio"
    static var description = IntentDescription("Get a summary of your MTRX portfolio including holdings, P&L, and allocation")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Time Period", default: .today)
    var period: PortfolioPeriod

    @Parameter(title: "Include DeFi Positions", default: true)
    var includeDeFi: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Check portfolio for \(\.$period)") {
            \.$includeDeFi
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let portfolio = try await PortfolioAggregator.shared.fetchSummary(
            period: period,
            includeDeFi: includeDeFi
        )

        let summary = formatPortfolioSummary(portfolio)

        return .result(
            value: summary,
            dialog: IntentDialog(stringLiteral: summary)
        )
    }

    private func formatPortfolioSummary(_ portfolio: IntentPortfolioSnapshot) -> String {
        var lines: [String] = []
        lines.append("Portfolio Value: $\(portfolio.totalValueUSD)")
        lines.append("24h Change: \(portfolio.changePercent24h >= 0 ? "+" : "")\(portfolio.changePercent24h)%")
        lines.append("Top Holdings:")
        for holding in portfolio.topHoldings.prefix(5) {
            lines.append("  \(holding.symbol): \(holding.balance) ($\(holding.valueUSD))")
        }
        if portfolio.defiPositions > 0 {
            lines.append("DeFi Positions: \(portfolio.defiPositions)")
            lines.append("DeFi TVL: $\(portfolio.defiTVL)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Token Price Intent

struct TokenPriceIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Token Price"
    static var description = IntentDescription("Check the current price of any token")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Token Symbol")
    var symbol: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let price = try await PortfolioAggregator.shared.tokenPrice(symbol: symbol)
        return .result(value: "\(symbol): $\(price)")
    }
}

// MARK: - Portfolio Alert Intent

struct PortfolioAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Portfolio Alert"
    static var description = IntentDescription("Set a price or percentage change alert for a token")

    @Parameter(title: "Token Symbol")
    var symbol: String

    @Parameter(title: "Alert Type", default: .priceAbove)
    var alertType: PortfolioAlertType

    @Parameter(title: "Threshold Value")
    var threshold: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Alert when \(\.$symbol) \(\.$alertType) \(\.$threshold)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try await PortfolioAggregator.shared.setAlert(
            symbol: symbol,
            type: alertType,
            threshold: threshold
        )
        return .result(value: "Alert set: \(symbol) \(alertType.rawValue) $\(threshold)")
    }
}

// MARK: - Portfolio Period Enum

enum PortfolioPeriod: String, AppEnum {
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
    case year = "This Year"
    case allTime = "All Time"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Time Period"
    static var caseDisplayRepresentations: [PortfolioPeriod: DisplayRepresentation] = [
        .today: "Today",
        .week: "This Week",
        .month: "This Month",
        .year: "This Year",
        .allTime: "All Time"
    ]
}

// MARK: - Portfolio Alert Type Enum

enum PortfolioAlertType: String, AppEnum {
    case priceAbove = "price above"
    case priceBelow = "price below"
    case changeAbove = "change above"
    case changeBelow = "change below"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Alert Type"
    static var caseDisplayRepresentations: [PortfolioAlertType: DisplayRepresentation] = [
        .priceAbove: "Price Above",
        .priceBelow: "Price Below",
        .changeAbove: "Change Above",
        .changeBelow: "Change Below"
    ]
}

// MARK: - Portfolio Data Models

struct IntentPortfolioSnapshot {
    let totalValueUSD: String
    let changePercent24h: Double
    let topHoldings: [TokenHolding]
    let defiPositions: Int
    let defiTVL: String
}

struct TokenHolding {
    let symbol: String
    let balance: String
    let valueUSD: String
}

// MARK: - Portfolio Aggregator

final class PortfolioAggregator {
    static let shared = PortfolioAggregator()

    func fetchSummary(period: PortfolioPeriod, includeDeFi: Bool) async throws -> IntentPortfolioSnapshot {
        // No fabricated portfolio. Returning hardcoded $0.00 would tell a funded user their
        // holdings are empty — a false reading presented as real. Live portfolio data isn't
        // wired to this Siri path yet, so fail honestly instead of inventing a balance.
        throw NSError(domain: "MTRX.Intent", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Your portfolio isn't available from Siri in this build yet. Open MTRX to see it."])
    }

    func tokenPrice(symbol: String) async throws -> String {
        // No hardcoded "0.00" — that reports a fabricated number as the real market price.
        // Live prices aren't wired to this Siri path yet; fail honestly.
        throw NSError(domain: "MTRX.Intent", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Live token prices aren't available in this build yet."])
    }

    func setAlert(symbol: String, type: PortfolioAlertType, threshold: Double) async throws {
        // An empty body here let perform() report "Alert set" while nothing was stored or
        // scheduled — the user would rely on an alert that never fires. Fail honestly until a
        // real alert store + monitor exists.
        throw NSError(domain: "MTRX.Intent", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Portfolio alerts aren't available in this build yet. Nothing was set."])
    }
}
