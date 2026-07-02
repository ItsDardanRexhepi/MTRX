// FundraiserView.swift
// MTRX
//
// Fundraiser campaign browsing with progress tracking, milestones, and contribution flow.

import SwiftUI

// MARK: - Fundraiser ViewModel

@MainActor
final class FundraiserViewModel: ObservableObject {
    @Published var campaigns: [Campaign] = []
    @Published var selectedFilter: CampaignFilter = .all
    @Published var isLoading: Bool = false
    @Published var selectedCampaign: Campaign?
    @Published var showDetail: Bool = false
    @Published var isDemo: Bool = true

    // MARK: - Filtered Campaigns

    var filteredCampaigns: [Campaign] {
        switch selectedFilter {
        case .all:
            return campaigns
        case .active:
            return campaigns.filter { $0.status == .active }
        case .completed:
            return campaigns.filter { $0.status == .completed }
        case .myCampaigns:
            return campaigns.filter { $0.isOwnCampaign }
        }
    }

    // MARK: - Load

    func loadCampaigns() async {
        guard !isLoading else { return }
        isLoading = true

        try? await Task.sleep(nanoseconds: 800_000_000)
        campaigns = Campaign.sampleData
        isDemo = true
        isLoading = false
    }

    func refresh() async {
        campaigns = []
        await loadCampaigns()
    }

    func selectCampaign(_ campaign: Campaign) {
        selectedCampaign = campaign
        showDetail = true
        MtrxHaptics.impact(.light)
    }
}

// MARK: - Campaign Filter

enum CampaignFilter: String, CaseIterable, Identifiable {
    case all          = "All"
    case active       = "Active"
    case completed    = "Completed"
    case myCampaigns  = "My Campaigns"

    var id: String { rawValue }
}

// MARK: - Campaign Status

enum FundraiserCampaignStatus: String {
    case active    = "Active"
    case completed = "Completed"

    var color: Color {
        switch self {
        case .active:    return .statusSuccess
        case .completed: return .accentPrimary
        }
    }

    var badgeStyle: MtrxBadge.BadgeStyle {
        switch self {
        case .active:    return .success
        case .completed: return .accent
        }
    }
}

// MARK: - Campaign Model

struct Campaign: Identifiable {
    let id = UUID()
    let title: String
    let creatorName: String
    let creatorInitials: String
    let description_: String
    let raised: Double
    let goal: Double
    let backerCount: Int
    let daysRemaining: Int
    let status: FundraiserCampaignStatus
    let isOwnCampaign: Bool
    let milestones: [CampaignMilestone]
    let rewardTiers: [RewardTier]
    let avatarColor: Color

    var progress: Double { min(raised / goal, 1.0) }
    var percentComplete: Int { Int(progress * 100) }

    var formattedRaised: String {
        if raised >= 1_000_000 {
            return String(format: "$%.1fM", raised / 1_000_000)
        } else if raised >= 1_000 {
            return String(format: "$%,.0f", raised)
        }
        return String(format: "$%.0f", raised)
    }

    var formattedGoal: String {
        if goal >= 1_000_000 {
            return String(format: "$%.1fM", goal / 1_000_000)
        } else if goal >= 1_000 {
            return String(format: "$%,.0f", goal)
        }
        return String(format: "$%.0f", goal)
    }

    static let sampleData: [Campaign] = [
        Campaign(
            title: "Community Solar Farm",
            creatorName: "SolarDAO",
            creatorInitials: "SD",
            description_: "Building a 2MW solar farm to power rural communities in East Africa. This project provides sustainable energy and creates local jobs. Fully transparent on-chain governance with milestone-based fund release.",
            raised: 72000, goal: 100000, backerCount: 234, daysRemaining: 12,
            status: .active, isOwnCampaign: false,
            milestones: [
                CampaignMilestone(title: "Land Acquisition", description_: "Secure and prepare the site", targetAmount: 20000, isComplete: true),
                CampaignMilestone(title: "Equipment Purchase", description_: "Order solar panels and inverters", targetAmount: 50000, isComplete: true),
                CampaignMilestone(title: "Installation", description_: "Full installation and grid connection", targetAmount: 80000, isComplete: false),
                CampaignMilestone(title: "Launch", description_: "Begin power generation", targetAmount: 100000, isComplete: false),
            ],
            rewardTiers: [
                RewardTier(name: "Bronze", amount: 25, description_: "Thank you message and progress updates"),
                RewardTier(name: "Silver", amount: 100, description_: "Name on donor wall + quarterly energy reports"),
                RewardTier(name: "Gold", amount: 500, description_: "Revenue share token + governance voting rights"),
            ],
            avatarColor: .orange
        ),
        Campaign(
            title: "Clean Water DAO",
            creatorName: "AquaDAO",
            creatorInitials: "AD",
            description_: "Deploying water purification systems across 15 villages in rural Kenya. Each system serves 500+ people. Smart contract ensures funds release only upon verified installation.",
            raised: 45000, goal: 120000, backerCount: 156, daysRemaining: 28,
            status: .active, isOwnCampaign: false,
            milestones: [
                CampaignMilestone(title: "Survey Complete", description_: "Site assessment for all villages", targetAmount: 15000, isComplete: true),
                CampaignMilestone(title: "Phase 1 Deploy", description_: "Install in first 5 villages", targetAmount: 50000, isComplete: false),
                CampaignMilestone(title: "Phase 2 Deploy", description_: "Install in next 5 villages", targetAmount: 85000, isComplete: false),
                CampaignMilestone(title: "Full Coverage", description_: "Complete all installations", targetAmount: 120000, isComplete: false),
            ],
            rewardTiers: [
                RewardTier(name: "Bronze", amount: 10, description_: "Impact certificate NFT"),
                RewardTier(name: "Silver", amount: 50, description_: "Named well plaque + NFT"),
                RewardTier(name: "Gold", amount: 250, description_: "DAO voting token + impact dashboard"),
            ],
            avatarColor: .blue
        ),
        Campaign(
            title: "Open Source DeFi Tools",
            creatorName: "DevCollective",
            creatorInitials: "DC",
            description_: "Building open-source developer tools for DeFi protocol integration. Includes SDK, documentation, and example applications. All code MIT licensed.",
            raised: 38000, goal: 50000, backerCount: 412, daysRemaining: 5,
            status: .active, isOwnCampaign: true,
            milestones: [
                CampaignMilestone(title: "Core SDK", description_: "Build and release the core SDK", targetAmount: 15000, isComplete: true),
                CampaignMilestone(title: "Documentation", description_: "Comprehensive docs and tutorials", targetAmount: 30000, isComplete: true),
                CampaignMilestone(title: "Example Apps", description_: "3 reference applications", targetAmount: 40000, isComplete: false),
                CampaignMilestone(title: "Audit & Launch", description_: "Security audit and v1.0 release", targetAmount: 50000, isComplete: false),
            ],
            rewardTiers: [
                RewardTier(name: "Bronze", amount: 15, description_: "Name in contributor credits"),
                RewardTier(name: "Silver", amount: 100, description_: "Logo in README + priority support"),
                RewardTier(name: "Gold", amount: 1000, description_: "Governance seat + custom integration"),
            ],
            avatarColor: .green
        ),
        Campaign(
            title: "Regenerative Agriculture",
            creatorName: "FarmDAO",
            creatorInitials: "FD",
            description_: "Transitioning 500 acres of conventional farmland to regenerative practices. Carbon credits generated are tokenized and distributed to backers.",
            raised: 250000, goal: 250000, backerCount: 892, daysRemaining: 0,
            status: .completed, isOwnCampaign: false,
            milestones: [
                CampaignMilestone(title: "Soil Testing", description_: "Baseline soil health assessment", targetAmount: 25000, isComplete: true),
                CampaignMilestone(title: "Cover Crops", description_: "Plant initial cover crop rotation", targetAmount: 100000, isComplete: true),
                CampaignMilestone(title: "Equipment", description_: "No-till equipment purchase", targetAmount: 180000, isComplete: true),
                CampaignMilestone(title: "Full Transition", description_: "Complete regenerative conversion", targetAmount: 250000, isComplete: true),
            ],
            rewardTiers: [
                RewardTier(name: "Bronze", amount: 20, description_: "Monthly farm updates"),
                RewardTier(name: "Silver", amount: 200, description_: "Carbon credit token allocation"),
                RewardTier(name: "Gold", amount: 2000, description_: "Revenue share + farm visit"),
            ],
            avatarColor: .purple
        ),
        Campaign(
            title: "Mesh Network Initiative",
            creatorName: "ConnectDAO",
            creatorInitials: "CD",
            description_: "Deploying decentralized mesh network nodes across underserved urban areas. Providing free internet access and resilient communication infrastructure.",
            raised: 18500, goal: 75000, backerCount: 89, daysRemaining: 45,
            status: .active, isOwnCampaign: false,
            milestones: [
                CampaignMilestone(title: "Hardware Sourcing", description_: "Source and test mesh hardware", targetAmount: 20000, isComplete: false),
                CampaignMilestone(title: "Pilot Zone", description_: "Deploy 10-node pilot network", targetAmount: 40000, isComplete: false),
                CampaignMilestone(title: "Expansion", description_: "Scale to 50 nodes across 3 zones", targetAmount: 60000, isComplete: false),
                CampaignMilestone(title: "Full Network", description_: "100+ nodes with redundancy", targetAmount: 75000, isComplete: false),
            ],
            rewardTiers: [
                RewardTier(name: "Bronze", amount: 10, description_: "Network status dashboard access"),
                RewardTier(name: "Silver", amount: 75, description_: "Dedicated node naming rights"),
                RewardTier(name: "Gold", amount: 500, description_: "Governance + bandwidth allocation"),
            ],
            avatarColor: .accentPrimary
        ),
        Campaign(
            title: "Music Rights Marketplace",
            creatorName: "SoundBlock",
            creatorInitials: "SB",
            description_: "Building a decentralized platform for independent musicians to tokenize and trade music royalty rights. Smart contracts automate revenue distribution.",
            raised: 95000, goal: 95000, backerCount: 543, daysRemaining: 0,
            status: .completed, isOwnCampaign: false,
            milestones: [
                CampaignMilestone(title: "Smart Contracts", description_: "Royalty distribution contracts", targetAmount: 30000, isComplete: true),
                CampaignMilestone(title: "Platform MVP", description_: "Core marketplace interface", targetAmount: 60000, isComplete: true),
                CampaignMilestone(title: "Artist Onboarding", description_: "Onboard 50 pilot artists", targetAmount: 80000, isComplete: true),
                CampaignMilestone(title: "Public Launch", description_: "Open marketplace to all", targetAmount: 95000, isComplete: true),
            ],
            rewardTiers: [
                RewardTier(name: "Bronze", amount: 25, description_: "Early platform access"),
                RewardTier(name: "Silver", amount: 150, description_: "Curated royalty token bundle"),
                RewardTier(name: "Gold", amount: 1000, description_: "Platform governance token"),
            ],
            avatarColor: .pink
        ),
    ]
}

struct CampaignMilestone: Identifiable {
    let id = UUID()
    let title: String
    let description_: String
    let targetAmount: Double
    let isComplete: Bool
}

struct RewardTier: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
    let description_: String
}

// MARK: - Fundraiser View

struct FundraiserView: View {
    @StateObject private var viewModel = FundraiserViewModel()
    @State private var appeared = false

    var body: some View { _regulatedBody.mvpGated() }

    @ViewBuilder private var _regulatedBody: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                if viewModel.isLoading && viewModel.campaigns.isEmpty {
                    loadingState
                } else if viewModel.filteredCampaigns.isEmpty {
                    MtrxEmptyState(
                        icon: Symbols.fundraiser,
                        title: "No Campaigns",
                        message: "No \(viewModel.selectedFilter.rawValue.lowercased()) campaigns found. Check back later or start your own.",
                        actionLabel: "Refresh"
                    ) {
                        Task { await viewModel.refresh() }
                    }
                } else {
                    campaignList
                        .demoBadge(viewModel.isDemo)
                }
            }
            .navigationTitle("Fundraisers")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showDetail) {
                if let campaign = viewModel.selectedCampaign {
                    CampaignDetailSheet(campaign: campaign)
                        .presentationDetents([.large])
                }
            }
            .task {
                guard !appeared else { return }
                appeared = true
                await viewModel.loadCampaigns()
            }
        }
    }

    // MARK: - Campaign List

    private var campaignList: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                filterChips
                campaignCards
            }
            .padding(.bottom, Spacing.xxl)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(CampaignFilter.allCases) { filter in
                    MtrxChip(
                        label: filter.rawValue,
                        isSelected: filter == viewModel.selectedFilter
                    ) {
                        withAnimation(Motion.springSnappy) {
                            viewModel.selectedFilter = filter
                        }
                        MtrxHaptics.selection()
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Campaign Cards

    private var campaignCards: some View {
        LazyVStack(spacing: Spacing.ms) {
            ForEach(Array(viewModel.filteredCampaigns.enumerated()), id: \.element.id) { index, campaign in
                CampaignCardView(campaign: campaign) {
                    viewModel.selectCampaign(campaign)
                }
                .mtrxStaggeredAppearance(index: index, isVisible: appeared)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Loading

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: Spacing.ms) {
                HStack(spacing: Spacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule()
                            .fill(Color.surfaceOverlay)
                            .frame(width: 72, height: 30)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.contentPadding)
                .mtrxShimmer(isActive: true)

                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            Circle().fill(Color.surfaceOverlay).frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.surfaceOverlay).frame(width: 140, height: 14)
                                RoundedRectangle(cornerRadius: 3).fill(Color.surfaceOverlay).frame(width: 80, height: 10)
                            }
                            Spacer()
                        }
                        RoundedRectangle(cornerRadius: 4).fill(Color.surfaceOverlay).frame(height: 8)
                        HStack {
                            RoundedRectangle(cornerRadius: 3).fill(Color.surfaceOverlay).frame(width: 80, height: 12)
                            Spacer()
                            RoundedRectangle(cornerRadius: 3).fill(Color.surfaceOverlay).frame(width: 60, height: 12)
                        }
                    }
                    .mtrxCardStyle()
                    .mtrxShimmer(isActive: true)
                }
            }
            .padding(.top, Spacing.sm)
        }
    }
}

// MARK: - Campaign Card

struct CampaignCardView: View {
    let campaign: Campaign
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            MtrxCard(style: .standard) {
                VStack(alignment: .leading, spacing: Spacing.ms) {
                    // Title
                    Text(campaign.title)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Creator row
                    HStack(spacing: Spacing.sm) {
                        MtrxAvatar(
                            text: campaign.creatorInitials,
                            color: campaign.avatarColor,
                            size: 24
                        )

                        Text(campaign.creatorName)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)

                        Spacer()

                        MtrxBadge(text: campaign.status.rawValue, style: campaign.status.badgeStyle)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.surfaceOverlay)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentPrimary)
                                .frame(width: geo.size.width * campaign.progress, height: 8)
                                .animation(Motion.springDefault, value: campaign.progress)
                        }
                    }
                    .frame(height: 8)

                    // Amount
                    HStack(spacing: Spacing.xs) {
                        Text("\(campaign.formattedRaised) / \(campaign.formattedGoal) raised")
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    // Stats row
                    HStack(spacing: Spacing.ms) {
                        MtrxProgressRing(
                            progress: campaign.progress,
                            size: 36,
                            lineWidth: 3,
                            color: .accentPrimary,
                            showLabel: true
                        )

                        Text("\(campaign.percentComplete)%")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.accentPrimary)

                        HStack(spacing: Spacing.xs) {
                            Image(systemName: Symbols.backers)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.labelTertiary)
                            Text("\(campaign.backerCount)")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)
                        }

                        if campaign.daysRemaining > 0 {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: Symbols.clock)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.labelTertiary)
                                Text("\(campaign.daysRemaining)d left")
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(campaign.daysRemaining <= 5 ? Color.statusWarning : Color.labelSecondary)
                            }
                        }

                        Spacer()

                        if campaign.status == .active {
                            Button {} label: {
                                Text("Back This")
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Campaign Detail Sheet

struct CampaignDetailSheet: View {
    let campaign: Campaign
    @Environment(\.dismiss) private var dismiss
    @State private var contributionAmount: String = ""
    @State private var isContributing = false
    @State private var showContributed = false

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                        MtrxSheetHeader(title: campaign.title, subtitle: "by \(campaign.creatorName)") {
                            dismiss()
                        }

                        descriptionSection
                        progressSection
                        milestoneTimeline
                        rewardTiersSection
                        contributionSection

                        Spacer().frame(height: Spacing.xxxl)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                }

                // Floating contribute button
                if campaign.status == .active && !contributionAmount.isEmpty {
                    VStack {
                        Spacer()

                        Button {
                            guard let val = Double(contributionAmount), val > 0 else { return }
                            isContributing = true
                            MtrxHaptics.success()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isContributing = false
                                showContributed = true
                                contributionAmount = ""
                            }
                        } label: {
                            Text("Contribute")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: isContributing, fullWidth: true))
                        .disabled(contributionAmount.isEmpty || isContributing)
                        .padding(Spacing.contentPadding)
                        .background(.ultraThinMaterial)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: Symbols.close)
                            .accessibilityLabel("Close")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
            .overlay {
                if showContributed {
                    contributedToast
                }
            }
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("About")
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)

                Text(campaign.description_)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .lineSpacing(4)
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Raised")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        MtrxAnimatedValue(
                            value: campaign.raised,
                            prefix: "$",
                            decimals: 0,
                            font: .mtrxMonoMedium,
                            color: .accentPrimary
                        )
                    }

                    Spacer()

                    MtrxProgressRing(
                        progress: campaign.progress,
                        size: 64,
                        lineWidth: 6,
                        color: .accentPrimary,
                        showLabel: true
                    )

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Goal")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Text(campaign.formattedGoal)
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.surfaceOverlay)
                            .frame(height: 10)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentPrimary)
                            .frame(width: geo.size.width * campaign.progress, height: 10)
                            .mtrxGlow(color: .accentPrimary, radius: 4)
                    }
                }
                .frame(height: 10)

                HStack {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.backers)
                            .font(.system(size: 14))
                        Text("\(campaign.backerCount) backers")
                            .font(.mtrxCaptionBold)
                    }
                    .foregroundStyle(Color.labelSecondary)

                    Spacer()

                    if campaign.daysRemaining > 0 {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: Symbols.clock)
                                .font(.system(size: 14))
                            Text("\(campaign.daysRemaining) days left")
                                .font(.mtrxCaptionBold)
                        }
                        .foregroundStyle(campaign.daysRemaining <= 5 ? Color.statusWarning : Color.labelSecondary)
                    } else {
                        MtrxBadge(text: "Ended", style: .neutral)
                    }
                }
            }
        }
    }

    // MARK: - Milestone Timeline

    private var milestoneTimeline: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Milestones")
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)

                ForEach(Array(campaign.milestones.enumerated()), id: \.element.id) { index, milestone in
                    HStack(alignment: .top, spacing: Spacing.ms) {
                        // Timeline connector
                        VStack(spacing: 0) {
                            milestoneCircle(for: milestone, index: index)

                            if index < campaign.milestones.count - 1 {
                                Rectangle()
                                    .fill(Color.accentPrimary.opacity(0.3))
                                    .frame(width: 2)
                                    .frame(minHeight: 44)
                            }
                        }

                        // Content
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(milestone.title)
                                .font(.mtrxCalloutBold)
                                .foregroundStyle(milestone.isComplete ? Color.labelPrimary : Color.labelSecondary)

                            Text(milestone.description_)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelTertiary)

                            Text(String(format: "$%,.0f", milestone.targetAmount))
                                .font(.mtrxMonoSmall)
                                .foregroundStyle(milestone.isComplete ? Color.accentPrimary : Color.labelTertiary)
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    private func milestoneCircle(for milestone: CampaignMilestone, index: Int) -> some View {
        let isCurrentMilestone = !milestone.isComplete && (index == 0 || campaign.milestones[index - 1].isComplete)

        return ZStack {
            Circle()
                .fill(milestone.isComplete ? Color.statusSuccess : (isCurrentMilestone ? Color.clear : Color.surfaceOverlay))
                .frame(width: 14, height: 14)

            Circle()
                .stroke(
                    milestone.isComplete ? Color.statusSuccess : (isCurrentMilestone ? Color.accentPrimary : Color.labelTertiary),
                    lineWidth: 2
                )
                .frame(width: 14, height: 14)

            if milestone.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Reward Tiers

    private var rewardTiersSection: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Reward Tiers")
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)

                ForEach(campaign.rewardTiers) { tier in
                    MtrxCard(style: .outlined) {
                        HStack(spacing: Spacing.ms) {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: Symbols.reward)
                                        .font(.system(size: 14))
                                        .foregroundStyle(tierColor(for: tier.name))

                                    Text(tier.name)
                                        .font(.mtrxCalloutBold)
                                        .foregroundStyle(Color.labelPrimary)
                                }

                                Text(tier.description_)
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                            }

                            Spacer()

                            Text(String(format: "$%.0f+", tier.amount))
                                .font(.mtrxMono)
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                }
            }
        }
    }

    private func tierColor(for name: String) -> Color {
        switch name {
        case "Bronze": return .orange
        case "Silver": return .gray
        case "Gold":   return .yellow
        default:       return .accentPrimary
        }
    }

    // MARK: - Contribution Section

    private var contributionSection: some View {
        Group {
            if campaign.status == .active {
                MtrxCard(style: .elevated, accentEdge: .top) {
                    VStack(alignment: .leading, spacing: Spacing.ms) {
                        Text("Contribute")
                            .font(.mtrxTitle3)
                            .foregroundStyle(Color.labelPrimary)

                        MtrxTextField(
                            placeholder: "Amount (USD)",
                            text: $contributionAmount,
                            icon: "dollarsign.circle",
                            keyboardType: .decimalPad
                        )

                        // Quick amount chips
                        HStack(spacing: Spacing.sm) {
                            ForEach(["25", "50", "100", "500"], id: \.self) { amount in
                                MtrxChip(
                                    label: "$\(amount)",
                                    isSelected: contributionAmount == amount
                                ) {
                                    contributionAmount = amount
                                    MtrxHaptics.selection()
                                }
                            }
                        }

                        HStack(spacing: Spacing.xs) {
                            Image(systemName: Symbols.gas)
                                .font(.system(size: 12))
                            Text("Est. network fee: ~0.001 ETH")
                                .font(.mtrxCaption1)
                        }
                        .foregroundStyle(Color.labelTertiary)

                        Button {
                            guard let val = Double(contributionAmount), val > 0 else { return }
                            isContributing = true
                            MtrxHaptics.success()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isContributing = false
                                withAnimation(Motion.springDefault) {
                                    showContributed = true
                                }
                                contributionAmount = ""
                            }
                        } label: {
                            Text("Contribute")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, isLoading: isContributing, fullWidth: true))
                        .disabled(contributionAmount.isEmpty || isContributing)
                    }
                }
            }
        }
    }

    // MARK: - Toast

    private var contributedToast: some View {
        VStack {
            MtrxToast(message: "Contribution submitted!", icon: Symbols.complete, style: .success)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(Motion.springDefault) {
                            showContributed = false
                        }
                    }
                }
            Spacer()
        }
        .padding(.top, Spacing.xl)
        .animation(Motion.springDefault, value: showContributed)
    }
}

// MARK: - Preview

#Preview {
    FundraiserView()
        .preferredColorScheme(.dark)
}
