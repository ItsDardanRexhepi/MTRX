// TreasuryView.swift
// MTRX
//
// DAO treasury — total balance, asset breakdown, transaction history, propose spending sheet.

import SwiftUI

// MARK: - Data Models

struct TreasuryAssetItem: Identifiable {
    let id = UUID()
    let token: String
    let symbol: String
    let balance: String
    let usdValue: String
}

struct TreasuryTxItem: Identifiable {
    let id = UUID()
    let type: String
    let token: String
    let amount: String
    let recipient: String?
    let timestamp: String
}

// MARK: - View Model

@MainActor
class TreasuryViewModel: ObservableObject {
    @Published var totalUSD: String = "$0"
    @Published var assets: [TreasuryAssetItem] = []
    @Published var transactions: [TreasuryTxItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showProposal: Bool = false
    @Published var isDemo: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    // Proposal form
    @Published var proposalToken: String = ""
    @Published var proposalAmount: String = ""
    @Published var proposalRecipient: String = ""
    @Published var proposalDescription: String = ""
    @Published var isSubmitting: Bool = false

    var canSubmitProposal: Bool {
        !proposalToken.trimmingCharacters(in: .whitespaces).isEmpty &&
        !proposalAmount.trimmingCharacters(in: .whitespaces).isEmpty &&
        !proposalRecipient.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(proposalAmount) != nil
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live treasury from GovernanceService when configured. Treasury is per-DAO;
        // we use the user's first DAO. Else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                let daos = try await GovernanceService.shared.getDAOs(address: address)
                if let dao = daos.first {
                    async let balanceReq = GovernanceService.shared.getTreasuryBalance(daoId: dao.daoId)
                    async let historyReq = GovernanceService.shared.getTreasuryHistory(daoId: dao.daoId)
                    let balance = try await balanceReq
                    totalUSD = balance.totalUSD.formatted(.currency(code: "USD"))
                    assets = balance.assets.map { a in
                        TreasuryAssetItem(
                            token: a.token, symbol: a.symbol,
                            balance: a.balance.formatted(.number.precision(.fractionLength(2))),
                            usdValue: a.usdValue.formatted(.currency(code: "USD"))
                        )
                    }
                    transactions = (try await historyReq).map { t in
                        TreasuryTxItem(
                            type: t.type, token: t.token,
                            amount: "\(t.amount.formatted()) \(t.token)",
                            recipient: t.recipient,
                            timestamp: Self.dateFormatter.string(from: t.timestamp)
                        )
                    }
                    isDemo = false
                    isLoading = false
                    return
                }
            } catch {
                errorMessage = "Live treasury unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(600))
            totalUSD = "$1,284,530"
            assets = TreasuryViewModel.sampleAssets
            transactions = TreasuryViewModel.sampleTransactions
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load treasury data."
            isLoading = false
        }
    }

    func submitProposal() async {
        guard canSubmitProposal else { return }
        isSubmitting = true

        do {
            try await Task.sleep(for: .seconds(1.5))
            proposalToken = ""
            proposalAmount = ""
            proposalRecipient = ""
            proposalDescription = ""
            isSubmitting = false
            showProposal = false
        } catch {
            isSubmitting = false
        }
    }

    static let sampleAssets: [TreasuryAssetItem] = [
        TreasuryAssetItem(token: "Ethereum", symbol: "ETH", balance: "320.50", usdValue: "$1,076,880"),
        TreasuryAssetItem(token: "USD Coin", symbol: "USDC", balance: "150,000", usdValue: "$150,000"),
        TreasuryAssetItem(token: "MTRX", symbol: "MTRX", balance: "2,500,000", usdValue: "$50,000"),
        TreasuryAssetItem(token: "Wrapped Bitcoin", symbol: "WBTC", balance: "0.1120", usdValue: "$7,650")
    ]

    static let sampleTransactions: [TreasuryTxItem] = [
        TreasuryTxItem(type: "Inflow", token: "ETH", amount: "+10.00 ETH", recipient: nil, timestamp: "Apr 12, 2026"),
        TreasuryTxItem(type: "Outflow", token: "USDC", amount: "-5,000 USDC", recipient: "0xabc...123", timestamp: "Apr 10, 2026"),
        TreasuryTxItem(type: "Outflow", token: "ETH", amount: "-2.50 ETH", recipient: "0xdef...456", timestamp: "Apr 8, 2026"),
        TreasuryTxItem(type: "Inflow", token: "MTRX", amount: "+100,000 MTRX", recipient: nil, timestamp: "Apr 5, 2026"),
        TreasuryTxItem(type: "Outflow", token: "USDC", amount: "-12,000 USDC", recipient: "0x789...abc", timestamp: "Apr 1, 2026")
    ]
}

// MARK: - Treasury View

struct TreasuryView: View {
    @StateObject private var viewModel = TreasuryViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.assets.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.assets.isEmpty {
                    errorState(message: error)
                } else {
                    treasuryContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Treasury")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showProposal) {
                proposeSpendingSheet
            }
        }
    }

    // MARK: - Content

    private var treasuryContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                totalBalanceHeader
                assetBreakdown
                transactionHistory
                proposeButton
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Total Balance Header

    private var totalBalanceHeader: some View {
        MtrxCard(style: .glass, accentEdge: .top) {
            VStack(spacing: Spacing.sm) {
                Text("Treasury Balance")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)

                Text(viewModel.totalUSD)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.labelPrimary)

                Text("\(viewModel.assets.count) assets")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Asset Breakdown

    private var assetBreakdown: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Asset Breakdown")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.assets) { asset in
                assetRow(asset)
            }
        }
    }

    private func assetRow(_ asset: TreasuryAssetItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                Circle()
                    .fill(Color(red: 0.0, green: 0.675, blue: 0.694).opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(asset.symbol.prefix(2)))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.token)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text("\(asset.balance) \(asset.symbol)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                Text(asset.usdValue)
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color.labelPrimary)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Transaction History

    private var transactionHistory: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Transaction History")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            if viewModel.transactions.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.labelTertiary)
                    Text("No treasury transactions yet")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.xl)
            } else {
                ForEach(viewModel.transactions) { tx in
                    transactionRow(tx)
                }
            }
        }
    }

    private func transactionRow(_ tx: TreasuryTxItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                ZStack {
                    Circle()
                        .fill(tx.type == "Inflow" ? Color.priceUp.opacity(0.12) : Color.priceDown.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: tx.type == "Inflow" ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tx.type == "Inflow" ? Color.priceUp : Color.priceDown)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.type)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    if let recipient = tx.recipient {
                        Text("To: \(recipient)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    Text(tx.timestamp)
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                Text(tx.amount)
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(tx.type == "Inflow" ? Color.priceUp : Color.priceDown)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Propose Button

    private var proposeButton: some View {
        Button {
            viewModel.showProposal = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16))
                Text("Propose Spending")
                    .font(.mtrxBodyBold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.ms)
            .background(Color(red: 0.0, green: 0.675, blue: 0.694))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Propose Spending Sheet

    private var proposeSpendingSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Token
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Token")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("ETH, USDC, MTRX...", text: $viewModel.proposalToken)
                            .font(.mtrxBody)
                            .textInputAutocapitalization(.characters)
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Amount
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Amount")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("0.00", text: $viewModel.proposalAmount)
                            .font(.mtrxMono)
                            .keyboardType(.decimalPad)
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Recipient
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Recipient Address")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("0x...", text: $viewModel.proposalRecipient)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Description
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Description (optional)")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("Reason for this spending proposal...", text: $viewModel.proposalDescription, axis: .vertical)
                            .font(.mtrxBody)
                            .lineLimit(3...6)
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                Spacer()

                Button {
                    Task { await viewModel.submitProposal() }
                } label: {
                    Text(viewModel.isSubmitting ? "Submitting..." : "Submit Proposal")
                        .font(.mtrxBodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.ms)
                        .background(viewModel.canSubmitProposal ? Color(red: 0.0, green: 0.675, blue: 0.694) : Color.labelTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
                .disabled(!viewModel.canSubmitProposal || viewModel.isSubmitting)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Propose Spending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        viewModel.showProposal = false
                    }
                    .foregroundStyle(Color.labelSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.statusWarning)
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
}

// MARK: - Preview

#Preview {
    TreasuryView()
        .preferredColorScheme(.dark)
}
