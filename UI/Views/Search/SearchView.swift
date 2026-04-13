// SearchView.swift
// MTRX
//
// Global search — presented as a sheet with debounced results grouped by type.

import SwiftUI

// MARK: - Search View

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var recentSearches: [String] = ["ETH", "Uniswap", "Escrow Contract"]
    @State private var debouncedText: String = ""
    @State private var searchTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: Spacing.sectionGap) {
                        if debouncedText.isEmpty {
                            recentSearchesSection
                            trendingSection
                        } else if filteredTokens.isEmpty
                                    && filteredContracts.isEmpty
                                    && filteredUsers.isEmpty
                                    && filteredMarketplace.isEmpty {
                            MtrxEmptyState(
                                icon: Symbols.search,
                                title: "No Results",
                                message: "Nothing matched \"\(debouncedText)\". Try a different search term."
                            )
                            .padding(.top, Spacing.xxl)
                        } else {
                            searchResultsContent
                        }
                    }
                    .padding(.vertical, Spacing.md)
                }
            }
            .safeAreaInset(edge: .top) {
                searchHeader
            }
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        debouncedText = newValue
                    }
                }
            }
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.ms) {
                MtrxSearchBar(text: $searchText, placeholder: "Search tokens, contracts, users...")

                Button("Cancel") {
                    dismiss()
                }
                .font(.mtrxCallout)
                .foregroundStyle(Color.accentPrimary)
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)

            MtrxDivider()
        }
    }

    // MARK: - Recent Searches

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Recent", action: {
                withAnimation(Motion.springSnappy) {
                    recentSearches.removeAll()
                }
            }, actionLabel: "Clear All")
            .padding(.horizontal, Spacing.contentPadding)

            if recentSearches.isEmpty {
                Text("No recent searches")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
                    .padding(.horizontal, Spacing.contentPadding)
            } else {
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        searchText = term
                        debouncedText = term
                        MtrxHaptics.selection()
                    } label: {
                        HStack(spacing: Spacing.ms) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.labelTertiary)
                                .frame(width: 24)

                            Text(term)
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelPrimary)

                            Spacer()

                            Button {
                                withAnimation(Motion.springSnappy) {
                                    recentSearches.removeAll { $0 == term }
                                }
                            } label: {
                                Image(systemName: Symbols.close)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.labelTertiary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.surfaceOverlay)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, Spacing.contentPadding)
                        .padding(.vertical, Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Trending

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Trending")
                .padding(.horizontal, Spacing.contentPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(SearchSampleData.trendingTerms, id: \.self) { term in
                        MtrxChip(label: term, icon: Symbols.trendUp) {
                            searchText = term
                            debouncedText = term
                            MtrxHaptics.selection()
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsContent: some View {
        VStack(spacing: Spacing.sectionGap) {
            if !filteredTokens.isEmpty {
                tokenResultsSection
            }
            if !filteredContracts.isEmpty {
                contractResultsSection
            }
            if !filteredUsers.isEmpty {
                userResultsSection
            }
            if !filteredMarketplace.isEmpty {
                marketplaceResultsSection
            }
        }
    }

    // MARK: - Token Results

    private var tokenResultsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Tokens")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(filteredTokens) { token in
                Button {
                    MtrxHaptics.selection()
                    print("Navigate to token: \(token.symbol)")
                } label: {
                    HStack(spacing: Spacing.ms) {
                        MtrxAvatar(text: token.symbol, color: token.iconColor, size: Spacing.Size.avatarSmall)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.name)
                                .font(.mtrxBodyBold)
                                .foregroundStyle(Color.labelPrimary)
                            Text(token.symbol)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f", token.price))
                                .font(.mtrxMono)
                                .foregroundStyle(Color.labelPrimary)
                            HStack(spacing: 3) {
                                Image(systemName: token.change24h >= 0 ? Symbols.trendUp : Symbols.trendDown)
                                    .font(.system(size: 10, weight: .bold))
                                Text(String(format: "%.2f%%", abs(token.change24h)))
                                    .font(.mtrxCaptionBold)
                            }
                            .foregroundStyle(token.change24h >= 0 ? Color.priceUp : Color.priceDown)
                        }

                        Image(systemName: Symbols.forward)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.vertical, Spacing.listRowVertical)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Contract Results

    private var contractResultsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Contracts")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(filteredContracts) { contract in
                Button {
                    MtrxHaptics.selection()
                    print("Navigate to contract: \(contract.name)")
                } label: {
                    HStack(spacing: Spacing.ms) {
                        Image(systemName: contract.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: Spacing.Size.avatarSmall, height: Spacing.Size.avatarSmall)
                            .background(Color.accentPrimary.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(contract.name)
                                .font(.mtrxBodyBold)
                                .foregroundStyle(Color.labelPrimary)
                            HStack(spacing: Spacing.sm) {
                                MtrxBadge(text: contract.type, style: .info)
                                MtrxBadge(text: contract.status, style: contract.statusStyle)
                            }
                        }

                        Spacer()

                        Image(systemName: Symbols.forward)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.vertical, Spacing.listRowVertical)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - User Results

    private var userResultsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Users")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(filteredUsers) { user in
                Button {
                    MtrxHaptics.selection()
                    print("Navigate to user: \(user.displayName)")
                } label: {
                    HStack(spacing: Spacing.ms) {
                        MtrxAvatar(text: user.displayName, color: user.avatarColor, size: Spacing.Size.avatarSmall)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.mtrxBodyBold)
                                .foregroundStyle(Color.labelPrimary)
                            Text(user.address)
                                .font(.mtrxMonoSmall)
                                .foregroundStyle(Color.labelSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: Symbols.forward)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.vertical, Spacing.listRowVertical)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Marketplace Results

    private var marketplaceResultsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Marketplace")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(filteredMarketplace) { item in
                Button {
                    MtrxHaptics.selection()
                    print("Navigate to marketplace item: \(item.name)")
                } label: {
                    HStack(spacing: Spacing.ms) {
                        Image(systemName: Symbols.marketplace)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.accentTertiary)
                            .frame(width: Spacing.Size.avatarSmall, height: Spacing.Size.avatarSmall)
                            .background(Color.accentTertiary.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.mtrxBodyBold)
                                .foregroundStyle(Color.labelPrimary)
                            Text(item.category)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }

                        Spacer()

                        Text(item.price)
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)

                        Image(systemName: Symbols.forward)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.vertical, Spacing.listRowVertical)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Filtered Results

    private var filteredTokens: [SearchTokenResult] {
        SearchSampleData.tokens.filter {
            $0.name.localizedCaseInsensitiveContains(debouncedText) ||
            $0.symbol.localizedCaseInsensitiveContains(debouncedText)
        }
    }

    private var filteredContracts: [SearchContractResult] {
        SearchSampleData.contracts.filter {
            $0.name.localizedCaseInsensitiveContains(debouncedText) ||
            $0.type.localizedCaseInsensitiveContains(debouncedText)
        }
    }

    private var filteredUsers: [SearchUserResult] {
        SearchSampleData.users.filter {
            $0.displayName.localizedCaseInsensitiveContains(debouncedText) ||
            $0.address.localizedCaseInsensitiveContains(debouncedText)
        }
    }

    private var filteredMarketplace: [SearchMarketplaceResult] {
        SearchSampleData.marketplace.filter {
            $0.name.localizedCaseInsensitiveContains(debouncedText) ||
            $0.category.localizedCaseInsensitiveContains(debouncedText)
        }
    }
}

// MARK: - Search Result Models

private struct SearchTokenResult: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let price: Double
    let change24h: Double
    let iconColor: Color
}

private struct SearchContractResult: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let type: String
    let status: String
    let statusStyle: MtrxBadge.BadgeStyle
}

private struct SearchUserResult: Identifiable {
    let id = UUID()
    let displayName: String
    let address: String
    let avatarColor: Color
}

private struct SearchMarketplaceResult: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let price: String
}

// MARK: - Sample Data

private enum SearchSampleData {

    static let trendingTerms: [String] = [
        "DeFi Lending",
        "NFT Marketplace",
        "DAO Governance",
        "Staking",
        "Insurance"
    ]

    static let tokens: [SearchTokenResult] = [
        SearchTokenResult(symbol: "ETH", name: "Ethereum", price: 3245.67, change24h: 3.12, iconColor: .blue),
        SearchTokenResult(symbol: "BTC", name: "Bitcoin", price: 67890.12, change24h: -1.23, iconColor: .orange),
        SearchTokenResult(symbol: "MTRX", name: "Matrix Token", price: 0.0234, change24h: 12.45, iconColor: .accentPrimary),
        SearchTokenResult(symbol: "UNI", name: "Uniswap", price: 7.82, change24h: -0.45, iconColor: .pink),
        SearchTokenResult(symbol: "LINK", name: "Chainlink", price: 14.56, change24h: 5.67, iconColor: .blue),
        SearchTokenResult(symbol: "AAVE", name: "Aave", price: 92.30, change24h: 1.89, iconColor: .purple)
    ]

    static let contracts: [SearchContractResult] = [
        SearchContractResult(name: "Escrow Agreement", icon: Symbols.escrow, type: "Escrow", status: "Active", statusStyle: .success),
        SearchContractResult(name: "Token Vesting", icon: Symbols.stake, type: "Vesting", status: "Pending", statusStyle: .warning),
        SearchContractResult(name: "DAO Treasury", icon: Symbols.dao, type: "Governance", status: "Active", statusStyle: .success),
        SearchContractResult(name: "Insurance Pool", icon: Symbols.insurance, type: "Insurance", status: "Deployed", statusStyle: .accent)
    ]

    static let users: [SearchUserResult] = [
        SearchUserResult(displayName: "Alice Chen", address: "0x1a2b...3c4d5e6f", avatarColor: .accentPrimary),
        SearchUserResult(displayName: "Bob Martinez", address: "0x9f8e...7d6c5b4a", avatarColor: .statusInfo),
        SearchUserResult(displayName: "Carol Wright", address: "0x4d5e...6f7a8b9c", avatarColor: .purple),
        SearchUserResult(displayName: "Dave Kumar", address: "0x2c3d...4e5f6a7b", avatarColor: .orange)
    ]

    static let marketplace: [SearchMarketplaceResult] = [
        SearchMarketplaceResult(name: "Genesis Pass #42", category: "NFT Collection", price: "0.85 ETH"),
        SearchMarketplaceResult(name: "DeFi Strategy Bot", category: "Tools", price: "49.99 USDC"),
        SearchMarketplaceResult(name: "Smart Contract Audit", category: "Services", price: "500 USDC"),
        SearchMarketplaceResult(name: "Governance Template", category: "Templates", price: "Free")
    ]
}

// MARK: - Preview

#Preview {
    SearchView()
        .preferredColorScheme(.dark)
}
