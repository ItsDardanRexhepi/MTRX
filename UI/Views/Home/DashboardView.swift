// DashboardView.swift
// MTRX
//
// Portfolio dashboard with value hero, custom Path chart, allocation rings,
// active DeFi positions, and recent activity. No Charts framework.

import SwiftUI

// MARK: - Chart Period

enum ChartPeriod: String, CaseIterable {
    case oneHour = "1H"
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonth = "3M"
    case oneYear = "1Y"
    case all = "All"
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var isLoaded = false
    @State private var selectedPeriod: ChartPeriod = .oneDay

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    portfolioHeroSection
                        .mtrxFadeInFromBottom(isVisible: isLoaded, delay: 0)

                    chartSection
                        .mtrxFadeInFromBottom(isVisible: isLoaded, delay: 0.08)

                    allocationSection
                        .mtrxFadeInFromBottom(isVisible: isLoaded, delay: 0.16)

                    positionsSection
                        .mtrxFadeInFromBottom(isVisible: isLoaded, delay: 0.24)

                    recentActivitySection
                        .mtrxFadeInFromBottom(isVisible: isLoaded, delay: 0.32)

                    Spacer(minLength: Spacing.xxl)
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.md)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(Motion.springDefault) {
                        isLoaded = true
                    }
                }
            }
        }
    }

    // MARK: - Portfolio Hero

    private var portfolioHeroSection: some View {
        VStack(spacing: Spacing.sm) {
            Text("Total Portfolio")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)

            MtrxAnimatedValue(value: walletManager.totalPortfolioValue)

            portfolioChangeRow
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }

    private var portfolioChangeRow: some View {
        HStack(spacing: Spacing.sm) {
            let isUp = walletManager.portfolioChange24h >= 0

            Image(systemName: isUp ? Symbols.trendUp : Symbols.trendDown)
                .font(.system(size: 12, weight: .bold))

            Text(String(format: "%@%.2f%%", isUp ? "+" : "", walletManager.portfolioChange24h))
                .font(.mtrxCaptionBold)

            Text(String(format: "(%@$%.2f)", isUp ? "+" : "-", abs(walletManager.portfolioChangeAbsolute)))
                .font(.mtrxCaption1)
        }
        .foregroundStyle(walletManager.portfolioChange24h >= 0 ? Color.priceUp : Color.priceDown)
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack(spacing: Spacing.md) {
            MiniChartView(
                dataPoints: chartDataForPeriod(selectedPeriod),
                lineColor: .accentPrimary,
                fillColor: .accentPrimary
            )
            .frame(height: 160)
            .mtrxCardStyle()

            // Period chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(ChartPeriod.allCases, id: \.self) { period in
                        MtrxChip(
                            label: period.rawValue,
                            isSelected: selectedPeriod == period
                        ) {
                            withAnimation(Motion.springSnappy) {
                                selectedPeriod = period
                            }
                            MtrxHaptics.selection()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Allocation Section

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            MtrxSectionHeader(title: "Allocation")

            HStack(spacing: Spacing.md) {
                AllocationItem(
                    label: "Tokens",
                    progress: 0.55,
                    color: .accentPrimary
                )
                AllocationItem(
                    label: "DeFi",
                    progress: 0.25,
                    color: .trinityPrimary
                )
                AllocationItem(
                    label: "NFTs",
                    progress: 0.12,
                    color: .accentTertiary
                )
                AllocationItem(
                    label: "Staking",
                    progress: 0.08,
                    color: .statusSuccess
                )
            }
            .frame(maxWidth: .infinity)
        }
        .mtrxCardStyle()
    }

    // MARK: - Positions Section

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            MtrxSectionHeader(title: "Active Positions")

            if walletManager.defiPositions.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.chartPie,
                    title: "No Positions",
                    message: "Your active DeFi positions will appear here."
                )
                .frame(height: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(walletManager.defiPositions.enumerated()), id: \.element.id) { index, position in
                        DeFiPositionRow(position: position)

                        if index < walletManager.defiPositions.count - 1 {
                            MtrxDivider()
                                .padding(.leading, Spacing.Size.avatarMedium + Spacing.ms)
                        }
                    }
                }
            }
        }
        .mtrxCardStyle()
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            MtrxSectionHeader(title: "Recent Activity", action: {}, actionLabel: "View All")

            if walletManager.transactions.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.transaction,
                    title: "No Activity",
                    message: "Your recent transactions will appear here."
                )
                .frame(height: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(walletManager.transactions.prefix(4).enumerated()), id: \.element.id) { index, tx in
                        TransactionActivityRow(transaction: tx)

                        if index < min(walletManager.transactions.count, 4) - 1 {
                            MtrxDivider()
                                .padding(.leading, Spacing.Size.avatarMedium + Spacing.ms)
                        }
                    }
                }
            }
        }
        .mtrxCardStyle()
    }

    // MARK: - Chart Seed Data

    private func chartDataForPeriod(_ period: ChartPeriod) -> [CGFloat] {
        switch period {
        case .oneHour:
            return [0.52, 0.54, 0.53, 0.55, 0.56, 0.54, 0.57, 0.59, 0.58, 0.60,
                    0.61, 0.59, 0.62, 0.63, 0.61, 0.64, 0.65, 0.63, 0.66, 0.67,
                    0.65, 0.68, 0.69, 0.70, 0.68, 0.71, 0.72, 0.70, 0.73, 0.74,
                    0.72, 0.75, 0.76, 0.74, 0.77, 0.78, 0.76, 0.79, 0.80, 0.78,
                    0.81, 0.82, 0.80, 0.83, 0.84, 0.82, 0.85, 0.86]
        case .oneDay:
            return [0.45, 0.47, 0.44, 0.48, 0.50, 0.52, 0.49, 0.53, 0.55, 0.54,
                    0.56, 0.58, 0.55, 0.59, 0.61, 0.60, 0.63, 0.62, 0.65, 0.64,
                    0.67, 0.66, 0.69, 0.68, 0.71, 0.70, 0.73, 0.72, 0.75, 0.74,
                    0.77, 0.76, 0.79, 0.78, 0.81, 0.80, 0.83, 0.82, 0.85, 0.84,
                    0.87, 0.86, 0.89, 0.88, 0.90, 0.88, 0.91, 0.92]
        case .oneWeek:
            return [0.30, 0.35, 0.33, 0.40, 0.38, 0.45, 0.42, 0.48, 0.46, 0.52,
                    0.50, 0.55, 0.53, 0.58, 0.55, 0.60, 0.57, 0.63, 0.60, 0.65,
                    0.62, 0.68, 0.65, 0.70, 0.67, 0.72, 0.69, 0.74, 0.71, 0.76,
                    0.73, 0.78, 0.75, 0.80, 0.77, 0.82, 0.79, 0.84, 0.81, 0.86,
                    0.83, 0.88, 0.85, 0.90, 0.87, 0.92, 0.89, 0.94]
        case .oneMonth:
            return [0.20, 0.25, 0.22, 0.30, 0.28, 0.35, 0.32, 0.38, 0.36, 0.42,
                    0.40, 0.45, 0.43, 0.50, 0.48, 0.55, 0.52, 0.58, 0.55, 0.62,
                    0.60, 0.65, 0.62, 0.68, 0.65, 0.70, 0.68, 0.73, 0.70, 0.75,
                    0.72, 0.78, 0.75, 0.80, 0.77, 0.82, 0.79, 0.85, 0.82, 0.87,
                    0.84, 0.89, 0.86, 0.91, 0.88, 0.93, 0.90, 0.95]
        case .threeMonth:
            return [0.10, 0.18, 0.15, 0.25, 0.22, 0.30, 0.27, 0.35, 0.32, 0.38,
                    0.35, 0.42, 0.40, 0.48, 0.45, 0.52, 0.50, 0.55, 0.52, 0.58,
                    0.55, 0.62, 0.60, 0.65, 0.62, 0.68, 0.65, 0.72, 0.70, 0.75,
                    0.72, 0.78, 0.75, 0.82, 0.80, 0.85, 0.82, 0.88, 0.85, 0.90,
                    0.87, 0.92, 0.89, 0.94, 0.91, 0.95, 0.93, 0.97]
        case .oneYear:
            return [0.05, 0.10, 0.08, 0.15, 0.12, 0.20, 0.18, 0.25, 0.22, 0.30,
                    0.28, 0.35, 0.32, 0.38, 0.35, 0.42, 0.40, 0.48, 0.45, 0.52,
                    0.50, 0.58, 0.55, 0.62, 0.60, 0.68, 0.65, 0.72, 0.70, 0.78,
                    0.75, 0.82, 0.80, 0.85, 0.82, 0.88, 0.85, 0.90, 0.87, 0.92,
                    0.89, 0.94, 0.91, 0.95, 0.93, 0.96, 0.94, 0.97]
        case .all:
            return [0.02, 0.05, 0.03, 0.08, 0.06, 0.12, 0.10, 0.18, 0.15, 0.22,
                    0.20, 0.28, 0.25, 0.32, 0.30, 0.38, 0.35, 0.42, 0.40, 0.48,
                    0.45, 0.52, 0.50, 0.58, 0.55, 0.65, 0.62, 0.70, 0.68, 0.75,
                    0.72, 0.78, 0.75, 0.82, 0.80, 0.85, 0.82, 0.88, 0.85, 0.90,
                    0.87, 0.92, 0.89, 0.95, 0.92, 0.96, 0.94, 0.98]
        }
    }
}

// MARK: - Mini Chart View (Path-based, no Charts framework)

struct MiniChartView: View {
    let dataPoints: [CGFloat]
    var lineColor: Color = .accentPrimary
    var fillColor: Color = .accentPrimary
    var lineWidth: CGFloat = 2

    @State private var animationProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let points = normalizedPoints(in: CGSize(width: width, height: height))

            ZStack {
                // Gradient fill under the line
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: height))
                    path.addLine(to: first)
                    addSmoothCurve(to: &path, points: points)
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: last.x, y: height))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [fillColor.opacity(0.2), fillColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(Double(animationProgress))

                // Line stroke
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    addSmoothCurve(to: &path, points: points)
                }
                .trim(from: 0, to: animationProgress)
                .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                // Pulsing dot at end point
                if let last = points.last, animationProgress >= 1 {
                    Circle()
                        .fill(lineColor)
                        .frame(width: 8, height: 8)
                        .mtrxGlow(color: lineColor, radius: 10)
                        .mtrxPulse(isActive: true)
                        .position(last)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                animationProgress = 1
            }
        }
        .onChange(of: dataPoints.count) { _, _ in
            animationProgress = 0
            withAnimation(.easeOut(duration: 1.0)) {
                animationProgress = 1
            }
        }
    }

    // MARK: - Helpers

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard dataPoints.count > 1 else { return [] }
        let minVal = dataPoints.min() ?? 0
        let maxVal = dataPoints.max() ?? 1
        let range = maxVal - minVal
        let safeRange = range == 0 ? 1 : range
        let padding: CGFloat = 8

        return dataPoints.enumerated().map { index, value in
            let x = (CGFloat(index) / CGFloat(dataPoints.count - 1)) * size.width
            let normalized = (value - minVal) / safeRange
            let y = (size.height - padding * 2) * (1 - normalized) + padding
            return CGPoint(x: x, y: y)
        }
    }

    private func addSmoothCurve(to path: inout Path, points: [CGPoint]) {
        guard points.count > 1 else { return }
        for i in 1..<points.count {
            let current = points[i]
            let previous = points[i - 1]
            let midX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }
    }
}

// MARK: - Allocation Item

private struct AllocationItem: View {
    let label: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.sm) {
            MtrxProgressRing(
                progress: progress,
                size: 52,
                lineWidth: 5,
                color: color,
                showLabel: true
            )

            Text(label)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - DeFi Position Row

private struct DeFiPositionRow: View {
    let position: DeFiPositionItem

    var body: some View {
        HStack(spacing: Spacing.ms) {
            MtrxAvatar(
                symbol: position.icon,
                color: .accentPrimary,
                size: Spacing.Size.avatarMedium
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(position.protocol_)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Text(position.type)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(position.value))
                    .font(.mtrxMono)
                    .foregroundStyle(Color.labelPrimary)

                HStack(spacing: Spacing.xs) {
                    Text(String(format: "%.1f%% APY", position.apy))
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.priceUp)

                    if let health = position.healthFactor {
                        Circle()
                            .fill(healthColor(for: health))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func healthColor(for factor: Double) -> Color {
        if factor >= 2.0 { return .healthGood }
        if factor >= 1.5 { return .healthModerate }
        if factor >= 1.2 { return .healthWarning }
        return .healthCritical
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Transaction Activity Row

private struct TransactionActivityRow: View {
    let transaction: TransactionItem

    var body: some View {
        HStack(spacing: Spacing.ms) {
            // Type icon with colored circle background
            Image(systemName: transaction.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(transaction.iconColor)
                .frame(width: Spacing.Size.avatarMedium, height: Spacing.Size.avatarMedium)
                .background(transaction.iconColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Text(transaction.subtitle)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.amount)
                    .font(.mtrxMono)
                    .foregroundStyle(amountColor(for: transaction))
                    .lineLimit(1)

                Text(relativeTimestamp(transaction.timestamp))
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func amountColor(for tx: TransactionItem) -> Color {
        switch tx.type {
        case .receive: return .priceUp
        case .send: return .priceDown
        default: return .labelPrimary
        }
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview("Dashboard") {
    DashboardView()
        .environmentObject(WalletManager())
        .preferredColorScheme(.dark)
}
