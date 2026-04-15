// MintNFTView.swift
// MTRX
//
// Mint NFT interface — image selection, metadata input, attributes, royalty, preview, and submit.

import SwiftUI
import PhotosUI

// MARK: - Attribute Pair

struct NFTAttribute: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

// MARK: - View Model

@MainActor
class MintNFTViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var attributes: [NFTAttribute] = [NFTAttribute(key: "", value: "")]
    @Published var royaltyPercentage: Double = 5.0
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var selectedImage: UIImage?
    @Published var isMinting: Bool = false
    @Published var errorMessage: String?
    @Published var showPreview: Bool = false
    @Published var mintComplete: Bool = false

    var estimatedMintFee: String { "$2.40" }
    var estimatedGas: String { "0.0008 ETH" }

    var canMint: Bool {
        selectedImage != nil &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var validAttributes: [NFTAttribute] {
        attributes.filter {
            !$0.key.trimmingCharacters(in: .whitespaces).isEmpty &&
            !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    func loadSelectedPhoto() async {
        guard let item = selectedPhotoItem else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = image
            }
        } catch {
            errorMessage = "Failed to load the selected image."
        }
    }

    func addAttribute() {
        attributes.append(NFTAttribute(key: "", value: ""))
    }

    func removeAttribute(at offsets: IndexSet) {
        attributes.remove(atOffsets: offsets)
        if attributes.isEmpty {
            attributes.append(NFTAttribute(key: "", value: ""))
        }
    }

    func removeAttribute(id: UUID) {
        attributes.removeAll { $0.id == id }
        if attributes.isEmpty {
            attributes.append(NFTAttribute(key: "", value: ""))
        }
    }

    func mint() async {
        guard canMint else { return }
        isMinting = true
        errorMessage = nil

        do {
            try await Task.sleep(for: .seconds(2))
            isMinting = false
            mintComplete = true
        } catch {
            errorMessage = "Minting failed. Please try again."
            isMinting = false
        }
    }
}

// MARK: - Mint NFT View

struct MintNFTView: View {
    @StateObject private var viewModel = MintNFTViewModel()
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(title: "Mint NFT", subtitle: "Create a new NFT on Base") {
                        dismiss()
                    }

                    if viewModel.mintComplete {
                        mintSuccessView
                    } else if viewModel.showPreview {
                        previewSection
                    } else {
                        mintForm
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
            .onChange(of: viewModel.selectedPhotoItem) { _, _ in
                Task { await viewModel.loadSelectedPhoto() }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Mint Form

    private var mintForm: some View {
        VStack(spacing: Spacing.lg) {
            imagePickerSection
            nameDescriptionSection
            attributesSection
            royaltySection
            feeSection
            previewButton
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Image Picker

    private var imagePickerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Image")
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)

            PhotosPicker(
                selection: $viewModel.selectedPhotoItem,
                matching: .images
            ) {
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.accentPrimary)
                                .padding(Spacing.sm)
                        }
                } else {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: Symbols.photo)
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Color.accentPrimary.opacity(0.6))

                        Text("Tap to select an image")
                            .font(.mtrxCallout)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                            .foregroundStyle(Color.accentPrimary.opacity(0.3))
                    )
                }
            }
        }
    }

    // MARK: - Name & Description

    private var nameDescriptionSection: some View {
        VStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Name")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                MtrxTextField(placeholder: "My NFT", text: $viewModel.name)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Description")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                TextEditor(text: $viewModel.description)
                    .font(.mtrxBody)
                    .frame(minHeight: 80, maxHeight: 140)
                    .padding(Spacing.sm)
                    .scrollContentBackground(.hidden)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
        }
    }

    // MARK: - Attributes

    private var attributesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Attributes")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                Spacer()
                Button {
                    MtrxHaptics.impact(.light)
                    withAnimation(Motion.springSnappy) {
                        viewModel.addAttribute()
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.add)
                            .font(.system(size: 12, weight: .bold))
                        Text("Add")
                            .font(.mtrxCaptionBold)
                    }
                    .foregroundStyle(Color.accentPrimary)
                }
            }

            ForEach(Array(viewModel.attributes.enumerated()), id: \.element.id) { index, attribute in
                HStack(spacing: Spacing.sm) {
                    TextField("Trait", text: Binding(
                        get: { viewModel.attributes[safe: index]?.key ?? "" },
                        set: { if viewModel.attributes.indices.contains(index) { viewModel.attributes[index].key = $0 } }
                    ))
                    .font(.mtrxBody)
                    .padding(.horizontal, Spacing.textFieldPadding)
                    .frame(height: Spacing.Size.textFieldHeight)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                    TextField("Value", text: Binding(
                        get: { viewModel.attributes[safe: index]?.value ?? "" },
                        set: { if viewModel.attributes.indices.contains(index) { viewModel.attributes[index].value = $0 } }
                    ))
                    .font(.mtrxBody)
                    .padding(.horizontal, Spacing.textFieldPadding)
                    .frame(height: Spacing.Size.textFieldHeight)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                    if viewModel.attributes.count > 1 {
                        Button {
                            MtrxHaptics.impact(.light)
                            withAnimation(Motion.springSnappy) {
                                viewModel.removeAttribute(id: attribute.id)
                            }
                        } label: {
                            Image(systemName: Symbols.remove)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.statusError.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Royalty Slider

    private var royaltySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Royalty")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                Spacer()
                Text(String(format: "%.1f%%", viewModel.royaltyPercentage))
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color.accentPrimary)
            }

            Slider(value: $viewModel.royaltyPercentage, in: 0...10, step: 0.5)
                .tint(Color.accentPrimary)

            HStack {
                Text("0%")
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
                Spacer()
                Text("10%")
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
    }

    // MARK: - Fee Display

    private var feeSection: some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.ms) {
                feeRow(label: "Mint Fee", value: viewModel.estimatedMintFee)
                MtrxDivider()
                feeRow(label: "Est. Gas", value: viewModel.estimatedGas)
                MtrxDivider()
                feeRow(label: "Network", value: "Base")
            }
        }
    }

    private func feeRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value)
                .font(.mtrxMonoSmall)
                .foregroundStyle(Color.labelPrimary)
        }
    }

    // MARK: - Preview Button

    private var previewButton: some View {
        VStack(spacing: Spacing.sm) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                MtrxHaptics.impact(.medium)
                withAnimation(Motion.springDefault) {
                    viewModel.showPreview = true
                }
            } label: {
                Text("Preview NFT")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
            .disabled(!viewModel.canMint)
            .opacity(viewModel.canMint ? 1 : 0.5)
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(spacing: Spacing.lg) {
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
                    .padding(.horizontal, Spacing.contentPadding)
            }

            MtrxCard(style: .glass) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(viewModel.name)
                        .font(.mtrxTitle2)
                        .foregroundStyle(Color.labelPrimary)

                    if !viewModel.description.isEmpty {
                        Text(viewModel.description)
                            .font(.mtrxBody)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    if !viewModel.validAttributes.isEmpty {
                        MtrxDivider()
                        ForEach(viewModel.validAttributes) { attr in
                            HStack {
                                Text(attr.key)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.accentPrimary)
                                Spacer()
                                Text(attr.value)
                                    .font(.mtrxCallout)
                                    .foregroundStyle(Color.labelPrimary)
                            }
                        }
                    }

                    MtrxDivider()

                    HStack {
                        Text("Royalty")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text(String(format: "%.1f%%", viewModel.royaltyPercentage))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            VStack(spacing: Spacing.ms) {
                Button {
                    Task { await viewModel.mint() }
                } label: {
                    Text(viewModel.isMinting ? "Minting..." : "Mint NFT")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .primary,
                    size: .large,
                    isLoading: viewModel.isMinting,
                    fullWidth: true
                ))
                .disabled(viewModel.isMinting)

                Button {
                    MtrxHaptics.impact(.light)
                    withAnimation(Motion.springDefault) {
                        viewModel.showPreview = false
                    }
                } label: {
                    Text("Edit")
                }
                .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .regular))
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
        .mtrxFadeInFromBottom(isVisible: true)
    }

    // MARK: - Mint Success

    private var mintSuccessView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: Symbols.complete)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.statusSuccess)
                .mtrxPulse(isActive: true)

            VStack(spacing: Spacing.sm) {
                Text("NFT Minted")
                    .font(.mtrxTitle1)
                    .foregroundStyle(Color.labelPrimary)

                Text("\(viewModel.name) has been minted on Base.")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
            .padding(.horizontal, Spacing.contentPadding)

            Spacer()
        }
        .padding(.horizontal, Spacing.contentPadding)
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    MintNFTView()
        .preferredColorScheme(.dark)
}
