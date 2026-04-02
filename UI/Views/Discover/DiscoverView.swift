// DiscoverView.swift
// MTRX
//
// Marketplace partner network and fundraisers discovery hub.

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

    private let api = MTRXAPIClient.shared

    // MARK: - Computed Filters

    var filteredListings: [MarketplaceListing] {
        var result = trendingListings
        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory.rawValue }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var filteredFundraisers: [FundraiserItem] {
        if searchText.isEmpty { return activeFundraisers }
        return activeFundraisers.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Load Data

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        async let listingsTask: () = loadListings()
        async let fundraisersTask: () = loadFundraisers()
        async let partnersTask: () = loadPartners()

        _ = await (listingsTask, fundraisersTask, partnersTask)
        isLoading = false
    }

    func loadListings() async {
        do {
            let raw: [String: AnyCodableValue] = try await api.listMarketplaceListings()
            let items = parseListings(raw)
            trendingListings = items

            // Derive featured items from top listings
            featuredItems = items.prefix(3).enumerated().map { index, listing in
                let badges = ["Trending", "New", "Hot"]
                return FeaturedItem(
                    title: listing.name,
                    subtitle: "\(listing.category) - \(listing.price)",
                    badge: badges[index % badges.count]
                )
            }
            if featuredItems.isEmpty {
                featuredItems = FeaturedItem.sampleData
            }
        } catch {
            if trendingListings.isEmpty {
                trendingListings = MarketplaceListing.sampleData
                featuredItems = FeaturedItem.sampleData
            }
            errorMessage = error.localizedDescription
        }
    }

    func loadFundraisers() async {
        do {
            let raw: [String: AnyCodableValue] = try await api.listCampaigns()
            let items = parseFundraisers(raw)
            activeFundraisers = items
            if activeFundraisers.isEmpty {
                activeFundraisers = FundraiserItem.sampleData
            }
        } catch {
            if activeFundraisers.isEmpty {
                activeFundraisers = FundraiserItem.sampleData
            }
        }
    }

    func loadPartners() async {
        // Partners are currently static; populate from local data
        partners = PartnerItem.sampleData
    }

    // MARK: - Parsers

    private func parseListings(_ raw: [String: AnyCodableValue]) -> [MarketplaceListing] {
        guard case .array(let items) = raw["data"] ?? raw["listings"] ?? .null else {
            return []
        }
        return items.compactMap { item -> MarketplaceListing? in
            guard case .dictionary(let dict) = item else { return nil }
            let name = dict["name"]?.stringValue ?? dict["title"]?.stringValue ?? "Unknown"
            let category = dict["category"]?.stringValue ?? dict["asset_type"]?.stringValue ?? "DeFi"
            let priceVal = dict["price"]?.doubleValue ?? dict["price"]?.intValue.map { Double($0) } ?? 0
            let price = priceVal > 0 ? "$\(String(format: "%.2f", priceVal))" : "$0.00"
            let volumeVal = dict["volume"]?.doubleValue ?? 0
            let volume = volumeVal > 0 ? "\(String(format: "%.1f", volumeVal / 1000))K vol" : "0 vol"
            let icon = iconForCategory(category)
            return MarketplaceListing(name: name, category: category, price: price, volume: volume, icon: icon)
        }
    }

    private func parseFundraisers(_ raw: [String: AnyCodableValue]) -> [FundraiserItem] {
        guard case .array(let items) = raw["data"] ?? raw["campaigns"] ?? .null else {
            return []
        }
        return items.compactMap { item -> FundraiserItem? in
            guard case .dictionary(let dict) = item else { return nil }
            let title = dict["title"]?.stringValue ?? "Campaign"
            let desc = dict["description"]?.stringValue ?? ""
            let goalAmount = dict["goal_amount"]?.doubleValue ?? 100_000
            let raisedAmount = dict["raised_amount"]?.doubleValue ?? dict["current_amount"]?.doubleValue ?? 0
            let progress = goalAmount > 0 ? min(raisedAmount / goalAmount, 1.0) : 0
            let daysLeft = dict["days_remaining"]?.intValue ?? dict["duration_days"]?.intValue ?? 30
            let verified = dict["is_verified"]?.boolValue ?? false
            return FundraiserItem(
                title: title,
                description_: desc,
                progress: progress,
                daysLeft: "\(daysLeft) days left",
                isVerified: verified
            )
        }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "defi": return Symbols.chartLine
        case "nft", "nfts": return Symbols.nft
        case "rwa": return Symbols.property
        case "insurance": return Symbols.insurance
        case "dao", "daos": return Symbols.dao
        default: return Symbols.globe
        }
    }
}

// MARK: - Discover View

struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.trendingListings.isEmpty {
                    loadingState
                } else if let error = viewModel.errorMessage, viewModel.trendingListings.isEmpty {
                    errorState(error)
                } else {
                    contentView
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $viewModel.searchText, prompt: "Search marketplace, fundraisers...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Open filters
                    } label: {
                        Image(systemName: Symbols.filter)
                    }
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
            Text("Loading discoveries...")
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

            Text("Something went wrong")
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

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sectionGap) {
                categoryFilter
                featuredCarousel
                trendingSection
                fundraiserSection
                partnersSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.loadAll()
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(DiscoverCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(Motion.springSnappy) {
                            viewModel.selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: category.icon)
                                .font(.system(size: 12))
                            Text(category.rawValue)
                                .font(.mtrxCaptionBold)
                        }
                        .padding(.horizontal, Spacing.chipHorizontal)
                        .padding(.vertical, Spacing.chipVertical)
                        .background(viewModel.selectedCategory == category ? Color.accentPrimary : Color.surfaceOverlay)
                        .foregroundStyle(viewModel.selectedCategory == category ? .white : Color.labelPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Featured Carousel

    private var featuredCarousel: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Featured")
                .font(.mtrxTitle3)
                .padding(.horizontal, Spacing.contentPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(viewModel.featuredItems) { item in
                        FeaturedCard(item: item)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Trending Section

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("Trending", systemImage: Symbols.trendUp)
                    .font(.mtrxTitle3)
                Spacer()
                NavigationLink {
                    MarketplaceView()
                } label: {
                    Text("See All")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.accentPrimary)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.filteredListings) { listing in
                NavigationLink {
                    MarketplaceListingDetail(listing: listing)
                } label: {
                    MarketplaceListingRow(listing: listing)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Fundraiser Section

    private var fundraiserSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("Active Fundraisers", systemImage: Symbols.fundraiser)
                    .font(.mtrxTitle3)
                Spacer()
                NavigationLink {
                    FundraiserView()
                } label: {
                    Text("See All")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.accentPrimary)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(viewModel.filteredFundraisers) { fundraiser in
                        NavigationLink {
                            FundraiserView()
                        } label: {
                            FundraiserCard(fundraiser: fundraiser)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Partners Section

    private var partnersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Partner Network")
                .font(.mtrxTitle3)
                .padding(.horizontal, Spacing.contentPadding)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Spacing.md) {
                ForEach(viewModel.partners) { partner in
                    PartnerCell(partner: partner)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }
}

// MARK: - Discover Category

enum DiscoverCategory: String, CaseIterable {
    case all = "All"
    case defi = "DeFi"
    case nft = "NFTs"
    case rwa = "RWA"
    case dao = "DAOs"
    case insurance = "Insurance"

    var icon: String {
        switch self {
        case .all: return Symbols.globe
        case .defi: return Symbols.chartLine
        case .nft: return Symbols.nft
        case .rwa: return Symbols.property
        case .dao: return Symbols.dao
        case .insurance: return Symbols.insurance
        }
    }
}

// MARK: - Featured Card

struct FeaturedCard: View {
    let item: FeaturedItem

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                .fill(LinearGradient.mtrxPrimary)
                .frame(width: 280, height: 160)
                .overlay(
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(item.badge)
                            .font(.mtrxCaptionBold)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())

                        Spacer()

                        Text(item.title)
                            .font(.mtrxHeadline)
                            .foregroundStyle(.white)

                        Text(item.subtitle)
                            .font(.mtrxCaption1)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
        }
    }
}

// MARK: - Marketplace Listing Row

struct MarketplaceListingRow: View {
    let listing: MarketplaceListing

    var body: some View {
        HStack(spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                .fill(Color.accentSecondary.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: listing.icon)
                        .foregroundStyle(Color.accentSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(listing.name)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Text(listing.category)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(listing.price)
                    .font(.mtrxBodyTabular)
                    .foregroundStyle(Color.labelPrimary)
                Text(listing.volume)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Fundraiser Card

struct FundraiserCard: View {
    let fundraiser: FundraiserItem

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(fundraiser.title)
                    .font(.mtrxHeadline)
                    .lineLimit(1)
                Spacer()
                Image(systemName: Symbols.verified)
                    .foregroundStyle(Color.accentPrimary)
                    .opacity(fundraiser.isVerified ? 1 : 0)
            }

            Text(fundraiser.description_)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)

            ProgressView(value: fundraiser.progress)
                .tint(Color.accentPrimary)

            HStack {
                Text("\(Int(fundraiser.progress * 100))% funded")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.accentPrimary)
                Spacer()
                Text(fundraiser.daysLeft)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(width: 260)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Partner Cell

struct PartnerCell: View {
    let partner: PartnerItem

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Circle()
                .fill(Color.accentPrimary.opacity(0.1))
                .frame(width: Spacing.Size.avatarLarge, height: Spacing.Size.avatarLarge)
                .overlay(
                    Image(systemName: partner.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentPrimary)
                )

            Text(partner.name)
                .font(.mtrxCaptionBold)
                .lineLimit(1)
        }
    }
}

// MARK: - Placeholder Detail

struct MarketplaceListingDetail: View {
    let listing: MarketplaceListing
    var body: some View {
        Text(listing.name)
            .navigationTitle(listing.name)
    }
}

// MARK: - Data Models

struct FeaturedItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let badge: String

    static let sampleData: [FeaturedItem] = [
        FeaturedItem(title: "Tokenized Real Estate", subtitle: "Invest in fractional property", badge: "New"),
        FeaturedItem(title: "Weather Insurance", subtitle: "Parametric crop protection", badge: "Trending"),
    ]
}

struct MarketplaceListing: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: String
    let price: String
    let volume: String
    let icon: String

    static let sampleData: [MarketplaceListing] = [
        MarketplaceListing(name: "Nairobi Solar Farm", category: "RWA", price: "$50/token", volume: "2.4K vol", icon: Symbols.property),
        MarketplaceListing(name: "DeFi Index Fund", category: "DeFi", price: "$1,240", volume: "12K vol", icon: Symbols.chartPie),
        MarketplaceListing(name: "Carbon Credits", category: "RWA", price: "$12.50", volume: "8.1K vol", icon: Symbols.globe),
    ]
}

struct FundraiserItem: Identifiable {
    let id = UUID()
    let title: String
    let description_: String
    let progress: Double
    let daysLeft: String
    let isVerified: Bool

    static let sampleData: [FundraiserItem] = [
        FundraiserItem(title: "Community Solar", description_: "Solar panel installation for rural communities", progress: 0.72, daysLeft: "12 days left", isVerified: true),
        FundraiserItem(title: "Water Access DAO", description_: "Clean water infrastructure in East Africa", progress: 0.45, daysLeft: "28 days left", isVerified: true),
    ]
}

struct PartnerItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String

    static let sampleData: [PartnerItem] = [
        PartnerItem(name: "Aave", icon: Symbols.stake),
        PartnerItem(name: "Uniswap", icon: Symbols.swap),
        PartnerItem(name: "Chainlink", icon: Symbols.link),
        PartnerItem(name: "XMTP", icon: Symbols.messageEncrypted),
        PartnerItem(name: "Lido", icon: Symbols.escrow),
        PartnerItem(name: "ENS", icon: Symbols.globe),
    ]
}

// MARK: - Preview

#Preview {
    DiscoverView()
}
