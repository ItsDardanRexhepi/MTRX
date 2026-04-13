// BuildView.swift
// MTRX
//
// Smart contract management hub — contracts, templates, and subscriptions.

import SwiftUI

// MARK: - Build ViewModel

@MainActor
final class BuildViewModel: ObservableObject {

    // MARK: - Published State

    @Published var contracts: [ContractListItem] = []
    @Published var templates: [ContractTemplate] = []
    @Published var subscriptions: [SubscriptionItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedSegment: BuildSegment = .contracts
    @Published var showCreateContract: Bool = false
    @Published var contentAppeared: Bool = false

    // MARK: - Computed Stats

    var activeCount: Int {
        contracts.filter { $0.status == .active }.count
    }

    var pendingCount: Int {
        contracts.filter { $0.status == .pending }.count
    }

    var totalValue: String {
        let total = contracts.reduce(0.0) { $0 + $1.valueNumeric }
        if total >= 1_000_000 {
            return String(format: "$%.1fM", total / 1_000_000)
        } else if total >= 1_000 {
            return String(format: "$%.1fK", total / 1_000)
        }
        return String(format: "$%.0f", total)
    }

    // MARK: - Load Data

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        contracts = ContractListItem.sampleData
        templates = ContractTemplate.sampleData
        subscriptions = SubscriptionItem.sampleData

        isLoading = false

        withAnimation(Motion.springDefault) {
            contentAppeared = true
        }
    }

    func refresh() async {
        contentAppeared = false
        await loadAll()
    }
}

// MARK: - Build Segment

enum BuildSegment: String, CaseIterable {
    case contracts = "My Contracts"
    case templates = "Templates"
    case subscriptions = "Subscriptions"
}

// MARK: - Contract Status

enum ContractStatus: String {
    case active = "Active"
    case pending = "Pending"
    case completed = "Completed"
    case disputed = "Disputed"

    var color: Color {
        switch self {
        case .active: return .statusSuccess
        case .pending: return .statusWarning
        case .completed: return .accentPrimary
        case .disputed: return .statusError
        }
    }

    var icon: String {
        switch self {
        case .active: return Symbols.contractActive
        case .pending: return Symbols.pending
        case .completed: return Symbols.complete
        case .disputed: return Symbols.dispute
        }
    }
}

// MARK: - Build View

struct BuildView: View {
    @StateObject private var viewModel = BuildViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    segmentControl
                        .padding(.horizontal, Spacing.contentPadding)
                        .padding(.vertical, Spacing.ms)

                    Group {
                        if viewModel.isLoading && viewModel.contracts.isEmpty {
                            MtrxLoadingView(rows: 8)
                        } else {
                            switch viewModel.selectedSegment {
                            case .contracts:
                                contractsView
                            case .templates:
                                templatesView
                            case .subscriptions:
                                subscriptionsView
                            }
                        }
                    }
                }
                .background(MtrxGradientBackground(style: .primary))

                // FAB
                if viewModel.selectedSegment == .contracts && !viewModel.contracts.isEmpty {
                    fabButton
                }
            }
            .navigationTitle("Build")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        MtrxHaptics.impact(.light)
                    } label: {
                        Image(systemName: Symbols.filter)
                            .foregroundStyle(Color.accentPrimary)
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

    // MARK: - Custom Segment Control

    private var segmentControl: some View {
        HStack(spacing: 0) {
            ForEach(BuildSegment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(Motion.springSnappy) {
                        viewModel.selectedSegment = segment
                    }
                    MtrxHaptics.selection()
                } label: {
                    Text(segment.rawValue)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(viewModel.selectedSegment == segment ? .white : Color.labelSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            viewModel.selectedSegment == segment
                                ? Capsule().fill(Color.accentPrimary)
                                : Capsule().fill(Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.surfaceOverlay)
        .clipShape(Capsule())
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            viewModel.showCreateContract = true
            MtrxHaptics.impact(.medium)
        } label: {
            Image(systemName: Symbols.add)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentPrimary)
                .clipShape(Circle())
                .shadow(color: Color.accentPrimary.opacity(0.4), radius: 12, y: 4)
        }
        .padding(.trailing, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .transition(.mtrxScale)
    }

    // MARK: - Contracts View

    private var contractsView: some View {
        Group {
            if viewModel.contracts.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.contractCreate,
                    title: "No Contracts Yet",
                    message: "Create your first smart contract to get started with secure, on-chain agreements.",
                    actionLabel: "Create Your First Contract"
                ) {
                    viewModel.showCreateContract = true
                    MtrxHaptics.impact(.medium)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: Spacing.md) {
                        // Stats row
                        statsRow
                            .mtrxStaggeredAppearance(index: 0, isVisible: viewModel.contentAppeared)

                        // Contract list
                        ForEach(Array(viewModel.contracts.enumerated()), id: \.element.id) { index, contract in
                            NavigationLink {
                                ContractDetailView(contract: contract)
                            } label: {
                                ContractCardRow(contract: contract)
                                    .mtrxStaggeredAppearance(index: index + 1, isVisible: viewModel.contentAppeared)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer().frame(height: Spacing.xxxl + Spacing.xl)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: Spacing.sm) {
            MtrxStatCard(
                title: "Active",
                value: "\(viewModel.activeCount)",
                icon: Symbols.contractActive
            )

            MtrxStatCard(
                title: "Pending",
                value: "\(viewModel.pendingCount)",
                icon: Symbols.pending
            )

            MtrxStatCard(
                title: "Total Value",
                value: viewModel.totalValue,
                icon: Symbols.wallet
            )
        }
    }

    // MARK: - Templates View

    private var templatesView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                ForEach(Array(viewModel.templates.enumerated()), id: \.element.id) { index, template in
                    TemplateCardView(template: template)
                        .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Subscriptions View

    private var subscriptionsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: Spacing.md) {
                // Active subscriptions
                ForEach(Array(viewModel.subscriptions.enumerated()), id: \.element.id) { index, subscription in
                    SubscriptionCardView(subscription: subscription)
                        .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                }

                // Upgrade prompt
                upgradePrompt
                    .mtrxStaggeredAppearance(index: viewModel.subscriptions.count, isVisible: viewModel.contentAppeared)

                Spacer().frame(height: Spacing.xxl)
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Upgrade Prompt

    private var upgradePrompt: some View {
        MtrxCard(style: .glass) {
            VStack(spacing: Spacing.md) {
                Image(systemName: Symbols.sparkle)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.accentPrimary)
                    .mtrxGlow()

                VStack(spacing: Spacing.xs) {
                    Text("Unlock Pro Features")
                        .font(.mtrxTitle3)
                        .foregroundStyle(Color.labelPrimary)

                    Text("Get unlimited contracts, priority execution, and advanced analytics with MTRX Pro.")
                        .font(.mtrxSubheadline)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    MtrxHaptics.impact(.medium)
                } label: {
                    Text("Upgrade to Pro")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
            }
            .frame(maxWidth: .infinity)
        }
        .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
    }
}

// MARK: - Contract Card Row

struct ContractCardRow: View {
    let contract: ContractListItem

    var body: some View {
        MtrxCard(style: .standard, accentEdge: .leading) {
            VStack(spacing: Spacing.ms) {
                // Top row: status badge + type
                HStack {
                    MtrxBadge(text: contract.status.rawValue, style: badgeStyle)

                    Spacer()

                    Text(contract.contractType)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                }

                // Middle: name + counterparty
                HStack(spacing: Spacing.ms) {
                    MtrxAvatar(
                        symbol: contract.typeIcon,
                        color: contract.status.color,
                        size: Spacing.Size.avatarMedium
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(contract.title)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(1)

                        Text(contract.counterparty)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                MtrxDivider()

                // Bottom: value + date + action
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Value")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(contract.value)
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Created")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(contract.createdDate)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer().frame(width: Spacing.md)

                    Button {
                        MtrxHaptics.impact(.light)
                    } label: {
                        Text(contract.actionLabel)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
                }
            }
        }
    }

    private var badgeStyle: MtrxBadge.BadgeStyle {
        switch contract.status {
        case .active: return .success
        case .pending: return .warning
        case .completed: return .accent
        case .disputed: return .error
        }
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
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(contract.title)
                            .font(.mtrxTitle2)
                        Text(contract.counterparty)
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    MtrxBadge(
                        text: contract.status.rawValue,
                        style: contract.status == .active ? .success :
                               contract.status == .pending ? .warning :
                               contract.status == .disputed ? .error : .accent
                    )
                }

                // Value card
                MtrxCard(style: .glass) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Contract Value")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Text(contract.value)
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.accentPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Milestones
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Milestones")
                        .font(.mtrxTitle3)

                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: Spacing.ms) {
                            Image(systemName: i == 0 ? Symbols.complete : Symbols.pending)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(i == 0 ? Color.statusSuccess : Color.labelTertiary)
                                .frame(width: 24)

                            Text("Milestone \(i + 1)")
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelPrimary)

                            Spacer()

                            Text("$\((i + 1) * 1000)")
                                .font(.mtrxMono)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        .padding(.vertical, Spacing.sm)

                        if i < 2 {
                            MtrxDivider()
                        }
                    }
                }

                // Actions
                VStack(spacing: Spacing.sm) {
                    if contract.status == .pending {
                        Button {
                            isSigningContract = true
                            MtrxHaptics.impact(.medium)
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                isSigningContract = false
                                MtrxHaptics.success()
                            }
                        } label: {
                            Label("Sign Contract", systemImage: Symbols.contractSign)
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: isSigningContract, fullWidth: true))
                        .disabled(isSigningContract)
                    }

                    if contract.status == .active {
                        Button {
                            isExecuting = true
                            MtrxHaptics.impact(.medium)
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                isExecuting = false
                                MtrxHaptics.success()
                            }
                        } label: {
                            Label("Execute Milestone", systemImage: Symbols.milestone)
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: isExecuting, fullWidth: true))
                        .disabled(isExecuting)
                    }

                    Button { } label: {
                        Label("View on Chain", systemImage: Symbols.externalLink)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular, fullWidth: true))

                    Button {
                        showDisputeConfirm = true
                    } label: {
                        Label("Raise Dispute", systemImage: Symbols.dispute)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .destructive, size: .regular, fullWidth: true))
                }
            }
            .padding(Spacing.contentPadding)
        }
        .background(MtrxGradientBackground(style: .primary))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Raise Dispute?", isPresented: $showDisputeConfirm) {
            Button("Raise Dispute", role: .destructive) {
                MtrxHaptics.warning()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will initiate a formal dispute process on-chain.")
        }
    }
}

// MARK: - Template Card View

struct TemplateCardView: View {
    let template: ContractTemplate
    @State private var isPressed: Bool = false

    var body: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.ms) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                        .fill(template.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: template.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(template.accentColor)
                }

                // Name
                Text(template.name)
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)

                // Description
                Text(template.description_)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Use Template button
                Button {
                    MtrxHaptics.impact(.medium)
                } label: {
                    Text("Use Template")
                }
                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact, fullWidth: true))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(Motion.springSnappy, value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: { })
    }
}

// MARK: - Subscription Card View

struct SubscriptionCardView: View {
    let subscription: SubscriptionItem

    var body: some View {
        MtrxCard(style: .standard, accentEdge: .leading) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    MtrxAvatar(
                        symbol: subscription.icon,
                        color: subscription.tierColor,
                        size: Spacing.Size.avatarMedium
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscription.name)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)

                        MtrxBadge(text: subscription.tier, style: .accent)
                    }

                    Spacer()

                    Text(subscription.amount)
                        .font(.mtrxMono)
                        .foregroundStyle(Color.labelPrimary)
                }

                MtrxDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Renewal")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(subscription.nextDate)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    // Usage stats
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Usage")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        HStack(spacing: Spacing.xs) {
                            MtrxProgressRing(
                                progress: subscription.usagePercent,
                                size: 24,
                                lineWidth: 3,
                                color: subscription.tierColor,
                                showLabel: false
                            )
                            Text("\(Int(subscription.usagePercent * 100))%")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }

                    Spacer().frame(width: Spacing.sm)

                    Button {
                        MtrxHaptics.impact(.light)
                    } label: {
                        Text("Manage")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))
                }
            }
        }
    }
}

// MARK: - Data Models

struct ContractListItem: Identifiable {
    let id = UUID()
    let title: String
    let contractType: String
    let counterparty: String
    let value: String
    let valueNumeric: Double
    let status: ContractStatus
    let typeIcon: String
    let createdDate: String
    let actionLabel: String

    static let sampleData: [ContractListItem] = [
        ContractListItem(
            title: "Freelance Development",
            contractType: "Escrow",
            counterparty: "0x1a2b...3c4d",
            value: "$5,000",
            valueNumeric: 5_000,
            status: .active,
            typeIcon: Symbols.contract,
            createdDate: "Mar 15, 2026",
            actionLabel: "View"
        ),
        ContractListItem(
            title: "Property Lease Agreement",
            contractType: "Lease",
            counterparty: "0x9f8e...7d6c",
            value: "$2,400/mo",
            valueNumeric: 28_800,
            status: .active,
            typeIcon: Symbols.property,
            createdDate: "Feb 28, 2026",
            actionLabel: "View"
        ),
        ContractListItem(
            title: "Insurance Policy",
            contractType: "Insurance",
            counterparty: "InsureDAO",
            value: "$500",
            valueNumeric: 500,
            status: .pending,
            typeIcon: Symbols.insurance,
            createdDate: "Apr 2, 2026",
            actionLabel: "Sign"
        ),
        ContractListItem(
            title: "Revenue Share",
            contractType: "Revenue Split",
            counterparty: "0xab12...ef34",
            value: "$12,500",
            valueNumeric: 12_500,
            status: .completed,
            typeIcon: Symbols.chartPie,
            createdDate: "Jan 10, 2026",
            actionLabel: "Details"
        ),
        ContractListItem(
            title: "Vendor Payment",
            contractType: "Escrow",
            counterparty: "0x5678...9abc",
            value: "$3,200",
            valueNumeric: 3_200,
            status: .disputed,
            typeIcon: Symbols.dispute,
            createdDate: "Mar 28, 2026",
            actionLabel: "Resolve"
        ),
    ]
}

struct ContractTemplate: Identifiable {
    let id = UUID()
    let name: String
    let description_: String
    let icon: String
    let accentColor: Color

    static let sampleData: [ContractTemplate] = [
        ContractTemplate(name: "Escrow", description_: "Milestone-based escrow with conditional release", icon: Symbols.escrow, accentColor: .accentPrimary),
        ContractTemplate(name: "Freelance", description_: "Time or deliverable based freelance agreement", icon: Symbols.contract, accentColor: .statusInfo),
        ContractTemplate(name: "Subscription", description_: "Recurring payment streams with auto-renewal", icon: Symbols.processing, accentColor: .purple),
        ContractTemplate(name: "Revenue Share", description_: "Automatic revenue splitting between parties", icon: Symbols.chartPie, accentColor: .statusSuccess),
        ContractTemplate(name: "Joint Ownership", description_: "Shared asset ownership with governance rules", icon: Symbols.property, accentColor: .orange),
        ContractTemplate(name: "Loan Agreement", description_: "Collateralized lending with flexible terms", icon: Symbols.fee, accentColor: .accentTertiary),
        ContractTemplate(name: "Fundraiser", description_: "Campaign-based fundraising with milestones", icon: Symbols.fundraiser, accentColor: .pink),
        ContractTemplate(name: "DAO", description_: "Decentralized governance with treasury management", icon: Symbols.dao, accentColor: .accentSecondary),
    ]
}

struct SubscriptionItem: Identifiable {
    let id = UUID()
    let name: String
    let tier: String
    let amount: String
    let nextDate: String
    let icon: String
    let tierColor: Color
    let usagePercent: Double

    static let sampleData: [SubscriptionItem] = [
        SubscriptionItem(name: "DeFi Yield Optimizer", tier: "Pro", amount: "$29/mo", nextDate: "May 1, 2026", icon: Symbols.chartLine, tierColor: .accentPrimary, usagePercent: 0.73),
        SubscriptionItem(name: "Data Oracle Feed", tier: "Standard", amount: "$12/mo", nextDate: "Apr 28, 2026", icon: Symbols.link, tierColor: .statusInfo, usagePercent: 0.45),
        SubscriptionItem(name: "Contract Analytics", tier: "Free", amount: "$0/mo", nextDate: "N/A", icon: Symbols.chartBar, tierColor: .labelTertiary, usagePercent: 0.92),
    ]
}

// MARK: - Preview

#Preview {
    BuildView()
}
