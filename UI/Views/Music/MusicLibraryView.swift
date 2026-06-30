// MusicLibraryView.swift
// MTRX — Apple Music library browsing (MusicKit)
//
// Surfaces the user's saved Apple Music content — Playlists, Artists, Albums,
// Songs, Recently Added — categorized and navigable, played through the same
// MusicKitManager engine used by the player. There is no second MusicKit path:
// reads go through MusicKitManager's library methods (gated by the one
// authorization it owns) and playback goes through MusicKitManager.playSongs.
// Every state is honest (loading / failed / empty) and never fabricated. Per
// Apple Music Identity Guidelines each screen carries Apple Music attribution.

import SwiftUI
import Observation
#if canImport(MusicKit)
import MusicKit

// MARK: - Load state (mirrors MusicKitManager.ChartLoad)

enum LibraryLoadState {
    case idle, loading, loaded, failed
}

/// Honest placeholder shown while a category has no items to display. It tells
/// the user *why* there's nothing — still loading, a real failure (often the
/// MusicKit capability), or a genuinely empty library — never a fake list.
@ViewBuilder
func libraryPlaceholder(_ state: LibraryLoadState, empty: String) -> some View {
    switch state {
    case .idle, .loading:
        ProgressView().padding(.top, Spacing.xl)
    case .failed:
        Text("Couldn't load your library. Make sure Apple Music access is allowed and the app's MusicKit capability is enabled.")
            .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
            .multilineTextAlignment(.center)
            .padding(.top, Spacing.xl).padding(.horizontal, Spacing.lg)
    case .loaded:
        Text(empty)
            .font(.mtrxCallout).foregroundStyle(Color.labelTertiary)
            .padding(.top, Spacing.xl)
    }
}

// MARK: - Apple Music attribution (required on every library screen)

private struct AppleMusicAttribution: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            AppleMusicBadge()
                .padding(.vertical, Spacing.xs)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
        }
    }
}

private extension View {
    func appleMusicAttributed() -> some View { modifier(AppleMusicAttribution()) }
}

// MARK: - Categories surfaced in the player's "Your Library" section

enum LibraryCategory: String, CaseIterable, Identifiable {
    case playlists = "Playlists"
    case artists = "Artists"
    case albums = "Albums"
    case songs = "Songs"
    case recentlyAdded = "Recently Added"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .playlists:     return "music.note.list"
        case .artists:       return "music.mic"
        case .albums:        return "square.stack"
        case .songs:         return "music.note"
        case .recentlyAdded: return "clock"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .playlists:
            LibraryPaginatedList(
                title: "Playlists",
                emptyText: "No playlists in your library yet.",
                fetch: { try await MusicKitManager.shared.libraryPlaylists() },
                row: { LibraryItemRow(artwork: $0.artwork, title: $0.name, subtitle: $0.curatorName) },
                destination: { LibraryDetailView(source: .playlist($0)) }
            )
        case .albums:
            LibraryPaginatedList(
                title: "Albums",
                emptyText: "No albums in your library yet.",
                fetch: { try await MusicKitManager.shared.libraryAlbums() },
                row: { LibraryItemRow(artwork: $0.artwork, title: $0.title, subtitle: $0.artistName) },
                destination: { LibraryDetailView(source: .album($0)) }
            )
        case .artists:
            LibraryPaginatedList(
                title: "Artists",
                emptyText: "No artists in your library yet.",
                fetch: { try await MusicKitManager.shared.libraryArtists() },
                row: { LibraryItemRow(artwork: $0.artwork, title: $0.name, subtitle: nil, circular: true) },
                destination: { LibraryArtistDetailView(artist: $0) }
            )
        case .songs:
            LibrarySongsView(recentlyAdded: false)
        case .recentlyAdded:
            LibrarySongsView(recentlyAdded: true)
        }
    }
}

/// The category row shown in the player's browse list.
struct MusicLibraryCategoryRow: View {
    let category: LibraryCategory

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: category.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 28)
            Text(category.rawValue)
                .font(.mtrxCallout).foregroundStyle(Color.labelPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.labelTertiary)
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(category.rawValue)
        .accessibilityHint("Browse your \(category.rawValue.lowercased())")
    }
}

// MARK: - Reusable artwork row (playlists / albums / artists)

struct LibraryItemRow: View {
    let artwork: Artwork?
    let title: String
    let subtitle: String?
    var circular: Bool = false

    private var corner: CGFloat { circular ? 24 : 6 }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Group {
                if let artwork {
                    ArtworkImage(artwork, width: 48, height: 48)
                } else {
                    RoundedRectangle(cornerRadius: corner)
                        .fill(Color.surfaceOverlay)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: circular ? "music.mic" : "music.note")
                                .foregroundStyle(Color.labelTertiary)
                        )
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.mtrxCallout).foregroundStyle(Color.labelPrimary).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.labelTertiary)
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}

// MARK: - Generic paginated browse list (playlists / albums / artists)

struct LibraryPaginatedList<Item: MusicItem, Row: View, Destination: View>: View {
    let title: String
    let emptyText: String
    let fetch: () async throws -> MusicItemCollection<Item>
    let row: (Item) -> Row
    let destination: (Item) -> Destination

    init(title: String, emptyText: String,
         fetch: @escaping () async throws -> MusicItemCollection<Item>,
         @ViewBuilder row: @escaping (Item) -> Row,
         @ViewBuilder destination: @escaping (Item) -> Destination) {
        self.title = title
        self.emptyText = emptyText
        self.fetch = fetch
        self.row = row
        self.destination = destination
    }

    @State private var music = MusicKitManager.shared
    @State private var items: [Item] = []
    @State private var cursor: MusicItemCollection<Item>?
    @State private var load: LibraryLoadState = .idle
    @State private var loadingMore = false

    var body: some View {
        ScrollView {
            if items.isEmpty {
                libraryPlaceholder(load, empty: emptyText).frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(items, id: \.id) { item in
                        NavigationLink { destination(item) } label: { row(item) }
                            .buttonStyle(.plain)
                            .onAppear { Task { await loadMore(after: item) } }
                    }
                    if loadingMore { ProgressView().padding(.vertical, Spacing.sm) }
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            }
        }
        .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .appleMusicAttributed()
        .task { if load == .idle { await initialLoad() } }
    }

    private func initialLoad() async {
        load = .loading
        do {
            let batch = try await fetch()
            items = Array(batch)
            cursor = batch
            load = .loaded
        } catch {
            load = .failed
        }
    }

    /// Lazy pagination: when the last visible row appears, pull the next batch.
    private func loadMore(after item: Item) async {
        guard !loadingMore, item.id == items.last?.id,
              let c = cursor, c.hasNextBatch else { return }
        loadingMore = true
        if let next = await music.loadMore(c) {
            items.append(contentsOf: next)
            cursor = next
        }
        loadingMore = false
    }
}

// MARK: - Songs / Recently Added (tap to play into the shared engine)

struct LibrarySongsView: View {
    let recentlyAdded: Bool

    @State private var music = MusicKitManager.shared
    @State private var songs: [Song] = []
    @State private var cursor: MusicItemCollection<Song>?
    @State private var load: LibraryLoadState = .idle
    @State private var loadingMore = false

    private var title: String { recentlyAdded ? "Recently Added" : "Songs" }

    var body: some View {
        ScrollView {
            if songs.isEmpty {
                libraryPlaceholder(load, empty: "No songs in your library yet.").frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                        Button { Task { await music.playSongs(songs, startAt: idx) } } label: {
                            SongRow(song: song, isCurrent: music.currentSong?.id == song.id, isPlaying: music.isPlaying)
                        }
                        .buttonStyle(.plain)
                        .onAppear { Task { await loadMore(after: song) } }
                    }
                    if loadingMore { ProgressView().padding(.vertical, Spacing.sm) }
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            }
        }
        .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .appleMusicAttributed()
        .task { if load == .idle { await initialLoad() } }
    }

    private func initialLoad() async {
        load = .loading
        do {
            let batch = try await music.librarySongs(limit: 50, recentlyAdded: recentlyAdded)
            songs = Array(batch)
            cursor = batch
            load = .loaded
        } catch {
            load = .failed
        }
    }

    private func loadMore(after song: Song) async {
        guard !loadingMore, song.id == songs.last?.id,
              let c = cursor, c.hasNextBatch else { return }
        loadingMore = true
        if let next = await music.loadMore(c) {
            songs.append(contentsOf: next)
            cursor = next
        }
        loadingMore = false
    }
}

// MARK: - Playlist / Album detail (tracks → play into the shared engine)

struct LibraryDetailView: View {
    enum Source {
        case playlist(Playlist)
        case album(Album)
    }
    let source: Source

    @State private var music = MusicKitManager.shared
    @State private var songs: [Song] = []
    @State private var load: LibraryLoadState = .idle

    // Album metadata, resolved for the Apple-style header (one extra catalog fetch).
    @State private var detailedAlbum: Album?
    @State private var resolvedArtist: Artist?
    @State private var notesExpanded = false

    // Whole album / playlist add-to-library state for the header control.
    private enum AddState { case idle, adding, added, failed }
    @State private var addState: AddState = .idle

    // Per-track add state, held HERE (not inside the row) so a tapped checkmark
    // survives the LazyVStack recycling rows as they scroll off and back on.
    @State private var trackAdd: [String: TrackAddPhase] = [:]

    private var isAlbum: Bool { if case .album = source { return true }; return false }

    private var title: String {
        switch source {
        case .playlist(let p): return p.name
        case .album(let a):    return a.title
        }
    }
    /// The accent-coloured line under the title — artist (album) or curator (playlist).
    private var accentSubtitle: String? {
        switch source {
        case .playlist(let p): return p.curatorName
        case .album(let a):    return a.artistName
        }
    }
    private var artwork: Artwork? {
        switch source {
        case .playlist(let p): return p.artwork
        case .album(let a):    return a.artwork
        }
    }
    private var artSize: CGFloat { min(UIScreen.main.bounds.width * 0.62, 300) }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                header
                tracks
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.sm)
        }
        .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { shareControl }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .appleMusicAttributed()
        .task { if load == .idle { await loadEverything() } }
    }

    // MARK: Header — artwork · title · artist · meta · controls · notes

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            artworkView
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
                .padding(.top, Spacing.xs)

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.labelPrimary)
                    .multilineTextAlignment(.center).lineLimit(2)
                artistLine
                if metaText != nil || losslessBadgeText != nil { metaLine(metaText ?? "") }
            }
            .padding(.horizontal, Spacing.sm)

            controls.padding(.top, Spacing.xs)

            if let notes = editorialText {
                Text(notes)
                    .font(.mtrxFootnote)
                    .foregroundStyle(Color.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(notesExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { notesExpanded.toggle() } }
                    .padding(.top, Spacing.xs)
            }
        }
    }

    @ViewBuilder private var artworkView: some View {
        if let artwork {
            ArtworkImage(artwork, width: artSize, height: artSize)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.surfaceOverlay)
                .overlay(Image(systemName: "music.note").font(.system(size: 54)).foregroundStyle(Color.labelTertiary))
        }
    }

    @ViewBuilder private var artistLine: some View {
        if let artist = resolvedArtist {
            NavigationLink { LibraryArtistDetailView(artist: artist) } label: {
                Text(accentSubtitle ?? artist.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentPrimary).lineLimit(1)
            }
            .buttonStyle(.plain)
        } else if let sub = accentSubtitle, !sub.isEmpty {
            Text(sub).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentPrimary).lineLimit(1)
        }
    }

    private func metaLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            if !text.isEmpty {
                Text(text)
                    .font(.mtrxFootnote)
                    .foregroundStyle(Color.labelTertiary)
            }
            if let badge = losslessBadgeText {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.labelQuaternary, lineWidth: 1)
                    )
            }
        }
        .lineLimit(1)
    }

    // Genre · Year (album) / "N songs" (playlist)
    private var metaText: String? {
        if isAlbum {
            var parts: [String] = []
            if let g = detailedAlbum?.genreNames.first, !g.isEmpty { parts.append(g) }
            if let y = releaseYear { parts.append(y) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        } else {
            return songs.isEmpty ? nil : "\(songs.count) song\(songs.count == 1 ? "" : "s")"
        }
    }
    private var releaseYear: String? {
        guard let date = detailedAlbum?.releaseDate else { return nil }
        return Calendar.current.dateComponents([.year], from: date).year.map(String.init)
    }
    /// Apple's lossless wordmark, distinguishing Hi-Res Lossless like Apple Music does.
    private var losslessBadgeText: String? {
        guard let variants = detailedAlbum?.audioVariants else { return nil }
        if variants.contains(.highResolutionLossless) { return "Hi-Res Lossless" }
        if variants.contains(.lossless) { return "Lossless" }
        return nil
    }
    private var editorialText: String? {
        let notes = detailedAlbum?.editorialNotes
        let text = (notes?.standard ?? notes?.short)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    // MARK: Controls — Shuffle (circle) · Play (white pill) · Add (circle)

    private var controls: some View {
        HStack(spacing: Spacing.md) {
            Button { Task { await playShuffled() } } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(songs.isEmpty ? Color.labelTertiary : Color.labelPrimary)
                    .frame(width: 52, height: 52)
                    .background(Color.labelQuaternary.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain).disabled(songs.isEmpty).accessibilityLabel("Shuffle")

            Button { Task { await music.playSongs(songs, startAt: 0) } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Play").fontWeight(.semibold)
                }
                .font(.system(size: 18))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.white, in: Capsule())
                .opacity(songs.isEmpty ? 0.5 : 1)
            }
            .buttonStyle(.plain).disabled(songs.isEmpty).accessibilityLabel("Play")

            Button { triggerAdd() } label: {
                Group {
                    switch addState {
                    case .adding: ProgressView()
                    case .added:  Image(systemName: "checkmark")
                    case .failed: Image(systemName: "exclamationmark")
                    case .idle:   Image(systemName: "plus")
                    }
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(addState == .added ? Color.statusSuccess :
                                 addState == .failed ? Color.statusWarning : Color.labelPrimary)
                .frame(width: 52, height: 52)
                .background(Color.labelQuaternary.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(songs.isEmpty || addState == .adding || addState == .added)
            .accessibilityLabel(addState == .added ? "Added to Library" : "Add to Library")
        }
    }

    // MARK: Tracks — Apple-style numbered rows (no thumbnails)

    @ViewBuilder private var tracks: some View {
        if songs.isEmpty {
            libraryPlaceholder(load, empty: "No playable songs here.")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                    AlbumTrackRow(
                        number: idx + 1,
                        song: song,
                        isCurrent: music.currentSong?.id == song.id,
                        isPlaying: music.isPlaying,
                        addPhase: trackAdd[song.id.rawValue] ?? .idle,
                        onPlay: { Task { await music.playSongs(songs, startAt: idx) } },
                        onAdd:  { addTrack(song) }
                    )
                    if idx < songs.count - 1 {
                        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 38)
                    }
                }
            }
        }
    }

    // MARK: Toolbar — Share · More

    @ViewBuilder private var shareControl: some View {
        if let url = shareURL {
            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share")
        } else {
            ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button { Task { await music.playSongs(songs, startAt: 0) } } label: { Label("Play", systemImage: "play.fill") }
            Button { Task { await playShuffled() } } label: { Label("Shuffle", systemImage: "shuffle") }
            Button { triggerAdd() } label: { Label("Add to Library", systemImage: "plus") }
            shareControl
        } label: {
            Image(systemName: "ellipsis")
        }
        .disabled(songs.isEmpty)
        .accessibilityLabel("More")
    }

    private var shareURL: URL? {
        switch source {
        case .album(let a):    return a.url
        case .playlist(let p): return p.url
        }
    }
    private var shareText: String {
        accentSubtitle.map { "\(title) — \($0)" } ?? title
    }

    // MARK: Actions / loading

    private func playShuffled() async {
        guard !songs.isEmpty else { return }
        await music.playSongs(songs.shuffled(), startAt: 0)
    }

    private func triggerAdd() {
        guard addState == .idle || addState == .failed else { return }
        MtrxHaptics.impact(.light)
        addState = .adding
        Task {
            let outcome: MusicKitManager.AddOutcome
            switch source {
            case .album(let a):    outcome = await music.addToLibrary(album: a)
            case .playlist(let p): outcome = await music.addToLibrary(playlist: p)
            }
            addState = (outcome == .added) ? .added : .failed
        }
    }

    private func addTrack(_ song: Song) {
        let key = song.id.rawValue
        let cur = trackAdd[key] ?? .idle
        guard cur == .idle || cur == .failed else { return }
        MtrxHaptics.impact(.light)
        trackAdd[key] = .adding
        Task {
            let outcome = await music.addToLibrary(song)
            trackAdd[key] = (outcome == .added) ? .added : .failed
        }
    }

    private func loadEverything() async {
        load = .loading
        do {
            switch source {
            case .playlist(let p):
                songs = try await music.songs(of: p)
            case .album(let a):
                let detail = try await music.loadAlbumDetail(a)
                songs = detail.songs
                detailedAlbum = detail.album
                resolvedArtist = detail.album.artists?.first
            }
            load = .loaded
        } catch {
            load = .failed
        }
    }
}

// MARK: - Apple-style album/playlist track row

/// Add-to-library state for one track. Owned by LibraryDetailView (keyed by song
/// id) rather than the row, so a tapped checkmark persists while the LazyVStack
/// recycles rows during scrolling.
enum TrackAddPhase { case idle, adding, added, failed }

/// One track row in the album/playlist view: number (or a now-playing waveform),
/// the title with an Explicit badge, a real add-to-library control, and a More
/// menu. Tapping the row plays from this track. No thumbnail — the album art
/// already sits in the header, exactly like the Apple Music album screen.
struct AlbumTrackRow: View {
    let number: Int
    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool
    let addPhase: TrackAddPhase
    let onPlay: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onPlay) {
                HStack(spacing: Spacing.sm) {
                    leading.frame(width: 26)
                    HStack(spacing: 6) {
                        Text(song.title)
                            .font(.mtrxCallout)
                            .foregroundStyle(isCurrent ? Color.accentPrimary : Color.labelPrimary)
                            .lineLimit(1)
                        if song.contentRating == .explicit { explicitBadge }
                    }
                    Spacer(minLength: Spacing.sm)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            addButton
            menu
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number). \(song.title)")
        .accessibilityHint("Plays this track")
    }

    @ViewBuilder private var leading: some View {
        if isCurrent && isPlaying {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentPrimary)
                .symbolEffect(.variableColor, isActive: true)
        } else {
            Text("\(number)")
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(Color.labelTertiary)
        }
    }

    private var explicitBadge: some View {
        Text("E")
            .font(.system(size: 9, weight: .heavy)).foregroundStyle(Color.labelSecondary)
            .frame(width: 15, height: 15)
            .background(Color.labelQuaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var addButton: some View {
        Button { onAdd() } label: {
            Group {
                switch addPhase {
                case .idle:   Image(systemName: "plus.circle")
                case .adding: ProgressView()
                case .added:  Image(systemName: "checkmark.circle.fill")
                case .failed: Image(systemName: "exclamationmark.circle")
                }
            }
            .font(.system(size: 18))
            .foregroundStyle(addPhase == .added ? Color.statusSuccess :
                             addPhase == .failed ? Color.statusWarning : Color.labelSecondary)
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(addPhase == .adding || addPhase == .added)
        .accessibilityLabel(addPhase == .added ? "Added to Library" : "Add to Library")
    }

    private var menu: some View {
        Menu {
            Button(action: onPlay) { Label("Play", systemImage: "play.fill") }
            Button(action: onAdd) { Label("Add to Library", systemImage: "plus") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.labelTertiary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }
}

// MARK: - Artist detail (the artist's albums in your library)

struct LibraryArtistDetailView: View {
    let artist: Artist

    @State private var music = MusicKitManager.shared
    @State private var albums: [Album] = []
    @State private var load: LibraryLoadState = .idle

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                VStack(spacing: Spacing.sm) {
                    Group {
                        if let art = artist.artwork {
                            ArtworkImage(art, width: 140, height: 140)
                        } else {
                            Circle().fill(Color.surfaceOverlay).frame(width: 140, height: 140)
                                .overlay(Image(systemName: "music.mic").font(.system(size: 40)).foregroundStyle(Color.labelTertiary))
                        }
                    }
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())

                    Text(artist.name).font(.mtrxTitle3).foregroundStyle(Color.labelPrimary)
                        .multilineTextAlignment(.center)
                }

                if albums.isEmpty {
                    libraryPlaceholder(load, empty: "No albums available for this artist.")
                } else {
                    LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("Albums").font(.mtrxTitle3).foregroundStyle(Color.labelPrimary)
                            Spacer()
                        }
                        ForEach(albums, id: \.id) { album in
                            NavigationLink { LibraryDetailView(source: .album(album)) } label: {
                                LibraryItemRow(artwork: album.artwork, title: album.title, subtitle: album.artistName)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        }
        .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .appleMusicAttributed()
        .task { if load == .idle { await loadAlbums() } }
    }

    private func loadAlbums() async {
        load = .loading
        do {
            albums = Array(try await music.albums(of: artist))
            load = .loaded
        } catch {
            load = .failed
        }
    }
}

// MARK: - Shared section header

func librarySectionHeader(_ title: String) -> some View {
    HStack {
        Text(title).font(.mtrxTitle3).foregroundStyle(Color.labelPrimary)
        Spacer()
    }
    .padding(.top, Spacing.sm)
}

// MARK: - Add to Library button (real MusicKit write, honest feedback)

/// Adds a catalog item to the user's Apple Music library via MusicKitManager.
/// It only shows the "added" checkmark after the real write succeeds, and an
/// honest warning glyph if it fails — never a fake confirmation.
struct AddToLibraryButton: View {
    let add: () async -> MusicKitManager.AddOutcome

    enum Phase { case idle, adding, added, failed }
    @State private var phase: Phase = .idle

    var body: some View {
        Button {
            guard phase == .idle || phase == .failed else { return }
            MtrxHaptics.impact(.light)
            phase = .adding
            Task { phase = (await add()) == .added ? .added : .failed }
        } label: {
            Group {
                switch phase {
                case .idle:   Image(systemName: "plus.circle")
                case .adding: ProgressView()
                case .added:  Image(systemName: "checkmark.circle.fill")
                case .failed: Image(systemName: "exclamationmark.circle")
                }
            }
            .font(.system(size: 22))
            .foregroundStyle(iconColor)
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(phase == .adding || phase == .added)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconColor: Color {
        switch phase {
        case .added:  return Color.statusSuccess
        case .failed: return Color.statusWarning
        default:      return Color.accentPrimary
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle:   return "Add to library"
        case .adding: return "Adding to library"
        case .added:  return "Added to library"
        case .failed: return "Couldn't add to library, tap to retry"
        }
    }
}

// MARK: - Apple Music catalog search (find, play, add)

struct MusicSearchView: View {
    @State private var music = MusicKitManager.shared
    @State private var term = ""
    @State private var results = MusicKitManager.CatalogSearchResults()
    @State private var state: LibraryLoadState = .idle

    private var trimmed: String { term.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            if trimmed.count < 2 {
                promptState
            } else if results.isEmpty {
                searchPlaceholder
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                    if !results.songs.isEmpty {
                        librarySectionHeader("Songs")
                        ForEach(Array(results.songs.enumerated()), id: \.element.id) { idx, song in
                            HStack(spacing: Spacing.sm) {
                                Button { Task { await music.playSongs(Array(results.songs), startAt: idx) } } label: {
                                    SongRow(song: song, isCurrent: music.currentSong?.id == song.id, isPlaying: music.isPlaying)
                                }
                                .buttonStyle(.plain)
                                AddToLibraryButton { await music.addToLibrary(song) }
                            }
                        }
                    }
                    if !results.albums.isEmpty {
                        librarySectionHeader("Albums")
                        ForEach(results.albums, id: \.id) { album in
                            HStack(spacing: Spacing.sm) {
                                NavigationLink { LibraryDetailView(source: .album(album)) } label: {
                                    LibraryItemRow(artwork: album.artwork, title: album.title, subtitle: album.artistName)
                                }
                                .buttonStyle(.plain)
                                AddToLibraryButton { await music.addToLibrary(album: album) }
                            }
                        }
                    }
                    if !results.artists.isEmpty {
                        librarySectionHeader("Artists")
                        ForEach(results.artists, id: \.id) { artist in
                            NavigationLink { LibraryArtistDetailView(artist: artist) } label: {
                                LibraryItemRow(artwork: artist.artwork, title: artist.name, subtitle: nil, circular: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !results.playlists.isEmpty {
                        librarySectionHeader("Playlists")
                        ForEach(results.playlists, id: \.id) { playlist in
                            HStack(spacing: Spacing.sm) {
                                NavigationLink { LibraryDetailView(source: .playlist(playlist)) } label: {
                                    LibraryItemRow(artwork: playlist.artwork, title: playlist.name, subtitle: playlist.curatorName)
                                }
                                .buttonStyle(.plain)
                                AddToLibraryButton { await music.addToLibrary(playlist: playlist) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            }
        }
        .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Songs, albums, artists, playlists")
        .appleMusicAttributed()
        // Debounced search: .task(id:) cancels the in-flight search whenever the
        // term changes, so we only hit the catalog after the user pauses typing.
        .task(id: term) { await runSearch() }
    }

    private var promptState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass").font(.system(size: 48)).foregroundStyle(Color.labelTertiary)
            Text("Search Apple Music").font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
            Text("Find songs, albums, artists and playlists to play or add to your library.")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Spacing.lg)
        }
        .frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
    }

    @ViewBuilder
    private var searchPlaceholder: some View {
        switch state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
        case .failed:
            Text("Couldn't search Apple Music. Make sure Apple Music access is allowed and the app's MusicKit capability is enabled.")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, Spacing.xxl).padding(.horizontal, Spacing.lg)
        case .loaded:
            Text("No results for “\(trimmed)”.")
                .font(.mtrxCallout).foregroundStyle(Color.labelTertiary)
                .frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
        }
    }

    private func runSearch() async {
        let q = trimmed
        guard q.count >= 2 else {
            results = MusicKitManager.CatalogSearchResults()
            state = .idle
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        // Drop the previous query's hits before fetching so the honest loading
        // spinner shows, and a failed reload falls through to the failed state
        // instead of leaving stale results that look like the current query.
        results = MusicKitManager.CatalogSearchResults()
        state = .loading
        do {
            let r = try await music.searchCatalog(q)
            if Task.isCancelled { return }
            results = r
            state = .loaded
        } catch {
            if Task.isCancelled { return }
            state = .failed
        }
    }
}

#endif
