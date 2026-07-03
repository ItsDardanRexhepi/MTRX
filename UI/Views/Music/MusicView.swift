// MusicView.swift
// MTRX
//
// On-chain music platform — catalog, royalties, upload, streaming, and earnings.

import SwiftUI

// MARK: - View Model

final class MusicViewModel: ObservableObject {

    // MARK: - Published State

    @Published var catalog: [MusicTrack] = []
    @Published var myCatalog: [MusicTrack] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isEmpty: Bool = false

    // Upload
    @Published var uploadTitle: String = ""
    @Published var uploadArtist: String = ""
    @Published var uploadPricePerPlay: String = "0.001"
    @Published var collaborators: [Collaborator] = [Collaborator(name: "", splitPercent: 100)]
    @Published var isUploading: Bool = false
    @Published var uploadSuccess: Bool = false

    // Player
    @Published var currentTrack: MusicTrack?
    @Published var isPlaying: Bool = false
    @Published var playbackProgress: Double = 0.0

    // Detail
    @Published var selectedTrack: MusicTrack?
    @Published var showDetail: Bool = false

    // Earnings
    @Published var isClaiming: Bool = false

    // Honest failure
    @Published var actionUnavailable: Bool = false

    // MARK: - Load

    func loadCatalog() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.catalog = MusicTrack.sampleCatalog
            self.myCatalog = MusicTrack.sampleMine
            self.isEmpty = self.catalog.isEmpty
            self.isLoading = false
        }
    }

    // MARK: - Upload

    func uploadTrack() {
        guard !uploadTitle.isEmpty else {
            errorMessage = "Track title is required."
            return
        }
        let totalSplit = collaborators.reduce(0) { $0 + $1.splitPercent }
        guard totalSplit == 100 else {
            errorMessage = "Royalty splits must total 100%."
            return
        }
        errorMessage = nil
        // Honest failure: no backend/on-chain path is wired to publish a track
        // or register its royalty splits. Change no state; surface honestly.
        isUploading = false
        actionUnavailable = true
    }

    // MARK: - Player

    func playTrack(_ track: MusicTrack) {
        if currentTrack?.id == track.id {
            isPlaying.toggle()
        } else {
            currentTrack = track
            isPlaying = true
            playbackProgress = 0
            simulatePlayback()
        }
    }

    private func simulatePlayback() {
        guard isPlaying, playbackProgress < 1.0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isPlaying else { return }
            self.playbackProgress = min(self.playbackProgress + 0.01, 1.0)
            self.simulatePlayback()
        }
    }

    // MARK: - Detail

    func showTrackDetail(_ track: MusicTrack) {
        selectedTrack = track
        showDetail = true
    }

    // MARK: - Claim

    func claimEarnings() {
        // Honest failure: no backend/on-chain path is wired to claim royalty
        // earnings. Do not zero the demo earnings as if a payout occurred.
        isClaiming = false
        actionUnavailable = true
    }

    // MARK: - Collaborators

    func addCollaborator() {
        collaborators.append(Collaborator(name: "", splitPercent: 0))
    }

    func removeCollaborator(at index: Int) {
        guard collaborators.count > 1 else { return }
        collaborators.remove(at: index)
    }

    private func resetUploadForm() {
        uploadTitle = ""
        uploadArtist = ""
        uploadPricePerPlay = "0.001"
        collaborators = [Collaborator(name: "", splitPercent: 100)]
    }
}

// MARK: - Models

struct MusicTrack: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    var plays: Int
    let pricePerPlay: Double
    let royaltySplits: [RoyaltySplit]
    var earnings: Double
    let duration: Int
    let uploadDate: Date

    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static var sampleCatalog: [MusicTrack] {
        [
            MusicTrack(title: "Decentralized Dreams", artist: "CryptoBeats", plays: 12450, pricePerPlay: 0.001, royaltySplits: [RoyaltySplit(name: "CryptoBeats", percentage: 80), RoyaltySplit(name: "Producer X", percentage: 20)], earnings: 12.45, duration: 234, uploadDate: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()),
            MusicTrack(title: "Block by Block", artist: "HashHarmony", plays: 8920, pricePerPlay: 0.002, royaltySplits: [RoyaltySplit(name: "HashHarmony", percentage: 70), RoyaltySplit(name: "Lyricist A", percentage: 15), RoyaltySplit(name: "Mixer B", percentage: 15)], earnings: 17.84, duration: 198, uploadDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()),
            MusicTrack(title: "Consensus", artist: "NodeVibes", plays: 5340, pricePerPlay: 0.0015, royaltySplits: [RoyaltySplit(name: "NodeVibes", percentage: 100)], earnings: 8.01, duration: 276, uploadDate: Calendar.current.date(byAdding: .weekOfYear, value: -2, to: Date()) ?? Date()),
        ]
    }

    static var sampleMine: [MusicTrack] {
        [
            MusicTrack(title: "My First Track", artist: "You", plays: 42, pricePerPlay: 0.001, royaltySplits: [RoyaltySplit(name: "You", percentage: 100)], earnings: 0.042, duration: 180, uploadDate: Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()),
        ]
    }
}

struct RoyaltySplit: Identifiable {
    let id = UUID()
    let name: String
    let percentage: Int
}

struct Collaborator: Identifiable {
    let id = UUID()
    var name: String
    var splitPercent: Int
}

// MARK: - View

struct MusicView: View {
    @StateObject private var viewModel = MusicViewModel()
    @State private var selectedTab: MusicTab = .catalog

    private let accentColor = Color(red: 0.0, green: 0.675, blue: 0.694)

    enum MusicTab: String, CaseIterable {
        case catalog = "Catalog"
        case upload = "Upload"
        case myCatalog = "My Music"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                tabContent

                if viewModel.currentTrack != nil {
                    playerBar
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Music")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { viewModel.loadCatalog() }
            .honestActionAlert($viewModel.actionUnavailable, message: "Uploading tracks and claiming earnings aren't available in this build yet. Nothing was changed.")
            .sheet(isPresented: $viewModel.showDetail) {
                if let track = viewModel.selectedTrack {
                    trackDetailSheet(track)
                }
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(MusicTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .catalog:
            catalogSection
        case .upload:
            uploadSection
        case .myCatalog:
            myCatalogSection
        }
    }

    // MARK: - Catalog

    private var catalogSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading catalog...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isEmpty {
                ContentUnavailableView("No Tracks", systemImage: "music.note", description: Text("No music available yet."))
            } else {
                List {
                    ForEach(viewModel.catalog) { track in
                        trackRow(track)
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.showTrackDetail(track) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func trackRow(_ track: MusicTrack) -> some View {
        HStack(spacing: Spacing.ms) {
            RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm)
                .fill(LinearGradient(colors: [accentColor.opacity(0.6), accentColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(track.title)
                    .font(.mtrxHeadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(track.artist)
                    .font(.mtrxSubheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("\(track.plays) plays")
                    .font(.mtrxCaption1)
                    .foregroundStyle(.secondary)

                Text(track.formattedDuration)
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(.tertiary)
            }

            Button {
                viewModel.playTrack(track)
            } label: {
                Image(systemName: viewModel.currentTrack?.id == track.id && viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .accessibilityLabel("Play or pause track")
                    .font(.title)
                    .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Track Detail Sheet

    private func trackDetailSheet(_ track: MusicTrack) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg)
                        .fill(LinearGradient(colors: [accentColor.opacity(0.4), accentColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 200)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundStyle(.white)
                        )

                    VStack(spacing: Spacing.sm) {
                        Text(track.title)
                            .font(.mtrxTitle2)
                        Text(track.artist)
                            .font(.mtrxSubheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Royalty Split")
                            .font(.mtrxHeadline)

                        ForEach(track.royaltySplits) { split in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack {
                                    Text(split.name)
                                        .font(.mtrxSubheadline)
                                    Spacer()
                                    Text("\(split.percentage)%")
                                        .font(.mtrxHeadlineTabular)
                                        .foregroundStyle(accentColor)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(.systemGray5))
                                            .frame(height: 8)

                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(accentColor)
                                            .frame(width: geo.size.width * Double(split.percentage) / 100.0, height: 8)
                                    }
                                }
                                .frame(height: 8)
                            }
                        }
                    }
                    .mtrxCardStyle()

                    HStack(spacing: Spacing.lg) {
                        statPill(label: "Plays", value: "\(track.plays)")
                        statPill(label: "Price/Play", value: String(format: "%.4f ETH", track.pricePerPlay))
                        statPill(label: "Duration", value: track.formattedDuration)
                    }
                }
                .padding(Spacing.contentPadding)
            }
            .navigationTitle("Track Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.showDetail = false }
                }
            }
        }
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.mtrxCaptionBold)
            Text(label)
                .font(.mtrxCaption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
    }

    // MARK: - Upload

    private var uploadSection: some View {
        Form {
            Section("Track Info") {
                TextField("Track title", text: $viewModel.uploadTitle)
                TextField("Artist name", text: $viewModel.uploadArtist)

                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(accentColor)
                    Text("Select audio file")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(accentColor)
                }

                HStack {
                    Image(systemName: "photo.artframe")
                        .foregroundStyle(accentColor)
                    Text("Select artwork")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "photo.badge.plus")
                        .foregroundStyle(accentColor)
                }
            }

            Section("Price Per Play (ETH)") {
                TextField("0.001", text: $viewModel.uploadPricePerPlay)
                    .font(.mtrxMono)
                    .keyboardType(.decimalPad)
            }

            Section("Collaborators & Splits") {
                ForEach(Array(viewModel.collaborators.enumerated()), id: \.element.id) { index, _ in
                    HStack(spacing: Spacing.sm) {
                        TextField("Name", text: $viewModel.collaborators[index].name)
                        TextField("Split %", value: $viewModel.collaborators[index].splitPercent, format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        if viewModel.collaborators.count > 1 {
                            Button {
                                viewModel.removeCollaborator(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Remove collaborator")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button {
                    viewModel.addCollaborator()
                } label: {
                    Label("Add Collaborator", systemImage: "plus.circle")
                        .foregroundStyle(accentColor)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.mtrxFootnote)
                }
            }

            Section {
                Button {
                    viewModel.uploadTrack()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isUploading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "icloud.and.arrow.up")
                            Text("Upload Track")
                                .font(.mtrxHeadline)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                }
                .disabled(viewModel.isUploading)
                .listRowInsets(EdgeInsets())
                .padding(Spacing.contentPadding)
            }
        }
    }

    // MARK: - My Catalog

    private var myCatalogSection: some View {
        Group {
            if viewModel.myCatalog.isEmpty {
                ContentUnavailableView("No Uploads", systemImage: "music.note.list", description: Text("Upload your first track to see it here."))
            } else {
                List {
                    Section {
                        let totalEarnings = viewModel.myCatalog.reduce(0.0) { $0 + $1.earnings }
                        let totalStreams = viewModel.myCatalog.reduce(0) { $0 + $1.plays }

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Total Streams")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(.secondary)
                                Text("\(totalStreams)")
                                    .font(.mtrxMonoMedium)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Unclaimed Earnings")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.4f ETH", totalEarnings))
                                    .font(.mtrxMonoMedium)
                                    .foregroundStyle(accentColor)
                            }
                        }

                        Button {
                            viewModel.claimEarnings()
                        } label: {
                            HStack {
                                Spacer()
                                if viewModel.isClaiming {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Claim Earnings")
                                        .font(.mtrxHeadline)
                                }
                                Spacer()
                            }
                            .padding(.vertical, Spacing.sm)
                            .background(totalEarnings > 0 ? accentColor : Color(.systemGray4))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        }
                        .disabled(totalEarnings <= 0 || viewModel.isClaiming)
                        .listRowInsets(EdgeInsets())
                        .padding(Spacing.contentPadding)
                    }

                    Section("Tracks") {
                        ForEach(viewModel.myCatalog) { track in
                            trackRow(track)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Player Bar

    private var playerBar: some View {
        VStack(spacing: 0) {
            ProgressView(value: viewModel.playbackProgress)
                .tint(accentColor)
                .frame(height: 2)

            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(accentColor)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentTrack?.title ?? "")
                        .font(.mtrxCaptionBold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(viewModel.currentTrack?.artist ?? "")
                        .font(.mtrxCaption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.isPlaying.toggle()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .accessibilityLabel("Play or pause")
                        .font(.title3)
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview {
    MusicView()
}
