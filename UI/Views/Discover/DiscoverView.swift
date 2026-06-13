// DiscoverView.swift
// MTRX
//
// Marketplace browsing and discovery hub — featured items, trending listings,
// active fundraisers, and the partner network.

import SwiftUI

// MARK: - Discover ViewModel

@MainActor
final class DiscoverViewModel: ObservableObject {

    // MARK: - Published State

    @Published var featuredItems: [FeaturedItem] = []
    @Published var trendingListings: [MarketplaceListing] = []
    @Published var activeFundraisers: [FundraiserItem] = []
    @Published var partners: [PartnerItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    @Published var selectedCategory: DiscoverCategory = .all
    @Published var currentFeaturedIndex: Int = 0
    @Published var contentAppeared: Bool = false

    // MARK: - Computed Filters

    var filteredFeaturedItems: [FeaturedItem] {
        var result = featuredItems
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.subtitle.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var filteredListings: [MarketplaceListing] {
        var result = trendingListings
        if selectedCategory != .all {
            result = result.filter { $0.categoryKey == selectedCategory.rawValue }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.category.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var filteredFundraisers: [FundraiserItem] {
        var result = activeFundraisers
        if selectedCategory != .all && selectedCategory != .markets {
            return []
        }
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var filteredPartners: [PartnerItem] {
        if !searchText.isEmpty {
            return partners.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return partners
    }

    // MARK: - Load Data

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // Simulated network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        featuredItems = FeaturedItem.sampleData
        trendingListings = MarketplaceListing.sampleData
        activeFundraisers = FundraiserItem.sampleData
        partners = PartnerItem.sampleData

        isLoading = false

        withAnimation(Motion.springDefault) {
            contentAppeared = true
        }
    }

    func refresh() async {
        contentAppeared = false
        await loadAll()
    }

    // MARK: - Auto-advance Featured

    func advanceFeatured() {
        guard !filteredFeaturedItems.isEmpty else { return }
        withAnimation(Motion.springGentle) {
            currentFeaturedIndex = (currentFeaturedIndex + 1) % filteredFeaturedItems.count
        }
    }
}

// MARK: - Discover Category

/// Discoverable categories on the Discover tab.
///
/// Aligned with the backend capability catalog (21 categories at
/// `runtime/capabilities/catalog.py`). Each case maps to a `category`
/// value returned by `GET /api/v1/capabilities/categories`, so the tab
/// can filter against the live registry with no translation layer.
enum DiscoverCategory: String, CaseIterable, Identifiable {
    case all
    case contracts
    case defi
    case defiAdvanced = "defi_advanced"
    case nft
    case nftFinance = "nft_finance"
    case identity
    case governance
    case social
    case creator
    case payments
    case bridging
    case staking
    case privacy
    case oracles
    case storage
    case compute
    case realWorld = "real_world"
    case markets
    case security
    case gaming
    case infra

    var id: String { rawValue }

    /// Human-friendly label shown on the filter chip.
    var displayName: String {
        switch self {
        case .all:           return "All"
        case .contracts:     return "Contracts"
        case .defi:          return "DeFi"
        case .defiAdvanced:  return "DeFi Advanced"
        case .nft:           return "NFTs"
        case .nftFinance:    return "NFT Finance"
        case .identity:      return "Identity"
        case .governance:    return "Governance"
        case .social:        return "Social"
        case .creator:       return "Creator"
        case .payments:      return "Payments"
        case .bridging:      return "Cross-chain"
        case .staking:       return "Staking"
        case .privacy:       return "Privacy"
        case .oracles:       return "Oracles"
        case .storage:       return "Storage"
        case .compute:       return "Compute"
        case .realWorld:     return "Real-World"
        case .markets:       return "Markets"
        case .security:      return "Security"
        case .gaming:        return "Gaming"
        case .infra:         return "Infra"
        }
    }

    /// SF Symbol name used in the chip and detail views.
    var icon: String {
        switch self {
        case .all:           return Symbols.globe
        case .contracts:     return "doc.text.fill"
        case .defi:          return Symbols.chartLine
        case .defiAdvanced:  return "chart.bar.xaxis"
        case .nft:           return "photo.artframe"
        case .nftFinance:    return "dollarsign.square"
        case .identity:      return "person.text.rectangle"
        case .governance:    return Symbols.dao
        case .social:        return "bubble.left.and.bubble.right"
        case .creator:       return "music.note"
        case .payments:      return "creditcard"
        case .bridging:      return "arrow.left.arrow.right"
        case .staking:       return "lock.square.stack"
        case .privacy:       return "lock.shield"
        case .oracles:       return "antenna.radiowaves.left.and.right"
        case .storage:       return "externaldrive"
        case .compute:       return "cpu"
        case .realWorld:     return "building.2"
        case .markets:       return Symbols.marketplace
        case .security:      return "key.fill"
        case .gaming:        return "gamecontroller.fill"
        case .infra:         return "server.rack"
        }
    }

    /// Whether this category routes to a dedicated hub view when tapped.
    var hasHubView: Bool {
        switch self {
        case .bridging, .compute, .gaming, .creator, .oracles,
             .realWorld, .payments, .storage, .markets, .defiAdvanced,
             .nft, .nftFinance, .identity, .social, .contracts, .staking:
            return true
        default:
            return false
        }
    }
}

// MARK: - DeFi Sub-Destination

/// Sub-destinations for the "Explore DeFi" section on Discover.
enum DeFiSubDestination: String, Hashable, Identifiable {
    case lending
    case liquidity
    case yield
    case realWorld
    case governance

    var id: String { rawValue }
}

// MARK: - Discover View

struct DiscoverView: View {
    @EnvironmentObject var walletManager: WalletManager
    @StateObject private var viewModel = DiscoverViewModel()
    @State private var autoAdvanceTimer: Timer?
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var selectedFeaturedItem: FeaturedItem?
    @State private var pushedCategory: DiscoverCategory?
    @State private var pushedDeFi: DeFiSubDestination?
    @State private var showFilters = false
    @State private var showDiscoverMenu = false
    @State private var showTrendingAll = false
    @State private var backingFundraiser: FundraiserItem?

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                Group {
                    if viewModel.isLoading && viewModel.trendingListings.isEmpty {
                        MtrxLoadingView(rows: 8)
                    } else {
                        contentView
                    }
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MtrxGlassCircleButton(icon: "line.3.horizontal") {
                        showDiscoverMenu = true
                    }
                }
            }
            .sheet(isPresented: $showDiscoverMenu) {
                DiscoverMenuSheet(
                    selectedCategory: $viewModel.selectedCategory,
                    onCategory: { category in
                        if category.hasHubView {
                            pushedCategory = category
                        } else {
                            withAnimation(Motion.springSnappy) { viewModel.selectedCategory = category }
                        }
                        showDiscoverMenu = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .navigationDestination(item: $pushedCategory) { category in
                categoryDestination(for: category)
            }
            .navigationDestination(item: $pushedDeFi) { destination in
                defiDestination(for: destination)
            }
        }
        .task {
            await viewModel.loadAll()
            startAutoAdvance()
        }
        // "Explore something new" completes only when the user actually
        // drills into a category, a DeFi hub, or a featured item.
        .onChange(of: pushedCategory) { _, v in if v != nil { DailyFlow.shared.mark(.explore) } }
        .onChange(of: pushedDeFi) { _, v in if v != nil { DailyFlow.shared.mark(.explore) } }
        .onDisappear {
            stopAutoAdvance()
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .sheet(item: $selectedFeaturedItem) { item in
            FeaturedDetailSheet(item: item) { selectedFeaturedItem = nil }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showFilters) {
            DiscoverFiltersSheet()
        }
        .sheet(item: $backingFundraiser) { fundraiser in
            BackFundraiserSheet(fundraiser: fundraiser)
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Generous section rhythm — each section gets room to breathe.
            // Leaner Discover: categories + recent activity live in the
            // menu pop-out; fundraisers fold into Trending; Top Yield is
            // merged into Yield Farming; Portfolio lives in Account.
            LazyVStack(spacing: Spacing.lg) {
                searchBar
                    .mtrxStaggeredAppearance(index: 0, isVisible: viewModel.contentAppeared)

                featuredSection
                    .mtrxStaggeredAppearance(index: 1, isVisible: viewModel.contentAppeared)

                exploreDeFiSection
                    .mtrxStaggeredAppearance(index: 2, isVisible: viewModel.contentAppeared)

                trendingSection
                    .mtrxStaggeredAppearance(index: 3, isVisible: viewModel.contentAppeared)

                // Bottom padding for tab bar
                Spacer().frame(height: Spacing.xxl)
            }
            .padding(.top, Spacing.sm)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        MtrxSearchBar(text: $viewModel.searchText, placeholder: "Search marketplace, fundraisers...")
            .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(DiscoverCategory.allCases, id: \.self) { category in
                    MtrxChip(
                        label: category.rawValue,
                        icon: category.icon,
                        isSelected: viewModel.selectedCategory == category
                    ) {
                        MtrxHaptics.selection()
                        // If this category has a dedicated hub view, push it.
                        // Otherwise fall back to the existing filter behavior.
                        if category.hasHubView {
                            pushedCategory = category
                        } else {
                            withAnimation(Motion.springSnappy) {
                                viewModel.selectedCategory = category
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Category Destination

    @ViewBuilder
    private func categoryDestination(for category: DiscoverCategory) -> some View {
        switch category {
        case .bridging:
            BridgeView()
        case .compute:
            ComputeView()
        case .gaming:
            GamingView()
        case .creator:
            MusicView()
        case .oracles:
            OraclesView()
        case .realWorld:
            RWAView()
        case .payments:
            StablecoinView()
        case .storage:
            StorageView()
        case .markets:
            TradingView()
        case .defiAdvanced:
            YieldView()
        case .nft:
            NFTGalleryView()
        case .nftFinance:
            MintNFTView()
        case .identity:
            DomainView()
        case .social:
            EventsView()
        case .contracts:
            DisputeView()
        case .staking:
            StakingView()
        default:
            EmptyView()
        }
    }

    // MARK: - DeFi Sub-Destination

    @ViewBuilder
    private func defiDestination(for destination: DeFiSubDestination) -> some View {
        switch destination {
        case .lending:
            LendingView()
        case .liquidity:
            LiquidityView()
        case .yield:
            YieldView()
        case .realWorld:
            RWAView()
        case .governance:
            GovernanceView()
        }
    }

    // MARK: - Explore DeFi Section

    /// One browse category for everything financial on Discover:
    /// lending, liquidity, yield, real-world assets, and governance.
    private var exploreDeFiSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionHeaderBottom) {
            MtrxSectionHeader(title: "Explore DeFi")
                .padding(.horizontal, Spacing.contentPadding)

            VStack(spacing: Spacing.sm) {
                exploreRow(systemName: "banknote.fill", title: "Lending", subtitle: "Borrow and lend assets", color: .statusInfo) {
                    pushedDeFi = .lending
                }
                exploreRow(systemName: "drop.fill", title: "Liquidity Pools", subtitle: "Provide liquidity, earn fees", color: .trinityPrimary) {
                    pushedDeFi = .liquidity
                }
                exploreRow(systemName: "chart.line.uptrend.xyaxis", title: "Yield Farming", subtitle: "Optimize returns across protocols", color: .statusSuccess) {
                    pushedDeFi = .yield
                }
                exploreRow(systemName: "building.columns.fill", title: "Real World Assets", subtitle: "Bonds, property & commodities", color: .accentSecondary) {
                    pushedDeFi = .realWorld
                }
                exploreRow(systemName: "checkmark.seal.fill", title: "Governance", subtitle: "Vote on active proposals", color: .purple) {
                    pushedDeFi = .governance
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    private func exploreRow(systemName: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            MtrxHaptics.selection()
            action()
        } label: {
            MtrxCard(style: .standard) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: systemName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(color)
                        .frame(width: 40, height: 40)
                        .background(color.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)
                        Text(subtitle)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    Image(systemName: Symbols.forward)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Featured Section

    private var featuredSection: some View {
        let items = viewModel.filteredFeaturedItems
        return VStack(alignment: .leading, spacing: Spacing.sectionHeaderBottom) {
            MtrxSectionHeader(title: "Featured")
                .padding(.horizontal, Spacing.contentPadding)

            if items.isEmpty {
                EmptyView()
            } else {
                TabView(selection: $viewModel.currentFeaturedIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        FeaturedCardView(item: item, onExplore: {
                            selectedFeaturedItem = item
                            DailyFlow.shared.mark(.explore)
                        })
                            // Half the previous inset → the channel between
                            // adjacent cards is halved while they stay coherent.
                            .padding(.horizontal, Spacing.xs)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 196)

                // Page dots
                HStack(spacing: 6) {
                    ForEach(0..<items.count, id: \.self) { index in
                        Circle()
                            .fill(index == viewModel.currentFeaturedIndex ? Color.accentPrimary : Color.labelQuaternary)
                            .frame(width: index == viewModel.currentFeaturedIndex ? 8 : 6, height: index == viewModel.currentFeaturedIndex ? 8 : 6)
                            .animation(Motion.springSnappy, value: viewModel.currentFeaturedIndex)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.xs)
            }
        }
    }

    // MARK: - Trending Section

    private var trendingSection: some View {
        // Trending: a ranked top-5 list, then a side-scrolling carousel of
        // the next five — ten total, with everything behind See All.
        let all = viewModel.filteredListings
        let topFive = Array(all.prefix(5))
        let nextFive = Array(all.dropFirst(5).prefix(5))
        return VStack(alignment: .leading, spacing: Spacing.sectionHeaderBottom) {
            MtrxSectionHeader(title: "Trending", action: {
                MtrxHaptics.impact(.light)
                showTrendingAll = true
            })
            .padding(.horizontal, Spacing.contentPadding)

            if topFive.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.search,
                    title: "No Results",
                    message: "Try adjusting your search or category filter."
                )
                .frame(height: 180)
            } else {
                // The side-scrolling carousel rides on top; the ranked
                // top-five list sits beneath it.
                if !nextFive.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.md) {
                            ForEach(nextFive) { listing in
                                NavigationLink {
                                    MarketplaceListingDetail(listing: listing)
                                } label: {
                                    TrendingMiniCard(listing: listing)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded { DailyFlow.shared.mark(.explore) })
                            }
                        }
                        .padding(.horizontal, Spacing.contentPadding)
                    }
                }

                LazyVStack(spacing: Spacing.xs) {
                    ForEach(Array(topFive.enumerated()), id: \.element.id) { index, listing in
                        NavigationLink {
                            MarketplaceListingDetail(listing: listing)
                        } label: {
                            TrendingListingRow(listing: listing, rank: index + 1)
                                .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { DailyFlow.shared.mark(.explore) })
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, nextFive.isEmpty ? 0 : Spacing.xs)
            }
        }
        .sheet(isPresented: $showTrendingAll) {
            TrendingAllSheet(listings: all)
        }
    }

    // MARK: - Portfolio Card (removed from Discover — lives in Account)

    // MARK: - Portfolio Card

    private var portfolioCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionHeaderBottom) {
            MtrxSectionHeader(title: "Portfolio")
                .padding(.horizontal, Spacing.contentPadding)

            NavigationLink {
                Text("Portfolio")
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Total Value")
                            .font(.mtrxCaption)
                            .foregroundStyle(Color.labelSecondary)
                        Text(walletManager.totalPortfolioValue, format: .currency(code: "USD"))
                            .font(.mtrxTitle2)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("24h Change")
                            .font(.mtrxCaption)
                            .foregroundStyle(Color.labelSecondary)
                        Text(String(format: "%@%.2f%%", walletManager.portfolioChange24h >= 0 ? "+" : "", walletManager.portfolioChange24h))
                            .font(.mtrxHeadline)
                            .foregroundStyle(walletManager.portfolioChange24h >= 0 ? Color.statusSuccess : Color.statusError)
                    }
                }
                .padding(Spacing.ml)
                .background(Color.surfaceOverlay)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Yield Opportunities Section

    private var yieldOpportunitiesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionHeaderBottom) {
            MtrxSectionHeader(title: "Top Yield Opportunities")
                .padding(.horizontal, Spacing.contentPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    yieldCard(name: "ETH Staking", apy: "4.2%", risk: "Conservative", color: .statusSuccess)
                    yieldCard(name: "USDC Lending", apy: "6.8%", risk: "Conservative", color: .statusSuccess)
                    yieldCard(name: "ETH-USDC LP", apy: "12.4%", risk: "Moderate", color: .statusWarning)
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    private func yieldCard(name: String, apy: String, risk: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name)
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelPrimary)
            Text(apy)
                .font(.mtrxTitle2)
                .foregroundStyle(Color.accentPrimary)
            Text(risk)
                .font(.mtrxCaption)
                .foregroundStyle(color)
        }
        .frame(width: 156, alignment: .leading)
        .padding(Spacing.ml)
        .background(Color.surfaceOverlay)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionHeaderBottom) {
            MtrxSectionHeader(title: "Recent Activity")
                .padding(.horizontal, Spacing.contentPadding)

            VStack(spacing: Spacing.xs) {
                activityRow(type: "Swap", detail: "0.5 ETH → 900 USDC", time: "2 min ago", icon: "arrow.triangle.2.circlepath")
                activityRow(type: "Stake", detail: "1.0 ETH staked", time: "1 hour ago", icon: "lock.fill")
                activityRow(type: "Received", detail: "250 USDC from vitalik.eth", time: "3 hours ago", icon: "arrow.down.circle.fill")
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    private func activityRow(type: String, detail: String, time: String, icon: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 32, height: 32)
                .background(Color.accentPrimary.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(type)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelPrimary)
                Text(detail)
                    .font(.mtrxCaption)
                    .foregroundStyle(Color.labelSecondary)
            }
            Spacer()
            Text(time)
                .font(.mtrxCaption)
                .foregroundStyle(Color.labelTertiary)
        }
        .padding(Spacing.sm)
        .background(Color.surfaceOverlay)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }

    // MARK: - Timer

    private func startAutoAdvance() {
        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                viewModel.advanceFeatured()
            }
        }
    }

    private func stopAutoAdvance() {
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
    }
}

// MARK: - Featured Card View

struct FeaturedCardView: View {
    let item: FeaturedItem
    var onExplore: (() -> Void)? = nil
    @State private var parallaxOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let midX = geometry.frame(in: .global).midX
            let screenWidth = UIScreen.main.bounds.width
            let offset = (midX - screenWidth / 2) / screenWidth

            ZStack(alignment: .bottomLeading) {
                // Gradient background
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous)
                    .fill(item.gradient)
                    .overlay(
                        // Subtle pattern overlay
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.08), .clear, .black.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                // Parallax decorative circle
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 200, height: 200)
                    .offset(x: 140 + offset * 30, y: -60)

                Circle()
                    .fill(.white.opacity(0.04))
                    .frame(width: 120, height: 120)
                    .offset(x: -40 + offset * 20, y: -100)

                // Content
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Category badge
                    MtrxBadge(text: item.badge, style: .accent)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())

                    Spacer()

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(item.title)
                            .font(.mtrxTitle2)
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(item.subtitle)
                            .font(.mtrxSubheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }

                    Button {
                        MtrxHaptics.impact(.medium)
                        onExplore?()
                    } label: {
                        Text("Explore")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .accent, size: .compact))
                }
                .padding(Spacing.md)
            }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous))
            .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.xl)
            .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        }
    }
}

// MARK: - Trending Listing Row

struct TrendingListingRow: View {
    let listing: MarketplaceListing
    let rank: Int

    var body: some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                // Rank number
                Text("\(rank)")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelTertiary)
                    .frame(width: 20)

                // Token avatar
                MtrxAvatar(
                    symbol: listing.icon,
                    color: listing.avatarColor,
                    size: Spacing.Size.avatarMedium
                )

                // Name + category
                VStack(alignment: .leading, spacing: 2) {
                    Text(listing.name)
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)

                    MtrxBadge(text: listing.category, style: .neutral)
                }

                Spacer()

                // Price + change
                VStack(alignment: .trailing, spacing: 2) {
                    Text(listing.price)
                        .font(.mtrxMono)
                        .foregroundStyle(Color.labelPrimary)

                    HStack(spacing: 3) {
                        Image(systemName: listing.change24h >= 0 ? Symbols.trendUp : Symbols.trendDown)
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.1f%%", abs(listing.change24h)))
                            .font(.mtrxCaptionBold)
                    }
                    .foregroundStyle(listing.change24h >= 0 ? Color.priceUp : Color.priceDown)
                }
            }
        }
    }
}

// MARK: - Trending Mini Card (the side-scrolling five)

struct TrendingMiniCard: View {
    let listing: MarketplaceListing

    var body: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                MtrxAvatar(symbol: listing.icon, color: listing.avatarColor, size: Spacing.Size.avatarMedium)
                Text(listing.name)
                    .font(.mtrxCalloutBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                MtrxBadge(text: listing.category, style: .neutral)
                HStack(spacing: Spacing.sm) {
                    Text(listing.price)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                    HStack(spacing: 2) {
                        Image(systemName: listing.change24h >= 0 ? Symbols.trendUp : Symbols.trendDown)
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%.1f%%", abs(listing.change24h)))
                            .font(.mtrxCaption2)
                    }
                    .foregroundStyle(listing.change24h >= 0 ? Color.priceUp : Color.priceDown)
                }
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}

// MARK: - Trending All Sheet (See All)

struct TrendingAllSheet: View {
    let listings: [MarketplaceListing]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(Array(listings.enumerated()), id: \.element.id) { index, listing in
                        NavigationLink {
                            MarketplaceListingDetail(listing: listing)
                        } label: {
                            TrendingListingRow(listing: listing, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("All Trending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
        }
    }
}

// MARK: - Fundraiser Card View

struct FundraiserCardView: View {
    let fundraiser: FundraiserItem
    var onBack: (() -> Void)? = nil
    @State private var isPressed: Bool = false

    var body: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.ms) {
                // Title row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fundraiser.title)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(1)

                        Text(fundraiser.description_)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    MtrxProgressRing(
                        progress: fundraiser.progress,
                        size: 50,
                        lineWidth: 5,
                        color: fundraiser.progress >= 0.75 ? .statusSuccess : .accentPrimary
                    )
                }

                // Raised / Goal
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Raised")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(fundraiser.raisedFormatted)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.accentPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Goal")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(fundraiser.goalFormatted)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }

                // Days left + Back button
                HStack {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.clock)
                            .font(.system(size: 12))
                        Text(fundraiser.daysLeft)
                            .font(.mtrxCaptionBold)
                    }
                    .foregroundStyle(Color.labelSecondary)

                    Spacer()

                    Button {
                        MtrxHaptics.impact(.medium)
                        onBack?()
                    } label: {
                        Text("Back")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                }
            }
        }
        .frame(width: 280)
        .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
    }
}

// MARK: - Marketplace Listing Detail (Placeholder)

struct MarketplaceListingDetail: View {
    let listing: MarketplaceListing

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                MtrxAvatar(
                    symbol: listing.icon,
                    color: listing.avatarColor,
                    size: Spacing.Size.avatarXLarge
                )
                .padding(.top, Spacing.xl)

                Text(listing.name)
                    .font(.mtrxTitle1)

                MtrxBadge(text: listing.category, style: .accent)

                Text(listing.price)
                    .font(.mtrxMonoMedium)
                    .foregroundStyle(Color.accentPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .background(MtrxGradientBackground(style: .primary))
        .navigationTitle(listing.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data Models

struct FeaturedItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let badge: String
    let gradientColors: [Color]

    var gradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let sampleData: [FeaturedItem] = [
        FeaturedItem(
            title: "Tokenized Real Estate",
            subtitle: "Invest in fractional property ownership on-chain",
            badge: "Featured",
            gradientColors: [Color.accentPrimary, Color(red: 0.1, green: 0.3, blue: 0.6)]
        ),
        FeaturedItem(
            title: "DeFi Yield Aggregator",
            subtitle: "Auto-compound across 15+ protocols for max yield",
            badge: "Trending",
            gradientColors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.1, blue: 0.5)]
        ),
        FeaturedItem(
            title: "Parametric Insurance",
            subtitle: "Weather-indexed crop protection with instant payouts",
            badge: "New",
            gradientColors: [Color(red: 0.0, green: 0.5, blue: 0.4), Color(red: 0.0, green: 0.3, blue: 0.5)]
        ),
        FeaturedItem(
            title: "DAO Governance Hub",
            subtitle: "Create and manage decentralized organizations",
            badge: "Popular",
            gradientColors: [Color(red: 0.6, green: 0.3, blue: 0.0), Color(red: 0.4, green: 0.15, blue: 0.0)]
        ),
        FeaturedItem(
            title: "Carbon Credit Exchange",
            subtitle: "Trade verified carbon offsets transparently",
            badge: "Impact",
            gradientColors: [Color(red: 0.1, green: 0.5, blue: 0.2), Color(red: 0.05, green: 0.3, blue: 0.15)]
        ),
        FeaturedItem(
            title: "Gaming Marketplace",
            subtitle: "Trade in-game assets across chains seamlessly",
            badge: "Hot",
            gradientColors: [Color(red: 0.7, green: 0.1, blue: 0.3), Color(red: 0.5, green: 0.0, blue: 0.4)]
        ),
    ]
}

struct MarketplaceListing: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: String
    /// Matches a DiscoverCategory rawValue so the chips filter exactly.
    let categoryKey: String
    let price: String
    let change24h: Double
    let volume: String
    let icon: String
    let avatarColor: Color

    /// At least one listing per Discover category, so every chip
    /// demos with real content.
    static let sampleData: [MarketplaceListing] = [
        // real_world
        MarketplaceListing(name: "Nairobi Solar Farm", category: "Real World", categoryKey: "real_world", price: "$50.00", change24h: 12.4, volume: "2.4K", icon: Symbols.property, avatarColor: .orange),
        MarketplaceListing(name: "Carbon Credits", category: "Real World", categoryKey: "real_world", price: "$12.50", change24h: -2.1, volume: "8.1K", icon: Symbols.globe, avatarColor: .green),
        MarketplaceListing(name: "Weather Shield Insurance", category: "Real World", categoryKey: "real_world", price: "$150.00", change24h: 1.5, volume: "1.2K", icon: Symbols.insurance, avatarColor: .accentPrimary),
        // defi
        MarketplaceListing(name: "DeFi Index Fund", category: "DeFi", categoryKey: "defi", price: "$1,240.00", change24h: 3.8, volume: "12K", icon: Symbols.chartPie, avatarColor: .blue),
        MarketplaceListing(name: "Yield Optimizer V2", category: "DeFi", categoryKey: "defi", price: "$89.99", change24h: 7.2, volume: "5.6K", icon: Symbols.chartLine, avatarColor: .purple),
        // defi_advanced
        MarketplaceListing(name: "Options Vault Pro", category: "DeFi Advanced", categoryKey: "defi_advanced", price: "$310.00", change24h: 9.1, volume: "4.2K", icon: "chart.xyaxis.line", avatarColor: .purple),
        MarketplaceListing(name: "Perp Strategy Engine", category: "DeFi Advanced", categoryKey: "defi_advanced", price: "$199.00", change24h: -3.2, volume: "2.9K", icon: "waveform.path.ecg", avatarColor: .blue),
        // contracts
        MarketplaceListing(name: "Escrow Contract Suite", category: "Contracts", categoryKey: "contracts", price: "$120.00", change24h: 5.2, volume: "3.7K", icon: "doc.badge.gearshape", avatarColor: .statusInfo),
        MarketplaceListing(name: "Audit-Ready Templates", category: "Contracts", categoryKey: "contracts", price: "$45.00", change24h: 2.8, volume: "6.4K", icon: "checkmark.shield", avatarColor: .green),
        // nft
        MarketplaceListing(name: "Genesis Art Drop", category: "NFT", categoryKey: "nft", price: "$85.00", change24h: 18.3, volume: "7.1K", icon: "photo.artframe", avatarColor: .pink),
        // nft_finance
        MarketplaceListing(name: "NFT Lending Desk", category: "NFT Finance", categoryKey: "nft_finance", price: "$210.00", change24h: 6.7, volume: "1.8K", icon: "banknote", avatarColor: .orange),
        // identity
        MarketplaceListing(name: "ZK Identity Pass", category: "Identity", categoryKey: "identity", price: "$15.00", change24h: 4.1, volume: "11K", icon: "person.badge.shield.checkmark", avatarColor: .accentPrimary),
        // governance
        MarketplaceListing(name: "Governance Token", category: "Governance", categoryKey: "governance", price: "$3.42", change24h: -0.8, volume: "45K", icon: Symbols.dao, avatarColor: .accentTertiary),
        MarketplaceListing(name: "DAO Launch Toolkit", category: "Governance", categoryKey: "governance", price: "$75.00", change24h: 3.3, volume: "2.2K", icon: "building.columns", avatarColor: .statusInfo),
        // social
        MarketplaceListing(name: "Creator Social Graph", category: "Social", categoryKey: "social", price: "$28.00", change24h: 11.0, volume: "5.3K", icon: "person.2.wave.2", avatarColor: .pink),
        // creator
        MarketplaceListing(name: "Royalty Splitter", category: "Creator", categoryKey: "creator", price: "$65.00", change24h: 7.9, volume: "1.6K", icon: "music.note.list", avatarColor: .purple),
        // payments
        MarketplaceListing(name: "Instant Pay Rails", category: "Payments", categoryKey: "payments", price: "$9.99", change24h: 15.6, volume: "22K", icon: "bolt.circle", avatarColor: .accentPrimary),
        // bridging
        MarketplaceListing(name: "Cross-Chain Bridge Pass", category: "Bridging", categoryKey: "bridging", price: "$75.00", change24h: -1.4, volume: "3.1K", icon: "arrow.left.arrow.right.circle", avatarColor: .blue),
        // staking
        MarketplaceListing(name: "Staking Pool Alpha", category: "Staking", categoryKey: "staking", price: "$500.00", change24h: -4.3, volume: "9.8K", icon: Symbols.stake, avatarColor: .statusInfo),
        // privacy
        MarketplaceListing(name: "ZK Privacy Shield", category: "Privacy", categoryKey: "privacy", price: "$140.00", change24h: 8.8, volume: "2.7K", icon: "eye.slash.circle", avatarColor: .accentTertiary),
        // oracles
        MarketplaceListing(name: "Price Oracle Feed", category: "Oracles", categoryKey: "oracles", price: "$199.00", change24h: 2.4, volume: "13K", icon: "antenna.radiowaves.left.and.right", avatarColor: .orange),
        // storage
        MarketplaceListing(name: "Decentralized Storage Quota", category: "Storage", categoryKey: "storage", price: "$19.00", change24h: 5.5, volume: "8.9K", icon: "externaldrive.badge.icloud", avatarColor: .green),
        // compute
        MarketplaceListing(name: "GPU Compute Credits", category: "Compute", categoryKey: "compute", price: "$240.00", change24h: 21.2, volume: "4.8K", icon: "cpu", avatarColor: .statusError),
        // markets
        MarketplaceListing(name: "Prediction Markets Pack", category: "Markets", categoryKey: "markets", price: "$55.00", change24h: 13.5, volume: "6.2K", icon: "chart.bar.xaxis", avatarColor: .pink),
        MarketplaceListing(name: "Gaming Loot Market", category: "Markets", categoryKey: "markets", price: "$25.00", change24h: 24.6, volume: "3.3K", icon: "gamecontroller.fill", avatarColor: .pink),
    ]
}

struct FundraiserItem: Identifiable {
    let id = UUID()
    let title: String
    let description_: String
    let progress: Double
    let raised: Double
    let goal: Double
    let daysLeft: String
    let isVerified: Bool

    var raisedFormatted: String {
        formatCurrency(raised)
    }

    var goalFormatted: String {
        formatCurrency(goal)
    }

    private func formatCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        } else {
            return String(format: "$%.0f", value)
        }
    }

    static let sampleData: [FundraiserItem] = [
        FundraiserItem(title: "Community Solar", description_: "Solar panel installation for rural communities across East Africa", progress: 0.72, raised: 72_000, goal: 100_000, daysLeft: "12 days left", isVerified: true),
        FundraiserItem(title: "Water Access DAO", description_: "Clean water infrastructure and maintenance in remote villages", progress: 0.45, raised: 225_000, goal: 500_000, daysLeft: "28 days left", isVerified: true),
        FundraiserItem(title: "Open Protocol Fund", description_: "Building open-source DeFi tooling for emerging markets", progress: 0.88, raised: 440_000, goal: 500_000, daysLeft: "5 days left", isVerified: true),
        FundraiserItem(title: "Digital ID Initiative", description_: "Self-sovereign identity infrastructure for underbanked populations", progress: 0.31, raised: 155_000, goal: 500_000, daysLeft: "45 days left", isVerified: false),
    ]
}

struct PartnerItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let category: String
    let brandColor: Color
    let isVerified: Bool

    static let sampleData: [PartnerItem] = [
        PartnerItem(name: "Aave", icon: Symbols.stake, category: "Lending", brandColor: .purple, isVerified: true),
        PartnerItem(name: "Uniswap", icon: Symbols.swap, category: "DEX", brandColor: .pink, isVerified: true),
        PartnerItem(name: "Chainlink", icon: Symbols.link, category: "Oracle", brandColor: .blue, isVerified: true),
        PartnerItem(name: "XMTP", icon: Symbols.messageEncrypted, category: "Messaging", brandColor: .accentPrimary, isVerified: true),
        PartnerItem(name: "Lido", icon: Symbols.escrow, category: "Staking", brandColor: .accentSecondary, isVerified: true),
        PartnerItem(name: "ENS", icon: Symbols.globe, category: "Identity", brandColor: .statusInfo, isVerified: true),
    ]
}

// MARK: - Discover Filters Sheet

struct DiscoverFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss

    enum SortOption: String, CaseIterable, Identifiable {
        case trending = "Trending"
        case newest = "Newest"
        case topRated = "Top Rated"

        var id: String { rawValue }
    }

    @State private var freeTierOnly: Bool = false
    @State private var availableNow: Bool = false
    @State private var sortOption: SortOption = .trending

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sectionGap) {
                    MtrxCard(style: .glass) {
                        VStack(spacing: Spacing.md) {
                            Toggle(isOn: $freeTierOnly) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Free tier only")
                                        .font(.mtrxBodyBold)
                                        .foregroundStyle(Color.labelPrimary)
                                    Text("Hide listings with paid plans")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                }
                            }
                            .tint(Color.accentPrimary)

                            MtrxDivider()

                            Toggle(isOn: $availableNow) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Available now")
                                        .font(.mtrxBodyBold)
                                        .foregroundStyle(Color.labelPrimary)
                                    Text("Hide listings with waitlists")
                                        .font(.mtrxCaption1)
                                        .foregroundStyle(Color.labelSecondary)
                                }
                            }
                            .tint(Color.accentPrimary)
                        }
                    }

                    MtrxCard(style: .glass) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Sort by")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)

                            Picker("Sort", selection: $sortOption) {
                                ForEach(SortOption.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.vertical, Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        MtrxHaptics.impact(.light)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Back Fundraiser Sheet

struct BackFundraiserSheet: View {
    let fundraiser: FundraiserItem
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""

    private let presets: [Int] = [25, 50, 100, 250]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sectionGap) {
                    headerCard
                    progressCard
                    amountCard
                    trinityNote
                    payButton
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.vertical, Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Back Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var headerCard: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(fundraiser.title)
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)
                Text(fundraiser.description_)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressCard: some View {
        MtrxCard(style: .glass) {
            VStack(spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Raised")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(fundraiser.raisedFormatted)
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.accentPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Goal")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(fundraiser.goalFormatted)
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }

                ProgressView(value: fundraiser.progress)
                    .tint(Color.accentPrimary)

                HStack {
                    Image(systemName: Symbols.clock)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.labelSecondary)
                    Text(fundraiser.daysLeft)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                }
            }
        }
    }

    private var amountCard: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Contribution")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)

                HStack {
                    Text("$")
                        .font(.mtrxMonoLarge)
                        .foregroundStyle(Color.labelSecondary)
                    TextField("0", text: $amountText)
                        .font(.mtrxMonoLarge)
                        .foregroundStyle(Color.labelPrimary)
                        .keyboardType(.decimalPad)
                }
                .padding(Spacing.md)
                .background(Color.surfaceOverlay)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))

                HStack(spacing: Spacing.sm) {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            MtrxHaptics.selection()
                            amountText = "\(preset)"
                        } label: {
                            Text("$\(preset)")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.accentPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.sm)
                                .background(Color.accentPrimary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var trinityNote: some View {
        MtrxCard(style: .standard) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: Symbols.escrow)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trinity-secured escrow")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelPrimary)
                    Text("Your contribution is held in a smart contract escrow until the fundraiser milestones are met. Funds are auto-refunded if the goal isn't reached.")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        }
    }

    private var payButton: some View {
        Button {
            MtrxHaptics.success()
            dismiss()
        } label: {
            Text("Pay")
        }
        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
        .disabled(amountText.isEmpty)
    }
}

// MARK: - Preview

#Preview {
    DiscoverView()
        .environmentObject(WalletManager())
}

// MARK: - Featured Detail Sheet

/// Full product page for a Featured item: hero, live-feeling stats,
/// what it does, why it matters, and a working door into the real hub.
struct FeaturedDetailSheet: View {
    let item: FeaturedItem
    let onDone: () -> Void

    private struct Detail {
        let about: String
        let stats: [(String, String)]
        let highlights: [String]
        let ctaLabel: String
    }

    private var detail: Detail {
        switch item.title {
        case "Tokenized Real Estate":
            return Detail(
                about: "Own fractions of income-generating property from $50. Every share is an on-chain token with automated rent distribution, transparent valuations, and instant secondary-market liquidity — no brokers, no paperwork, no minimum lockup.",
                stats: [("$48M", "Tokenized"), ("7.2%", "Avg yield"), ("12K", "Investors")],
                highlights: ["Fractional ownership from $50", "Monthly rent paid automatically", "Audited property valuations on-chain", "Sell your share anytime"],
                ctaLabel: "Browse Properties"
            )
        case "DeFi Yield Aggregator":
            return Detail(
                about: "One deposit, fifteen protocols. The aggregator continuously moves your liquidity to the best risk-adjusted yield across audited DeFi venues and auto-compounds the returns — what would take hours of daily management happens on-chain, every block.",
                stats: [("15+", "Protocols"), ("11.4%", "Top APY"), ("$120M", "TVL")],
                highlights: ["Auto-compounding every block", "Risk-scored protocol allocation", "Withdraw anytime, no penalties", "Gas costs covered by MTRX"],
                ctaLabel: "Open Yield Hub"
            )
        case "Parametric Insurance":
            return Detail(
                about: "Insurance that pays the moment the data says so. Coverage is indexed to verified weather oracles — if rainfall drops below the threshold, the payout executes instantly. No claims process, no adjusters, no waiting.",
                stats: [("<60s", "Payout time"), ("40K", "Policies"), ("99.8%", "Auto-settled")],
                highlights: ["Instant oracle-triggered payouts", "No claims paperwork ever", "Cover crops, travel, or events", "Premiums from $5/month"],
                ctaLabel: "Explore Coverage"
            )
        case "DAO Governance Hub":
            return Detail(
                about: "Spin up a decentralized organization in minutes: token-weighted voting, treasury management, and proposal pipelines — all enforced by smart contracts. From three-person project squads to ten-thousand-member communities.",
                stats: [("2.4K", "Active DAOs"), ("$310M", "In treasuries"), ("89K", "Voters")],
                highlights: ["Launch a DAO in under 5 minutes", "On-chain voting with delegation", "Multi-sig treasury built in", "Templates for every structure"],
                ctaLabel: "Open Governance"
            )
        case "Carbon Credit Exchange":
            return Detail(
                about: "Trade verified carbon offsets with full provenance. Every credit traces back to a certified project with satellite-verified impact data — retire credits to offset your footprint or trade them on the open market.",
                stats: [("1.2M", "Tons offset"), ("340", "Projects"), ("100%", "Verified")],
                highlights: ["Satellite-verified projects", "Instant retirement certificates", "Transparent pricing history", "Fractional credits from $1"],
                ctaLabel: "View Marketplace"
            )
        default: // Gaming Marketplace
            return Detail(
                about: "Your items, actually yours. Trade weapons, skins, and characters across games and chains — assets live in your wallet, not a publisher's database, so they survive any game shutting down.",
                stats: [("8M", "Items traded"), ("120", "Games"), ("0.5%", "Trade fee")],
                highlights: ["Cross-game asset portability", "Instant escrow-protected trades", "Creator royalties built in", "Works across 6 chains"],
                ctaLabel: "Open Gaming Hub"
            )
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch item.title {
        case "Tokenized Real Estate": RWAView()
        case "DeFi Yield Aggregator": YieldView()
        case "Parametric Insurance": RWAView()
        case "DAO Governance Hub": DAOView()
        case "Carbon Credit Exchange": MarketplaceView()
        default: GamingView()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Hero — tightened so the title sits close to the badge.
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous)
                        .fill(item.gradient)
                        .frame(height: 128)
                        .overlay {
                            VStack {
                                HStack {
                                    MtrxBadge(text: item.badge, style: .accent)
                                    Spacer()
                                }
                                Spacer()
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.mtrxTitle2)
                                            .foregroundStyle(.white)
                                        Text(item.subtitle)
                                            .font(.mtrxCaption1)
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                    Spacer()
                                }
                            }
                            .padding(Spacing.md)
                        }

                    // Stats — concrete numbers build trust fast.
                    HStack(spacing: Spacing.sm) {
                        ForEach(detail.stats, id: \.1) { value, label in
                            VStack(spacing: 3) {
                                Text(value)
                                    .font(.mtrxHeadline)
                                    .foregroundStyle(Color.labelPrimary)
                                Text(label)
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.ms)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                        }
                    }

                    // About
                    Text(detail.about)
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelSecondary)
                        .lineSpacing(4)

                    // Highlights
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(detail.highlights, id: \.self) { line in
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.statusSuccess)
                                Text(line)
                                    .font(.mtrxCallout)
                                    .foregroundStyle(Color.labelPrimary)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))

                    // The real door in.
                    NavigationLink {
                        destination
                    } label: {
                        Text(detail.ctaLabel)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(colors: [Color.accentPrimary, Color.trinityPrimary],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
                            .shadow(color: Color.accentPrimary.opacity(0.35), radius: 12, y: 5)
                    }
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
    }
}

// MARK: - Discover Menu (liquid-glass pop-out)

/// The pop-out menu that holds everything that used to clutter the
/// Discover scroll: the category filters and Recent Activity. Liquid
/// glass, opened from the menu button on the top-left.
struct DiscoverMenuSheet: View {
    @Binding var selectedCategory: DiscoverCategory
    let onCategory: (DiscoverCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: Spacing.sm),
                           GridItem(.flexible(), spacing: Spacing.sm)]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Categories
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        MtrxSectionHeader(title: "Categories")
                        LazyVGrid(columns: columns, spacing: Spacing.sm) {
                            // Advanced variants are folded into their parents
                            // (DeFi Advanced → DeFi, NFT Finance → NFTs).
                            ForEach(DiscoverCategory.allCases.filter { $0 != .defiAdvanced && $0 != .nftFinance }) { category in
                                Button {
                                    MtrxHaptics.selection()
                                    onCategory(category)
                                } label: {
                                    HStack(spacing: Spacing.sm) {
                                        Image(systemName: category.icon)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.accentPrimary)
                                            .frame(width: 30, height: 30)
                                            .background(Color.accentPrimary.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                                        Text(category.displayName)
                                            .font(.mtrxCaptionBold)
                                            .foregroundStyle(Color.labelPrimary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 9)
                                    .padding(.horizontal, Spacing.ms)
                                    .background(selectedCategory == category ? Color.accentPrimary.opacity(0.10) : Color.clear)
                                    .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                                            .stroke(selectedCategory == category ? Color.accentPrimary.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Recent Activity
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        MtrxSectionHeader(title: "Recent Activity")
                        VStack(spacing: Spacing.xs) {
                            menuActivityRow("Swap", "0.5 ETH → 900 USDC", "2 min ago", "arrow.triangle.2.circlepath")
                            menuActivityRow("Stake", "1.0 ETH staked", "1 hour ago", "lock.fill")
                            menuActivityRow("Received", "250 USDC from vitalik.eth", "3 hours ago", "arrow.down.circle.fill")
                        }
                    }
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
        }
    }

    private func menuActivityRow(_ type: String, _ detail: String, _ time: String, _ icon: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 32, height: 32)
                .background(Color.accentPrimary.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(type).font(.mtrxCaptionBold).foregroundStyle(Color.labelPrimary)
                Text(detail).font(.mtrxCaption2).foregroundStyle(Color.labelTertiary).lineLimit(1)
            }
            Spacer()
            Text(time).font(.mtrxCaption2).foregroundStyle(Color.labelQuaternary)
        }
        .padding(Spacing.ms)
        .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
    }
}
