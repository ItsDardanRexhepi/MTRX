// DiscoverView.swift
// MTRX
//
// Marketplace partner network and fundraisers discovery hub.

import SwiftUI

// MARK: - Discover View

struct DiscoverView: View {
    @State private var searchText: String = ""
    @State private var selectedCategory: DiscoverCategory = .all
    @State private var featuredItems: [FeaturedItem] = FeaturedItem.sampleData
    @State private var trendingListings: [MarketplaceListing] = MarketplaceListing.sampleData
    @State private var activeFundraisers: [FundraiserItem] = FundraiserItem.sampleData

    // MARK: - Body

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Discover")
            .searchable(text: $searchText, prompt: "Search marketplace, fundraisers...")
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
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(DiscoverCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(Motion.springSnappy) {
                            selectedCategory = category
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
                        .background(selectedCategory == category ? Color.accentPrimary : Color.surfaceOverlay)
                        .foregroundStyle(selectedCategory == category ? .white : Color.labelPrimary)
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
                    ForEach(featuredItems) { item in
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

            ForEach(trendingListings) { listing in
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
                    ForEach(activeFundraisers) { fundraiser in
                        FundraiserCard(fundraiser: fundraiser)
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
                ForEach(PartnerItem.sampleData) { partner in
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
