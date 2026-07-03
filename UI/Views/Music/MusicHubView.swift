// MusicHubView.swift
// MTRX — Apple Music hub (MusicKit), a five-tab player
//
// MTRX's own five-tab music experience over MusicKit — New, Radio, Home,
// Library, Search — laid out in the familiar Apple Music shape but built from
// MTRX's design system and clearly attributed to Apple Music (per Apple Music
// Identity Guidelines: it is MTRX's player, not a copy of the Apple Music app).
//
// Honesty discipline carried over from the rest of the music layer:
//   • All content comes from real MusicKit responses (chart, library, search,
//     recently played) — never fabricated lists or fake "now playing".
//   • Genre tiles and Radio "stations" use MTRX's OWN gradient artwork, not
//     Apple's editorial images, and play real shuffled catalog queues.
//   • Lyrics stay honestly unavailable (see LyricsView); no licensed text.
// Everything routes through the single MusicKitManager (one authorization, one
// playback engine) — there is no second MusicKit path.

import SwiftUI
import Observation
#if canImport(MusicKit)
import MusicKit
#endif

// MARK: - Hub container (the five tabs)

struct MusicHubView: View {
    @State private var music = MusicKitManager.shared
    @State private var showNowPlaying = false
    @Environment(\.dismiss) private var dismiss

#if canImport(MusicKit)
    enum Tab: Hashable { case new, radio, home, library, search }
    // Home sits in the MIDDLE; Library is second-from-right; Search is far-right —
    // New and Radio fill the two left slots. Default selection is Home (middle).
    @State private var selection: Tab = .home

    var body: some View {
        Group {
            switch music.state {
            case .connectedFull, .connectedPreview: tabs
            case .notConnected:                      MusicHubGate(kind: .connect)
            case .denied:                            MusicHubGate(kind: .denied)
            case .unavailable:                       MusicHubGate(kind: .unavailable)
            }
        }
        .onAppear { music.refreshState() }
        .sheet(isPresented: $showNowPlaying) { NowPlayingView() }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            MusicNewTab(openNowPlaying: openNowPlaying, onClose: { dismiss() })
                .tabItem { Label("New", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.new)
            MusicRadioTab(openNowPlaying: openNowPlaying, onClose: { dismiss() })
                .tabItem { Label("Radio", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.radio)
            MusicHomeTab(openNowPlaying: openNowPlaying, onClose: { dismiss() })
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            MusicLibraryTab(openNowPlaying: openNowPlaying, onClose: { dismiss() })
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
                .tag(Tab.library)
            MusicSearchTab(openNowPlaying: openNowPlaying, onClose: { dismiss() })
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)
        }
        .tint(Color.accentPrimary)
    }

    private func openNowPlaying() { showNowPlaying = true }
#else
    var body: some View { MusicHubGate(kind: .unavailable) }
#endif
}

// MARK: - Connection gates (connect / denied / unavailable)

struct MusicHubGate: View {
    enum Kind { case connect, denied, unavailable }
    let kind: Kind

    @State private var music = MusicKitManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)
                content
            }
            .navigationTitle("Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { AppleMusicBadge() }
                ToolbarItem(placement: .topBarTrailing) { CloseButton { dismiss() } }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .connect:
            VStack(spacing: Spacing.lg) {
                Spacer()
                Image(systemName: "music.note.list").font(.system(size: 56)).foregroundStyle(Color.accentPrimary)
                Text("Connect Apple Music").font(.mtrxTitle2).foregroundStyle(Color.labelPrimary)
                Text("Listen right inside MTRX. This is a separate Apple Music permission — it's not part of signing in.")
                    .font(.mtrxBody).foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, Spacing.lg)
                Button { Task { await music.connect() } } label: {
                    HStack {
                        if music.isWorking { ProgressView().tint(.white) }
                        Text("Connect Apple Music")
                    }
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
                .disabled(music.isWorking)
                .padding(.horizontal, Spacing.lg)
                Spacer()
            }
        case .denied:
            VStack(spacing: Spacing.md) {
                Spacer()
                Image(systemName: "music.note").font(.system(size: 48)).foregroundStyle(Color.labelTertiary)
                Text("Apple Music isn't connected").font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
                Text("You declined Apple Music access. You can enable it in Settings if you'd like to listen here.")
                    .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, Spacing.lg)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: { Text("Open Settings") }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular))
                Spacer()
            }
        case .unavailable:
            VStack(spacing: Spacing.md) {
                Spacer()
                Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(Color.labelTertiary)
                Text("Apple Music is unavailable").font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
                Text("Apple Music can't be reached on this device right now.")
                    .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, Spacing.lg)
                Spacer()
            }
        }
    }
}

// MARK: - Shared small pieces

/// The toolbar close (X) used on every hub screen — this player is a modal sheet.
struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: Symbols.close)
                .accessibilityLabel("Close")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.labelPrimary)
        }
    }
}

#if canImport(MusicKit)

/// Apple Music attribution footer placed at the bottom of each tab's scroll.
private struct MusicAttributionFooter: View {
    var body: some View {
        AppleMusicBadge()
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)
    }
}

/// The floating oval mini-player bubble above the tab bar on every tab — the
/// product owner's chosen shape (liquid-glass pill with side gutters, NOT the
/// full-width Apple Music bar). The whole bubble is one hit target: a tap
/// anywhere on it that isn't a transport button opens the full player, and no
/// touch on the bubble ever falls through to the content underneath; the
/// transport buttons carry full-height 44pt targets and act without leaving
/// the tab.
struct MusicMiniPlayer: View {
    @State private var music = MusicKitManager.shared
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                Group {
                    if let art = music.nowPlayingArtwork {
                        ArtworkImage(art, width: 40, height: 40)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Color.surfaceOverlay).frame(width: 40, height: 40)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(music.nowPlayingTitle ?? "").font(.mtrxCaptionBold).foregroundStyle(Color.labelPrimary).lineLimit(1)
                    Text(music.nowPlayingArtist ?? "").font(.mtrxCaption2).foregroundStyle(Color.labelSecondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { music.skipPrevious() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.labelPrimary).accessibilityLabel("Previous")
                        .frame(width: 38, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { music.togglePlayPause() } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.labelPrimary)
                        .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                        .frame(width: 40, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { music.skipNext() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.labelPrimary).accessibilityLabel("Next")
                        .frame(width: 38, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            // The whole bubble is a single hit target — no dead spots between
            // the artwork, text, and transports that let taps fall through.
            .contentShape(Rectangle())
            .mtrxLiquidGlass(in: RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full player")
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.xs)
    }
}

/// Common chrome for a tab: gradient background, large title, close button, and
/// the persistent mini-player pinned above the tab bar.
struct MusicTabScaffold<Content: View>: View {
    let title: String
    let openNowPlaying: () -> Void
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var music = MusicKitManager.shared

    var body: some View {
        NavigationStack {
            content()
                .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { CloseButton(action: onClose) }
                }
        }
        .safeAreaInset(edge: .bottom) {
            if music.hasNowPlaying { MusicMiniPlayer(onTap: openNowPlaying) }
        }
    }
}

/// The "E" explicit badge, reused by tiles and grids.
struct MusicExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 9, weight: .heavy)).foregroundStyle(Color.labelSecondary)
            .frame(width: 15, height: 15)
            .background(Color.labelQuaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .accessibilityHidden(true)
    }
}

private func sectionTitle(_ t: String) -> some View {
    Text(t).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.labelPrimary)
}

// MARK: - Genres (MTRX's own gradient artwork — not Apple's editorial images)

struct MusicGenre: Identifiable {
    let name: String
    let term: String
    let colors: [Color]
    var id: String { name }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let all: [MusicGenre] = [
        MusicGenre(name: "Summertime Sounds", term: "summer hits",
                   colors: [Color(red: 1.00, green: 0.62, blue: 0.24), Color(red: 0.62, green: 0.30, blue: 0.86)]),
        MusicGenre(name: "R&B", term: "r&b",
                   colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.36, green: 0.24, blue: 0.70)]),
        MusicGenre(name: "Hip-Hop", term: "hip hop",
                   colors: [Color(red: 0.20, green: 0.45, blue: 0.95), Color(red: 0.10, green: 0.20, blue: 0.55)]),
        MusicGenre(name: "Hits", term: "top hits",
                   colors: [Color(red: 0.95, green: 0.78, blue: 0.20), Color(red: 0.85, green: 0.45, blue: 0.10)]),
        MusicGenre(name: "Pop", term: "pop",
                   colors: [Color(red: 0.98, green: 0.45, blue: 0.66), Color(red: 0.80, green: 0.25, blue: 0.55)]),
        MusicGenre(name: "Country", term: "country",
                   colors: [Color(red: 0.92, green: 0.62, blue: 0.18), Color(red: 0.70, green: 0.38, blue: 0.12)]),
        MusicGenre(name: "Dance", term: "dance electronic",
                   colors: [Color(red: 0.18, green: 0.78, blue: 0.55), Color(red: 0.10, green: 0.50, blue: 0.42)]),
        MusicGenre(name: "Rock", term: "rock",
                   colors: [Color(red: 0.95, green: 0.42, blue: 0.30), Color(red: 0.65, green: 0.20, blue: 0.22)]),
        MusicGenre(name: "Latin", term: "latin",
                   colors: [Color(red: 0.98, green: 0.35, blue: 0.55), Color(red: 0.72, green: 0.18, blue: 0.62)]),
        MusicGenre(name: "Jazz", term: "jazz",
                   colors: [Color(red: 0.36, green: 0.50, blue: 0.78), Color(red: 0.18, green: 0.26, blue: 0.48)]),
        MusicGenre(name: "Classical", term: "classical",
                   colors: [Color(red: 0.55, green: 0.58, blue: 0.66), Color(red: 0.28, green: 0.30, blue: 0.38)]),
        MusicGenre(name: "K-Pop", term: "k-pop",
                   colors: [Color(red: 0.66, green: 0.40, blue: 0.96), Color(red: 0.96, green: 0.45, blue: 0.72)]),
        MusicGenre(name: "Afrobeats", term: "afrobeats",
                   colors: [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.55, green: 0.70, blue: 0.20)]),
        MusicGenre(name: "Workout", term: "workout",
                   colors: [Color(red: 0.10, green: 0.62, blue: 0.92), Color(red: 0.06, green: 0.32, blue: 0.62)]),
    ]
}

/// A colorful genre tile, like the Apple Music Search grid — MTRX's own gradient.
private struct GenreTile: View {
    let genre: MusicGenre
    var subtitle: String? = nil
    var glyph: String? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            genre.gradient
            if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.22))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(genre.name)
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .padding(12)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Search tab (carbon copy of Apple Music Search)

struct MusicSearchTab: View {
    let openNowPlaying: () -> Void
    let onClose: () -> Void

    @State private var music = MusicKitManager.shared
    @State private var term = ""
    @State private var results = MusicKitManager.CatalogSearchResults()
    @State private var state: LibraryLoadState = .idle
    @FocusState private var fieldFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)]
    private var trimmed: String { term.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { trimmed.count >= 2 }

    var body: some View {
        MusicTabScaffold(title: "Search", openNowPlaying: openNowPlaying, onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    searchField
                    if searching {
                        results.isEmpty ? AnyView(searchPlaceholder) : AnyView(resultsList)
                    } else {
                        browseGrid
                    }
                    MusicAttributionFooter()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .task(id: term) { await runSearch() }
    }

    // The rounded search field with a leading glass icon and a trailing mic, like
    // Apple Music. The mic focuses the field (no fake voice recognition).
    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.labelSecondary)
            TextField("Artists, Songs, Lyrics, and More", text: $term)
                .focused($fieldFocused)
                .submitLabel(.search)
                .foregroundStyle(Color.labelPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !term.isEmpty {
                Button { term = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain).accessibilityLabel("Clear search")
            } else {
                Button { fieldFocused = true } label: {
                    Image(systemName: "mic.fill").foregroundStyle(Color.labelSecondary)
                }
                .buttonStyle(.plain).accessibilityLabel("Search")
            }
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 11)
        .background(Color.surfaceOverlay, in: Capsule())
    }

    private var browseGrid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.sm) {
            ForEach(MusicGenre.all) { genre in
                NavigationLink { MusicGenreView(genre: genre, openNowPlaying: openNowPlaying) } label: {
                    GenreTile(genre: genre)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // The live catalog results (songs / albums / artists / playlists).
    private var resultsList: some View {
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
    }

    @ViewBuilder private var searchPlaceholder: some View {
        switch state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
        case .failed:
            Text("Couldn't search Apple Music. Make sure Apple Music access is allowed and the app's MusicKit capability is enabled.")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, Spacing.xxl).padding(.horizontal, Spacing.lg)
        case .loaded:
            Text("No results for \u{201C}\(trimmed)\u{201D}.")
                .font(.mtrxCallout).foregroundStyle(Color.labelTertiary)
                .frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
        }
    }

    private func runSearch() async {
        let q = trimmed
        guard q.count >= 2 else {
            results = MusicKitManager.CatalogSearchResults(); state = .idle; return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        results = MusicKitManager.CatalogSearchResults()
        state = .loading
        do {
            let r = try await music.searchCatalog(q)
            if Task.isCancelled { return }
            results = r; state = .loaded
        } catch {
            if Task.isCancelled { return }
            state = .failed
        }
    }
}

// MARK: - Genre browse (tapping a Search tile) — real catalog content + a station

struct MusicGenreView: View {
    let genre: MusicGenre
    let openNowPlaying: () -> Void

    @State private var music = MusicKitManager.shared
    @State private var results = MusicKitManager.CatalogSearchResults()
    @State private var load: LibraryLoadState = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                if results.songs.isEmpty && results.albums.isEmpty {
                    libraryPlaceholder(load, empty: "Nothing to show for \(genre.name) right now.")
                } else {
                    if !results.songs.isEmpty {
                        librarySectionHeader("Songs")
                        LazyVStack(spacing: Spacing.xs) {
                            ForEach(Array(results.songs.enumerated()), id: \.element.id) { idx, song in
                                Button { Task { await music.playSongs(Array(results.songs), startAt: idx) } } label: {
                                    SongRow(song: song, isCurrent: music.currentSong?.id == song.id, isPlaying: music.isPlaying)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !results.albums.isEmpty {
                        librarySectionHeader("Albums")
                        LazyVStack(spacing: Spacing.xs) {
                            ForEach(results.albums, id: \.id) { album in
                                NavigationLink { LibraryDetailView(source: .album(album)) } label: {
                                    LibraryItemRow(artwork: album.artwork, title: album.title, subtitle: album.artistName)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                MusicAttributionFooter()
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        }
        .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
        .navigationTitle(genre.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if load == .idle { await loadGenre() } }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            genre.gradient
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Spacer()
                Text(genre.name).font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                HStack(spacing: Spacing.sm) {
                    Button { Task { await startStation(shuffled: false) } } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular))
                    Button { Task { await startStation(shuffled: true) } } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular))
                }
            }
            .padding(Spacing.md)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func startStation(shuffled: Bool) async {
        let songs = Array(results.songs)
        guard !songs.isEmpty else {
            await music.playStation(term: genre.term); openNowPlaying(); return
        }
        await music.playSongs(shuffled ? songs.shuffled() : songs, startAt: 0)
        openNowPlaying()
    }

    private func loadGenre() async {
        load = .loading
        do {
            results = try await music.searchCatalog(genre.term, limit: 25)
            load = .loaded
        } catch {
            load = .failed
        }
    }
}

// MARK: - Library tab (carbon copy of Apple Music Library)

struct MusicLibraryTab: View {
    let openNowPlaying: () -> Void
    let onClose: () -> Void

    @State private var music = MusicKitManager.shared
    @State private var recentAlbums: [Album] = []
    @State private var load: LibraryLoadState = .idle

    private let grid = [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)]

    var body: some View {
        MusicTabScaffold(title: "Library", openNowPlaying: openNowPlaying, onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    categoryList
                    recentlyAdded
                    MusicAttributionFooter()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }
            .task { if load == .idle { await loadRecent() } }
        }
    }

    // Playlists / Artists / Albums / Songs — "Recently Added" has its own dedicated
    // grid below, so it's excluded here to avoid a duplicate Recently Added surface.
    private var categoryRows: [LibraryCategory] {
        LibraryCategory.allCases.filter { $0 != .recentlyAdded }
    }

    private var categoryList: some View {
        VStack(spacing: 0) {
            ForEach(Array(categoryRows.enumerated()), id: \.element.id) { idx, category in
                NavigationLink { category.destination } label: {
                    MusicLibraryCategoryRow(category: category)
                }
                .buttonStyle(.plain)
                if idx < categoryRows.count - 1 {
                    Divider().overlay(Color.labelPrimary.opacity(0.08)).padding(.leading, 40)
                }
            }
        }
    }

    @ViewBuilder private var recentlyAdded: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Recently Added")
            if recentAlbums.isEmpty {
                libraryPlaceholder(load, empty: "Albums you add will show up here.").frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: grid, spacing: Spacing.md) {
                    ForEach(recentAlbums, id: \.id) { album in
                        NavigationLink { LibraryDetailView(source: .album(album)) } label: {
                            AlbumGridCell(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func loadRecent() async {
        load = .loading
        do {
            recentAlbums = Array(try await music.libraryAlbums(limit: 20, recentlyAdded: true))
            load = .loaded
        } catch {
            load = .failed
        }
    }
}

/// A 2-up album cell: large square artwork, title (+ explicit), artist.
private struct AlbumGridCell: View {
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let art = album.artwork {
                    ArtworkImage(art, width: 180, height: 180)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.surfaceOverlay)
                        .overlay(Image(systemName: "music.note").font(.system(size: 36)).foregroundStyle(Color.labelTertiary))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 4) {
                Text(album.title).font(.mtrxCaptionBold).foregroundStyle(Color.labelPrimary).lineLimit(1)
                if album.contentRating == .explicit { MusicExplicitBadge() }
            }
            Text(album.artistName).font(.mtrxCaption2).foregroundStyle(Color.labelSecondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Home tab (Top Picks + Recently Played)

struct MusicHomeTab: View {
    let openNowPlaying: () -> Void
    let onClose: () -> Void

    @State private var music = MusicKitManager.shared

    var body: some View {
        MusicTabScaffold(title: "Home", openNowPlaying: openNowPlaying, onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    topPicks
                    recentlyPlayed
                    MusicAttributionFooter()
                }
                .padding(.vertical, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }
        }
    }

    @ViewBuilder private var topPicks: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Top Picks for You").padding(.horizontal, Spacing.md)
            if music.chart.isEmpty {
                chartPlaceholder.padding(.horizontal, Spacing.md)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(Array(music.chart.prefix(10)), id: \.id) { song in
                            Button { Task { await music.play(song) } } label: {
                                FeaturedSongCard(song: song, eyebrow: "TOP PICK")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
        }
    }

    @ViewBuilder private var recentlyPlayed: some View {
        if !music.recentlyPlayed.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionTitle("Recently Played").padding(.horizontal, Spacing.md)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        ForEach(Array(music.recentlyPlayed.enumerated()), id: \.element.id) { idx, song in
                            Button { Task { await music.playSongs(Array(music.recentlyPlayed), startAt: idx) } } label: {
                                SongSquareTile(song: song)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
        }
    }

    @ViewBuilder private var chartPlaceholder: some View {
        switch music.chartLoad {
        case .loading, .idle:
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
        case .failed:
            Text("Couldn't load Apple Music content. The app's MusicKit capability may not be enabled yet.")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        case .loaded:
            Text("No picks available right now.").font(.mtrxCallout).foregroundStyle(Color.labelTertiary)
        }
    }
}

/// A large featured card for a song (Home Top Picks).
private struct FeaturedSongCard: View {
    let song: Song
    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let art = song.artwork {
                        ArtworkImage(art, width: 280, height: 280)
                    } else {
                        RoundedRectangle(cornerRadius: 14).fill(Color.surfaceOverlay)
                            .frame(width: 280, height: 280)
                            .overlay(Image(systemName: "music.note").font(.system(size: 56)).foregroundStyle(Color.labelTertiary))
                    }
                }
                .frame(width: 280, height: 280)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .frame(width: 280, height: 280)
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 4) {
                        Text(song.title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        if song.contentRating == .explicit { MusicExplicitBadge() }
                    }
                    Text(song.artistName).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                .padding(14)
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(width: 280)
    }
}

/// A small square tile for a song (Home Recently Played).
private struct SongSquareTile: View {
    let song: Song
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let art = song.artwork {
                    ArtworkImage(art, width: 150, height: 150)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.surfaceOverlay).frame(width: 150, height: 150)
                        .overlay(Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(Color.labelTertiary))
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(song.title).font(.mtrxCaptionBold).foregroundStyle(Color.labelPrimary).lineLimit(1).frame(width: 150, alignment: .leading)
            Text(song.artistName).font(.mtrxCaption2).foregroundStyle(Color.labelSecondary).lineLimit(1).frame(width: 150, alignment: .leading)
        }
    }
}

// MARK: - New tab (catalog charts — top songs + top albums)

struct MusicNewTab: View {
    let openNowPlaying: () -> Void
    let onClose: () -> Void

    @State private var music = MusicKitManager.shared

    var body: some View {
        MusicTabScaffold(title: "New", openNowPlaying: openNowPlaying, onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if music.chart.isEmpty {
                        placeholder.padding(.horizontal, Spacing.md).padding(.top, Spacing.xl)
                    } else {
                        playBar.padding(.horizontal, Spacing.md)
                        featured
                        topAlbums
                        topSongs.padding(.horizontal, Spacing.md)
                    }
                    MusicAttributionFooter()
                }
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }
        }
    }

    private var playBar: some View {
        HStack(spacing: Spacing.sm) {
            Button { Task { await music.playSongs(Array(music.chart), startAt: 0); openNowPlaying() } } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
            Button { Task { await music.playSongs(Array(music.chart).shuffled(), startAt: 0); openNowPlaying() } } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular, fullWidth: true))
        }
    }

    @ViewBuilder private var featured: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Today's Hits").padding(.horizontal, Spacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(Array(music.chart.prefix(8)), id: \.id) { song in
                        Button { Task { await music.play(song) } } label: {
                            FeaturedSongCard(song: song, eyebrow: "TOP SONG")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    @ViewBuilder private var topAlbums: some View {
        if !music.albumChart.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionTitle("Top Albums").padding(.horizontal, Spacing.md)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        ForEach(music.albumChart, id: \.id) { album in
                            NavigationLink { LibraryDetailView(source: .album(album)) } label: {
                                AlbumSquareTile(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
        }
    }

    private var topSongs: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle("Top Songs")
            LazyVStack(spacing: Spacing.xs) {
                ForEach(Array(music.chart.enumerated()), id: \.element.id) { idx, song in
                    Button { Task { await music.playSongs(Array(music.chart), startAt: idx) } } label: {
                        SongRow(song: song, isCurrent: music.currentSong?.id == song.id, isPlaying: music.isPlaying)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        switch music.chartLoad {
        case .loading, .idle:
            ProgressView().frame(maxWidth: .infinity)
        case .failed:
            Text("Couldn't load Apple Music content. The app's MusicKit capability may not be enabled yet.")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        case .loaded:
            Text("No songs available right now.").font(.mtrxCallout).foregroundStyle(Color.labelTertiary).frame(maxWidth: .infinity)
        }
    }
}

/// A square album tile for horizontal carousels (New tab Top Albums).
private struct AlbumSquareTile: View {
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let art = album.artwork {
                    ArtworkImage(art, width: 150, height: 150)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.surfaceOverlay).frame(width: 150, height: 150)
                        .overlay(Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(Color.labelTertiary))
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 4) {
                Text(album.title).font(.mtrxCaptionBold).foregroundStyle(Color.labelPrimary).lineLimit(1)
                if album.contentRating == .explicit { MusicExplicitBadge() }
            }
            .frame(width: 150, alignment: .leading)
            Text(album.artistName).font(.mtrxCaption2).foregroundStyle(Color.labelSecondary).lineLimit(1).frame(width: 150, alignment: .leading)
        }
    }
}

// MARK: - Radio tab (honest genre stations — real shuffled catalog queues)

struct MusicRadioTab: View {
    let openNowPlaying: () -> Void
    let onClose: () -> Void

    @State private var music = MusicKitManager.shared

    private let columns = [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)]

    var body: some View {
        MusicTabScaffold(title: "Radio", openNowPlaying: openNowPlaying, onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    topStation
                    stationsGrid
                    note
                    MusicAttributionFooter()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }
        }
    }

    private var topStation: some View {
        Button {
            Task { await music.playStation(term: "top hits"); openNowPlaying() }
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color.accentPrimary, Color(red: 0.36, green: 0.16, blue: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 60, weight: .semibold)).foregroundStyle(.white.opacity(0.2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(Spacing.md)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MTRX RADIO").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.85))
                    Text("Today's Hits Station").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Text("A nonstop shuffle of the top catalog").font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                .padding(Spacing.md)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var stationsGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Stations by Genre")
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach(MusicGenre.all) { genre in
                    Button {
                        Task { await music.playStation(term: genre.term); openNowPlaying() }
                    } label: {
                        GenreTile(genre: genre, subtitle: "Station", glyph: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var note: some View {
        Text("Stations play a live shuffle of Apple Music catalog content. Full playback needs an Apple Music subscription; otherwise you'll hear 30-second previews.")
            .font(.mtrxCaption1).foregroundStyle(Color.labelTertiary)
            .multilineTextAlignment(.leading)
    }
}

#endif
