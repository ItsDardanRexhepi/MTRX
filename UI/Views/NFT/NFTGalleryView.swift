// NFTGalleryView.swift
// MTRX
//
// NFT gallery — grid display with collection filter, pull-to-refresh, and navigation to detail.

import SwiftUI

// MARK: - NFT Display Item

struct NFTDisplayItem: Identifiable, Hashable {
    let id: String
    let tokenId: String
    let contract: String
    let name: String
    let collectionName: String
    let imageURL: String?
    let floorPrice: Double?
    let description: String
    let traits: [NFTTrait]

    init(
        id: String = UUID().uuidString,
        tokenId: String,
        contract: String,
        name: String,
        collectionName: String,
        imageURL: String? = nil,
        floorPrice: Double? = nil,
        description: String = "",
        traits: [NFTTrait] = []
    ) {
        self.id = id
        self.tokenId = tokenId
        self.contract = contract
        self.name = name
        self.collectionName = collectionName
        self.imageURL = imageURL
        self.floorPrice = floorPrice
        self.description = description
        self.traits = traits
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: NFTDisplayItem, rhs: NFTDisplayItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - NFT Trait

struct NFTTrait: Identifiable, Hashable {
    let id: String
    let traitType: String
    let value: String

    init(id: String = UUID().uuidString, traitType: String, value: String) {
        self.id = id
        self.traitType = traitType
        self.value = value
    }
}

// MARK: - View Model

@MainActor
class NFTGalleryViewModel: ObservableObject {
    @Published var nfts: [NFTDisplayItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedCollection: String?
    @Published var isDemo: Bool = false

    var collectionNames: [String] {
        let names = Set(nfts.map(\.collectionName))
        return Array(names).sorted()
    }

    var filteredNFTs: [NFTDisplayItem] {
        guard let selected = selectedCollection else { return nfts }
        return nfts.filter { $0.collectionName == selected }
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live NFTs from NFTService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                let live = try await NFTService.shared.getUserNFTs(address: address)
                nfts = live.map { n in
                    NFTDisplayItem(
                        tokenId: n.tokenId,
                        contract: n.contract,
                        name: n.name,
                        collectionName: n.collectionName,
                        imageURL: n.imageURL,
                        floorPrice: n.floorPrice,
                        description: n.description,
                        traits: n.traits.map { NFTTrait(traitType: $0.traitType, value: $0.value) }
                    )
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live NFTs unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(800))
            nfts = NFTGalleryViewModel.sampleNFTs
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load your NFTs. Please try again."
            isLoading = false
        }
    }

    func refresh() async {
        errorMessage = nil
        do {
            try await Task.sleep(for: .milliseconds(600))
            nfts = NFTGalleryViewModel.sampleNFTs
        } catch {
            errorMessage = "Refresh failed. Please try again."
        }
    }

    static let sampleNFTs: [NFTDisplayItem] = [
        NFTDisplayItem(
            tokenId: "1042",
            contract: "0xBC4C...A3f2",
            name: "Genesis Architect #1042",
            collectionName: "Genesis Architects",
            imageURL: nil,
            floorPrice: 0.85,
            description: "A founding architect of the MTRX network. Holders govern protocol upgrades.",
            traits: [
                NFTTrait(traitType: "Background", value: "Void Black"),
                NFTTrait(traitType: "Body", value: "Chrome"),
                NFTTrait(traitType: "Eyes", value: "Terminal Green"),
                NFTTrait(traitType: "Accessory", value: "Data Visor")
            ]
        ),
        NFTDisplayItem(
            tokenId: "7",
            contract: "0xD1E5...9c4B",
            name: "Base Onchain Summer #7",
            collectionName: "Onchain Summer",
            imageURL: nil,
            floorPrice: 0.12,
            description: "Commemorative NFT for Base network launch participants.",
            traits: [
                NFTTrait(traitType: "Season", value: "Summer 2024"),
                NFTTrait(traitType: "Rarity", value: "Uncommon")
            ]
        ),
        NFTDisplayItem(
            tokenId: "389",
            contract: "0xBC4C...A3f2",
            name: "Genesis Architect #389",
            collectionName: "Genesis Architects",
            imageURL: nil,
            floorPrice: 0.85,
            description: "A founding architect of the MTRX network.",
            traits: [
                NFTTrait(traitType: "Background", value: "Deep Blue"),
                NFTTrait(traitType: "Body", value: "Matte Black"),
                NFTTrait(traitType: "Eyes", value: "Amber"),
                NFTTrait(traitType: "Accessory", value: "None")
            ]
        ),
        NFTDisplayItem(
            tokenId: "55",
            contract: "0xF2A8...1dC3",
            name: "Matrix Realm #55",
            collectionName: "Matrix Realms",
            imageURL: nil,
            floorPrice: 2.4,
            description: "Virtual land parcel in the Matrix Realms metaverse.",
            traits: [
                NFTTrait(traitType: "Zone", value: "Central Hub"),
                NFTTrait(traitType: "Size", value: "Medium"),
                NFTTrait(traitType: "Terrain", value: "Crystal")
            ]
        )
    ]
}

// MARK: - NFT Gallery View

struct NFTGalleryView: View {
    @StateObject private var viewModel = NFTGalleryViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.nfts.isEmpty {
                    loadingGrid
                } else if let error = viewModel.errorMessage, viewModel.nfts.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else if viewModel.filteredNFTs.isEmpty && viewModel.nfts.isEmpty {
                    emptyState
                } else {
                    nftContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("NFT Gallery")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - NFT Content

    private var nftContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                collectionFilter
                if viewModel.filteredNFTs.isEmpty {
                    MtrxEmptyState(
                        icon: Symbols.nft,
                        title: "No NFTs in this collection",
                        message: "Try selecting a different collection filter."
                    )
                    .frame(minHeight: 300)
                } else {
                    nftGrid
                }
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Collection Filter

    private var collectionFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                MtrxChip(
                    label: "All",
                    isSelected: viewModel.selectedCollection == nil
                ) {
                    MtrxHaptics.selection()
                    withAnimation(Motion.springSnappy) {
                        viewModel.selectedCollection = nil
                    }
                }

                ForEach(viewModel.collectionNames, id: \.self) { name in
                    MtrxChip(
                        label: name,
                        isSelected: viewModel.selectedCollection == name
                    ) {
                        MtrxHaptics.selection()
                        withAnimation(Motion.springSnappy) {
                            viewModel.selectedCollection = name
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - NFT Grid

    private var nftGrid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.md) {
            ForEach(viewModel.filteredNFTs) { nft in
                NavigationLink(value: nft) {
                    NFTGridCell(nft: nft)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .navigationDestination(for: NFTDisplayItem.self) { nft in
            NFTDetailView(nft: nft)
        }
    }

    // MARK: - Loading Grid

    private var loadingGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(0..<4, id: \.self) { _ in
                    NFTSkeletonCell()
                }
            }
            .padding(Spacing.contentPadding)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        MtrxEmptyState(
            icon: Symbols.nft,
            title: "No NFTs yet",
            message: "Say \"mint an NFT\" or \"buy an NFT\" to Trinity."
        )
    }
}

// MARK: - NFT Grid Cell

struct NFTGridCell: View {
    let nft: NFTDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            nftImage
            nftInfo
        }
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private var nftImage: some View {
        Group {
            if let urlString = nft.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    case .failure:
                        nftPlaceholder
                    case .empty:
                        nftShimmerPlaceholder
                    @unknown default:
                        nftPlaceholder
                    }
                }
            } else {
                nftPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Spacing.CornerRadius.md,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: Spacing.CornerRadius.md,
                style: .continuous
            )
        )
    }

    private var nftPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentPrimary.opacity(0.15), Color.accentSecondary.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: Symbols.nft)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.accentPrimary.opacity(0.5))
        }
    }

    private var nftShimmerPlaceholder: some View {
        Rectangle()
            .fill(Color.surfaceOverlay)
            .mtrxShimmer(isActive: true)
    }

    private var nftInfo: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(nft.name)
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(nft.collectionName)
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let floor = nft.floorPrice {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.accentPrimary)
                    Text(String(format: "%.2f ETH", floor))
                        .font(.mtrxMonoTiny)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }
}

// MARK: - Skeleton Cell

struct NFTSkeletonCell: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Rectangle()
                .fill(Color.surfaceOverlay)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Spacing.CornerRadius.md,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: Spacing.CornerRadius.md,
                        style: .continuous
                    )
                )
                .mtrxShimmer(isActive: true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.surfaceOverlay)
                    .frame(height: 12)
                    .mtrxShimmer(isActive: true)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.surfaceOverlay)
                    .frame(width: 80, height: 10)
                    .mtrxShimmer(isActive: true)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.sm)
        }
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    NFTGalleryView()
        .preferredColorScheme(.dark)
}
