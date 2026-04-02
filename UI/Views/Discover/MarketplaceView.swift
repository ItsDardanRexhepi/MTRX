// MarketplaceView.swift
// MTRX
//
// Component 24 — Decentralized marketplace listings with search, filters, and categories.

import SwiftUI

// MARK: - Marketplace ViewModel

@MainActor
final class MarketplaceViewModel: ObservableObject {
    @Published var listings: [MarketplaceListing] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: MarketplaceFilter = .all
    @Published var sortOrder: MarketplaceSortOrder = .trending
    @Published var viewMode: MarketplaceViewMode = .list
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showFilters: Bool = false
    @Published var showListItemSheet: Bool = false
    @Published var showPurchaseConfirmation: Bool = false
    @Published var selectedListingForPurchase: MarketplaceListing?
    @Published var isPurchasing: Bool = false
    @Published var currentPage: Int = 1
    @Published var hasMorePages: Bool = true
    @Published var isLoadingMore: Bool = false

    private let api = MTRXAPIClient.shared

    // MARK: - Filtered Listings

    var filteredListings: [MarketplaceListing] {
        var result = listings
        if selectedFilter != .all {
            result = result.filter { $0.category == selectedFilter.rawValue }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    // MARK: - Load

    func loadListings() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let query = searchText.isEmpty ? nil : searchText
            let raw: [String: AnyCodableValue] = try await api.listMarketplaceListings(query: query)
            listings = parseListings(raw)

            // Check for pagination
            if case .dictionary(let meta) = raw["meta"] {
                let total = meta["total"]?.intValue ?? listings.count
                hasMorePages = listings.count < total
            } else {
                hasMorePages = false
            }

            if listings.isEmpty {
                listings = MarketplaceListing.sampleData
            }
        } catch {
            if listings.isEmpty {
                listings = MarketplaceListing.sampleData
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: MarketplaceListing) async {
        guard hasMorePages, !isLoadingMore else { return }
        let thresholdIndex = filteredListings.index(filteredListings.endIndex, offsetBy: -3)
        guard let currentIndex = filteredListings.firstIndex(where: { $0.id == currentItem.id }),
              currentIndex >= thresholdIndex else { return }

        isLoadingMore = true
        currentPage += 1

        do {
            let raw: [String: AnyCodableValue] = try await api.listMarketplaceListings(query: nil)
            let newItems = parseListings(raw)
            listings.append(contentsOf: newItems)
            hasMorePages = !newItems.isEmpty
        } catch {
            hasMorePages = false
        }

        isLoadingMore = false
    }

    // MARK: - Purchase

    func purchaseListing(_ listing: MarketplaceListing) async {
        isPurchasing = true
        do {
            _ = try await api.purchaseListing(id: listing.id.uuidString)
            // Remove purchased listing from the list
            listings.removeAll { $0.id == listing.id }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
        isPurchasing = false
        showPurchaseConfirmation = false
        selectedListingForPurchase = nil
    }

    // MARK: - List Item for Sale

    func createListing(assetType: String, assetId: String, price: Double, currency: String, description: String) async {
        do {
            let request = ListingCreateRequest(
                assetType: assetType,
                assetId: assetId,
                price: price,
                currency: currency,
                description: description
            )
            _ = try await api.createListing(request)
            await loadListings()
        } catch {
            errorMessage = "Failed to list item: \(error.localizedDescription)"
        }
    }

    // MARK: - Parser

    private func parseListings(_ raw: [String: AnyCodableValue]) -> [MarketplaceListing] {
        guard case .array(let items) = raw["data"] ?? raw["listings"] ?? .null else {
            return []
        }
        return items.compactMap { item -> MarketplaceListing? in
            guard case .dictionary(let dict) = item else { return nil }
            let name = dict["name"]?.stringValue ?? dict["title"]?.stringValue ?? "Unknown"
            let category = dict["category"]?.stringValue ?? dict["asset_type"]?.stringValue ?? "DeFi"
            let priceVal = dict["price"]?.doubleValue ?? 0
            let price = priceVal > 0 ? "$\(String(format: "%.2f", priceVal))" : "$0.00"
            let volumeVal = dict["volume"]?.doubleValue ?? 0
            let volume = volumeVal > 0 ? "\(String(format: "%.1f", volumeVal / 1000))K vol" : "0 vol"
            let icon = iconForCategory(category)
            return MarketplaceListing(name: name, category: category, price: price, volume: volume, icon: icon)
        }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "defi": return Symbols.chartLine
        case "nft", "nfts": return Symbols.nft
        case "rwa": return Symbols.property
        case "insurance": return Symbols.insurance
        case "services": return Symbols.contract
        default: return Symbols.globe
        }
    }
}

// MARK: - Marketplace View

struct MarketplaceView: View {
    @StateObject private var viewModel = MarketplaceViewModel()

    private let gridColumns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.listings.isEmpty {
                loadingState
            } else if let error = viewModel.errorMessage, viewModel.listings.isEmpty {
                errorState(error)
            } else {
                filterBar
                sortAndViewControls

                Group {
                    switch viewModel.viewMode {
                    case .list:
                        listLayout
                    case .grid:
                        gridLayout
                    }
                }
            }
        }
        .navigationTitle("Marketplace")
        .searchable(text: $viewModel.searchText, prompt: "Search listings...")
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.loadListings() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showListItemSheet = true
                } label: {
                    Image(systemName: Symbols.addCircle)
                }
            }
        }
        .sheet(isPresented: $viewModel.showFilters) {
            MarketplaceFilterSheet(selectedFilter: $viewModel.selectedFilter)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $viewModel.showListItemSheet) {
            ListItemForSaleSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showPurchaseConfirmation) {
            if let listing = viewModel.selectedListingForPurchase {
                PurchaseConfirmationSheet(listing: listing, viewModel: viewModel)
                    .presentationDetents([.medium])
            }
        }
        .task {
            await viewModel.loadListings()
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .controlSize(.large)
            Text("Loading marketplace...")
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
            Text("Failed to load marketplace")
                .font(.mtrxTitle3)
            Text(message)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadListings() }
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

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(MarketplaceFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(Motion.springSnappy) {
                            viewModel.selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.mtrxCaptionBold)
                            .padding(.horizontal, Spacing.chipHorizontal)
                            .padding(.vertical, Spacing.chipVertical)
                            .background(viewModel.selectedFilter == filter ? Color.accentPrimary : Color.surfaceOverlay)
                            .foregroundStyle(viewModel.selectedFilter == filter ? .white : Color.labelPrimary)
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
                        viewModel.sortOrder = order
                    } label: {
                        Label(order.rawValue, systemImage: order == viewModel.sortOrder ? Symbols.complete : "")
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: Symbols.sort)
                    Text(viewModel.sortOrder.rawValue)
                        .font(.mtrxCaption1)
                }
                .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            Text("\(viewModel.filteredListings.count) listings")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelTertiary)

            Spacer()

            HStack(spacing: Spacing.xs) {
                Button {
                    withAnimation { viewModel.viewMode = .list }
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(viewModel.viewMode == .list ? Color.accentPrimary : Color.labelTertiary)
                }

                Button {
                    withAnimation { viewModel.viewMode = .grid }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(viewModel.viewMode == .grid ? Color.accentPrimary : Color.labelTertiary)
                }
            }

            Button {
                viewModel.showFilters = true
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
                ForEach(viewModel.filteredListings) { listing in
                    NavigationLink {
                        MarketplaceListingDetail(listing: listing)
                    } label: {
                        MarketplaceListingRow(listing: listing)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            viewModel.selectedListingForPurchase = listing
                            viewModel.showPurchaseConfirmation = true
                        } label: {
                            Label("Purchase", systemImage: Symbols.purchase)
                        }
                    }
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: listing)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding()
                }
            }
            .padding(Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.loadListings()
        }
    }

    // MARK: - Grid Layout

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Spacing.md) {
                ForEach(viewModel.filteredListings) { listing in
                    NavigationLink {
                        MarketplaceListingDetail(listing: listing)
                    } label: {
                        MarketplaceGridCard(listing: listing)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            viewModel.selectedListingForPurchase = listing
                            viewModel.showPurchaseConfirmation = true
                        } label: {
                            Label("Purchase", systemImage: Symbols.purchase)
                        }
                    }
                }
            }
            .padding(Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.loadListings()
        }
    }
}

// MARK: - Purchase Confirmation Sheet

struct PurchaseConfirmationSheet: View {
    let listing: MarketplaceListing
    @ObservedObject var viewModel: MarketplaceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Image(systemName: listing.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentPrimary)

                Text("Purchase \(listing.name)?")
                    .font(.mtrxTitle3)
                    .multilineTextAlignment(.center)

                VStack(spacing: Spacing.sm) {
                    HStack {
                        Text("Price")
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text(listing.price)
                            .font(.mtrxMonoMedium)
                    }
                    HStack {
                        Text("Category")
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text(listing.category)
                    }
                    HStack {
                        Text("Est. Gas Fee")
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text("~0.002 ETH")
                            .font(.mtrxMonoSmall)
                    }
                }
                .font(.mtrxBody)
                .padding(Spacing.md)
                .background(Color.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))

                Spacer()

                Button {
                    Task { await viewModel.purchaseListing(listing) }
                } label: {
                    HStack {
                        if viewModel.isPurchasing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Confirm Purchase")
                        }
                    }
                    .font(.mtrxHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Spacing.Size.buttonHeight)
                    .background(Color.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
                .disabled(viewModel.isPurchasing)
            }
            .padding(Spacing.contentPadding)
            .navigationTitle("Confirm Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - List Item For Sale Sheet

struct ListItemForSaleSheet: View {
    @ObservedObject var viewModel: MarketplaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var assetType: String = "NFT"
    @State private var assetId: String = ""
    @State private var price: String = ""
    @State private var currency: String = "USDC"
    @State private var description: String = ""
    @State private var isSubmitting: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Asset") {
                    Picker("Type", selection: $assetType) {
                        ForEach(["NFT", "RWA", "Token", "Service"], id: \.self) { Text($0) }
                    }
                    TextField("Asset ID", text: $assetId)
                        .font(.mtrxMono)
                }

                Section("Pricing") {
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(["USDC", "ETH", "DAI", "USDT"], id: \.self) { Text($0) }
                    }
                }

                Section("Description") {
                    TextField("Describe your listing...", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button {
                        isSubmitting = true
                        Task {
                            let priceValue = Double(price) ?? 0
                            await viewModel.createListing(
                                assetType: assetType,
                                assetId: assetId,
                                price: priceValue,
                                currency: currency,
                                description: description
                            )
                            isSubmitting = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("List for Sale")
                                    .font(.mtrxHeadline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(assetId.isEmpty || price.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("List Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
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
