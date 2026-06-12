// MarketplaceView.swift
// MTRX
//
// Full marketplace browsing UI with search, category filters, grid layout, and detail sheet.

import SwiftUI

// MARK: - Marketplace ViewModel

@MainActor
final class MarketplaceViewModel: ObservableObject {
    @Published var listings: [MarketplaceItem] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: MarketCategory = .all
    @Published var sortOption: MarketSortOption = .popularity
    @Published var isLoading: Bool = false
    @Published var showSortPicker: Bool = false
    @Published var selectedListing: MarketplaceItem?
    @Published var showDetail: Bool = false

    // MARK: - Filtered Listings

    var filteredListings: [MarketplaceItem] {
        var result = listings

        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.sellerName.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOption {
        case .priceLow:
            result.sort { $0.priceValue < $1.priceValue }
        case .priceHigh:
            result.sort { $0.priceValue > $1.priceValue }
        case .newest:
            result.sort { $0.listedDate > $1.listedDate }
        case .popularity:
            result.sort { $0.viewCount > $1.viewCount }
        }

        return result
    }

    // MARK: - Load

    func loadListings() async {
        guard !isLoading else { return }
        isLoading = true

        try? await Task.sleep(nanoseconds: 800_000_000)
        listings = MarketplaceItem.sampleData
        isLoading = false
    }

    func refresh() async {
        listings = []
        await loadListings()
    }

    func selectListing(_ item: MarketplaceItem) {
        selectedListing = item
        showDetail = true
        MtrxHaptics.impact(.light)
    }
}

// MARK: - Category

enum MarketCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case property = "Property"
    case digital = "Digital"
    case services = "Services"
    case collectibles = "Collectibles"
    case equipment = "Equipment"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return Symbols.marketplace
        case .property: return Symbols.property
        case .digital: return Symbols.nft
        case .services: return Symbols.contract
        case .collectibles: return Symbols.reward
        case .equipment: return Symbols.build
        }
    }
}

// MARK: - Sort Option

enum MarketSortOption: String, CaseIterable, Identifiable {
    case popularity = "Popular"
    case newest = "Newest"
    case priceLow = "Price: Low"
    case priceHigh = "Price: High"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .popularity: return Symbols.trendUp
        case .newest: return Symbols.clock
        case .priceLow: return "arrow.down"
        case .priceHigh: return "arrow.up"
        }
    }
}

// MARK: - Marketplace Item Model

struct MarketplaceItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let description_: String
    let priceValue: Double
    let category: MarketCategory
    let sellerName: String
    let sellerRating: Double
    let gradientColors: [Color]
    let viewCount: Int
    let listedDate: Date
    let specifications: [SpecRow]

    var formattedPrice: String {
        if priceValue >= 1000 {
            return String(format: "$%,.0f", priceValue)
        }
        return String(format: "$%,.2f", priceValue)
    }

    var categoryBadgeStyle: MtrxBadge.BadgeStyle {
        switch category {
        case .all: return .neutral
        case .property: return .warning
        case .digital: return .info
        case .services: return .success
        case .collectibles: return .accent
        case .equipment: return .neutral
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MarketplaceItem, rhs: MarketplaceItem) -> Bool { lhs.id == rhs.id }

    struct SpecRow: Hashable, Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    static let sampleData: [MarketplaceItem] = [
        MarketplaceItem(
            name: "Nairobi Solar Farm Token",
            description_: "Fractional ownership of a 2MW solar farm in Nairobi. Earn yield from energy production distributed monthly. Fully audited smart contract with insurance coverage.",
            priceValue: 2500, category: .property, sellerName: "SolarDAO", sellerRating: 4.8,
            gradientColors: [.orange, .yellow], viewCount: 1842, listedDate: Date().addingTimeInterval(-86400),
            specifications: [.init(label: "Capacity", value: "2 MW"), .init(label: "Yield", value: "~8.2% APY"), .init(label: "Insurance", value: "Covered")]
        ),
        MarketplaceItem(
            name: "Genesis Pass #0042",
            description_: "Legendary MTRX Genesis Pass granting early access to all platform features, governance voting power, and fee discounts. Limited edition of 100.",
            priceValue: 3400, category: .digital, sellerName: "MTRX Labs", sellerRating: 5.0,
            gradientColors: [.accentPrimary, .blue], viewCount: 3210, listedDate: Date().addingTimeInterval(-172800),
            specifications: [.init(label: "Edition", value: "#42 of 100"), .init(label: "Rarity", value: "Legendary"), .init(label: "Perks", value: "Fee Discount")]
        ),
        MarketplaceItem(
            name: "Smart Contract Audit",
            description_: "Professional security audit for Solidity smart contracts. Includes vulnerability assessment, gas optimization report, and remediation guidance.",
            priceValue: 1800, category: .services, sellerName: "SecureChain", sellerRating: 4.9,
            gradientColors: [.green, .mint], viewCount: 956, listedDate: Date().addingTimeInterval(-43200),
            specifications: [.init(label: "Duration", value: "5-7 days"), .init(label: "Languages", value: "Solidity, Vyper"), .init(label: "Report", value: "Full PDF")]
        ),
        MarketplaceItem(
            name: "Vintage Hardware Wallet",
            description_: "Rare first-edition Ledger Nano S from 2016. Collector's item in original packaging, fully functional with firmware update capability.",
            priceValue: 450, category: .collectibles, sellerName: "CryptoVault", sellerRating: 4.6,
            gradientColors: [.purple, .pink], viewCount: 678, listedDate: Date().addingTimeInterval(-259200),
            specifications: [.init(label: "Year", value: "2016"), .init(label: "Condition", value: "Mint"), .init(label: "Box", value: "Original")]
        ),
        MarketplaceItem(
            name: "Mining Rig - 6x RTX 4090",
            description_: "Complete mining rig with 6 NVIDIA RTX 4090 GPUs. Custom cooling solution, 2000W PSU, ready to deploy. Hashrate tested and verified.",
            priceValue: 12500, category: .equipment, sellerName: "MineForge", sellerRating: 4.7,
            gradientColors: [.red, .orange], viewCount: 2104, listedDate: Date().addingTimeInterval(-518400),
            specifications: [.init(label: "GPUs", value: "6x RTX 4090"), .init(label: "PSU", value: "2000W"), .init(label: "Hashrate", value: "Verified")]
        ),
        MarketplaceItem(
            name: "DeFi Yield Strategy Bot",
            description_: "Automated yield farming bot that optimizes across 12 protocols. Backtested with 18% APY over the last year. Includes source code and documentation.",
            priceValue: 890, category: .digital, sellerName: "AlgoTrader", sellerRating: 4.4,
            gradientColors: [.blue, .cyan], viewCount: 1567, listedDate: Date().addingTimeInterval(-345600),
            specifications: [.init(label: "Protocols", value: "12"), .init(label: "Backtested APY", value: "~18%"), .init(label: "Language", value: "Python")]
        ),
        MarketplaceItem(
            name: "Carbon Credit Bundle",
            description_: "1000 verified carbon credits from reforestation projects in Brazil. Each credit offsets 1 tonne of CO2. Gold Standard certified.",
            priceValue: 15000, category: .property, sellerName: "GreenBlock", sellerRating: 4.5,
            gradientColors: [.green, .teal], viewCount: 890, listedDate: Date().addingTimeInterval(-604800),
            specifications: [.init(label: "Credits", value: "1,000"), .init(label: "Standard", value: "Gold Standard"), .init(label: "Origin", value: "Brazil")]
        ),
        MarketplaceItem(
            name: "Web3 UX Consultation",
            description_: "1-on-1 UX design consultation for DeFi and Web3 applications. Includes wireframes, user flow analysis, and accessibility review.",
            priceValue: 350, category: .services, sellerName: "PixelDAO", sellerRating: 4.8,
            gradientColors: [.indigo, .purple], viewCount: 423, listedDate: Date().addingTimeInterval(-129600),
            specifications: [.init(label: "Duration", value: "2 hours"), .init(label: "Deliverables", value: "Wireframes"), .init(label: "Follow-up", value: "Included")]
        ),
    ]
}

// MARK: - Marketplace View

struct MarketplaceView: View {
    @StateObject private var viewModel = MarketplaceViewModel()
    @State private var appeared = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: Spacing.ms),
        GridItem(.flexible(), spacing: Spacing.ms)
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                if viewModel.isLoading && viewModel.listings.isEmpty {
                    shimmerGrid
                } else if viewModel.filteredListings.isEmpty && !viewModel.searchText.isEmpty {
                    MtrxEmptyState(
                        icon: Symbols.search,
                        title: "No Results",
                        message: "No listings match \"\(viewModel.searchText)\". Try a different search term.",
                        actionLabel: "Clear Search"
                    ) {
                        viewModel.searchText = ""
                    }
                } else if viewModel.filteredListings.isEmpty {
                    MtrxEmptyState(
                        icon: Symbols.marketplace,
                        title: "No Listings",
                        message: "The marketplace is empty right now. Check back soon for new listings.",
                        actionLabel: "Refresh"
                    ) {
                        Task { await viewModel.refresh() }
                    }
                } else {
                    listingContent
                }
            }
            .navigationTitle("Marketplace")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showSortPicker) {
                sortPickerSheet
                    .presentationDetents([.height(320)])
            }
            .sheet(isPresented: $viewModel.showDetail) {
                if let listing = viewModel.selectedListing {
                    MarketplaceDetailSheet(listing: listing)
                        .presentationDetents([.large])
                }
            }
            .task {
                guard !appeared else { return }
                appeared = true
                await viewModel.loadListings()
            }
        }
    }

    // MARK: - Content

    private var listingContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                searchAndSort
                categoryFilters
                listingGrid
            }
            .padding(.bottom, Spacing.xxl)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Search + Sort

    private var searchAndSort: some View {
        HStack(spacing: Spacing.sm) {
            MtrxSearchBar(text: $viewModel.searchText, placeholder: "Search marketplace...")

            Button {
                viewModel.showSortPicker = true
                MtrxHaptics.impact(.light)
            } label: {
                Image(systemName: Symbols.sort)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Category Filters

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(MarketCategory.allCases) { category in
                    MtrxChip(
                        label: category.rawValue,
                        icon: category == viewModel.selectedCategory ? category.icon : nil,
                        isSelected: category == viewModel.selectedCategory
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

    // MARK: - Listing Grid

    private var listingGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: Spacing.ms) {
            ForEach(Array(viewModel.filteredListings.enumerated()), id: \.element.id) { index, item in
                MarketplaceGridCard(listing: item)
                    .onTapGesture {
                        viewModel.selectListing(item)
                    }
                    .mtrxStaggeredAppearance(index: index, isVisible: appeared)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Shimmer Loading

    private var shimmerGrid: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Fake search bar
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm)
                    .fill(Color.surfaceOverlay)
                    .frame(height: 40)
                    .padding(.horizontal, Spacing.contentPadding)
                    .mtrxShimmer(isActive: true)

                // Fake chips
                HStack(spacing: Spacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule()
                            .fill(Color.surfaceOverlay)
                            .frame(width: 70, height: 30)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.contentPadding)
                .mtrxShimmer(isActive: true)

                // Fake grid
                LazyVGrid(columns: gridColumns, spacing: Spacing.ms) {
                    ForEach(0..<6, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm)
                                .fill(Color.surfaceOverlay)
                                .frame(height: 120)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.surfaceOverlay)
                                .frame(width: 100, height: 14)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.surfaceOverlay)
                                .frame(width: 60, height: 12)

                            HStack {
                                Circle().fill(Color.surfaceOverlay).frame(width: 20, height: 20)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.surfaceOverlay)
                                    .frame(width: 50, height: 10)
                            }
                        }
                        .mtrxCardStyle()
                        .mtrxShimmer(isActive: true)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Sort Picker Sheet

    private var sortPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MtrxSheetHeader(title: "Sort By", subtitle: "Choose listing order")

                VStack(spacing: Spacing.xs) {
                    ForEach(MarketSortOption.allCases) { option in
                        Button {
                            withAnimation(Motion.springSnappy) {
                                viewModel.sortOption = option
                            }
                            MtrxHaptics.selection()
                            viewModel.showSortPicker = false
                        } label: {
                            HStack(spacing: Spacing.ms) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(viewModel.sortOption == option ? Color.accentPrimary : Color.labelSecondary)
                                    .frame(width: 24)

                                Text(option.rawValue)
                                    .font(.mtrxBody)
                                    .foregroundStyle(Color.labelPrimary)

                                Spacer()

                                if viewModel.sortOption == option {
                                    Image(systemName: Symbols.complete)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.accentPrimary)
                                }
                            }
                            .padding(.vertical, Spacing.ms)
                            .padding(.horizontal, Spacing.contentPadding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if option != MarketSortOption.allCases.last {
                            MtrxDivider()
                                .padding(.leading, Spacing.xxl)
                        }
                    }
                }
                .padding(.top, Spacing.sm)

                Spacer()
            }
            .background(Color.backgroundPrimary)
        }
    }
}

// MARK: - Grid Card

struct MarketplaceGridCard: View {
    let listing: MarketplaceItem

    var body: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Gradient placeholder image
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: listing.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: listing.category.icon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    )
                    .overlay(alignment: .topTrailing) {
                        MtrxBadge(text: listing.category.rawValue, style: listing.categoryBadgeStyle)
                            .padding(Spacing.xs)
                    }

                // Name
                Text(listing.name)
                    .font(.mtrxCalloutBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Price
                Text(listing.formattedPrice)
                    .font(.mtrxMono)
                    .foregroundStyle(Color.accentPrimary)

                // Seller
                HStack(spacing: Spacing.xs) {
                    MtrxAvatar(
                        text: listing.sellerName,
                        color: listing.gradientColors.first ?? .accentPrimary,
                        size: 20
                    )

                    Text(listing.sellerName)
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                }

                // View button
                Button {} label: {
                    Text("View")
                }
                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact, fullWidth: true))
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Detail Sheet

struct MarketplaceDetailSheet: View {
    let listing: MarketplaceItem
    @Environment(\.dismiss) private var dismiss
    @State private var showOfferInput = false
    @State private var offerAmount: String = ""
    @State private var isBuying = false

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                        // Large image area
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: listing.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 240)
                            .overlay(
                                Image(systemName: listing.category.icon)
                                    .font(.system(size: 56, weight: .light))
                                    .foregroundStyle(.white.opacity(0.6))
                            )
                            .overlay(alignment: .topTrailing) {
                                MtrxBadge(text: listing.category.rawValue, style: listing.categoryBadgeStyle)
                                    .padding(Spacing.ms)
                            }

                        // Title + price
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(listing.name)
                                .font(.mtrxTitle2)
                                .foregroundStyle(Color.labelPrimary)

                            Text(listing.formattedPrice)
                                .font(.mtrxMonoMedium)
                                .foregroundStyle(Color.accentPrimary)
                                .mtrxGlow(color: .accentPrimary, radius: 4)
                        }

                        // Description
                        MtrxCard(style: .standard) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                MtrxSectionHeader(title: "Description")

                                Text(listing.description_)
                                    .font(.mtrxBody)
                                    .foregroundStyle(Color.labelSecondary)
                                    .lineSpacing(4)
                            }
                        }

                        // Seller info
                        MtrxCard(style: .standard) {
                            HStack(spacing: Spacing.ms) {
                                MtrxAvatar(
                                    text: listing.sellerName,
                                    color: listing.gradientColors.first ?? .accentPrimary,
                                    size: Spacing.Size.avatarMedium
                                )

                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(listing.sellerName)
                                        .font(.mtrxHeadline)
                                        .foregroundStyle(Color.labelPrimary)

                                    HStack(spacing: Spacing.xs) {
                                        ForEach(0..<5, id: \.self) { i in
                                            Image(systemName: Double(i) < listing.sellerRating ? "star.fill" : "star")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Double(i) < listing.sellerRating ? Color.accentTertiary : Color.labelTertiary)
                                        }
                                        Text(String(format: "%.1f", listing.sellerRating))
                                            .font(.mtrxCaptionBold)
                                            .foregroundStyle(Color.labelSecondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: Symbols.verified)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.accentPrimary)
                            }
                        }

                        // Specifications
                        if !listing.specifications.isEmpty {
                            MtrxCard(style: .standard) {
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    MtrxSectionHeader(title: "Specifications")

                                    ForEach(listing.specifications) { spec in
                                        HStack {
                                            Text(spec.label)
                                                .font(.mtrxCallout)
                                                .foregroundStyle(Color.labelSecondary)
                                            Spacer()
                                            Text(spec.value)
                                                .font(.mtrxMono)
                                                .foregroundStyle(Color.labelPrimary)
                                        }

                                        if spec.id != listing.specifications.last?.id {
                                            MtrxDivider()
                                        }
                                    }
                                }
                            }
                        }

                        // Offer input
                        if showOfferInput {
                            MtrxCard(style: .elevated, accentEdge: .leading) {
                                VStack(alignment: .leading, spacing: Spacing.ms) {
                                    Text("Your Offer")
                                        .font(.mtrxHeadline)
                                        .foregroundStyle(Color.labelPrimary)

                                    MtrxTextField(
                                        placeholder: "Enter amount (USD)",
                                        text: $offerAmount,
                                        icon: "dollarsign.circle",
                                        keyboardType: .decimalPad
                                    )

                                    Button {
                                        MtrxHaptics.success()
                                        showOfferInput = false
                                        offerAmount = ""
                                    } label: {
                                        Text("Submit Offer")
                                    }
                                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
                                    .disabled(offerAmount.isEmpty)
                                }
                            }
                        }

                        Spacer().frame(height: Spacing.xxxl)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                }

                // Bottom action buttons
                VStack {
                    Spacer()

                    HStack(spacing: Spacing.ms) {
                        Button {
                            withAnimation(Motion.springDefault) {
                                showOfferInput.toggle()
                            }
                            MtrxHaptics.impact(.medium)
                        } label: {
                            Text("Make Offer")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .large))

                        Button {
                            isBuying = true
                            MtrxHaptics.success()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isBuying = false
                            }
                        } label: {
                            Text("Buy Now")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: isBuying, fullWidth: true))
                        .disabled(isBuying)
                    }
                    .padding(Spacing.contentPadding)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: Symbols.close)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MarketplaceView()
        .preferredColorScheme(.dark)
}
