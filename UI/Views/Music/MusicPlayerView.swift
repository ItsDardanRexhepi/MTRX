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
#if canImport(MusicKit)
import MusicKit
#endif

// MARK: - Apple Music attribution lockup (single-line, never wraps)

struct AppleMusicBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "applelogo").font(.system(size: 11, weight: .semibold))
            Text("Music").font(.system(size: 12, weight: .semibold))
        }
        .fixedSize()
        .foregroundStyle(Color.labelSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Music")
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
                    Text(primaryText)
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
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
                    AppleMusicBadge()
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
                librarySection
                Divider().padding(.vertical, Spacing.sm)
                chartSection
            }
            .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm).padding(.bottom, Spacing.lg)
        }
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
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full player")
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
    @State private var showSubscriptionOffer = false
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @Environment(\.dismiss) private var dismiss

    private var artworkSize: CGFloat { min(UIScreen.main.bounds.width - 96, 330) }

    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .primary)
            VStack(spacing: Spacing.lg) {
                grabber
                Spacer(minLength: 0)
                artwork
                trackInfo
                scrubber
                transport
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
        }
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showQueue) { QueueListView() }
#if canImport(MusicKit)
        .musicSubscriptionOffer(isPresented: $showSubscriptionOffer)
#endif
    }

    private var grabber: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.labelSecondary).accessibilityLabel("Minimize")
            }
            Spacer()
            AppleMusicBadge()
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.labelSecondary).accessibilityLabel("Up next")
            }
        }
    }

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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        .scaleEffect(music.isPlaying ? 1.0 : 0.85)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: music.isPlaying)
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.surfaceOverlay)
            Image(systemName: "music.note").font(.system(size: 64)).foregroundStyle(Color.labelTertiary)
        }
    }

    private var trackInfo: some View {
        VStack(spacing: 4) {
            Text(music.nowPlayingTitle ?? "Not playing")
                .font(.mtrxTitle3.weight(.bold)).foregroundStyle(Color.labelPrimary).lineLimit(1)
            Text(music.nowPlayingArtist ?? "")
                .font(.mtrxBody).foregroundStyle(Color.accentPrimary).lineLimit(1)
            if music.isPreviewPlayback {
                Button { showSubscriptionOffer = true } label: {
                    Text("Preview · Subscribe for full songs")
                        .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var displayedTime: TimeInterval { isScrubbing ? scrubValue : music.currentTime }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(music.duration, 1),
                onEditingChanged: { editing in
                    if editing { scrubValue = music.currentTime; isScrubbing = true }
                    else { music.seek(to: scrubValue); isScrubbing = false }
                }
            )
            .tint(Color.accentPrimary)
            HStack {
                Text(mmss(displayedTime))
                Spacer()
                Text("-" + mmss(max(music.duration - displayedTime, 0)))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.labelTertiary)
        }
    }

    private var transport: some View {
        HStack {
            transportButton(music.shuffleOn ? "shuffle" : "shuffle", active: music.shuffleOn, size: 20,
                            label: music.shuffleOn ? "Shuffle on" : "Shuffle off") { music.toggleShuffle() }
            Spacer()
            transportButton("backward.fill", size: 28, label: "Previous") { music.skipPrevious() }
            Spacer()
            Button { MtrxHaptics.impact(.medium); music.togglePlayPause() } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44, weight: .medium)).foregroundStyle(Color.labelPrimary)
                    .frame(width: 64, height: 64)
                    .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
            }
            Spacer()
            transportButton("forward.fill", size: 28, label: "Next") { music.skipNext() }
            Spacer()
            transportButton(music.repeatMode == .one ? "repeat.1" : "repeat",
                            active: music.repeatMode != .off, size: 20, label: repeatLabel) { music.cycleRepeat() }
        }
    }

    private var repeatLabel: String {
        switch music.repeatMode {
        case .off: return "Repeat off"
        case .all: return "Repeat all"
        case .one: return "Repeat one"
        }
    }

    private func transportButton(_ name: String, active: Bool = false, size: CGFloat, label: String, _ action: @escaping () -> Void) -> some View {
        Button { MtrxHaptics.impact(.light); action() } label: {
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? Color.accentPrimary : Color.labelPrimary)
                .frame(width: 44, height: 44)
                .accessibilityLabel(label)
        }
    }

    private var bottomBar: some View {
        HStack {
            AppleMusicBadge()
            Spacer()
            Button { music.stop(); dismiss() } label: {
                Text("Stop").font(.mtrxCaption1).foregroundStyle(Color.labelTertiary)
            }
        }
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
