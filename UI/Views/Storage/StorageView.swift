// StorageView.swift
// MTRX
//
// Decentralized storage — file management, IPFS/Filecoin uploads, CID tracking, pin status.

import SwiftUI

// MARK: - Data Models

struct FileItem: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let size: String
    let uploadedAt: String
    let layer: String
    let isPinned: Bool
    let cid: String
}

// MARK: - View Model

@MainActor
class StorageViewModel: ObservableObject {
    @Published var files: [FileItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showUpload: Bool = false

    // Upload form
    @Published var uploadFilename: String = ""
    @Published var selectedLayer: String = "IPFS"
    @Published var isUploading: Bool = false
    @Published var copiedCID: String?

    let storageLayers = ["IPFS", "Filecoin"]

    var totalFiles: Int { files.count }
    var pinnedFiles: Int { files.filter(\.isPinned).count }

    var totalStorageUsed: String {
        let sizes = files.compactMap { sizeInBytes($0.size) }
        let total = sizes.reduce(0, +)
        return formatBytes(total)
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            try await Task.sleep(for: .milliseconds(700))
            files = StorageViewModel.sampleFiles
            isLoading = false
        } catch {
            errorMessage = "Unable to load storage data."
            isLoading = false
        }
    }

    func uploadFile() async {
        guard !uploadFilename.isEmpty else { return }
        isUploading = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            let file = FileItem(
                filename: uploadFilename,
                mimeType: "application/octet-stream",
                size: "1.2 MB",
                uploadedAt: "Just now",
                layer: selectedLayer,
                isPinned: selectedLayer == "IPFS",
                cid: "Qm\(UUID().uuidString.prefix(16))"
            )
            files.insert(file, at: 0)
            uploadFilename = ""
            isUploading = false
            showUpload = false
        } catch {
            isUploading = false
        }
    }

    func copyCID(_ cid: String) {
        UIPasteboard.general.string = cid
        copiedCID = cid
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedCID = nil
        }
    }

    private func sizeInBytes(_ size: String) -> Int64? {
        let parts = size.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return nil }
        let unit = String(parts[1]).uppercased()
        switch unit {
        case "KB": return Int64(value * 1024)
        case "MB": return Int64(value * 1024 * 1024)
        case "GB": return Int64(value * 1024 * 1024 * 1024)
        default: return Int64(value)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static let sampleFiles: [FileItem] = [
        FileItem(filename: "contract_abi.json", mimeType: "application/json", size: "24 KB", uploadedAt: "2h ago", layer: "IPFS", isPinned: true, cid: "QmX7b3fVfCnHYiRJo4of2CpKZia5UWz8HsGqrmfVHBEZiC"),
        FileItem(filename: "avatar.png", mimeType: "image/png", size: "2.4 MB", uploadedAt: "1d ago", layer: "IPFS", isPinned: true, cid: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG"),
        FileItem(filename: "dataset_v3.csv", mimeType: "text/csv", size: "156 MB", uploadedAt: "3d ago", layer: "Filecoin", isPinned: false, cid: "bafy2bzacedfghjklmnopqrstuvwxyz12345abcde"),
        FileItem(filename: "model_weights.bin", mimeType: "application/octet-stream", size: "1.2 GB", uploadedAt: "1w ago", layer: "Filecoin", isPinned: false, cid: "bafy2bzaceg7hijk8lmnop9qrstuvwxyz67890fgh"),
        FileItem(filename: "metadata.json", mimeType: "application/json", size: "4 KB", uploadedAt: "2w ago", layer: "IPFS", isPinned: true, cid: "QmZtmD2qt6fJot2qfNUMNPRqAoRrmkVKaztv6EUSm1YRs1")
    ]
}

// MARK: - Storage View

struct StorageView: View {
    @StateObject private var viewModel = StorageViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.files.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.files.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    storageContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Storage")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showUpload = true
                    } label: {
                        Image(systemName: Symbols.addCircle)
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showUpload) {
                uploadSheet
            }
        }
    }

    // MARK: - Content

    private var storageContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                storageSummary
                filesSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Storage Summary

    private var storageSummary: some View {
        HStack(spacing: Spacing.sm) {
            MtrxStatCard(title: "Total Files", value: "\(viewModel.totalFiles)", icon: "doc.fill")
            MtrxStatCard(title: "Pinned", value: "\(viewModel.pinnedFiles)", icon: "pin.fill")
            MtrxStatCard(title: "Used", value: viewModel.totalStorageUsed, icon: "externaldrive.fill")
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Files Section

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Files")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.files) { file in
                fileCard(file)
            }
        }
    }

    private func fileCard(_ file: FileItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.ms) {
                    MtrxAvatar(
                        symbol: fileIcon(for: file.mimeType),
                        color: .accentPrimary,
                        size: 40
                    )

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.xs) {
                            Text(file.filename)
                                .font(.mtrxBodyBold)
                                .foregroundStyle(Color.labelPrimary)
                                .lineLimit(1)
                            if file.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.accentPrimary)
                            }
                        }
                        HStack(spacing: Spacing.sm) {
                            Text(file.size)
                                .font(.mtrxCaption1)
                            Text(file.uploadedAt)
                                .font(.mtrxCaption1)
                        }
                        .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    MtrxBadge(text: file.layer, style: file.layer == "IPFS" ? .info : .accent)
                }

                HStack(spacing: Spacing.sm) {
                    Text(file.cid)
                        .font(.mtrxMono)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        viewModel.copyCID(file.cid)
                    } label: {
                        Image(systemName: viewModel.copiedCID == file.cid ? Symbols.complete : Symbols.copy)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(viewModel.copiedCID == file.cid ? Color.statusSuccess : Color.accentPrimary)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Upload Sheet

    private var uploadSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                MtrxSheetHeader(title: "Upload File", subtitle: "Store on decentralized storage") {
                    viewModel.showUpload = false
                }

                VStack(spacing: Spacing.md) {
                    // File picker placeholder
                    Button {
                        // File picker would open here
                    } label: {
                        VStack(spacing: Spacing.md) {
                            Image(systemName: "arrow.up.doc.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.accentPrimary)
                            Text("Select File")
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(Color.surfaceOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                                .stroke(Color.accentPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [8, 4]))
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Filename")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        MtrxTextField(placeholder: "Enter filename", text: $viewModel.uploadFilename)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Storage Layer")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        HStack(spacing: Spacing.sm) {
                            ForEach(viewModel.storageLayers, id: \.self) { layer in
                                MtrxChip(
                                    label: layer,
                                    isSelected: viewModel.selectedLayer == layer
                                ) {
                                    viewModel.selectedLayer = layer
                                }
                            }
                        }
                    }

                    // Layer info
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: Symbols.alertInfo)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.statusInfo)
                        Text(viewModel.selectedLayer == "IPFS"
                             ? "IPFS provides fast retrieval with content-addressing. Files are pinned automatically."
                             : "Filecoin offers long-term verifiable storage with cryptographic proofs.")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .padding(Spacing.ms)
                    .background(Color.statusInfo.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
                .padding(.horizontal, Spacing.contentPadding)

                Spacer()

                Button {
                    Task { await viewModel.uploadFile() }
                } label: {
                    Text(viewModel.isUploading ? "Uploading..." : "Upload")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .primary,
                    size: .large,
                    isLoading: viewModel.isUploading,
                    fullWidth: true
                ))
                .disabled(viewModel.uploadFilename.isEmpty || viewModel.isUploading)
                .opacity(viewModel.uploadFilename.isEmpty ? 0.5 : 1)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

    private func fileIcon(for mimeType: String) -> String {
        if mimeType.contains("json") { return "doc.text.fill" }
        if mimeType.contains("image") { return Symbols.photo }
        if mimeType.contains("csv") || mimeType.contains("text") { return "tablecells.fill" }
        return "doc.fill"
    }
}

// MARK: - Preview

#Preview {
    StorageView()
        .preferredColorScheme(.dark)
}
