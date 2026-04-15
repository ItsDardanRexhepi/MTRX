// InsuranceView.swift
// MTRX
//
// DeFi insurance — coverage options, active policies, file claims, coverage calculator.

import SwiftUI

// MARK: - Data Models

struct CoverageItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let maxCoverage: String
    let premiumRate: String
    let riskType: String
}

struct PolicyItem: Identifiable {
    let id = UUID()
    let coverageName: String
    let amount: String
    let premium: String
    let endDate: String
    let status: String
}

// MARK: - View Model

@MainActor
class InsuranceViewModel: ObservableObject {
    @Published var coverages: [CoverageItem] = []
    @Published var policies: [PolicyItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var calculatorAmount: String = ""
    @Published var selectedCoverage: CoverageItem?
    @Published var showFileClaim: Bool = false

    var estimatedPremium: String {
        guard let amount = Double(calculatorAmount), amount > 0, let coverage = selectedCoverage else {
            return "$0.00"
        }
        let rateString = coverage.premiumRate.replacingOccurrences(of: "%", with: "")
        let rate = Double(rateString) ?? 2.5
        let premium = amount * (rate / 100)
        return String(format: "$%.2f", premium)
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            try await Task.sleep(for: .milliseconds(600))
            coverages = InsuranceViewModel.sampleCoverages
            policies = InsuranceViewModel.samplePolicies
            isLoading = false
        } catch {
            errorMessage = "Unable to load insurance data."
            isLoading = false
        }
    }

    static let sampleCoverages: [CoverageItem] = [
        CoverageItem(name: "Smart Contract", description: "Protection against smart contract exploits and vulnerabilities", maxCoverage: "$500,000", premiumRate: "2.5%", riskType: "Protocol"),
        CoverageItem(name: "Stablecoin Depeg", description: "Coverage for stablecoin depegging events below threshold", maxCoverage: "$250,000", premiumRate: "1.8%", riskType: "Market"),
        CoverageItem(name: "Oracle Failure", description: "Protection against oracle manipulation or data feed failures", maxCoverage: "$300,000", premiumRate: "3.2%", riskType: "Technical"),
        CoverageItem(name: "Bridge Exploit", description: "Coverage for cross-chain bridge security incidents", maxCoverage: "$400,000", premiumRate: "4.0%", riskType: "Infrastructure")
    ]

    static let samplePolicies: [PolicyItem] = [
        PolicyItem(coverageName: "Smart Contract", amount: "$10,000", premium: "$250.00", endDate: "Jul 15, 2026", status: "Active"),
        PolicyItem(coverageName: "Stablecoin Depeg", amount: "$5,000", premium: "$90.00", endDate: "Sep 30, 2026", status: "Active"),
        PolicyItem(coverageName: "Bridge Exploit", amount: "$8,000", premium: "$320.00", endDate: "Mar 1, 2026", status: "Expired")
    ]
}

// MARK: - Insurance View

struct InsuranceView: View {
    @StateObject private var viewModel = InsuranceViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.coverages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.coverages.isEmpty {
                    errorState(message: error)
                } else {
                    insuranceContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Insurance")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.load() }
        }
    }

    // MARK: - Content

    private var insuranceContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                coveragesSection
                if !viewModel.policies.isEmpty {
                    policiesSection
                }
                calculatorSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Coverages Section

    private var coveragesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Available Coverage")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.coverages) { coverage in
                coverageCard(coverage)
            }
        }
    }

    private func coverageCard(_ coverage: CoverageItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coverage.name)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(coverage.riskType)
                            .font(.mtrxCaption2)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.0, green: 0.675, blue: 0.694).opacity(0.12))
                            .clipShape(Capsule())
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(coverage.premiumRate)
                            .font(.mtrxHeadlineTabular)
                            .foregroundStyle(Color.labelPrimary)
                        Text("annual premium")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                Text(coverage.description)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)

                HStack {
                    Text("Max Coverage")
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                    Spacer()
                    Text(coverage.maxCoverage)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                }

                Button {
                    viewModel.selectedCoverage = coverage
                } label: {
                    Text("Get Quote")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color(red: 0.0, green: 0.675, blue: 0.694))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Policies Section

    private var policiesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Active Policies")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Button {
                    viewModel.showFileClaim = true
                } label: {
                    Text("File Claim")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.statusError)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.policies) { policy in
                policyRow(policy)
            }
        }
    }

    private func policyRow(_ policy: PolicyItem) -> some View {
        MtrxCard(style: policy.status == "Expired" ? .outlined : .standard) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(policy.coverageName)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text("Expires \(policy.endDate)")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }

                    Spacer()

                    Text(policy.status)
                        .font(.mtrxCaptionBold)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 3)
                        .background(policyStatusColor(policy.status).opacity(0.12))
                        .clipShape(Capsule())
                        .foregroundStyle(policyStatusColor(policy.status))
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Coverage")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(policy.amount)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Premium Paid")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(policy.premium)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Calculator Section

    private var calculatorSection: some View {
        MtrxCard(style: .glass, accentEdge: .leading) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Coverage Calculator")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Coverage Amount (USD)")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)

                    HStack {
                        Text("$")
                            .font(.mtrxBody)
                            .foregroundStyle(Color.labelTertiary)
                        TextField("10,000", text: $viewModel.calculatorAmount)
                            .font(.mtrxMono)
                            .keyboardType(.decimalPad)
                    }
                    .padding(Spacing.ms)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }

                if let selected = viewModel.selectedCoverage {
                    HStack {
                        Text("Selected Coverage")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text(selected.name)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                    }
                }

                HStack {
                    Text("Estimated Annual Premium")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text(viewModel.estimatedPremium)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
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

    // MARK: - Helpers

    private func policyStatusColor(_ status: String) -> Color {
        switch status {
        case "Active": return .statusSuccess
        case "Expired": return .labelTertiary
        case "Pending": return .statusWarning
        default: return .labelSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    InsuranceView()
        .preferredColorScheme(.dark)
}
