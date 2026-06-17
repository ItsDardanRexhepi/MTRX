// RWAView.swift
// MTRX
//
// Real World Assets — category filtering, asset cards with APY/risk, holdings section, purchase flow.

import SwiftUI

// MARK: - Data Models

struct RWAItem: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let apy: String
    let minInvestment: String
    let riskRating: String
}

struct RWAHoldingItem: Identifiable {
    let id = UUID()
    let assetName: String
    let tokenBalance: String
    let usdValue: String
    let pendingYield: String
}

// MARK: - View Model

@MainActor
class RWAViewModel: ObservableObject {
    @Published var assets: [RWAItem] = []
    @Published var holdings: [RWAHoldingItem] = []
    @Published var selectedCategory: String = "All"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let categories = ["All", "Real Estate", "Treasury Bonds", "Commodities", "Private Credit"]

    var filteredAssets: [RWAItem] {
        if selectedCategory == "All" {
            return assets
        }
        return assets.filter { $0.category == selectedCategory }
    }

    var totalHoldingsValue: String {
        let total = holdings.compactMap { item -> Double? in
            let cleaned = item.usdValue.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }.reduce(0, +)
        return String(format: "$%,.2f", total)
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live assets from the gateway; fall back to sample data if it isn't up.
        if let live = try? await MTRXAPIClient.shared.rwaAssets(), !live.assets.isEmpty {
            assets = live.assets.map { a in
                RWAItem(name: a.name, category: a.category,
                        apy: a.apy ?? "—", minInvestment: a.minInvestment ?? "—",
                        riskRating: a.riskRating ?? "—")
            }
            holdings = RWAViewModel.sampleHoldings
            isLoading = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(600))
            assets = RWAViewModel.sampleAssets
            holdings = RWAViewModel.sampleHoldings
            isLoading = false
        } catch {
            errorMessage = "Unable to load RWA data."
            isLoading = false
        }
    }

    static let sampleAssets: [RWAItem] = [
        RWAItem(name: "Manhattan Office REIT", category: "Real Estate", apy: "7.2%", minInvestment: "$1,000", riskRating: "Medium"),
        RWAItem(name: "US T-Bill 6M", category: "Treasury Bonds", apy: "5.1%", minInvestment: "$100", riskRating: "Low"),
        RWAItem(name: "Gold Vault Token", category: "Commodities", apy: "2.8%", minInvestment: "$500", riskRating: "Low"),
        RWAItem(name: "Private Credit Fund A", category: "Private Credit", apy: "9.5%", minInvestment: "$5,000", riskRating: "High"),
        RWAItem(name: "Miami Residential Pool", category: "Real Estate", apy: "6.8%", minInvestment: "$2,500", riskRating: "Medium"),
        RWAItem(name: "US T-Bill 3M", category: "Treasury Bonds", apy: "4.9%", minInvestment: "$100", riskRating: "Low"),
        RWAItem(name: "Silver Commodity Token", category: "Commodities", apy: "3.1%", minInvestment: "$250", riskRating: "Low"),
        RWAItem(name: "SME Lending Pool", category: "Private Credit", apy: "11.2%", minInvestment: "$10,000", riskRating: "High")
    ]

    static let sampleHoldings: [RWAHoldingItem] = [
        RWAHoldingItem(assetName: "US T-Bill 6M", tokenBalance: "50.00 TBILL6M", usdValue: "$5,000.00", pendingYield: "$21.25"),
        RWAHoldingItem(assetName: "Manhattan Office REIT", tokenBalance: "10.00 MNHTN", usdValue: "$10,000.00", pendingYield: "$58.33"),
        RWAHoldingItem(assetName: "Gold Vault Token", tokenBalance: "5.00 GVLT", usdValue: "$2,500.00", pendingYield: "$5.83")
    ]
}

// MARK: - RWA View

struct RWAView: View {
    @StateObject private var viewModel = RWAViewModel()

    // MARK: - Body

    var body: some View { _regulatedBody.mvpGated() }

    @ViewBuilder private var _regulatedBody: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.assets.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.assets.isEmpty {
                    errorState(message: error)
                } else {
                    rwaContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Real World Assets")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.load() }
        }
    }

    // MARK: - Content

    private var rwaContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                categoryFilter
                assetsSection
                if !viewModel.holdings.isEmpty {
                    holdingsSection
                }
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(viewModel.categories, id: \.self) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedCategory = category
                        }
                    } label: {
                        Text(category)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(viewModel.selectedCategory == category ? .white : Color.labelSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                viewModel.selectedCategory == category
                                    ? Color(red: 0.0, green: 0.675, blue: 0.694)
                                    : Color.surfaceOverlay
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Assets Section

    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Available Assets")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            if viewModel.filteredAssets.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.labelTertiary)
                    Text("No assets in this category")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.xl)
            } else {
                ForEach(viewModel.filteredAssets) { asset in
                    assetCard(asset)
                }
            }
        }
    }

    private func assetCard(_ asset: RWAItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.name)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(asset.category)
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(asset.apy)
                            .font(.mtrxHeadlineTabular)
                            .foregroundStyle(Color.priceUp)
                        Text("APY")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                HStack {
                    HStack(spacing: Spacing.xs) {
                        Text("Min:")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(asset.minInvestment)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        Text("Risk:")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(asset.riskRating)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(riskColor(asset.riskRating))
                    }
                }

                Button {
                    // Purchase flow
                } label: {
                    Text("Purchase")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color(red: 0.0, green: 0.675, blue: 0.694))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Holdings Section

    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Your Holdings")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Text(viewModel.totalHoldingsValue)
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
            }
            .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.holdings) { holding in
                holdingRow(holding)
            }
        }
    }

    private func holdingRow(_ holding: RWAHoldingItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    Text(holding.assetName)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    Text(holding.usdValue)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Balance")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(holding.tokenBalance)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Pending Yield")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(holding.pendingYield)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.priceUp)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.statusWarning)
            Text(message)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.675, blue: 0.694))
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func riskColor(_ rating: String) -> Color {
        switch rating {
        case "Low": return .statusSuccess
        case "Medium": return .statusWarning
        case "High": return .statusError
        default: return .labelSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    RWAView()
        .preferredColorScheme(.dark)
}
