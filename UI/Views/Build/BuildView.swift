// BuildView.swift
// MTRX
//
// Smart contracts listings and subscription management hub.

import SwiftUI

// MARK: - Build ViewModel

@MainActor
final class BuildViewModel: ObservableObject {
    // MARK: - Published State

    @Published var activeContracts: [ContractListItem] = []
    @Published var subscriptions: [SubscriptionItem] = []
    @Published var templates: [ContractTemplate] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedSection: BuildSection = .contracts
    @Published var showCreateContract: Bool = false

    // Stats
    @Published var activeCount: Int = 0
    @Published var pendingCount: Int = 0
    @Published var completedCount: Int = 0

    private let api = MTRXAPIClient.shared

    // MARK: - Load All

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        async let contractsTask: () = loadContracts()
        async let subscriptionsTask: () = loadSubscriptions()
        async let templatesTask: () = loadTemplates()

        _ = await (contractsTask, subscriptionsTask, templatesTask)
        isLoading = false
    }

    // MARK: - Load Contracts

    func loadContracts() async {
        do {
            let raw: [String: AnyCodableValue] = try await api.listContracts()
            let items = parseContracts(raw)
            activeContracts = items

            activeCount = items.filter { $0.status == "Active" }.count
            pendingCount = items.filter { $0.status == "Pending" }.count
            completedCount = items.filter { $0.status == "Completed" }.count

            if activeContracts.isEmpty {
                activeContracts = ContractListItem.sampleData
                activeCount = 3
                pendingCount = 2
                completedCount = 15
            }
        } catch {
            if activeContracts.isEmpty {
                activeContracts = ContractListItem.sampleData
                activeCount = 3
                pendingCount = 2
                completedCount = 15
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Load Subscriptions

    func loadSubscriptions() async {
        do {
            let raw: [String: AnyCodableValue] = try await api.listSubscriptions()
            let items = parseSubscriptions(raw)
            subscriptions = items
            if subscriptions.isEmpty {
                subscriptions = SubscriptionItem.sampleData
            }
        } catch {
            if subscriptions.isEmpty {
                subscriptions = SubscriptionItem.sampleData
            }
        }
    }

    // MARK: - Load Templates

    func loadTemplates() async {
        // Templates are currently sourced locally
        templates = ContractTemplate.sampleData
    }

    // MARK: - Parsers

    private func parseContracts(_ raw: [String: AnyCodableValue]) -> [ContractListItem] {
        guard case .array(let items) = raw["data"] ?? raw["contracts"] ?? .null else {
            return []
        }
        return items.compactMap { item -> ContractListItem? in
            guard case .dictionary(let dict) = item else { return nil }
            let title = dict["title"]?.stringValue ?? dict["name"]?.stringValue ?? "Contract"
            let counterparty = dict["counterparty"]?.stringValue ?? dict["parties"]?.stringValue ?? "Unknown"
            let valueNum = dict["value"]?.doubleValue ?? dict["total_value"]?.doubleValue ?? 0
            let value = valueNum > 0 ? "$\(String(format: "%,.0f", valueNum))" : "$0"
            let status = dict["status"]?.stringValue ?? "Pending"
            let contractType = dict["type"]?.stringValue ?? dict["contract_type"]?.stringValue ?? "escrow"

            let statusColor: Color = {
                switch status.lowercased() {
                case "active": return .statusSuccess
                case "pending": return .statusWarning
                case "completed", "executed": return .accentPrimary
                case "disputed": return .statusError
                default: return .labelTertiary
                }
            }()

            let typeIcon: String = {
                switch contractType.lowercased() {
                case "escrow": return Symbols.escrow
                case "freelance": return Symbols.contract
                case "subscription": return Symbols.processing
                case "lease", "property": return Symbols.property
                case "insurance": return Symbols.insurance
                default: return Symbols.contract
                }
            }()

            return ContractListItem(
                title: title,
                counterparty: counterparty,
                value: value,
                status: status.capitalized,
                statusColor: statusColor,
                typeIcon: typeIcon
            )
        }
    }

    private func parseSubscriptions(_ raw: [String: AnyCodableValue]) -> [SubscriptionItem] {
        guard case .array(let items) = raw["data"] ?? raw["subscriptions"] ?? .null else {
            return []
        }
        return items.compactMap { item -> SubscriptionItem? in
            guard case .dictionary(let dict) = item else { return nil }
            let name = dict["name"]?.stringValue ?? dict["plan_name"]?.stringValue ?? "Subscription"
            let frequency = dict["frequency"]?.stringValue ?? dict["interval"]?.stringValue ?? "Monthly"
            let amountVal = dict["amount"]?.doubleValue ?? 0
            let amount = amountVal > 0 ? "$\(String(format: "%.0f", amountVal))/mo" : "$0/mo"
            let nextDate = dict["next_billing_date"]?.stringValue ?? dict["next_date"]?.stringValue ?? "N/A"
            return SubscriptionItem(name: name, frequency: frequency.capitalized, amount: amount, nextDate: nextDate)
        }
    }
}

// MARK: - Build View

struct BuildView: View {
    @StateObject private var viewModel = BuildViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionPicker

                Group {
                    if viewModel.isLoading && viewModel.activeContracts.isEmpty {
                        loadingState
                    } else if let error = viewModel.errorMessage, viewModel.activeContracts.isEmpty {
                        errorState(error)
                    } else {
                        switch viewModel.selectedSection {
                        case .contracts:
                            contractsSection
                        case .subscriptions:
                            subscriptionsSection
                        case .templates:
                            templatesSection
                        }
                    }
                }
            }
            .navigationTitle("Build")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showCreateContract = true
                    } label: {
                        Image(systemName: Symbols.addCircle)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showCreateContract) {
                NavigationStack {
                    ContractView()
                }
            }
        }
        .task {
            await viewModel.loadAll()
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .controlSize(.large)
            Text("Loading contracts...")
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: Symbols.alertWarning)
                .font(.system(size: 48))
                .foregroundStyle(Color.statusWarning)

            Text("Failed to load")
                .font(.mtrxTitle3)

            Text(message)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            Button {
                Task { await viewModel.loadAll() }
            } label: {
                Label("Retry", systemImage: Symbols.refresh)
                    .font(.mtrxHeadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: Spacing.Size.buttonHeight)
                    .background(Color.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        Picker("Section", selection: $viewModel.selectedSection) {
            ForEach(BuildSection.allCases, id: \.self) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Contracts Section

    private var contractsSection: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                // Summary stats
                HStack(spacing: Spacing.md) {
                    BuildStatCard(title: "Active", value: "\(viewModel.activeCount)", color: .statusSuccess)
                    BuildStatCard(title: "Pending", value: "\(viewModel.pendingCount)", color: .statusWarning)
                    BuildStatCard(title: "Completed", value: "\(viewModel.completedCount)", color: .accentPrimary)
                }
                .padding(.bottom, Spacing.sm)

                ForEach(viewModel.activeContracts) { contract in
                    NavigationLink {
                        ContractDetailView(contract: contract)
                    } label: {
                        ContractListRow(contract: contract)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.loadContracts()
        }
    }

    // MARK: - Subscriptions Section

    private var subscriptionsSection: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(viewModel.subscriptions) { subscription in
                    SubscriptionRow(subscription: subscription)
                }
            }
            .padding(Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.loadSubscriptions()
        }
    }

    // MARK: - Templates Section

    private var templatesSection: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                ForEach(viewModel.templates) { template in
                    NavigationLink {
                        ContractView()
                    } label: {
                        TemplateCard(template: template)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.contentPadding)
        }
    }
}

// MARK: - Build Section

enum BuildSection: String, CaseIterable {
    case contracts = "Contracts"
    case subscriptions = "Subscriptions"
    case templates = "Templates"
}

// MARK: - Contract List Row

struct ContractListRow: View {
    let contract: ContractListItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: contract.typeIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: Spacing.Size.avatarMedium, height: Spacing.Size.avatarMedium)
                .background(Color.accentPrimary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(contract.title)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)

                Text(contract.counterparty)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(contract.value)
                    .font(.mtrxBodyTabular)
                    .foregroundStyle(Color.labelPrimary)

                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(contract.statusColor)
                        .frame(width: 8, height: 8)
                    Text(contract.status)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        }
        .padding(Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

// MARK: - Contract Detail View

struct ContractDetailView: View {
    let contract: ContractListItem
    @State private var isSigningContract: Bool = false
    @State private var isExecuting: Bool = false
    @State private var showDisputeConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                // Status header
                HStack {
                    VStack(alignment: .leading) {
                        Text(contract.title)
                            .font(.mtrxTitle2)
                        Text(contract.counterparty)
                            .font(.mtrxSubheadline)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Text(contract.status)
                        .font(.mtrxCaptionBold)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(contract.statusColor.opacity(0.15))
                        .foregroundStyle(contract.statusColor)
                        .clipShape(Capsule())
                }

                // Value
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Contract Value")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Text(contract.value)
                        .font(.mtrxMonoMedium)
                }

                Divider()

                // Milestones placeholder
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Milestones")
                        .font(.mtrxTitle3)

                    ForEach(0..<3, id: \.self) { i in
                        HStack {
                            Image(systemName: i == 0 ? Symbols.complete : Symbols.pending)
                                .foregroundStyle(i == 0 ? Color.statusSuccess : Color.labelTertiary)
                            Text("Milestone \(i + 1)")
                                .font(.mtrxBody)
                            Spacer()
                            Text("$\((i + 1) * 1000)")
                                .font(.mtrxBodyTabular)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                }

                // Actions
                VStack(spacing: Spacing.sm) {
                    if contract.status == "Pending" {
                        Button {
                            isSigningContract = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                isSigningContract = false
                            }
                        } label: {
                            HStack {
                                if isSigningContract {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Label("Sign Contract", systemImage: Symbols.contractSign)
                                }
                            }
                            .font(.mtrxHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: Spacing.Size.buttonHeight)
                            .background(Color.statusSuccess)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                        }
                        .disabled(isSigningContract)
                    }

                    if contract.status == "Active" {
                        Button {
                            isExecuting = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                isExecuting = false
                            }
                        } label: {
                            HStack {
                                if isExecuting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Label("Execute Milestone", systemImage: Symbols.milestone)
                                }
                            }
                            .font(.mtrxHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: Spacing.Size.buttonHeight)
                            .background(Color.accentPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                        }
                        .disabled(isExecuting)
                    }

                    Button { } label: {
                        Label("View on Chain", systemImage: Symbols.externalLink)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.accentPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Spacing.Size.buttonHeight)
                            .background(Color.accentPrimary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    Button {
                        showDisputeConfirm = true
                    } label: {
                        Label("Raise Dispute", systemImage: Symbols.dispute)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.statusError)
                            .frame(maxWidth: .infinity)
                            .frame(height: Spacing.Size.buttonHeight)
                            .background(Color.statusError.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
            }
            .padding(Spacing.contentPadding)
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Raise Dispute?", isPresented: $showDisputeConfirm) {
            Button("Raise Dispute", role: .destructive) {
                Task {
                    let request = DisputeCreateRequest(
                        contractId: contract.id.uuidString,
                        description: "Dispute for \(contract.title)",
                        evidence: [:]
                    )
                    _ = try? await MTRXAPIClient.shared.createDispute(request)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will initiate a formal dispute process on-chain.")
        }
    }
}

// MARK: - Subscription Row

struct SubscriptionRow: View {
    let subscription: SubscriptionItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: Symbols.processing)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: Spacing.Size.avatarSmall, height: Spacing.Size.avatarSmall)
                .background(Color.accentPrimary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.mtrxBodyBold)
                Text(subscription.frequency)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(subscription.amount)
                    .font(.mtrxBodyTabular)
                Text("Next: \(subscription.nextDate)")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: ContractTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: template.icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.accentPrimary)

            Text(template.name)
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)

            Text(template.description_)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Build Stat Card

struct BuildStatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.mtrxTitle2)
                .foregroundStyle(color)
            Text(title)
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

// MARK: - Models

struct ContractListItem: Identifiable {
    let id = UUID()
    let title: String
    let counterparty: String
    let value: String
    let status: String
    let statusColor: Color
    let typeIcon: String

    static let sampleData: [ContractListItem] = [
        ContractListItem(title: "Freelance Development", counterparty: "0x1a2b...3c4d", value: "$5,000", status: "Active", statusColor: .statusSuccess, typeIcon: Symbols.contract),
        ContractListItem(title: "Property Lease", counterparty: "PropertyDAO", value: "$2,400/mo", status: "Active", statusColor: .statusSuccess, typeIcon: Symbols.property),
        ContractListItem(title: "Insurance Policy", counterparty: "InsureDAO", value: "$500", status: "Pending", statusColor: .statusWarning, typeIcon: Symbols.insurance),
    ]
}

struct SubscriptionItem: Identifiable {
    let id = UUID()
    let name: String
    let frequency: String
    let amount: String
    let nextDate: String

    static let sampleData: [SubscriptionItem] = [
        SubscriptionItem(name: "DeFi Yield Optimizer", frequency: "Monthly", amount: "$29/mo", nextDate: "Apr 1"),
        SubscriptionItem(name: "Data Oracle Feed", frequency: "Weekly", amount: "$5/wk", nextDate: "Mar 31"),
    ]
}

struct ContractTemplate: Identifiable {
    let id = UUID()
    let name: String
    let description_: String
    let icon: String

    static let sampleData: [ContractTemplate] = [
        ContractTemplate(name: "Escrow", description_: "Milestone-based escrow contract", icon: Symbols.escrow),
        ContractTemplate(name: "Subscription", description_: "Recurring payment stream", icon: Symbols.processing),
        ContractTemplate(name: "DAO Treasury", description_: "Multi-sig treasury management", icon: Symbols.treasury),
        ContractTemplate(name: "Insurance", description_: "Parametric insurance policy", icon: Symbols.insurance),
    ]
}

// MARK: - Preview

#Preview {
    BuildView()
}
