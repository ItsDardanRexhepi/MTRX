// NFTDetailView.swift
// MTRX
//
// NFT detail page — full image, metadata, traits grid, and action buttons.

import SwiftUI

// MARK: - View Model

@MainActor
class NFTDetailViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var actionInProgress: String?
    @Published var actionUnavailable: String?

    let nft: NFTDisplayItem

    init(nft: NFTDisplayItem) {
        self.nft = nft
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            try await Task.sleep(for: .milliseconds(400))
            isLoading = false
        } catch {
            errorMessage = "Unable to load NFT details."
            isLoading = false
        }
    }

    func listForSale() async {
        // Honest failure: no real marketplace-listing path is wired. Do NOT silently
        // clear the spinner and pretend it worked — nothing was listed.
        actionInProgress = nil
        actionUnavailable = "Listing isn't available in this build yet. Nothing was listed."
    }

    func transfer() async {
        // Honest failure: no real on-chain NFT transfer path is wired. Do NOT silently
        // clear the spinner and pretend it worked — nothing was transferred.
        actionInProgress = nil
        actionUnavailable = "NFT transfer isn't available in this build yet. Nothing was transferred."
    }

    func makeOffer() async {
        // Honest failure: no real offer path is wired. Do NOT silently clear the spinner
        // and pretend it worked — no offer was made.
        actionInProgress = nil
        actionUnavailable = "Making an offer isn't available in this build yet. No offer was made."
    }
}

// MARK: - NFT Detail View

struct NFTDetailView: View {
    let nft: NFTDisplayItem
    @StateObject private var viewModel: NFTDetailViewModel

    init(nft: NFTDisplayItem) {
        self.nft = nft
        self._viewModel = StateObject(wrappedValue: NFTDetailViewModel(nft: nft))
    }

    private let traitsColumns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                MtrxErrorView(message: error) {
                    Task { await viewModel.load() }
                }
            } else {
                detailContent
            }
        }
        .background(MtrxGradientBackground(style: .primary))
        .navigationTitle(nft.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("Not Available Yet", isPresented: Binding(
            get: { viewModel.actionUnavailable != nil },
            set: { if !$0 { viewModel.actionUnavailable = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.actionUnavailable = nil }
        } message: {
            Text(viewModel.actionUnavailable ?? "")
        }
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                nftImageSection
                infoSection
                if nft.floorPrice != nil {
                    floorPriceSection
                }
                if !nft.traits.isEmpty {
                    traitsSection
                }
                actionsSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
    }

    // MARK: - Image Section

    private var nftImageSection: some View {
        Group {
            if let urlString = nft.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        imagePlaceholder
                    case .empty:
                        imagePlaceholder
                            .mtrxShimmer(isActive: true)
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
        .padding(.horizontal, Spacing.contentPadding)
    }

    private var imagePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentPrimary.opacity(0.2), Color.accentSecondary.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: Spacing.sm) {
                Image(systemName: Symbols.nft)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.accentPrimary.opacity(0.5))
                Text(nft.name)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(nft.collectionName)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.accentPrimary)

                    Text(nft.name)
                        .font(.mtrxTitle2)
                        .foregroundStyle(Color.labelPrimary)
                }

                MtrxDivider()

                detailRow(label: "Token ID", value: "#\(nft.tokenId)")
                detailRow(label: "Contract", value: truncatedContract)

                if !nft.description.isEmpty {
                    MtrxDivider()
                    Text(nft.description)
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Floor Price Section

    private var floorPriceSection: some View {
        MtrxCard(style: .standard) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Floor Price")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentPrimary)
                        Text(String(format: "%.2f ETH", nft.floorPrice ?? 0))
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("Estimated Value")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Text(String(format: "$%.2f", (nft.floorPrice ?? 0) * 3200))
                        .font(.mtrxHeadlineTabular)
                        .foregroundStyle(Color.labelPrimary)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Traits Section

    private var traitsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Traits")
                .padding(.horizontal, Spacing.contentPadding)

            LazyVGrid(columns: traitsColumns, spacing: Spacing.sm) {
                ForEach(nft.traits) { trait in
                    traitCell(trait)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    private func traitCell(_ trait: NFTTrait) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(trait.traitType.uppercased())
                .font(.mtrxCaption2)
                .foregroundStyle(Color.accentPrimary)

            Text(trait.value)
                .font(.mtrxCalloutBold)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.ms)
        .background(Color.accentPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                .stroke(Color.accentPrimary.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: Spacing.ms) {
            Button {
                Task { await viewModel.listForSale() }
            } label: {
                Text(viewModel.actionInProgress == "list" ? "Listing..." : "List for Sale")
            }
            .buttonStyle(MtrxButtonStyle(
                variant: .primary,
                size: .large,
                isLoading: viewModel.actionInProgress == "list",
                fullWidth: true
            ))
            .disabled(viewModel.actionInProgress != nil)

            HStack(spacing: Spacing.ms) {
                Button {
                    Task { await viewModel.transfer() }
                } label: {
                    Text(viewModel.actionInProgress == "transfer" ? "Sending..." : "Transfer")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .secondary,
                    size: .regular,
                    isLoading: viewModel.actionInProgress == "transfer",
                    fullWidth: true
                ))
                .disabled(viewModel.actionInProgress != nil)

                Button {
                    Task { await viewModel.makeOffer() }
                } label: {
                    Text(viewModel.actionInProgress == "offer" ? "Offering..." : "Make Offer")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .secondary,
                    size: .regular,
                    isLoading: viewModel.actionInProgress == "offer",
                    fullWidth: true
                ))
                .disabled(viewModel.actionInProgress != nil)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Helpers

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value)
                .font(.mtrxMono)
                .foregroundStyle(Color.labelPrimary)
        }
    }

    private var truncatedContract: String {
        let contract = nft.contract
        if contract.count > 12 {
            let prefix = contract.prefix(6)
            let suffix = contract.suffix(4)
            return "\(prefix)...\(suffix)"
        }
        return contract
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NFTDetailView(nft: NFTGalleryViewModel.sampleNFTs[0])
    }
    .preferredColorScheme(.dark)
}
