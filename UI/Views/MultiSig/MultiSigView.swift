// MultiSigView.swift
// MTRX
//
// Multi-signature wallet management — wallets, pending transactions, create wallet, propose transactions.

import SwiftUI

// MARK: - MultiSig ViewModel

@MainActor
final class MultiSigViewModel: ObservableObject {

    // MARK: - Published State

    @Published var wallets: [MultiSigWallet] = []
    @Published var selectedWallet: MultiSigWallet?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showCreateWallet: Bool = false
    @Published var showProposeTransaction: Bool = false
    @Published var contentAppeared: Bool = false

    // Create wallet form
    @Published var walletName: String = ""
    @Published var signerAddresses: [String] = ["", "", ""]
    @Published var threshold: String = "2"
    @Published var isCreating: Bool = false

    // Propose transaction form
    @Published var txDescription: String = ""
    @Published var txRecipient: String = ""
    @Published var txAmount: String = ""
    @Published var txToken: String = "ETH"
    @Published var isProposing: Bool = false

    // MARK: - Computed

    var validSigners: [String] {
        signerAddresses.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var canCreateWallet: Bool {
        !walletName.trimmingCharacters(in: .whitespaces).isEmpty &&
        validSigners.count >= 2 &&
        (Int(threshold) ?? 0) >= 1 &&
        (Int(threshold) ?? 0) <= validSigners.count
    }

    var canPropose: Bool {
        !txDescription.trimmingCharacters(in: .whitespaces).isEmpty &&
        !txRecipient.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Double(txAmount) ?? 0) > 0
    }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        try? await Task.sleep(nanoseconds: 800_000_000)

        wallets = MultiSigWallet.sampleData
        isLoading = false

        withAnimation(Motion.springDefault) {
            contentAppeared = true
        }
    }

    func createWallet() async {
        guard canCreateWallet else { return }
        isCreating = true

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let newWallet = MultiSigWallet(
            name: walletName,
            // Simulated address (no chain configured) — deterministic, not a real deploy.
            address: DemoArtifacts.address(seed: "multisig|\(walletName)|\(validSigners.joined(separator: ","))"),
            threshold: Int(threshold) ?? 2,
            signers: validSigners,
            balanceETH: 0,
            balanceUSD: 0,
            pendingTransactions: []
        )
        wallets.insert(newWallet, at: 0)
        isCreating = false
        showCreateWallet = false
        walletName = ""
        signerAddresses = ["", "", ""]
        threshold = "2"
        MtrxHaptics.success()
    }

    func proposeTransaction() async {
        guard canPropose, let wallet = selectedWallet else { return }
        isProposing = true

        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let newTx = PendingMultiSigTx(
            description_: txDescription,
            recipient: txRecipient,
            amount: Double(txAmount) ?? 0,
            token: txToken,
            signaturesCollected: 1,
            signaturesRequired: wallet.threshold,
            proposedBy: "You",
            proposedDate: Date()
        )

        if let index = wallets.firstIndex(where: { $0.id == wallet.id }) {
            wallets[index].pendingTransactions.insert(newTx, at: 0)
            selectedWallet = wallets[index]
        }

        isProposing = false
        showProposeTransaction = false
        txDescription = ""
        txRecipient = ""
        txAmount = ""
        MtrxHaptics.success()
    }

    func approveTransaction(_ tx: PendingMultiSigTx, in wallet: MultiSigWallet) {
        if let wIndex = wallets.firstIndex(where: { $0.id == wallet.id }),
           let tIndex = wallets[wIndex].pendingTransactions.firstIndex(where: { $0.id == tx.id }) {
            wallets[wIndex].pendingTransactions[tIndex].signaturesCollected += 1
            selectedWallet = wallets[wIndex]
        }
        MtrxHaptics.impact(.medium)
    }

    func rejectTransaction(_ tx: PendingMultiSigTx, in wallet: MultiSigWallet) {
        if let wIndex = wallets.firstIndex(where: { $0.id == wallet.id }),
           let tIndex = wallets[wIndex].pendingTransactions.firstIndex(where: { $0.id == tx.id }) {
            wallets[wIndex].pendingTransactions[tIndex].rejected = true
            selectedWallet = wallets[wIndex]
        }
        MtrxHaptics.warning()
    }

    func addSignerField() {
        signerAddresses.append("")
    }
}

// MARK: - MultiSig View

struct MultiSigView: View {
    @StateObject private var viewModel = MultiSigViewModel()

    private let accent = Color(red: 0.0, green: 0.675, blue: 0.694)

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                if viewModel.isLoading && viewModel.wallets.isEmpty {
                    MtrxLoadingView(rows: 6)
                } else if let error = viewModel.errorMessage {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else if let wallet = viewModel.selectedWallet {
                    walletDetailView(wallet)
                } else {
                    walletsListView
                }
            }
            .navigationTitle(viewModel.selectedWallet != nil ? viewModel.selectedWallet!.name : "Multi-Sig")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.selectedWallet != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(Motion.springSnappy) {
                                viewModel.selectedWallet = nil
                            }
                        } label: {
                            Image(systemName: Symbols.back)
                                .accessibilityLabel("Back to wallets")
                                .foregroundStyle(accent)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.selectedWallet == nil {
                        Button {
                            viewModel.showCreateWallet = true
                            MtrxHaptics.impact(.medium)
                        } label: {
                            Image(systemName: Symbols.addCircle)
                                .accessibilityLabel("Create multisig wallet")
                                .foregroundStyle(accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showCreateWallet) {
                createWalletSheet
            }
            .sheet(isPresented: $viewModel.showProposeTransaction) {
                proposeTransactionSheet
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Wallets List

    private var walletsListView: some View {
        Group {
            if viewModel.wallets.isEmpty {
                MtrxEmptyState(
                    icon: "person.3.fill",
                    title: "No Multi-Sig Wallets",
                    message: "Create a multi-signature wallet to manage funds with multiple signers.",
                    actionLabel: "Create Wallet"
                ) {
                    viewModel.showCreateWallet = true
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(Array(viewModel.wallets.enumerated()), id: \.element.id) { index, wallet in
                            Button {
                                withAnimation(Motion.springSnappy) {
                                    viewModel.selectedWallet = wallet
                                }
                                MtrxHaptics.selection()
                            } label: {
                                walletCard(wallet)
                            }
                            .buttonStyle(.plain)
                            .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                        }
                        Spacer().frame(height: Spacing.xxl)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                }
            }
        }
    }

    private func walletCard(_ wallet: MultiSigWallet) -> some View {
        MtrxCard(style: .standard, accentEdge: .leading) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(wallet.name)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)

                        Text(wallet.address)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    MtrxBadge(text: "\(wallet.threshold) of \(wallet.signers.count)", style: .accent)
                }

                MtrxDivider()

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Balance")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(String(format: "%.4f ETH", wallet.balanceETH))
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Pending")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        let pendingCount = wallet.pendingTransactions.filter { !$0.rejected }.count
                        Text("\(pendingCount) tx")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(pendingCount > 0 ? Color.statusWarning : Color.labelSecondary)
                    }

                    Image(systemName: Symbols.forward)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                        .padding(.leading, Spacing.sm)
                }
            }
        }
    }

    // MARK: - Wallet Detail

    private func walletDetailView(_ wallet: MultiSigWallet) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Spacing.sectionGap) {
                // Balance
                MtrxCard(style: .glass) {
                    VStack(spacing: Spacing.sm) {
                        Text("Balance")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Text(String(format: "%.4f ETH", wallet.balanceETH))
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.labelPrimary)
                        Text(String(format: "$%.2f", wallet.balanceUSD))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.contentPadding)

                // Signers
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    MtrxSectionHeader(title: "Signers", subtitle: "\(wallet.threshold) of \(wallet.signers.count) required")
                        .padding(.horizontal, Spacing.contentPadding)

                    ForEach(wallet.signers, id: \.self) { signer in
                        HStack(spacing: Spacing.ms) {
                            MtrxAvatar(symbol: "person.fill", color: accent, size: 28)
                            Text(signer)
                                .font(.mtrxMonoSmall)
                                .foregroundStyle(Color.labelPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.contentPadding)
                    }
                }

                // Pending transactions
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        MtrxSectionHeader(title: "Pending Transactions")
                        Spacer()
                        Button {
                            viewModel.showProposeTransaction = true
                            MtrxHaptics.impact(.medium)
                        } label: {
                            Label("Propose", systemImage: Symbols.add)
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    let activeTx = wallet.pendingTransactions.filter { !$0.rejected }
                    if activeTx.isEmpty {
                        MtrxEmptyState(
                            icon: Symbols.transaction,
                            title: "No Pending Transactions",
                            message: "Propose a transaction for signers to review."
                        )
                        .frame(height: 180)
                    } else {
                        ForEach(activeTx) { tx in
                            pendingTxCard(tx, wallet: wallet)
                                .padding(.horizontal, Spacing.contentPadding)
                        }
                    }
                }

                Spacer().frame(height: Spacing.xxl)
            }
            .padding(.top, Spacing.md)
        }
    }

    private func pendingTxCard(_ tx: PendingMultiSigTx, wallet: MultiSigWallet) -> some View {
        MtrxCard(style: .elevated) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    Text(tx.description_)
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(2)
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("To")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(tx.recipient)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Amount")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(String(format: "%.4f %@", tx.amount, tx.token))
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                    }
                }

                MtrxDivider()

                HStack {
                    // Signatures progress
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Signatures")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        HStack(spacing: Spacing.xs) {
                            ForEach(0..<tx.signaturesRequired, id: \.self) { i in
                                Circle()
                                    .fill(i < tx.signaturesCollected ? Color.statusSuccess : Color.surfaceOverlay)
                                    .frame(width: 10, height: 10)
                            }
                            Text("\(tx.signaturesCollected)/\(tx.signaturesRequired)")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: Spacing.sm) {
                        Button {
                            viewModel.approveTransaction(tx, in: wallet)
                        } label: {
                            Label("Approve", systemImage: Symbols.complete)
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))

                        Button {
                            viewModel.rejectTransaction(tx, in: wallet)
                        } label: {
                            Image(systemName: Symbols.close)
                                .accessibilityLabel("Reject transaction")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .destructive, size: .compact))
                    }
                }
            }
        }
    }

    // MARK: - Create Wallet Sheet

    private var createWalletSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(title: "Create Multi-Sig", subtitle: "Set up a multi-signature wallet") {
                        viewModel.showCreateWallet = false
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        fieldLabel("Wallet Name", required: true)
                        MtrxTextField(placeholder: "Team Treasury", text: $viewModel.walletName, icon: Symbols.wallet)

                        fieldLabel("Signers", required: true)
                        ForEach(viewModel.signerAddresses.indices, id: \.self) { index in
                            MtrxTextField(
                                placeholder: "Signer \(index + 1) address (0x...)",
                                text: $viewModel.signerAddresses[index],
                                icon: "person.fill"
                            )
                        }

                        Button {
                            viewModel.addSignerField()
                            MtrxHaptics.impact(.light)
                        } label: {
                            Label("Add Signer", systemImage: Symbols.addCircle)
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))

                        fieldLabel("Threshold", required: true)
                        MtrxTextField(
                            placeholder: "2",
                            text: $viewModel.threshold,
                            icon: Symbols.key,
                            keyboardType: .numberPad
                        )
                        Text("Minimum number of signatures required to execute a transaction")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    Button {
                        MtrxHaptics.impact(.medium)
                        Task { await viewModel.createWallet() }
                    } label: {
                        Label("Create Wallet", systemImage: Symbols.wallet)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: viewModel.isCreating, fullWidth: true))
                    .disabled(!viewModel.canCreateWallet || viewModel.isCreating)
                    .opacity(viewModel.canCreateWallet ? 1 : 0.5)
                    .padding(.horizontal, Spacing.contentPadding)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Propose Transaction Sheet

    private var proposeTransactionSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(title: "Propose Transaction") {
                        viewModel.showProposeTransaction = false
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        fieldLabel("Description", required: true)
                        MtrxTextField(placeholder: "Pay contractor for Q1 work", text: $viewModel.txDescription, icon: Symbols.contract)

                        fieldLabel("Recipient", required: true)
                        MtrxTextField(placeholder: "0x...", text: $viewModel.txRecipient, icon: "person.fill")

                        fieldLabel("Amount", required: true)
                        HStack(spacing: Spacing.sm) {
                            MtrxTextField(placeholder: "1.5", text: $viewModel.txAmount, keyboardType: .decimalPad)
                            Menu {
                                ForEach(["ETH", "USDC", "DAI", "WETH"], id: \.self) { token in
                                    Button(token) { viewModel.txToken = token }
                                }
                            } label: {
                                Text(viewModel.txToken)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, Spacing.md)
                                    .frame(height: Spacing.Size.textFieldHeight)
                                    .background(Color.surfaceOverlay)
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    Button {
                        MtrxHaptics.impact(.medium)
                        Task { await viewModel.proposeTransaction() }
                    } label: {
                        Label("Submit Proposal", systemImage: Symbols.send)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: viewModel.isProposing, fullWidth: true))
                    .disabled(!viewModel.canPropose || viewModel.isProposing)
                    .opacity(viewModel.canPropose ? 1 : 0.5)
                    .padding(.horizontal, Spacing.contentPadding)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func fieldLabel(_ text: String, required: Bool = false) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(text)
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)
            if required {
                Text("*")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.statusError)
            }
        }
    }
}

// MARK: - Data Models

struct MultiSigWallet: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let threshold: Int
    let signers: [String]
    let balanceETH: Double
    let balanceUSD: Double
    var pendingTransactions: [PendingMultiSigTx]

    static let sampleData: [MultiSigWallet] = [
        MultiSigWallet(
            name: "Team Treasury",
            address: DemoArtifacts.address(seed: "Team Treasury"),
            threshold: 2, signers: ["0x1a2b...3c4d", "0x5e6f...7890", "0xabcd...ef01"],
            balanceETH: 12.5, balanceUSD: 42_500,
            pendingTransactions: [
                PendingMultiSigTx(description_: "Pay audit firm for Q1 security review", recipient: "0xaaaa...bbbb", amount: 2.5, token: "ETH", signaturesCollected: 1, signaturesRequired: 2, proposedBy: "0x1a2b...3c4d", proposedDate: Calendar.current.date(byAdding: .hour, value: -6, to: Date())!),
                PendingMultiSigTx(description_: "Fund marketing campaign", recipient: "0xcccc...dddd", amount: 5000, token: "USDC", signaturesCollected: 0, signaturesRequired: 2, proposedBy: "0x5e6f...7890", proposedDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!),
            ]
        ),
        MultiSigWallet(
            name: "Operations Fund",
            address: DemoArtifacts.address(seed: "Operations Fund"),
            threshold: 3, signers: ["0x1a2b...3c4d", "0x5e6f...7890", "0xabcd...ef01", "0x9876...5432"],
            balanceETH: 5.8, balanceUSD: 19_720,
            pendingTransactions: []
        ),
    ]
}

struct PendingMultiSigTx: Identifiable {
    let id = UUID()
    let description_: String
    let recipient: String
    let amount: Double
    let token: String
    var signaturesCollected: Int
    let signaturesRequired: Int
    let proposedBy: String
    let proposedDate: Date
    var rejected: Bool = false
}

// MARK: - Preview

#Preview {
    MultiSigView()
}
