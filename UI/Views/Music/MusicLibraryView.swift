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

    private var title: String {
        switch source {
        case .playlist(let p): return p.name
        case .album(let a):    return a.title
        }
    }
    private var subtitle: String? {
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

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                header
                if songs.isEmpty {
                    libraryPlaceholder(load, empty: "No playable songs here.")
                } else {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                            Button { Task { await music.playSongs(songs, startAt: idx) } } label: {
                                SongRow(song: song, isCurrent: music.currentSong?.id == song.id, isPlaying: music.isPlaying)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        }
        .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .appleMusicAttributed()
        .task { if load == .idle { await loadSongs() } }
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            Group {
                if let artwork {
                    ArtworkImage(artwork, width: 200, height: 200)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.surfaceOverlay)
                        .frame(width: 200, height: 200)
                        .overlay(Image(systemName: "music.note").font(.system(size: 44)).foregroundStyle(Color.labelTertiary))
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title).font(.mtrxTitle3).foregroundStyle(Color.labelPrimary)
                .multilineTextAlignment(.center).lineLimit(2)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.mtrxCallout).foregroundStyle(Color.labelSecondary).lineLimit(1)
            }

            HStack(spacing: Spacing.sm) {
                Button { Task { await music.playSongs(songs, startAt: 0) } } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular))
                .disabled(songs.isEmpty)

                Button { Task { await playShuffled() } } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular))
                .disabled(songs.isEmpty)
            }
            .padding(.top, Spacing.xs)
        }
    }

    private func playShuffled() async {
        guard !songs.isEmpty else { return }
        await music.playSongs(songs.shuffled(), startAt: 0)
    }

    private func loadSongs() async {
        load = .loading
        do {
            switch source {
            case .playlist(let p): songs = try await music.songs(of: p)
            case .album(let a):    songs = try await music.songs(of: a)
            }
            load = .loaded
        } catch {
            load = .failed
        }
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
                    libraryPlaceholder(load, empty: "No albums from this artist in your library.")
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

#endif
