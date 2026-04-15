// TokenDetailView.swift
// MTRX
//
// Token detail page — price, chart, holdings, market data, and recent transactions.

import SwiftUI

// MARK: - Token Detail View

struct TokenDetailView: View {
    let token: AppTokenBalance

    @State private var isLoading: Bool = true
    @State private var selectedPeriod: TokenChartPeriod = .oneDay
    @State private var showCopiedToast: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    private let contractAddress = "0x4F9e...8B2c7D1a3E5f"
    private let avgBuyPrice = "$3,102.45"

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                MtrxLoadingView(rows: 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sectionGap) {
                        priceHeaderSection
                        chartSection
                        holdingsCard
                        quickActionsRow
                        marketDataCard
                        recentTransactionsSection
                    }
                    .padding(.vertical, Spacing.contentPadding)
                }
            }
        }
        .background(MtrxGradientBackground(style: .primary))
        .navigationTitle(token.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                MtrxToast(message: "Address copied", icon: Symbols.copy, style: .success)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, Spacing.xl)
            }
        }
        .alert("MTRX", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                await MainActor.run {
                    withAnimation(Motion.springDefault) {
                        isLoading = false
                    }
                }
            }
        }
    }

    // MARK: - Price Header

    private var priceHeaderSection: some View {
        VStack(spacing: Spacing.md) {
            MtrxAvatar(text: token.symbol, color: token.iconColor, size: 56)

            Text(String(format: "$%.2f", token.priceUSD))
                .font(.mtrxMonoLarge)
                .foregroundStyle(Color.labelPrimary)

            HStack(spacing: Spacing.xs) {
                Image(systemName: token.change24h >= 0 ? Symbols.trendUp : Symbols.trendDown)
                    .font(.system(size: 14, weight: .bold))
                Text(String(format: "%@%.2f%%", token.change24h >= 0 ? "+" : "", token.change24h))
                    .font(.mtrxCalloutBold)
            }
            .foregroundStyle(token.change24h >= 0 ? Color.priceUp : Color.priceDown)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.md)
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack(spacing: Spacing.md) {
            TokenMiniChartView(color: token.iconColor)
                .frame(height: 160)
                .padding(.horizontal, Spacing.contentPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(TokenChartPeriod.allCases) { period in
                        MtrxChip(
                            label: period.label,
                            isSelected: selectedPeriod == period
                        ) {
                            withAnimation(Motion.springSnappy) {
                                selectedPeriod = period
                            }
                            MtrxHaptics.selection()
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Holdings Card

    private var holdingsCard: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Your Holdings")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)

                MtrxDivider()

                holdingsRow(label: "Balance", value: String(format: "%.4f %@", token.balance, token.symbol), font: .mtrxMono)
                holdingsRow(label: "USD Value", value: String(format: "$%.2f", token.valueUSD), font: .mtrxBodyBold)
                holdingsRow(label: "Avg. Buy Price", value: avgBuyPrice, font: .mtrxMono)

                MtrxDivider()

                pnlRow
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    private func holdingsRow(label: String, value: String, font: Font) -> some View {
        HStack {
            Text(label)
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value)
                .font(font)
                .foregroundStyle(Color.labelPrimary)
        }
    }

    private var pnlRow: some View {
        HStack {
            Text("P&L")
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            HStack(spacing: Spacing.xs) {
                Image(systemName: token.change24h >= 0 ? Symbols.trendUp : Symbols.trendDown)
                    .font(.system(size: 12, weight: .bold))
                Text(String(format: "%@%.2f%%", token.change24h >= 0 ? "+" : "", token.change24h))
                    .font(.mtrxCalloutBold)
            }
            .foregroundStyle(token.change24h >= 0 ? Color.priceUp : Color.priceDown)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: Spacing.xl) {
            quickActionButton(icon: Symbols.send, label: "Send") {
                MtrxHaptics.impact(.medium)
                alertMessage = "Send \(token.symbol) flow coming soon"
                showAlert = true
            }
            quickActionButton(icon: Symbols.receive, label: "Receive") {
                MtrxHaptics.impact(.medium)
                alertMessage = "Receive \(token.symbol) - share your wallet address"
                showAlert = true
            }
            quickActionButton(icon: Symbols.swap, label: "Swap") {
                MtrxHaptics.impact(.medium)
                alertMessage = "Swap \(token.symbol) flow coming soon"
                showAlert = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.contentPadding)
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 52, height: 52)
                    .background(Color.accentPrimary.opacity(0.1))
                    .clipShape(Circle())

                Text(label)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Market Data

    private var marketDataCard: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Market Data")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)

                MtrxDivider()

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Spacing.md),
                    GridItem(.flexible(), spacing: Spacing.md)
                ], spacing: Spacing.md) {
                    marketStatItem(title: "Market Cap", value: "$389.2B")
                    marketStatItem(title: "24h Volume", value: "$14.7B")
                    marketStatItem(title: "Circulating Supply", value: "120.2M")
                    marketStatItem(title: "Total Supply", value: "120.2M")
                }

                MtrxDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contract Address")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Text(contractAddress)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        UIPasteboard.general.string = contractAddress
                        MtrxHaptics.success()
                        withAnimation(Motion.springDefault) {
                            showCopiedToast = true
                        }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            await MainActor.run {
                                withAnimation(Motion.springDefault) {
                                    showCopiedToast = false
                                }
                            }
                        }
                    } label: {
                        Image(systemName: Symbols.copy)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.accentPrimary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text("Network")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    MtrxBadge(text: "Base", style: .accent)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    private func marketStatItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
            Text(value)
                .font(.mtrxHeadlineTabular)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Recent Transactions

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Recent Transactions", action: {
                alertMessage = "Full transaction history coming soon"
                showAlert = true
            })
            .padding(.horizontal, Spacing.contentPadding)

            MtrxCard(style: .standard) {
                VStack(spacing: 0) {
                    ForEach(Array(recentTxItems.enumerated()), id: \.element.id) { index, tx in
                        Button {
                            MtrxHaptics.selection()
                            alertMessage = "Transaction details: \(tx.title)"
                            showAlert = true
                        } label: {
                            transactionRow(tx)
                        }
                        .buttonStyle(.plain)

                        if index < recentTxItems.count - 1 {
                            MtrxDivider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    private func transactionRow(_ tx: TransactionItem) -> some View {
        HStack(spacing: Spacing.ms) {
            Image(systemName: tx.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tx.iconColor)
                .frame(width: 32, height: 32)
                .background(tx.iconColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.title)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Text(tx.subtitle)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.amount)
                    .font(.mtrxMono)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                Text(tx.timestamp.relativeFormatted)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    private var recentTxItems: [TransactionItem] {
        Array(TransactionItem.sampleData.prefix(3))
    }
}

// MARK: - Chart Period

private enum TokenChartPeriod: String, CaseIterable, Identifiable {
    case oneHour = "1H"
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case oneYear = "1Y"

    var id: String { rawValue }
    var label: String { rawValue }
}

// MARK: - Mini Chart

private struct TokenMiniChartView: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Area fill
                Path { path in
                    drawChartPath(path: &path, width: width, height: height)
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.25), color.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line stroke
                Path { path in
                    drawChartPath(path: &path, width: width, height: height)
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.5), radius: 4, y: 2)
            }
        }
    }

    private func drawChartPath(path: inout Path, width: CGFloat, height: CGFloat) {
        let points: [CGFloat] = [0.6, 0.45, 0.55, 0.35, 0.5, 0.3, 0.4, 0.25, 0.35, 0.2, 0.28, 0.22]
        let stepX = width / CGFloat(points.count - 1)

        path.move(to: CGPoint(x: 0, y: height * points[0]))

        for i in 1..<points.count {
            let currentX = stepX * CGFloat(i)
            let currentY = height * points[i]
            let previousX = stepX * CGFloat(i - 1)
            let previousY = height * points[i - 1]

            let controlX1 = previousX + (currentX - previousX) * 0.4
            let controlY1 = previousY
            let controlX2 = previousX + (currentX - previousX) * 0.6
            let controlY2 = currentY

            path.addCurve(
                to: CGPoint(x: currentX, y: currentY),
                control1: CGPoint(x: controlX1, y: controlY1),
                control2: CGPoint(x: controlX2, y: controlY2)
            )
        }
    }
}

// MARK: - Date Extension

private extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TokenDetailView(token: AppTokenBalance.sampleData[0])
    }
    .preferredColorScheme(.dark)
}
