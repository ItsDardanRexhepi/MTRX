// StorageView.swift
// MTRX
//
// Decentralized storage — file management, IPFS/Filecoin uploads, CID tracking, pin status.

import SwiftUI
import UniformTypeIdentifiers

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
    @Published var isDemo: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    // Upload form
    @Published var uploadFilename: String = ""
    @Published var selectedLayer: String = "IPFS"
    @Published var isUploading: Bool = false
    @Published var copiedCID: String?

    // Picked-file state (populated by the real document picker)
    @Published var showFilePicker: Bool = false
    @Published var selectedFileData: Data?
    @Published var selectedFileName: String?
    @Published var selectedFileSizeLabel: String?
    @Published var selectedMimeType: String?

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

        // Live files from StorageService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                let live = try await StorageService.shared.getUserFiles(address: address)
                files = live.map { f in
                    FileItem(
                        filename: f.filename,
                        mimeType: f.mimeType,
                        size: ByteCountFormatter.string(fromByteCount: f.size, countStyle: .file),
                        uploadedAt: Self.dateFormatter.string(from: f.uploadedAt),
                        layer: f.layer,
                        isPinned: f.isPinned,
                        cid: f.cid
                    )
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live files unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(700))
            files = StorageViewModel.sampleFiles
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load storage data."
            isLoading = false
        }
    }

    /// Handle the result of the system document picker. Reads the picked file's
    /// real bytes (security-scoped), size and MIME type — no placeholder values.
    func handlePickedFile(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = "Couldn't open the file: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                selectedFileData = data
                selectedFileName = url.lastPathComponent
                if uploadFilename.isEmpty { uploadFilename = url.lastPathComponent }
                selectedFileSizeLabel = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                selectedMimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't read the file: \(error.localizedDescription)"
            }
        }
    }

    /// Request/response shapes for the real `/storage/files` upload.
    private struct UploadBody: Encodable {
        let dataBase64: String
        let filename: String
        let mimeType: String
        let layer: String
    }
    private struct UploadedFile: Decodable {
        let cid: String
        let mimeType: String?
        let size: Int64?
    }

    func uploadFile() async {
        guard !uploadFilename.isEmpty else { return }
        guard let data = selectedFileData else {
            errorMessage = "Select a file first."
            return
        }
        isUploading = true
        errorMessage = nil
        do {
            // Real upload via the in-build API client — the backend assigns the
            // CID. We never fabricate one; on failure we surface the error rather
            // than inventing a result. (The old Services/StorageService.swift is
            // not in the build; we call MTRXAPIClient directly.)
            let body = UploadBody(
                dataBase64: data.base64EncodedString(),
                filename: uploadFilename,
                mimeType: selectedMimeType ?? "application/octet-stream",
                layer: selectedLayer
            )
            let uploaded: UploadedFile = try await MTRXAPIClient.shared.post(path: "/storage/files", body: body)
            let sizeLabel = uploaded.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                ?? selectedFileSizeLabel
                ?? ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            let file = FileItem(
                filename: uploadFilename,
                mimeType: uploaded.mimeType ?? selectedMimeType ?? "application/octet-stream",
                size: sizeLabel,
                uploadedAt: "Just now",
                layer: selectedLayer,
                isPinned: selectedLayer == "IPFS",
                cid: uploaded.cid
            )
            files.insert(file, at: 0)
            resetUploadForm()
            showUpload = false
        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
        }
        isUploading = false
    }

    private func resetUploadForm() {
        uploadFilename = ""
        selectedFileData = nil
        selectedFileName = nil
        selectedFileSizeLabel = nil
        selectedMimeType = nil
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
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showUpload = true
                    } label: {
                        Image(systemName: Symbols.addCircle)
                            .accessibilityLabel("Upload file")
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
                                .minimumScaleFactor(0.8)
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
                        .minimumScaleFactor(0.75)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        viewModel.copyCID(file.cid)
                    } label: {
                        Image(systemName: viewModel.copiedCID == file.cid ? Symbols.complete : Symbols.copy)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(viewModel.copiedCID == file.cid ? Color.statusSuccess : Color.accentPrimary)
                            .accessibilityLabel("Copy file ID")
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
                    // Real document picker
                    Button {
                        viewModel.showFilePicker = true
                    } label: {
                        VStack(spacing: Spacing.md) {
                            Image(systemName: viewModel.selectedFileData == nil ? "arrow.up.doc.fill" : "doc.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.accentPrimary)
                            Text(viewModel.selectedFileName ?? "Select File")
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .truncationMode(.middle)
                            if let size = viewModel.selectedFileSizeLabel {
                                Text(size)
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                            }
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
                .disabled(viewModel.uploadFilename.isEmpty || viewModel.selectedFileData == nil || viewModel.isUploading)
                .opacity(viewModel.uploadFilename.isEmpty || viewModel.selectedFileData == nil ? 0.5 : 1)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
            .fileImporter(
                isPresented: $viewModel.showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                viewModel.handlePickedFile(result)
            }
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
