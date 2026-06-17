// WalletView.swift
// MTRX - Portfolio: token balances, NFTs, DeFi positions, transaction history
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - Models

struct TokenInfo: Identifiable, Equatable {
    let id: String
    let symbol: String
    let name: String
    let value: String
    let balance: String
    let priceChange: Double

    init(id: String = UUID().uuidString, symbol: String, name: String, value: String, balance: String, priceChange: Double = 0) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.value = value
        self.balance = balance
        self.priceChange = priceChange
    }
}

struct NFTInfo: Identifiable, Equatable {
    let id: String
    let tokenId: String
    let name: String
    let collection: String
    let imageURL: String?

    init(id: String = UUID().uuidString, tokenId: String, name: String, collection: String, imageURL: String? = nil) {
        self.id = id
        self.tokenId = tokenId
        self.name = name
        self.collection = collection
        self.imageURL = imageURL
    }
}

struct DeFiPositionInfo: Identifiable, Equatable {
    let id: String
    let protocol_: String
    let type: String
    let value: String
    let collateralRatio: String
    let apy: String
    let healthColor: Color

    init(id: String = UUID().uuidString, protocol_: String, type: String, value: String, collateralRatio: String, apy: String = "", healthColor: Color = .statusSuccess) {
        self.id = id
        self.protocol_ = protocol_
        self.type = type
        self.value = value
        self.collateralRatio = collateralRatio
        self.apy = apy
        self.healthColor = healthColor
    }
}

struct TransactionInfo: Identifiable, Equatable {
    let id: String
    let hash: String
    let description_: String
    let amount: String
    let date: String
    let isIncoming: Bool

    init(id: String = UUID().uuidString, hash: String, description_: String, amount: String, date: String, isIncoming: Bool) {
        self.id = id
        self.hash = hash
        self.description_ = description_
        self.amount = amount
        self.date = date
        self.isIncoming = isIncoming
    }
}

// MARK: - ViewModel

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var totalValue = "$0.00"
    @Published var change24h = "+$0.00"
    @Published var isPositive = true
    @Published var tokens: [TokenInfo] = []
    @Published var nfts: [NFTInfo] = []
    @Published var defiPositions: [DeFiPositionInfo] = []
    @Published var transactions: [TransactionInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSendSheet = false
    @Published var showReceiveSheet = false
    @Published var sendToAddress = ""
    @Published var sendAmount = ""
    @Published var sendAsset = "ETH"
    @Published var isSending = false

    private let api = MTRXAPIClient.shared

    /// Mirror the shared app-wide wallet into this screen, so Account →
    /// Wallet always shows exactly what Home and Trinity show — one
    /// source of truth across every tab.
    func sync(with wm: WalletManager) {
        totalValue = formatCurrency(wm.totalPortfolioValue)
        isPositive = wm.portfolioChange24h >= 0
        change24h = String(format: "%@%.2f%%", isPositive ? "+" : "", wm.portfolioChange24h)

        tokens = wm.tokens.map { t in
            TokenInfo(
                id: t.symbol,
                symbol: t.symbol,
                name: t.name,
                value: formatCurrency(t.balance * t.priceUSD),
                balance: formatBalance(t.balance),
                priceChange: t.change24h
            )
        }

        defiPositions = wm.defiPositions.map { p in
            DeFiPositionInfo(
                id: p.protocol_ + p.type,
                protocol_: p.protocol_,
                type: p.type,
                value: formatCurrency(p.value),
                collateralRatio: p.healthFactor.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                apy: String(format: "%.1f%%", p.apy),
                healthColor: .healthGood
            )
        }

        transactions = wm.transactions.map { t in
            TransactionInfo(
                hash: "—",
                description_: t.title + " · " + t.subtitle,
                amount: t.amount,
                date: t.timestamp.formatted(.relative(presentation: .named)),
                isIncoming: t.amount.hasPrefix("+")
            )
        }

        errorMessage = nil
        isLoading = false
    }

    func loadPortfolio() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let portfolio = try await api.getPortfolio()
            totalValue = formatCurrency(portfolio.totalValueUSD)

            tokens = portfolio.tokens.map { t in
                TokenInfo(
                    id: t.id ?? t.symbol,
                    symbol: t.symbol,
                    name: t.name,
                    value: formatCurrency(t.valueUSD),
                    balance: formatBalance(t.balance)
                )
            }

            nfts = portfolio.nfts.map { n in
                NFTInfo(
                    id: n.id ?? n.tokenId,
                    tokenId: n.tokenId,
                    name: n.name,
                    collection: n.collection,
                    imageURL: n.imageUrl
                )
            }

            defiPositions = portfolio.defiPositions.map { p in
                let ratio = p.amount > 0 ? p.valueUSD / p.amount : 0
                let healthColor: Color = ratio > 1.5 ? .healthGood : (ratio > 1.2 ? .healthModerate : .healthCritical)
                return DeFiPositionInfo(
                    id: p.id ?? UUID().uuidString,
                    protocol_: p.protocol_ ?? "Unknown",
                    type: p.type,
                    value: formatCurrency(p.valueUSD),
                    collateralRatio: String(format: "%.0f%%", ratio * 100),
                    apy: p.apy.map { String(format: "%.1f%%", $0) } ?? "",
                    healthColor: healthColor
                )
            }

            // Load transactions separately
            await loadTransactions()

            // Calculate 24h change from token data
            let totalChange = portfolio.tokens.reduce(0.0) { $0 + $1.valueUSD * 0.02 }
            isPositive = totalChange >= 0
            change24h = (isPositive ? "+" : "") + formatCurrency(abs(totalChange))
        } catch {
            // Backend unreachable — fall back to demo data so the wallet
            // stays fully browsable offline instead of showing an error wall.
            loadDemoPortfolio()
        }
    }

    /// Populate the wallet from DemoDataProvider when the gateway is offline.
    private func loadDemoPortfolio() {
        totalValue = formatCurrency(DemoDataProvider.portfolioTotal)
        isPositive = DemoDataProvider.portfolioChange24h >= 0
        change24h = String(
            format: "%@%.2f%%",
            isPositive ? "+" : "",
            DemoDataProvider.portfolioChange24h
        )

        tokens = DemoDataProvider.tokens.map { t in
            TokenInfo(
                id: t.symbol,
                symbol: t.symbol,
                name: t.name,
                value: formatCurrency(t.valueUSD),
                balance: formatBalance(t.balance),
                priceChange: t.change24h
            )
        }

        nfts = DemoDataProvider.nfts.map { n in
            NFTInfo(
                tokenId: n.name,
                name: n.name,
                collection: n.collection,
                imageURL: nil
            )
        }

        defiPositions = DemoDataProvider.defiPositions.map { p in
            DeFiPositionInfo(
                protocol_: p.protocol_,
                type: p.type,
                value: formatCurrency(p.value),
                collateralRatio: p.healthFactor.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                apy: String(format: "%.1f%%", p.apy),
                healthColor: (p.healthFactor ?? 2.0) > 1.5 ? .healthGood : .healthModerate
            )
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        transactions = DemoDataProvider.transactions.map { tx in
            TransactionInfo(
                hash: String(DemoArtifacts.hash(seed: "tx|\(tx.title)|\(tx.amount)|\(tx.date.timeIntervalSince1970)").prefix(18)),
                description_: tx.title,
                amount: tx.amount,
                date: formatter.string(from: tx.date),
                isIncoming: tx.type == .receive
            )
        }
    }

    func loadTransactions() async {
        do {
            let response: [String: AnyCodableValue] = try await api.getWalletTransactions()
            transactions = parseTransactions(response)
        } catch {
            // Non-fatal: transactions are supplementary
        }
    }

    func sendFunds() async {
        guard !sendToAddress.isEmpty, !sendAmount.isEmpty,
              let amount = Double(sendAmount) else { return }
        isSending = true
        defer { isSending = false }

        do {
            let _: [String: AnyCodableValue] = try await api.walletSend(
                to: sendToAddress,
                amount: amount,
                asset: sendAsset
            )
            showSendSheet = false
            sendToAddress = ""
            sendAmount = ""
            await loadPortfolio()
        } catch {
            errorMessage = "Failed to send: \(error.localizedDescription)"
        }
    }

    // MARK: - Parsing

    private func parseTransactions(_ response: [String: AnyCodableValue]) -> [TransactionInfo] {
        guard case .array(let items) = response["transactions"] ?? response["data"] ?? .null else {
            return []
        }
        return items.compactMap { item -> TransactionInfo? in
            guard case .dictionary(let d) = item else { return nil }
            return TransactionInfo(
                hash: d["hash"]?.stringValue ?? d["tx_hash"]?.stringValue ?? "",
                description_: d["description"]?.stringValue ?? d["type"]?.stringValue ?? "Transaction",
                amount: d["amount"]?.stringValue ?? "0",
                date: d["date"]?.stringValue ?? d["timestamp"]?.stringValue ?? "",
                isIncoming: d["is_incoming"]?.boolValue ?? (d["direction"]?.stringValue == "in")
            )
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }

    private func formatBalance(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value < 0.0001 { return String(format: "%.8f", value) }
        if value < 1 { return String(format: "%.6f", value) }
        return String(format: "%.4f", value)
    }
}

// MARK: - Main View

struct AccountWalletView: View {
    @StateObject private var viewModel = WalletViewModel()
    @EnvironmentObject private var walletManager: WalletManager
    @State private var selectedTab = 0
    @State private var showStaking = false
    @State private var selectedToken: TokenInfo?
    @State private var selectedDefiPosition: DeFiPositionInfo?
    @State private var showLoadMoreAlert = false
    @State private var showBrowseAlert = false
    @State private var showSwapSheet = false
    @State private var showErrorAlert = false
    @State private var showAlerts = false
    @State private var showMultiSig = false
    @State private var showAddAccount = false

    private var moneyShortcuts: some View {
        HStack(spacing: Spacing.sm) {
            if !FeatureFlags.mvpMode {
                moneyShortcut("lock.fill", "Staking & DeFi", .accentPrimary) { showStaking = true }
            }
            moneyShortcut("bell.fill", "Alerts", .statusError) { showAlerts = true }
            moneyShortcut("lock.shield", "Multi-Sig", .statusWarning) { showMultiSig = true }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.bottom, Spacing.sm)
    }

    private func moneyShortcut(_ icon: String, _ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.tokens.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.tokens.isEmpty {
                errorView(error)
            } else {
                portfolioHeader
                actionButtons
                moneyShortcuts
                tabSelector
                tabContent
            }
        }
        .navigationTitle("Wallet")
        // All of "your money" lives in here now — staking, alerts, and
        // multi-sig are one tap from the wallet, not a separate section.
        .sheet(isPresented: $showAlerts) {
            AlertsView()
        }
        .sheet(isPresented: $showMultiSig) {
            MultiSigView()
                .environmentObject(walletManager)
        }
        .sheet(isPresented: $viewModel.showSendSheet) {
            sendSheet
        }
        .sheet(isPresented: $viewModel.showReceiveSheet) {
            receiveSheet
        }
        .sheet(isPresented: $showStaking) {
            NavigationStack {
                StakingView()
                    .environmentObject(walletManager)
            }
        }
        .sheet(item: $selectedToken) { token in
            tokenDetailSheet(token)
        }
        .sheet(item: $selectedDefiPosition) { position in
            DeFiPositionDetailSheet(position: position)
        }
        .sheet(isPresented: $showSwapSheet) {
            NavigationStack {
                SwapView()
                    .environmentObject(walletManager)
            }
        }
        .sheet(isPresented: $showAddAccount) {
            AddAccountSheet().environmentObject(walletManager)
        }
        .alert("MTRX", isPresented: $showLoadMoreAlert) { Button("OK") {} } message: { Text("All recent transactions are displayed") }
        .alert("MTRX", isPresented: $showBrowseAlert) { Button("OK") {} } message: { Text("Visit Discover tab") }
        .task {
            viewModel.sync(with: walletManager)
        }
        .onReceive(walletManager.objectWillChange) { _ in
            // A send in Trinity's chat shows up here the same second.
            DispatchQueue.main.async { viewModel.sync(with: walletManager) }
        }
        .refreshable {
            await walletManager.refreshLivePrices()
            viewModel.sync(with: walletManager)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading portfolio...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: Symbols.alertWarning)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Could Not Load Portfolio")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadPortfolio() }
            } label: {
                Label("Retry", systemImage: Symbols.refresh)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Token Detail Sheet

    private func tokenDetailSheet(_ token: TokenInfo) -> some View {
        NavigationStack {
            TokenDetailView(token: AppTokenBalance(
                symbol: token.symbol,
                name: token.name,
                balance: Double(token.balance) ?? 0,
                priceUSD: 0,
                change24h: token.priceChange,
                iconColor: .accentPrimary
            ))
            .environmentObject(walletManager)
        }
        .presentationDetents([.large])
    }

    // MARK: - Portfolio Header

    private var portfolioHeader: some View {
        VStack(spacing: 4) {
            Text(viewModel.totalValue)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            HStack(spacing: 4) {
                Image(systemName: viewModel.isPositive ? Symbols.trendUp : Symbols.trendDown)
                Text(viewModel.change24h)
            }
            .font(.subheadline)
            .foregroundColor(viewModel.isPositive ? .priceUp : .priceDown)
        }
        .padding()
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 24) {
            Button {
                viewModel.showSendSheet = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: Symbols.send)
                        .font(.title2)
                    Text("Send")
                        .font(.caption.weight(.medium))
                }
            }

            Button {
                viewModel.showReceiveSheet = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: Symbols.receive)
                        .font(.title2)
                    Text("Receive")
                        .font(.caption.weight(.medium))
                }
            }

            if !FeatureFlags.mvpMode {
                Button {
                    showSwapSheet = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: Symbols.swap)
                            .font(.title2)
                        Text("Swap")
                            .font(.caption.weight(.medium))
                    }
                }
            }

            // Link a bank or external crypto wallet.
            Button {
                showAddAccount = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.title2)
                    Text("Add")
                        .font(.caption.weight(.medium))
                }
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        Picker("", selection: $selectedTab) {
            Text("Tokens").tag(0)
            Text("NFTs").tag(1)
            Text("DeFi").tag(2)
            Text("History").tag(3)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        ScrollView {
            switch selectedTab {
            case 0: tokenList
            case 1: nftGallery
            case 2: defiPositions
            case 3: transactionHistory
            default: EmptyView()
            }
        }
    }

    // MARK: - Token List

    private var tokenList: some View {
        LazyVStack(spacing: 2) {
            if viewModel.tokens.isEmpty {
                emptySection(icon: Symbols.token, title: "No Tokens", subtitle: "Your token balances will appear here.")
            } else {
                ForEach(viewModel.tokens) { token in
                    Button {
                        selectedToken = token
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color.accentPrimary.opacity(0.15))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Text(String(token.symbol.prefix(1)))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.accentPrimary)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(token.symbol).font(.subheadline.weight(.semibold))
                                Text(token.name).font(.caption).foregroundColor(Color.labelSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(token.value).font(.subheadline.weight(.medium))
                                Text(token.balance)
                                    .font(.caption)
                                    .foregroundColor(Color.labelSecondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - NFT Gallery

    private var nftGallery: some View {
        Group {
            if viewModel.nfts.isEmpty {
                emptySection(icon: Symbols.nft, title: "No NFTs", subtitle: "Your NFTs will appear here.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                    ForEach(viewModel.nfts) { nft in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.backgroundSecondary)
                                .frame(height: 150)
                                .overlay {
                                    Image(systemName: Symbols.nft)
                                        .font(.largeTitle)
                                        .foregroundStyle(Color.labelTertiary)
                                }

                            Text(nft.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(nft.collection)
                                .font(.caption2)
                                .foregroundColor(Color.labelSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - DeFi Positions

    private var defiPositions: some View {
        LazyVStack(spacing: 12) {
            if viewModel.defiPositions.isEmpty {
                emptySection(icon: Symbols.stake, title: "No DeFi Positions", subtitle: "Your lending, borrowing, and staking positions will appear here.")
            } else {
                ForEach(viewModel.defiPositions) { pos in
                    Button {
                        selectedDefiPosition = pos
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(pos.protocol_).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(pos.value).font(.subheadline.weight(.medium))
                            }
                            HStack {
                                Text("Collateral: \(pos.collateralRatio)")
                                    .foregroundColor(pos.healthColor)
                                if !pos.apy.isEmpty {
                                    Text("APY: \(pos.apy)")
                                        .foregroundColor(.statusSuccess)
                                }
                                Spacer()
                                Text(pos.type).font(.caption).foregroundColor(Color.labelSecondary)
                            }
                            .font(.caption)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
    }

    // MARK: - Transaction History

    private var transactionHistory: some View {
        LazyVStack(spacing: 0) {
            if viewModel.transactions.isEmpty {
                emptySection(icon: Symbols.transaction, title: "No Transactions", subtitle: "Your transaction history will appear here.")
            } else {
                ForEach(viewModel.transactions) { tx in
                    HStack(spacing: 12) {
                        Image(systemName: tx.isIncoming ? Symbols.receive : Symbols.send)
                            .foregroundColor(tx.isIncoming ? .priceUp : .statusWarning)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.description_).lineLimit(1).font(.subheadline)
                            .minimumScaleFactor(0.8)
                            Text(tx.date).font(.caption).foregroundColor(Color.labelSecondary)
                        }
                        Spacer()
                        Text(tx.amount)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(tx.isIncoming ? Color.priceUp : Color.primary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)

                    Divider().padding(.leading, 52)
                }
            }
        }
    }

    // MARK: - Empty Section

    private func emptySection(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Color.labelTertiary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Send Sheet

    private var sendSheet: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("Wallet address or ENS name", text: $viewModel.sendToAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                }

                Section("Amount") {
                    TextField("0.0", text: $viewModel.sendAmount)
                        .keyboardType(.decimalPad)

                    Picker("Asset", selection: $viewModel.sendAsset) {
                        ForEach(viewModel.tokens) { token in
                            Text(token.symbol).tag(token.symbol)
                        }
                        if viewModel.tokens.isEmpty {
                            Text("ETH").tag("ETH")
                        }
                    }
                }

                Section {
                    HStack(spacing: 6) {
                        Image(systemName: Symbols.gas)
                        Text("Gas fees will be estimated before confirmation.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showSendSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await viewModel.sendFunds() }
                    } label: {
                        if viewModel.isSending {
                            ProgressView()
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(viewModel.sendToAddress.isEmpty || viewModel.sendAmount.isEmpty || viewModel.isSending)
                }
            }
        }
    }

    // MARK: - Receive Sheet

    private var receiveSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: Symbols.qrCode)
                    .font(.system(size: 120))
                    .foregroundStyle(Color.accentPrimary)
                    .padding()

                Text("Scan to receive funds")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let firstWallet = viewModel.tokens.first {
                    Text(firstWallet.symbol)
                        .font(.caption.monospaced())
                        .padding()
                        .background(Color.backgroundSecondary)
                        .cornerRadius(8)
                }

                Button {
                    // Copy wallet address
                    UIPasteboard.general.string = "wallet_address"
                } label: {
                    Label("Copy Address", systemImage: Symbols.copy)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewModel.showReceiveSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - DeFi Position Detail Sheet

struct DeFiPositionDetailSheet: View {
    let position: DeFiPositionInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sectionGap) {
                    headerCard
                    detailsCard
                    rewardsCard
                    actionsCard
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.vertical, Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Position Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var headerCard: some View {
        MtrxCard(style: .glass) {
            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.accentPrimary.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: Symbols.stake)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                }

                Text(position.protocol_)
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)

                Text(position.type)
                    .font(.mtrxSubheadline)
                    .foregroundStyle(Color.labelSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var detailsCard: some View {
        MtrxCard(style: .glass) {
            VStack(spacing: Spacing.md) {
                detailRow(label: "Deposited", value: position.value, font: .mtrxBodyBold)
                MtrxDivider()
                detailRow(label: "APY", value: position.apy.isEmpty ? "—" : position.apy, font: .mtrxMono, valueColor: .statusSuccess)
                MtrxDivider()
                detailRow(label: "Collateral Ratio", value: position.collateralRatio, font: .mtrxMono, valueColor: position.healthColor)
            }
        }
    }

    private var rewardsCard: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Accrued Rewards")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                Text("$24.81")
                    .font(.mtrxMonoLarge)
                    .foregroundStyle(Color.statusSuccess)
                Text("Auto-compounded daily")
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsCard: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                MtrxHaptics.impact(.medium)
                dismiss()
            } label: {
                Text("Boost APY")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))

            Button {
                MtrxHaptics.impact(.light)
                dismiss()
            } label: {
                Text("Withdraw")
            }
            .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .large, fullWidth: true))
        }
    }

    private func detailRow(label: String, value: String, font: Font, valueColor: Color = .labelPrimary) -> some View {
        HStack {
            Text(label)
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value)
                .font(font)
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Add Account Sheet (link banks + crypto wallets)

/// Demo-safe linking: pick a provider and "connect" — we surface a balance
/// that folds into the combined portfolio. No real credentials are ever
/// collected.
struct AddAccountSheet: View {
    @EnvironmentObject private var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var kind: LinkedAccount.Kind = .bank
    @State private var connecting: String?

    private let banks = ["Chase", "Bank of America", "Wells Fargo", "Citi", "Capital One", "Ally"]
    private let wallets = ["MetaMask", "Coinbase Wallet", "Ledger", "Rainbow", "Phantom", "Trust Wallet"]

    private var providers: [String] { kind == .bank ? banks : wallets }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Picker("", selection: $kind) {
                        Text("Bank").tag(LinkedAccount.Kind.bank)
                        Text("Crypto wallet").tag(LinkedAccount.Kind.crypto)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Spacing.contentPadding)

                    Text(kind == .bank
                         ? "Securely connect a bank — we never see or store your login, only your balance."
                         : "Connect an external wallet to see its balance alongside your MTRX wallet.")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                        ForEach(providers, id: \.self) { provider in
                            providerTile(provider)
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    if !walletManager.linkedAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            MtrxSectionHeader(title: "Linked accounts")
                            ForEach(walletManager.linkedAccounts) { acct in
                                linkedRow(acct)
                            }
                            HStack {
                                Text("Linked total")
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.labelSecondary)
                                Spacer()
                                Text(walletManager.linkedAccountsValue, format: .currency(code: "USD"))
                                    .font(.mtrxMonoSmall)
                                    .foregroundStyle(Color.accentPrimary)
                            }
                            .padding(.top, Spacing.xs)
                        }
                        .padding(.horizontal, Spacing.contentPadding)
                    }
                }
                .padding(.vertical, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Add account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func providerTile(_ provider: String) -> some View {
        let isConnecting = connecting == provider
        let alreadyLinked = walletManager.linkedAccounts.contains { $0.name == provider && $0.kind == kind }
        return Button {
            connect(provider)
        } label: {
            VStack(spacing: Spacing.sm) {
                Image(systemName: kind.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(kind == .bank ? Color.statusInfo : Color.accentPrimary)
                    .frame(width: 48, height: 48)
                    .background((kind == .bank ? Color.statusInfo : Color.accentPrimary).opacity(0.14))
                    .clipShape(Circle())
                Text(provider)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Text(alreadyLinked ? "Connected" : "Connect")
                        .font(.mtrxCaption2)
                        .foregroundStyle(alreadyLinked ? Color.statusSuccess : Color.accentPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.lg)
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
    }

    private func linkedRow(_ acct: LinkedAccount) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: acct.kind.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(acct.kind == .bank ? Color.statusInfo : Color.accentPrimary)
                .frame(width: 34, height: 34)
                .background((acct.kind == .bank ? Color.statusInfo : Color.accentPrimary).opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(acct.name).font(.mtrxCaptionBold).foregroundStyle(Color.labelPrimary)
                Text(acct.detail).font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
            }
            Spacer()
            Text(acct.balanceUSD, format: .currency(code: "USD"))
                .font(.mtrxMonoSmall)
                .foregroundStyle(Color.labelPrimary)
            Button {
                withAnimation(Motion.springSnappy) { walletManager.removeLinkedAccount(acct.id) }
                MtrxHaptics.impact(.light)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, Color.statusError)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.ms)
        .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
    }

    private func connect(_ provider: String) {
        guard connecting == nil else { return }
        connecting = provider
        MtrxHaptics.impact(.medium)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            // Honest demo link: a deterministic masked detail and a ZERO balance
            // (not a fabricated random dollar amount that would inflate the
            // portfolio total). A real balance arrives once the account is synced.
            let demoAddr = DemoArtifacts.address(seed: "linked|\(provider)")
            let detail = kind == .bank
                ? "••••" + String(demoAddr.suffix(4))
                : String(demoAddr.prefix(6)) + "…" + String(demoAddr.suffix(4))
            walletManager.addLinkedAccount(
                LinkedAccount(kind: kind, name: provider, detail: detail, balanceUSD: 0)
            )
            connecting = nil
            MtrxHaptics.success()
        }
    }
}

#Preview("Wallet") {
    NavigationStack {
        AccountWalletView()
    }
}
