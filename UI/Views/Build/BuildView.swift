// BuildView.swift
// MTRX
//
// Smart contract management hub — contracts, templates, and subscriptions.

import Combine
import SwiftUI
import SafariServices

// MARK: - Build ViewModel

@MainActor
final class BuildViewModel: ObservableObject {

    // MARK: - Published State

    @Published var contracts: [ContractListItem] = []
    private var cancellables = Set<AnyCancellable>()
    @Published var templates: [BuildContractTemplate] = []
    @Published var subscriptions: [SubscriptionItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedSegment: BuildSegment = .contracts
    @Published var showCreateContract: Bool = false
    @Published var contentAppeared: Bool = false
    @Published var showContractFilter: Bool = false
    @Published var statusFilters: Set<BuildContractStatus> = [.active, .pending, .completed, .disputed]
    @Published var showDeployContract: Bool = false
    @Published var showLaunchToken: Bool = false
    @Published var showCreateDAO: Bool = false
    @Published var showUpgrade: Bool = false
    @Published var showPublishContent: Bool = false
    @Published var showCreatorHub: Bool = false
    @Published var showIndexer: Bool = false
    @Published var selectedTemplate: BuildContractTemplate? = nil

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

        contracts = DeployedContractsStore.shared.items + ContractListItem.sampleData
        templates = BuildContractTemplate.sampleData
        subscriptions = SubscriptionItem.sampleData

        // New deployments from the wizard surface at the top, live.
        // Subscribe exactly once — refresh() must not stack duplicates.
        if cancellables.isEmpty {
            DeployedContractsStore.shared.$items
                .receive(on: DispatchQueue.main)
                .sink { [weak self] deployed in
                    self?.contracts = deployed + ContractListItem.sampleData
                }
                .store(in: &cancellables)
        }

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
    // Order along the strip: Templates, Create, My Contracts.
    case templates = "Templates"
    case create = "Create"
    case contracts = "My Contracts"

    var tabIcon: String {
        switch self {
        case .contracts: return "doc.text"
        case .templates: return "square.grid.2x2"
        case .create: return "plus.circle"
        }
    }
}

// MARK: - Contract Status

enum BuildContractStatus: String {
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
    @ObservedObject private var meshOutbox = MeshOutbox.shared
    @State private var statFilter: BuildContractStatus?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                // The ocean fills the whole screen from the first frame —
                // never sized by the content above it, so loading states
                // can't expose black edges.
                MtrxGradientBackground(style: .primary)

                VStack(spacing: 0) {
                    segmentControl
                        .padding(.horizontal, Spacing.contentPadding)
                        .padding(.vertical, Spacing.ms)

                    // Off-grid: actions initialized while disconnected ride
                    // the local mesh outbox — surfaced here, non-blocking.
                    if !meshOutbox.entries.isEmpty {
                        VStack(spacing: Spacing.sm) {
                            ForEach(meshOutbox.entries) { entry in
                                MeshOutboxCard(entry: entry)
                            }
                        }
                        .padding(.horizontal, Spacing.contentPadding)
                        .padding(.bottom, Spacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Group {
                        if viewModel.isLoading && viewModel.contracts.isEmpty {
                            MtrxLoadingView(rows: 8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        } else {
                            switch viewModel.selectedSegment {
                            case .contracts:
                                contractsView
                            case .templates:
                                templatesView
                            case .create:
                                createView
                            }
                        }
                    }
                }
                // Swipe between Templates / Create / My Contracts, the same way
                // the Social tab moves between its top tabs.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            let w = value.translation.width
                            let h = value.translation.height
                            // Only act on a clearly horizontal swipe so vertical
                            // scrolling is never hijacked.
                            guard abs(w) > 70, abs(w) > abs(h) * 1.6 else { return }

                            let segments = BuildSegment.allCases
                            guard let idx = segments.firstIndex(of: viewModel.selectedSegment) else { return }
                            if w < 0, idx < segments.count - 1 {
                                // Next segment.
                                withAnimation(Motion.springSnappy) { viewModel.selectedSegment = segments[idx + 1] }
                                MtrxHaptics.selection()
                            } else if w > 0, idx > 0 {
                                // Previous segment.
                                withAnimation(Motion.springSnappy) { viewModel.selectedSegment = segments[idx - 1] }
                                MtrxHaptics.selection()
                            }
                        }
                )

                // FAB
                if viewModel.selectedSegment == .contracts && !viewModel.contracts.isEmpty {
                    fabButton
                }
            }
            .navigationTitle("Build")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(NotificationCenter.default.publisher(for: .mtrxPopToRoot)) { note in
                // Re-tapping the Build dock tab returns to Templates.
                if note.userInfo?["index"] as? Int == 1 {
                    withAnimation(Motion.springSnappy) { viewModel.selectedSegment = .templates }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MtrxGlassCircleButton(icon: Symbols.filter) {
                        viewModel.showContractFilter = true
                    }
                }
            }
            .sheet(isPresented: $viewModel.showCreateContract) {
                NavigationStack {
                    ContractView()
                }
            }
            .sheet(isPresented: $viewModel.showContractFilter) {
                ContractFilterSheet(selected: $viewModel.statusFilters)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $viewModel.showDeployContract) {
                NavigationStack {
                    DeployContractView()
                }
            }
            .sheet(isPresented: $viewModel.showLaunchToken) {
                NavigationStack {
                    ContractView()
                }
            }
            .sheet(isPresented: $viewModel.showCreateDAO) {
                NavigationStack {
                    DAOView()
                }
            }
            .sheet(isPresented: $viewModel.showUpgrade) {
                UpgradeView(
                    blockedFeature: .contractDeployments,
                    currentUsage: 3,
                    limit: 3
                )
            }
            .sheet(isPresented: $viewModel.showPublishContent) {
                NavigationStack {
                    ContentPublishingView()
                }
            }
            .sheet(isPresented: $viewModel.showCreatorHub) {
                NavigationStack {
                    CreatorView()
                }
            }
            .sheet(isPresented: $viewModel.showIndexer) {
                NavigationStack {
                    IndexerView()
                }
            }
            .sheet(item: $viewModel.selectedTemplate) { template in
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

    @Namespace private var buildSegmentNS

    /// A clean underline tab strip with an icon per section — clearer and
    /// less chunky than the old pill-in-a-capsule.
    private var segmentControl: some View {
        // Three equal-width tabs, evenly distributed across the strip.
        HStack(spacing: 0) {
            ForEach(BuildSegment.allCases, id: \.self) { segment in
                let isActive = viewModel.selectedSegment == segment
                Button {
                    withAnimation(Motion.springSnappy) { viewModel.selectedSegment = segment }
                    MtrxHaptics.selection()
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: segment.tabIcon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(segment.rawValue)
                                .font(.system(size: 14, weight: isActive ? .bold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(isActive ? Color.labelPrimary : Color.labelTertiary)

                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 2.5)
                            if isActive {
                                Capsule().fill(Color.accentPrimary).frame(height: 2.5)
                                    .matchedGeometryEffect(id: "buildSegment", in: buildSegmentNS)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.separatorStandard.opacity(0.4)).frame(height: 0.5)
        }
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

                        // Contract list (honors the tapped stat filter)
                        ForEach(Array(displayedContracts.enumerated()), id: \.element.id) { index, contract in
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
            statButton(.active) {
                MtrxStatCard(title: "Active", value: "\(viewModel.activeCount)", icon: Symbols.contractActive)
            }
            statButton(.pending) {
                MtrxStatCard(title: "Pending", value: "\(viewModel.pendingCount)", icon: Symbols.pending)
            }
            // Total Value clears any filter — tap to see everything.
            statButton(nil) {
                MtrxStatCard(title: "Total Value", value: viewModel.totalValue, icon: Symbols.wallet)
            }
        }
    }

    /// Tappable stat — toggles the contract list filter. Tap an active
    /// filter again to clear it; tap Total Value to show all.
    private func statButton<Content: View>(_ status: BuildContractStatus?, @ViewBuilder _ content: () -> Content) -> some View {
        Button {
            MtrxHaptics.selection()
            withAnimation(Motion.springSnappy) {
                statFilter = (statFilter == status) ? nil : status
            }
        } label: {
            content()
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                        .stroke(statFilter == status && status != nil ? Color.accentPrimary : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    /// The contracts shown, honoring the tapped stat filter.
    private var displayedContracts: [ContractListItem] {
        guard let f = statFilter else { return viewModel.contracts }
        return viewModel.contracts.filter { $0.status == f }
    }

    // MARK: - Templates View

    private var templatesView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                ForEach(Array(viewModel.templates.enumerated()), id: \.element.id) { index, template in
                    TemplateCardView(template: template) {
                        viewModel.selectedTemplate = template
                        MtrxHaptics.impact(.medium)
                    }
                    .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Subscriptions View

    private var createView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.sm),
                    GridItem(.flexible(), spacing: Spacing.sm)
                ],
                spacing: Spacing.sm
            ) {
                buildActionCard(
                    icon: "doc.text.fill",
                    title: "Deploy Contract",
                    description: "Deploy from pre-audited templates — ERC-20, NFT, Escrow, Multi-sig, and more.",
                    index: 0
                ) {
                    viewModel.showDeployContract = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "bitcoinsign.circle.fill",
                    title: "Launch Token",
                    description: "Fair launch with vesting schedules and airdrop distribution tools.",
                    index: 1
                ) {
                    viewModel.showLaunchToken = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "person.3.fill",
                    title: "Create DAO",
                    description: "Set up a decentralized organization with governance, treasury, and voting.",
                    index: 2
                ) {
                    viewModel.showCreateDAO = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "paperplane.fill",
                    title: "Airdrop Distributor",
                    description: "Batch distribute tokens to thousands of addresses in one transaction.",
                    index: 3
                ) {
                    viewModel.showLaunchToken = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "shippingbox.fill",
                    title: "Supply Chain Registry",
                    description: "Register and track items with immutable on-chain provenance records.",
                    index: 4
                ) {
                    viewModel.showCreateContract = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "star.circle.fill",
                    title: "Creator Token",
                    description: "Launch a social token with a bonding curve for your community.",
                    index: 5
                ) {
                    viewModel.showLaunchToken = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "lock.shield.fill",
                    title: "Multi-Sig Wallet",
                    description: "Create a shared wallet requiring multiple approvals for transactions.",
                    index: 6
                ) {
                    viewModel.showDeployContract = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "repeat.circle.fill",
                    title: "Subscription Plan",
                    description: "Create on-chain subscription offerings with tiered pricing.",
                    index: 7
                ) {
                    viewModel.showCreateContract = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "doc.richtext.fill",
                    title: "Publish Content",
                    description: "Publish articles, posts, and media on-chain with permanent provenance.",
                    index: 8
                ) {
                    viewModel.showPublishContent = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "sparkles",
                    title: "Creator Hub",
                    description: "Manage your creator presence — channels, monetization, and audience.",
                    index: 9
                ) {
                    viewModel.showCreatorHub = true
                    MtrxHaptics.impact(.medium)
                }

                buildActionCard(
                    icon: "server.rack",
                    title: "Chain Indexer",
                    description: "Query indexed on-chain data — blocks, transactions, and contract events.",
                    index: 10
                ) {
                    viewModel.showIndexer = true
                    MtrxHaptics.impact(.medium)
                }

                // Upgrade prompt
                upgradePrompt
                    .mtrxStaggeredAppearance(index: 10, isVisible: viewModel.contentAppeared)

                Spacer().frame(height: Spacing.xxl)
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
        }
    }

    private func buildActionCard(
        icon: String,
        title: String,
        description: String,
        index: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MtrxCard(style: .standard) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accentPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.accentPrimary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.labelPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(description)
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            }
            .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
        }
        .buttonStyle(.plain)
    }

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
                    viewModel.showUpgrade = true
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
    @State private var showActionConfirm = false
    @State private var sharedToSocial = false

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

                    Spacer().frame(width: Spacing.sm)

                    // Share this build to the social feed for others to find.
                    Button {
                        SocialViewModel.shared.postBuild(
                            title: contract.title,
                            kind: contract.contractType,
                            address: contract.counterparty,
                            displayName: ""
                        )
                        sharedToSocial = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    Button {
                        MtrxHaptics.success()
                        showActionConfirm = true
                    } label: {
                        Text(contract.actionLabel)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
                }
            }
        }
        .alert("\(contract.actionLabel) — \(contract.title)", isPresented: $showActionConfirm) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Executed on the MTRX network. Gas covered by the platform — the updated contract state is reflected on-chain.")
        }
        .alert("Shared to Social", isPresented: $sharedToSocial) {
            Button("View", role: .none) {
                NotificationCenter.default.post(name: .mtrxSwitchTab, object: nil, userInfo: ["index": 3])
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("“\(contract.title)” was posted to your feed for others to discover.")
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
    @State private var disputeFiled = false
    let contract: ContractListItem
    @State private var isSigningContract: Bool = false
    @State private var isExecuting: Bool = false
    @State private var showDisputeConfirm: Bool = false
    @State private var explorerURL: URL? = nil

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

                    Button {
                        let address = explorerAddress
                        if let url = URL(string: "https://basescan.org/address/\(address)") {
                            explorerURL = url
                            MtrxHaptics.impact(.light)
                        }
                    } label: {
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
                disputeFiled = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will initiate a formal dispute process on-chain.")
        }
        .alert("Dispute Filed", isPresented: $disputeFiled) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Case #DSP-\(Int.random(in: 1000...9999)) opened. An arbiter reviews the contract within 48 hours; funds stay escrowed until resolution.")
        }
        .sheet(item: $explorerURL) { url in
            BuildSafariView(url: url)
                .ignoresSafeArea()
        }
    }

    private var explorerAddress: String {
        // Use counterparty if it looks like an address; otherwise fall back to a placeholder
        let raw = contract.counterparty
        if raw.hasPrefix("0x") {
            // Strip ellipsis truncation if present
            return raw.replacingOccurrences(of: "...", with: "")
        }
        return "0x0000000000000000000000000000000000000000"
    }
}

// MARK: - Build Safari View Wrapper

struct BuildSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Template Card View

struct TemplateCardView: View {
    let template: BuildContractTemplate
    var onUse: () -> Void = {}
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
                Button(action: onUse) {
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
    @State private var showManage = false
    @State private var manageResult: String?

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
                        showManage = true
                    } label: {
                        Text("Manage")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))
                }
            }
        }
        .confirmationDialog(subscription.name, isPresented: $showManage, titleVisibility: .visible) {
            Button("Change plan (\(subscription.tier))") {
                manageResult = "Plan change scheduled — takes effect at the next billing cycle."
            }
            Button("Pause billing") {
                manageResult = "Billing paused. Resume anytime from this menu."
            }
            Button("Cancel subscription", role: .destructive) {
                manageResult = "Subscription cancelled — access continues until \(subscription.nextDate)."
            }
            Button("Close", role: .cancel) {}
        } message: {
            Text("\(subscription.amount) · renews \(subscription.nextDate)")
        }
        .alert("Done", isPresented: .init(
            get: { manageResult != nil },
            set: { if !$0 { manageResult = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(manageResult ?? "")
        }
    }
}

// MARK: - Data Models

/// Contracts created in the New Contract wizard land here so the Build
/// hub list shows them immediately, ahead of the sample history.
@MainActor
final class DeployedContractsStore: ObservableObject {
    static let shared = DeployedContractsStore()
    @Published var items: [ContractListItem] = []
}

struct ContractListItem: Identifiable {
    let id = UUID()
    let title: String
    let contractType: String
    let counterparty: String
    let value: String
    let valueNumeric: Double
    let status: BuildContractStatus
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

struct BuildContractTemplate: Identifiable {
    let id = UUID()
    let name: String
    let description_: String
    let icon: String
    let accentColor: Color

    static let sampleData: [BuildContractTemplate] = [
        BuildContractTemplate(name: "Escrow", description_: "Milestone-based escrow with conditional release", icon: Symbols.escrow, accentColor: .accentPrimary),
        BuildContractTemplate(name: "Freelance", description_: "Time or deliverable based freelance agreement", icon: Symbols.contract, accentColor: .statusInfo),
        BuildContractTemplate(name: "Subscription", description_: "Recurring payment streams with auto-renewal", icon: Symbols.processing, accentColor: .purple),
        BuildContractTemplate(name: "Revenue Share", description_: "Automatic revenue splitting between parties", icon: Symbols.chartPie, accentColor: .statusSuccess),
        BuildContractTemplate(name: "Joint Ownership", description_: "Shared asset ownership with governance rules", icon: Symbols.property, accentColor: .orange),
        BuildContractTemplate(name: "Loan Agreement", description_: "Collateralized lending with flexible terms", icon: Symbols.fee, accentColor: .accentTertiary),
        BuildContractTemplate(name: "Fundraiser", description_: "Campaign-based fundraising with milestones", icon: Symbols.fundraiser, accentColor: .pink),
        BuildContractTemplate(name: "DAO", description_: "Decentralized governance with treasury management", icon: Symbols.dao, accentColor: .accentSecondary),
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

    /// Renewal dates are always in the future relative to today.
    private static func upcoming(_ days: Int) -> String {
        (Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
            .formatted(.dateTime.month(.abbreviated).day().year())
    }

    static let sampleData: [SubscriptionItem] = [
        SubscriptionItem(name: "DeFi Yield Optimizer", tier: "Pro", amount: "$29/mo", nextDate: upcoming(21), icon: Symbols.chartLine, tierColor: .accentPrimary, usagePercent: 0.73),
        SubscriptionItem(name: "Data Oracle Feed", tier: "Standard", amount: "$12/mo", nextDate: upcoming(9), icon: Symbols.link, tierColor: .statusInfo, usagePercent: 0.45),
        SubscriptionItem(name: "Contract Analytics", tier: "Free", amount: "$0/mo", nextDate: "N/A", icon: Symbols.chartBar, tierColor: .labelTertiary, usagePercent: 0.92),
    ]
}

// MARK: - Contract Filter Sheet

struct ContractFilterSheet: View {
    @Binding var selected: Set<BuildContractStatus>
    @Environment(\.dismiss) private var dismiss

    private let allStatuses: [BuildContractStatus] = [.active, .pending, .completed, .disputed]

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                MtrxCard(style: .standard) {
                    VStack(spacing: 0) {
                        ForEach(Array(allStatuses.enumerated()), id: \.offset) { index, status in
                            Toggle(isOn: binding(for: status)) {
                                HStack(spacing: Spacing.ms) {
                                    Image(systemName: status.icon)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(status.color)
                                        .frame(width: 28, height: 28)

                                    Text(status.rawValue)
                                        .font(.mtrxBody)
                                        .foregroundStyle(Color.labelPrimary)
                                }
                            }
                            .tint(Color.accentPrimary)
                            .padding(.vertical, Spacing.sm)

                            if index < allStatuses.count - 1 {
                                MtrxDivider()
                            }
                        }
                    }
                }

                Button {
                    selected = Set(allStatuses)
                    MtrxHaptics.selection()
                } label: {
                    Text("Reset Filters")
                }
                .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))

                Spacer()
            }
            .padding(Spacing.contentPadding)
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Filter Contracts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentPrimary)
                }
            }
        }
    }

    private func binding(for status: BuildContractStatus) -> Binding<Bool> {
        Binding(
            get: { selected.contains(status) },
            set: { isOn in
                if isOn {
                    selected.insert(status)
                } else {
                    selected.remove(status)
                }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    BuildView()
}
