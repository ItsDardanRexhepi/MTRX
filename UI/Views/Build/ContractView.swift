// ContractView.swift
// MTRX
//
// Component 1 — Contract creation wizard with template selection and parameter configuration.

import SwiftUI

// MARK: - Contract View (Creation Wizard)

struct ContractView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: ContractWizardStep = .template
    @State private var selectedTemplate: ContractTemplateType?
    @State private var contractName: String = ""
    @State private var counterpartyAddress: String = ""
    @State private var totalValue: String = ""
    @State private var selectedToken: String = "USDC"
    @State private var milestones: [MilestoneInput] = [MilestoneInput()]
    @State private var disputeResolution: DisputeResolutionType = .arbitration
    @State private var expirationDays: Int = 30
    @State private var showConfirmation: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            stepContent
            navigationButtons
        }
        .navigationTitle("New Contract")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Deploy Contract?", isPresented: $showConfirmation) {
            Button("Deploy", role: .none) { deployContract() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will deploy the contract to the blockchain. Gas fees will apply.")
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(ContractWizardStep.allCases, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentPrimary : Color.surfaceOverlay)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                switch currentStep {
                case .template:
                    templateSelectionStep
                case .details:
                    detailsStep
                case .milestones:
                    milestonesStep
                case .terms:
                    termsStep
                case .review:
                    reviewStep
                }
            }
            .padding(Spacing.contentPadding)
        }
    }

    // MARK: - Step 1: Template Selection

    private var templateSelectionStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Choose Template")
                .font(.mtrxTitle2)

            Text("Select a contract template to get started.")
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)

            ForEach(ContractTemplateType.allCases, id: \.self) { template in
                Button {
                    withAnimation(Motion.springSnappy) {
                        selectedTemplate = template
                    }
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: template.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: Spacing.Size.avatarMedium, height: Spacing.Size.avatarMedium)
                            .background(Color.accentPrimary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.mtrxBodyBold)
                                .foregroundStyle(Color.labelPrimary)
                            Text(template.description_)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }

                        Spacer()

                        if selectedTemplate == template {
                            Image(systemName: Symbols.complete)
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                            .stroke(selectedTemplate == template ? Color.accentPrimary : Color.separatorStandard, lineWidth: selectedTemplate == template ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Step 2: Details

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Contract Details")
                .font(.mtrxTitle2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Contract Name")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                TextField("e.g., Website Development", text: $contractName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Counterparty Address")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                HStack {
                    TextField("0x... or ENS name", text: $counterpartyAddress)
                        .font(.mtrxMono)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        // Paste from clipboard or scan QR
                    } label: {
                        Image(systemName: Symbols.qrScanner)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Total Value")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                HStack {
                    TextField("0.00", text: $totalValue)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    Picker("Token", selection: $selectedToken) {
                        Text("USDC").tag("USDC")
                        Text("ETH").tag("ETH")
                        Text("DAI").tag("DAI")
                        Text("USDT").tag("USDT")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: - Step 3: Milestones

    private var milestonesStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Milestones")
                .font(.mtrxTitle2)

            Text("Define payment milestones for phased release of funds.")
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)

            ForEach($milestones) { $milestone in
                VStack(spacing: Spacing.sm) {
                    HStack {
                        Text("Milestone \(milestones.firstIndex(where: { $0.id == milestone.id }).map { $0 + 1 } ?? 0)")
                            .font(.mtrxCaptionBold)
                        Spacer()
                        if milestones.count > 1 {
                            Button {
                                milestones.removeAll { $0.id == milestone.id }
                            } label: {
                                Image(systemName: Symbols.remove)
                                    .foregroundStyle(Color.statusError)
                            }
                        }
                    }

                    TextField("Description", text: $milestone.description_)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        TextField("Amount", text: $milestone.amount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text(selectedToken)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                .padding(Spacing.sm)
                .background(Color.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }

            Button {
                milestones.append(MilestoneInput())
            } label: {
                Label("Add Milestone", systemImage: Symbols.add)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.accentPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.sm)
                    .background(Color.accentPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
        }
    }

    // MARK: - Step 4: Terms

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Terms & Conditions")
                .font(.mtrxTitle2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Dispute Resolution")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)

                Picker("Resolution", selection: $disputeResolution) {
                    ForEach(DisputeResolutionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Expiration")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)

                Stepper("\(expirationDays) days", value: $expirationDays, in: 7...365, step: 7)
            }
        }
    }

    // MARK: - Step 5: Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Review Contract")
                .font(.mtrxTitle2)

            ReviewRow(label: "Template", value: selectedTemplate?.title ?? "None")
            ReviewRow(label: "Name", value: contractName)
            ReviewRow(label: "Counterparty", value: counterpartyAddress.isEmpty ? "Not set" : counterpartyAddress)
            ReviewRow(label: "Value", value: "\(totalValue) \(selectedToken)")
            ReviewRow(label: "Milestones", value: "\(milestones.count)")
            ReviewRow(label: "Dispute", value: disputeResolution.rawValue)
            ReviewRow(label: "Expiration", value: "\(expirationDays) days")

            Text("Estimated gas: ~0.003 ETH")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: Spacing.md) {
            if currentStep != .template {
                Button {
                    withAnimation(Motion.springDefault) {
                        currentStep = currentStep.previous
                    }
                } label: {
                    Text("Back")
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.accentPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Spacing.Size.buttonHeight)
                        .background(Color.accentPrimary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
            }

            Button {
                if currentStep == .review {
                    showConfirmation = true
                } else {
                    withAnimation(Motion.springDefault) {
                        currentStep = currentStep.next
                    }
                }
            } label: {
                Text(currentStep == .review ? "Deploy" : "Next")
                    .font(.mtrxHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Spacing.Size.buttonHeight)
                    .background(canProceed ? Color.accentPrimary : Color.labelTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
            .disabled(!canProceed)
        }
        .padding(Spacing.contentPadding)
        .background(.ultraThinMaterial)
    }

    // MARK: - Validation

    private var canProceed: Bool {
        switch currentStep {
        case .template: return selectedTemplate != nil
        case .details: return !contractName.isEmpty && !counterpartyAddress.isEmpty
        case .milestones: return !milestones.isEmpty
        case .terms: return true
        case .review: return true
        }
    }

    // MARK: - Actions

    private func deployContract() {
        dismiss()
    }
}

// MARK: - Review Row

struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value)
                .font(.mtrxBodyBold)
                .foregroundStyle(Color.labelPrimary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Wizard Step

enum ContractWizardStep: Int, CaseIterable {
    case template = 0
    case details = 1
    case milestones = 2
    case terms = 3
    case review = 4

    var next: ContractWizardStep {
        ContractWizardStep(rawValue: min(rawValue + 1, 4)) ?? .review
    }

    var previous: ContractWizardStep {
        ContractWizardStep(rawValue: max(rawValue - 1, 0)) ?? .template
    }
}

// MARK: - Contract Template Type

enum ContractTemplateType: String, CaseIterable {
    case escrow, freelance, subscription, lease, insurance

    var title: String {
        switch self {
        case .escrow: return "Escrow"
        case .freelance: return "Freelance"
        case .subscription: return "Subscription"
        case .lease: return "Lease"
        case .insurance: return "Insurance"
        }
    }

    var description_: String {
        switch self {
        case .escrow: return "Milestone-based payment release"
        case .freelance: return "Time-based or deliverable-based work"
        case .subscription: return "Recurring automated payments"
        case .lease: return "Property or asset rental agreement"
        case .insurance: return "Parametric insurance policy"
        }
    }

    var icon: String {
        switch self {
        case .escrow: return Symbols.escrow
        case .freelance: return Symbols.contract
        case .subscription: return Symbols.processing
        case .lease: return Symbols.property
        case .insurance: return Symbols.insurance
        }
    }
}

// MARK: - Dispute Resolution

enum DisputeResolutionType: String, CaseIterable {
    case arbitration = "Arbitration"
    case dao = "DAO Vote"
    case oracle = "Oracle"
}

// MARK: - Milestone Input

struct MilestoneInput: Identifiable {
    let id = UUID()
    var description_: String = ""
    var amount: String = ""
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ContractView()
    }
}
