// MusicPlayerView.swift
// MTRX — Apple Music player (MusicKit)
//
// MTRX's own player over MusicKit — a familiar now-playing layout (large
// artwork, scrubber, prev/play-pause/next, repeat, shuffle, up-next queue)
// styled with MTRX's design system. Per Apple Music Identity Guidelines it is
// clearly MTRX's player with Apple Music attribution, not a copy of the Apple
// Music app. Every state is honest (see MusicKitManager).

import SwiftUI
import Observation
import MediaPlayer   // MPVolumeView — writes the system volume behind the SwiftUI slider
import AVKit         // AVRoutePickerView — AirPlay / output-route selection
import Combine       // ObservableObject for the system-volume bridge
#if canImport(MusicKit)
import MusicKit
#endif

// MARK: - Apple Music attribution lockup (single-line, never wraps)

/// Apple Music attribution: the Apple logo glyph + "Music", per the product owner's
/// design decision — build 186 displayed it this way and that is the desired presentation.
struct AppleMusicBadge: View {
    var body: some View {
        // Two text runs on one baseline. The glyph is a touch smaller than the word
        // and gets a small upward baseline offset — a bare inline Apple logo renders
        // slightly large and low — leaving it optically centred with "Music"
        // everywhere the badge appears (toolbar, Home card, now-playing, attribution).
        (
            Text("\(Image(systemName: "applelogo"))")
                .font(.system(size: 11, weight: .semibold)).baselineOffset(1.0)
            + Text(" Music").font(.system(size: 13, weight: .semibold))
        )
        .fixedSize()
        .foregroundStyle(Color.labelSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Music")
    }
}

// MARK: - System volume + AirPlay (UIKit bridges)

/// A real system-output volume slider. Wraps `MPVolumeView`, so it reflects and
/// drives the SAME volume the hardware buttons control — exactly how any music
/// player behaves. (Renders empty in the Simulator; live on a device.)
/// Reads + writes the system output volume. The VISIBLE control is a plain SwiftUI
/// Slider (so the layout can never be forced off-screen the way an in-flow MPVolumeView
/// was); a 1×1 off-screen MPVolumeView, hosted via `HiddenVolumeHost`, is used only to
/// write the value, and KVO on the audio session reflects the hardware buttons live.
final class SystemVolume: ObservableObject {
    @Published var level: Float = AVAudioSession.sharedInstance().outputVolume
    let mpView = MPVolumeView(frame: .zero)
    private var observation: NSKeyValueObservation?
    private var ignoreEchoUntil = Date.distantPast

    init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, let v = change.newValue else { return }
            DispatchQueue.main.async {
                if Date() > self.ignoreEchoUntil { self.level = v }   // ignore our own writes
            }
        }
    }

    func set(_ v: Float) {
        level = v
        ignoreEchoUntil = Date().addingTimeInterval(0.3)
        if let slider = mpView.subviews.compactMap({ $0 as? UISlider }).first {
            slider.value = v   // an in-hierarchy MPVolumeView slider drives the system volume
        }
    }
}

/// Hosts the 1×1 off-screen MPVolumeView so its slider can write the system volume.
struct HiddenVolumeHost: UIViewRepresentable {
    let view: MPVolumeView
    func makeUIView(context: Context) -> MPVolumeView { view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MPVolumeView, context: Context) -> CGSize? {
        CGSize(width: 1, height: 1)
    }
}

/// The AirPlay / output-route button — send playback to AirPods, a HomePod,
/// AirPlay speakers, etc., just like the Apple Music now-playing screen.
struct AirPlayRoutePicker: UIViewRepresentable {
    var tint: UIColor = UIColor(Color.labelSecondary)
    var activeTint: UIColor = UIColor(Color.accentPrimary)
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = tint
        v.activeTintColor = activeTint
        v.prioritizesVideoDevices = false
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
    // Pin to a fixed size so the UIKit view can never widen the controls row.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AVRoutePickerView, context: Context) -> CGSize? {
        CGSize(width: 28, height: 28)
    }
}

// MARK: - Lyrics (honest placeholder until a licensed provider is wired)

/// Lyrics aren't exposed by MusicKit's public API, and reproducing licensed lyric
/// text would be a copyright problem — so until a licensed lyrics provider is wired
/// up, this surfaces an honest, never-faked state instead of inventing words.
struct LyricsView: View {
    let title: String?
    let artist: String?
    @Environment(\.dismiss) private var dismiss

    private var unavailableMessage: String {
        let track = title.map { "\u{201C}\($0)\u{201D}" } ?? "this track"
        let by = artist.map { " by \($0)" } ?? ""
        return "Time-synced lyrics need a licensed lyrics provider. Once one is connected, \(track)\(by) will scroll here in time with the music."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)
                VStack(spacing: Spacing.md) {
                    Spacer()
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 46, weight: .light)).foregroundStyle(Color.labelTertiary)
                    Text("Lyrics aren't available yet")
                        .font(.mtrxTitle3.weight(.bold)).foregroundStyle(Color.labelPrimary)
                    Text(unavailableMessage)
                        .font(.mtrxBody).foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, Spacing.xl)
                    Spacer()
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { AppleMusicBadge() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: Symbols.close).accessibilityLabel("Close")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.labelPrimary)
                    }
                }
            }
        }
    }
}

private func mmss(_ t: TimeInterval) -> String {
    guard t.isFinite, t >= 0 else { return "0:00" }
    let s = Int(t.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Home widget card (matches the Portfolio card styling)

struct HomeMusicWidget: View {
    @State private var music = MusicKitManager.shared
    let onOpen: () -> Void

    var body: some View {
        Button {
            MtrxHaptics.impact(.light)
            onOpen()
        } label: {
            HStack(spacing: Spacing.md) {
                artworkOrNote
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    titleView
                    HStack(spacing: 6) {
                        Text(secondaryText)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                        if music.isPreviewPlayback {
                            Text("Preview")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.accentPrimary.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                }

                Spacer(minLength: Spacing.sm)

                if music.hasNowPlaying {
                    // Inline play/pause — a separate tap target from the card.
                    Button {
                        MtrxHaptics.impact(.light)
                        music.togglePlayPause()
                    } label: {
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                } else {
                    // The Apple Music brand now lives in the card's title (the logo
                    // lockup), so the trailing chip is just the disclosure chevron.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(Spacing.ms)
            .background(Color.trinityPrimary.opacity(0.035))
            .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.trinityPrimary.opacity(0.35), Color.trinityPrimary.opacity(0.06)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.trinityPrimary.opacity(0.08), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Apple Music player")
    }

    @ViewBuilder private var artworkOrNote: some View {
#if canImport(MusicKit)
        if music.hasNowPlaying, let art = music.nowPlayingArtwork {
            ArtworkImage(art, width: 48, height: 48)
        } else { noteIcon }
#else
        noteIcon
#endif
    }

    private var noteIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.surfaceOverlay)
            Image(systemName: music.isPlaying ? "waveform" : "music.note")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentPrimary)
                .symbolEffect(.variableColor, isActive: music.isPlaying)
        }
    }

    /// The card title: the song title when one is playing, otherwise the Apple Music
    /// LOGO lockup (the glyph + word) rather than the plain words "Apple Music".
    @ViewBuilder private var titleView: some View {
        if music.nowPlayingTitle != nil {
            Text(primaryText)
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
        } else {
            (Text("\(Image(systemName: "applelogo"))")
                .font(.system(size: 15, weight: .semibold)).baselineOffset(1)
             + Text(" Music").font(.system(size: 17, weight: .semibold)))
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
        }
    }

    private var primaryText: String {
        if let t = music.nowPlayingTitle { return t }
        return music.isConnected ? "Apple Music" : "Music"
    }
    private var secondaryText: String {
        if let a = music.nowPlayingArtist { return a }
        switch music.state {
        case .notConnected: return "Tap to connect Apple Music"
        case .denied:       return "Not connected"
        case .connectedFull: return "Browse and play"
        case .connectedPreview: return "Connected · previews"
        case .unavailable:  return "Unavailable"
        }
    }
}

// MARK: - Player sheet (browse list + mini player)

struct MusicPlayerView: View {
    @State private var music = MusicKitManager.shared
    @State private var showNowPlaying = false
    @State private var showSubscriptionOffer = false
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: Symbols.close)
                            .accessibilityLabel("Close")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary)
                    }
                }
            }
        }
        .onAppear { music.refreshState() }
        .sheet(isPresented: $showNowPlaying) { NowPlayingView() }
    }

    @ViewBuilder
    private var content: some View {
        switch music.state {
        case .notConnected: connectState
        case .denied:       deniedState
        case .unavailable:  unavailableState
        case .connectedFull, .connectedPreview:
            VStack(spacing: 0) {
                if music.state == .connectedPreview { previewNotice }
                browseList
                if music.hasNowPlaying { miniPlayer }
            }
        }
    }

    // MARK: Honest states

    private var connectState: some View {
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
    }

    private var deniedState: some View {
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
    }

    private var unavailableState: some View {
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

    private var previewNotice: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "info.circle")
            Text("30-second previews. Subscribe to Apple Music for full songs.").font(.mtrxCaption1)
            Spacer()
            Button("Subscribe") { showSubscriptionOffer = true }.font(.mtrxCaptionBold).foregroundStyle(Color.accentPrimary)
        }
        .foregroundStyle(Color.labelSecondary)
        .padding(Spacing.sm).background(Color.surfaceOverlay)
#if canImport(MusicKit)
        .musicSubscriptionOffer(isPresented: $showSubscriptionOffer)
#endif
    }

#if canImport(MusicKit)
    private var browseList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                searchEntry
                librarySection
                Divider().padding(.vertical, Spacing.sm)
                chartSection
            }
            .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm).padding(.bottom, Spacing.lg)
        }
    }

    /// Search-bar-styled entry that pushes the Apple Music catalog search screen
    /// (find → play, or add to library). Reuses the same MusicKitManager.
    private var searchEntry: some View {
        NavigationLink { MusicSearchView() } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.labelSecondary)
                Text("Search Apple Music").font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            .mtrxLiquidGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, Spacing.xs)
        .accessibilityLabel("Search Apple Music")
        .accessibilityHint("Find songs, albums, artists and playlists to play or add")
    }

    /// The user's saved Apple Music content, surfaced as categories that push
    /// into dedicated browse screens. Independent of the catalog chart below.
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Your Library")
            ForEach(LibraryCategory.allCases) { category in
                NavigationLink { category.destination } label: {
                    MusicLibraryCategoryRow(category: category)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        sectionHeader("Top Songs")
        if music.chart.isEmpty {
            Group {
                switch music.chartLoad {
                case .loading, .idle: Text("Loading top songs…").foregroundStyle(Color.labelTertiary)
                case .failed: Text("Couldn't load Apple Music content. The app's MusicKit capability may not be enabled yet.")
                    .foregroundStyle(Color.labelSecondary).multilineTextAlignment(.center)
                case .loaded: Text("No songs available right now.").foregroundStyle(Color.labelTertiary)
                }
            }
            .font(.mtrxCallout).frame(maxWidth: .infinity).padding(.top, Spacing.lg)
        } else {
            ForEach(music.chart) { song in
                Button { Task { await music.play(song) } } label: {
                    SongRow(song: song, isCurrent: music.currentSong?.id == song.id, isPlaying: music.isPlaying)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ t: String) -> some View {
        HStack {
            Text(t).font(.mtrxTitle3).foregroundStyle(Color.labelPrimary)
            Spacer()
        }
        .padding(.bottom, Spacing.xs)
    }

    /// Tap to expand into the full Now Playing screen.
    private var miniPlayer: some View {
        Button { showNowPlaying = true } label: {
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
                Spacer()
                Button { music.skipPrevious() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.labelPrimary)
                        .accessibilityLabel("Previous")
                }
                .buttonStyle(.plain)
                .padding(.trailing, Spacing.sm)
                Button { music.togglePlayPause() } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.labelPrimary)
                        .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                }
                .buttonStyle(.plain)
                Button { music.skipNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.labelPrimary)
                        .accessibilityLabel("Next")
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.sm)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            // Floating pill: fully rounded on all four corners (was top-rounded only, which
            // left the bottom corners square and read as clipped), and lifted off the bottom
            // edge below so the home indicator never cuts it off.
            .mtrxLiquidGlass(in: RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full player")
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }
#else
    private var browseList: some View { unavailableState }
    private var miniPlayer: some View { EmptyView() }
#endif
}

// MARK: - Song row

#if canImport(MusicKit)
struct SongRow: View {
    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let artwork = song.artwork {
                ArtworkImage(artwork, width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.surfaceOverlay).frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.mtrxCallout).foregroundStyle(isCurrent ? Color.accentPrimary : Color.labelPrimary).lineLimit(1)
                Text(song.artistName).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary).lineLimit(1)
            }
            Spacer()
            if isCurrent && isPlaying {
                Image(systemName: "waveform").foregroundStyle(Color.accentPrimary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(song.title) by \(song.artistName)")
        .accessibilityHint("Plays the song")
    }
}
#endif

// MARK: - Full Now Playing screen

struct NowPlayingView: View {
    @State private var music = MusicKitManager.shared
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showSubscriptionOffer = false
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var addedToLibrary = false
    @StateObject private var volume = SystemVolume()
    @Environment(\.dismiss) private var dismiss
#if canImport(MusicKit)
    // "Go to Album" / "Go to Artist" destinations, presented as detail sheets.
    @State private var goToAlbum: Album?
    @State private var goToArtist: Artist?
    @State private var loadingDestination = false
    private enum GoDestination { case album, artist }
#endif

    // Responsive square that always leaves room for every control row below it.
    private var artworkSize: CGFloat { min(UIScreen.main.bounds.width - 110, 300) }
    private var displayedTime: TimeInterval { isScrubbing ? scrubValue : music.currentTime }

    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .primary)
            // Every row is pure SwiftUI and only as wide as the padded content area —
            // nothing can push the layout past the screen. Sized to fit; never scrolls.
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.sm)
                artwork
                Spacer(minLength: 0)
                trackInfoRow.padding(.top, Spacing.md)
                scrubber.padding(.top, Spacing.md)
                transport.padding(.vertical, Spacing.xs)
                volumeRow
                bottomToolbar.padding(.top, Spacing.md)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showQueue) { QueueListView() }
        .sheet(isPresented: $showLyrics) {
            LyricsView(title: music.nowPlayingTitle, artist: music.nowPlayingArtist)
        }
#if canImport(MusicKit)
        .sheet(item: $goToAlbum) { album in
            NavigationStack { LibraryDetailView(source: .album(album)) }
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $goToArtist) { artist in
            NavigationStack { LibraryArtistDetailView(artist: artist) }
                .presentationDragIndicator(.visible)
        }
        .musicSubscriptionOffer(isPresented: $showSubscriptionOffer)
#endif
    }

    // MARK: Artwork — shrinks when paused, like Apple Music
    private var artwork: some View {
        Group {
#if canImport(MusicKit)
            if let art = music.nowPlayingArtwork {
                ArtworkImage(art, width: artworkSize, height: artworkSize)
            } else { artworkPlaceholder }
#else
            artworkPlaceholder
#endif
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        .scaleEffect(music.isPlaying ? 1.0 : 0.82)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: music.isPlaying)
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.surfaceOverlay)
            Image(systemName: "music.note").font(.system(size: 64)).foregroundStyle(Color.labelTertiary)
        }
    }

    // MARK: Title + explicit + artist, with Favorite (star) and More (…)
    private var trackInfoRow: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            titleArtistMenu
            Spacer(minLength: Spacing.sm)
            Button { addCurrentToLibrary() } label: {
                circleIcon(addedToLibrary ? "star.fill" : "star",
                           tint: addedToLibrary ? Color.accentPrimary : Color.labelPrimary)
            }
            .accessibilityLabel(addedToLibrary ? "Added to Library" : "Add to Library")
            Menu {
                Button { addCurrentToLibrary() } label: { Label("Add to Library", systemImage: "plus") }
                Button { showQueue = true } label: { Label("View Up Next", systemImage: "list.bullet") }
                Button { showLyrics = true } label: { Label("Lyrics", systemImage: "quote.bubble") }
            } label: {
                circleIcon("ellipsis", tint: Color.labelPrimary)
            }
            .accessibilityLabel("More")
        }
    }

    /// Tapping the title/artist opens the "Go to Album" / "Go to Artist" menu
    /// (just like the Apple Music now-playing screen), which pushes a real detail
    /// screen for the current track's album or artist.
    @ViewBuilder private var titleArtistMenu: some View {
#if canImport(MusicKit)
        Menu {
            Button { goTo(.album) } label: {
                Label(albumMenuTitle, systemImage: "square.stack")
            }
            Button { goTo(.artist) } label: {
                Label(artistMenuTitle, systemImage: "music.mic")
            }
        } label: {
            titleArtist
        }
        .disabled(music.currentSong == nil)
#else
        titleArtist
#endif
    }

    private var titleArtist: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(music.nowPlayingTitle ?? "Not playing")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(Color.labelPrimary).lineLimit(1)
                if isExplicit { explicitBadge }
            }
            Text(music.nowPlayingArtist ?? "")
                .font(.system(size: 20)).foregroundStyle(Color.labelSecondary).lineLimit(1)
        }
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
    }

#if canImport(MusicKit)
    private var albumMenuTitle: String {
        music.currentSong?.albumTitle.map { "Go to Album · \($0)" } ?? "Go to Album"
    }
    private var artistMenuTitle: String {
        music.nowPlayingArtist.map { "Go to Artist · \($0)" } ?? "Go to Artist"
    }

    private func goTo(_ which: GoDestination) {
        guard let song = music.currentSong else { return }
        MtrxHaptics.impact(.light)
        loadingDestination = true
        Task {
            let (album, artist) = await music.albumAndArtist(of: song)
            loadingDestination = false
            switch which {
            case .album:  goToAlbum = album
            case .artist: goToArtist = artist
            }
        }
    }
#endif

    private var explicitBadge: some View {
        Text("E")
            .font(.system(size: 10, weight: .heavy)).foregroundStyle(Color.labelSecondary)
            .frame(width: 17, height: 17)
            .background(Color.labelQuaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var isExplicit: Bool {
#if canImport(MusicKit)
        return music.currentSong?.contentRating == .explicit
#else
        return false
#endif
    }

    private func circleIcon(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(Color.labelQuaternary.opacity(0.25), in: Circle())
    }

    // MARK: Scrubber + elapsed / attribution / remaining
    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { displayedTime }, set: { scrubValue = $0 }),
                in: 0...max(music.duration, 1),
                onEditingChanged: { editing in
                    if editing { scrubValue = music.currentTime; isScrubbing = true }
                    else { music.seek(to: scrubValue); isScrubbing = false }
                }
            )
            .tint(Color.labelSecondary)
            HStack {
                Text(mmss(displayedTime))
                Spacer()
                scrubberCenter
                Spacer()
                Text("-" + mmss(max(music.duration - displayedTime, 0)))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.labelTertiary)
        }
    }

    @ViewBuilder
    private var scrubberCenter: some View {
        if music.isPreviewPlayback {
            Button { showSubscriptionOffer = true } label: {
                Text("Preview · Subscribe").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentPrimary)
            }
        } else {
            AppleMusicBadge()
        }
    }

    // MARK: Transport — previous · play/pause · next
    private var transport: some View {
        HStack {
            Spacer()
            transportButton("backward.fill", size: 32, label: "Previous") { music.skipPrevious() }
            Spacer()
            Button { MtrxHaptics.impact(.medium); music.togglePlayPause() } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 50, weight: .medium)).foregroundStyle(Color.labelPrimary)
                    .frame(width: 72, height: 72)
                    .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
            }
            Spacer()
            transportButton("forward.fill", size: 32, label: "Next") { music.skipNext() }
            Spacer()
        }
    }

    private func transportButton(_ name: String, size: CGFloat, label: String, _ action: @escaping () -> Void) -> some View {
        Button { MtrxHaptics.impact(.light); action() } label: {
            Image(systemName: name)
                .font(.system(size: size, weight: .medium)).foregroundStyle(Color.labelPrimary)
                .frame(width: 60, height: 60)
                .accessibilityLabel(label)
        }
    }

    // MARK: Volume — system slider; the MPVolumeView that writes the volume is hosted
    // off-layout (1×1 background) so it can never affect sizing.
    private var volumeRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "speaker.fill").font(.system(size: 13)).foregroundStyle(Color.labelTertiary)
            Slider(value: Binding(get: { Double(volume.level) }, set: { volume.set(Float($0)) }), in: 0...1)
                .tint(Color.labelSecondary)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 13)).foregroundStyle(Color.labelTertiary)
        }
        .background(
            HiddenVolumeHost(view: volume.mpView)
                .frame(width: 1, height: 1).opacity(0.02).allowsHitTesting(false)
        )
    }

    // MARK: Bottom toolbar — lyrics · airplay · shuffle · repeat · up-next
    private var bottomToolbar: some View {
        HStack {
            toolbarButton("quote.bubble", active: false, label: "Lyrics") { showLyrics = true }
            Spacer()
            AirPlayRoutePicker().frame(width: 26, height: 26).accessibilityLabel("AirPlay")
            Spacer()
            toolbarButton("shuffle", active: music.shuffleOn,
                          label: music.shuffleOn ? "Shuffle on" : "Shuffle off") { music.toggleShuffle() }
            Spacer()
            toolbarButton(music.repeatMode == .one ? "repeat.1" : "repeat",
                          active: music.repeatMode != .off, label: "Repeat") { music.cycleRepeat() }
            Spacer()
            toolbarButton("list.bullet", active: false, label: "Up next") { showQueue = true }
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func toolbarButton(_ icon: String, active: Bool, label: String, _ action: @escaping () -> Void) -> some View {
        Button { MtrxHaptics.impact(.light); action() } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(active ? Color.accentPrimary : Color.labelSecondary)
                .frame(width: 44, height: 34)
                .accessibilityLabel(label)
        }
    }

    private func addCurrentToLibrary() {
        MtrxHaptics.impact(.light)
#if canImport(MusicKit)
        guard let song = music.currentSong else { return }
        Task {
            if case .added = await music.addToLibrary(song) { addedToLibrary = true }
        }
#endif
    }
}

// MARK: - Up Next queue

struct QueueListView: View {
    @State private var music = MusicKitManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)
#if canImport(MusicKit)
                ScrollView {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(Array(music.queueSongs.enumerated()), id: \.offset) { index, song in
                            Button { music.jump(to: index) } label: {
                                SongRow(song: song, isCurrent: index == music.currentIndex, isPlaying: music.isPlaying)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                }
#endif
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { AppleMusicBadge() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: Symbols.close).accessibilityLabel("Close")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.labelPrimary)
                    }
                }
            }
        }
    }
}
