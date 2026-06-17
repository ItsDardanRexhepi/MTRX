// PortfolioView.swift
// MTRX
//
// Portfolio overview — total value, 24h change, token holdings list, transaction history with pull-to-refresh.

import SwiftUI

// MARK: - Data Models

struct PortfolioTokenItem: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let balance: String
    let usdValue: String
    let changePercent: String
}

struct TransactionItem: Identifiable {
    let id = UUID()
    let type: String
    let token: String?
    let amount: String
    let date: String
    let status: String
}

// MARK: - View Model

@MainActor
class PortfolioViewModel: ObservableObject {
    @Published var totalValue: String = "$0.00"
    @Published var change24h: String = "+0.0%"
    @Published var tokens: [PortfolioTokenItem] = []
    @Published var transactions: [TransactionItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isDemo: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    var changeColor: Color {
        if change24h.hasPrefix("+") { return .priceUp }
        if change24h.hasPrefix("-") { return .priceDown }
        return .priceNeutral
    }

    var changeIcon: String {
        if change24h.hasPrefix("+") { return "arrow.up.right" }
        if change24h.hasPrefix("-") { return "arrow.down.right" }
        return "arrow.right"
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live portfolio from PortfolioService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                async let summaryReq = PortfolioService.shared.getPortfolioSummary(address: address)
                async let txReq = PortfolioService.shared.getTransactionHistory(address: address, page: 1)
                let summary = try await summaryReq
                let txs = try await txReq
                totalValue = summary.totalValueUSD.formatted(.currency(code: "USD"))
                change24h = String(format: "%+.2f%%", summary.change24hPercent)
                tokens = summary.tokens.map { t in
                    PortfolioTokenItem(
                        name: t.name, symbol: t.symbol,
                        balance: String(format: "%.4f", t.balance),
                        usdValue: t.usdValue.formatted(.currency(code: "USD")),
                        changePercent: String(format: "%+.2f%%", t.change24hPercent)
                    )
                }
                transactions = txs.map { tx in
                    let amountLabel = tx.amount
                        .map { String(format: "%+.4f \(tx.token ?? "")", $0).trimmingCharacters(in: .whitespaces) } ?? "—"
                    return TransactionItem(
                        type: tx.type, token: tx.token, amount: amountLabel,
                        date: Self.dateFormatter.string(from: tx.timestamp), status: tx.status
                    )
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live portfolio unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(600))
            totalValue = "$12,847.63"
            change24h = "+3.42%"
            tokens = PortfolioViewModel.sampleTokens
            transactions = PortfolioViewModel.sampleTransactions
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load portfolio data."
            isLoading = false
        }
    }

    static let sampleTokens: [PortfolioTokenItem] = [
        PortfolioTokenItem(name: "Ethereum", symbol: "ETH", balance: "2.4500", usdValue: "$8,232.50", changePercent: "+4.12%"),
        PortfolioTokenItem(name: "USD Coin", symbol: "USDC", balance: "3,200.00", usdValue: "$3,200.00", changePercent: "+0.01%"),
        PortfolioTokenItem(name: "Chainlink", symbol: "LINK", balance: "85.00", usdValue: "$1,105.13", changePercent: "-1.23%"),
        PortfolioTokenItem(name: "Aave", symbol: "AAVE", balance: "3.50", usdValue: "$310.00", changePercent: "+2.87%")
    ]

    static let sampleTransactions: [TransactionItem] = [
        TransactionItem(type: "Send", token: "ETH", amount: "-0.5000 ETH", date: "Apr 12, 2026", status: "Confirmed"),
        TransactionItem(type: "Receive", token: "USDC", amount: "+1,200.00 USDC", date: "Apr 11, 2026", status: "Confirmed"),
        TransactionItem(type: "Swap", token: "LINK", amount: "50 LINK -> 0.18 ETH", date: "Apr 10, 2026", status: "Confirmed"),
        TransactionItem(type: "Send", token: "ETH", amount: "-0.1000 ETH", date: "Apr 9, 2026", status: "Pending")
    ]
}

// MARK: - Portfolio View

struct PortfolioView: View {
    @StateObject private var viewModel = PortfolioViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.tokens.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.tokens.isEmpty {
                    errorState(message: error)
                } else {
                    portfolioContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Content

    private var portfolioContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                totalValueHeader
                tokensSection
                transactionsSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Total Value Header

    private var totalValueHeader: some View {
        MtrxCard(style: .glass, accentEdge: .top) {
            VStack(spacing: Spacing.md) {
                VStack(spacing: Spacing.xs) {
                    Text("Total Portfolio Value")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)

                    Text(viewModel.totalValue)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.labelPrimary)
                }

                HStack(spacing: Spacing.xs) {
                    Image(systemName: viewModel.changeIcon)
                        .font(.system(size: 14, weight: .semibold))
                    Text(viewModel.change24h)
                        .font(.mtrxHeadlineTabular)
                    Text("24h")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                }
                .foregroundStyle(viewModel.changeColor)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            VoiceOverSupport.portfolioLabel(
                value: viewModel.totalValue,
                change: viewModel.change24h,
                isPositive: !viewModel.change24h.hasPrefix("-")
            ) + Text(viewModel.isDemo ? " Showing demo data." : "")
        )
    }

    // MARK: - Tokens Section

    private var tokensSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Holdings")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)
                .accessibilityAddTraits(.isHeader)

            if viewModel.tokens.isEmpty {
                emptyTokensState
            } else {
                ForEach(viewModel.tokens) { token in
                    tokenRow(token)
                }
            }
        }
    }

    private func tokenRow(_ token: PortfolioTokenItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                Circle()
                    .fill(Color(red: 0.0, green: 0.675, blue: 0.694).opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(token.symbol.prefix(2)))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(token.name)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text("\(token.balance) \(token.symbol)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(token.usdValue)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                    Text(token.changePercent)
                        .font(.mtrxCaption1)
                        .foregroundStyle(token.changePercent.hasPrefix("-") ? Color.priceDown : Color.priceUp)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(token.name), \(token.balance) \(token.symbol), value \(token.usdValue), 24-hour change \(token.changePercent)")
    }

    private var emptyTokensState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 40))
                .foregroundStyle(Color.labelTertiary)
            Text("No tokens yet")
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
            Text("Your token holdings will appear here once you receive or purchase tokens.")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Transactions Section

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent Transactions")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)
                .accessibilityAddTraits(.isHeader)

            if viewModel.transactions.isEmpty {
                emptyTransactionsState
            } else {
                ForEach(viewModel.transactions) { tx in
                    transactionRow(tx)
                }
            }
        }
    }

    private func transactionRow(_ tx: TransactionItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                ZStack {
                    Circle()
                        .fill(transactionIconBackground(tx.type))
                        .frame(width: 36, height: 36)
                    Image(systemName: transactionIcon(tx.type))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(transactionIconColor(tx.type))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.type)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text(tx.date)
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(tx.amount)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                    Text(tx.status)
                        .font(.mtrxCaption2)
                        .foregroundStyle(tx.status == "Pending" ? Color.statusWarning : Color.statusSuccess)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tx.type), \(tx.amount), \(tx.date). Status: \(tx.status).")
    }

    private var emptyTransactionsState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(Color.labelTertiary)
            Text("No transactions yet")
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
            Text("Your transaction history will appear here.")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.statusWarning)
                .accessibilityHidden(true)
            Text(message)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.675, blue: 0.694))
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func transactionIcon(_ type: String) -> String {
        switch type {
        case "Send": return "arrow.up.right"
        case "Receive": return "arrow.down.left"
        case "Swap": return "arrow.triangle.2.circlepath"
        default: return "arrow.left.arrow.right"
        }
    }

    private func transactionIconColor(_ type: String) -> Color {
        switch type {
        case "Send": return .priceDown
        case "Receive": return .priceUp
        case "Swap": return Color(red: 0.0, green: 0.675, blue: 0.694)
        default: return .labelSecondary
        }
    }

    private func transactionIconBackground(_ type: String) -> Color {
        transactionIconColor(type).opacity(0.12)
    }
}

// MARK: - Preview

#Preview {
    PortfolioView()
        .preferredColorScheme(.dark)
}
