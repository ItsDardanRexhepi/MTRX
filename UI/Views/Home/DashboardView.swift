// DashboardView.swift
// MTRX
//
// Personal dashboard with portfolio value, positions, transactions, alerts, and charts.

import SwiftUI
import Charts

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var selectedTimeRange: TimeRange = .day
    @State private var portfolioHistory: [PortfolioDataPoint] = PortfolioDataPoint.sampleData
    @State private var positions: [PositionItem] = PositionItem.sampleData
    @State private var recentTransactions: [TransactionItem] = TransactionItem.sampleData
    @State private var alerts: [AlertItem] = AlertItem.sampleData
    @State private var isRefreshing: Bool = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sectionGap) {
                portfolioSummarySection
                portfolioChartSection
                timeRangePicker
                activeAlertsSection
                positionsSection
                recentTransactionsSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await refreshDashboard()
        }
        .navigationTitle("Dashboard")
    }

    // MARK: - Portfolio Summary

    private var portfolioSummarySection: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Portfolio Value")
                        .font(.mtrxSubheadline)
                        .foregroundStyle(Color.labelSecondary)

                    Text("$124,567.89")
                        .font(.mtrxMonoLarge)
                        .foregroundStyle(Color.labelPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.trendUp)
                        Text("+$2,891.45")
                    }
                    .font(.mtrxHeadlineTabular)
                    .foregroundStyle(Color.priceUp)

                    Text("+2.37% today")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.priceUp)
                }
            }

            HStack(spacing: Spacing.md) {
                StatCard(title: "Positions", value: "12", icon: Symbols.chartPie)
                StatCard(title: "Yield", value: "8.4%", icon: Symbols.trendUp)
                StatCard(title: "Health", value: "Good", icon: Symbols.shieldCheck)
            }
        }
        .mtrxContentPadding()
    }

    // MARK: - Portfolio Chart

    private var portfolioChartSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Chart(portfolioHistory) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(Color.accentPrimary)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentPrimary.opacity(0.3), Color.accentPrimary.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel()
                        .font(.mtrxCaption2)
                }
            }
            .frame(height: 200)
        }
        .mtrxContentPadding()
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(Motion.springSnappy) {
                        selectedTimeRange = range
                    }
                } label: {
                    Text(range.label)
                        .font(.mtrxCaptionBold)
                        .padding(.horizontal, Spacing.chipHorizontal)
                        .padding(.vertical, Spacing.chipVertical)
                        .background(
                            selectedTimeRange == range
                                ? Color.accentPrimary
                                : Color.surfaceOverlay
                        )
                        .foregroundStyle(
                            selectedTimeRange == range
                                ? .white
                                : Color.labelPrimary
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Active Alerts

    @ViewBuilder
    private var activeAlertsSection: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Active Alerts", icon: Symbols.alertWarning)

                ForEach(alerts) { alert in
                    AlertRow(alert: alert)
                }
            }
            .mtrxContentPadding()
        }
    }

    // MARK: - Positions

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Positions", icon: Symbols.chartPie, trailing: {
                NavigationLink("See All") { Text("All Positions") }
                    .font(.mtrxCaptionBold)
            })

            ForEach(positions) { position in
                PositionRow(position: position)
            }
        }
        .mtrxContentPadding()
    }

    // MARK: - Recent Transactions

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Recent Transactions", icon: Symbols.transaction, trailing: {
                NavigationLink("See All") { Text("All Transactions") }
                    .font(.mtrxCaptionBold)
            })

            ForEach(recentTransactions) { tx in
                TransactionRow(transaction: tx)
            }
        }
        .mtrxContentPadding()
    }

    // MARK: - Refresh

    private func refreshDashboard() async {
        isRefreshing = true
        // Simulate network refresh
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isRefreshing = false
    }
}

// MARK: - Supporting Components

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentPrimary)
            Text(value)
                .font(.mtrxHeadline)
            Text(title)
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    let icon: String
    var trailing: (() -> Trailing)?

    init(title: String, icon: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.mtrxHeadline)
            Spacer()
            trailing?()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, icon: String) {
        self.title = title
        self.icon = icon
        self.trailing = nil
    }
}

// MARK: - Row Components

struct PositionRow: View {
    let position: PositionItem

    var body: some View {
        HStack {
            Circle()
                .fill(Color.accentPrimary.opacity(0.2))
                .frame(width: Spacing.Size.avatarSmall, height: Spacing.Size.avatarSmall)
                .overlay(
                    Text(position.symbol.prefix(2))
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.accentPrimary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(position.name)
                    .font(.mtrxBodyBold)
                Text(position.protocol_)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(position.value)
                    .font(.mtrxBodyTabular)
                Text(position.apy)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.priceUp)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct TransactionRow: View {
    let transaction: TransactionItem

    var body: some View {
        HStack {
            Image(systemName: transaction.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: Spacing.Size.avatarSmall, height: Spacing.Size.avatarSmall)
                .background(Color.accentPrimary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .font(.mtrxBodyBold)
                Text(transaction.subtitle)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.amount)
                    .font(.mtrxBodyTabular)
                Text(transaction.timestamp)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct AlertRow: View {
    let alert: AlertItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: Symbols.alertWarning)
                .foregroundStyle(alert.severity == .critical ? Color.statusError : Color.statusWarning)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.mtrxBodyBold)
                Text(alert.message)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            Button("Action") { }
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.accentPrimary)
        }
        .padding(Spacing.sm)
        .background(alert.severity == .critical ? Color.statusError.opacity(0.1) : Color.statusWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

// MARK: - Data Models

enum TimeRange: CaseIterable {
    case hour, day, week, month, year, all

    var label: String {
        switch self {
        case .hour: "1H"
        case .day: "1D"
        case .week: "1W"
        case .month: "1M"
        case .year: "1Y"
        case .all: "All"
        }
    }
}

struct PortfolioDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double

    static let sampleData: [PortfolioDataPoint] = (0..<24).map { i in
        PortfolioDataPoint(
            date: Calendar.current.date(byAdding: .hour, value: -23 + i, to: Date())!,
            value: 120000 + Double.random(in: -5000...5000)
        )
    }
}

struct PositionItem: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let protocol_: String
    let value: String
    let apy: String

    static let sampleData: [PositionItem] = [
        PositionItem(name: "ETH Staking", symbol: "ETH", protocol_: "Lido", value: "$45,230", apy: "+4.2% APY"),
        PositionItem(name: "USDC Lending", symbol: "USDC", protocol_: "Aave", value: "$32,100", apy: "+6.8% APY"),
        PositionItem(name: "ETH/USDC LP", symbol: "LP", protocol_: "Uniswap", value: "$18,500", apy: "+12.3% APY"),
    ]
}

struct TransactionItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let amount: String
    let timestamp: String
    let icon: String

    static let sampleData: [TransactionItem] = [
        TransactionItem(title: "Swap", subtitle: "ETH → USDC", amount: "-0.5 ETH", timestamp: "2m ago", icon: Symbols.swap),
        TransactionItem(title: "Received", subtitle: "From 0x1a2b...3c4d", amount: "+1,200 USDC", timestamp: "1h ago", icon: Symbols.receive),
        TransactionItem(title: "Staked", subtitle: "Lido stETH", amount: "-2.0 ETH", timestamp: "3h ago", icon: Symbols.stake),
    ]
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: AlertSeverity

    enum AlertSeverity { case warning, critical }

    static let sampleData: [AlertItem] = [
        AlertItem(title: "Low Collateral", message: "ETH/USDC position at 135% ratio", severity: .warning),
    ]
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DashboardView()
            .environmentObject(WalletManager())
    }
}
