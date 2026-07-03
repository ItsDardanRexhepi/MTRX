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
    private var poll: Timer?
    private var ignoreEchoUntil = Date.distantPast

    init() {
        // MPVolumeView doesn't clip its own slider, so its thumb leaks onto the
        // screen as a faint oval that tracks the volume. Clip it to its 1×1
        // footprint and blank the thumb image so nothing renders — it still
        // writes the system volume through the in-hierarchy slider (see set()).
        mpView.clipsToBounds = true
        mpView.setVolumeThumbImage(UIImage(), for: .normal)
        // Activate a MIXING session so `outputVolume` KVO delivers hardware
        // volume-button presses into the UI LIVE — the key is `.mixWithOthers`:
        // it coexists with the Apple Music player (which plays through the
        // system music service, a separate session) instead of grabbing audio
        // focus. Grabbing focus is what paused playback before; mixing never
        // interrupts, ducks, or takes over Now Playing. We play no audio through
        // this session — it exists only to observe the system volume. Without an
        // active session, `outputVolume` KVO never fires, so the phone's buttons
        // and our rocker would never sync.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        level = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, let v = change.newValue else { return }
            DispatchQueue.main.async {
                if Date() > self.ignoreEchoUntil { self.level = v }   // ignore our own writes
            }
        }
        // A fast backstop for the rare press the KVO coalesces away, so the
        // rocker never lags the hardware by more than a blink.
        poll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let v = AVAudioSession.sharedInstance().outputVolume
            if Date() > self.ignoreEchoUntil, abs(v - self.level) > 0.0005 { self.level = v }
        }
    }

    deinit {
        poll?.invalidate()
        // Do NOT deactivate the session here. AVAudioSession is a process-wide
        // singleton that MusicKit's player shares — deactivating it when the
        // Now Playing sheet closes would pause the very music that should keep
        // playing in the mini player. The mixing category we set is harmless to
        // leave in place; the KVO observer tears itself down when this object
        // is released.
    }

    /// The MPVolumeView's writable UISlider. On current iOS it is NOT a direct
    /// subview (it sits a level or two down), so a flat `subviews` scan finds
    /// nothing and the write silently no-ops — the exact "slider moves but the
    /// phone's volume doesn't" bug. Search the whole subtree.
    private func systemSlider(in view: UIView) -> UISlider? {
        for sub in view.subviews {
            if let slider = sub as? UISlider { return slider }
            if let nested = systemSlider(in: sub) { return nested }
        }
        return nil
    }

    func set(_ v: Float) {
        level = v
        ignoreEchoUntil = Date().addingTimeInterval(0.3)
        // Write on the next runloop tick: MPVolumeView ignores writes that land
        // before its internal slider has attached to the system volume service.
        DispatchQueue.main.async { [weak self] in
            guard let self, let slider = self.systemSlider(in: self.mpView) else { return }
            slider.value = v   // the in-hierarchy MPVolumeView slider drives the SYSTEM volume
            // UISlider programmatic writes don't fire valueChanged; MPVolumeView
            // listens for it to commit the system volume on some iOS versions.
            slider.sendActions(for: .valueChanged)
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
    @StateObject private var volume = SystemVolume()
    @Environment(\.dismiss) private var dismiss
#if canImport(MusicKit)
    // The current track's album/artist, resolved eagerly so the "Go to Album" /
    // "Go to Artist" menu only offers what actually exists — never a dead-end tap.
    @State private var resolvedAlbum: Album?
    @State private var resolvedArtist: Artist?
    // The tapped destination, presented as a detail sheet.
    @State private var goToAlbum: Album?
    @State private var goToArtist: Artist?
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
        .task(id: music.currentSong?.id) { await resolveDestinations() }
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
            // Favorite (love) the current track — a real, persisted toggle that
            // works on every build, independent of subscription or library writes.
            Button { toggleFavorite() } label: {
                circleIcon(isFavorited ? "star.fill" : "star",
                           tint: isFavorited ? Color.accentPrimary : Color.labelPrimary)
            }
            .disabled(music.currentSong == nil)
            .accessibilityLabel(isFavorited ? "Remove from Favorites" : "Favorite")
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
            if let album = resolvedAlbum {
                Button { goToAlbum = album } label: { Label(albumMenuTitle, systemImage: "square.stack") }
            }
            if let artist = resolvedArtist {
                Button { goToArtist = artist } label: { Label(artistMenuTitle, systemImage: "music.mic") }
            }
        } label: {
            titleArtist
        }
        .disabled(resolvedAlbum == nil && resolvedArtist == nil)
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
        resolvedAlbum.map { "Go to Album · \($0.title)" } ?? "Go to Album"
    }
    private var artistMenuTitle: String {
        resolvedArtist.map { "Go to Artist · \($0.name)" } ?? "Go to Artist"
    }

    /// Resolve the current track's album + artist whenever the track changes, so the
    /// menu only ever offers destinations that actually exist (no dead-end taps).
    private func resolveDestinations() async {
        resolvedAlbum = nil
        resolvedArtist = nil
        guard let song = music.currentSong else { return }
        let (album, artist) = await music.albumAndArtist(of: song)
        resolvedAlbum = album
        resolvedArtist = artist
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
            // Keep Apple Music attribution visible even in preview mode — the whole
            // lockup doubles as the Subscribe affordance.
            Button { showSubscriptionOffer = true } label: {
                HStack(spacing: 5) {
                    AppleMusicBadge()
                    Text("· Subscribe").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
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
        Task { _ = await music.addToLibrary(song) }
#endif
    }

    /// Whether the current track is one of the user's favorites (loved).
    private var isFavorited: Bool {
#if canImport(MusicKit)
        return music.isFavorite(music.currentSong)
#else
        return false
#endif
    }

    private func toggleFavorite() {
        MtrxHaptics.impact(.light)
#if canImport(MusicKit)
        guard let song = music.currentSong else { return }
        _ = music.toggleFavorite(song)
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
