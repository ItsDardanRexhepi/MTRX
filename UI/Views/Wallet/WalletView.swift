// WalletView.swift
// MTRX
//
// Full wallet management: portfolio overview, tokens, NFTs, DeFi positions, activity.

import SwiftUI

// MARK: - Wallet View

struct WalletView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var selectedSegment: WalletSegment = .tokens
    @State private var isVisible = false
    @State private var showSendSheet = false
    @State private var showReceiveSheet = false
    @State private var showSwapSheet = false
    @State private var tokenSortOrder: TokenSortOrder = .byValue
    @State private var activityFilter: ActivityFilter = .all

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    portfolioHeader
                    quickActions
                    segmentPicker
                    segmentContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                withAnimation(Motion.springDefault) {
                    isVisible = true
                }
            }
        }
        .sheet(isPresented: $showSendSheet) {
            SendView()
                .environmentObject(walletManager)
        }
        .sheet(isPresented: $showReceiveSheet) {
            ReceiveView()
        }
        .sheet(isPresented: $showSwapSheet) {
            SwapView()
                .environmentObject(walletManager)
        }
    }

    // MARK: - Portfolio Header

    private var portfolioHeader: some View {
        VStack(spacing: Spacing.ms) {
            Text("Total Balance")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)

            MtrxAnimatedValue(
                value: walletManager.totalPortfolioValue,
                prefix: "$",
                decimals: 2,
                font: .mtrxMonoLarge,
                color: .labelPrimary
            )

            change24hRow

            miniChart
                .padding(.top, Spacing.xs)
        }
        .padding(.top, Spacing.lg)
        .padding(.horizontal, Spacing.contentPadding)
        .mtrxFadeInFromBottom(isVisible: isVisible)
    }

    private var change24hRow: some View {
        HStack(spacing: Spacing.sm) {
            let isPositive = walletManager.portfolioChange24h >= 0

            Image(systemName: isPositive ? Symbols.trendUp : Symbols.trendDown)
                .font(.system(size: 12, weight: .bold))

            Text(String(format: "%@%.2f%%", isPositive ? "+" : "", walletManager.portfolioChange24h))
                .font(.mtrxMonoSmall)

            Text(String(format: "(%@$%.2f)", isPositive ? "+" : "-", abs(walletManager.portfolioChangeAbsolute)))
                .font(.mtrxMonoSmall)
                .foregroundStyle(isPositive ? Color.priceUp.opacity(0.7) : Color.priceDown.opacity(0.7))
        }
        .foregroundStyle(walletManager.portfolioChange24h >= 0 ? Color.priceUp : Color.priceDown)
    }

    // MARK: - Mini Chart (24h)

    private var miniChart: some View {
        MtrxCard(style: .glass) {
            chartPath
                .stroke(Color.accentPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .fill(
                    LinearGradient(
                        colors: [Color.accentPrimary.opacity(0.2), Color.accentPrimary.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 60)
        }
    }

    private var chartPath: Path {
        Path { path in
            let points: [CGFloat] = [0.4, 0.35, 0.5, 0.45, 0.55, 0.6, 0.52, 0.65, 0.58, 0.7, 0.68, 0.75]
            guard points.count > 1 else { return }

            let width: CGFloat = UIScreen.main.bounds.width - (Spacing.contentPadding * 2) - (Spacing.cardPadding * 2)
            let height: CGFloat = 60
            let stepX = width / CGFloat(points.count - 1)

            path.move(to: CGPoint(x: 0, y: height * (1 - points[0])))
            for i in 1..<points.count {
                let x = stepX * CGFloat(i)
                let y = height * (1 - points[i])
                let prevX = stepX * CGFloat(i - 1)
                let prevY = height * (1 - points[i - 1])
                let controlX1 = prevX + stepX * 0.4
                let controlX2 = x - stepX * 0.4
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: controlX1, y: prevY),
                    control2: CGPoint(x: controlX2, y: y)
                )
            }

            // Close the fill area
            path.addLine(to: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.closeSubpath()
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: Spacing.lg) {
            quickActionButton(icon: Symbols.send, label: "Send") {
                MtrxHaptics.impact(.medium)
                showSendSheet = true
            }
            quickActionButton(icon: Symbols.receive, label: "Receive") {
                MtrxHaptics.impact(.medium)
                showReceiveSheet = true
            }
            quickActionButton(icon: Symbols.swap, label: "Swap") {
                MtrxHaptics.impact(.medium)
                showSwapSheet = true
            }
            quickActionButton(icon: Symbols.stake, label: "Stake") {
                MtrxHaptics.impact(.medium)
            }
        }
        .padding(.vertical, Spacing.lg)
        .mtrxFadeInFromBottom(isVisible: isVisible, delay: 0.1)
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.accentPrimary.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                }
                Text(label)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Segment Picker

    private var segmentPicker: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(WalletSegment.allCases, id: \.self) { segment in
                Button {
                    MtrxHaptics.selection()
                    withAnimation(Motion.springSnappy) {
                        selectedSegment = segment
                    }
                } label: {
                    Text(segment.rawValue)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(selectedSegment == segment ? .white : Color.labelSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            Capsule()
                                .fill(selectedSegment == segment ? Color.accentPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.xs)
        .background(Color.surfaceOverlay.opacity(0.5))
        .clipShape(Capsule())
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.bottom, Spacing.md)
        .mtrxFadeInFromBottom(isVisible: isVisible, delay: 0.15)
    }

    // MARK: - Segment Content

    @ViewBuilder
    private var segmentContent: some View {
        switch selectedSegment {
        case .tokens:
            tokensTab
        case .nfts:
            nftsTab
        case .defi:
            defiTab
        case .activity:
            activityTab
        }
    }

    // MARK: - Tokens Tab

    private var tokensTab: some View {
        VStack(spacing: 0) {
            tokensSortHeader
            LazyVStack(spacing: 0) {
                let sorted = sortedTokens
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, token in
                    Button {
                        MtrxHaptics.impact(.light)
                    } label: {
                        tokenRow(token)
                    }
                    .buttonStyle(.plain)
                    .mtrxStaggeredAppearance(index: index, isVisible: isVisible)

                    if index < sorted.count - 1 {
                        MtrxDivider()
                            .padding(.leading, 68)
                    }
                }
            }

            tokensFooter
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    private var tokensSortHeader: some View {
        HStack {
            Text("Assets")
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)
            Spacer()
            Menu {
                Button { tokenSortOrder = .byValue } label: {
                    Label("By Value", systemImage: "dollarsign.circle")
                }
                Button { tokenSortOrder = .byChange } label: {
                    Label("By 24h Change", systemImage: Symbols.chartLine)
                }
                Button { tokenSortOrder = .alphabetical } label: {
                    Label("Alphabetical", systemImage: "textformat.abc")
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: Symbols.sort)
                        .font(.system(size: 14, weight: .medium))
                    Text(tokenSortOrder.label)
                        .font(.mtrxCaptionBold)
                }
                .foregroundStyle(Color.accentPrimary)
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    private var sortedTokens: [AppTokenBalance] {
        switch tokenSortOrder {
        case .byValue:
            return walletManager.tokens.sorted { $0.valueUSD > $1.valueUSD }
        case .byChange:
            return walletManager.tokens.sorted { abs($0.change24h) > abs($1.change24h) }
        case .alphabetical:
            return walletManager.tokens.sorted { $0.name < $1.name }
        }
    }

    private func tokenRow(_ token: AppTokenBalance) -> some View {
        HStack(spacing: Spacing.ms) {
            MtrxAvatar(text: token.symbol, color: token.iconColor, size: Spacing.Size.avatarMedium)

            VStack(alignment: .leading, spacing: 2) {
                Text(token.name)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Text(token.symbol)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTokenBalance(token.balance, symbol: token.symbol))
                    .font(.mtrxMono)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: Spacing.xs) {
                    Text(formatUSD(token.valueUSD))
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelSecondary)

                    MtrxBadge(
                        text: String(format: "%@%.1f%%", token.change24h >= 0 ? "+" : "", token.change24h),
                        style: token.change24h >= 0 ? .success : .error
                    )
                }
            }
        }
        .padding(.vertical, Spacing.listRowVertical)
        .contentShape(Rectangle())
    }

    private var tokensFooter: some View {
        HStack {
            Text("Total")
                .font(.mtrxBodyBold)
                .foregroundStyle(Color.labelPrimary)
            Spacer()
            Text(formatUSD(walletManager.totalPortfolioValue))
                .font(.mtrxMonoMedium)
                .foregroundStyle(Color.labelPrimary)
        }
        .padding(.vertical, Spacing.md)
        .padding(.top, Spacing.sm)
    }

    // MARK: - NFTs Tab

    private var nftsTab: some View {
        Group {
            if walletManager.nfts.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.nft,
                    title: "No NFTs Yet",
                    message: "Your collected NFTs and digital assets will appear here.",
                    actionLabel: "Browse Marketplace"
                ) {
                    // No-op: navigate to marketplace handled elsewhere.
                }
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Spacing.ms),
                        GridItem(.flexible(), spacing: Spacing.ms)
                    ],
                    spacing: Spacing.ms
                ) {
                    ForEach(Array(walletManager.nfts.enumerated()), id: \.element.id) { index, nft in
                        Button {
                            MtrxHaptics.impact(.light)
                        } label: {
                            nftCard(nft)
                        }
                        .buttonStyle(.plain)
                        .mtrxStaggeredAppearance(index: index, isVisible: isVisible)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    private func nftCard(_ nft: NFTItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Gradient art placeholder
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: nft.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 140)
                .overlay(
                    Image(systemName: Symbols.nft)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(nft.name)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(nft.collection)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack {
                Text(String(format: "%.2f ETH", nft.floorPrice))
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color.labelPrimary)

                Spacer()

                MtrxBadge(text: nft.rarity, style: rarityBadgeStyle(nft.rarity))
            }
        }
        .mtrxCardStyle()
    }

    private func rarityBadgeStyle(_ rarity: String) -> MtrxBadge.BadgeStyle {
        switch rarity.lowercased() {
        case "legendary": return .warning
        case "epic": return .accent
        case "rare": return .info
        default: return .neutral
        }
    }

    // MARK: - DeFi Tab

    private var defiTab: some View {
        VStack(spacing: Spacing.md) {
            // Total DeFi summary
            let totalDefi = walletManager.defiPositions.reduce(0.0) { $0 + $1.value }
            HStack {
                Text("Total DeFi Value")
                    .font(.mtrxSubheadline)
                    .foregroundStyle(Color.labelSecondary)
                Spacer()
                Text(formatUSD(totalDefi))
                    .font(.mtrxMonoMedium)
                    .foregroundStyle(Color.labelPrimary)
            }
            .padding(.horizontal, Spacing.contentPadding)

            ForEach(Array(walletManager.defiPositions.enumerated()), id: \.element.id) { index, position in
                defiPositionCard(position)
                    .padding(.horizontal, Spacing.contentPadding)
                    .mtrxStaggeredAppearance(index: index, isVisible: isVisible)
            }
        }
    }

    private func defiPositionCard(_ position: DeFiPositionItem) -> some View {
        MtrxCard(style: .standard, accentEdge: .leading) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    Image(systemName: position.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(position.protocol_)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(position.type)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    Text(formatUSD(position.value))
                        .font(.mtrxMono)
                        .foregroundStyle(Color.labelPrimary)
                }

                MtrxDivider()

                HStack {
                    // APY
                    HStack(spacing: Spacing.xs) {
                        Text("APY")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Text(String(format: "%.1f%%", position.apy))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.priceUp)
                    }

                    Spacer()

                    // Health factor gauge
                    if let health = position.healthFactor {
                        HStack(spacing: Spacing.xs) {
                            Text("Health")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                            healthGauge(health)
                        }
                    }

                    Spacer()

                    Button {
                        MtrxHaptics.impact(.light)
                    } label: {
                        Text("Manage")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
                }
            }
        }
    }

    private func healthGauge(_ factor: Double) -> some View {
        let color = healthColor(factor)
        return HStack(spacing: 3) {
            // Mini bar gauge
            GeometryReader { _ in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: max(4, min(48, CGFloat(factor / 3.0) * 48)))
                }
            }
            .frame(width: 48, height: 6)

            Text(String(format: "%.1f", factor))
                .font(.mtrxMonoSmall)
                .foregroundStyle(color)
        }
    }

    private func healthColor(_ factor: Double) -> Color {
        switch factor {
        case 2.5...: return .healthGood
        case 1.5..<2.5: return .healthModerate
        case 1.0..<1.5: return .healthWarning
        default: return .healthCritical
        }
    }

    // MARK: - Activity Tab

    private var activityTab: some View {
        VStack(spacing: Spacing.md) {
            activityFilterChips

            LazyVStack(spacing: 0) {
                let filtered = filteredTransactions
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, tx in
                    transactionRow(tx)
                        .mtrxStaggeredAppearance(index: index, isVisible: isVisible)

                    if index < filtered.count - 1 {
                        MtrxDivider()
                            .padding(.leading: 68)
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            Button {
                MtrxHaptics.impact(.light)
            } label: {
                Text("Load More")
            }
            .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
            .padding(.bottom, Spacing.xl)
        }
    }

    private var activityFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(ActivityFilter.allCases, id: \.self) { filter in
                    MtrxChip(
                        label: filter.rawValue,
                        isSelected: activityFilter == filter
                    ) {
                        MtrxHaptics.selection()
                        withAnimation(Motion.springSnappy) {
                            activityFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    private var filteredTransactions: [TransactionItem] {
        switch activityFilter {
        case .all:
            return walletManager.transactions
        case .sent:
            return walletManager.transactions.filter { $0.type == .send }
        case .received:
            return walletManager.transactions.filter { $0.type == .receive }
        case .swaps:
            return walletManager.transactions.filter { $0.type == .swap }
        case .contracts:
            return walletManager.transactions.filter { $0.type == .contract || $0.type == .approve }
        }
    }

    private func transactionRow(_ tx: TransactionItem) -> some View {
        HStack(spacing: Spacing.ms) {
            ZStack {
                Circle()
                    .fill(tx.iconColor.opacity(0.12))
                    .frame(width: Spacing.Size.avatarMedium, height: Spacing.Size.avatarMedium)
                Image(systemName: tx.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tx.iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.title)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Text(tx.subtitle)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.amount)
                    .font(.mtrxMono)
                    .foregroundStyle(txAmountColor(tx))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: Spacing.xs) {
                    Text(tx.timestamp.formatted(.relative(presentation: .named)))
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)

                    txStatusBadge(tx.status)
                }
            }
        }
        .padding(.vertical, Spacing.listRowVertical)
        .contentShape(Rectangle())
    }

    private func txAmountColor(_ tx: TransactionItem) -> Color {
        switch tx.type {
        case .receive: return .priceUp
        case .send: return .priceDown
        default: return .labelPrimary
        }
    }

    @ViewBuilder
    private func txStatusBadge(_ status: TransactionItem.TxStatus) -> some View {
        switch status {
        case .confirmed:
            Image(systemName: Symbols.complete)
                .font(.system(size: 10))
                .foregroundStyle(Color.statusSuccess)
        case .pending:
            Image(systemName: Symbols.pending)
                .font(.system(size: 10))
                .foregroundStyle(Color.statusWarning)
        case .failed:
            Image(systemName: Symbols.failed)
                .font(.system(size: 10))
                .foregroundStyle(Color.statusError)
        }
    }

    // MARK: - Formatters

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formatTokenBalance(_ balance: Double, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = balance < 1 ? 6 : (balance < 100 ? 4 : 2)
        formatter.minimumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: balance)) ?? "0.00"
        return "\(formatted) \(symbol)"
    }
}

// MARK: - Supporting Types

enum WalletSegment: String, CaseIterable {
    case tokens = "Tokens"
    case nfts = "NFTs"
    case defi = "DeFi"
    case activity = "Activity"
}

enum TokenSortOrder {
    case byValue, byChange, alphabetical

    var label: String {
        switch self {
        case .byValue: return "Value"
        case .byChange: return "Change"
        case .alphabetical: return "A-Z"
        }
    }
}

enum ActivityFilter: String, CaseIterable {
    case all = "All"
    case sent = "Sent"
    case received = "Received"
    case swaps = "Swaps"
    case contracts = "Contracts"
}

// MARK: - Preview

#Preview {
    WalletView()
        .environmentObject(WalletManager())
        .preferredColorScheme(.dark)
}
