// ContractView.swift
// MTRX
//
// Contract creation wizard with three-step flow: Template, Configure, Review.

import SwiftUI

// MARK: - Contract ViewModel

@MainActor
final class ContractViewModel: ObservableObject {
    @Published var step: Int = 0
    @Published var selectedTemplate: ContractTemplate?

    // Form fields
    @Published var contractName: String = ""
    @Published var counterpartyAddress: String = ""
    @Published var amount: String = ""
    @Published var selectedDuration: ContractDuration = .thirtyDays
    @Published var customDurationDays: String = ""
    @Published var termsText: String = ""
    @Published var agreedToImmutable: Bool = false

    // State
    @Published var isDeploying: Bool = false
    @Published var deploySuccess: Bool = false
    @Published var deployUnavailable: Bool = false

    // MARK: - Validation

    var isTemplateSelected: Bool { selectedTemplate != nil }

    var isNameValid: Bool {
        !contractName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isAddressValid: Bool {
        let addr = counterpartyAddress.trimmingCharacters(in: .whitespaces)
        return addr.count >= 10 && (addr.hasPrefix("0x") || addr.hasSuffix(".eth"))
    }

    var isAmountValid: Bool {
        guard let val = Double(amount) else { return false }
        return val > 0
    }

    var canProceedFromConfig: Bool {
        isNameValid && isAddressValid && isAmountValid
    }

    var canDeploy: Bool {
        canProceedFromConfig && agreedToImmutable && selectedTemplate != nil
    }

    var estimatedFee: String { "~0.003 ETH ($9.74)" }

    var durationDisplay: String {
        switch selectedDuration {
        case .thirtyDays:  return "30 days"
        case .sixtyDays:   return "60 days"
        case .ninetyDays:  return "90 days"
        case .custom:
            let d = Int(customDurationDays) ?? 0
            return d > 0 ? "\(d) days" : "Custom"
        }
    }

    // MARK: - Navigation

    func goNext() {
        guard step < 2 else { return }
        withAnimation(Motion.springDefault) {
            step += 1
        }
        MtrxHaptics.impact(.light)
    }

    func goBack() {
        guard step > 0 else { return }
        withAnimation(Motion.springDefault) {
            step -= 1
        }
    }

    // MARK: - Deploy

    func deploy() {
        // Honest failure: there is no real on-chain deploy path wired (no signer / no
        // chain configured), so this must NOT fabricate a deployed contract or show
        // "Contract Deployed". Killed the timer-then-success, the fake deploySuccess, the
        // DeployedContractsStore insert, and the off-grid fake. Nothing is deployed.
        isDeploying = false
        deploySuccess = false
        deployUnavailable = true
    }

    func pasteAddress() {
        if let clip = UIPasteboard.general.string {
            counterpartyAddress = clip
            MtrxHaptics.impact(.light)
        }
    }
}

// MARK: - Duration

enum ContractDuration: String, CaseIterable, Identifiable {
    case thirtyDays  = "30 days"
    case sixtyDays   = "60 days"
    case ninetyDays  = "90 days"
    case custom      = "Custom"

    var id: String { rawValue }
}

// MARK: - Template

enum ContractTemplate: String, CaseIterable, Identifiable {
    case escrow       = "Escrow"
    case freelance    = "Freelance"
    case subscription = "Subscription"
    case revenueShare = "Revenue Share"
    case loan         = "Loan"
    case jointOwnership = "Joint Ownership"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .escrow:         return Symbols.escrow
        case .freelance:      return "person.fill"
        case .subscription:   return Symbols.processing
        case .revenueShare:   return Symbols.chartPie
        case .loan:           return Symbols.fee
        case .jointOwnership: return Symbols.groupChat
        }
    }

    var subtitle: String {
        switch self {
        case .escrow:         return "Milestone-based payment release with dispute resolution"
        case .freelance:      return "Time or deliverable-based work agreements"
        case .subscription:   return "Recurring automated payment schedules"
        case .revenueShare:   return "Proportional revenue distribution to parties"
        case .loan:           return "Collateralized lending with repayment terms"
        case .jointOwnership: return "Shared asset ownership and governance"
        }
    }
}

// MARK: - Contract View

struct ContractView: View {
    @StateObject private var viewModel = ContractViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                VStack(spacing: 0) {
                    stepIndicator
                        .padding(.horizontal, Spacing.contentPadding)
                        .padding(.vertical, Spacing.md)

                    // Step content
                    Group {
                        switch viewModel.step {
                        case 0:  templateStep
                        case 1:  configureStep
                        default: reviewStep
                        }
                    }
                }

                // Deploy overlay
                if viewModel.isDeploying {
                    deployingOverlay
                }

                if viewModel.deploySuccess {
                    deploySuccessOverlay
                }
            }
            .alert("Not Available Yet", isPresented: $viewModel.deployUnavailable) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Contract deployment isn't available in this build yet. Nothing was deployed.")
            }
            .navigationTitle("New Contract")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if viewModel.step == 0 {
                            dismiss()
                        } else {
                            viewModel.goBack()
                        }
                    } label: {
                        Image(systemName: viewModel.step == 0 ? Symbols.close : Symbols.back)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                            .accessibilityLabel(viewModel.step == 0 ? "Close" : "Go back")
                    }
                }
            }
            .onAppear {
                withAnimation(Motion.springDefault.delay(0.1)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                let stepLabels = ["Template", "Configure", "Review"]

                // Circle
                VStack(spacing: Spacing.xs) {
                    ZStack {
                        Circle()
                            .fill(stepCircleColor(for: index))
                            .frame(width: 32, height: 32)

                        if index < viewModel.step {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(index == viewModel.step ? .white : Color.labelTertiary)
                        }
                    }

                    Text(stepLabels[index])
                        .font(.mtrxCaption2)
                        .foregroundStyle(index <= viewModel.step ? Color.labelPrimary : Color.labelTertiary)
                }

                // Connecting line
                if index < 2 {
                    Rectangle()
                        .fill(index < viewModel.step ? Color.statusSuccess : Color.surfaceOverlay)
                        .frame(height: 2)
                        .padding(.bottom, Spacing.md)
                }
            }
        }
    }

    private func stepCircleColor(for index: Int) -> Color {
        if index < viewModel.step {
            return .statusSuccess
        } else if index == viewModel.step {
            return .accentPrimary
        }
        return .surfaceOverlay
    }

    // MARK: - Step 1: Template Selection

    private var templateStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    MtrxSectionHeader(
                        title: "Choose Template",
                        subtitle: "Select a contract type to get started"
                    )

                    LazyVGrid(columns: gridColumns, spacing: Spacing.md) {
                        ForEach(ContractTemplate.allCases) { template in
                            templateCard(template)
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.xxxl)
            }

            // Next button (visible when template selected)
            if viewModel.isTemplateSelected {
                Button {
                    viewModel.goNext()
                } label: {
                    Text("Next")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
                .padding(Spacing.contentPadding)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.springDefault, value: viewModel.isTemplateSelected)
    }

    private func templateCard(_ template: ContractTemplate) -> some View {
        let isSelected = viewModel.selectedTemplate == template

        return Button {
            withAnimation(Motion.springSnappy) {
                viewModel.selectedTemplate = template
            }
            MtrxHaptics.impact(.medium)
        } label: {
            MtrxCard(style: .standard) {
                VStack(spacing: Spacing.ms) {
                    Image(systemName: template.icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.accentPrimary)
                        .frame(height: 40)

                    Text(template.rawValue)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)

                    Text(template.subtitle)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                            .stroke(Color.accentPrimary, lineWidth: 2)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Configuration

    private var configureStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    // Selected template badge
                    if let template = viewModel.selectedTemplate {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: template.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentPrimary)
                            Text(template.rawValue)
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.accentPrimary)
                        }
                        .padding(.horizontal, Spacing.ms)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.accentPrimary.opacity(0.12))
                        .clipShape(Capsule())
                    }

                    // Contract name
                    configField(title: "Contract Name") {
                        MtrxTextField(
                            placeholder: "e.g., Website Development Agreement",
                            text: $viewModel.contractName,
                            icon: Symbols.edit
                        )
                    }

                    // Counterparty address
                    configField(title: "Counterparty Address") {
                        HStack(spacing: Spacing.sm) {
                            MtrxTextField(
                                placeholder: "0x... or ENS name",
                                text: $viewModel.counterpartyAddress,
                                icon: Symbols.key
                            )

                            Button {
                                viewModel.pasteAddress()
                            } label: {
                                Image(systemName: Symbols.paste)
                                    .mtrxSymbolStyle(size: 18)
                                    .foregroundStyle(Color.accentPrimary)
                                    .frame(width: 44, height: Spacing.Size.textFieldHeight)
                                    .background(Color.surfaceOverlay)
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                                    .accessibilityLabel("Paste address")
                            }
                        }
                    }

                    // Amount
                    configField(title: "Amount") {
                        HStack(spacing: Spacing.sm) {
                            TextField("0.00", text: $viewModel.amount)
                                .font(.mtrxMono)
                                .keyboardType(.decimalPad)
                                .padding(.horizontal, Spacing.textFieldPadding)
                                .frame(height: Spacing.Size.textFieldHeight)
                                .background(Color.surfaceOverlay)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                            Text("ETH")
                                .font(.mtrxCalloutBold)
                                .foregroundStyle(Color.accentPrimary)
                                .padding(.horizontal, Spacing.ms)
                                .frame(height: Spacing.Size.textFieldHeight)
                                .background(Color.surfaceOverlay)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        }
                    }

                    // Duration picker
                    configField(title: "Duration") {
                        VStack(spacing: Spacing.sm) {
                            Picker("Duration", selection: $viewModel.selectedDuration) {
                                ForEach(ContractDuration.allCases) { duration in
                                    Text(duration.rawValue).tag(duration)
                                }
                            }
                            .pickerStyle(.segmented)

                            if viewModel.selectedDuration == .custom {
                                HStack(spacing: Spacing.sm) {
                                    TextField("Days", text: $viewModel.customDurationDays)
                                        .font(.mtrxMono)
                                        .keyboardType(.numberPad)
                                        .padding(.horizontal, Spacing.textFieldPadding)
                                        .frame(height: Spacing.Size.textFieldHeight)
                                        .background(Color.surfaceOverlay)
                                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                                    Text("days")
                                        .font(.mtrxCallout)
                                        .foregroundStyle(Color.labelSecondary)
                                }
                            }
                        }
                    }

                    // Terms
                    configField(title: "Terms & Conditions") {
                        TextEditor(text: $viewModel.termsText)
                            .font(.mtrxBody)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(Spacing.textFieldPadding)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxxl)
            }

            // Next button
            Button {
                viewModel.goNext()
            } label: {
                Text("Next")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
            .disabled(!viewModel.canProceedFromConfig)
            .padding(Spacing.contentPadding)
            .background(.ultraThinMaterial)
        }
    }

    private func configField(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)
            content()
        }
    }

    // MARK: - Step 3: Review

    private var reviewStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    MtrxSectionHeader(
                        title: "Review Contract",
                        subtitle: "Verify all details before deploying"
                    )

                    // Summary card
                    MtrxCard(style: .elevated) {
                        VStack(spacing: Spacing.ms) {
                            reviewRow(label: "Template", value: viewModel.selectedTemplate?.rawValue ?? "--")
                            MtrxDivider()
                            reviewRow(label: "Name", value: viewModel.contractName)
                            MtrxDivider()
                            reviewRow(label: "Counterparty", value: viewModel.counterpartyAddress, isMono: true)
                            MtrxDivider()
                            reviewRow(label: "Amount", value: "\(viewModel.amount) ETH")
                            MtrxDivider()
                            reviewRow(label: "Duration", value: viewModel.durationDisplay)
                        }
                    }

                    // Terms preview
                    if !viewModel.termsText.isEmpty {
                        MtrxCard(style: .standard) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Terms")
                                    .font(.mtrxHeadline)
                                    .foregroundStyle(Color.labelPrimary)

                                Text(viewModel.termsText)
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                                    .lineSpacing(3)
                            }
                        }
                    }

                    // Network fee estimate
                    MtrxCard(style: .glass) {
                        HStack {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: Symbols.gas)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.accentPrimary)
                                Text("Network Fee")
                                    .font(.mtrxCallout)
                                    .foregroundStyle(Color.labelSecondary)
                            }
                            Spacer()
                            Text(viewModel.estimatedFee)
                                .font(.mtrxMono)
                                .foregroundStyle(Color.labelPrimary)
                        }
                    }

                    // Immutability agreement
                    Button {
                        withAnimation(Motion.springSnappy) {
                            viewModel.agreedToImmutable.toggle()
                        }
                        MtrxHaptics.selection()
                    } label: {
                        HStack(spacing: Spacing.ms) {
                            Image(systemName: viewModel.agreedToImmutable ? "checkmark.square.fill" : "square")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(viewModel.agreedToImmutable ? Color.accentPrimary : Color.labelTertiary)

                            Text("I understand this contract is immutable once deployed")
                                .font(.mtrxCallout)
                                .foregroundStyle(Color.labelPrimary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxxl)
            }

            // Deploy button
            Button {
                viewModel.deploy()
            } label: {
                Text("Deploy Contract")
            }
            .buttonStyle(MtrxButtonStyle(
                variant: .primary,
                size: .large,
                isLoading: viewModel.isDeploying,
                fullWidth: true
            ))
            .disabled(!viewModel.canDeploy || viewModel.isDeploying)
            .padding(Spacing.contentPadding)
            .background(.ultraThinMaterial)
        }
    }

    private func reviewRow(label: String, value: String, isMono: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.mtrxCallout)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value)
                .font(isMono ? .mtrxMonoSmall : .mtrxCalloutBold)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Deploying Overlay

    private var deployingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            MtrxCard(style: .elevated) {
                VStack(spacing: Spacing.lg) {
                    MtrxProgressRing(
                        progress: 0.7,
                        size: 64,
                        lineWidth: 5,
                        color: .accentPrimary,
                        showLabel: false
                    )
                    .mtrxPulse(isActive: true)

                    Text("Deploying Contract")
                        .font(.mtrxTitle3)
                        .foregroundStyle(Color.labelPrimary)

                    Text("Submitting transaction to the network...")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 240)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Success Overlay

    private var deploySuccessOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            MtrxCard(style: .elevated) {
                VStack(spacing: Spacing.lg) {
                    Image(systemName: Symbols.complete)
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color.statusSuccess)
                        .mtrxGlow(color: .statusSuccess, radius: 8)

                    Text("Contract Deployed")
                        .font(.mtrxTitle3)
                        .foregroundStyle(Color.labelPrimary)

                    Text("Your contract is now live on the network.")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
                }
                .frame(width: 260)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Preview

#Preview {
    ContractView()
        .preferredColorScheme(.dark)
}
