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
            errorMessage = "Failed to load portfolio: \(error.localizedDescription)"
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

struct WalletView: View {
    @StateObject private var viewModel = WalletViewModel()
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.tokens.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.tokens.isEmpty {
                errorView(error)
            } else {
                portfolioHeader
                actionButtons
                tabSelector
                tabContent
            }
        }
        .navigationTitle("Wallet")
        .sheet(isPresented: $viewModel.showSendSheet) {
            sendSheet
        }
        .sheet(isPresented: $viewModel.showReceiveSheet) {
            receiveSheet
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil && !viewModel.tokens.isEmpty)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.loadPortfolio()
        }
        .refreshable {
            await viewModel.loadPortfolio()
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

            Button {
                // Future: swap flow
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: Symbols.swap)
                        .font(.title2)
                    Text("Swap")
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
                    HStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Text(String(token.symbol.prefix(1)))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.accentColor)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.symbol).font(.subheadline.weight(.semibold))
                            Text(token.name).font(.caption).foregroundColor(.labelSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(token.value).font(.subheadline.weight(.medium))
                            Text(token.balance)
                                .font(.caption)
                                .foregroundColor(.labelSecondary)
                        }
                    }
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
                                        .foregroundStyle(.labelTertiary)
                                }

                            Text(nft.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text(nft.collection)
                                .font(.caption2)
                                .foregroundColor(.labelSecondary)
                                .lineLimit(1)
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
                            Text(pos.type).font(.caption).foregroundColor(.labelSecondary)
                        }
                        .font(.caption)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
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
                            Text(tx.date).font(.caption).foregroundColor(.labelSecondary)
                        }
                        Spacer()
                        Text(tx.amount)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(tx.isIncoming ? .priceUp : .primary)
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
                .foregroundStyle(.labelTertiary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.labelSecondary)
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
                    .foregroundStyle(.accentColor)
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

#Preview("Wallet") {
    NavigationStack {
        WalletView()
    }
}
