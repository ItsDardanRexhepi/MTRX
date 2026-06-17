// DeployContractView.swift
// MTRX
//
// Deploy smart contracts from templates — template library, parameter form, gas estimate, deployment confirmation.

import SwiftUI

// MARK: - Deploy Contract ViewModel

@MainActor
final class DeployContractViewModel: ObservableObject {

    // MARK: - Published State

    @Published var templates: [DeployTemplate] = []
    @Published var selectedTemplate: DeployTemplate?
    @Published var parameterValues: [String: String] = [:]
    @Published var isLoading: Bool = false
    @Published var isDeploying: Bool = false
    @Published var errorMessage: String?
    @Published var deployedAddress: String?
    @Published var showConfirmation: Bool = false
    @Published var gasEstimate: DeployGasEstimate?
    @Published var contentAppeared: Bool = false
    @Published var searchText: String = ""

    // MARK: - Computed

    var filteredTemplates: [DeployTemplate] {
        if searchText.isEmpty { return templates }
        return templates.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    var canDeploy: Bool {
        guard let template = selectedTemplate else { return false }
        return template.parameters.allSatisfy { param in
            guard param.isRequired else { return true }
            let val = parameterValues[param.id] ?? ""
            return !val.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        try? await Task.sleep(nanoseconds: 800_000_000)

        templates = DeployTemplate.sampleData
        gasEstimate = DeployGasEstimate(
            estimatedGwei: 24,
            estimatedUSD: 12.48,
            maxGwei: 32,
            maxUSD: 16.64
        )
        isLoading = false

        withAnimation(Motion.springDefault) {
            contentAppeared = true
        }
    }

    func selectTemplate(_ template: DeployTemplate) {
        withAnimation(Motion.springSnappy) {
            selectedTemplate = template
            parameterValues = [:]
            for param in template.parameters {
                parameterValues[param.id] = param.defaultValue
            }
        }
        MtrxHaptics.selection()
    }

    func deploy() async {
        guard canDeploy else { return }
        isDeploying = true

        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // SIMULATED deploy (no chain configured). Derive a deterministic,
        // content-addressed demo address from the template + params — never the
        // old hardcoded real Uniswap router address. The real on-chain deploy
        // runs through the WalletTransactionService pipeline once PendingCredentials
        // is filled.
        let seed = (selectedTemplate?.name ?? "contract") + "|" + parameterValues
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        deployedAddress = DemoArtifacts.address(seed: seed)
        isDeploying = false
        showConfirmation = false
        MtrxHaptics.success()
    }

    func reset() {
        withAnimation(Motion.springSnappy) {
            selectedTemplate = nil
            parameterValues = [:]
            deployedAddress = nil
            showConfirmation = false
        }
    }
}

// MARK: - Deploy Contract View

struct DeployContractView: View {
    @StateObject private var viewModel = DeployContractViewModel()
    @Environment(\.dismiss) private var dismiss

    private let accent = Color(red: 0.0, green: 0.675, blue: 0.694)

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                Group {
                    if viewModel.isLoading && viewModel.templates.isEmpty {
                        MtrxLoadingView(rows: 8)
                    } else if let error = viewModel.errorMessage {
                        MtrxErrorView(message: error) {
                            Task { await viewModel.load() }
                        }
                    } else if viewModel.deployedAddress != nil {
                        deploySuccessView
                    } else if viewModel.selectedTemplate != nil {
                        parameterFormView
                    } else {
                        templateLibraryView
                    }
                }
            }
            .navigationTitle("Deploy Contract")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.selectedTemplate != nil && viewModel.deployedAddress == nil {
                        Button {
                            viewModel.reset()
                        } label: {
                            Image(systemName: Symbols.back)
                                .foregroundStyle(accent)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: Symbols.close)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showConfirmation) {
                deployConfirmationSheet
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Template Library

    private var templateLibraryView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Spacing.lg) {
                MtrxSearchBar(text: $viewModel.searchText, placeholder: "Search templates")
                    .padding(.horizontal, Spacing.contentPadding)

                if viewModel.filteredTemplates.isEmpty {
                    MtrxEmptyState(
                        icon: Symbols.contractCreate,
                        title: "No Templates Found",
                        message: "Try a different search term."
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: Spacing.md
                    ) {
                        ForEach(Array(viewModel.filteredTemplates.enumerated()), id: \.element.id) { index, template in
                            templateCard(template)
                                .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                }

                Spacer().frame(height: Spacing.xxl)
            }
            .padding(.top, Spacing.sm)
        }
    }

    private func templateCard(_ template: DeployTemplate) -> some View {
        Button {
            viewModel.selectTemplate(template)
        } label: {
            MtrxCard(style: .glass) {
                VStack(alignment: .leading, spacing: Spacing.ms) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                            .fill(template.color.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: template.icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(template.color)
                    }

                    Text(template.name)
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)

                    Text(template.subtitle)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    MtrxBadge(text: template.category, style: .accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Parameter Form

    private var parameterFormView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Spacing.sectionGap) {
                if let template = viewModel.selectedTemplate {
                    // Template header
                    HStack(spacing: Spacing.ms) {
                        MtrxAvatar(symbol: template.icon, color: template.color, size: Spacing.Size.avatarLarge)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(template.name)
                                .font(.mtrxTitle3)
                                .foregroundStyle(Color.labelPrimary)
                            Text(template.subtitle)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    MtrxDivider()
                        .padding(.horizontal, Spacing.contentPadding)

                    // Dynamic parameters
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        MtrxSectionHeader(title: "Parameters")
                            .padding(.horizontal, Spacing.contentPadding)

                        ForEach(template.parameters) { param in
                            parameterField(param)
                                .padding(.horizontal, Spacing.contentPadding)
                        }
                    }

                    // Gas estimate
                    if let gas = viewModel.gasEstimate {
                        gasEstimateSection(gas)
                    }

                    // Deploy button
                    Button {
                        viewModel.showConfirmation = true
                        MtrxHaptics.impact(.medium)
                    } label: {
                        Label("Review & Deploy", systemImage: Symbols.send)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
                    .disabled(!viewModel.canDeploy)
                    .opacity(viewModel.canDeploy ? 1 : 0.5)
                    .padding(.horizontal, Spacing.contentPadding)
                }

                Spacer().frame(height: Spacing.xxl)
            }
            .padding(.top, Spacing.md)
        }
    }

    private func parameterField(_ param: TemplateParameter) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text(param.label)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                if param.isRequired {
                    Text("*")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.statusError)
                }
            }

            switch param.type {
            case .text, .address:
                MtrxTextField(
                    placeholder: param.placeholder,
                    text: binding(for: param.id),
                    keyboardType: param.type == .address ? .asciiCapable : .default
                )
            case .number:
                MtrxTextField(
                    placeholder: param.placeholder,
                    text: binding(for: param.id),
                    keyboardType: .decimalPad
                )
            case .toggle:
                Toggle(isOn: toggleBinding(for: param.id)) {
                    Text(param.placeholder)
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                }
                .tint(accent)
                .padding(.horizontal, Spacing.textFieldPadding)
                .frame(height: Spacing.Size.textFieldHeight)
                .background(Color.surfaceOverlay)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            case .picker:
                Menu {
                    ForEach(param.options, id: \.self) { option in
                        Button(option) {
                            viewModel.parameterValues[param.id] = option
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.parameterValues[param.id] ?? param.placeholder)
                            .font(.mtrxBody)
                            .foregroundStyle(
                                viewModel.parameterValues[param.id] != nil
                                    ? Color.labelPrimary
                                    : Color.labelPlaceholder
                            )
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.horizontal, Spacing.textFieldPadding)
                    .frame(height: Spacing.Size.textFieldHeight)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
            }

            if let hint = param.hint {
                Text(hint)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { viewModel.parameterValues[key] ?? "" },
            set: { viewModel.parameterValues[key] = $0 }
        )
    }

    private func toggleBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.parameterValues[key] == "true" },
            set: { viewModel.parameterValues[key] = $0 ? "true" : "false" }
        )
    }

    // MARK: - Gas Estimate

    private func gasEstimateSection(_ gas: DeployGasEstimate) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    Image(systemName: Symbols.gas)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(accent)
                    Text("Gas Estimate")
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                }

                MtrxDivider()

                HStack {
                    Text("Estimated")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text("\(gas.estimatedGwei) Gwei")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                    Text("(\(formatUSD(gas.estimatedUSD)))")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelSecondary)
                }

                HStack {
                    Text("Max")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text("\(gas.maxGwei) Gwei")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                    Text("(\(formatUSD(gas.maxUSD)))")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Confirmation Sheet

    private var deployConfirmationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(title: "Confirm Deployment") {
                        viewModel.showConfirmation = false
                    }

                    // Warning banner
                    HStack(spacing: Spacing.ms) {
                        Image(systemName: Symbols.alertWarning)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.statusWarning)

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Irreversible Action")
                                .font(.mtrxHeadline)
                                .foregroundStyle(Color.statusWarning)
                            Text("You're about to deploy a live contract. This cannot be undone.")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.statusWarning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                            .stroke(Color.statusWarning.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, Spacing.contentPadding)

                    // Summary
                    if let template = viewModel.selectedTemplate {
                        MtrxCard(style: .elevated) {
                            VStack(spacing: Spacing.ms) {
                                summaryRow(label: "Template", value: template.name)
                                MtrxDivider()
                                summaryRow(label: "Network", value: "Ethereum Mainnet")
                                MtrxDivider()

                                ForEach(template.parameters) { param in
                                    let value = viewModel.parameterValues[param.id] ?? "N/A"
                                    summaryRow(label: param.label, value: value)
                                    if param.id != template.parameters.last?.id {
                                        MtrxDivider()
                                    }
                                }

                                if let gas = viewModel.gasEstimate {
                                    MtrxDivider()
                                    summaryRow(label: "Est. Gas Fee", value: formatUSD(gas.estimatedUSD))
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.contentPadding)
                    }

                    // Deploy button
                    Button {
                        MtrxHaptics.impact(.heavy)
                        Task { await viewModel.deploy() }
                    } label: {
                        Label("Deploy Contract", systemImage: Symbols.send)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .destructive, size: .large, isLoading: viewModel.isDeploying, fullWidth: true))
                    .disabled(viewModel.isDeploying)
                    .padding(.horizontal, Spacing.contentPadding)

                    Button {
                        viewModel.showConfirmation = false
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .regular))
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value)
                .font(.mtrxMonoSmall)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Deploy Success

    private var deploySuccessView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: Symbols.complete)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.statusSuccess)
                .mtrxGlow(color: .statusSuccess)

            VStack(spacing: Spacing.sm) {
                Text("Contract Deployed")
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)

                Text("Your contract is now live on Ethereum Mainnet.")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
            }

            if let address = viewModel.deployedAddress {
                MtrxCard(style: .elevated) {
                    VStack(spacing: Spacing.ms) {
                        Text("Contract Address")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        Text(address)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: Spacing.md) {
                            Button {
                                UIPasteboard.general.string = address
                                MtrxHaptics.success()
                            } label: {
                                Label("Copy", systemImage: Symbols.copy)
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))

                            Button {
                                // Open Etherscan
                            } label: {
                                Label("Etherscan", systemImage: Symbols.externalLink)
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.contentPadding)
            }

            Spacer()

            Button {
                viewModel.reset()
            } label: {
                Text("Deploy Another")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
            .padding(.horizontal, Spacing.contentPadding)

            Spacer().frame(height: Spacing.xl)
        }
        .mtrxFadeInFromBottom(isVisible: true)
    }

    // MARK: - Helpers

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Data Models

struct DeployTemplate: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let icon: String
    let color: Color
    let category: String
    let parameters: [TemplateParameter]

    static let sampleData: [DeployTemplate] = [
        DeployTemplate(
            name: "ERC-20", subtitle: "Fungible token standard",
            icon: "circle.circle.fill", color: .statusInfo, category: "Token",
            parameters: [
                TemplateParameter(label: "Token Name", placeholder: "My Token", type: .text, isRequired: true),
                TemplateParameter(label: "Symbol", placeholder: "MTK", type: .text, isRequired: true),
                TemplateParameter(label: "Initial Supply", placeholder: "1000000", type: .number, isRequired: true),
                TemplateParameter(label: "Decimals", placeholder: "18", type: .number, defaultValue: "18"),
                TemplateParameter(label: "Mintable", placeholder: "Allow future minting", type: .toggle, defaultValue: "false"),
                TemplateParameter(label: "Burnable", placeholder: "Allow token burning", type: .toggle, defaultValue: "false"),
            ]
        ),
        DeployTemplate(
            name: "ERC-721", subtitle: "Non-fungible token standard",
            icon: "square.stack.3d.up.fill", color: .purple, category: "NFT",
            parameters: [
                TemplateParameter(label: "Collection Name", placeholder: "My NFT Collection", type: .text, isRequired: true),
                TemplateParameter(label: "Symbol", placeholder: "MNFT", type: .text, isRequired: true),
                TemplateParameter(label: "Base URI", placeholder: "https://api.example.com/metadata/", type: .text, isRequired: true),
                TemplateParameter(label: "Max Supply", placeholder: "10000", type: .number),
            ]
        ),
        DeployTemplate(
            name: "ERC-1155", subtitle: "Multi-token standard",
            icon: "square.stack.3d.down.right.fill", color: .orange, category: "Multi-Token",
            parameters: [
                TemplateParameter(label: "Collection Name", placeholder: "Multi Token", type: .text, isRequired: true),
                TemplateParameter(label: "Base URI", placeholder: "https://api.example.com/token/", type: .text, isRequired: true),
            ]
        ),
        DeployTemplate(
            name: "Multi-sig", subtitle: "Multi-signature wallet",
            icon: "person.3.fill", color: .statusSuccess, category: "Wallet",
            parameters: [
                TemplateParameter(label: "Wallet Name", placeholder: "Team Wallet", type: .text, isRequired: true),
                TemplateParameter(label: "Signer 1", placeholder: "0x...", type: .address, isRequired: true),
                TemplateParameter(label: "Signer 2", placeholder: "0x...", type: .address, isRequired: true),
                TemplateParameter(label: "Signer 3", placeholder: "0x...", type: .address),
                TemplateParameter(label: "Threshold", placeholder: "2", type: .number, isRequired: true, hint: "Minimum signatures required"),
            ]
        ),
        DeployTemplate(
            name: "DAO", subtitle: "Governance token + treasury",
            icon: Symbols.dao, color: Color(red: 0.0, green: 0.675, blue: 0.694), category: "Governance",
            parameters: [
                TemplateParameter(label: "DAO Name", placeholder: "My DAO", type: .text, isRequired: true),
                TemplateParameter(label: "Token Symbol", placeholder: "GOV", type: .text, isRequired: true),
                TemplateParameter(label: "Voting Period", placeholder: "3 days", type: .picker, options: ["1 day", "3 days", "5 days", "7 days"]),
                TemplateParameter(label: "Quorum", placeholder: "10", type: .number, hint: "Percentage of votes needed"),
            ]
        ),
        DeployTemplate(
            name: "Escrow", subtitle: "Conditional payment escrow",
            icon: Symbols.escrow, color: .accentTertiary, category: "Payment",
            parameters: [
                TemplateParameter(label: "Beneficiary", placeholder: "0x...", type: .address, isRequired: true),
                TemplateParameter(label: "Arbiter", placeholder: "0x...", type: .address, isRequired: true),
                TemplateParameter(label: "Release Condition", placeholder: "Describe the release condition", type: .text, isRequired: true),
            ]
        ),
        DeployTemplate(
            name: "Vesting", subtitle: "Token vesting schedule",
            icon: "clock.arrow.circlepath", color: .pink, category: "Token",
            parameters: [
                TemplateParameter(label: "Token Address", placeholder: "0x...", type: .address, isRequired: true),
                TemplateParameter(label: "Beneficiary", placeholder: "0x...", type: .address, isRequired: true),
                TemplateParameter(label: "Total Amount", placeholder: "1000000", type: .number, isRequired: true),
                TemplateParameter(label: "Cliff (months)", placeholder: "12", type: .number, isRequired: true),
                TemplateParameter(label: "Duration (months)", placeholder: "48", type: .number, isRequired: true),
            ]
        ),
        DeployTemplate(
            name: "Timelock", subtitle: "Time-delayed execution",
            icon: "lock.badge.clock.fill", color: .statusWarning, category: "Security",
            parameters: [
                TemplateParameter(label: "Admin Address", placeholder: "0x...", type: .address, isRequired: true),
                TemplateParameter(label: "Min Delay", placeholder: "86400", type: .number, isRequired: true, hint: "Minimum delay in seconds (86400 = 1 day)"),
                TemplateParameter(label: "Proposers", placeholder: "0x...", type: .address, isRequired: true),
                TemplateParameter(label: "Executors", placeholder: "0x...", type: .address, isRequired: true),
            ]
        ),
    ]
}

struct TemplateParameter: Identifiable {
    let id = UUID().uuidString
    let label: String
    let placeholder: String
    var type: ParamType = .text
    var isRequired: Bool = false
    var defaultValue: String? = nil
    var hint: String? = nil
    var options: [String] = []

    enum ParamType {
        case text, number, address, toggle, picker
    }
}

struct DeployGasEstimate {
    let estimatedGwei: Int
    let estimatedUSD: Double
    let maxGwei: Int
    let maxUSD: Double
}

// MARK: - Preview

#Preview {
    DeployContractView()
}
