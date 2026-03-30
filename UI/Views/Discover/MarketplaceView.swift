// MarketplaceView.swift
// MTRX
//
// Component 24 — Decentralized marketplace listings with search, filters, and categories.

import SwiftUI

// MARK: - Marketplace View

struct MarketplaceView: View {
    @State private var searchText: String = ""
    @State private var selectedFilter: MarketplaceFilter = .all
    @State private var sortOrder: MarketplaceSortOrder = .trending
    @State private var listings: [MarketplaceListing] = MarketplaceListing.sampleData
    @State private var viewMode: MarketplaceViewMode = .list
    @State private var showFilters: Bool = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            sortAndViewControls

            Group {
                switch viewMode {
                case .list:
                    listLayout
                case .grid:
                    gridLayout
                }
            }
        }
        .navigationTitle("Marketplace")
        .searchable(text: $searchText, prompt: "Search listings...")
        .sheet(isPresented: $showFilters) {
            MarketplaceFilterSheet(selectedFilter: $selectedFilter)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(MarketplaceFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(Motion.springSnappy) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.mtrxCaptionBold)
                            .padding(.horizontal, Spacing.chipHorizontal)
                            .padding(.vertical, Spacing.chipVertical)
                            .background(selectedFilter == filter ? Color.accentPrimary : Color.surfaceOverlay)
                            .foregroundStyle(selectedFilter == filter ? .white : Color.labelPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Sort & View Controls

    private var sortAndViewControls: some View {
        HStack {
            Menu {
                ForEach(MarketplaceSortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        Label(order.rawValue, systemImage: order == sortOrder ? Symbols.complete : "")
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: Symbols.sort)
                    Text(sortOrder.rawValue)
                        .font(.mtrxCaption1)
                }
                .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            Text("\(listings.count) listings")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelTertiary)

            Spacer()

            HStack(spacing: Spacing.xs) {
                Button {
                    withAnimation { viewMode = .list }
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(viewMode == .list ? Color.accentPrimary : Color.labelTertiary)
                }

                Button {
                    withAnimation { viewMode = .grid }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(viewMode == .grid ? Color.accentPrimary : Color.labelTertiary)
                }
            }

            Button {
                showFilters = true
            } label: {
                Image(systemName: Symbols.filter)
                    .foregroundStyle(Color.accentPrimary)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - List Layout

    private var listLayout: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(filteredListings) { listing in
                    NavigationLink {
                        MarketplaceListingDetail(listing: listing)
                    } label: {
                        MarketplaceListingRow(listing: listing)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.contentPadding)
        }
    }

    // MARK: - Grid Layout

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Spacing.md) {
                ForEach(filteredListings) { listing in
                    NavigationLink {
                        MarketplaceListingDetail(listing: listing)
                    } label: {
                        MarketplaceGridCard(listing: listing)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.contentPadding)
        }
    }

    // MARK: - Filtered Listings

    private var filteredListings: [MarketplaceListing] {
        var result = listings
        if selectedFilter != .all {
            result = result.filter { $0.category == selectedFilter.rawValue }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }
}

// MARK: - Grid Card

struct MarketplaceGridCard: View {
    let listing: MarketplaceListing

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                .fill(Color.accentPrimary.opacity(0.1))
                .frame(height: 120)
                .overlay(
                    Image(systemName: listing.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentPrimary)
                )

            Text(listing.name)
                .font(.mtrxBodyBold)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)

            Text(listing.category)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)

            HStack {
                Text(listing.price)
                    .font(.mtrxHeadlineTabular)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Text(listing.volume)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .padding(Spacing.cardPadding)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Filter Sheet

struct MarketplaceFilterSheet: View {
    @Binding var selectedFilter: MarketplaceFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Category") {
                    ForEach(MarketplaceFilter.allCases, id: \.self) { filter in
                        Button {
                            selectedFilter = filter
                            dismiss()
                        } label: {
                            HStack {
                                Text(filter.rawValue)
                                Spacer()
                                if selectedFilter == filter {
                                    Image(systemName: Symbols.complete)
                                        .foregroundStyle(Color.accentPrimary)
                                }
                            }
                        }
                        .foregroundStyle(Color.labelPrimary)
                    }
                }

                Section("Price Range") {
                    Text("Min - Max (coming soon)")
                        .foregroundStyle(Color.labelTertiary)
                }

                Section("Verified Only") {
                    Toggle("Show verified only", isOn: .constant(false))
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Enums

enum MarketplaceFilter: String, CaseIterable {
    case all = "All"
    case defi = "DeFi"
    case nft = "NFTs"
    case rwa = "RWA"
    case insurance = "Insurance"
    case services = "Services"
}

enum MarketplaceSortOrder: String, CaseIterable {
    case trending = "Trending"
    case newest = "Newest"
    case priceHigh = "Price: High"
    case priceLow = "Price: Low"
    case volume = "Volume"
}

enum MarketplaceViewMode {
    case list, grid
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MarketplaceView()
    }
}
