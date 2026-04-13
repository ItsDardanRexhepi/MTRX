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
            result = result.filter { $0.category.localizedCaseInsensitiveContains(selectedCategory.rawValue) }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.category.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var filteredFundraisers: [FundraiserItem] {
        var result = activeFundraisers
        if selectedCategory != .all && selectedCategory != .fundraisers {
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

enum DiscoverCategory: String, CaseIterable {
    case all = "All"
    case marketplace = "Marketplace"
    case fundraisers = "Fundraisers"
    case daos = "DAOs"
    case defi = "DeFi"
    case insurance = "Insurance"
    case gaming = "Gaming"

    var icon: String {
        switch self {
        case .all: return Symbols.globe
        case .marketplace: return Symbols.marketplace
        case .fundraisers: return Symbols.fundraiser
        case .daos: return Symbols.dao
        case .defi: return Symbols.chartLine
        case .insurance: return Symbols.insurance
        case .gaming: return "gamecontroller.fill"
        }
    }
}

// MARK: - Discover View

struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @State private var autoAdvanceTimer: Timer?

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        MtrxHaptics.impact(.light)
                    } label: {
                        Image(systemName: Symbols.filter)
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
            }
        }
        .task {
            await viewModel.loadAll()
            startAutoAdvance()
        }
        .onDisappear {
            stopAutoAdvance()
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: Spacing.sectionGap) {
                searchBar
                    .mtrxStaggeredAppearance(index: 0, isVisible: viewModel.contentAppeared)

                categoryChips
                    .mtrxStaggeredAppearance(index: 1, isVisible: viewModel.contentAppeared)

                featuredSection
                    .mtrxStaggeredAppearance(index: 2, isVisible: viewModel.contentAppeared)

                trendingSection
                    .mtrxStaggeredAppearance(index: 3, isVisible: viewModel.contentAppeared)

                fundraiserSection
                    .mtrxStaggeredAppearance(index: 4, isVisible: viewModel.contentAppeared)

                partnerSection
                    .mtrxStaggeredAppearance(index: 5, isVisible: viewModel.contentAppeared)

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
                        withAnimation(Motion.springSnappy) {
                            viewModel.selectedCategory = category
                        }
                        MtrxHaptics.selection()
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
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
                        FeaturedCardView(item: item)
                            .padding(.horizontal, Spacing.contentPadding)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 280)

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
        let listings = viewModel.filteredListings
        return VStack(alignment: .leading, spacing: Spacing.sectionHeaderBottom) {
            MtrxSectionHeader(title: "Trending", action: {
                MtrxHaptics.impact(.light)
            })
            .padding(.horizontal, Spacing.contentPadding)

            if listings.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.search,
                    title: "No Results",
                    message: "Try adjusting your search or category filter."
                )
                .frame(height: 180)
            } else {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(Array(listings.enumerated()), id: \.element.id) { index, listing in
                        NavigationLink {
                            MarketplaceListingDetail(listing: listing)
                        } label: {
                            TrendingListingRow(listing: listing, rank: index + 1)
                                .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Fundraiser Section

    private var fundraiserSection: some View {
        let fundraisers = viewModel.filteredFundraisers
        return VStack(alignment: .leading, spacing: Spacing.sectionHeaderBottom) {
            MtrxSectionHeader(title: "Active Fundraisers", action: {
                MtrxHaptics.impact(.light)
            })
            .padding(.horizontal, Spacing.contentPadding)

            if !fundraisers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(fundraisers) { fundraiser in
                            FundraiserCardView(fundraiser: fundraiser)
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                }
            }
        }
    }

    // MARK: - Partner Section

    private var partnerSection: some View {
        let partners = viewModel.filteredPartners
        return VStack(alignment: .leading, spacing: Spacing.sectionHeaderBottom) {
            MtrxSectionHeader(title: "Partner Network")
                .padding(.horizontal, Spacing.contentPadding)

            if !partners.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                    ForEach(Array(partners.enumerated()), id: \.element.id) { index, partner in
                        PartnerCardView(partner: partner)
                            .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
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
                    } label: {
                        Text("Explore")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .accent, size: .compact))
                }
                .padding(Spacing.lg)
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

// MARK: - Fundraiser Card View

struct FundraiserCardView: View {
    let fundraiser: FundraiserItem
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

// MARK: - Partner Card View

struct PartnerCardView: View {
    let partner: PartnerItem
    @State private var isPressed: Bool = false

    var body: some View {
        MtrxCard(style: .glass) {
            VStack(spacing: Spacing.ms) {
                // Logo
                ZStack {
                    Circle()
                        .fill(partner.brandColor.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: partner.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(partner.brandColor)
                }

                // Name
                Text(partner.name)
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)

                Text(partner.category)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)

                // Verified badge
                if partner.isVerified {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.verified)
                            .font(.system(size: 12, weight: .semibold))
                        Text("Verified")
                            .font(.mtrxCaptionBold)
                    }
                    .foregroundStyle(Color.accentPrimary)
                }
            }
            .frame(maxWidth: .infinity)
        }
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
    let price: String
    let change24h: Double
    let volume: String
    let icon: String
    let avatarColor: Color

    static let sampleData: [MarketplaceListing] = [
        MarketplaceListing(name: "Nairobi Solar Farm", category: "Marketplace", price: "$50.00", change24h: 12.4, volume: "2.4K", icon: Symbols.property, avatarColor: .orange),
        MarketplaceListing(name: "DeFi Index Fund", category: "DeFi", price: "$1,240.00", change24h: 3.8, volume: "12K", icon: Symbols.chartPie, avatarColor: .blue),
        MarketplaceListing(name: "Carbon Credits", category: "Marketplace", price: "$12.50", change24h: -2.1, volume: "8.1K", icon: Symbols.globe, avatarColor: .green),
        MarketplaceListing(name: "Yield Optimizer V2", category: "DeFi", price: "$89.99", change24h: 7.2, volume: "5.6K", icon: Symbols.chartLine, avatarColor: .purple),
        MarketplaceListing(name: "Weather Shield", category: "Insurance", price: "$150.00", change24h: 1.5, volume: "1.2K", icon: Symbols.insurance, avatarColor: .accentPrimary),
        MarketplaceListing(name: "Governance Token", category: "DAOs", price: "$3.42", change24h: -0.8, volume: "45K", icon: Symbols.dao, avatarColor: .accentTertiary),
        MarketplaceListing(name: "Gaming Loot Box", category: "Gaming", price: "$25.00", change24h: 24.6, volume: "3.3K", icon: "gamecontroller.fill", avatarColor: .pink),
        MarketplaceListing(name: "Staking Pool Alpha", category: "DeFi", price: "$500.00", change24h: -4.3, volume: "9.8K", icon: Symbols.stake, avatarColor: .statusInfo),
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

// MARK: - Preview

#Preview {
    DiscoverView()
}
