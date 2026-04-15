// DelegationView.swift
// MTRX
//
// Voting delegation — current delegations, incoming delegations, delegate form, undelegate, voting power.

import SwiftUI

// MARK: - Data Models

struct DelegationItem: Identifiable {
    let id = UUID()
    let delegator: String
    let delegatee: String
    let token: String
    let amount: String
    let since: String
}

// MARK: - View Model

@MainActor
class DelegationViewModel: ObservableObject {
    @Published var delegatedTo: [DelegationItem] = []
    @Published var delegatedFrom: [DelegationItem] = []
    @Published var showDelegate: Bool = false
    @Published var delegateAddress: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Delegate form
    @Published var delegateToken: String = "MTRX"
    @Published var delegateAmount: String = ""
    @Published var isDelegating: Bool = false

    let availableTokens = ["MTRX", "veMTRX", "UNI", "AAVE"]

    var canDelegate: Bool {
        !delegateAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !delegateAmount.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(delegateAmount) != nil
    }

    var totalVotingPower: String {
        let ownPower = 25_000.0
        let incomingPower = delegatedFrom.compactMap { item -> Double? in
            let cleaned = item.amount.replacingOccurrences(of: ",", with: "").components(separatedBy: " ").first
            return Double(cleaned ?? "0")
        }.reduce(0, +)
        let outgoingPower = delegatedTo.compactMap { item -> Double? in
            let cleaned = item.amount.replacingOccurrences(of: ",", with: "").components(separatedBy: " ").first
            return Double(cleaned ?? "0")
        }.reduce(0, +)
        let total = ownPower + incomingPower - outgoingPower
        return formatTokenAmount(total)
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            try await Task.sleep(for: .milliseconds(600))
            delegatedTo = DelegationViewModel.sampleDelegatedTo
            delegatedFrom = DelegationViewModel.sampleDelegatedFrom
            isLoading = false
        } catch {
            errorMessage = "Unable to load delegation data."
            isLoading = false
        }
    }

    func delegate() async {
        guard canDelegate else { return }
        isDelegating = true

        do {
            try await Task.sleep(for: .seconds(1.5))
            let newDelegation = DelegationItem(
                delegator: "0x1234...abcd",
                delegatee: delegateAddress,
                token: delegateToken,
                amount: "\(delegateAmount) \(delegateToken)",
                since: "Just now"
            )
            delegatedTo.insert(newDelegation, at: 0)
            delegateAddress = ""
            delegateAmount = ""
            isDelegating = false
            showDelegate = false
        } catch {
            isDelegating = false
        }
    }

    func undelegate(_ item: DelegationItem) async {
        do {
            try await Task.sleep(for: .milliseconds(800))
            delegatedTo.removeAll { $0.id == item.id }
        } catch {
            // Handle error silently
        }
    }

    private func formatTokenAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }

    static let sampleDelegatedTo: [DelegationItem] = [
        DelegationItem(delegator: "0x1234...abcd", delegatee: "0xaaaa...1111", token: "MTRX", amount: "5,000 MTRX", since: "Mar 15, 2026"),
        DelegationItem(delegator: "0x1234...abcd", delegatee: "0xbbbb...2222", token: "veMTRX", amount: "2,000 veMTRX", since: "Feb 20, 2026")
    ]

    static let sampleDelegatedFrom: [DelegationItem] = [
        DelegationItem(delegator: "0xcccc...3333", delegatee: "0x1234...abcd", token: "MTRX", amount: "10,000 MTRX", since: "Apr 1, 2026"),
        DelegationItem(delegator: "0xdddd...4444", delegatee: "0x1234...abcd", token: "MTRX", amount: "3,500 MTRX", since: "Mar 28, 2026"),
        DelegationItem(delegator: "0xeeee...5555", delegatee: "0x1234...abcd", token: "veMTRX", amount: "8,000 veMTRX", since: "Mar 10, 2026")
    ]
}

// MARK: - Delegation View

struct DelegationView: View {
    @StateObject private var viewModel = DelegationViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.delegatedTo.isEmpty && viewModel.delegatedFrom.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.delegatedTo.isEmpty && viewModel.delegatedFrom.isEmpty {
                    errorState(message: error)
                } else {
                    delegationContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Delegation")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showDelegate = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                    }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showDelegate) {
                delegateSheet
            }
        }
    }

    // MARK: - Content

    private var delegationContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                votingPowerHeader
                outgoingDelegationsSection
                incomingDelegationsSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Voting Power Header

    private var votingPowerHeader: some View {
        MtrxCard(style: .glass, accentEdge: .top) {
            VStack(spacing: Spacing.sm) {
                Text("Total Voting Power")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)

                Text(viewModel.totalVotingPower)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.labelPrimary)

                HStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.xs) {
                        Text("\(viewModel.delegatedTo.count)")
                            .font(.mtrxHeadlineTabular)
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                        Text("Outgoing")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }

                    Rectangle()
                        .fill(Color.separatorStandard)
                        .frame(width: 1, height: 30)

                    VStack(spacing: Spacing.xs) {
                        Text("\(viewModel.delegatedFrom.count)")
                            .font(.mtrxHeadlineTabular)
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                        Text("Incoming")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Outgoing Delegations

    private var outgoingDelegationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Delegated To")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            if viewModel.delegatedTo.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "arrow.up.forward.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.labelTertiary)
                    Text("No outgoing delegations")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelSecondary)
                    Text("Delegate your voting power to a trusted representative.")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.lg)
            } else {
                ForEach(viewModel.delegatedTo) { delegation in
                    outgoingDelegationRow(delegation)
                }
            }
        }
    }

    private func outgoingDelegationRow(_ delegation: DelegationItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delegatee")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(delegation.delegatee)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color.labelPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(delegation.amount)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                        Text("Since \(delegation.since)")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                Button {
                    Task { await viewModel.undelegate(delegation) }
                } label: {
                    Text("Undelegate")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.statusError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.statusError.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Incoming Delegations

    private var incomingDelegationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Delegated From")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            if viewModel.delegatedFrom.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "arrow.down.backward.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.labelTertiary)
                    Text("No incoming delegations")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.lg)
            } else {
                ForEach(viewModel.delegatedFrom) { delegation in
                    incomingDelegationRow(delegation)
                }
            }
        }
    }

    private func incomingDelegationRow(_ delegation: DelegationItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                ZStack {
                    Circle()
                        .fill(Color.priceUp.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.down.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.priceUp)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(delegation.delegator)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.labelPrimary)
                    Text("Since \(delegation.since)")
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                Text(delegation.amount)
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color.priceUp)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Delegate Sheet

    private var delegateSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Delegate Address
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Delegate Address")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("0x...", text: $viewModel.delegateAddress)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Token Selector
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Token")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.sm) {
                                ForEach(viewModel.availableTokens, id: \.self) { token in
                                    Button {
                                        viewModel.delegateToken = token
                                    } label: {
                                        Text(token)
                                            .font(.mtrxCaptionBold)
                                            .foregroundStyle(viewModel.delegateToken == token ? .white : Color.labelSecondary)
                                            .padding(.horizontal, Spacing.md)
                                            .padding(.vertical, Spacing.sm)
                                            .background(
                                                viewModel.delegateToken == token
                                                    ? Color(red: 0.0, green: 0.675, blue: 0.694)
                                                    : Color.surfaceOverlay
                                            )
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Amount
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Amount")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        HStack {
                            TextField("0", text: $viewModel.delegateAmount)
                                .font(.mtrxMono)
                                .keyboardType(.decimalPad)
                            Text(viewModel.delegateToken)
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelTertiary)
                        }
                        .padding(Spacing.ms)
                        .background(Color.surfaceOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                // Info notice
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.statusInfo)
                    Text("Delegating transfers your voting power to another address. You retain ownership of your tokens and can undelegate at any time.")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(Spacing.md)
                .background(Color.statusInfo.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                .padding(.horizontal, Spacing.contentPadding)

                Spacer()

                Button {
                    Task { await viewModel.delegate() }
                } label: {
                    Text(viewModel.isDelegating ? "Delegating..." : "Delegate")
                        .font(.mtrxBodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.ms)
                        .background(viewModel.canDelegate ? Color(red: 0.0, green: 0.675, blue: 0.694) : Color.labelTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
                .disabled(!viewModel.canDelegate || viewModel.isDelegating)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Delegate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        viewModel.showDelegate = false
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
    DelegationView()
        .preferredColorScheme(.dark)
}
